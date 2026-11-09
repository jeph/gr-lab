# Image Sync 2.1.32: connection lifecycle, liveness and capability gating

Companion to [connection-lifecycle.md](connection-lifecycle.md) (GR WORLD 2.0.0). Source: Ricoh's **Image Sync** app, `com.ricohimaging.imagesync` 2.1.32 (versionCode 20132000, APK SHA-256 `00756f0c0474c7f6ac0271b817effadf15e92362d49eab9d86cd0d6bba639442`). Paths are relative to `work/imagesync-jadx/sources`. SDK = `com/ricoh/camera/sdk/wireless/...` (cited as `impl/...`, `api/...`). Static analysis only; no camera was contacted. Labels: **[inferred]** = reasoned from code, **[unknown]** = not settled statically. Related: [remote shooting](remote-shooting.md), [Image Sync BLE](ble-imagesync.md), [camera models](../camera-models.md).

## 0. Headline findings

- **Image Sync 2.1.32 does not know the GR IV family.** No string `GR IV` exists anywhere in the sources or resources (rg over `com`, `m`, `s`, `j2` and `resources`). Wi-Fi detection rejects any `/v1/props.model` that is not in `SUPPORT_CAMERA` (`impl/WiFiCameraDeviceDetector.java:39-41`, list at `impl/ImplCameraDeviceWiFiAdapterFactory.java:42-59`). The BLE SDK list holds only the GR III family and the K-3 III models (`impl/ImplCameraDeviceBleAdapter.java:327-333`), and the app model enum `m/b0.java` has 15 entries with no GR IV. Every GR-specific behaviour below therefore applies to the GR III/IIIx (+HDF) only. For GR IV, Image Sync is evidence about the protocol family, not about a supported body.
- **Image Sync has an active HTTP heartbeat; GR WORLD has none.** Every 500 ms (fixed delay) `ConnectionChecker` sends an uncached `GET /v1/props` (connect 1 s, read 10 s) and compares the model, serial and BLE name. A disconnect is declared only after **≥3 consecutive failures *and* ≥40 s since the last success** (`impl/ConnectionChecker.java:12-15,62-104`, `impl/SyncTrigger.java:176-179`).
- The WebSocket `/v1/changes` is opened with **connect timeout 7 s and read timeout 0 (none)**, `pingInterval` 0 (no pings). On `onFailure` it is **restarted immediately, with no back-off** (`impl/SyncTrigger.java:44-52,174`; `impl/RestCameraClient.java:261-334`).
- Wi-Fi join is the same Android pattern as GR WORLD (`WifiNetworkSpecifier`, INTERNET removed, `bindProcessToNetwork`, 60 s watchdog). Differences from GR WORLD: Image Sync is **WPA2-only** (`setWpa2Passphrase`, no WPA3), it **pins the BSSID** to the camera's `/v1/props.macAddress` on later connections, and **after success it never unregisters the request** (it unregisters only on `onLost`).
- Image Sync **deliberately drops Wi-Fi 60 s after the app goes to the background**. For BLE models it first reconnects BLE (if `bleEnableCondition` allows it), then turns camera WLAN off (`WLANEnable.FALSE`), then calls `WifiManager.disconnect()` (`com/ricohimaging/imagesync/SvApplication.java:303-306`, `m/c6.java:31-60`).

---

## 1. Wi-Fi join, network binding and BLE handoff

### 1.1 Android Q+ join (`ConnectingWifiActivity`, `SelectBleDeviceActivity`, `s.e`)

| Step | Behaviour | Evidence |
|---|---|---|
| Request | `NetworkRequest.Builder().addTransportType(TRANSPORT_WIFI=1).removeCapability(NET_CAPABILITY_INTERNET=12).setNetworkSpecifier(WifiNetworkSpecifier.Builder().setSsid(ssid).setWpa2Passphrase(pw)[.setBssid(MacAddress.fromString(bssid))])`. `setBssid` is used only when a stored BSSID is non-empty. There is no WPA3, no `setBssidPattern`, and the 2-argument `requestNetwork` has no framework timeout. | `com/ricohimaging/imagesync/ConnectingWifiActivity.java:174-177`; `SelectBleDeviceActivity.java:122-125`; `s/e.java:298-301` |
| `onAvailable` | `bindProcessToNetwork(network)` binds the whole process; state becomes SUCCESS; the SDK connect task `n0` starts (`l(true)`). | `m/m0.java:25-35`; `m/j2.java:32-41` |
| `onUnavailable` | State becomes FAILURE. | `m/m0.java:58-63`; `m/j2.java:45-48` |
| `onLost` | ConnectingWifiActivity callback: `unregisterNetworkCallback(this)` only, with **no unbind and no UI notification**. The `j2` callback (BLE flow) has **no `onLost` override**. | `m/m0.java:44-50`; `m/j2.java` (no override) |
| Watchdog | A thread polls the state 60 × 1 s. SUCCESS → exit **without** unregistering, so the request lives on. FAILURE or 60 s timeout → `unregisterNetworkCallback` + error screen (`error_msg_check_camera_setting`). User cancel → unregister. Confirmed in bytecode via a jadx `--fallback` decompile of `androidx.work.impl.e` (temporary scratch file, deleted after use). | `androidx/work/impl/e.java:62-111` (case 3; the default case is the BLE-flow twin with flag `j`) |
| SDK connect after bind | `n0`: up to **7 attempts, 10 s sleep between** (≈70 s), each `s.i.a()` = detect + connect. Returns TIMEOUT (`o0.f1505c`) → error `error_msg_check_ssid_and_camera_setting` (or `error_msg_wifi_connection` when `move_from_last_ap`). | `m/n0.java:70-105,108-127`; `ConnectingWifiActivity.java:49-55` |
| Process-wide default bind | `SvApplication.onCreate` → `j2.g.K()`: `registerNetworkCallback` **and** `requestNetwork` for *any* Wi-Fi without INTERNET. `onAvailable` binds the process; `onLost` unbinds (`bindProcessToNetwork(null)`) and unregisters. `CheckWifiActivity.onResume` calls it again and then sleeps 3 s. | `SvApplication.java:233`; `j2/g.java:232-239`; `s/j.java:32-50`; `CheckWifiActivity.java:93-98` |
| Already on the SSID? | `s.e` (reconnect from the image list or shooting icon) first runs `j2.g.A(ctx, ssid)`, a `NetworkCallback.onCapabilitiesChanged` reading `WifiInfo.getSSID()`. On a match it skips `requestNetwork`. | `s/e.java:294-297`; `s/q.java:24-53` |
| HTTP socket factory | Default `SocketFactory` (OkHttp builder default). There is no `Network.getSocketFactory()`; traffic relies on the process binding. | `y1/s.java:92-94` |

### 1.2 Pre-Q join (API < 29)

`j2.g.k()` runs `WifiManager.disconnect()`, sleeps 2 s, reuses or creates a `WifiConfiguration` (`"WPA"`/`"wpa_aes"` → WPA-PSK, `"wep"`, otherwise open), then `enableNetwork(others,false)`, `enableNetwork(id,true)`, `saveConfiguration`, `setWifiEnabled(true)`, and finally the generic bind `K()` (`j2/g.java:635-721`).

### 1.3 Credentials and BSSID persistence

- After a successful connect, `s.i.c()` stores the SSID and the key (AES-encrypted with a random key, Base64 encoded) with security `"WPA"`. The BSSID stored is `WLANSpecification.WLANMACAddress.toLowerCase()`, which over Wi-Fi comes from `/v1/props.macAddress`. They go to SharedPreferences `SHARED_PREFERENCE_KEY_LAST_AP_*` and to a per-camera JSON file (`q.b`, written when a BLE name exists) (`s/i.java:142-161,183-246`; `impl/ImplCameraDeviceWifiAdapter.java:585-589`; `impl/ItemCameraInfo.java` `updateItems`).
- Later joins pass that MAC as the `setBssid` value (`m/k2.java:164-205`; `s/e.java:265,287`). **[unknown]** Whether `/v1/props.macAddress` always equals the AP BSSID. If it does not, the pinned specifier would never match.
- NFC: the NDEF payload is split on `\t`. The SSID is `[0].substring(12)`, the password `[1].substring(4)` and the security `[2].substring(7)`. The app then writes 16 bytes `"RIMW\0\1…"` to the tag (FeliCa write `0x08` / ISO-DEP APDU `00 D6`) (`ConnectNfcActivity.java:100-234`). **[inferred]** The fixed prefixes are field labels.

### 1.4 BLE → Wi-Fi handoff (GR III family, K-3 III)

Sequence (`m/k2.java:38-228`, `s/i.java:40-181`, `s/e.java:66-190`):
1. `s.i.a` with BLE: `cameraDevice.connect(BLE)`. **Connecting BLE disconnects the SDK Wi-Fi adapter and connecting Wi-Fi disconnects BLE**, so the two are mutually exclusive (`impl/ImplCameraDevice.java:122-160`). If the camera is not powered: `setPower(true)`, with one retry on failure (`s/i.java:123-129`). Read the `SSID`/`Key`/`Channel` settings over BLE and store them. Write `PairedCentralDeviceName = Build.MODEL` (`s/i.java:169`; BLE only, because the REST YAMLs have no key for it, `res/raw/camera_ricoh_gr_iii.yaml`).
2. GR III family: abort if `CaptureMethod == MOVIE` and `OperationMode == CAPTURE` (`m/k2.java:101-116`).
3. If `OperationMode == BLE_STARTUP` (`"bleStartup"`): write `CAPTURE` when entered from the shooting icon (GR III: `PLAYBACK` if the camera is in movie mode), otherwise `PLAYBACK` (`m/k2.java:118-142`).
4. K-3 III from the shooting icon stays **BLE-only** (`n.c.a` reads the settings and there is no Wi-Fi) (`m/k2.java:144-147`; `s/e.java:135-138`; `n/c.java:45-70`).
5. Read `WLANEnable`; if it is not TRUE, write `WLANEnable.TRUE` (`m/k2.java:149-162`). `s.e` additionally calls `WifiManager.setWifiEnabled(true)` when phone Wi-Fi is off (`s/e.java:150-156`).
6. Run the Q+ join from §1.1 with the stored SSID/pw/BSSID (`m/k2.java:204-206`). The `l2` SDK connect then runs 7 × 10 s (`m/l2.java:57-86`). In the `s.e` variant the BLE link is first awaited for 10 s, and after the join the app polls `connect(WLAN)` every 100 ms for up to 10 s (`s/e.java:75-83,163-172`).
- Wi-Fi-path quirks in `s.i.a` (`s/i.java:56-98,171-178`): even when already WLAN-connected it re-reads `WLANEnable` and sets it TRUE if needed. For `PENTAX K-S2`/`GR II` with fw < 1.1 and channel 6, it rewrites `channel=1` (`PUT /v1/params/device`).
- Device params over Wi-Fi: `PUT /v1/params/device`, `Content-Type: text/plain`, body `key=value&key=value`. Values are not URL-encoded; `gpsInfo` is quoted (`impl/ItemCameraParams.java:33-48,72-87`; `impl/RestCameraClient.java:218-246`; `impl/RestCameraSettingConverter.java:217-258`). GR III keys: `datetime` (`yyyy-MM-dd'T'HH:mm:ss` local time; G900 SE uses UTC `…'Z'`), `channel`, `key`, `ssid`, `focusEffectiveArea`, `powerOffTransfer`, `autoResize` (`on`/`off`), `geoTagging`, `gpsInfo`, `bleEnableCondition` (`disable`/`enableAnytime`/`enablePowerOn`), `operationMode` (`capture`/`playback`/`bleStartup`/`powerOffTransfer`/`other`) (`res/raw/camera_ricoh_gr_iii.yaml`).
- `WLANEnable.FALSE` over Wi-Fi (GR III family, K-3 III) = **`POST /v1/device/wlan/finish`** with an empty `text/plain` body (`impl/ImplCameraDeviceWifiAdapter.java:755-804`; `impl/ActionCapture.java:516-525`).

---

## 2. Liveness, keep-alive, disconnect detection, reconnect

### 2.1 HTTP client (`RestCameraClient`, OkHttp **5.1.0**, UA `okhttp/5.1.0`)

| Item | Value | Evidence |
|---|---|---|
| Client | One singleton `t` (OkHttpClient). Each GET or WebSocket builds a derived client via `newBuilder()`, which shares the **connection pool**, dispatcher and task runner. | `impl/RestCameraClient.java:58-59,129-136`; `y1/t.java:243-275` |
| Builder defaults | connect 10 s, read 10 s, write 10 s, `retryOnConnectionFailure=true` (OkHttp silently retries a failed connection or route), WS close timeout 60 s, minimum deflate size 1024 | `y1/s.java:80-104` |
| Pool | OkHttp default: keep-alive **5 min** (`timeUnit.toNanos(5)`), max idle 5 **[inferred, OkHttp default]** | `c2/u.java:29-31`; `b2/d.java:168-186` |
| `doGet(url, cls, useCache, connectSec, readSec)` | Per-call timeouts. The response is cached per bean class in `cacheMap`; a `useCache=true` caller gets the last body of that class **without any network I/O**. | `impl/RestCameraClient.java:121-159` |
| Callers | Usually `(7, 10)`. `pullWithShortTimeout` uses `(1, 10)`. Photo list `/v1/photos` uses `(7, 300)`. | `impl/ItemCameraInfo.java:133,147`; `impl/ItemImages.java:233,330` |
| `doGetStream(url, readMs)` | Called with `0`, meaning **no read timeout**; connect stays at the default 10 s. Non-200 → `RestCameraException(url,-1,http)`. Returns the stream and `Content-Length`. | `impl/RestCameraClient.java:161-186`; `impl/ItemImages.java:272,361` |
| POST/PUT | Base client (10/10/10 s), body `text/plain` | `impl/RestCameraClient.java:188-246` |
| JSON quirk | Response text has `4294967295` replaced with `-2147483648` before Jackson parsing. | `impl/RestCameraClient.java:109-111` |
| Retries | None at app level apart from OkHttp's connection retry. | — |

### 2.2 `SyncTrigger` (started by `connect(WLAN)` → `startPolling()`)

- `startWebSocket(baseURL+"/v1/changes", listener, 7, 0)`: the **`7, 0` are connect timeout 7 s and read timeout 0 (disabled)**. They are not retries or a ping interval. The `RealWebSocket` is built with `pingInterval=0`, so there are **no client pings**. Handshake headers: `Upgrade: websocket`, `Connection: Upgrade`, `Sec-WebSocket-Version: 13`, `Sec-WebSocket-Extensions: permessage-deflate` (`impl/RestCameraClient.java:261-334`).
- `onFailure` → `finishWebSocket()` + `startWebSocket(...)` immediately, unbounded, with no back-off. `onClosed` only logs (`impl/SyncTrigger.java:39-52`).
- Messages are parsed into `BeanChanges`. If `changed` is null, the `change` field is used (`impl/SyncTrigger.java:55-66`). Dispatch by `changed` value: `cameraDirect` (UpdateChanged), `storage` (UpdateLatestCaptureImage: `action=="add"` and `captureId!="0"` → `latestFilePath`/`latestStorage`; UpdateCameraImage when background sync is on), `transfer` (UpdateTransfer), `lens`, `capture`, `camera` (UpdateCameraSetting/UpdateCaptureSetting/UpdateCameraStorage refetch), `battery` (UpdateCameraStatus) (`impl/Update*.java` `getChanged()`).
- Timers: `ScheduledThreadPoolExecutor(3)`, **every runnable `scheduleWithFixedDelay(500 ms, 500 ms)`** (`impl/SyncTrigger.java:146-153,176-179`). Registered (`impl/ImplCameraDeviceWifiAdapter.java:257-323`):
  - `ConnectionChecker` → real `GET /v1/props` (`ItemCameraInfo(useCache=false)`, `:204-213`).
  - `UpdateCaptureSetting`, `UpdateCameraSetting` and `UpdateCameraStorage` (useCache=true) → re-parse the cached `/v1/props` body with no extra traffic (`impl/ItemCaptureParams.java:40-45` `useCache = z5`; `impl/ItemCameraParams.java:23-25`; `impl/ItemStorages.java:22-23`; `impl/ItemStatus.java:19-20`).
  - GR III family and K-3 III also run `UpdateCameraStatus(useCache=true)`.
  - Net effect: about **one `/v1/props` per (500 ms + RTT)** while connected.
- `ConnectionChecker.run` (`impl/ConnectionChecker.java:52-113`):
  - Skips (counts as OK) while the image list is being read (`UpdateState.READING_LIST`).
  - Otherwise `pullWithShortTimeout()` (1 s connect), or `pull()` (7 s) while reading info.
  - `isSameCameraInfo(manufacturer, model, serial, bdName)` must match (`impl/ItemCameraInfo.java` `isSameCameraInfo`).
  - Failure or exception → `numRetry++`. When `numRetry` was already ≥2 and `now - lastSuccess > 40000 ms` → `processDisconnect()`: adapter `disconnect()` (stops the trigger and WS, terminates downloads; waits ≤2 s), then `deviceDisconnected` to every listener.
- `destroy()`: shut down the executors (2 s + 2 s each) and finish the WS (`impl/SyncTrigger.java:113-144`).

### 2.3 App reaction and reconnect

- Shooting screen `deviceDisconnected` → clears the camera and returns to `MainActivity` (`m/e4.java:37-52`). `MainActivity` listener → clears the camera; if in the foreground, restarts the **auto-detect timer** (`m/f2.java:20-41`).
- Auto-detect timer: `Timer.schedule(task, 3000, 1000)`, active while no camera is attached (`MainActivity.java:117-124`). The task loops (`n/e.java:55-190`):
  - If phone Wi-Fi is on, try `s.i.a(WLAN)`, i.e. a WLAN detect via `GET /v1/props` on the currently bound network. **No `requestNetwork`.**
  - Otherwise, if BT and location are on and the pref `SHARED_PREFERENCE_KEY_BLUETOOTH_AUTO_RECONNECTION` is set, scan BLE for 10 s for bonded and known names, then `connect(BLE)`.
- Re-entering Wi-Fi from the image list or shooting icon uses `s.e` (BLE wake → WLAN on → specifier join → `connect(WLAN)` poll) (`m/d2.java:40-66`; `s/u.java:85-108`).
- Background policy:
  - 60 s after `ProcessLifecycle.onStop` with WLAN connected, `c6` runs on GR III family/K-3 III. It connects BLE if a bonded device exists and `bleEnableCondition ∈ {enableAnytime, enablePowerOn}`, sends `WLANEnable.FALSE`, disconnects the SDK WLAN, and calls `WifiManager.disconnect()`. Other models: SDK disconnect + `WifiManager.disconnect()`. `onStart` cancels the pending handler (`SvApplication.java:270-284,297-306`; `m/c6.java:31-60`).
  - The shooting screen also stops movie recording and turns live view off 60 s after `onPause` if the app is backgrounded (`ShootingActivity.java:2742-2752,1410-1446`).
- No WakeLock or WifiLock is used by app code (rg for `newWakeLock`/`createWifiLock`/`WifiLock` in app and SDK packages: no hits).
- The only foreground service is `LocationUpdateService` (type `location`, `startForeground(1, …, 8)`, 2 s timer) (`LocationUpdateService.java:72-97`; manifest `foregroundServiceType="location"`).
- Periodic time sync: if the pref `SHARED_PREFERENCE_KEY_AUTO_DATETIME_SYNC` is set, a 60 s `Timer` pushes `CameraTime(now)` (`PUT /v1/params/device datetime=…` over Wi-Fi) for K-3 III and the GR III family when powered and `operationMode == capture`. The timer cancels after the first success, so it is not a heartbeat (`SvApplication.java:113-134`; `m/e6.java:30-75`).

### 2.4 Liveness / reconnect comparison

| Aspect | Image Sync 2.1.32 | GR WORLD 2.0.0 (docs) |
|---|---|---|
| Join API | `WifiNetworkSpecifier`, TRANSPORT_WIFI, INTERNET removed, `bindProcessToNetwork` (`ConnectingWifiActivity.java:174`, `m/m0.java:29`) | Same (`connection-lifecycle.md` §1) |
| Security | WPA2 passphrase only | WPA2/WPA3/transition with WPA3→WPA2 fallback |
| BSSID | Pinned to the stored `/v1/props.macAddress` after the first connect | Not pinned |
| Join timeout | 60 × 1 s watchdog + SDK connect 7 × 10 s | 60 s (120 s with fallback); props pre-check 3 s |
| Request lifetime after success | Kept registered until `onLost` | Field of MainActivity; `disconnectWifi` unregisters V only |
| `onLost` | Unregister only (ConnectingWifi), nothing (BLE flow `j2`); global `K()` callback unbinds. The UI learns via ConnectionChecker. | V: silent unbind/unregister; W: nothing |
| HTTP keep-alive | OkHttp shared pool, 5 min idle, `retryOnConnectionFailure` | `HttpURLConnection` (native) / new Dart client per request |
| Heartbeat | **`GET /v1/props` every 500 ms** (fixed delay), connect 1 s / read 10 s | None |
| WS `/v1/changes` | Connect 7 s, read timeout none, no ping, **auto-restart on failure** | No ping, never reopened |
| Loss declaration | ≥3 consecutive failed props checks **and** ≥40 s since last success; identity mismatch counts as failure | WS `onDone` or connectivity `none` |
| Auto reconnect | Foreground: 1 s detect loop over the bound Wi-Fi + optional BLE auto-reconnect (10 s scan) | None |
| Background | Deliberately turns camera WLAN off and disconnects 60 s after backgrounding | No equivalent timer documented |
| FGS / locks | Location FGS only; no Wi-Fi/wake lock | `dataSync` FGS during transfers (`allowWifiLock`) |

---

## 3. Detection and model gating

### 3.1 Detection

- Wi-Fi: `WiFiCameraDeviceDetector.detect` → `GET http://192.168.0.1/v1/props` (1 s/10 s). If `model` is null it retries against `http://192.168.1.1` as `G900 SE`. The model must be in `SUPPORT_CAMERA`, otherwise it logs `"<model> is unsupported"` and returns null. Manufacturer defaults to `"RICOH IMAGING COMPANY, LTD."` (`impl/WiFiCameraDeviceDetector.java:14-56`; `impl/ItemCameraInfo.java` `guessManufacturer`). Identity fields come from `/v1/props`: `model`, `serialNo`, `firmwareVersion`, `macAddress`, `bdName`, `manufacturer`, `stateMovie=="busy"` (`impl/ItemCameraInfo.java` `updateItems`).
- BLE: the scan accepts names starting with `"GR"` or `"PENTAX"` (`impl/BleCameraDeviceDetector.java:18-26`; `impl/ble/core/d.java:178-197`). The app filters bonded names by prefix `GR_` (GR III family) or `PENTAX_` (K-3 III) (`SelectBleDeviceActivity.java:180-196`). Scans run 30 s on the select screen, 3 s and 10 s elsewhere (`m/k1.java:278,313`; `m/i6.java:37`; `n/e.java:111`). BLE internals are out of scope here.
- Base URL `http://192.168.0.1` / `ws://192.168.0.1`; G900 SE uses `192.168.1.1` (`impl/SyncTrigger.java:105-111`; `impl/ItemImages.java:71-75`).
- `SYNC_MODE` (WEBSOCKET for WG-M2/G900 SE, POLLING otherwise) is stored but **never read**. All models get WS + polling (`impl/ImplCameraDeviceWiFiAdapterFactory.java:472-474`; `impl/ImplCameraDeviceWifiAdapter.java:78,126`).

### 3.2 Capability matrix

SDK `ActionCapture.Option(still, stillWithFocus, movie, focus, changeCaptureMethod, powerOff, shootMode, changeExposureProgram)` (`impl/ActionCapture.java:61-70`; values `impl/ImplCameraDeviceWiFiAdapterFactory.java:353-456`).

| Model string (`/v1/props.model`) | Wi-Fi SDK | BLE SDK | Option flags (S,SF,Mv,F,CM,PO,SM,EP) | Movie/bulb URLs | XS/resize (`?size=xs`) | Transfer list + auto-transfer | Remote shooting entry (app) | Notes |
|---|---|---|---|---|---|---|---|---|
| `RICOH GR III` | yes | yes | 1,1,1,1,0,1,1,1 | `/v1/camera/shoot` (+`/compose`) | yes | yes | yes, blocked in movie mode | fw ≤ 1.00 → "firmware update required" dialog |
| `RICOH GR III HDF` | yes | yes | same as GR III | same | yes | yes | yes, blocked in movie mode | |
| `RICOH GR IIIx` | yes | yes | same | same | yes | yes | yes, blocked in movie mode | |
| `RICOH GR IIIx HDF` | yes | yes | same | same | yes | yes | yes, blocked in movie mode | |
| `GR II` | yes | no | 1,1,0,1,0,1,0,0; focus URL `http://192.168.0.1/v1/lens/focus/lock`, query `af=camera` | — | no | no | **no** ("This function not supported") | fw < 1.1 + channel 6 → force channel 1; storage `in` hidden when `sd1` present |
| `PENTAX K-3 Mark III` / `… Monochrome` | yes | yes | 1,1,1,1,0,0,1,0 | `/v1/camera/shoot` (+`/compose`) | yes | yes (per-storage) | yes; BLE-only shooting path | storage-active props |
| `PENTAX K-1` / `K-1 Mark II` | yes | no | 1,1,0,1,0,0,0,0 | — | no | no | yes | |
| `PENTAX KP` | yes | no | 1,1,1,1,0,0,1,0 | `/v1/camera/shoot` | no | no | yes | |
| `PENTAX K-70` / `KF` / `K-S2` | yes | no | 1,1,0,1,0,0,0,0 | — | no | no | yes | |
| `RICOH WG-M2` | yes | no | 1,0,1,0,1,0,1,0 | — | no | no | yes | |
| `G900 SE` | yes | no | 1,1,1,1,1,0,0,0 | — | no | no | yes | base `192.168.1.1` |
| any GR IV string | **rejected** | **rejected** | — | — | — | — | — | not in any list |

Evidence for the rows:
- BLE list: `impl/ImplCameraDeviceBleAdapter.java:327-333`.
- XS list: `impl/ImplCameraDeviceWiFiAdapterFactory.java:60-67`; `impl/ImplCameraImage.java:188-190`.
- Transfer list: `impl/ImplCameraDeviceWifiAdapter.java:225-255`.
- Shooting entry: `s/s.java:37-86` (result `NOT_SUPPORTED_REMOTE_SHOOTING_CAMERA` for GR II; `error_msg_switch_to_stillimage_mode` for the GR III family in movie mode).
- Firmware dialog: `ConnectingWifiActivity.java:70-72`; `MainActivity.java:109-115`; `s/u.java:85-90` (string `msg_not_supported_version`).
- K-S2/GR II channel fix: `s/i.java:171-178`.
- Storage rule: `impl/ImplCameraDeviceWiFiAdapterFactory.java:208-224`.

App predicates in `s/g.java` (model sets):
- `I`/`P` = K-3 III family + GR III family: background BLE/WLAN-off, recordable time (`:146-162,247-263`).
- `N` = GR II, GR III family, G900 SE: second storage (`:221-238`).
- `G` = K-1, K-1 II, K-3 III Mono, K-3 III unless fw is `1.40`/`1.41`: Astro Tracer type 3 UI (`:129-137`; `ShootingActivity.java:2342-2354`).
- `J` and `R` = K-3 III family + GR III family. `R` gates the "Auto resize" setting row and the resize-transfer menu (`m/d3.java:252`; `ImageViewActivity.java:143`). In bytecode the firmware comparisons (`"1.60"`, `"1.10"`, `"1.41"`) are dead: every branch returns true (fallback decompile of `s.g`).
- `M` excludes WG-M2, the GR III family and G900 SE (`:217-219`).
- `Q` = K-3 III family (`:265-270`).

Minimum firmware in Image Sync: only GR III ≤ 1.00 triggers a warning. There is **no GR IIIx minimum** (contrast `research/camera-models.md`, which follows GR WORLD: GR III ≥ 2.00, GR IIIx ≥ 1.50, GR II ≥ 3.00).

Manual model picker: K-S2, GR II, WG-M2, K-1, K-3 III, K-70, KF, KP, GR III, GR IIIx, G900 SE (`SelectConnectionModelActivity.java:26-39`). HDF and Monochrome variants are folded into their base button for BLE history (`SelectConnectionProcessActivity.java:150-158`).

---

## 4. Transfer differences vs GR WORLD

| Item | Image Sync | Evidence |
|---|---|---|
| Image GET | `GET /v1/photos/{dir}/{file}{query}`, query `""` (full), `?size=view`, `?size=thumb`, `?size=xs`. Storage appended as `?storage=` (full) or `&storage=` (others). Only non-K-3 III storages pass `null`. | `impl/ItemImages.java:29,43-47,258-270,344-359` |
| `?xs` marker | A file name containing `?xs` is stripped before building the URL. In the auto-transfer list such entries are downloaded with `size=xs`. `transfers[].size` `"full"`/`"xs"` maps to `TransferQuality`. | `impl/ItemImages.java:345-347`; `m/j.java:354-366`; `impl/ImplCameraTransferImage.java:43-50` |
| Download timeouts | connect 10 s, **no read timeout**; 4096-byte chunks. A first byte `{` is parsed as an error JSON → `RestCameraException(errCode)`. | `impl/RestCameraClient.java:161-186`; `impl/ItemImages.java:78-87,367-381` |
| Range/resume | **None** (no Range header anywhere) | rg `Range` |
| List | `GET /v1/photos[?storage=s][&|?limit=n][&after=dir/file]`, paged until a page holds fewer than `limit` items; read timeout 300 s | `impl/ItemImages.java:312-342,89-105` |
| Info | `GET /v1/photos/{dir}/{file}/info[?storage=]` (7/10 s), fields `datetime`, `orientation` 1–8, `size`, `file`, `dir` | `impl/ItemImages.java:175-200` |
| Latest | `GET /v1/photos/latest/info`, or `/v1/photos/{latestFilePath}/info?storage=` when the WS supplied a path | `impl/ItemImages.java:202-223`; `impl/ImplCameraDeviceWifiAdapter.java:617-627` |
| Transfers | `GET /v1/transfers?status=untransferred&limit=5000[&storage=s][&after=index]` (7/10 s). Only the GR III family and K-3 III have it; K-3 III passes the storage ID. | `impl/ItemTransfers.java:13,50-78`; `impl/ImplCameraDeviceWifiAdapter.java:225-255` |
| Mark transferred | `PUT /v1/photos/{dir}/{file}/transfer` body `status=transferred[&storage=s]` (`text/plain`) | `impl/ItemImages.java:243-256` |
| WS transfer events | `changed:"transfer"`, `action` ∈ `add`/`state`/`delete`/`format`; fields `storage`, `index`, `filepath`, `size`, `state` (`untransferred`/`transferred`) | `impl/UpdateTransfer.java:38-123` |
| Background list sync | The app sets `setBackgroundSyncImages(false)` and `setSortMode(false)` before connect, so `UpdateCameraImage` is not registered and there is no automatic photo-list refresh | `s/i.java:100-101`; `impl/ImplCameraDeviceWifiAdapter.java:276-278` |

GR WORLD differences:
- GR WORLD uses `HttpURLConnection` with 10/15/120 s timeouts and no keep-alive tuning (`http-api.md:17`, `connection-lifecycle.md` §2).
- GR WORLD runs a `dataSync` FGS + WifiLock during transfers. Image Sync has neither, and its 60 s background WLAN shutdown would interrupt long background transfers **[inferred]**.

---

## 5. Errors

- Envelope: every JSON response carries `errCode` (int, 200 = OK) and `errMsg` (`impl/BeanProps.java`, `impl/Bean*.java`). Any `errCode != 200` → `RestCameraException(url[, body], errCode)` with `httpCode` 200. A JSON parse failure → errCode `-1` (`impl/RestCameraException.java:10-56`). In streams, an HTTP status other than 200 → `(url, -1, httpStatus)`.
- SDK `ErrorCode`: `NETWORK_ERROR`, `DEVICE_NOT_FOUND`, `IMAGE_NOT_FOUND`, `INVALID_SETTING`, `INVALID_ARGUMENT`, `NO_SPACE`, `FORBIDDEN`, `UNKNOWN_VALUE`, `IO_ERROR` (`api/response/ErrorCode.java`).
- Mappings:
  - errCode or HTTP **404** on download/info → `IMAGE_NOT_FOUND` (`impl/ImplCameraImage.java:398,473,515,606`).
  - Shoot errCode **412** while storage is full → `NO_SPACE` (`"…is Full"`) (`impl/ImplCameraDeviceWifiAdapter.java:1096-1101`).
  - Any other REST error → `FORBIDDEN "Failed <url>(ErrorCode:n)"`.
  - IOException → `NETWORK_ERROR`.
  - Local `ENOSPC` → `NO_SPACE`.
  - Capture refused while busy → `FORBIDDEN "Device Busy"` (`:1111`).
  - Not connected → `DEVICE_NOT_FOUND` (`:188-192`).
  - Download `"Communication Error"` → `NETWORK_ERROR` (`impl/ImplCameraImage.java:529-543`).
- App UI errors: `error_msg_check_camera_setting` (join failed or timed out), `error_msg_check_ssid_and_camera_setting` (SDK connect timeout), `error_msg_wifi_connection` (last-AP path), `error_msg_camera_not_supported`, `error_msg_function_not_supported`, `error_msg_switch_to_stillimage_mode` (`ConnectingWifiActivity.java:49-96`; `s/s.java:99-128`).

## 6. Unknowns

1. Whether `/v1/props.macAddress` equals the AP BSSID used by `setBssid` (affects every pinned rejoin).
2. Camera behaviour under a 2 Hz `/v1/props` poll: power or auto-off effects, and whether it suppresses the idle drops seen with GR WORLD. Needs a live capture.
3. Whether the GR IV `/v1/props` and `/v1/changes` semantics match those the GR III-era SDK expects; Image Sync would reject the body before it got that far.
4. The NFC payload field labels (`substring(12/4/7)`) and the meaning of the `RIMW` tag write.
