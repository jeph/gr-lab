# GR camera Wi-Fi remote shooting: live view, capture, focus, exposure (from Image Sync 2.1.32)

GR WORLD 2.0.0 has no live view or HTTP shooting caller ([HTTP API](http-api.md)). Ricoh's older **Image Sync** app implements them for GR II and GR III/IIIx, so this document is reverse engineered from `com.ricohimaging.imagesync` 2.1.32 (versionCode 20132000, APK SHA-256 `00756f0c0474c7f6ac0271b817effadf15e92362d49eab9d86cd0d6bba639442`) and its embedded Ricoh wireless SDK, cross-checked against the GR III and GR IV `webapid` decompilations in `firmware/evidence/`. Static analysis only; no camera was contacted. BLE-side shooting and exposure characteristics are in [ble-imagesync.md](ble-imagesync.md); the test procedure is in [hardware validation](../hardware-validation.md).

Citation prefixes (all relative to `work/imagesync-jadx/sources` unless noted):
- `impl/` = `com/ricoh/camera/sdk/wireless/impl/`, `api/` = `com/ricoh/camera/sdk/wireless/api/`, `app/` = `com/ricohimaging/imagesync/`
- `res/raw/…` is relative to `work/imagesync-jadx/resources/`
- `fw/…` is relative to the repo root `firmware/evidence/`
- `/tmp-simple` marks a jadx `-m simple` re-decompile, used where default jadx output was wrong or failed. Reproduce with `jadx --single-class <cls> -m simple`.

Labels: **[inferred]** = derived but not directly stated; **[unknown]** = not resolvable statically.

---

## 0. Headline facts

1. **Image Sync does not support GR IV.** The Wi-Fi support list is exactly: `GR II`, `RICOH GR III`, `RICOH GR III HDF`, `RICOH GR IIIx`, `RICOH GR IIIx HDF`, plus PENTAX/WG/G900 models (`impl/ImplCameraDeviceWiFiAdapterFactory.java:24-59`). If the `/v1/props` `model` is not on that list, the camera is rejected (`impl/WiFiCameraDeviceDetector.java:39-42`). No `GR IV` string exists anywhere in the app sources or resources (rg, 0 hits). GR IV behavior below is therefore an extrapolation from GR III plus the firmware handlers.
2. **Request style.** Every request is plain HTTP/1.1 to `http://192.168.0.1`. The only exception is G900 SE, which uses `192.168.1.1` (`impl/ActionLiveview.java:28-32`, `impl/ActionCapture.java:177-181`).
   - POST/PUT bodies are `key=value&key=value` strings. They are sent with `Content-Type: text/plain; charset=utf-8`, not form-urlencoded (`impl/RestCameraClient.java:192,220`; the charset is appended at `y1/y.java:16-31`).
   - Values are **not URL-encoded**. For example, `xv=+0.3` is sent with a literal `+` (`impl/ItemCaptureParams.java:267-282`).
3. **Success is determined by the JSON `errCode`, not the HTTP status.**
   - POST/PUT/GET responses are parsed as JSON. Success means `errCode == 200` (for example `impl/ActionCapture.java:305,327`). The HTTP status is not checked, except for live view (`impl/RestCameraClient.java:174-176`).
   - Before parsing, every JSON body has `4294967295` textually replaced with `-2147483648` (`impl/RestCameraClient.java:110`).
4. **HTTP client.** OkHttp 5.1.0 (UA `okhttp/5.1.0`, `c2/v.java:278`).
   - Defaults are connect, read and write timeouts of 10 s, with retry-on-connection-failure on (`y1/s.java:83,99-101`).
   - POST/PUT use these defaults.
   - `/v1/props` GETs use 7 s connect / 10 s read (`impl/ItemCaptureParams.java:420`). The connection checker uses 1 s connect / 10 s read (`impl/ItemCameraInfo.java:147`).
   - The SDK has no retry loop of its own.

---

## 1. Live view

### 1.1 Request

| Item | Value | Evidence |
|---|---|---|
| Method/URL | `GET http://192.168.0.1/v1/liveview`, **no query string**. Image Sync never sends `maxfps` or `reso`. | `impl/ActionLiveview.java:14,31,41` |
| Headers | OkHttp defaults only: `Host`, `Connection: Keep-Alive`, `Accept-Encoding: gzip`, `User-Agent: okhttp/5.1.0` **[inferred from OkHttp]** | `impl/RestCameraClient.java:161-171` |
| Timeouts | Connect 10 s (client default). Read timeout **0 = infinite** (`doGetStream(url, 0)`, unit ms). | `impl/ActionLiveview.java:41`, `impl/RestCameraClient.java:166-170` |
| Status check | A non-200 status throws `RestCameraException(url,-1,status)`. The stream thread then ends silently. | `impl/RestCameraClient.java:173-176`, `impl/ActionLiveview.java:72-77` |
| Model gate | All Wi-Fi models. There is no option flag. | `impl/ImplCameraDeviceWifiAdapter.java:902-913` |

### 1.2 MJPEG parsing (`MjpegInputStream`)

The client is **marker-driven and ignores the multipart boundary entirely** (`impl/MjpegInputStream.java:104-149`).

1. The input stream is wrapped in a 200 000-byte `BufferedInputStream` and marked with `mark(200000)` (`:34,106`).
2. The parser scans for SOI `FF D8` (`:35,108`). The bytes before SOI are treated as a "header" and parsed with `java.util.Properties`. If a `Content-Length` property is present, that value is used as the frame length (`:89-94,116`).
3. If `Content-Length` is missing or non-numeric (`NumberFormatException`), the parser scans for EOI `FF D9`.
   - It first searches the window `[L/2, 3L/2)`, where L is the previous frame length (`:62-79,121-126`).
   - If that fails, it scans from the mark (`:47-60`).
4. The frame is read from SOI with the computed length (`:136-137`) and delivered as a copy (`impl/ActionLiveview.java:51`).
5. **Limits:** the maximum frame and header-search size is 200 000 bytes (`impl/ActionLiveview.java:12`, `impl/MjpegInputStream.java:19`). A frame of length 0 terminates the stream (`impl/ActionLiveview.java:47-50`). `skip = 1`, so every frame is delivered (`:42,140`).
6. **Quirk [inferred from arithmetic].** The EOI offset is measured from the mark (the start of the part header), but the read starts at SOI. Delivered buffers can therefore contain the following part's header bytes after `FF D9`. JPEG decoders ignore trailing bytes.

**Firmware agreement (GR III and GR IV webapid, rodata):**
- The stream header block contains:
  - `Cache-Control: no-store, no-cache, must-revalidate, max-age=0`
  - `Expires: 0`
  - `Pragma: no-cache`
  - `Content-Type: multipart/x-mixed-replace; boundary=--boundary\r\n\r\n`
- Each part is `--boundary\r\n` + `Content-Type: image/jpeg\r\n\r\n` + JPEG. **There is no per-part `Content-Length`.**
- String offsets:
  - GR IV `usr/bin/webapid` (sha256 `27d3d36f…7f8dd2`): file 0xb522c–0xb52e4.
  - GR III (sha256 `75ffb326…039797`): 0xea0d8–0xea190.
- `fw/gr4-route-send-frame.c:82-99` sends two constant buffers plus the frame (15 s send timeout). `fw/gr4-route-send-header.c:19-49` sends 5 header buffers.
- The declared boundary is `--boundary`, so an RFC 2046 delimiter would be `----boundary`, yet parts start with `--boundary`. **Strict multipart parsers will fail. Scan for SOI/EOI as Image Sync does.**
- Image Sync's Content-Length branch is therefore never taken against GR III/IV **[inferred]**.

### 1.3 Firmware query parameters, which Image Sync does not use

- `maxfps` (rodata 0xb5050 GR IV):
  - Absent → 90 (`fw/gr4-route-fps-query.c:64`).
  - Non-digit → `BadRequest` (`:99-126,165`).
  - Digits in 1..90 are accepted (`:212-213`).
  - Other numeric values are clamped to 90, still OK (`:221`).
- `reso` (rodata 0xbba44 GR IV):
  - Absent → resolution unchanged; the current value is read (`fw/gr4-route-reso-query.c:60`, `fw/gr4-route-liveview.c:140-148`).
  - A value that `ConvertToIpcu` rejects → `BadRequest` (`fw/gr4-route-reso-query.c:91-136`).
  - The accepted syntax is **[unknown]** from the evidence. The log string `reso number has invalid value : {},{}` implies two numbers. Third-party clients use `reso=720x480` (`research/notes/route-history-findings.md:58,60`).
- Sequence (`fw/gr4-route-liveview.c`):
  1. Parse `reso`, then `maxfps` (`:42-71`).
  2. `SetValidRequest`; the log "RLV valid socket changed" means a newer request supersedes the older socket **[inferred]** (`:73-92`).
  3. Global mutex (`:132`).
  4. Get or set reso (`:140-204`).
  5. `ChangeRemoteLvMode(1)` if not already on (`:310-363`).
  6. `SendHeader` → `SendFrameLoop(reso, maxfps)` (`:365-368`).
  7. `ChangeRemoteLvMode(0)` (`:378-484`).
  8. Close the socket (`:528`).
- GR IV rodata also contains `SendSingleFrame`, `"{} timeout because of continuous busy state."` (0xb4fc7) and two embedded baseline JPEGs: 2 274 bytes at **720×480** (0xb5304) and 4 839 bytes at **1080×720** (0xb5c0c). Both are uniformly black (every pixel 1/255). GR III has the same busy-timeout string (0xe9ebb).
- How frames are fetched (GR IV webapid, `firmware/evidence/gr4-liveview-*.c`): `SendFrameLoop` (0x7f5a0) calls `SendSingleFrame` and then sleeps to hold `maxfps`. `SendSingleFrame` repeats `SendFrame` (0x7f16c) while the request is still the valid one. `SendFrame` asks the camera controller for a frame through `CameraController::GetCaptureCommand()` (`GetRemoteLvFrame`):
  - `0`: the frame is sent as a part.
  - `3`: nothing is sent and it asks again at once, so the stream simply stalls.
  - `4`: `SendDummyFrame` (0x7ef30) sends the black JPEG of the stream's size.
  - Anything else: logs `GetRemoteLvFrame command faild({})` and the loop ends with InternalServerError, closing the stream.
- Touch focus (`Capture::Focus`, 0x7a11c) is a release with the shoot flag off (`ReleaseOption::Create(false, 1, pos)`) through that same `GetCaptureCommand()` object. The decompiled `Capture::Focus` does not touch live view. Nothing in the code read so far ties the `3`/`4` answers to focusing; whether the controller holds frames back during AF is **[unknown]**. Seen on a GR IV HDF (fw 1.20, 2026-11-08): the GR Photo preview pauses briefly on every tap to focus. Cause not established: a camera-side stall and a client-side cause have not been told apart (no frame-arrival trace around a focus yet, no GR WORLD comparison).
- Frame size actually streamed: **[unknown]** statically. GR IV third-party logs report 720×480 (`research/notes/route-history-findings.md:9`).

### 1.4 Lifecycle and threading

- `startLiveView()` returns OK if already running. Otherwise it spawns one thread (`impl/ImplCameraDeviceWifiAdapter.java:902-913`, `impl/ActionLiveview.java:96-110`).
- `stopLiveView()` sets `isRunning=false` and interrupts the thread (`impl/ActionLiveview.java:112-115`).
  - It **does not close the socket**. The loop exits only at the next frame boundary, when `!isRunning && interrupted` (`:43`).
  - Combined with the infinite read timeout, a stalled camera can hang the thread **[inferred]**.
  - The stream is closed in the loop's exit path (`:54-60`).
- **No reconnection in the SDK.** Any exception or zero-length frame ends the thread with `isRunning=false` (`:72-77`).
  - The app's 500 ms UI timer (`app/ShootingActivity.java:2788-2790`, `m/r4.java`) calls `U()` in several branches, for example `m/r4.java:247,315`.
  - `U()` re-issues `startLiveView()` (`app/ShootingActivity.java:1403`, `m/q3.java:37`). This acts as an implicit restart **[inferred]**.
- `disconnect()` stops live view (`impl/ImplCameraDeviceWifiAdapter.java:435-438`).
- **Around shooting and focus, the SDK never stops or restarts live view.** `focus`/`startCapture` do not touch `liveViewAction` (`impl/ActionCapture.java:477-559`).
  - The app stops live view (`V()` → `stopLiveView`, `m/q3.java:39-44`, `app/ShootingActivity.java:1410-1431`) only when:
    - the user toggles it off (`m/v3.java:105-124`);
    - entering settings or the gallery (`m/v3.java:42-45,196-201`);
    - leaving the screen (`app/ShootingActivity.java:2731`);
    - there is a storage error (`app/ShootingActivity.java:3359-3389`);
    - the drive mode or exposure forbids app control (§1.6).
  - Firmware may substitute a busy frame (§1.3).
- Frame delivery: `liveViewFrameUpdated(camera, bytes)` (`impl/ImplCameraDeviceWifiAdapter.java:127-135`).
  - The app keeps a deque of at most about 4 frames and decodes only the newest on the UI thread (`m/e4.java:92-100`).

### 1.5 Orientation

The camera reports how it is held, and Image Sync turns the live view picture to match. The frames themselves stay in the sensor's landscape layout **[inferred]**: Image Sync turns them itself, and the GR IV webapid's only built-in frames (the black busy frames, §1.3) are 720×480 and 1080×720.

**The value.** `cameraOrientation` is one of `none|positive|reverse|vertical_right|vertical_left` (Image Sync `api/setting/capture/CameraOrientation.java`, `res/raw/capture_ricoh_gr_iii.yaml:424-431`; the same five strings in GR IV webapid rodata 0xbb3e0–0xbb40c).
- A GR IV HDF (fw 1.20) reported `"cameraOrientation": "positive"` in `/v1/props` **[observed, 2026-11-07]**.
- GR IV webapid 1.20 **[found in code]**: `camera_orientation::GetCurrentValue` (0xb1538) reads camera property `0x7f`. Two places read it: `CameraParams::Fetch` (0x9d888; `CameraParams` is part of `/v1/props` and of the `PUT /v1/params/camera` answer) and `CameraDirect::Fetch` (`fw/gr4-camera-direct-fetch-0xaa988.c`). `CameraDirect::Serialize` (`fw/gr4-camera-direct-serialize-0xaa4e4.c`) writes it as `cameraOrientation` into the `cameraDirect` change, after `capturing`, `stateStill`, `stateMovie`, `countDown`, `onePushBracket`, `shotsTotal` and `shotsCurrent`.
- **The camera pushes it when it changes [found in code].** `PropertyEventHandler::Setup` (`fw/gr4-property-handler-setup-0x8c29c.c`) subscribes to changes of properties `0x2d 0x2e 0x2f 0x30 0x33 0x37 0x38 0x39 0x7f` (the list built in `_INIT_17`, `fw/gr4-property-list-init-0x8c6ac.c`). `PropertyEventHandler::PropertyChanged` (`fw/gr4-property-changed-0x8c3b0.c`) sends a `cameraDirect` change to the WebSocket when a changed property is in that list, so turning the camera should send one with the new orientation. Not yet seen on hardware.
- Which physical way round `vertical_right` and `vertical_left` are, and when the camera says `none` (pointing up or down, perhaps), are **[unknown]**.

**What Image Sync does** (2.1.32):
- It reads `CameraOrientation` with the other capture settings (`app/ShootingActivity.java:1897,1906`) and again on every settings poll (`m/r4.java:394-399`). It follows the camera only when the setting `SHARED_PREFERENCE_KEY_LIVE_VIEW_CAMERA_ORIENTATION_FOLLOW` is on (`p/a.java:139`) and its model gate `s/g.J` passes (decompiled badly; it returns true for every model reached).
- `m/a.a` turns the value into 1 `positive`, 2 `vertical_left`, 3 `reverse`, 4 `vertical_right`; anything else, `none` included, is 1. `m/a.f` gives the picture's clockwise turn: 0°, 270°, 180°, 90° (`View.setRotation`, `app/ShootingActivity.java:1366-1378`).
- With the phone upright and the camera upright, the bitmap is turned +90° (`m/e4.java:118-124`) and its view `f(d(A1))`: 0° for `vertical_right`, 180° for `vertical_left`. In total the frame turns 90° clockwise for `vertical_right` and 90° counter-clockwise for `vertical_left`, the same as `m/a.f`.
- Touch focus undoes the turn before normalising the point (`app/ShootingActivity.java:1029-1123`), so `pos` stays in the frame's own landscape layout (§3.2).

**What GR Photo does:** it takes `cameraOrientation` from `/v1/props` and from `cameraDirect`, shows the frame turned by Image Sync's angles, maps taps back into the frame's layout for `pos`, and lays the controls out around the turned picture. Whether a GR IV pushes `cameraDirect` on a turn and keeps its frames landscape is to be confirmed on hardware ([hardware validation](../hardware-validation.md) session C).

### 1.6 When the app refuses live view and touch (GR III family)

`ShootingActivity.w()` failed in default jadx (`app/ShootingActivity.java:3484-3542`). Recovered via `/tmp-simple` `ShootingActivity.java:3712+`.

| Condition | Result |
|---|---|
| Exposure program = BULB (`exposureMode=B`) | Refused. Message: *"When the shutter speed is set to B in M mode, you can not operate the camera from app."* |
| Drive mode `single`, `self10s`, `self2s` | Allowed |
| Other drive modes on Wi-Fi only | Refused. Message: *"Camera cannot be operated by application in the current drive mode."* |

Strings are in `res/values/strings.xml`. The code→string mapping is via `app/ShootingActivity.java:1267-1290` (the `m.a.h` = code−1 mapping is **[inferred]**). The refusal also sets `w=false`, which disables touch (`app/ShootingActivity.java:1917-1923`).

---

## 2. Capture (HTTP shutter)

### 2.1 Endpoints and bodies (`ActionCapture`)

| Operation | Method/path | Body (exact) | Used for | Evidence |
|---|---|---|---|---|
| Still, no AF | `POST /v1/camera/shoot` | `""` (GR III), `af=camera` (GR II) | Shutter button while live view is on | `impl/ActionCapture.java:208-215,556`; factory `:433-435`; app `m/p3.java:35` |
| Still with AF | `POST /v1/camera/shoot` | `af=on` (GR III), `af=camera` (GR II) | Shutter button with live view off and focusMode AF | same |
| Touch shutter (AF+) | `POST /v1/camera/shoot` | `<stillbody>&pos=X,Y`, e.g. `af=on&pos=50,50` | Touch in "AF+" mode | `impl/ActionCapture.java:319-324,204-206`; `app/ShootingActivity.java:389-407`; `m/t3.java:43-56` |
| Movie start | GR III: `POST /v1/camera/shoot`. Default: `POST /v1/camera/shoot/start` | `""` | `CaptureMethod.MOVIE` | `impl/ActionCapture.java:298-312`; factory `:374-375` |
| Movie stop | GR III: `POST /v1/camera/shoot` (toggle). Default: `POST /v1/camera/shoot/finish` | `""` | | `impl/ActionCapture.java:563-569,596-616` |
| Bulb/Time start | GR III (`exposureMode` B **or** T): `POST /v1/camera/shoot` with the still body | still body | | `impl/ActionCapture.java:270-288,555-558`; factory `:376-377` |
| Bulb/Time stop | GR III: `POST /v1/camera/shoot`, body `""` | `""` | | `impl/ActionCapture.java:570-579` |
| Interval-composite finish | `POST /v1/camera/shoot/compose` | `""` | GR III `intervalComp*` stop while not in countdown | `impl/ActionCapture.java:392-407`; factory `:378` |
| Cancel self-timer | `POST /v1/camera/shoot/cancel` | `""` | GR III self-timer stop, or interval-comp in countdown | `impl/ActionCapture.java:397-404,417-427` |
| Stop continuous/interval | `POST /v1/camera/shoot` | `""` | GR III `continuous`, `interval` | `impl/ActionCapture.java:409-415` |
| Green button | `PUT /v1/params/camera` | `""` | App "green button" | `impl/ActionCapture.java:453-463`; `m/k1.java:91` |
| Power off | `POST /v1/device/finish` | `""` | `setPower(false)`; GR II and GR III family (`supportPowerOff`) | `impl/ActionCapture.java:501-514`; factory `:368,427` |
| WLAN off | `POST /v1/device/wlan/finish` | `""` | `setCameraSettings(WLANEnable.FALSE)`, GR III family only | `impl/ImplCameraDeviceWifiAdapter.java:755-767,793-795`; `impl/ActionCapture.java:516-526` |
| Camera memo | `PUT /v1/configs/cameramemofile` | File body. `Content-Type: text/plain`. `Content-Disposition: attachment; filename*=utf8''<pct-enc>` | **G900 SE only** (throws otherwise) | `impl/ActionCapture.java:528-542`; `impl/RestCameraClient.java:336-360` |

`X,Y` = `Math.round(x*100)`, `Math.round(y*100)` (integers 0..100, comma, no space) (`impl/ActionCapture.java:204-206`, `androidx/activity/result/b.java:65-67`). Coordinates are in §3.2.

GR III `stop()` for MOVIE does not return after the movie-stop POST. It falls into `stopImplForGRIII`, which throws `UnsupportedOperationException` for MOVIE unless the early-return condition holds (`impl/ActionCapture.java:563-593,389-419`) **[inferred quirk]**. Do not copy it.

### 2.2 Responses

- Shoot response bean: `{errCode:int, errMsg:str, captureId:str, captured:bool, focused:bool}` (`impl/BeanShoot.java:10-14`).
- Non-200 `errCode` → `RestCameraException`. If `errCode == 412` and a writable storage reports 0 remaining, the error is mapped to `NO_SPACE` (`impl/ImplCameraDeviceWifiAdapter.java:1096-1100`).
- Before shooting, the client checks that no capture is already in progress, and for GR III that `stillState` is idle unless the method is still/bracket/interval-comp (`impl/ImplCameraDeviceWifiAdapter.java:173-186`). Otherwise it returns "Device Busy" (`:1111-1113`).
- GR III shoot: the returned `captureId` is recorded in `shootActionResultMap` (`impl/ActionCapture.java:264-268,337`).
- Movie start: after an OK, the SDK polls `GET /v1/props` every 100 ms until `stateMovie == "busy"`, giving up after 3 s (`impl/ItemCameraInfo.java:49,157-172`; `impl/ImplCameraDeviceWifiAdapter.java:1078-1082`).

### 2.3 Completion tracking: WebSocket plus polling, no `/latest` polling loop

- `ws://192.168.0.1/v1/changes` is opened for **all** Wi-Fi models.
  - The `SYNC_MODE` enum is computed but never read (`impl/ImplCameraDeviceWiFiAdapterFactory.java:472-474`; only used at `impl/ImplCameraDeviceWifiAdapter.java:126`).
  - Connect 7 s, read 0 (`impl/SyncTrigger.java:174`).
  - The SDK adds `Sec-WebSocket-Extensions: permessage-deflate` (`impl/RestCameraClient.java:309-313`).
  - On `onFailure` it immediately restarts (`impl/SyncTrigger.java:44-52`).
- Messages are parsed as `BeanChanges` (`impl/BeanChanges.java:10-30`). If `changed` is null, `change` is used instead (`impl/SyncTrigger.java:58-61`). Dispatch by `changed`:

| `changed` | Keys read | Effect | Evidence |
|---|---|---|---|
| `cameraDirect` | `stateStill`, `stateMovie`, `countDown` (`idle\|busy2s\|busy10s\|busy12s\|time`), `capturing`, `shotsCurrent`, `shotsTotal`; `cameraOrientation` comes from the settings poll instead (§1.5) | GR III: capture COMPLETE when (movie and `stateMovie=="idle"`) or (`stateStill` ∈ {`idle`,`continuous`} and `countDown=="idle"` and `!capturing`). A self-timer back to idle early means CANCELLED. GR IV webapid also sends `onePushBracket` and `cameraOrientation` in it (§1.5) | `impl/UpdateChanged.java:26-33,104-165` |
| `lens` | `captureId`, `focused` | `captureId=="0"` is ignored. For a pending shoot → `focusComplete(ok/err)` event. Otherwise the result is stored for `focus()` waiters. | `impl/UpdateCaptureIdForLens.java:22-52` |
| `capture` | `captureId` | Removes the pending shoot entry | `impl/UpdateCaptureIdForCapture.java:17-30` |
| `storage` | `action`, `filepath`, `storage`, `captureId` | On `action=="add"` (and `captureId != "0"`), remembers the path → `latestCaptureImageChanged`. Also triggers an image-list resync and `imageStored`/`captureComplete` counting. | `impl/UpdateLatestCaptureImage.java:22-39`; `impl/UpdateCameraImage.java:200-272` |
| `camera` | – | Re-reads `/v1/props` into the capture/camera setting caches | `impl/UpdateCaptureSetting.java:24`, `impl/UpdateCameraSetting.java:24`, `impl/UpdateCameraStorage.java:78` |
| `battery` | – | Re-reads status | `impl/UpdateCameraStatus.java:22` |
| `transfer` | – | Transfer list | `impl/UpdateTransfer.java:34` |

- **Latest image:** `GET /v1/photos/<filepath>/info[?storage=<id>]` (7 s/10 s). `GET /v1/photos/latest/info` is used only when no `filepath` has been seen (`impl/ItemImages.java:31,202-223`).
  - Response: `{errCode, errMsg, captured, datetime, dir, file, orientation:int, size:long}` (`impl/BeanPhotoInfo.java:10-17`).
  - For GR III the `storage` query is omitted, because `createItemImages(null,…)` is used (`impl/ImplCameraDeviceWiFiAdapterFactory.java:192`).
  - Neither GR III nor GR IV webapid contains a `/latest` route string. On a GR IV HDF (fw 1.20) `GET /v1/photos/latest/info` returns HTTP 200 with `{"errCode": 400, "errMsg": "Bad Request"}` **[observed]** ([results log](../hardware-validation.md#4-results-log)).
- **Polling (every Wi-Fi model):** a `ScheduledThreadPoolExecutor(3)` runs every 500 ms with fixed delay (`impl/SyncTrigger.java:23,147,176-179`).
  - `ConnectionChecker` → `GET /v1/props` (1 s connect).
  - Cached setting/storage updaters also run, and for GR III cached status too (`impl/ImplCameraDeviceWifiAdapter.java:275-322`).
  - Cached reads are served from the last `BeanProps` fetched by any uncached GET: the cache is keyed by bean class and refreshed on every fetch (`impl/RestCameraClient.java:121-149`). Effective props refresh is therefore ≈2 Hz.
  - Disconnect when there are ≥3 consecutive failures **and** more than 40 s since the last success (`impl/ConnectionChecker.java:12-15,63-104`).

**Differences from our GR WORLD docs** (`research/protocol/http-api.md:177-199`):
- GR WORLD ignores WebSocket messages on III/IV and only knows `storage|battery|camera`.
- Image Sync relies on `cameraDirect`, `lens`, `capture`, `transfer` and the `change` alias, plus keys `captureId`, `focused`, `stateStill`, `stateMovie`, `countDown`, `capturing`, `shotsCurrent`, `shotsTotal`, `action`, `filepath`, `storage`.
- All of these keys exist as strings in both webapids (GR III and GR IV `strings`: `captureId`, `stateStill`, `cameraDirect`, `lens`, `focused`, `filepath`, `action`, …).
- Image Sync uses only `/v1/props` and never `/v1/status/device`.

---

## 3. Focus

### 3.1 Requests

| Model | Request | Body | Response handling | Evidence |
|---|---|---|---|---|
| GR III family (and default) | `POST /v1/lens/focus` | `pos=X,Y`, or `""` for `focus()` with no point | `BeanFocus {errCode, errMsg, captureId, focused, focusRunning, focusCenters:[[int]], focusEffectiveArea:[int]}`. If `captureId` is non-empty, wait up to **40 s** (100 ms poll; abort on disconnect) for WS `changed:"lens"` with the same `captureId`; result = its `focused`. Otherwise use `focused` from the response. | `impl/ActionCapture.java:430-451,477-499`; `impl/BeanFocus.java:11-17` |
| GR II | Intended `POST /v1/lens/focus/lock`, `pos=X,Y` | | `focused` from the response | factory `:433` |

- **GR II bug:** the factory stores the *absolute* URL `http://192.168.0.1/v1/lens/focus/lock`, and `focus()` prepends `baseURL` again. The result is `http://192.168.0.1http://192.168.0.1/v1/lens/focus/lock` (`impl/ActionCapture.java:481-484`, `androidx/activity/result/b.java:132-136`).
  - OkHttp URL parsing then fails with an invalid port **[inferred]**. GR II touch-AF is broken in 2.1.32.
  - This contradicts the assumption that Image Sync exercises GR II focus/lock. That path exists in neither GR III nor GR IV webapid (string scan: 0 hits).
- When the app calls focus:
  - Touch in "AF" mode → `focus(point)`.
  - In "AF+" mode with the shutter enabled → `startCapture(point)`, i.e. shoot with AF at the point (`app/ShootingActivity.java:389-407`; preference `SHARED_PREFERENCE_KEY_TOUCH_AF` ∈ {`AF`,`AF+`}, `p/a.java:106`, `z/c.java:1130-1137`).
  - Touch is honored only when `focusMode == AUTO` (or MOVIE), per `m/t3.java:43-58`.

### 3.2 Coordinates

- `Point(x,y)` is normalized 0..1 on the **live-view image in camera (landscape) orientation**: origin top-left, x to the right, y down.
  - The app inverts its UI rotation per orientation before normalizing (`app/ShootingActivity.java:1029-1123`; `m/t3.java:43`).
  - On the wire: integer percent `round(v*100)`.
- **Valid area:** taps outside the AF effective rectangle are dropped (`app/ShootingActivity.java:1124-1126`). The rectangle comes from `/v1/props` `focusEffectiveArea: [W, H]`, with W and H in percent of the frame:
  - It is centered: x ∈ [0.5−W/200, 0.5+W/200], y ∈ [0.5−H/200, 0.5+H/200] (`impl/RestCameraSettingConverter.java:137-154`; key in `res/raw/camera_ricoh_gr_iii.yaml:25-27`).
  - If the key is absent the default is (0.111,0.125)–(0.889,0.875) (`app/ShootingActivity.java:1019-1024`). GR II's YAML has no such key.
- Firmware: both shoot and focus parse the `pos` key via `focus_pos::GetFromKeyValues`. The key strings `pos`, `af`, `setting`, `reset` are adjacent in rodata (GR IV 0xb47ef, GR III 0xe7c73).
  - Focus builds `ReleaseOption::Create(false, 1, pos…)`. Shoot builds `ReleaseOption::Create(<af value>, 1, pos…)`, with the `af` default = 1 when absent.
  - Both return `ShootResponse(err, id)`, which is consistent with `captureId` (`fw/gr4-route-focus.c:60,110,131`; `fw/gr4-route-shoot.c:45-66,123-136`; GR III identical `fw/gr3-route-Focus.c:96,196`, `fw/gr3-route-Shoot.c:98-106,210`).
  - The `af` value vocabulary (`on`/`off`/`camera`) is **[unknown]** from the firmware; `shutter_mode` was not decompiled. For `pos`, see the `focus_pos` note below.
- Observed on a GR IV HDF (fw 1.20, 2026-11-08, GR Photo phone log of 30+ taps on the live-view picture):
  - The `POST /v1/lens/focus` answer has neither `focused` nor `focusRunning`, which fits a `ShootResponse` (`errCode`, `errMsg`, `captureId`). A second run (16:44-16:45, 14 taps) logged `captureId` `"1"`, `"2"`, … in the answers, then a `lens` change with the same `captureId` 1.3-2.1 s later, after the answer every time. All 14 `lens` changes said `focused: false`; whether the camera really failed to focus was not checked.
  - In that run live view stopped within 0.05 s of each request and the next frame came within 0.03 s of the `lens` change, followed by one more gap of 0.40-0.54 s. So the stream is frozen for exactly the time the camera spends on the focus.
  - `focus_pos::GetFromKeyValues` (0x7913c, `firmware/evidence/gr4-focus-pos-0x7913c.c`) reads `pos` with `IntPairString` (BadRequest when that fails) and defaults to `(50, 50)` when the key is absent. So the units are percent with the centre at 50,50, as Image Sync sends; the accepted range is still **[unknown]**.
  - A single focus is answered in 19-77 ms, and a live-view frame gap of 0.87-2.16 s follows each one (26 of 26); setting changes in the same run caused no gap. The last frame before each gap arrived between 0.12 s before and 0.08 s after the request was sent.
  - Focuses sent 1.5-2 s apart are answered later and later (0.56, 1.1, 1.7, 2.4, 3.9, 5.0, 6.9, 8.4, 8.7 s), and live view stays frozen throughout (one 8.8 s gap). So the camera holds a focus sent while one runs until that one ends, and keeps live view stalled across the series. That the gap is the camera focusing, rather than another camera-side cause, is **[inferred]**: the phone answered the HTTP requests during the gaps, so its UI thread was not stalled.
  - GR Photo therefore sends one focus at a time and only the newest tap made meanwhile **[design]**.
  - A third run (16:53-16:54, 9 taps) had the first successful focuses. The 6 with `lens` `focused: true` ended 0.18-1.08 s after the request; the live-view gap matched each (two below the 0.3 s logging threshold). The 3 with `focused: false` ended 0.67-2.84 s after it, gap matching. The user saw the picture stop while the lens searched and move again when it stopped. So the stream pauses for as long as the camera's AF search, and a quick lock means a short pause. Whether any setting keeps frames coming during the search is **[unknown]**.

### 3.3 Lens params and zoom

- `FocusSetting` → `PUT /v1/params/lens`, body `focusSetting=<val>` (`impl/ItemCaptureParams.java:29,359-382`). GR III values (`res/raw/capture_ricoh_gr_iii.yaml:410-423`): `manual multiauto spot pinpoint tracking continuous snap inf movie multiauto_center zone_select`.
  - The Image Sync app writes FocusSetting only for PENTAX (Macro/Standard/Star toggles, `m/k1.java:93-102`; `s/i.java:131-138`). For GR it is read-only.
  - Firmware agrees on `PUT /v1/params/lens` key-value dispatch (`fw/gr4-route-lens-params.c`, `fw/gr4-route-lens-set.c`).
- `ZoomLevel` → `POST /v1/lens/zoom`, body `level=<val>` (`impl/ItemCaptureParams.java:30,384-410`). This route is not in GR III/IV webapid (string scan) and is not in the GR YAMLs. Ignore it for GR.
- `focusMode` (`af`/`mf` on GR III; `AF`/`MF` on GR II) is read-only (FocusMethod, `res/raw/capture_ricoh_gr_iii.yaml:365-369`, `res/raw/capture_gr_ii.yaml:247-250`).

---

## 4. Exposure and camera parameters

### 4.1 Read: `GET /v1/props`

- The current value is `props[<rest_key>]`. The available list is `props[<rest_key> + "List"]` (`impl/RestCaptureSettingConverter.java:43-53`).
- No list is read for `focusMode`, `onePushBracket`, `remocon`, `cameraOrientation`, `gradND`, `type3*`, or AutoFocusRunning (`:133-135`).
- All `BeanProps` keys are listed at `impl/BeanProps.java:11-91`. GR-relevant keys: `av avList tv tvList sv svList xv xvList WBMode WBModeList effect effectList exposureMode exposureModeList exposureModeOption stillSize stillSizeList stillFormat stillFormatList movieSize movieSizeList meteringMode meteringModeList focusMode focusSetting focusSettingList shootMode shootModeList captureMode captureModeList countDown shotsTotal onePushBracket cameraOrientation focusEffectiveArea state stateMovie storages battery model serialNo firmwareVersion macAddress bdName ssid key`.
- `exposureModeOption`: `"shift"` → PROGRAM_SHIFT / ISO_PRIORITY_SHIFT; `"hyper"` → HyperProgram flag (`impl/ItemCaptureParams.java:205-229`).
- `captureMode=="movie"` forces CaptureMethod=MOVIE for GR III. Default jadx output is misleading; see `/tmp-simple` `ItemCaptureParams.changeCaptureModeToRelatedSettings`, L38–L41.

### 4.2 Write routing (`ItemCaptureParams.push`, `impl/ItemCaptureParams.java:433-456`)

The SDK supports several settings per request. The app always sends **one setting per call** (`n/b.java:2088`, `m/y4.java:43-48`).

| Setting | Request | Body |
|---|---|---|
| `StillImageCaptureFormat` | `PUT /v1/params/device` | `stillFormat=jpeg\|dng\|rawdng` (`:309-332`) |
| `CompositionAdjustment` / `Enable` | `PUT /v1/params/camera/compAdjust` | `x=<i>&y=<i>&r=<i>`, `setting=true\|false` (`:284-307,334-357`). PENTAX only; not in GR webapid. |
| `FocusSetting` | `PUT /v1/params/lens` | `focusSetting=…` |
| `ZoomLevel` | `POST /v1/lens/zoom` | `level=…` |
| everything else | `PUT /v1/params/camera` | `key=value[&…]` (`:267-282`) |

- The `PUT /v1/params/camera` response is props-shaped JSON, but on the GR IV it is not the full `/v1/props`. The SDK re-parses current values and lists from it (`:446-452`). GR IV webapid `ParamsCameraResponse::Fetch` (0x74a78) builds it from `CameraStatus::Fetch` and `CameraParams::Fetch` only. `/v1/props` (`PropsResponse::Fetch`, 0x76368) also adds device and lens parts and `CameraConstants::Fetch` (0x9c290). That last part produces the supported-value lists of capture mode, `effect`, exposure mode, metering, movie size, `reso`, shoot mode, still size and WB mode (`*::GetSupportedValues`). So after a setting change those `<key>List`s are missing from the answer, and a client must keep the ones it read from `/v1/props`. This matches what was seen on a GR IV HDF (fw 1.20, 2026-11-08): after one Image Control change, GR Photo could no longer offer Image Control choices.
- An empty-body `PUT /v1/params/camera` is the "green button" (§2.1).
- `ExposureProgram` writes are converted to `exposureMode=` (`:232-265`). The app never writes ExposureProgram for GR: the mode dial is authoritative. The SDK's mapping would emit duplicate `exposureMode=` pairs (e.g. `P` and `movieP` → `null`) **[inferred]**. Avoid.

### 4.3 Key/value tables (exact strings)

The YAML `rest_value` maps SDK constant name → wire value. GR III, GR III HDF, GR IIIx and GR IIIx HDF files are byte-identical (`diff` of `capture_*`/`camera_*` = empty).

| Setting | Key | GR III family values (`res/raw/capture_ricoh_gr_iii.yaml`) | GR II values (`res/raw/capture_gr_ii.yaml`) |
|---|---|---|---|
| Aperture | `av` | `0.5 … 2.8 3.2 3.3 3.5 4.0 4.5 4.8 5.0 5.6 6.3 6.7 7.1 8.0 9.0 9.5 10 11 13 14 16 … 256`; unset = `---` (`:218-283`) | `null`, `0.5…16`, … (`:155-185`) |
| Shutter | `tv` | `N.D` = N/D seconds: `1.4000`=1/4000, `1.250`=1/250, `3.10`=0.3 s, `25.10`=2.5 s, `2.1`=2 s … `1200.1`=1200 s, plus `1.24000` … `1.5000`. Unset/first entry `0.1` (`:75-191`). | `B`, `T`, `1.4000` … `300.1` (`:56-116`) |
| ISO | `sv` | `auto 100 125 140 160 … 819200`; unset `---` (`:17-74`) | `auto auto_hi 100 … 25600` (`:26-55`) |
| Exp. comp. | `xv` | `-5.0 … -0.3 0.0 +0.3 … +5.0` (1/3 and 1/2 steps), plus `0` (`:284-328`) | `-4.0 … +4.0` (1/3 steps) (`:186-213`) |
| WB | `WBMode` | `auto multiAuto daylight tungsten shade cloud daylightFluorescent dayWhiteFluorescent coolWhiteFluorescent warmWhiteFluorescent manual1 colorTemp1 cte custom1 custom2 custom3` (`:199-217`) | as III minus `colorTemp1 custom1-3`, plus `incandescent custom` (`:138-154`) |
| Image control | `effect` | `off col_vivid col_custom1 col_custom2 efc_monochrome efc_softMonochrome efc_hardMonochrome efc_highContrast efc_posiFilm efc_bleachBypass efc_retro efc_HDRTone` (`:2-16`) | 21 values incl. `col_bright efc_monoToning efc_crossProcess efc_miniature …` (`:2-25`) |
| Exposure mode (read-only) | `exposureMode` | `auto P TV AV TAV M SV B T BT U1 U2 U3 SFP` (`:329-345`) | `auto P TV AV TAV M movie` (`:214-223`) |
| JPEG size | `stillSize` | `L3 M3 S3 XS3` (`:192-198`) | `<fmt>_<aspect>`: `D_11 D_32 D_43 DJ_* L3_* M3_* S3_* XS3_*` (`:117-137`) |
| File format | `stillFormat` (→ `/v1/params/device`) | `jpeg dng rawdng` (`:346-351`) | – (part of `stillSize`) |
| Movie size | `movieSize` | `FHD24p FHD30p FHD60p` (`:352-357`) | `4K30 FHD24p … VGA30p` (`:224-240`) |
| Metering | `meteringMode` | `multi center spot highlight` (`:358-364`) | `multi center spot` (`:241-246`) |
| Drive | `shootMode` | `single continuous self10s self2s bracket bracketSelf10s bracketSelf2s multiExp multiExpSelf10s multiExpSelf2s interval intervalSelf10s intervalSelf2s intervalComp intervalCompSelf10s intervalCompSelf2s` (`:370-388`) | – (no drive key) |
| Capture mode (read) | `captureMode` | `still movie` (`:405-409`) | – |

The GR IV's `effect` values differ from the GR III family's: a GR IV HDF lists 17, adding `efc_negaFilm efc_cineYellow efc_cineGreen efc_crossProcess col_custom3` (`image-control.md` §3, observed on firmware 1.20 on 2026-11-09).

`sv` is the ISO in effect, not the ISO setting:

- Found in code (GR IV webapid): `CameraParams::Fetch` (0x9d888) takes `sv` from `sv::GetCurrentValue` (0xb9614), which reads the *current* value of camera property 0x44 (0x77 for movies), not the setting value. `sv::ConvertToWebapi` (0xb91e0) turns 0 into `auto`, 1 into `auto_hi` and anything else into the number. With ISO AUTO the current value is the metered ISO, so `/v1/props` and the `PUT /v1/params/camera` answer report a number. The GR III webapid does the same (`sv::GetCurrentValue` 0xebc6c, `ConvertToWebapi` 0xebb40).
- Found in code: `sv::SetValue` (0xb9848) turns `auto`/`auto_hi` into 0/1 and writes them as the setting. `svList` comes from `sv::GetSupportedValues` (0xb93ec) with the same conversion; webapid does not filter it by exposure mode. Nothing in webapid reads the ISO setting. Over BLE, bled's `Shooting::ISO::GetBLEValue` (0x7071c) also reads the current value, so the ISO characteristic's 0 = AUTO is very likely no better **[inferred]**.
- Found in code: Image Sync shows AUTO only when `sv` is the string `auto` (`m/r4.java:973-998`).
- Observed on a GR IV HDF (reported 2026-11-09, firmware not recorded): after AUTO was picked on GR Photo's ISO dial, the readout showed a number at the next props read.
- Observed on a GR IV HDF (fw 1.20, 2026-11-07, Av): `svList` was `100 … 204800` with no `auto`, `sv` was `6400`. Whether ISO was AUTO on the body then is **[unknown]**.
- **[unknown]**: any HTTP, WebSocket or BLE field that says ISO is AUTO while `sv` shows a number. **[inferred]**: an empty `svList` may mean the camera sets ISO itself (as `tvList: []` did in Av). The GR IV has no TAv on its mode dial: its modes are P, Av, Tv, Snap and M, and M with ISO AUTO lets the camera set the ISO (GR IV user manual pp. 52-53). Next step: a debug log in Av and in M, each with ISO AUTO and with a fixed ISO.

- Camera (device) params: `camera_ricoh_gr_iii.yaml`:
  - `datetime`, `channel` `1..11`, `key`, `ssid`
  - `focusEffectiveArea`
  - `powerOffTransfer`/`autoResize`/`geoTagging` `on|off`
  - `gpsInfo`
  - `bleEnableCondition` `disable|enableAnytime|enablePowerOn`
  - `operationMode` `capture|playback|bleStartup|powerOffTransfer|other` (`:1-59`)
  - These are written via `PUT /v1/params/device` (`impl/ItemCameraParams.java:17,72-87`).
- Firmware cross-check: GR IV `webapid` rodata contains `multi center highlight` and `4K30 4K24 FHD60p FHD30p FHD25p FHD24p HD60p…` near the `reso` table. These are shared string/enum values, **not** evidence of GR IV movie capability: Ricoh's [GR IV specifications](https://www.ricoh-imaging.co.jp/english/products/gr-4/spec/) list movie recording as Full HD 1920×1080 at 60p/30p/24p only. A client must offer only the values in the camera's `movieSizeList` from `/v1/props`, never a hard-coded table.

---

## 5. Per-model behavior (`ImplCameraDeviceWiFiAdapterFactory.createOption`, `:273-457`)

Option flags are `Option(still, stillWithFocus, movie, focus, changeCaptureMethod, powerOff, shootMode, changeExposureProgram)` (`impl/ActionCapture.java:61-70`).

| Model string (exact `/v1/props` `model`) | Flags | URL overrides | Shoot body | Focus |
|---|---|---|---|---|
| `GR II` (`:426-436`) | T,T,F,T,F,T,F,F | `focusURL="http://192.168.0.1/v1/lens/focus/lock"` (malformed after prefixing, §3.1) | `af=camera` always | `/v1/lens/focus/lock` (broken) |
| `RICOH GR III`, `RICOH GR III HDF`, `RICOH GR IIIx`, `RICOH GR IIIx HDF` (`:364-379`) | T,T,T,T,F,T,T,T | movie start/stop, bulb start/stop = `/v1/camera/shoot`; compose = `/v1/camera/shoot/compose` | `""` / `af=on`, `+&pos=X,Y` | `/v1/lens/focus` + WS `lens` wait |
| GR IV (any) | **unsupported**: rejected at detection | – | – | – |

- Images per shot, used to count `captureComplete`:
  - GR III: 2 if the storage `format=="rawdng"`, else 1 (`:369-372`).
  - GR II: 2 if `format=="jpegdng"` (`:429-431`).
- Additional GR III-only behavior:
  - B **and** T are treated as bulb (`impl/ActionCapture.java:270-288`).
  - Busy check uses `stillState` (`impl/ImplCameraDeviceWifiAdapter.java:173-186`).
  - Storage full is checked by `recordableTime` in non-still modes (`:339-347`).
  - The status timer is registered (`:313-321`).
  - WLAN-off is supported (`:755-767`).
- GR II firmware < 1.10 hides channel 6 (`impl/ImplCameraDeviceWifiAdapter.java:887-895`).
- GR II storage lock check: `sd1` must be READ_WRITE (`factory :85-93`).
- GR WORLD vs Image Sync: GR WORLD has no live view, exposure or HTTP-shoot callers (`research/protocol/http-api.md:15,98-107`). Image Sync implements all of them for GR II and GR III/IIIx.

---

## 6. Firmware cross-check summary (GR IV `fw/gr4-route-*.c`, GR III `fw/gr3-route-*.c`)

| Topic | Image Sync | Firmware | Verdict |
|---|---|---|---|
| Live view query | none sent | `maxfps` default 90 (1..90), `reso` optional | Compatible. Image Sync gets default fps and current reso. |
| MJPEG framing | SOI/EOI scan; Content-Length optional | `--boundary` parts, no Content-Length, declared boundary `--boundary` | Agree. A strict multipart parser would mismatch the delimiter. |
| One stream | One thread, no explicit close on stop | Mutex plus "valid socket" replacement | Compatible. Close the socket explicitly in a new client. |
| Shoot keys | `af=`, `pos=` | `ParseKeyValuesString` + `focus_pos` + `shutter_mode` (`af`, default 1) | Agree on keys; values **[unknown]** |
| Focus | `POST /v1/lens/focus` `pos=` | `Capture::Focus` parses `pos`; release option with AF-flag false | Agree |
| Focus lock | GR II only (malformed) | No `/v1/lens/focus/lock` in III/IV | III/IV do not have it |
| Compose / cancel | `POST …/compose`, `…/cancel`, empty body | `Compose` (vtable +0x0c), `CancelShootTimer` (+0x10) (`fw/gr4-route-compose.c:16`, `fw/gr4-route-cancel.c:16`) | Agree |
| Movie / bulb | Toggle on `POST /v1/camera/shoot` | No `/shoot/start` or `/shoot/finish` in III/IV | Agree: GR III/IV toggle via `/shoot` |
| Params | `PUT /v1/params/camera`, `/lens`, `/device` | All three registered; camera returns fetched props | Agree |
| Zoom / compAdjust / memo / `photos/latest` | SDK has them | Absent from III/IV route strings | PENTAX/G900 only |
| WLAN finish | `POST /v1/device/wlan/finish`, empty | `ChangeWlanMode(0)` (`fw/gr4-route-wlan-finish.c`) | Agree |

---

## 7. Implementation recipe (GR III/IIIx; extrapolated to IV with the caveats above)

1. Join Wi-Fi and run `GET /v1/props`. Check `model`.
2. Open `ws://192.168.0.1/v1/changes`. Poll `/v1/props` at 2 Hz or on `changed:"camera"`.
3. Live view: `GET /v1/liveview`. Optionally add `?maxfps=N` (firmware 1..90) and `reso=WxH` **[unknown syntax]**. Split on `FF D8`…`FF D9`. Close the socket to stop, and reconnect on EOF.
4. Touch AF: `POST /v1/lens/focus`, body `pos=<0-100>,<0-100>`, in landscape frame coordinates, clamped to `focusEffectiveArea`. Then wait for WS `{"changed":"lens","captureId":<id>,"focused":bool}`, with a 40 s cap.
5. Shutter:
   - `POST /v1/camera/shoot` with body `""` (no AF), `af=on`, or `af=on&pos=X,Y`.
   - Completion: WS `cameraDirect` (`stateStill` idle/continuous ∧ `countDown` idle ∧ `!capturing`), then `storage` `action:add` `filepath` → `GET /v1/photos/<filepath>/info`.
   - In T/movie mode, POSTing the same endpoint again stops.
   - Self-timer cancel: `/v1/camera/shoot/cancel`. Interval-composite finish: `/v1/camera/shoot/compose`.
6. Exposure: `PUT /v1/params/camera` with body `tv=1.250`, `av=2.8`, `sv=400`, `xv=+0.7`, `WBMode=daylight` or `effect=efc_monochrome`. Only values present in the corresponding `<key>List` are valid. Then re-read the response props, keeping the `/v1/props` lists the response leaves out (see §4.2).
7. Format: `PUT /v1/params/device`, body `stillFormat=rawdng`.

## 8. Open unknowns

- `af` value vocabulary accepted by III/IV beyond Image Sync's `on`, and the meaning of an absent `af` (firmware default int 1). GR II `camera`.
- `pos` units and range as validated by `focus_pos` (Image Sync sends 0..100 integer percent).
- `reso` syntax and allowed values. The default live-view resolution on III/IV (720×480 reported externally).
- Whether III/IV firmware URL-decodes bodies. Image Sync's literal `+` in `xv=+0.3` implies it must not decode `+` as space **[inferred]**.
- Whether GR IV firmware sends WS `capture` and `cameraDirect` at runtime. Its `lens` change is observed (§3.2) and the `cameraDirect` payload is known from webapid (§1.5), including a push when the camera is turned, but neither has been seen on hardware.
- Whether GR IV live view frames stay landscape when the camera is held upright, which physical way round `vertical_right` and `vertical_left` are, and when the camera reports `none` (§1.5).
- Exact HTTP status codes accompanying non-200 `errCode`s on III/IV (Image Sync ignores the HTTP status).
