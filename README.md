# GR Lab

Companion app for Ricoh GR cameras (GR III, GR IIIx, GR IV) on iOS and Android, built with Flutter on a pure-Dart protocol package. The protocol was reverse-engineered from Ricoh's GR WORLD app and the camera firmware; the research lives in a separate repository.

Current scope: pairing a camera over Bluetooth, connecting (waking the camera, turning on its Wi-Fi, joining it), browsing the photos and videos on the camera, viewing them, and downloading them to the phone's photo library. Shooting, Image Control, location sync, firmware update and Ricoh account services are not implemented.

## Layout

| Path | Contents |
|---|---|
| `packages/gr_protocol` | BLE GATT, Wi-Fi HTTP API, change WebSocket and the connect/recover session, in pure Dart |
| `packages/gr_fake_camera` | Simulated GR IV (BLE, Wi-Fi join, HTTP server on loopback) for tests and demo mode |
| `app` | The Flutter app (`io.jeph.grlab`), with Kotlin and Swift code for Wi-Fi joining and saving to the photo library |

## Running

```sh
cd app
flutter run                                  # real camera (needs a phone with Bluetooth)
flutter run --dart-define=GR_DEMO=true       # simulated camera, works on the Android emulator and iOS simulator
```

Demo mode keeps its data in a separate `demo/` folder. On first launch the simulated camera is found, paired and confirmed automatically; later launches start with the camera off, so connecting shows the wake step. Demo RAW files are JPEG bytes with a `.DNG` name.

## Tests

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd app && flutter test)
(cd app && flutter test integration_test --dart-define=GR_DEMO=true -d <device>)
```

The integration test runs the whole demo flow (pair, connect, browse, download two shots) on a device, emulator or simulator. A debug build needs about 400 MB free on the emulator.

On the iOS simulator, the app must be installed when Photos access is granted, and `flutter test` uninstalls it afterwards, which deletes the grant. Grant it before every run:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos-add io.jeph.grlab
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

## Not verified on hardware yet

Everything above runs against the simulated camera. On a GR IV HDF with an Android phone, pairing, connecting, browsing and downloading worked. Still untested on hardware: the explanation before Android's Wi-Fi approval and whether the approval is then remembered, rejoining quietly after the phone leaves the camera's Wi-Fi, portrait orientation of the camera's thumbnails (based on its per-photo info), iOS hotspot joining, saving RAW+JPEG pairs to Photos, and movie playback from a downloaded file. iOS device builds need the Hotspot Configuration and Access Wi-Fi Information capabilities on the signing team.
