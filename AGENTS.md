# Agent instructions for GR Lab

GR Lab talks to Ricoh GR cameras over a protocol that was reverse-engineered, not documented by Ricoh. Most bugs show up only on real hardware. These rules exist so that a log from a tester's phone is enough to see what happened.

## Layout

| Path | Role |
|---|---|
| `packages/gr_protocol` | Wire format and protocol primitives in pure Dart: BLE catalog and codecs, HTTP client, change WebSocket, live view, session, tracing types |
| `packages/gr_camera` | The camera layer: the only code that talks to cameras or to the phone's Bluetooth and Wi-Fi. Platform adapters, native Wi-Fi code, session lifecycle, pairing, scanning, Library, Shoot and live view |
| `packages/gr_fake_camera` | Simulated GR IV for tests and demo mode |
| `app` | Flutter UI: widgets, navigation, presentation state, app data, saving to the photo library |
| `tool/check.sh` | Every code-quality check; see below |
| `research` | Protocol research: how each route and characteristic was found, firmware evidence, hardware results, what is still unknown. `research/README.md` indexes it |

## Research

`research/` is the record of what the camera does and how we know it. The code cites it (for example `research/protocol/remote-shooting.md §4.2`).

- Read the relevant file before changing protocol behaviour.
- Update it in the same change whenever you discover something new or notice drift: the camera, a firmware version or Ricoh's apps behaving differently from what the notes say, or the code relying on behaviour the notes don't describe. Correct the wrong text rather than appending a contradiction, and say what was seen, on which body and firmware, and when.
- Mark every fact as observed (on hardware, with date, body and firmware), found in code (with its source), inferred or unknown, as the files already do.
- Paths such as `firmware/evidence/…`, `work/…` and `apk/…` refer to the local research workspace (`../gr`), which holds Ricoh's APKs, their decompilation and the extracted firmware. Those are Ricoh's copyrighted files: never add them, or large excerpts of decompiled code, to this repository.
- Keep personal data out: no Wi-Fi passphrases, no home network names, no serial numbers, Bluetooth or Wi-Fi addresses of a particular camera or phone (use a synthetic serial such as `1234567` and mask addresses, `F0:3E:05:xx:xx:xx`), no keys or tokens taken from Ricoh's apps.

## Camera layer

- UI code never talks to a camera. Widgets and their view-models call `package:gr_camera/gr_camera.dart`, and nothing else in `app/lib` imports `gr_protocol`, `universal_ble`, `gr_camera/src/` or the native Wi-Fi channel.
- Only `app/lib/src/demo` may use `gr_fake_camera`, to build the demo environment.
- New camera behaviour (a route, a characteristic, a retry, a timing rule) goes into `gr_camera` or `gr_protocol`, with an API the UI calls. If the UI needs something the layer does not offer, add it to the layer.
- `tool/check_boundary.sh` enforces the import rules.

## Log every exchange with the camera

Many routes and characteristics were reverse-engineered, so what the camera actually sends is the evidence. Log more rather than less.

- Every exchange with a camera, or with the phone's Bluetooth and Wi-Fi stack on behalf of one, goes to the `TraceSink` as a `TraceEvent`: what was sent and what came back, in full.
  - BLE: scans and every advertisement, connects, discovery, every read, write, subscription and notification with UUIDs and bytes, disconnects and errors.
  - HTTP: method, URL, headers and full body of every request; status, headers and full body of every JSON or text response; content type, length and headers of binary responses; timing and errors.
  - WebSocket: every message in both directions, open, close and errors.
  - Live view: request, response headers, and each frame's number, size and dimensions.
  - Wi-Fi: every platform call with its arguments and result, every native event, and the native code's log lines.
  - Session and UI-level camera decisions (why a retry happened, why a setting was locked) as `session` events.
- New code that talks to the camera adds its tracing in the same change. Never use `print` or `debugPrint` for camera traffic.
- Other diagnostic output uses `print`/`debugPrint` in Dart, or the plugin's `log` in Kotlin and Swift: all of it goes to the debug log and only while "Enable debug logging" is on. Don't add a second logging path.
- Debug logging is on by default in the `dev` build and off in `prod`, where Settings can turn it on and export the log. The log holds the camera's Wi-Fi passphrase; that is intended for diagnosis.

## Checks

Run `tool/check.sh` before considering any change done. It runs the formatter, the analyzer with `very_good_analysis` on every package (infos are fatal), the camera layer boundary check and every test suite. The Android and iOS builds run `tool/check.sh --static` and refuse to build when it fails.

- Every check must pass, whether or not a finding looks important. Fix the code, not the check.
- Do not disable a lint, add `// ignore`, relax `analysis_options.yaml`, skip a test or bypass the build gate to get past a finding. An escape hatch is a last resort, for a finding that cannot be fixed (for example a false positive or a third-party API you cannot change). It must be as narrow as possible (one line, one rule) and carry a comment saying why.
- Kotlin and Swift warnings are errors too.

## Builds

- Flavors: `dev` (application ID `io.jeph.grlab.dev`, "GR Lab Dev") and `prod` (`io.jeph.grlab`, "GR Lab"). `flutter run` and `flutter build` without `--flavor` build `dev`.
- Demo mode: `--dart-define=GR_DEMO=true` runs against the simulated camera.

## Tests

- Behaviour changes come with tests against the simulated camera. Extend `gr_fake_camera` when the real camera does something it cannot yet simulate.
- Break the change on purpose and confirm a test fails before trusting it.
- Hardware findings (what a GR IV did on a given date and firmware) go into `research/`, marked as observed; guesses are marked as inferred.
- In doc comments, protocol facts that are not established carry an evidence tag with escaped brackets, `\[inferred\]`, `\[unknown\]` or `\[design\]` (our choice, not the camera's), so `comment_references` does not read them as code references. Do not state a meaning `research/` or the code does not support.
