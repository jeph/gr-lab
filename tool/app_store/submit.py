#!/usr/bin/env python3
"""Checks a release's What's New and submits its iOS build to Apple's reviews.

  tool/app_store/submit.py check <version>
      Checks that whats_new/<version>/ holds a What's New for each of the app's
      21 languages: one <locale>.txt per language, named like the ARB files,
      not empty and at most 4000 characters, which App Store Connect allows.

  tool/app_store/submit.py submit <version> <build number>
      Waits for App Store Connect to process the uploaded build, then:
      - adds it to the public TestFlight group with the What's New as its
        What to Test, and submits it for beta review;
      - puts it in App Store version <version>, released as soon as Apple
        approves it, with the What's New, and submits it for App Review. A
        version that is waiting for review or in review is taken out of review
        and reused for <version>, so the newest build is the one Apple reviews.
      A second run for the same release picks up where the first one stopped.

.github/workflows/release.yml runs `check` before it builds anything and
`submit` after the upload, in a job that holds the App Store Connect key and
nothing else. `submit` reads the key from the environment, as
tool/upload_testflight.sh does: APP_STORE_CONNECT_API_KEY_P8 (the contents of
its AuthKey_<key id>.p8 file), APP_STORE_CONNECT_API_KEY_ID and
APP_STORE_CONNECT_API_ISSUER_ID. Submitting for review needs a key with the App
Manager or Admin role.

It needs Python 3.10 or newer and the openssl command, which signs the API
tokens, and nothing that has to be installed.
"""

import base64
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "io.jeph.grphoto"
BETA_GROUP = "Public beta"
MAX_WHATS_NEW = 4000

# The app's languages (app/l10n.yaml), named like the ARB files, and the
# App Store localization each one fills.
LOCALES = {
    "en": "en-US",
    "fr": "fr-FR",
    "de": "de-DE",
    "es": "es-ES",
    "pt": "pt-PT",
    "it": "it",
    "nl": "nl-NL",
    "da": "da",
    "sv": "sv",
    "fi": "fi",
    "pl": "pl",
    "cs": "cs",
    "hu": "hu",
    "tr": "tr",
    "el": "el",
    "ru": "ru",
    "th": "th",
    "ko": "ko",
    "zh": "zh-Hans",
    "zh_Hant": "zh-Hant",
    "ja": "ja",
}

# App Store version states (AppVersionState). A version is released or
# replaced in any state not listed here.
EDITABLE = {
    "PREPARE_FOR_SUBMISSION",
    "READY_FOR_REVIEW",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}
UNDER_REVIEW = {"WAITING_FOR_EXPORT_COMPLIANCE", "WAITING_FOR_REVIEW", "IN_REVIEW"}
GOING_LIVE = {"ACCEPTED", "PROCESSING_FOR_DISTRIBUTION"}
HELD = {"PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE"}
OPEN = EDITABLE | UNDER_REVIEW | GOING_LIVE | HELD

# Review submissions that hold a version in review.
SUBMITTED = "WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"

# External TestFlight states in which the build is already submitted.
BETA_SUBMITTED = {
    "WAITING_FOR_BETA_REVIEW",
    "IN_BETA_REVIEW",
    "BETA_APPROVED",
    "IN_BETA_TESTING",
}


def log(message):
    print(message, flush=True)


def whats_new(version):
    """The What's New of [version], by App Store locale."""
    folder = HERE / "whats_new" / version
    texts, problems = {}, []
    for locale, store_locale in LOCALES.items():
        path = folder / f"{locale}.txt"
        if not path.is_file():
            problems.append(f"{path} is missing")
            continue
        text = path.read_text(encoding="utf-8").strip()
        if not text:
            problems.append(f"{path} is empty")
        elif len(text) > MAX_WHATS_NEW:
            problems.append(
                f"{path} has {len(text)} characters, more than {MAX_WHATS_NEW}"
            )
        texts[store_locale] = text
    if folder.is_dir():
        problems += [
            f"{p} is not one of the app's languages"
            for p in sorted(folder.iterdir())
            if p.stem not in LOCALES
        ]
    if problems:
        sys.exit("What's New of " + version + ":\n" + "\n".join(problems))
    return texts


class ApiError(Exception):
    def __init__(self, method, path, status, body):
        super().__init__(f"{method} {path} -> {status}: {body}")
        self.status = status


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _raw_signature(der):
    """The 64-byte r || s an ES256 token carries, from openssl's DER
    SEQUENCE { INTEGER r, INTEGER s } (short-form lengths for P-256)."""
    if der[0] != 0x30:
        raise ValueError("openssl's signature is not a DER sequence")
    parts, i = [], 2
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("openssl's signature is not two DER integers")
        length = der[i + 1]
        parts.append(int.from_bytes(der[i + 2 : i + 2 + length], "big"))
        i += 2 + length
    return b"".join(p.to_bytes(32, "big") for p in parts)


class AppStoreConnect:
    def __init__(self, key_path, key_id, issuer_id):
        self._key_path = key_path
        self._key_id = key_id
        self._issuer_id = issuer_id
        self._token = None
        self._token_time = 0.0

    def _bearer(self):
        # Apple takes tokens valid for up to 20 minutes; a new one is made
        # after 15.
        if self._token is None or time.time() - self._token_time > 15 * 60:
            now = int(time.time())
            header = {"alg": "ES256", "kid": self._key_id, "typ": "JWT"}
            claims = {
                "iss": self._issuer_id,
                "iat": now,
                "exp": now + 20 * 60,
                "aud": "appstoreconnect-v1",
            }
            signed = (
                _b64(json.dumps(header).encode())
                + "."
                + _b64(json.dumps(claims).encode())
            )
            der = subprocess.run(
                ["openssl", "dgst", "-sha256", "-binary", "-sign", self._key_path],
                input=signed.encode(),
                capture_output=True,
                check=True,
            ).stdout
            self._token = signed + "." + _b64(_raw_signature(der))
            self._token_time = now
        return self._token

    def request(self, method, path, body=None):
        request = urllib.request.Request(
            API + path,
            data=None if body is None else json.dumps(body).encode(),
            method=method,
            headers={
                "Authorization": "Bearer " + self._bearer(),
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                text = response.read().decode()
        except urllib.error.HTTPError as error:
            raise ApiError(method, path, error.code, error.read().decode()) from None
        return json.loads(text) if text else None

    def get(self, path):
        return self.request("GET", path)

    def patch(self, kind, identifier, attributes):
        return self.request(
            "PATCH",
            f"/v1/{kind}/{identifier}",
            {"data": {"type": kind, "id": identifier, "attributes": attributes}},
        )

    def post(self, kind, attributes=None, relationships=None):
        data = {"type": kind}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = {
                name: {"data": {"type": t, "id": i}}
                for name, (t, i) in relationships.items()
            }
        return self.request("POST", f"/v1/{kind}", {"data": data})["data"]


def wait_for_build(api, app_id, version, number):
    """The build once App Store Connect has processed it, which takes from a
    few minutes to over an hour."""
    deadline = time.monotonic() + 100 * 60
    while True:
        builds = api.get(
            f"/v1/builds?filter[app]={app_id}&filter[version]={number}"
            f"&filter[preReleaseVersion.version]={version}&filter[preReleaseVersion.platform]=IOS"
        )["data"]
        state = builds[0]["attributes"]["processingState"] if builds else None
        if state == "VALID":
            build = builds[0]
            if build["attributes"]["usesNonExemptEncryption"] is None:
                sys.exit(
                    f"Build {number} has no answer to the encryption question (ITSAppUsesNonExemptEncryption)"
                )
            log(f"Build {version} ({number}) is processed")
            return build
        if state in ("FAILED", "INVALID"):
            sys.exit(f"App Store Connect could not process build {number}: {state}")
        if time.monotonic() > deadline:
            sys.exit(
                f"Build {number} was not processed in time; the last state was {state}"
            )
        log(f"Build {number}: {state or 'not listed yet'}; checking again in 30 s")
        time.sleep(30)


def submit_beta(api, app_id, build, texts):
    groups = api.get(f"/v1/apps/{app_id}/betaGroups?limit=50")["data"]
    group = next(
        (
            g
            for g in groups
            if g["attributes"]["name"] == BETA_GROUP
            and not g["attributes"]["isInternalGroup"]
        ),
        None,
    )
    if group is None:
        sys.exit(f'The app has no external TestFlight group "{BETA_GROUP}"')
    members = api.get(f"/v1/betaGroups/{group['id']}/builds?limit=200")["data"]
    if all(b["id"] != build["id"] for b in members):
        api.request(
            "POST",
            f"/v1/betaGroups/{group['id']}/relationships/builds",
            {"data": [{"type": "builds", "id": build["id"]}]},
        )
        log(f'Added the build to "{BETA_GROUP}"')

    existing = {
        x["attributes"]["locale"]: x["id"]
        for x in api.get(f"/v1/builds/{build['id']}/betaBuildLocalizations?limit=50")[
            "data"
        ]
    }
    for locale, text in texts.items():
        if locale in existing:
            api.patch("betaBuildLocalizations", existing[locale], {"whatsNew": text})
        else:
            api.post(
                "betaBuildLocalizations",
                {"locale": locale, "whatsNew": text},
                {"build": ("builds", build["id"])},
            )
    log(f"Set What to Test in {len(texts)} languages")

    state = api.get(f"/v1/builds/{build['id']}/buildBetaDetail")["data"]["attributes"][
        "externalBuildState"
    ]
    if state in BETA_SUBMITTED:
        log(f"The build is already submitted for beta review: {state}")
        return
    if state != "READY_FOR_BETA_SUBMISSION":
        sys.exit(f"The build cannot be submitted for beta review: {state}")
    api.post(
        "betaAppReviewSubmissions", relationships={"build": ("builds", build["id"])}
    )
    log("Submitted the build for beta review")


def _versions(api, app_id):
    response = api.get(
        f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&include=build&limit=50"
    )
    builds = {}
    for version in response["data"]:
        data = version["relationships"]["build"].get("data")
        builds[version["id"]] = data["id"] if data else None
    return response["data"], builds


def withdraw(api, app_id):
    submissions = api.get(
        f"/v1/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&filter[state]={SUBMITTED}"
    )["data"]
    for submission in submissions:
        api.patch("reviewSubmissions", submission["id"], {"canceled": True})
        log(
            f"Took submission {submission['id']} out of review ({submission['attributes']['state']})"
        )


def open_version(api, app_id, version, build):
    """The App Store version that is to hold [build], or None when [version]
    is already submitted with it or has gone past review."""
    deadline = time.monotonic() + 30 * 60
    withdrawn = False
    while True:
        versions, builds = _versions(api, app_id)
        mine = [v for v in versions if v["attributes"]["versionString"] == version]
        if any(
            v["attributes"]["appVersionState"] not in EDITABLE | UNDER_REVIEW
            for v in mine
        ):
            log(f"Version {version} is already past review")
            return None
        current = [v for v in versions if v["attributes"]["appVersionState"] in OPEN]
        if not current:
            return api.post(
                "appStoreVersions",
                {
                    "platform": "IOS",
                    "versionString": version,
                    "releaseType": "AFTER_APPROVAL",
                },
                {"app": ("apps", app_id), "build": ("builds", build["id"])},
            )
        if len(current) > 1:
            sys.exit(
                "More than one App Store version is open: "
                + ", ".join(v["attributes"]["versionString"] for v in current)
            )
        open_one = current[0]
        name = open_one["attributes"]["versionString"]
        state = open_one["attributes"]["appVersionState"]
        if state in EDITABLE:
            log(f"Reusing version {name} ({state}) for {version}")
            return api.patch(
                "appStoreVersions",
                open_one["id"],
                {"versionString": version, "releaseType": "AFTER_APPROVAL"},
            )["data"]
        if (
            state in UNDER_REVIEW
            and name == version
            and builds[open_one["id"]] == build["id"]
        ):
            log(f"Version {version} is already submitted with this build: {state}")
            return None
        if state in HELD:
            sys.exit(
                f"Version {name} is approved and waits to be released ({state}); release it or remove it from review in App Store Connect"
            )
        if state in UNDER_REVIEW and not withdrawn:
            log(f"Version {name} is {state}; taking it out of review for {version}")
            withdraw(api, app_id)
            withdrawn = True
        elif state in GOING_LIVE:
            log(f"Version {name} is {state}; waiting for it to go live")
        if time.monotonic() > deadline:
            sys.exit(f"Version {name} stayed {state}")
        time.sleep(20)


def fill_version(api, app_id, version_id, build, texts):
    """Attaches [build] and the What's New, and the reviewer's details if the
    version has none."""
    api.request(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )

    localizations = api.get(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50"
    )["data"]
    found = {x["attributes"]["locale"] for x in localizations}
    if found != set(texts):
        sys.exit(
            "The App Store version's languages differ from the app's: "
            f"missing {sorted(set(texts) - found)}, extra {sorted(found - set(texts))}"
        )
    for localization in localizations:
        api.patch(
            "appStoreVersionLocalizations",
            localization["id"],
            {"whatsNew": texts[localization["attributes"]["locale"]]},
        )
    log(f"Set What's New in {len(texts)} languages")

    if _review_detail(api, version_id) is not None:
        return
    # The notes for Apple's reviewer, copied from the newest version that has them.
    versions, _ = _versions(api, app_id)
    for other in sorted(
        versions, key=lambda v: v["attributes"]["createdDate"], reverse=True
    ):
        detail = None if other["id"] == version_id else _review_detail(api, other["id"])
        if detail is not None:
            api.post(
                "appStoreReviewDetails",
                detail["attributes"],
                {"appStoreVersion": ("appStoreVersions", version_id)},
            )
            log(
                f"Copied the details for Apple's reviewer from version {other['attributes']['versionString']}"
            )
            return
    sys.exit("No App Store version has details for Apple's reviewer to copy")


def _review_detail(api, version_id):
    try:
        return api.get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")[
            "data"
        ]
    except ApiError as error:
        if error.status == 404:
            return None
        raise


def submit_review(api, app_id, version_id):
    drafts = api.get(
        f"/v1/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW"
    )["data"]
    if drafts:
        submission_id = drafts[0]["id"]
    else:
        submission_id = api.post(
            "reviewSubmissions", {"platform": "IOS"}, {"app": ("apps", app_id)}
        )["id"]
    items = api.get(
        f"/v1/reviewSubmissions/{submission_id}/items?include=appStoreVersion&limit=50"
    )["data"]
    if all(
        (i["relationships"]["appStoreVersion"].get("data") or {}).get("id")
        != version_id
        for i in items
    ):
        api.post(
            "reviewSubmissionItems",
            relationships={
                "reviewSubmission": ("reviewSubmissions", submission_id),
                "appStoreVersion": ("appStoreVersions", version_id),
            },
        )
    api.patch("reviewSubmissions", submission_id, {"submitted": True})
    for _ in range(12):
        state = api.get(f"/v1/appStoreVersions/{version_id}")["data"]["attributes"][
            "appVersionState"
        ]
        if state in UNDER_REVIEW:
            log(f"Submitted for App Review: {state}")
            return
        time.sleep(10)
    sys.exit(f"The version did not reach review after submitting: {state}")


def submit(version, number):
    texts = whats_new(version)
    for name in (
        "APP_STORE_CONNECT_API_KEY_P8",
        "APP_STORE_CONNECT_API_KEY_ID",
        "APP_STORE_CONNECT_API_ISSUER_ID",
    ):
        if not os.environ.get(name):
            sys.exit(f"{name} is not set")
    with tempfile.TemporaryDirectory() as folder:
        key_path = os.path.join(folder, "key.p8")
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as key:
            key.write(os.environ["APP_STORE_CONNECT_API_KEY_P8"] + "\n")
        api = AppStoreConnect(
            key_path,
            os.environ["APP_STORE_CONNECT_API_KEY_ID"],
            os.environ["APP_STORE_CONNECT_API_ISSUER_ID"],
        )

        apps = api.get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
        if len(apps) != 1:
            sys.exit(
                f"App Store Connect lists {len(apps)} apps with the bundle ID {BUNDLE_ID}"
            )
        app_id = apps[0]["id"]
        build = wait_for_build(api, app_id, version, number)
        submit_beta(api, app_id, build, texts)
        app_store_version = open_version(api, app_id, version, build)
        if app_store_version is not None:
            fill_version(api, app_id, app_store_version["id"], build, texts)
            submit_review(api, app_id, app_store_version["id"])


def main(args):
    if len(args) == 2 and args[0] == "check":
        whats_new(args[1])
        log(f"What's New of {args[1]}: all {len(LOCALES)} languages")
    elif len(args) == 3 and args[0] == "submit":
        submit(args[1], args[2])
    else:
        sys.exit(
            "usage: submit.py check <version> | submit.py submit <version> <build number>"
        )


if __name__ == "__main__":
    main(sys.argv[1:])
