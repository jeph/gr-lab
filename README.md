# GR Lab

Companion app for Ricoh GR cameras (GR III, GR IIIx, GR IV) on iOS and Android, built with Flutter on a pure-Dart protocol package. The protocol was reverse-engineered from Ricoh's GR WORLD and Image Sync apps and the camera firmware; the findings are in [`research/`](research/README.md).

Current scope: pairing cameras over Bluetooth and keeping several of them on a Cameras screen (switch, rename, forget), connecting (Bluetooth first, waking the camera and joining its Wi-Fi when the Library opens), browsing the photos and videos on the camera, viewing them, downloading them to the phone's photo library, and shooting (a Bluetooth remote, and live view over Wi-Fi). Image Control, location sync, firmware update and Ricoh account services are not implemented.

The app opens on the Cameras screen. With a camera paired, the one used last is on a card with a line drawing of the camera, an icon for its link, a power button and large Library, Shoot and Looks buttons, and the app links to it over Bluetooth by itself if it is nearby when the app opens; other cameras are listed below it. The icon is a crossed-out Bluetooth sign while the camera is not linked (brighter when it is nearby), pulses while Bluetooth is being linked and turns green once it is; from the moment the camera's Wi-Fi is being joined it is a Wi-Fi sign instead, pulsing until the Wi-Fi is up and green after. While Bluetooth is being linked, Cancel takes the place of the three buttons, which fade back in once the link is up. Linking over Bluetooth never turns a camera on. The power button turns the camera on or off over Bluetooth the way GR WORLD's does, linking it first when needed; a camera turned on with it stays on when GR Lab leaves it, and one turned off with it stays linked over Bluetooth. The card's Library, Shoot and Looks buttons open the camera's pages on that page; a floating tab bar at the bottom of the pages switches between them. The pages slide in over the Cameras screen. The camera's Wi-Fi is joined only for the Library and for live view, and opening either turns the camera on first if it is off. While joining, the page lists two steps, Bluetooth and Wi-Fi; if joining fails, it says why and what to check, with Try again. Joining takes a while, so once the Wi-Fi is up it stays up when you move to a page that does not need it or go back to the Cameras screen, whose card then shows the Wi-Fi icon in green: the Library and live view open without joining again, and a download carries on. Auto-disconnect (below) or Disconnect Wi-Fi in the camera sheet leaves the Wi-Fi, with Bluetooth still linked. Going back while the Wi-Fi is still being joined stops the join. A camera GR Lab turned on for a page is turned back off when you go back from the camera's pages or, if its Wi-Fi stayed up, when the Wi-Fi is left on the Cameras screen. If the Wi-Fi is lost while it is in use (the Library or live view is open, or a download, movie copy or playback is running), the page stays and the app gets it back by itself, shown as reconnecting; a camera switched off at its power button shows a red "Camera off" pill and is turned back on over Bluetooth. If the Wi-Fi does not come back, the app returns to the Cameras screen with Bluetooth still linked and a note on the card; if the camera is gone with its Bluetooth too (switched fully off, or out of range), it returns there saying the connection was lost. If the Wi-Fi is lost while nothing uses it, GR Lab lets it go without a word instead, and a camera switched off then stays off. On Android the loss is noticed as soon as the phone reports it; elsewhere, when the camera stops answering a Library request or its liveness polling. One camera is connected at a time.

A Bluetooth link that drops is linked again by itself, shown as reconnecting on the camera's pages and by the pulsing icon on the card. While only Bluetooth linked the camera, also when the Library or live view was opened meanwhile and is waiting for that link, one that is not back after 40 seconds counts as gone (switched fully off, or out of range): the app returns to the Cameras screen saying the connection was lost. The saved looks on the home dock stay in front when that happens while they are shown.

Shoot opens in the mode used last, Remote the first time. Remote works over Bluetooth alone: it turns the camera on in shooting mode (or switches a camera in playback to shooting), shows the mode dial, shots left and battery, and has a large shutter, the self-timer (off, 2 s, 10 s) and the drive mode. A running self-timer turns the shutter into a countdown ring; tapping it cancels. On Android the volume buttons fire the shutter too. Live view joins the camera's Wi-Fi and shows the camera's picture, dark and without the tab bar: tapping the picture focuses there, the aperture, shutter, ISO and EV readouts open a dial of the values the camera offers in its current mode, and the chips change the drive, self-timer, metering and Image Control. The picture is shown whole and as large as the window allows, on phones, foldables and tablets alike; the controls go above and below it, or beside it in a window as short as a phone on its side, and lie over its edges where the window leaves them no room of their own. Switching back to Remote (or ×) keeps the camera on and its Wi-Fi up, so live view starts at once the next time; it only stops a join that is still under way.

Auto-disconnect (Settings: 1, 5, 10 or 15 minutes, or Never; 5 by default) leaves the camera's Wi-Fi when GR Lab has not been used for that long, whichever screen is showing. With the Library or live view open it returns to the Cameras screen, the same way as Disconnect Wi-Fi; Shoot's Remote and Looks stay open on Bluetooth; and on the Cameras screen, which says the Wi-Fi was left, a camera GR Lab turned on is turned back off. Touches, scrolls, key presses and moving between screens count as use, and so does a running download, movie copy, movie playback or live view. Time with the app in the background counts towards the limit. With Never, the Wi-Fi stays up until Disconnect Wi-Fi, the power button or switching cameras ends it.

On Android, the first Wi-Fi join of each camera is explained before Android's own network list asks you to approve it. Android shows that list again for an approved camera after its network was disconnected by hand in Wi-Fi settings. When that happens, a short message names the network to choose, and if the join fails, GR Lab explains why the list came back and offers Try again.

Joining is timed around the camera's access point, which comes up a varying time after its Wi-Fi is turned on. When the camera is off, GR Lab turns its Wi-Fi on right after waking it instead of first waiting 8 seconds to see whether the wake drops the Bluetooth link. If that early write fails, it waits for the link as before; if it goes through and the join is still looking for the network 8 seconds after the wake, GR Lab turns the Wi-Fi on once more (linking again first if the link dropped). On Android, Android looks for the network when asked and then only every 10-20 seconds, so for an approved camera GR Lab asks again every 7 seconds until Android starts connecting. It does not ask again while Android's network list is open, or on phones that join camera networks on a second Wi-Fi connection.

## Layout

| Path | Contents |
|---|---|
| `packages/gr_protocol` | BLE GATT, Wi-Fi HTTP API, change WebSocket and the connect/recover session, in pure Dart |
| `packages/gr_camera` | The camera layer the app calls for everything camera-related: Bluetooth and Wi-Fi adapters (with the Kotlin and Swift Wi-Fi joining code), session, pairing, scanning, Library, Shoot and live view, and tracing of every exchange |
| `packages/gr_fake_camera` | Simulated GR IV (BLE, Wi-Fi join, HTTP server on loopback) for tests and demo mode |
| `app` | The Flutter app, with Kotlin and Swift code for saving to the photo library |
| `research` | Protocol research: how each route and characteristic was found, firmware evidence, hardware results, open questions |
| `tool` | `check.sh`, every code-quality check |

## Running

```sh
cd app
flutter run                                  # dev build, real camera (needs a phone with Bluetooth)
flutter run --flavor prod --release          # the build users get
flutter run --dart-define=GR_DEMO=true       # simulated camera, works on the Android emulator and iOS simulator
```

There are two builds. `dev` (`io.jeph.grlab.dev`, named "GR Lab Dev") installs beside `prod` (`io.jeph.grlab`, "GR Lab"). Without `--flavor`, `flutter run` and `flutter build` build `dev`.

Demo mode keeps its data in a separate `demo/` folder. On first launch, Add a camera finds the simulated camera and it confirms pairing by itself; later launches start with the camera off, which stays off until you open the Library (waking it is part of joining its Wi-Fi) or press the card's power button. Demo RAW files are JPEG bytes with a `.DNG` name.

### Debug log

GR Lab keeps debug logs while Settings > Enable debug logging is on: everything it sends to and receives from the camera (Bluetooth scans, reads, writes and notifications, every HTTP request and answer, WebSocket messages, live-view frame sizes, and the Wi-Fi joining steps), every line the app prints, uncaught errors, and the native Wi-Fi code's lines. The setting is on by default in `dev` and off in `prod`. While it is off nothing is logged, not even to logcat or the console, with one exception: the Flutter engine still reports uncaught errors there itself, so crashes stay visible. Settings > Debug log exports the log through the share sheet as JSON Lines files and clears it. The log keeps about 50 MB. It contains the camera's Wi-Fi password.

## Checks

```sh
tool/check.sh            # formatter, analyzer, camera layer boundary, all test suites
tool/check.sh --static   # without the tests
```

The analyzer uses `very_good_analysis` with infos treated as errors. Android and iOS builds run `tool/check.sh --static` first and stop if it fails. Kotlin and Swift warnings are errors. See `AGENTS.md` for the rules.

## Tests

```sh
(cd packages/gr_protocol && dart test)
(cd packages/gr_fake_camera && dart test)
(cd packages/gr_camera && flutter test)
(cd app && flutter test)
(cd app && flutter build apk --debug --flavor dev --dart-define=GR_DEMO=true)
(cd app && flutter test integration_test --flavor dev --dart-define=GR_DEMO=true -d <device>)
```

The integration test runs the whole demo flow (pair, connect, browse, download two shots) on a device, emulator or simulator. A debug build needs about 400 MB free on the emulator. On Android, `flutter test` takes neither the default flavor nor the app's ID from the project, so it needs `--flavor dev` and an APK built beforehand; without them it stops with "No application found".

On the iOS simulator, the app must be installed when Photos access is granted, and `flutter test` uninstalls it afterwards, which deletes the grant. Grant it before every run:

```sh
cd app
flutter build ios --simulator --debug --dart-define=GR_DEMO=true
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl privacy booted grant photos-add io.jeph.grlab.dev
flutter test integration_test --dart-define=GR_DEMO=true -d <simulator>
```

## Not verified on hardware yet

Everything above runs against the simulated camera. On a GR IV HDF with an Android phone, pairing, connecting, browsing and downloading worked, and so did waking an off camera and joining its Wi-Fi with Android asked again every 7 seconds (about 13 seconds from waking to the Library in five runs with the camera off, 2-13 seconds in two with it on). Still untested on hardware: Shoot (Remote and live view), the tab bar between the camera's pages, auto-disconnect, the Cameras screen (nearby detection from the advertisement, the automatic connect, switching between two real cameras), the explanation before Android's Wi-Fi approval and whether the approval is then remembered, the message and Try again question when Android's network list comes back for an approved camera, getting the Wi-Fi back in place when it is lost, the red Camera off pill and turning the camera back on after it is switched off, returning to the Cameras screen when the Wi-Fi does not come back or the camera is gone with its Bluetooth, turning the camera back off when leaving the Library, portrait orientation of the camera's thumbnails (based on its per-photo info), the image retries, timeouts and sharper sizes in the Library, iOS hotspot joining, saving RAW+JPEG pairs to Photos, and movie playback from a downloaded file. iOS device builds need the Hotspot Configuration and Access Wi-Fi Information capabilities on the signing team.
