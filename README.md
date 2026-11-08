# GR Lab

Companion app for Ricoh GR cameras (GR III, GR IIIx, GR IV) on iOS and Android, built with Flutter on a pure-Dart protocol package. The protocol was reverse-engineered from Ricoh's GR WORLD app and the camera firmware; the research lives in a separate repository.

Current scope: pairing cameras over Bluetooth and keeping several of them on a Cameras screen (switch, rename, forget), connecting (Bluetooth first, waking the camera and joining its Wi-Fi when the Library opens), browsing the photos and videos on the camera, viewing them, and downloading them to the phone's photo library. Shooting, Image Control, location sync, firmware update and Ricoh account services are not implemented.

The app opens on the Cameras screen. With a camera paired, the one used last is on a card with thumbnails from the last visit, and the app links to it over Bluetooth by itself if it is nearby when the app opens; other cameras are listed below it. Linking over Bluetooth never turns a camera on. The camera's Wi-Fi is joined only when you tap Library on the card, which turns the camera on first if it is off. While connecting, the card lists two steps, Bluetooth and Wi-Fi; if connecting fails, it says why and what to check. Once on Wi-Fi, the Library replaces the Cameras screen. Disconnecting Wi-Fi from the camera sheet returns to the Cameras screen with Bluetooth still linked. So does losing the Wi-Fi, with a note on the card: the app does not rejoin by itself, and tapping Library joins again. On Android the loss is noticed as soon as the phone reports it; elsewhere, when the camera stops answering a Library request or its liveness polling. One camera is connected at a time.

Auto-disconnect (Settings: 1, 5, 10 or 15 minutes, or Never; 5 by default) leaves the camera's Wi-Fi when GR Lab has not been used for that long, the same way as Disconnect Wi-Fi, and the Cameras screen says so. Touches, scrolls, key presses and moving between screens count as use, and so does a running download, movie copy or movie playback. Time with the app in the background counts towards the limit.

On Android, the first Wi-Fi join of each camera is explained before Android's own network list asks you to approve it. Android shows that list again for an approved camera after its network was disconnected by hand in Wi-Fi settings. When that happens, a short message names the network to choose, and if the join fails, GR Lab explains why the list came back and offers Try again.

Joining is timed around the camera's access point, which comes up a varying time after its Wi-Fi is turned on. When the camera is off, GR Lab turns its Wi-Fi on right after waking it instead of first waiting 8 seconds to see whether the wake drops the Bluetooth link. If that early write fails, it waits for the link as before; if it goes through and the join is still looking for the network 8 seconds after the wake, GR Lab turns the Wi-Fi on once more (linking again first if the link dropped). On Android, Android looks for the network when asked and then only every 10-20 seconds, so for an approved camera GR Lab asks again every 7 seconds until Android starts connecting. It does not ask again while Android's network list is open, or on phones that join camera networks on a second Wi-Fi connection.

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

Everything above runs against the simulated camera. On a GR IV HDF with an Android phone, pairing, connecting, browsing and downloading worked, and so did waking an off camera and joining its Wi-Fi with Android asked again every 7 seconds (about 13 seconds from waking to the Library in five runs with the camera off, 2-13 seconds in two with it on). Still untested on hardware: auto-disconnect, the Cameras screen (nearby detection from the advertisement, the automatic connect, switching between two real cameras), the explanation before Android's Wi-Fi approval and whether the approval is then remembered, the message and Try again question when Android's network list comes back for an approved camera, returning to the Cameras screen when the phone leaves the camera's Wi-Fi, portrait orientation of the camera's thumbnails (based on its per-photo info), the image retries, timeouts and sharper sizes in the Library, iOS hotspot joining, saving RAW+JPEG pairs to Photos, and movie playback from a downloaded file. iOS device builds need the Hotspot Configuration and Access Wi-Fi Information capabilities on the signing team.
