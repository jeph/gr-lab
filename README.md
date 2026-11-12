<p align="center">
  <img src="docs/icon.png" alt="GR Photo icon" width="128" height="128">
</p>

<h1 align="center">GR Photo</h1>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platforms: iOS and Android">
</p>

<p align="center">
  <b>English</b> ·
  <a href="docs/readme/README.fr.md">Français</a> ·
  <a href="docs/readme/README.de.md">Deutsch</a> ·
  <a href="docs/readme/README.es.md">Español</a> ·
  <a href="docs/readme/README.pt.md">Português</a> ·
  <a href="docs/readme/README.it.md">Italiano</a> ·
  <a href="docs/readme/README.nl.md">Nederlands</a> ·
  <a href="docs/readme/README.da.md">Dansk</a> ·
  <a href="docs/readme/README.sv.md">Svenska</a> ·
  <a href="docs/readme/README.fi.md">Suomi</a> ·
  <a href="docs/readme/README.pl.md">Polski</a> ·
  <a href="docs/readme/README.cs.md">Čeština</a> ·
  <a href="docs/readme/README.hu.md">Magyar</a> ·
  <a href="docs/readme/README.tr.md">Türkçe</a> ·
  <a href="docs/readme/README.el.md">Ελληνικά</a> ·
  <a href="docs/readme/README.ru.md">Русский</a> ·
  <a href="docs/readme/README.th.md">ไทย</a> ·
  <a href="docs/readme/README.ko.md">한국어</a> ·
  <a href="docs/readme/README.zh.md">中文简体</a> ·
  <a href="docs/readme/README.zh-Hant.md">中文繁體</a> ·
  <a href="docs/readme/README.ja.md">日本語</a>
</p>

**GR Photo** is a companion app for Ricoh GR cameras (GR III, GR IIIx and GR IV) on iOS and Android.
It browses and downloads the photos on your camera, works as a remote shutter with live view, and
keeps your Image Control looks in one place. It is built to be fast and easy to use, and to manage
the camera's colour profiles properly: save the look a photo was taken with, edit it against a
preview, and load it into the camera's Custom slots.

GR Photo is an independent project and is not affiliated with Ricoh. It talks to the camera with a
protocol that was reverse-engineered from Ricoh's own apps and the camera firmware; the findings are
written up in [`research/`](research/README.md).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/library-dark.png">
    <img src="docs/screenshots/library-light.png" alt="The Library: the camera's photos by day, with filters for JPEG, RAW and video" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/looks-dark.png">
    <img src="docs/screenshots/looks-light.png" alt="The Looks page: the camera's three Custom slots above the looks saved on the phone" height="400">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/look-editor-dark.png">
    <img src="docs/screenshots/look-editor-light.png" alt="The look editor: a before and after preview above the Image Control sliders" height="400">
  </picture>
  <img src="docs/screenshots/live-view.png" alt="Live view: the camera's picture with exposure readouts and the shutter" height="400">
</p>

<p align="center">
  <sub>Library, Looks, the look editor and live view, in demo mode with the simulated camera.</sub>
</p>

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Development](#development)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)
- [License](#license)

## Features

GR Photo puts three things first: getting to your photos quickly, staying out of your way, and
treating Image Control looks as something worth managing.

- **Fast.** GR Photo links to your camera over Bluetooth when it opens, if the camera is nearby.
  Opening the Library wakes the camera, turns on its Wi-Fi and joins it in one go, and the Wi-Fi
  then stays up while you move between pages, so nothing joins twice and a download carries on. File
  lists, thumbnails and previews are cached on the phone so the Library opens quickly. On a GR IV HDF
  with an Android phone, a switched-off camera reached its Library in about 13 seconds.
- **Easy to use.** One screen holds your cameras, and Library, Shoot and Looks are one tap from it.
  GR Photo turns the camera on, switches on its Wi-Fi and joins it for you, so there is nothing to
  set on the camera after pairing. When something fails, it says why and what to check, with Try
  again. A link that drops comes back by itself.
- **Looks you can manage.** Every photo in the Library shows the Image Control it was taken with,
  and one tap saves that as a look. Looks live on your phone, whichever camera they came from, with
  their settings, the photo they came from and a tag for the Custom slot that holds them.
- **A look editor with a preview.** Change the base image and every parameter it has, grouped as
  Tone, Colour, Detail and Effects, and see the result on your own photo or a sample: slide a
  divider across before and after, put them side by side, or tap to swap. The preview approximates
  the camera's rendering, worked out from its firmware
  ([`research/image-control-processing.md`](research/image-control-processing.md)).
- **Load looks into the camera.** The Looks page shows what the camera's Custom slots C1 to C3 hold.
  Drag a saved look onto a slot, or pick Load from its menu, and the camera has it. Reading and
  loading the slots works over Bluetooth alone, without joining the camera's Wi-Fi.
- **Library.** Browse the camera's photos and videos by day, filter by JPEG, RAW, video or not yet
  downloaded, and open any shot full screen with its details. Download one shot or a selection, as
  JPEG, RAW or both, into a GR Photo album in your phone's photo library. Downloads carry on while
  you use another app or lock the phone: Android shows them in a notification with Pause and Cancel
  all, and iOS 26 or later shows their progress on the Lock Screen and in the Dynamic Island. Videos
  play in the app.
- **Remote shutter.** A large shutter button over Bluetooth alone, with the self-timer, the drive
  mode, the mode dial, shots left and battery. On Android the volume buttons fire the shutter too.
- **Live view.** The camera's picture over Wi-Fi: tap to focus, set aperture, shutter speed, ISO and
  exposure compensation on a dial of the values the camera offers, and change drive, self-timer,
  metering and Image Control.
- **Geotagging.** GR cameras have no GPS. With Geotagging on for a camera, GR Photo sends your
  phone's location to it over Bluetooth while the camera is on, and the camera saves it in each
  photo. It carries on while you use another app or lock the phone, starts by itself when you
  switch the camera on if you allow location all the time, and keeps the camera's clock on your
  phone's time. Background geotagging is the hands-free alternative: the phone keeps a 90-day
  history of where it has been, and GR Photo adds the place recorded closest to the time a photo
  was taken when you download it, to JPEG and RAW files alike.
- **Several cameras.** Pair as many as you own and switch between them; rename or forget each one.
- **Themes and languages.** Light, Dark, Darkroom, Paper and Cyanotype themes, and the 21 languages
  of the camera's own menus.
- **Private.** No accounts, analytics, advertising or crash reporting. GR Photo talks only to your
  camera, and your location goes only to your camera and into your own photos; see the
  [privacy policy](app/assets/privacy.md).

## Requirements

- A Ricoh GR III, GR IIIx or GR IV, including the HDF bodies and the GR IV Monochrome.
- Looks need a GR IV on firmware 1.04 or later, a GR IV HDF or a GR IV Monochrome. The GR III and
  GR IIIx firmware offers no way to read or write Image Control settings from a phone.
- Android 12 or newer, or iOS 15 or newer.

GR Photo is young. The hardware log records runs with a GR IV HDF on firmware 1.20: pairing,
connecting, waking the camera, browsing, downloading, live view, focus and exposure changes. GR III
and GR IIIx support comes from the protocol research and has not been tested on a camera yet. See
[`research/hardware-validation.md`](research/hardware-validation.md) for what has been observed.

## Installation

On Android, download `gr-photo-v<version>.apk` from the
[latest release](https://github.com/jeph/gr-photo/releases/latest) on your phone and open it.
Android asks once for permission to install apps from your browser. Every release is signed with the
same key, so a newer one installs over the one you have and keeps your cameras and settings.

On iOS, every release goes to TestFlight, for now only to the project's own testers. There is no
public TestFlight link yet, so on an iPhone GR Photo is installed by building it from source.

Building from source needs [Flutter](https://flutter.dev) 3.47 or newer with the Android SDK or
Xcode set up.

```sh
git clone https://github.com/jeph/gr-photo.git
cd gr-photo/app
flutter run --flavor prod --release
```

`flutter run` installs on the phone that is connected to your computer. iOS builds need your own
signing team with the Hotspot Configuration and Access Wi-Fi Information capabilities. An Android
build from source is signed with your computer's debug key, not the release key, so Android installs
neither over the other: uninstall the one you have first.

To try the app without a camera, run it in demo mode, which uses a simulated GR IV with sample
photos and works on the Android emulator and the iOS simulator:

```sh
flutter run --dart-define=GR_DEMO=true
```

## Usage

1. **Pair your camera.** Tap Add a camera and follow the guide. On the camera, pairing is under
   MENU, Wireless Connection, Wireless Communication: set Action Mode to On, open Pairing and choose
   Execute Pairing, then confirm the code on the phone and press OK on the camera. The camera is
   then on the Cameras screen, and GR Photo links to it by itself when it opens with the camera
   nearby.
2. **Open the Library.** GR Photo turns the camera on if it is off and joins its Wi-Fi. Android asks
   you to approve the camera's network once. Tap a shot to view it, press and hold to select
   several, and download what you want to keep.
3. **Shoot.** Remote is a shutter over Bluetooth. Live view joins the camera's Wi-Fi and shows its
   picture, with focus and exposure controls.
4. **Save a look.** Open a photo in the Library and tap Save look, or make one from scratch with +
   on the Looks page. Tap a look to edit it, and drag it onto C1, C2 or C3 to load it into the
   camera.
5. **Add locations.** GR Photo offers Geotagging once for each camera; you can also turn it on
   later with ⋯ on the camera's card. Your phone asks whether GR Photo may use its location. From
   then on the location is sent whenever the camera is on and in reach. Background geotagging is
   under Settings, Location, and needs location allowed all the time.

Auto-disconnect in Settings leaves the camera's Wi-Fi after GR Photo has gone unused for a while (5
minutes by default). [How GR Photo behaves](docs/behaviour.md) describes each screen and every
connection state in detail.

## Development

### Layout

| Path | Contents |
|---|---|
| `packages/gr_protocol` | BLE GATT, Wi-Fi HTTP API, change WebSocket and the connect/recover session, in pure Dart |
| `packages/gr_camera` | The camera layer the app calls for everything camera-related: Bluetooth and Wi-Fi adapters (with the Kotlin and Swift Wi-Fi joining code), session, pairing, scanning, Library, Shoot and live view, and tracing of every exchange |
| `packages/gr_fake_camera` | Simulated GR IV (BLE, Wi-Fi join, HTTP server on loopback) for tests and demo mode |
| `app` | The Flutter app, with Kotlin and Swift code for saving to the photo library |
| `research` | Protocol research: how each route and characteristic was found, firmware evidence, hardware results, open questions |
| `tool` | `check.sh`, every code-quality check; the scripts that build, sign and upload a release; `testflight.sh`, an iOS upload from a Mac |

### Running

```sh
cd app
flutter run                                  # dev build, real camera (needs a phone with Bluetooth)
flutter run --profile                        # the same, at the speed of a release build
flutter run --flavor prod --release          # the build users get
flutter run --dart-define=GR_DEMO=true       # simulated camera, works on the Android emulator and iOS simulator
```

There are two builds. `dev` (`io.jeph.grphoto.dev`, named "GR Photo Dev") installs beside `prod`
(`io.jeph.grphoto`, "GR Photo"). Without `--flavor`, `flutter run` and `flutter build` build `dev`.

`flutter run` alone makes a debug build, which builds each frame several times slower than a profile
or release build (3 to 4 times in the Library on an Android emulator, 2026-11-10). Judge how smooth a
screen is with `--profile` or `--release`.

Demo mode keeps its data in a separate `demo/` folder. On first launch, Add a camera finds the
simulated camera and it confirms pairing by itself; later launches start with the camera off, which
stays off until you open the Library (waking it is part of joining its Wi-Fi) or press the card's
power button. Demo RAW files are JPEG bytes with a `.DNG` name.

### Checks

```sh
tool/check.sh            # formatter, analyzer, camera layer boundary, translations, all test suites
tool/check.sh --static   # without the tests
```

The analyzer uses `very_good_analysis` with infos treated as errors. Android and iOS builds run
`tool/check.sh --static` first and stop if it fails. Kotlin and Swift warnings are errors. See
[`AGENTS.md`](AGENTS.md) for the rules.

### Tests

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

The integration test runs the whole demo flow (pair, connect, browse, download two shots) on a
device, emulator or simulator. A debug build needs about 400 MB free on the emulator. On Android,
`flutter test` takes neither the default flavor nor the app's ID from the project, so it needs
`--flavor dev` and an APK built beforehand; without them it stops with "No application found".

On the iOS simulator, the app must be installed when Photos access is granted, and `flutter test`
uninstalls it afterwards, which deletes the grant. GR Photo asks for full access, to keep its album,
and on the iOS 26.3 simulator `simctl privacy grant photos` alone did not stop iOS from asking: the
grant it records has `auth_version` 1, and iOS takes it as full access only at 2. Grant it and set
that before every run:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos io.jeph.grphoto.dev
sqlite3 "$(xcrun simctl getenv booted HOME)/Library/TCC/TCC.db" \
  "UPDATE access SET auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = 'io.jeph.grphoto.dev'"
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

### Debug log

GR Photo keeps debug logs while Settings > Enable debug logging is on: everything it sends to and
receives from the camera (Bluetooth scans, reads, writes and notifications, every HTTP request and
answer, WebSocket messages, live-view frame sizes, and the Wi-Fi joining steps), every line the app
prints, uncaught errors, and the native Wi-Fi code's lines. The setting is on by default in `dev`
and off in `prod`. While it is off nothing is logged, not even to logcat or the console, with one
exception: the Flutter engine still reports uncaught errors there itself, so crashes stay visible.
Settings > Debug log exports the log through the share sheet as JSON Lines files and clears it. The
log keeps about 50 MB. It contains the camera's Wi-Fi password.

### Releases

Every push to `main` is a release, made by
[`.github/workflows/release.yml`](.github/workflows/release.yml). It numbers the release 0.0.N, one
more than the last, runs `tool/check.sh`, and builds the `prod` flavor of both apps in release mode.
The Android APK is signed with GR Photo's release key and published on the
[releases page](https://github.com/jeph/gr-photo/releases) with its SHA-256 checksum, a build
provenance attestation and the R8 mapping that reads its Kotlin stack traces. The iOS app is signed
for the App Store and uploaded to TestFlight. The keys are kept in GitHub environments that only
`main` can use, and the jobs that build the apps hold none of them.

`gh attestation verify gr-photo-v<version>.apk --repo jeph/gr-photo` checks that an APK was built by
that workflow from this repository.

```sh
tool/testflight.sh       # builds the prod iOS app and uploads it to TestFlight
```

The script puts a build that is not a release on TestFlight from a Mac. It builds the `prod` flavor
with the upload's time as its build number and sends it to App Store Connect, where it appears under
TestFlight once processed. Internal testers install it from the TestFlight app, without a cable.
Xcode signs and uploads the build with an App Store Connect API
key, so the setup on a Mac is the key's `AuthKey_<key id>.p8` file in
`~/.appstoreconnect/private_keys`, and `ASC_KEY_ID` and `ASC_ISSUER_ID` in
`~/.appstoreconnect/gr-photo.env`. The key needs the Admin role: Apple doesn't let an App Manager
key use the team's distribution certificate. The archive is built unsigned and signed for the App
Store on export (`app/ios/ExportOptions.plist`), because signing the archive itself would need a
registered test device on the team.

## Contributing

Bug reports and pull requests are welcome. Most bugs show up only on real hardware, so when you
[open an issue](https://github.com/jeph/gr-photo/issues), please include your camera model and
firmware version, your phone model and its Android or iOS version, and what you did. An exported
debug log (Settings, Debug log, Export log) usually shows what happened, but it contains your
camera's serial number and Wi-Fi password, so attach it only if you are comfortable sharing those.

Before sending a change, run `tool/check.sh`; every check has to pass. [`AGENTS.md`](AGENTS.md)
describes how the code is organised and the rules it follows.

Do not report suspected security vulnerabilities in public issues. Follow the
[security policy](.github/SECURITY.md) to submit a private vulnerability report.

## Acknowledgements

GR Photo is built with [Flutter](https://flutter.dev) and uses
[universal_ble](https://pub.dev/packages/universal_ble) for Bluetooth,
[image](https://pub.dev/packages/image), [video_player](https://pub.dev/packages/video_player),
[share_plus](https://pub.dev/packages/share_plus) and
[path_provider](https://pub.dev/packages/path_provider). Its text is set in
[Inter](https://rsms.me/inter/) and [JetBrains Mono](https://www.jetbrains.com/lp/mono/).

The protocol research rests on Ricoh's GR WORLD and Image Sync apps and the GR firmware, and on the
[Ricoh3x](https://github.com/Trimz/Ricoh3x) project's notes on the GR IIIx's Image Control settings.

## License

GR Photo is released under the [MIT License](LICENSE). Third-party packages and fonts that GR Photo
includes keep their own licenses. The app lists them under **Settings › About › Licenses**, and the
fonts' license texts are in [`app/assets/fonts/`](app/assets/fonts/).

The demo mode's sample photos are from [Unsplash](https://unsplash.com) and are used under the
[Unsplash License](https://unsplash.com/license), not the MIT License;
[`app/assets/photo-credits.txt`](app/assets/photo-credits.txt) lists them and their photographers.

Ricoh's apps and firmware, which the research cites, belong to Ricoh and are not part of this
repository.
