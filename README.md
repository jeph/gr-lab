# GR Lab

Companion app for Ricoh GR cameras (GR III, GR IIIx, GR IV) on iOS and Android, built with Flutter on a pure-Dart protocol package. The protocol was reverse-engineered from Ricoh's GR WORLD app and the camera firmware; the research lives in a separate repository.

Current scope: pairing cameras over Bluetooth and keeping several of them on a Cameras screen (switch, rename, forget), connecting (Bluetooth first, waking the camera and joining its Wi-Fi when the Library opens), browsing the photos and videos on the camera, viewing them, and downloading them to the phone's photo library. Shooting, Image Control, location sync, firmware update and Ricoh account services are not implemented.

The app opens on the Cameras screen. With a camera paired, the one used last is on a card with thumbnails from the last visit, and the app links to it over Bluetooth by itself if it is nearby when the app opens; other cameras are listed below it. The camera's Wi-Fi is joined only when you tap Library on the card. While connecting, the card lists two steps, Bluetooth and Wi-Fi; if connecting fails, it says why and what to check. Once on Wi-Fi, the Library replaces the Cameras screen. Disconnecting Wi-Fi from the camera sheet returns to the Cameras screen with Bluetooth still linked. So does losing the Wi-Fi, with a note on the card: the app does not rejoin by itself, and tapping Library joins again. On Android the loss is noticed as soon as the phone reports it; elsewhere, when the camera stops answering a Library request or its liveness polling. One camera is connected at a time.

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

Demo mode keeps its data in a separate `demo/` folder. On first launch, Add a camera finds the simulated camera and it confirms pairing by itself; later launches start with the camera off, which stays off until you open the Library (waking it is part of joining its Wi-Fi). Demo RAW files are JPEG bytes with a `.DNG` name.

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

Everything above runs against the simulated camera. On a GR IV HDF with an Android phone, pairing, connecting, browsing and downloading worked. Still untested on hardware: the Cameras screen (nearby detection from the advertisement, the automatic connect, switching between two real cameras), the explanation before Android's Wi-Fi approval and whether the approval is then remembered, returning to the Cameras screen when the phone leaves the camera's Wi-Fi, portrait orientation of the camera's thumbnails (based on its per-photo info), the image retries, timeouts and sharper sizes in the Library, iOS hotspot joining, saving RAW+JPEG pairs to Photos, and movie playback from a downloaded file. iOS device builds need the Hotspot Configuration and Access Wi-Fi Information capabilities on the signing team.
