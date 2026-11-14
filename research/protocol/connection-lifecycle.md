# GR WORLD 2.0.0: connection lifecycle and robustness (Wi-Fi join, keep-alive, loss detection, reconnect)

Scope: how the official Android app joins the camera's Wi-Fi AP, keeps the link up, notices when it drops, and reconnects. It also covers why the link drops and how a third-party client should do this better. Sources: jadx Java (`work/jadx/sources/...`, file:line), the blutter dump of `libapp.so` (`pp+0x…` pool offsets, `0x…` function addresses in `dis/condensed.txt`), and `AndroidManifest.xml`. Labels: **[inferred]** = reasoned, not directly observed; **[unknown]** = not settled statically.

Related docs: `http-api.md` (endpoints, WebSocket), the BLE slice (WLAN Control service `F37F568F-…`, characteristic `hJb` `9111CDD0-9F01-45C4-A2D4-E09E8FB0424D` = camera WLAN on/off), `../framework.md`.

---

## 1. Summary for implementers

- Android joins the camera AP with `WifiNetworkSpecifier` + `ConnectivityManager.requestNetwork(...)`. The request is TRANSPORT_WIFI with NET_CAPABILITY_INTERNET removed. When the network comes up the app calls **`bindProcessToNetwork(network)`**, so the whole process is bound to the camera network. Timeout is 60 s; for WPA2/WPA3 transition mode it falls back from WPA3 to WPA2 (worst case 120 s).
- The `NetworkCallback`, the timeout handler and the pending result all live as **fields of `MainActivity`**. No foreground service owns the Wi-Fi session. The `dataSync` foreground service (flutter_foreground_task, `allowWifiLock=true`) runs **only during photo transfers**. The `location` foreground service (geolocator) has `enableWifiLock=false`.
- **There is no keep-alive.** The app sends no periodic HTTP request or WebSocket ping (no `pingInterval`). The only periodic timers send location over BLE (5 s, or a user-set interval) and scan BLE. The one long-lived Wi-Fi connection is the WebSocket `ws://192.168.0.1/v1/changes`. For GR III/IV its messages are ignored, so it only serves as a liveness signal (see http-api.md §5).
- **Loss detection is indirect and incomplete:**
  - The native `onLost` for the WPA3/WPA2-direct request silently unbinds and unregisters. It never tells Dart.
  - The native `onLost` for the WPA2-fallback request **does nothing at all**, so the process stays bound to a dead network.
  - Dart notices loss only through (a) the WebSocket `onDone` (`websocketConnectionStateNotifierProvider` → `disconnected`) or (b) connectivity_plus reporting `none` as the first result.
  - Both listener paths are gated by an "isIgnore" flag. When the WebSocket drops, the state update still runs in the background; only the "connection lost" dialog is skipped while `isPaused` is true.
- **There is no automatic Wi-Fi reconnect.** The WebSocket is opened only by the post-join setup (`0xd1d508`), so it is never reopened on its own. The user has to restart the flow (e.g. the `/reconnect` route) or start a feature that runs the connect flow again.
- The app itself turns the camera WLAN **off**. Its BLE device "release" routine writes `hJb=0x00` and calls `disconnectWifi`. This routine runs before BLE (auto-)connects.

---

## 2. Native channel `com.pavct.jp.grapp/wifiConnection`

Registered in `AbstractActivityC0655d.java:516` (the Flutter host activity's `configureFlutterEngine`, with handler class `v6.b`). The channel name is the field `MainActivity.f10012G` (`MainActivity.java:52`). A second channel, `com.pavct.jp.grapp/widget` (`:1617`), is unrelated: it handles album/widget calls `deleteAlbum`, `deletePhotos`, `updateAlbum` and `updateAlbumName`. Unknown methods get `notImplemented` (`:1394`).

Results: `success(x)` = `mo2967d`, `error(code,msg,details)` = `mo2969f`.

| Method | Args | Native behaviour | Result | Evidence |
|---|---|---|---|---|
| `connectToWifi` | `ssid`, `password`, `serialNo`, `model`, `bdName` (String), `securityType` (int: 0 WPA2, 1 WPA3, 2 WPA2/WPA3 transition) | See §3. Pre-check `GET /v1/props` (3 s); if that fails, `requestNetwork` with a 60 s timeout. | `true` when the network is available or the pre-check passed. `false` from `onUnavailable`/`onLost` before success. Errors: `("connectToWifi","TIMEOUT Connection timeout")`, `("TIMEOUT","Connection timeout during WPA2 retry")`, `("Exception","Error",e)`, `("","")` if an arg is missing. | `AbstractActivityC0655d.java:582-666`; `C4805d.java`; `RunnableC4802a.java`; `MainActivity.java:73-115` |
| `disconnectWifi` | – | Removes the timeout, `bindProcessToNetwork(null)`, `unregisterNetworkCallback(V)` (**V only, never W**). | `true`. `false` on exception. `true` if the ConnectivityManager was never created. | `:1191-1216` |
| `getConnectedSsid` | – | Builds a generic Wi-Fi `NetworkRequest` without INTERNET. On callback X it calls `registerNetworkCallback` **and** `requestNetwork` (X has `FLAG_INCLUDE_LOCATION_INFO`, `super(1)`, `C4805d.java:240-244`). Has a 1 s timeout. `onCapabilitiesChanged` takes the SSID from `WifiInfo`, stores it with quotes stripped into `f10008A`, then unregisters. | SSID string **with quotes**. Errors: `("TIMEOUT","SSID get timeout")`, `("Lost","Get error")`, `("Unavailable","Get error")`, `("Exception","Error")`. | `:537-565`; `C4805d.java:77-115,143-160,197-213`; `RunnableC4802a.java:43-56` |
| `checkWifiState` | – | `WifiManager.isWifiEnabled()` | bool | `:676-681` |
| `getPropertyData` | – | `GET /v1/props`, 10 s connect/read | JSON string | `RunnableC3963a.java:96-127` |
| `getDeviceStatus` | – | `GET /v1/status/device`, 10 s | JSON | `RunnableC3963a.java:41-72` |
| `postCameraPower` | – | `POST /v1/device/finish` (empty body), 10 s connect, no read timeout. This is camera power-off. | `true` / error `"POST error"` | `RunnableC3963a.java:73-95` |
| `putWifiInfo` | `ssid`, `password` | `PUT /v1/params/device` body `channel=0&ssid=…&key=…` (GR II path) | bool | `RunnableC0391f.java:340-367` |
| `getPhotosList`, `getPhotoInfoList`, `getPhotosInfo`, `getTransfersList`, `putTransferState` | see http-api.md | Plain `HttpURLConnection` on a new thread. Timeouts 10 s (list/transfers), 15 s (info), 120 s (infos list), PUT 10 s connect. | JSON | `:684-1389` |

There is **no `lastConnectedWifi` channel method.** `"lastConnectedWifi"` (pp+0x279f0) and `"lastConnectedDevice"` (pp+0x27d30) are Dart preference keys read in `0xd1e340`.

All native HTTP uses `java.net.HttpURLConnection` (JDK-default keep-alive pool). It does not specify a network, so it relies on the process binding.

---

## 3. Android Wi-Fi join implementation (exact)

State fields in `MainActivity` (`MainActivity.java:19-70`):
- `N`: ConnectivityManager
- `O`: pending `connectToWifi` result
- `P`: main-looper Handler
- `Q`: timeout Runnable
- `A`: "current SSID", initially `""`
- `B`/`C`: ssid/password
- `F`: securityType
- `V`: `C4805d(this,0)`, the first-attempt callback
- `W`: `C4805d(this,2)`, the WPA2-fallback callback
- `X`: `C4805d(this)`, the getConnectedSsid callback
- `R`/`S`/`T`/`U`: ConnectivityManager / result / Handler / timeout used by getConnectedSsid

`connectToWifi(ssid, password, serialNo, model, bdName, securityType)` (`AbstractActivityC0655d.java:582-666`):
1. Cancel any pending timeout `Q`. Store `B=ssid`, `C=password`, `F=securityType`.
2. **Pre-check (on the platform/UI thread):** start a thread running `RunnableC1626F` case "default" and `join()` it (`:607-609`), so the main thread blocks for up to ~6 s. The thread does `GET http://192.168.0.1/v1/props` with 3 s connect + 3 s read (`RunnableC1626F.java:119-124`). It succeeds when all hold: `errCode==200`, `ssid==ssid`, `takeLast(8)` of `serialNo` `== serialNo` (`m792k0(8,…)`), `model` with "RICOH" removed and trimmed `== model`, and `bdName==bdName` (`:133-143`). On success, `connectToWifi` returns `true` **without requesting a network**.
3. If `A != ssid` and `A != ""`: `bindProcessToNetwork(null)` + `unregisterNetworkCallback(V)` (IllegalArgumentException is caught: "already unregistered") (`:623-634`).
4. Build `WifiNetworkSpecifier.Builder().setSsid(ssid)` with `setWpa2Passphrase` for type 0 or unknown and `setWpa3Passphrase` for 1 **and 2** (`:641-649`). Request = `NetworkRequest.Builder().addTransportType(TRANSPORT_WIFI).removeCapability(NET_CAPABILITY_INTERNET).setNetworkSpecifier(spec)` (`:650`). There is no BSSID pattern and no band.
5. `O = result`. `Q = RunnableC4802a(this,2)`. `requestNetwork(request, V)`. `postDelayed(Q, 60000)` (`:651-658`). The call uses the 2-arg `requestNetwork`, which has no framework timeout. Android shows its "connect to device" approval dialog unless this SSID was approved before **[inferred, platform behaviour]**.
6. Outcomes:
   - `V.onAvailable(network)`: remove `Q`, **`bindProcessToNetwork(network)`**, `A = B`, result `true`, `O = null` (`C4805d.java:31-49`).
   - `V.onUnavailable()`: unbind, unregister V, `A=""`. If `F==2`, log `"TransitionMode WPA3" "onUnavailable try WPA2"` and call `m6182n` (WPA2 retry). Otherwise result `false` (`C4805d.java:170-196`).
   - Timeout `Q` (60 s, `RunnableC4802a.java:57-75`): unbind, unregister V. If `F==2`, call `m6182n` (log `"TIMEOUT onUnavailable try WPA2"`). Otherwise error `("connectToWifi","TIMEOUT Connection timeout")`.
   - `V.onLost(network)`: remove `Q`, `bindProcessToNetwork(null)`, unregister V, `A=""`, `O?.success(false)` (`C4805d.java:120-142`). **After a successful connect `O` is already null, so Dart is never told the link was lost.**
7. `m6182n(ssid, pw)`, the WPA2 retry (`MainActivity.java:73-115`): unbind and unregister **W**; build the same request with `setWpa2Passphrase`; `requestNetwork(request, W)`; `Q = RunnableC4802a(this,0)` after 60 s. That timeout unbinds, unregisters W, and errors `("TIMEOUT","Connection timeout during WPA2 retry")`.
   - `W.onAvailable` behaves like V (bind process, `A=B`, `true`).
   - `W.onUnavailable` falls to the `default` branch (unbind, unregister, `false`).
   - **`W.onLost` and `W.onCapabilitiesChanged` fall into `default:` → only `super.onLost()`** (`C4805d.java:161-163`). There is no unbind, no unregister and no `A=""`.

`MainActivity` has **no** `onPause`/`onStop`/`onDestroy` override (the whole class is `MainActivity.java:16-116`). Callbacks are therefore not unregistered on background or destroy. The network request lives as long as the process (and the `MainActivity` instance it references). `launchMode="singleTop"`, and `configChanges` covers orientation/screenSize/etc. (`AndroidManifest.xml:91-94`), so rotation does not recreate the activity.

Platform facts that matter (AOSP `WifiNetworkFactory`, main branch; behaviour varies by OEM/version **[inferred]**):
- A request with a specifier is accepted only from a **foreground app or foreground service** ("Request not from foreground app or service. Rejecting"). A request from a foreground app overrides another app's active/connected request.
- A request with a specifier that also carries INTERNET is rejected. The app removes it, which is correct.
- The framework's own connection timeout is 30 s, with up to 3 connect retries (`NETWORK_CONNECTION_TIMEOUT_MS`, `USER_SELECTED_NETWORK_CONNECT_RETRY_MAX`). The app's 60 s timer is usually beaten by `onUnavailable`.
- When the request is released (unregister, or process death), the framework **disconnects and removes** the network (`teardownForConnectedNetwork`).
- `bindProcessToNetwork`: "if network ever disconnects, all Sockets created in this way will cease to work and all host name resolutions will fail."
- Registering a callback twice only logs "NetworkCallback was already registered". `unregisterNetworkCallback` releases every request mapped to the callback.

Manifest (`AndroidManifest.xml`):
- minSdk 31, targetSdk 36 (`:13-14`).
- Permissions: ACCESS_WIFI_STATE, CHANGE_WIFI_STATE, ACCESS_NETWORK_STATE, CHANGE_NETWORK_STATE, INTERNET, ACCESS_FINE/COARSE_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION, FOREGROUND_SERVICE_DATA_SYNC, WAKE_LOCK, RECEIVE_BOOT_COMPLETED, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, POST_NOTIFICATIONS, BLUETOOTH_SCAN/CONNECT. **No NEARBY_WIFI_DEVICES.**
- `usesCleartextTraffic="true"`.
- Services:
  - `com.pravera.flutter_foreground_task.service.ForegroundService`, `foregroundServiceType="dataSync"` (`:231-234`), meta `com.ricohimaging.grworld.service.STATUS_ICON`.
  - `com.baseflow.geolocator.GeolocatorLocationService`, `foregroundServiceType="location"` (`:454-458`).
- Receivers: `flutter_foreground_task` `RebootReceiver` (BOOT_COMPLETED/MY_PACKAGE_REPLACED/QUICKBOOT, exported) and `RestartReceiver`. `flutter_local_notifications` boot receiver. There is no Wi-Fi-related receiver.

---

## 4. Foreground services, Wi-Fi lock and wakelock (Dart)

**flutter_foreground_task options** are inlined constants in the toJson `0x835dec` (`add x3, NULL, #0x20` = true, `#0x30` = false):

| key | value |
|---|---|
| `autoRunOnBoot` | true (0x835e7c) |
| `autoRunOnMyPackageReplaced` | false (0x835eac) |
| `allowWakeLock` | true (0x835edc) |
| `allowWifiLock` | **true** (0x835f0c) |
| `allowAutoRestart` | true (0x835f3c) |
| `taskEventAction` | `{taskEventType: 1, taskEventInterval: <field>}` (0x835f6c; type 1 = presumably `nothing` **[inferred]**) |

- Started by `startService` (`pp+0x32160`, wrappers `0xdc143c` / `0xdc1770`, entry `0xdc1024`). Called only from the photo-transfer flows:
  - `0xdbc234` / `0xdbdd14`: camera "reserved transfer", log `予約転送処理エラー`.
  - `0xdbe510`.
  - `0xe3a278`: manual import; callers `PHm_ERb` / `QHm_HRb` closures.
- Stopped by `stopService` (pp+0x1dd8, `0xd493e8`) from the same flows and from `jLm_aRb` `0xd48b58`.
- Native: `ForegroundService.java:467` reads `allowWifiLock`. **So a WifiLock is held only during transfers.**
- `autoRunOnBoot=true` restarts the transfer service after reboot; it does nothing for the Wi-Fi session.

**geolocator foreground notification** (`0xd47214-0xd47264` → toJson `0x5924f0`):
- title `"位置情報送信"` (pp+0x274d0, "sending location").
- `enableWifiLock=false` (+0x17), `enableWakeLock=true` (+0x1b), `setOngoing=false`.
- Used for background location → camera over **BLE**.

**wakelock_plus** (screen-on only, no effect on Wi-Fi):
- `enable()` = `0x84b97c` (passes true), called from `0xdbc234`, `0xe3a278`, `0xdd2760`.
- `disable()` = `0x7e46b8`, called from `0xd90ffc`, `0xd913b0`, `0xdbc234`, `0xe3a278`.
- These are transfer and firmware/home screens **[inferred]** from the call sites.

---

## 5. Dart side: who calls the channel and what "connected" means

MethodChannel object: `Obj!MethodChannel@845371` (pp+0x1ff80).

| Dart fn | Channel call | Wrapper behaviour |
|---|---|---|
| `0xdda5c4` | `connectToWifi` | Args map {ssid,password,serialNo,model,bdName,securityType}. Logs `"Connection result: "`. A non-true result → ER_WF_001. A PlatformException whose text contains `"NEHotspotConfigurationErrorDomain Code=8"` → **ER_WF_007 InternalError (iOS)** (`0xdda87c`). Text containing `"timeout"` → **ER_WF_009 ConnectTimeoutError** (`0xdda900`). Anything else → ER_WF_001 (`0xdda92c`). **No Dart-side timeout.** |
| `0xd1b418` | `getConnectedSsid` | Failure → ER_WF_006 CheckSSIDError (lTb@865291). Always called through the retry helper. |
| `0xd45024` | `disconnectWifi` | Logs `"Disconnect result: "`. |
| `0xdd8e48` | `checkWifiState` | Logs `"Wi-Fi CheckStateError: "`. Called from `0xdd809c` (firmware step 2) and `0xe05cf8`, `0xe2d358`, `0xe47bd8`. |

**Retry helper** `0x5479e4` → loop `0xd1b0f4`. This looks like package:retry: named `NCi` = delay, default `la@8704a1` = **50 ms**; `OCi` = maxAttempts, default **3** (`0x547aac mov x5,#3`); `PCi`/`QCi`/`RCi` are optional predicates/callbacks. It delays with `Future.delayed` (0x4ad404) between attempts; a backoff multiplier is **[unknown]**.
- `getConnectedSsid` in the connect path: 3 × 50 ms (`0xddaab0`).
- `getConnectedSsid` in teardown: 3 × **100 ms** (`0xd44ef0`, `la@870441`).
- BLE writes: 3 × 50 ms (BLE slice).

**Connect orchestrator** `0xdd91ac` (class ILb; detail in `research/notes/ble/WlanChars.md` §3):
1. Load the registered device record, or throw ER_BL_001.
2. If connectivity contains `vpn` (Wxa@86cdd1), wait **1 s** (`0xdd9724`, la@870401) and throw ER_WF_010 VPNError.
3. Path by record kind (`0x58f270`; `BTb` cid 1242 = kind 0):
   - **kind 0 → `0xdda950`** (no BLE WLAN-on; **[inferred]** GR II / Wi-Fi-only):
     1. Optional BLE release (`0xd43cd4`/`0xd431f0`).
     2. `getConnectedSsid` (retry).
     3. Log `"get: <ssid>, <last>"`.
     4. Read prefs `lastConnectedDevice` / `lastConnectedWifi` (`0xd1e340`).
     5. If the phone is already on that SSID, go straight to `0xd1d508`. Otherwise call `connectToWifi` (`0xddaea0`) and then `0xd1d508` (`0xddae18`, `0xddaf40`).
   - **kind 1/2 → `0xdd9fe0`** (BLE models):
     1. BLE read of the WLAN characteristics (`0xd3e874`).
     2. Save `lastConnectedDevice`.
     3. BLE write `hJb=0x01` (camera WLAN ON) via `0xd419d0` (`0xdda1a0`).
     4. **Immediately** `connectToWifi` (`0xdda1e0`); there is no wait for the AP to come up. The native 30 s/60 s request window absorbs the AP boot time.
     5. `0xd1d508`.
   - Both paths run inside a cancelable wrapper (`0x56f82c`, closure `0x857390`).
4. Analytics: `success` / `connect_failure` / `vpn_failure` / `connect_timeout_failure` / `get_failure` / `wlan_router_failure` / `ios_internal_error` / `other_failure`, plus `"foreground"` / `"background"` from `isPaused` (`0xdd961c`, `0xdd9d54`).

**Post-join setup `0xd1d508`** ("connected to the camera" is decided here):
- `0xd28c9c` re-reads the SSID.
- `getPropertyData` (`GET /v1/props`) checks model and minimum firmware. A failure throws ER_WF_003.
- Opens the WebSocket (`0xd22098`): `WebSocketChannel.connect(Uri.parse("ws://192.168.0.1/v1/changes"))` (`0xd22114`, `0xd2211c`) with no protocols and no `pingInterval`. State becomes `connected` (KLb@867941, `0xd22198`). `listen(onData 0xd27770, onError 0x569a18, onDone 0x569938, cancelOnError: true)` (`0xd22234-0xd22248`). `onDone` sets state `disconnected` (KLb@867921) and logs closeCode/closeReason.

So "connected" =
1. native `requestNetwork` `onAvailable` (or the props pre-check),
2. the SSID matches (`getConnectedSsid`) for the kind-0 shortcut,
3. `GET /v1/props` succeeds,
4. the WebSocket is open.

After that, the WebSocket state is the liveness indicator.

**Dart HTTP client.** `package:http` with a **new Client per request**: `0xd3ac30` creates the client via `0x585624`/`0x5855e0`, sends, and closes it in `finally`. So there is no connection reuse; every call opens a new TCP connection. Per-call `Future.timeout` values: imgctrl 5 s, monthly log 10 s, ImageControl 10 s, endscreen 60 s, firmware prepare 60 s, firmware PUT 180 s (full table in http-api.md). The native channel HTTP uses `HttpURLConnection` with 3/10/15/120 s timeouts (§2).

---

## 6. Loss detection, background/foreground, teardown

**Listeners in the home view model** (`Lsn_MQb`):
- `0xbf51c8` on `connectivityStreamProvider` (pp+0x51f30, connectivity_plus; Android plugin `p034D6/C0221b.java` uses `registerDefaultNetworkCallback` **[inferred]**).
  - Logs `"ネットワーク状態が変化: prev → next"`.
  - Acts only if `next.first == ConnectivityResult.none` (Wxa@86cd51, `0xbf5470`) **and** the home state is variant `zQb` (cid 1350, `0xbf5524`).
  - Action: cleanup `0xdd39b8` (resets session providers) and a message `"Wifi接続が切断されました。"` (pp+0x51ee8, "Wi-Fi connection was lost").
  - Because the process is bound to a non-INTERNET local network, the reported list is usually `[wifi]`, or `[mobile]` when cellular stays up. **A camera-Wi-Fi loss while cellular is up is not `none`, so this listener does not fire [inferred].**
- `0xbf5750` on the "wifi isIgnore" flag. Logs `"wifi: isIgnore: … next: …"`. When the ignore flag clears **and** the WebSocket state is `disconnected` (KLb@867921, `0xbf5a24`) **and** the home state matches (`0x56afc8`), it runs cleanup `0xdd39b8` plus the same message. The BLE counterpart is `0xe86418` (`"ble: isIgnore:"`, `"Ble接続が切断されました。"`).
- `0xe851a4` (DeviceManager, WebSocket state change). If the transition is `connected → disconnected`, **`isPaused` is false** (`0xe8536c`) and flag `YBi` is true, it shows the info dialog `0xbf4988` (`images/icon/infoIcon.svg`). Every other case, including `isPaused == true`, branches to `0xe85408`. That code still checks `next == disconnected` (`0xe85418`) and runs the state update through closure `0xbf4ac8` (`0xe85430-0xe85470`). So in the background the loss is **recorded, and only the dialog is skipped**. Whether the dialog appears later on resume is **[unknown]**.
- `isPaused` is a global `StateProvider<bool>` (`Field ::.isPaused`, pp+0x274c8, static 0x141c). It is read by 16 sites (`0xe84c3c` camera power, `0xe855a4` BLE state, `0xe851a4`, `0xd2dc0c` / `0xd465b8` bg/auto-connect analytics, `0xd46f20` location). Its writer is the app's `AppLifecycleState` handler in `aRb` (inlined in the code blutter files under `0x547cc0`, 0x548320-0x5487a8): `resumed` (`Obj!laa@86f8e1`, pp+0x2a08) sets it false (0x5483e0) and `paused` (`Obj!laa@86f901`, pp+0x3c00) sets it true (0x5485a8) **[observed in code]**.
- **Background Wi-Fi release (found in code, Android build).** On `paused` the same handler, besides setting `isPaused`:
  1. Captures the `field_23` values of two notifiers (`IKi` → `XCb`, `KKi` → `ZCb`, 0x5485d4-0x548660) into the closure context. What they hold is **[unknown]**.
  2. If the bool provider `PBi` is true, calls 0x5487dc and sets `PBi` false (0x5486b0-0x548760). Neither is identified **[unknown]**.
  3. Schedules closure 0xd48694 with `Future(…)` (0x48e300). That closure runs `await Future.delayed(const Duration(seconds: 60), 0xd48b58)` (`Obj!la@870491` = 60 000 000 µs at pp+0xade8; `Future.delayed` = 0x4ad404) and logs `"切断失敗: $e"` ("disconnect failed") on an exception.
  4. After 60 s, 0xd48b58 returns without doing anything when the widget is gone, `isPaused` is false again (the app came back), either captured flag is true, or the int provider `VBi` is not 0 (0xd48c0c-0xd48c90). `VBi` and `WBi` are read by the photo transfer (0xdbdd14, which builds the `?size=xs` / `?size=full` requests) and its progress text `" (N/M)"` (0x99ef70), so they are presumably the transfer's counts **[inferred]**. Otherwise it awaits 0xd49450 on the `pBi` notifier, then `FlutterForegroundTask.stopService()` (`FRb` → 0x59294c → 0xd48dac, which throws `"The service is not started."`).
  5. 0xd49450 sets a busy flag (0x56d068 true), sets `VBi` and `WBi` to 0, and awaits the device manager's (`ILb`, via `WDi`) release 0xd43cd4: WLAN Control `00` over BLE (write errors logged as `"ble write error skip, "` and ignored), then teardown 0xd44ea0 (`disconnectWifi` when an SSID is connected, WebSocket close). It does **not** call 0xe1f2f8 / 0xd431f0, so the Bluetooth link stays (unlike the explicit disconnect 0xe1f068, [connect flow §3](grworld-connect-flow.md#3-disconnect-and-background-q6)), and Camera Power is not written.
  6. Back in 0xd48694, background-location housekeeping follows: 0xd48578 decides between 0xd2c284 (the `UPb` notifier with `"bgLocationLimit"` and `"Timer Set: N Hours."`) and 0xd1d0f0, and 0xd2c284 is skipped while a pairing or registration page (`SelectPage`, `BleConnection*Page`, `BleDevice*Page`, `WifiDevice*Page`) is current.

  The 60 s timer is not cancelled on `resumed`; the `isPaused` check at expiry is what stops it. Ricoh's GR WORLD FAQ (<https://www.ricoh-imaging.co.jp/english/support/qa/gr-world/>, read 2026-11-13) describes the result: on iOS the Wi-Fi is disconnected about a minute after the app goes to the background, interrupting a transfer; on Android a background transfer finishes and the Wi-Fi goes about a minute later. What re-arms the release after an Android transfer ends (the timer that expired during it skipped because `VBi` was not 0) was not found **[unknown]**. Everything here is from the Android build: Dart's `Platform` checks are folded at compile time, so a branch that only runs on Android would look unconditional here, and the iOS app's Dart code is not available. That iOS runs the same handler fits the FAQ's one minute but is **[inferred]**; so is whether a suspended iOS app gets to run the timer at all, which depends on what keeps GR WORLD awake in the background (its background location, or Bluetooth events).
- **The camera does not power itself off while an app is connected (found in documentation).** The GR IV user manual (Auto Power Off, p. 146; `work/manuals/gr4.txt`) lists "While the camera is connected to GR WORLD" among the cases where Auto Power Off is not available, beside image transfer and a computer connection. Whether a Bluetooth link alone counts, or only the Wi-Fi with a phone joined, is **[unknown]**; for a hardware test: leave a camera linked over Bluetooth only, with Auto Power Off at 1 min, and see whether it turns off.

**Teardown `0xd44ea0`:**
1. `getConnectedSsid` (3 × 100 ms).
2. If non-null, `disconnectWifi` (`0xd44f1c`).
3. Always close the WebSocket `0xd44f70` (state `disconnected`, close sink).

Callers:
- the BLE release routine `0xd43cd4`, which runs before writes for kind-0 records (`0xd44140`) and after a failed BLE write `"ble write error skip, "` (`0xd44340`, `0xd4436c`, `0xd44558`, `0xd44580`);
- power-off `0xe4c108`: `POST /v1/device/finish`, then WS close;
- the account flow `0xdeb86c` (`"アカウント操作前のWi-Fi切断失敗"`, "Wi-Fi disconnect before account operation failed": it drops camera Wi-Fi to reach the internet).

`0xd43cd4` also writes **`hJb=0x00` (camera WLAN OFF)** (`0xd441ec`, `0xd44414`). It is reached through `0xd431f0` from the BLE auto/background connect `0xd2e93c` (callers `0xd2dc0c` / `0xd465b8`, analytics `bg_connect_failure` / `auto_connect_failure`) and from `0xdda950`. Which devices are released (previous vs current) is **[inferred]** "other than the one being connected".

**Reconnect.** There is no timer or listener that rejoins Wi-Fi. `connectToWifi` runs only from user/feature flows (`0xdd91ac` callers `0xdd8fdc` firmware, `0xe07338`, `0xe47bd8`, `0xe49658`, `0xe499a0`). Pages: `/reconnect` (pp+0x90b0, `0xdabf24`; `"切断失敗:"` ("disconnect failed") in `0xd48694`), `/wifiDetect` (pp+0x83b8), `WifiDeviceDetectPage`, `WifiSettingPage`.

**Periodic timers** (none touch Wi-Fi):
- `0xd2b2d8`: `Timer.periodic(5 s)` (la@870431) → location write over BLE (`0xd2b5b4` → `0xd2b990`).
- `0xd4753c`: `"start timer N seconds."` with a user-chosen interval, `"write timer lastPosition"`.
- `0xdd606c`: 5 s during BLE scan.

---

## 7. Connection state machine (as implemented)

```
            ┌──────────── user starts a feature / firmware step2 / /reconnect ────────────┐
            ▼                                                                              │
 [IDLE] ─► [VPN_CHECK] ─vpn─► wait 1 s ─► ER_WF_010 ─────────────────────────────────────► [IDLE]
            │ ok
            ├─kind0─► [SSID_CHECK getConnectedSsid 3×50ms] ─same as lastConnectedWifi─┐
            │                    └─different/null─► [JOIN]                             │
            └─kind1/2─► [BLE_READ_WLAN] ─► [BLE_WRITE hJb=1 (3×50ms, ER_BL_005)] ─► [JOIN]
 [JOIN] native: precheck GET /v1/props 3s+3s (blocks UI thread)
        ├─ok──────────────────────────────────────────────────────────────────────────►[SETUP]
        └─requestNetwork(V) ── onAvailable ─► bindProcess ─────────────────────────────►[SETUP]
                │ onUnavailable / 60 s
                ├─ securityType==2 ─► requestNetwork(W, WPA2) ─ onAvailable ─► bind ──►[SETUP]
                │                         └─ onUnavailable/60 s ─► false / TIMEOUT ─► [IDLE] (ER_WF_001/009)
                └─ else ─► false / TIMEOUT ─► [IDLE] (ER_WF_001/009)
 [SETUP] 0xd1d508: GET /v1/props (model/fw check, ER_WF_003) ─► WS connect ─► [CONNECTED]
 [CONNECTED]  no keepalive; WS idle (GR III/IV), HTTP on demand (new TCP each call)
   ├─ V.onLost ─► native unbind+unregister, Dart NOT notified ─► (WS onDone) ─► [LOST]
   ├─ W.onLost ─► nothing (process stays bound to dead network) ─► (WS onDone) ─► [LOST]
   ├─ WS onDone/close ─► state=disconnected ─► state update 0xbf4ac8 (always); dialog only if !isPaused && YBi ─► [LOST]
   ├─ connectivity first==none && state zQb ─► cleanup + "Wifi接続が切断されました。" ─► [LOST]
   ├─ BLE release (auto/bg connect, power off, account op) ─► hJb=0 + disconnectWifi + WS close ─► [IDLE]
   └─ process death ─► framework releases request ─► AP disconnected ─► (next launch) [IDLE]
 [LOST] ─► cleanup 0xdd39b8 ─► [IDLE]  (no automatic rejoin)
```

Timeouts: pre-check 3 s + 3 s. Join 60 s, or 120 s with the WPA2 fallback (framework: 30 s × up to 3 retries inside). getConnectedSsid 1 s × 3 attempts. VPN delay 1 s. No keepalive interval exists.

---

## 8. Disconnect mechanisms and hypotheses (not a measured likelihood ranking)

| # | Cause | Evidence | Status |
|---|---|---|---|
| 1 | **Idle-session hypothesis, not a demonstrated cause.** The app sends no periodic Wi-Fi traffic. Firmware registers `/v1/ping`, but its handler reads camera datetime rather than explicitly resetting an idle timer. Neither observation establishes an AP inactivity threshold or proves that polling prevents shutdown. Ricoh's own Image Sync app does poll: an uncached `GET /v1/props` every 500 ms for the whole Wi-Fi session, declaring loss only after ≥3 consecutive failures and ≥40 s without success ([Image Sync connection §2](connection-imagesync.md#2-liveness-keep-alive-disconnect-detection-reconnect)). Ricoh shipping that design suggests the camera handles a 2 Hz poll **[inferred]**; it does not show the poll prevents drops. | App timer evidence §6; firmware `gr3-webapid-ping.json`, `gr4-webapid-ping.json`; Image Sync `impl/ConnectionChecker.java:12-104` | absent app heartbeat observed; camera idle policy **[unknown]** |
| 2 | **The process gets backgrounded and killed, so the network request is released and Android disconnects the AP.** The request is owned by `MainActivity` fields with no foreground service; the `dataSync` FGS/WifiLock exist only during transfers; the location FGS has `enableWifiLock=false`. OEM battery managers kill or freeze such processes, and Wi-Fi can go into power save with the screen off (no WifiLock). | `MainActivity.java:16-116`, FGS start sites §4, `0xd47248` | observed structure; consequence **[inferred]** |
| 3 | **The app turns the camera WLAN off itself.** The BLE release routine writes `hJb=0x00` and calls `disconnectWifi` + WS close. It runs from the BLE background/auto-connect path (`0xd2e93c` → `0xd431f0` → `0xd43cd4`), e.g. when the BLE link to the camera blips and auto-connect kicks in while the user is on Wi-Fi. | `0xd441ec`, `0xd44414`, `0xd44140`, `0xd44340` | writes observed; trigger timing **[inferred]** |
| 4 | **Unhandled / silent `onLost`.** For V, native unbinds and unregisters without notifying Dart; there is no rejoin, and Dart learns only via WS `onDone`. For the WPA2 fallback W, `onLost` does nothing: the process stays bound to a dead `Network`, so *all* sockets (camera and cloud) fail until the next `connectToWifi`/`disconnectWifi`, and `A` keeps the stale SSID. | `C4805d.java:120-142`, `:161-163` | observed |
| 5 | **Loss is missed or surfaced late.** The connectivity listener reacts only to `first==none`, which does not happen when cellular is up, so a camera-Wi-Fi loss is caught only through the WebSocket closing. While backgrounded, a WebSocket close updates state but shows no dialog (`0xe8536c` → `0xe85408`). This makes the user experience worse; it does not cause drops. | `0xbf5470`, `0xe8536c`, `0xe85418-0xe85470` | observed; UX effect **[inferred]** |
| 6 | **`disconnectWifi` only releases V.** After a WPA2-fallback join, W stays requested (the camera link is kept) while the process is unbound. Dart HTTP then goes out the default network and fails, which looks like a disconnect. | `:1207` | observed |
| 7 | **A foreground request from another app overrides ours** (another camera/IoT app, or Android's own Wi-Fi picker); and a new request from GR WORLD while backgrounded is rejected. Specifier connections on single-STA phones also take over the primary Wi-Fi, and the user switching networks tears it down. | AOSP `WifiNetworkFactory` `canNewRequestOverrideExistingRequest`, "Request not from foreground app or service" | platform **[inferred]** |
| 8 | **WLAN-on → join race.** `connectToWifi` is called right after `hJb=1` with no wait for the AP beacon. On slow AP start it relies on framework retries; the WPA3 attempt may fail and fall back after up to 60 s. Shows up as connect failures rather than drops. | `0xdda1a0` → `0xdda1e0` | observed |
| 9 | **The pre-check blocks the main thread** (`Thread.join`, up to ~6 s). Not a disconnect itself, but it can stall UI and lifecycle and trip ANR on top of other work. | `AbstractActivityC0655d.java:607-609` | observed |
| 10 | **VPN.** GR WORLD refuses to join while any VPN is up (ER_WF_010). On Android a VPN that apps cannot bypass does not route camera traffic away: Android refuses the process binding itself. Observed 2026-11-09 (Android 17 phone, GR IV HDF, Tailscale with `bypassable=false` and GR Photo's app ID inside its range): after Tailscale came up, every join completed association and DHCP, then `bindProcessToNetwork` returned false, so no camera traffic was possible. | `0xdd9724`; UI text pp+0x68ad8; GR Photo debug log and `dumpsys connectivity` | observed |

---

## 9. Recommendations for a robust client

### Android
- Own the session in a **foreground service** (`connectedDevice` type, Android 14+ permission `FOREGROUND_SERVICE_CONNECTED_DEVICE`). Start it from the foreground, then call `requestNetwork(specifier, callback, handler)` from the service. Keep one `NetworkCallback` registered for the whole session and unregister only on an explicit user disconnect.
- **Do not `bindProcessToNetwork`.** Bind per socket with `network.socketFactory`, `network.openConnection(url)`, or OkHttp `.socketFactory(network.socketFactory)`. For Dart/Flutter, route camera HTTP through a native client bound to the `Network`, or bind briefly and restore. The internet keeps working and a lost network cannot poison every socket.
- Handle `onLost` / `onUnavailable` uniformly for every attempt (WPA3, WPA2 fallback). Emit an event to the UI; do not just unbind. Then rejoin with backoff (e.g. 1 s, 2 s, 5 s, 10 s, capped), while BLE stays connected to re-issue WLAN-on.
- Hold a `WifiManager.WifiLock` (`WIFI_MODE_FULL_LOW_LATENCY` on 29+, or `FULL_HIGH_PERF`) for the whole session, plus a partial wakelock only during transfers. Ask for battery-optimisation exemption (the app already declares `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).
- Use `WifiNetworkSpecifier` with `setSsid`. A BSSID does **not** skip scans: AOSP `WifiNetworkFactory.triggerConnectIfUserApprovedMatchFound` connects an approved single-AP request only once a scan result matches. The factory scans when a request arrives and then periodically (AOSP 10 s; 17.5 s observed on an Android 17 phone, 2026-11-08), so a camera AP that comes up just after the first scan waits for the next one; filing the request again starts a new scan (see the GR Photo app's `WifiChannel`). Pick the passphrase type from BLE `security` (0 WPA2, 1 WPA3, 2 transition → try WPA3, then WPA2). Treat an approval-dialog rejection (`onUnavailable` within seconds) separately from timeouts.
- **VPN.** While a VPN that apps cannot bypass carries the app's traffic, netd allows the app no other network, so `bindProcessToNetwork` returns false (AOSP netd `checkUserNetworkAccess`; observed, §8 row 10). Per-socket binding (`Network.bindSocket`) goes through the same netd check **[inferred]**, so no app-side route exists: the user has to exclude the app in the VPN's settings or turn the VPN off. Apps cannot tell a bypassable VPN from one that is not (`VpnTransportInfo.isBypassable` is a system API), and `bindProcessToNetwork` also returns false for a network that is gone, so a refused bind is not proof of a VPN. GR Photo therefore checks only after a refused bind: if the camera network still has capabilities and `getActiveNetwork` (which returns a VPN only when it applies to the app) is a VPN, it reports `vpnSuspected`; the session keeps retrying and the app shows its VPN hint only when the join ends on that suspicion **\[design\]**. GR WORLD's up-front check reads the same `getActiveNetwork` capabilities (connectivity plugin `check`: `p009A7/C0049a.java:488-489`, VPN transport → `vpn` at `p177U5/C1728c.java:114-115`), so a VPN that excludes the app passes it, but it also refuses joins under VPNs that apply to the app and allow bypass, where binding would work.
- After BLE `hJb=0x01`, wait for the AP: poll scan results for the SSID, or just rely on the specifier request, but give it ≥30 s before falling back.
- Never write `hJb=0x00` or disconnect Wi-Fi as a side effect of BLE auto-reconnect. Keep BLE and Wi-Fi state machines independent: a BLE blip must not tear down Wi-Fi.
- Do network work off the main thread (no `Thread.join` on the UI thread).
- **GR Photo's downloads while the app is not in front \[design\].** While the download queue has work for the connected camera, GR Photo runs a `connectedDevice` foreground service (`app/android/app/src/main/kotlin/io/jeph/grphoto/DownloadService.kt`), so that Android does not freeze or kill the process and with it release the network request. `dataSync`, which GR WORLD uses (§4), is limited to six hours a day from Android 15 (Android documentation, foreground service types). The service does no camera work: the Dart download queue runs as before and tells it what to show, a notification with the progress, Pause or Resume, and Cancel all. It holds a partial wake lock while a file transfers and none while the queue is paused, and takes no `WifiLock`: `WIFI_MODE_FULL_HIGH_PERF` is deprecated and `WIFI_MODE_FULL_LOW_LATENCY` only applies while the app is in front with the screen on (Android documentation, `WifiManager`). The service stops with the task, so swiping GR Photo away ends the downloads; they stay queued and start again on the next connection. Android only starts a foreground service for an app in front, which holds here because the queue starts from a tap in the Library or on a connection the user opened. Observed 2026-11-11 on an Android 16 emulator with the simulated camera (no real camera network): after leaving the app and with the screen off the process stayed in the foreground-service state and shots kept arriving; Pause, Resume and Cancel all worked from the notification with the app in the background; a paused queue held no wake lock. Whether the camera network itself stays up through a long download with the screen off is **unknown** (open question 11).

### iOS
- Use `NEHotspotConfiguration(ssid:passphrase:isWEP:false)` with `joinOnce = false`, so the configuration persists while the app is backgrounded (`joinOnce = true` drops it when the app suspends). Handle `NEHotspotConfigurationErrorDomain` codes:
  - 13 alreadyAssociated = success
  - 7 userDenied
  - 8 internal: the app's ER_WF_007; retry after toggling, and tell the user to remove the camera from "My Networks", as the app's help text pp+0x69488 suggests.
- After `apply`, verify with `NEHotspotNetwork.fetchCurrent` (needs location permission) and an HTTP probe of `/v1/props`.
- Add `NSLocalNetworkUsageDescription` and trigger the local-network prompt early.
- iOS keeps no app sockets alive in the background; plan to reconnect on `didBecomeActive`. BLE background mode (`bluetooth-central`) can keep the camera awake and re-enable WLAN.
- Whether a VPN on iOS blocks camera traffic after an `NEHotspotConfiguration` join is **unknown**: iOS has no process-binding step that could be refused, and GR Photo has no iOS VPN check. GR WORLD's ER_WF_010 check runs in its Dart code, shared by both platforms (found in code); whether its connectivity plugin reports a VPN on iOS was not checked. Listed for a hardware test (open question 9).
- **GR Photo's downloads while the app is not in front \[design\].** On iOS 26 and later a running download queue is a continued processing task (`BGContinuedProcessingTask`, `app/ios/Runner/BackgroundDownloadsPlugin.swift`): the app keeps running in the background, and the system shows the task as a Live Activity with the title, subtitle and progress GR Photo gives it and a stop button. The task is asked for when the queue starts, with the app in front, as the API requires, and with the `fail` strategy, so a task the system cannot start at once is not queued behind others. Stop and the system taking the time away both arrive as the task's expiration handler, and GR Photo then pauses the queue; a paused queue ends the task, since the system UI has no paused state. The identifier is static, `<bundle ID>.downloads`, listed in `BGTaskSchedulerPermittedIdentifiers`, and its handler is registered on first use, which the SDK allows for this task type only (`BGTaskScheduler.h`; WWDC25 session 227). GR Photo declares no `UIBackgroundModes` entry: Apple's article "Performing long-running tasks on iOS and iPadOS" and the session name none for this task, but the SDK lists a missing mode among the causes of `BGTaskSchedulerErrorCodeNotPermitted`, so whether one is needed is **unknown** until a device run (a refusal is in the debug log as `BGTaskSchedulerErrorDomain 3`). Older iOS, and a refused task, get `beginBackgroundTask` time only. Observed 2026-11-11 on an iOS 26.5 simulator with the simulated camera: the request failed with `BGTaskSchedulerErrorDomain 1` (unavailable; the simulator does not support background processing), so only the fallback ran. Downloads went on for about 30 s after the app left the screen, the app was then suspended, and when it came back the queue carried on and finished with no failed download. The simulated camera is reached over loopback; whether a transfer from a real camera survives suspension is **unknown**. The continued processing task has not run anywhere yet (open question 10).

### Windows
- Join with WinRT `WiFiAdapter.ConnectAsync(network, WiFiReconnectionKind.Automatic, PasswordCredential)` or Native Wifi `WlanConnect` with a temporary profile, after `WlanScan` waits for the SSID.
- Subscribe to `NetworkInformation.NetworkStatusChanged` / `WlanRegisterNotification` (`wlan_notification_acm_disconnected`) for loss.
- If Ethernet or another Wi-Fi is present, add a host route to 192.168.0.1 via the camera interface, or bind sockets to its interface IP. Disable adapter power saving for the session where possible.

### macOS
- Join with CoreWLAN `CWInterface.associate(to:password:)` (needs location authorization for SSID visibility). Watch `CWEventDelegate.linkDidChangeForWiFiInterface` and `ssidDidChange`.
- The camera subnet route is automatic on the Wi-Fi interface. If the Mac prefers Ethernet for default, bind to `en0`'s address or use `NWParameters.requiredInterface`.

### All platforms
- **Liveness probes, not a proven keep-awake fix:** keep the WebSocket open and poll `GET /v1/props` while actively connected. Ricoh's Image Sync polls it every 500 ms with a 1 s connect timeout and treats the link as lost only after ≥3 consecutive failures and ≥40 s without success; it also reopens the WebSocket immediately on failure ([Image Sync connection](connection-imagesync.md)). Start from that design and measure on hardware whether a slower cadence (e.g. 2–5 s) is enough **[design choice]**. Firmware also registers `/v1/ping` on the analyzed GR III/IV builds; validate its response and model support before using it. Do not assume `/v1/status/device` exists on these models. Retry a failed socket and check network reachability before tearing down/rejoining Wi-Fi: a WebSocket close or HTTP socket expiry alone does not prove the AP disappeared.
- Reuse one HTTP connection (keep-alive) instead of a client per request.
- Use explicit timeouts: connect 3 s, read 10 s, downloads by idle timeout.
- If the camera's Wi-Fi auto-off is configurable over BLE/HTTP, read it and warn the user.
- Keep BLE connected during the Wi-Fi session where the model supports it, so the client can re-issue WLAN-on (`hJb=0x01`) after a camera-side AP shutdown and rejoin without user action.

### What GR Photo does

All of this is GR Photo's choice **[design]** (2026-11-11). Its effect on the camera's battery has not been measured. It is meant to ask no more of the camera's battery than the link needs.

- **Liveness probe.** While the Wi-Fi is up, GR Photo sends `GET /v1/ping` every 5 s (1 s connect, 10 s read) and applies Image Sync's loss rule (≥3 consecutive failures and ≥40 s without an answer). A loss is found 40–45 s after the last answer (45 s when every probe runs into its read timeout), against 40–42 s at Image Sync's 500 ms. Until 2026-11-11 it polled `GET /v1/props` every 500 ms as Image Sync does; that poll fed Image Sync's settings screen, which GR Photo does not need, and the GR IV builds each `/v1/props` answer from its status, parameters, device, lens and supported-value lists ([remote shooting §4.2](remote-shooting.md)), where the ping handler only reads the camera clock (found in code, [firmware inventory](../firmware-protocol-inventory.md#additional-route-verification)).
- **A GR IV answers `/v1/ping`** (observed: GR IV HDF, fw 1.20, 2026-11-11, camera in playback, GR Photo on an Android phone). Every probe got HTTP 200 with `{"errCode": 200, "errMsg": "OK", "datetime": "2026-11-11T12:00:00"}` (the camera's clock without a zone) in 12–75 ms, and when the phone lost the camera's network the rule declared the loss 42 s after the last answer ([hardware results](../hardware-validation.md#4-results-log)). So `/v1/ping` is GR Photo's only probe: an answer that is an error, or is not a JSON object, fails the probe as no answer does. Until this was seen, a camera that refused a ping was probed with `/v1/props` for the rest of that Wi-Fi link; that fallback is gone. A GR III/IIIx registers the route too (found in code) but has not been tried: one that refused pings would be taken for lost after 40 s and rejoined, over and over **[inferred]** (open question 12). Whether pings, or any traffic, change the camera's auto power-off or its access point's lifetime is **[unknown]** (open question 1).
- **`/v1/props` is read when something is expected to have changed**: once when a join is verified (as GR WORLD, §5), after a `battery` or `storage` change on the WebSocket, once a second by live view while it streams and after a setting it changed, and once to check the camera after a request failed or during recovery.
- **Disconnecting turns the camera's Wi-Fi off.** Ending a session (disconnect, switching or forgetting a camera) writes WLAN Control `00` over BLE before the link is closed, as GR WORLD's release does (§6), whenever the camera is linked and on, whether or not that session turned the Wi-Fi on: a session that ended without closing (the app was stopped) leaves it on, and nothing else turns it off. Leaving the Wi-Fi for lack of use already did the same. Nothing is written when GR Photo turns the camera off instead, when the camera is off, or when the BLE link is already gone; how long the camera then keeps its access point up is **[unknown]** (open question 1).
- **On iOS the camera's Wi-Fi is left soon after the app goes off screen** \[design\] (2026-11-13). A suspended iOS app runs no code, and a terminated one gets no call, so neither GR Photo's idle timer nor its teardown can run; the persistent `NEHotspotConfiguration` (`joinOnce = false`, iOS above) keeps the phone on the camera's network, and nothing writes WLAN Control `00`. A tester's GR IV stayed on with its Wi-Fi and Bluetooth icons lit for hours while the phone was locked and the reopened app showed it offline (reported 2026-11-13, no log; that iOS had ended the app is **[inferred]**). So once the app is off screen (Flutter's `hidden`/`paused`), `IdleDisconnect` asks iOS for background time (`beginBackgroundTask`, `WifiPlugin.swift`) and leaves the Wi-Fi, or stops a join still under way (`apply` installs the configuration before the phone has associated), through the usual stop (network removal, then WLAN `00`, or Camera Power `00` for a camera GR Photo woke, on the Cameras screen), 20 s later, or 8 s before the background time iOS reported runs out when that is sooner; the trace shows `backgroundTime` and `wifi.stop` with reason `background`. The download queue's `BGContinuedProcessingTask` (iOS 26+) keeps the Wi-Fi for as long as it runs, also in the moment between two downloads when no job holds it. Until 2026-11-13 only a running job kept it, and that moment cut queues off: on an iPhone with a GR IV HDF (fw 1.20), the trace shows the task running and photos downloading with the app off screen, then `wifi.stop` with reason `background` right after a photo was saved, 20 s after the app left the screen, and the task ended with the queue unfinished **[observed]** (2026-11-13); when the queue ends or iOS expires the task, the Wi-Fi is left first and the task ended after (`DownloadBackground`), and an expiring task starts a short background task to cover that. Older iOS, or a refused task, gets no exemption: the queue is cut off at the same 20 s and waits for the camera. At start-up `forgetLeftovers` removes every configuration `getConfiguredSSIDs` reports for the app, since a run iOS ended cannot have removed its own. This is GR WORLD's background release (§6) with 20 s instead of 60 s, since iOS gives about 30 s **[inferred from Apple's documentation, not measured]**. Android keeps the auto-disconnect timer only: its join is a `NetworkRequest` of the app's process, which ends with it. Not covered: Bluetooth stays linked (iOS state restoration keeps the link for an ended app), and whether a Bluetooth link alone stops the camera's Auto Power Off is **[unknown]** (above, and open question 15).
- **Live view stops when the app is hidden** (the phone locked or another app in front; Flutter's `hidden` and `paused` states on Android and iOS) and starts again on return. A system sheet over the app (`inactive`) does not stop it. The Wi-Fi stays up, and the time after which GR Photo leaves unused Wi-Fi counts from the stop. Before 2026-11-11 the stream ran for as long as the app's process did, which on Android is long after the screen locks. Image Sync goes further and turns the camera's Wi-Fi off 60 s after it goes to the background ([Image Sync connection](connection-imagesync.md)).
- **A lost Wi-Fi is got back unless the camera turned off.** While a page uses the Wi-Fi (the Library, live view, a running download), a loss found by the liveness probe, the phone's network report or a failed request is repaired by WLAN Control `01` over BLE and a rejoin, without asking the user. A camera that turned off (Camera Power `00` notified, or Operation Mode `02` on the BLE link that returned) is left off instead: the page says the camera is off and offers to turn it on, which also joins its Wi-Fi again. Until 2026-11-11 the recovery turned such a camera back on by itself. Evidence and what is still unknown: [GR WORLD power-on §8](power-on-grworld.md#8-gr-photo-link-drops-at-power-changes). Android and iOS share this code; the platforms differ only in how the phone reports the network gone.
- **The map's requests leave by the phone's internet connection, not the camera's Wi-Fi** (2026-11-12). The viewer's map of where a photo was taken fetches its tiles from `tiles.openfreemap.org`, usually while the camera's Wi-Fi is joined; it is GR Photo's only traffic that is not for a camera. On Android the whole process is bound to the camera's network (§3), where those requests would fail, so before the first map GR Photo gives MapLibre an OkHttp client that makes every socket and name lookup on `ConnectivityManager.getActiveNetwork()` (`Network.getSocketFactory()`, `Network.getAllByName()`; `MapNetwork.kt` in the app). That the active network stays the phone's internet connection while the camera is joined is **[inferred]** from Android's documentation: the camera's network is requested with `NET_CAPABILITY_INTERNET` removed (§3), so Android does not make it the default, and `bindProcessToNetwork` changes only where this process's unbound sockets go. With no default network the requests fail at once and the map shows its empty ground. On iOS nothing is done: that iOS keeps internet traffic off a Wi-Fi it joined with `NEHotspotConfiguration` and found to have no internet is **[inferred]**. Seen so far only on an Android emulator with the simulated camera, where no network is bound and the tiles load; both platforms with a real camera are **[unknown]** (open question 14).

---

## Camera-firmware cross-check

See [firmware inventory](../firmware-protocol-inventory.md) for exact image hashes and saved REA evidence. These are static findings, not observed disconnects:

- GR IV `WlanCommandHandler::RecvChangeWlanRunningState` calls `WlanDevice::Stop` for mode `0`; nonzero requests call `Start`. `WlanDevice::Stop` builds a `stop_wlan.sh` command. This establishes an explicit camera-side shutdown path, not the policy that decides when to send it (`gr4-netmgr-wlan-request.json`, `gr4-netmgr-device-stop.json`).
- GR IV `start_wlan.sh` starts hostapd, assigns `192.168.0.1/24` to `uap0`, starts DHCP, and polls hostapd's control interface up to 30 times with 100 ms sleeps. That is a startup readiness check, **not an idle timeout**, and `PONG` does not prove a phone has associated.
- `/v1/changes` close handling removes the socket and invokes registered callbacks. One GR IV firmware-update callback cancels an active update. No general AP-shutdown-on-WebSocket-close contract was established (`gr4-webapid-close.json`, `gr4-webapid-fw-ws-callback.json`).
- GR III webapid has Crow HTTP deadline/idle-object cleanup code. HTTP socket lifetime, WebSocket lifetime, AP lifetime, and camera power state must remain separate client states (`gr3-http-deadline.json`, `gr3-http-idle-delete.json`).
- Camera auto-power-off thresholds and indirect effects of ping remain unresolved. The firmware findings do **not** justify promoting missing heartbeats to a confirmed disconnect cause.
- The [network configuration report](../firmware-network-config.md) finds a one-hour DHCP lease and GR IV driver PS/deep-sleep settings, but neither is an AP idle-off timer. No numeric AP inactivity override was found in the inspected templates/scripts or recovered GR IV config edits; compiled defaults and RTOS policy remain outside that bounded negative finding.

## Evidence

- Channel registration and handlers: `AbstractActivityC0655d.java:516-1395` (connectToWifi 582-666, getConnectedSsid 537-565, putWifiInfo 568-579, postCameraPower 669-673, checkWifiState 676-681, disconnectWifi 1191-1216, getDeviceStatus 1219-1223, getPropertyData 1226-1230, photo methods 684-1389); widget channel 1617.
- Callbacks: `p403v6/C4805d.java:28-244`. Timeouts: `p403v6/RunnableC4802a.java:24-77`. WPA2 retry: `MainActivity.java:73-115`. Fields: `MainActivity.java:19-70`.
- Pre-check: `p168T4/RunnableC1626F.java:111-150`. Power off: `p308k6/RunnableC3963a.java:73-95`. putWifiInfo: `p062H0/RunnableC0391f.java:340-367`. FGS options read: `ForegroundService.java:467`.
- Manifest: `AndroidManifest.xml:5-45` (SDK/permissions), `:91-94` (activity), `:170-180`, `:231-234`, `:282-295`, `:454-458`.
- Dart channel calls: `0xdda5c4` (pp+0x2b250 `connectToWifi`, 0x2b278 NEHotspot…, 0x2b280 `timeout`); `0xd1b418` (pp+0x1ff88 `getConnectedSsid`); `0xd45024` (pp+0x29680); `0xdd8e48` (pp+0x2b4d0); `0xd1e340` (pp+0x27d30, 0x279f0).
- Error enum lTb: ER_WF_001 pp+0x2b178, 003 pp+0x27b38, 006 pp+0x1ff90, 007 pp+0x2b1b0 ("Internal Error(iOS)"), 009 pp+0x2b190, 010 pp+0x2b148. Security enum qJb: wpa2 pp+0x1a1f8, wpa3/transition pp+0x2a8d8 / 0x2a8e8; list pp+0x2b130.
- Retry helper: `0x5479e4` (defaults 0x547a3c la@8704a1 = 50 ms, 0x547aac maxAttempts 3), loop `0xd1b0f4`. Teardown use: `0xd44ef0` (la@870441 = 100 ms).
- Orchestrator `0xdd91ac` (VPN 0xdd9724, path select 0xdd93a0, analytics 0xdd9b54-0xdd9cac, isPaused 0xdd961c). Paths `0xdda950`, `0xdd9fe0` (WLAN-on 0xdda19c-0xdda1a0, join 0xdda1e0). Setup `0xd1d508`. WebSocket `0xd22098` (pp+0x28430; states KLb connected pp+0x28438, disconnected pp+0x28468; onDone 0x569938; close 0xd44f70).
- Teardown `0xd44ea0`. Release `0xd43cd4` (BTb cid 1242 check 0xd4412c, WLAN off 0xd441ec / 0xd44414, error skip pp+0x295c0). `0xd431f0` ← `0xd2e93c` (auto/bg connect) ← `0xd2dc0c` / `0xd465b8`.
- Listeners: `0xbf51c8` (pp+0x51ef0, none check 0xbf5470, cid 0x546 0xbf5524), `0xbf5750` (pp+0x51f00, 0xbf5a24), `0xe86418` (BLE), `0xe851a4` (isPaused 0xe8536c skips only the dialog 0xbf4988; state update 0xe85418-0xe85470 via closure 0xbf4ac8). Cleanup `0xdd39b8`. isPaused pp+0x274c8.
- FGS options `0x835dec` (bools 0x835e7c-0x835f3c), event action `0x835f6c`. Start path `0xdc1024` → `0xdc1298` → `0xdc143c`. Geolocator config `0xd47214-0xd47264`, toJson `0x5924f0`. Wakelock `0x84b97c` (enable), `0x7e46b8` (disable).
- Timers: `0xd2b2d8` (5 s, pp+0x284d8), `0xd4753c`, `0xdd606c`. HTTP client per request: `0xd3ac30` (`0x585624`, `0x5855e0`).
- Strings: pp+0x51ee8 "Wifi接続が切断されました。", pp+0x51ee0 "Ble接続が切断されました。", pp+0x698b8 "WLAN connection has been lost.", pp+0x69488 (iOS "My Networks" advice), pp+0x68ad8 (VPN), pp+0x83b8 `/wifiDetect`, pp+0x90b0 `/reconnect`.
- AOSP (platform behaviour, main branch): `WifiNetworkFactory.java` (foreground check ~L810, override rules ~L704-724, INTERNET rejection ~L730, release/teardown ~L956-986, `NETWORK_CONNECTION_TIMEOUT_MS=30000`, retries 3); `ConnectivityManager.java` (duplicate register only logs ~L4757; unregister releases all ~L5570-5600; `bindProcessToNetwork` javadoc ~L5880).

## Open questions (confirm with a live capture)

1. Camera WLAN idle/auto-power-off: after how long with (a) the WS open and idle, (b) no TCP at all, (c) BLE connected? Does an open WebSocket count as activity? Capture over Wi-Fi with a sniffer, plus a BLE sniff for WLAN-state notifications.
2. Does the camera send WS pings or close frames before shutting the AP? What close codes?
3. On a real Android device, after `onLost`, logcat `WifiNetworkFactory`/`ConnectivityService`: what released the request (app background, user, override, AP gone)? Does the framework reconnect while the request is still registered?
4. When does `0xd2e93c` (BLE auto/bg connect) actually run while a Wi-Fi session is active, and does it write `hJb=0x00` to the connected camera? Confirm with a BLE capture during a deliberate BLE link drop.
5. The exact writer of `isPaused` and the meaning of flags `YBi` / "isIgnore" and of state variant `zQb` (cid 1350): which screens set "ignore"?
6. `taskEventType: 1` mapping in this flutter_foreground_task version, and whether the transfer FGS keeps running after a transfer ends.
7. iOS native implementation (not in this APK): `joinOnce` setting and how `getConnectedSsid` / `disconnectWifi` are done (`NEHotspotNetwork.fetchCurrent`, `removeConfiguration`).
8. How long the AP takes to beacon after BLE `hJb=0x01`, per model; and whether WPA3 SAE succeeds on common Android phones for securityType 2.
9. iOS with a VPN (for example Tailscale) on: does a GR Photo join reach `192.168.0.1`, with and without the VPN routing the camera's subnet? If it fails, what does the app see?
10. GR Photo on an iPhone with iOS 26 or later and a camera: does the continued processing task start without a `UIBackgroundModes` entry, does the Live Activity show on the Lock Screen and in the Dynamic Island, does the transfer keep going over the camera's Wi-Fi with the app in the background and the phone locked, and what does the app see when the user stops the task or iOS expires it? On older iOS, what happens to a transfer cut off by suspension when the app returns? Partly answered 2026-11-13 (iPhone, GR IV HDF, fw 1.20, debug log): the task started without a `UIBackgroundModes` entry, and downloads went on over the camera's Wi-Fi with the app off screen **[observed]**; the Live Activity, the stop button and expiry are not in the log.
11. GR Photo on an Android phone and a camera: with the download foreground service running, does the camera network stay up through a download of several minutes with the screen off and the phone unplugged (Doze, the maker's battery manager)?
12. `GET /v1/ping` on a GR III/IIIx: HTTP status and body, and whether GR Photo's 5 s probes are answered. A GR IV HDF answers them in playback (2026-11-11, §9 "What GR Photo does"); a GR IV in capture has not been tried. With the Wi-Fi up and nothing else running, does the camera power off by itself sooner, later or the same under 5 s pings, under `/v1/props` every 500 ms and with no probe at all?
13. After GR Photo disconnects: does the camera's Wi-Fi indicator go out at the WLAN Control `00` write? And when the write cannot be made (the app is stopped while the Wi-Fi is up), how long does the camera keep its access point?
14. The viewer's map while a real camera's Wi-Fi is joined (§9 "What GR Photo does"): on an Android phone and on an iPhone, do the tiles from `tiles.openfreemap.org` load with mobile data on, and with a second Wi-Fi kept beside the camera's where the phone can do that? With mobile data off, does the map stay empty without disturbing the camera link? On Android, which network does `getActiveNetwork()` name then?
15. GR Photo on an iPhone with debug logging on, the Library open: lock the phone and wait a minute. Is the camera's Wi-Fi indicator out about 20 s after locking, how much time did iOS report (`backgroundTime.done`, `remainingMs`), and do `wifi.stop` (reason `background`) and the WLAN Control `00` write finish before iOS suspends the app? Then, with Auto Power Off at 1 min and the camera linked over Bluetooth only (Wi-Fi off), does the camera turn itself off? The GR IV manual says Auto Power Off is not available "while the camera is connected to GR WORLD" (§6); whether a Bluetooth link alone counts decides whether leaving the Wi-Fi is enough to let an unused camera turn off.
