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

## Branches and worktrees

Several agents work on this repository at once, so make every change in its own git worktree instead of in the main checkout at `~/Developer/gr-lab`. Create the worktree next to the main checkout on a new branch from `dev`, for example `git worktree add ../gr-lab-<branch> -b <branch> dev`, and leave the main checkout on `dev`.

Documentation changes are the exception. Edit Markdown files such as `AGENTS.md`, `README.md` and the files in `research/` directly in the main checkout on `dev`; they don't need a worktree. The exception covers documentation only: changes to the build system or toolchain, such as `pubspec.yaml` files, `analysis_options.yaml`, the Gradle files, the Xcode project, `Package.swift` or `tool/`, go in a worktree like any code change, even though they aren't application logic.

Development is trunk-based: `dev` is the trunk and the repository's default branch, and work reaches it in small, frequent pushes. Always pull `dev` into the worktree before building, with `git fetch origin && git rebase origin/dev`. Resolve any conflicts, and if changes other agents landed on `dev` break yours or don't work with them, fix that in your branch before you build. That way every build you test is the current `dev` plus your work.

Finished work goes directly to `dev`; this project doesn't use pull requests. Once your work is finished and `tool/check.sh` passes, rebase the branch onto `origin/dev` and run `git push origin HEAD:dev` from the worktree. Never push to `main` without the user's explicit approval; `main` only moves when the user asks for `dev` to be promoted to it. Never force push, to any branch, with `--force`, `--force-with-lease` or a `+` refspec. If the push is rejected because `dev` moved, fetch, rebase onto `origin/dev` again, fix any conflicts or breakage, and push again. Worktree branches stay local: never push them under their own names.

Once the push has landed, remove the worktree and its branch. Confirm the work is on `dev` with `git fetch origin && git merge-base --is-ancestor HEAD origin/dev`, then from the main checkout run `git worktree remove ../gr-lab-<branch>` and `git branch -D <branch>`. Finally, bring the main checkout up to date with `git pull --ff-only origin dev`.

## Commits

Write commit messages in the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format: `<type>(<optional scope>): <description>`, for example `fix(wifi): rejoin the camera network after Android drops it`. Use `feat` for new behaviour, `fix` for bug fixes, `docs` for documentation-only changes (including `research/`), and `refactor`, `perf`, `test`, `build`, `ci` or `chore` where they fit. Useful scopes are the areas of the app and the packages: `shoot`, `library`, `pairing`, `connection`, `settings`, `wifi`, `ble`, `protocol`, `camera`, `fake-camera`. Mark breaking changes with `!` after the type or scope and a `BREAKING CHANGE:` footer.

Commits are signed through 1Password, so commit normally first. If 1Password doesn't allow the signature, for example because the request times out or the agent returns an error, commit again without signing using `git -c commit.gpgsign=false commit`. Don't change the repository's or the global Git signing settings to get around it.

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

## Code you touch

Leave code you change better than you found it, and limit the cleanup to that code: don't refactor whole files or unrelated parts of the codebase. Where a change touches a function or block, flatten its nesting where you can, using early returns and guards and reordering conditions so the common path reads straight down, and simplify what's there. Some nesting is unavoidable; keep it when flattening would make the code harder to follow. Rename variables, properties and functions in that code whose names no longer match what they hold or do, or could say it more precisely.

## iOS and Android

GR Lab ships on iOS and Android, and every change has to work on both. A fix or feature aimed at one platform must not break or degrade the other, and shared Dart code must suit both platforms' native paths: for example, Android joins the camera network with a `WifiNetworkSpecifier` request and iOS with an `NEHotspotConfiguration`, and they differ in approval prompts, timing and errors. Keep platform differences inside the platform adapters and native code in `gr_camera`, behind one API for the UI. When one platform can't do what the other does, give it the closest equivalent and say why in the code and in `research/`. Before finishing, check what the change does on the other platform; test it on both where you can, and say in your summary which platforms you verified and which you couldn't.

## Checks

Run `tool/check.sh` before considering any change done. It runs the formatter, the analyzer with `very_good_analysis` on every package and on `tool/` (infos are fatal), the camera layer boundary check, the translated-text check and every test suite. The Android and iOS builds run `tool/check.sh --static` and refuse to build when it fails.

- Every check must pass, whether or not a finding looks important, including failures in code you didn't change: fix them rather than leaving them for later. Fix the code, not the check.
- Do not disable a lint, add `// ignore`, relax `analysis_options.yaml`, add a baseline, skip a test or bypass the build gate to get past a finding. Needing an escape hatch usually means you are taking a shortcut, and avoiding that shortcut is the point of this rule. An escape hatch is a last resort, only when a finding truly cannot be fixed (for example a false positive or a third-party API you cannot change). It must be as narrow as possible (one line, one rule, never a whole file) and carry a comment saying why the rule doesn't fit there.
- Kotlin and Swift warnings are errors too.

## Builds

- Flavors: `dev` (application ID `io.jeph.grlab.dev`, "GR Lab Dev") and `prod` (`io.jeph.grlab`, "GR Lab"). `flutter run` and `flutter build` without `--flavor` build `dev`.
- Demo mode: `--dart-define=GR_DEMO=true` runs against the simulated camera.

## Testing on devices

Most of GR Lab needs a real camera, but demo mode (`--dart-define=GR_DEMO=true`) runs the whole app against the simulated camera on an Android emulator. Several agents work at once, so each worktree gets its own emulator, and agents never share one: installs, app data and taps from one agent would otherwise overwrite or interrupt another's test. Don't install on, drive or shut down an emulator that another worktree or project is using.

Before testing, create an emulator for the worktree, named after its branch, with the Pixel 9 hardware profile and a system image under `~/Library/Android/sdk/system-images`, for example `echo no | avdmanager create avd -n gr-lab-<branch> -d pixel_9 -k "system-images;android-36;google_apis_playstore;arm64-v8a"` (the `echo no` answers its custom hardware profile prompt). Boot it on a free even port with `emulator -avd gr-lab-<branch> -port <port> -memory 4096`, and pass `-s emulator-<port>` to every `adb` command and `-d emulator-<port>` to `flutter` so it can't reach another agent's emulator or the phone. When you remove the worktree, shut the emulator down with `adb -s emulator-<port> emu kill` and delete it with `avdmanager delete avd -n gr-lab-<branch>`.

The user's phone is sometimes reachable over `adb`, and it's the only way to test with the user's camera, but it's their own phone, not a test device. Ask the user before you install a build on it, run commands on it (pulling a log included) or test on it, and do only what they agreed to. Install the `dev` build (`io.jeph.grlab.dev`) unless the user asks for `prod`. Never change settings on the phone, whether in Android, GR Lab or any other app, without asking first.

## Tests

- Behaviour changes come with tests against the simulated camera. Extend `gr_fake_camera` when the real camera does something it cannot yet simulate.
- Break the change on purpose and confirm a test fails before trusting it.
- Hardware findings (what a GR IV did on a given date and firmware) go into `research/`, marked as observed; guesses are marked as inferred.
- In doc comments, protocol facts that are not established carry an evidence tag with escaped brackets, `\[inferred\]`, `\[unknown\]` or `\[design\]` (our choice, not the camera's), so `comment_references` does not read them as code references. Do not state a meaning `research/` or the code does not support.

## Text the user sees

GR Lab is set up for translation, so every text the app itself shows comes from the localized messages in `app/lib/l10n/app_en.arb`: labels, buttons, errors, notices, dialogs and snackbars alike. Read them through `context.l10n` (the generated `AppLocalizations`). Text from the camera, such as its name, file names and setting values, is shown as the camera sends it. The camera layer reports failures as typed values, never as English sentences; the app turns each into a message. Give every message an `@` description, and describe each placeholder. Format numbers, sizes, times and dates with the locale (`intl`'s `NumberFormat` and `DateFormat`), not fixed patterns or English suffixes.

`tool/check_strings.dart` fails when a string literal with words in it goes straight to a widget that shows text (`Text('…')`, `title: '…'`, `tooltip: '…'` and similar) in `app/lib`. It matches common shapes, so passing it doesn't prove a screen is translated. A literal that truly must not be translated, such as the GR Lab brand name, carries `// not-translated: <why>` on the same line; like any escape hatch, it is a last resort.

## Privacy policy

`app/assets/privacy.md` is GR Lab's privacy policy, which Settings › About shows. App stores require it to be accurate, so when you add a feature or change behaviour, check whether the policy still describes what GR Lab does. Update it when a change affects what data GR Lab stores, where it stores it, or what it sends off the phone and to whom, or when GR Lab asks for a new permission or uses one for something new. Examples are a new network request other than to the camera, a new kind of file kept on the phone, a new export or share, or telemetry. When you update the policy, change the date at its top in the same commit.

## Third-party licenses

Before adding a dependency, whether a Dart or Flutter package in a `pubspec.yaml`, a Gradle dependency, or a Swift package, check its license. Don't add copyleft code (GPL, LGPL, AGPL) without asking first, since it would change how GR Lab can be distributed.

When you copy or adapt code, icons or other assets from another project, keep a header in the copied file naming the source, version and license.

The app has to show the license of everything third-party that it ships, in Settings › About › Licenses. Flutter adds the licenses of Dart and Flutter packages itself. Anything else it ships, such as fonts, copied assets, or native libraries from Gradle or Swift packages, needs its license file in `app/assets/` and an entry in the `LicenseRegistry` registration in `app/lib/main.dart`, as the Inter and JetBrains Mono fonts have.
