"""Tests for submit.py's choice of App Store version and TestFlight build,
against a fake App Store Connect. tool/check.sh runs them."""

import itertools
import unittest
from unittest import mock

import submit

BUILD_12 = {"id": "b12", "attributes": {"version": "12"}}


class FakeAppStoreConnect:
    """Answers the reads submit.py makes and records its writes. [states]
    is a list of App Store version lists, (version, state, build id), one per
    read; the last one stays."""

    def __init__(self, states=((),), beta_builds=()):
        self.states = list(states)
        self.beta_builds = beta_builds
        self.writes = []

    def get(self, path):
        if "/appStoreVersions" in path:
            versions = self.states.pop(0) if len(self.states) > 1 else self.states[0]
            return {
                "data": [
                    {
                        "id": "v" + name,
                        "attributes": {"versionString": name, "appVersionState": state},
                        "relationships": {"build": {"data": {"id": build}}},
                    }
                    for name, state, build in versions
                ]
            }
        if "/reviewSubmissions" in path:
            return {
                "data": [
                    {"id": "submission", "attributes": {"state": "WAITING_FOR_REVIEW"}}
                ]
            }
        if path.endswith("/betaGroups?limit=50"):
            return {
                "data": [
                    {
                        "id": "group",
                        "attributes": {
                            "name": submit.BETA_GROUP,
                            "isInternalGroup": False,
                        },
                    }
                ]
            }
        if "/betaGroups/group/builds" in path:
            return {
                "data": [
                    {"id": f"b{n}", "attributes": {"version": str(n)}}
                    for n in self.beta_builds
                ]
            }
        raise AssertionError("unexpected read: " + path)

    def post(self, kind, attributes=None, relationships=None):
        self.writes.append(("post", kind, attributes))
        return {"id": "new"}

    def patch(self, kind, identifier, attributes):
        self.writes.append(("patch", kind, identifier, attributes))
        return {"data": {"id": identifier}}

    def request(self, method, path, body=None):
        self.writes.append((method.lower(), path))
        raise _Stop


class _Stop(Exception):
    """Ends submit_beta at its first write, which is all a test looks at."""


# No waiting, and a clock that moves ten minutes a read, so a wait that
# would never end runs out after a few rounds.
@mock.patch.object(submit.time, "sleep", lambda _: None)
@mock.patch.object(submit.time, "monotonic", itertools.count(step=600).__next__)
class OpenVersionTest(unittest.TestCase):
    def open(self, *states):
        api = FakeAppStoreConnect(states)
        return submit.open_version(api, "app", "0.0.12", BUILD_12), api.writes

    def test_creates_a_version_when_none_is_open(self):
        version, writes = self.open([("0.0.9", "READY_FOR_DISTRIBUTION", "b9")])
        self.assertEqual(version, {"id": "new"})
        self.assertEqual(writes[0][:2], ("post", "appStoreVersions"))
        self.assertEqual(writes[0][2]["releaseType"], "AFTER_APPROVAL")

    def test_reuses_an_older_rejected_version(self):
        version, writes = self.open(
            [
                ("0.0.10", "DEVELOPER_REJECTED", "b10"),
                ("0.0.9", "READY_FOR_DISTRIBUTION", "b9"),
            ]
        )
        self.assertEqual(version, {"id": "v0.0.10"})
        self.assertEqual(
            writes,
            [
                (
                    "patch",
                    "appStoreVersions",
                    "v0.0.10",
                    {"versionString": "0.0.12", "releaseType": "AFTER_APPROVAL"},
                )
            ],
        )

    def test_takes_an_older_version_out_of_review_and_reuses_it(self):
        version, writes = self.open(
            [("0.0.11", "WAITING_FOR_REVIEW", "b11")],
            [("0.0.11", "DEVELOPER_REJECTED", "b11")],
        )
        self.assertEqual(version, {"id": "v0.0.11"})
        self.assertEqual(
            writes[0], ("patch", "reviewSubmissions", "submission", {"canceled": True})
        )
        self.assertEqual(writes[1][:3], ("patch", "appStoreVersions", "v0.0.11"))

    def test_leaves_its_own_submission_in_review(self):
        version, writes = self.open([("0.0.12", "IN_REVIEW", "b12")])
        self.assertIsNone(version)
        self.assertEqual(writes, [])

    def test_a_rerun_leaves_a_newer_version_in_review(self):
        version, writes = self.open(
            [
                ("0.0.13", "WAITING_FOR_REVIEW", "b13"),
                ("0.0.9", "READY_FOR_DISTRIBUTION", "b9"),
            ]
        )
        self.assertIsNone(version)
        self.assertEqual(writes, [])

    def test_a_rerun_leaves_a_newer_rejected_version(self):
        version, writes = self.open([("0.0.13", "DEVELOPER_REJECTED", "b13")])
        self.assertIsNone(version)
        self.assertEqual(writes, [])

    def test_a_rerun_creates_nothing_after_a_newer_release(self):
        version, writes = self.open([("0.0.13", "READY_FOR_DISTRIBUTION", "b13")])
        self.assertIsNone(version)
        self.assertEqual(writes, [])

    def test_compares_versions_as_numbers(self):
        version, writes = self.open([("0.0.9", "PREPARE_FOR_SUBMISSION", "b9")])
        self.assertEqual(version, {"id": "v0.0.9"})
        self.assertEqual(len(writes), 1)


class SubmitBetaTest(unittest.TestCase):
    def test_adds_the_build_to_the_group(self):
        api = FakeAppStoreConnect(beta_builds=[9, 11])
        with self.assertRaises(_Stop):
            submit.submit_beta(api, "app", BUILD_12, {})
        self.assertEqual(
            api.writes, [("post", "/v1/betaGroups/group/relationships/builds")]
        )

    def test_a_rerun_leaves_a_later_build_in_the_group(self):
        api = FakeAppStoreConnect(beta_builds=[9, 13])
        submit.submit_beta(api, "app", BUILD_12, {})
        self.assertEqual(api.writes, [])


if __name__ == "__main__":
    unittest.main()
