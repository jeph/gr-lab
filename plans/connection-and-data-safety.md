# Plan: connection handling and data safety fixes

Source: the code review of `dev` at `6c3213e` (November 2026). Each item below was found by reading the code; none has been reproduced on a GR IV yet. Every fix lands with a test that fails without it (AGENTS.md, "Tests").

Status marks: `[ ]` not started, `[~]` in progress, `[x]` landed on `dev` (commit in brackets), `[-]` dropped (reason given).

The work is split into workstreams so that no two agents edit the same source file at once. Each workstream runs in its own worktree and lands on `dev` by itself. Only the agent coordinating the work updates this file.

## Workstreams

| ID | Area | Owns | Status |
|---|---|---|---|
| W1 | Protocol session and change socket | `packages/gr_protocol/lib/src/session/`, `packages/gr_protocol/lib/src/http/changes.dart` | `[~]` |
| W2 | HTTP client and camera Library caches | `packages/gr_protocol/lib/src/http/client.dart`, `packages/gr_camera/lib/src/library/` | `[x]` |
| W3 | Camera layer pairing, Bluetooth adapter, native Wi-Fi, app pairing screens | `packages/gr_camera/lib/src/{session,pairing}.dart`, `packages/gr_camera/lib/src/platform/`, `packages/gr_camera/lib/src/shoot/remote.dart`, `packages/gr_camera/android/`, `packages/gr_camera/ios/`, `app/lib/src/pairing/` | `[~]` |
| W4 | App data, downloads and debug log | `app/lib/src/data/`, `app/lib/src/downloads/`, `app/lib/src/library/library_scope.dart`, `app/lib/src/debug/`, `app/lib/src/app_scope.dart` | `[x]` |
| W5 | App connection controller and Cameras screen | `app/lib/src/connection/`, `app/lib/src/cameras/` | `[~]` |
| W6 | Protocol Bluetooth pairing and Wi-Fi credentials | `packages/gr_protocol/lib/src/ble/` | `[x]` |
| W7 | Reused file names (after W2 and W4 land) | as needed across W2 and W4's files | `[~]` |

Test files follow their source files. `gr_fake_camera` is shared: changes to it stay small, and conflicts are resolved when rebasing.

## Connection handling

### W1: protocol session and change socket

- [ ] **C1. A failed Wi-Fi start keeps the phone on the camera's network.** When the phone joins but the camera doesn't answer (or is the wrong camera), the session drops back to Bluetooth without releasing the phone's join, and `stopWifi()` then does nothing. Release the join on every abandoned start. `session.dart` `_startWifi` error path, `_wifiInUse`.
- [ ] **C2. A normal session close keeps the phone on the camera's network.** `close()` releases the join only when asked to power the camera off. Release it on every close; camera power stays a separate choice. `session.dart` `close`. (W3 updates the `CameraSession.close` doc in `gr_camera` to match.)
- [ ] **C3. A Bluetooth drop during a wake leaves a dead link in use.** Drops are ignored while `_relinking` is set, which starts before the Operation Mode write; if the write then fails, the dead client is kept. `session.dart` `_powerOn`, `_onBleDisconnected`.
- [ ] **C4. A closed session can come back to life.** A WebSocket handshake or a scan that finishes after `close()` can start services or change the phase. `session.dart` `_startWifi`, `_startWifiServices`, `connectBluetooth`.
- [ ] **C5. Two Wi-Fi starts can run at once.** `startWifi()` doesn't check for a start already in flight. `session.dart`.
- [ ] **C6. Cancelling a Wi-Fi start or wake waits for the whole Bluetooth reconnect cycle**, which can take minutes. `session.dart` `_bleReconnect` waits.
- [ ] **C7. If the change notifications fail to open the first time, they are never retried.** `changes.dart` initial `connect()` failure, session `_startWifiServices`.
- [ ] **C8. Two change sockets can be open at once.** `connect()` doesn't share an open in progress or cancel a scheduled reconnect. `changes.dart`.

### W2: HTTP client and camera Library request limits

- [x] (e5053c7) **C9. Stalled responses outlive their timeouts.** After a timeout the body read keeps going, and an error response to a download has no timeout at all. `client.dart` `_exchange`, `_readBody`, download non-200 path.
- [x] (2d84032) **C10. The Library's three-request limit stops holding when the camera stalls.** A request past its deadline frees its slot but keeps its connection open. `request_queue.dart`, `camera_images.dart` `_fetch`, `movie_cache.dart`.
- [ ] **C28. Download pause and cancel, and Library info requests, still can't close a stalled request early.** C10 added an `abort` option, but `downloadFiles` and `fileInfo` don't take it yet, so these wait for the next chunk or their own HTTP timeout. `camera_library.dart`, `download_engine.dart`, `library_model.dart`.

### W3: camera layer pairing, Bluetooth adapter, native Wi-Fi

- [ ] **C11. iOS keeps the camera's network saved after a join times out.** `WifiPlugin.swift` timeout path after a successful `apply`.
- [ ] **C12. Android stops its fast rescans for the camera network after the app is paused** (for example by the approval screen) and never restarts them. `WifiChannel.kt` `onPause`/`onResume`.
- [ ] **C13. A cancelled pairing can disconnect the next pairing or session.** The pending connect isn't owned by anyone during cancellation. `pairing.dart`, `ble_transport.dart` connect and MTU.
- [ ] **C14. Pairing retries skip the 15-second wait the GR IV needs** before it locks out pairing (`research/protocol/ble.md`). Enforce the wait per camera and show it in the retry screen. `pairing.dart`, `app/lib/src/pairing/`.
- [ ] **C15. Turning a Bluetooth watcher off and on quickly can leave the camera's notifications switched off.** `ble_transport.dart` subscribe/unsubscribe, `remote.dart` `_subscribe`.
- [ ] **C16. Cancelling pairing leaves the previously linked camera disconnected.** `pairing_flow.dart` only restores a session that was connecting or on Wi-Fi, not one linked over Bluetooth.
- [ ] **C17. A Wi-Fi consent answer that arrives after the join was cancelled can still start a join.** `session.dart` `_ConsentWifi.leave`.

### W5: app connection controller and Cameras screen

- [ ] **C18. Pressing Back while Bluetooth is still connecting still joins Wi-Fi afterwards.** `connection_controller.dart` `joinWifi`, `_leaveWifi`.
- [ ] **C19. Switching to Library while Bluetooth is connecting never joins Wi-Fi.** `connection_controller.dart` `selectTab`.
- [ ] **C20. Two quick disconnects let a new connection reuse a link that is still closing.** `connection_controller.dart` `disconnect`, `_closing`.
- [ ] **C21. If Wi-Fi recovery gives up while the app is in the background, it isn't retried on return.** `connection_controller.dart` `_wifiGaveUp`, foreground setter.
- [ ] **C22. A Bluetooth permission granted in Settings is ignored until the app restarts.** `cameras_screen.dart` cached `_permission`.

### W6: protocol Bluetooth pairing and Wi-Fi credentials

- [x] (1ade2f4) **C23. If reading the camera's Wi-Fi security fails, the app assumes WPA2** instead of reporting it. Use WPA2 only when the camera has no security characteristic. `client.dart` `readWifiCredentials`.
- [x] (d304c5c) **C24. A camera that is turned off ends the pairing search** even when another camera nearby is on. `pairing.dart` scan predicate.
- [x] (d304c5c) **C25. A disconnect error during pairing cleanup hides the real pairing failure.** `pairing.dart` `fail`.
- [x] (bde0240) **C26. Delete `wakeCamera`.** It uses a wake method our GR IV test showed doesn't work, and nothing in the app calls it. `wake.dart`.
- [ ] **C27. A camera whose Wi-Fi security can't be read is still joined with WPA2.** After C23 the credentials report unknown security, but `session.dart` `_joinAndVerify` treats anything but WPA3 as WPA2, so a WPA3-only camera still fails to join. Decide what unknown security does (read it again, or try both). Follow-up after W1 lands, since W1 owns `session.dart`.

## Data safety

### W4: app data, downloads and debug log

- [x] (aa37cbc) **D1. One failed write stops settings and the camera list from saving** for the rest of the session. `settings.dart`, `cameras.dart` write chains.
- [x] (61c48f9) **D2. Download queue write errors are hidden**, and `flush()` reports success after a failed write. `download_engine.dart` `_save`.
- [x] (e035fc3) **D3. Leaving the camera pages and coming back quickly can run two download engines on the same queue**, which can save a photo twice or delete files the other still needs. `download_engine.dart`, `library_scope.dart`; also two writers sharing `downloads.json.tmp` in `json_file.dart`.
- [x] (091c1c5) **D4. If the debug log folder can't be opened, the app won't start**, even with logging off. `debug_log.dart` `open`, `app_scope.dart`.
- [x] (6f168a5) **D5. A half-written log line (after a crash or a failed write) corrupts the next entry.** `debug_log.dart` reopen and write-failure paths.
- [ ] **D9. After a crash between a photo-library save and the queue write, the shot can be saved again on restart.** W4 left this reconciliation out of D2. `download_engine.dart`.

### W2: camera Library caches

- [x] (afc3924) **D6. Two files with the same name on different storage or folders download to the same place**, and the second returns the first's bytes. `camera_library.dart` `downloadFiles`.
- [x] (7d37dc0) **D7. The preview and movie cache on disk has no size limit.** `camera_images.dart`, `movie_cache.dart`.

### W7: reused file names, crash replay, aborting stalled downloads

- [ ] **D8. When a file name comes back with different content** (SD card swap, deleted and re-shot), the app shows the old preview and movie and marks the new shot as already downloaded. Needs a freshness check for cached media and download history. `camera_images.dart`, `movie_cache.dart`, `library_model.dart`, `download_engine.dart`.

## Later (not in this plan)

Kept here so nothing from the review is lost. From the review reports, by area:

- Shoot: mode-dial lock races, a refused setting restoring old settings after live view closes, drive mode rollback, stale self-timer turning the shutter into a cancel, out-of-order last-shot thumbnails, live-view failures shown as a spinner.
- Library: "JPEG" retrying a failed RAW, "Today" label across daylight saving, two wrong messages, stale recent thumbnails on the Cameras screen.
- Accessibility: shutter and mode switch have no screen-reader action; theme choices not reachable by keyboard.
- Protocol: impossible camera dates accepted, live-view HTTP framing, `waitFor` keeps its subscription after a timeout, subscribe-before-read ordering on Bluetooth notifications, name byte length on registration.
- Project: 57 real-time waits in tests, release builds signed with the debug key, simulated camera too forgiving (HTTP without a Wi-Fi join, focus always succeeds, identical previews, no pairing lockout).
