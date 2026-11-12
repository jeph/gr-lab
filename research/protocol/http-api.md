# GR camera Wi-Fi HTTP / WebSocket API (as used by GR WORLD 2.0.0)

Scope: the API the camera serves on its own Wi-Fi AP at `192.168.0.1`, and how GR WORLD calls it. Everything here comes from static analysis of `libapp.so` (Dart AOT, blutter dump) and the jadx-decompiled Java/Kotlin host code. Conventions:

- `pp+0x…` is an object-pool offset in `work/cs/blutter_out/pp.txt`. `0x…` is a function address in `work/dis/dis.txt`.
- **[inferred]** means a conclusion drawn from code structure. **[unknown]** means static analysis could not settle it.
- Notes on Dart AOT encoding: `true` is `null+0x20` and `false` is `null+0x30` in this snapshot, so `tbnz w0,#4` branches on *false*. Dynamic-call selector offset 0 is `==`. Smi constants are tagged (`0x190` is 200), except when an unboxed `int` field is loaded with `ldur x,[obj,#7]`. In that case `0x190` is 400.

## 0. Summary for client implementers

- Plain HTTP/1.1 on `http://192.168.0.1`, REST-style `/v1/...`. Every JSON response the app parses carries `"errCode"`; success is `errCode == 200`. Errors add `"errMsg"` and sometimes `"detail": {"reason": …}`.
- Two code paths make the requests:
  - **Native Android (Java `HttpURLConnection`)**, reached through the MethodChannel `com.pavct.jp.grapp/wifiConnection` (pp+0x1ff80): photo listing, photo info, transfer list, transfer-state PUT, device status, props, power-off, Wi-Fi params PUT. The app does this so the requests go out over the camera Wi-Fi network bound with `bindProcessToNetwork`, not over cellular.
  - **Dart `package:http`** for image downloads (streamed), image-control BLOB, firmware upload, end-screen upload and camera logs.
- **No caller for the additional liveview/shooting HTTP routes was found in the inspected GR WORLD 2.0.0 Android build.** This is a bounded static result, not proof that every version/platform lacks such a path. The re-audit includes endpoint fragments, native URL builders, AOT request sites, remote-shooting UI/control code and all APK members—not just exact full URLs. The observed shutter path uses BLE; photo previews use `/v1/photos/...?...size=view`, which is not `/v1/liveview` sensor streaming. See §3 for evidence and limits. **Live view, HTTP shutter, touch focus and exposure writes are documented from Ricoh's Image Sync app in [remote-shooting.md](remote-shooting.md).**
- WebSocket `ws://192.168.0.1/v1/changes` pushes `{"errCode":200,"changed":"storage"|"battery"|"camera"}` change notifications. GR WORLD uses only these; Image Sync also handles `cameraDirect`, `lens`, `capture` and `transfer` messages with capture/focus payloads ([remote shooting §2.3](remote-shooting.md#23-completion-tracking-websocket-plus-polling-no-latest-polling-loop)).
- No HTTP Range/resume, no auth headers, no keep-alive tuning. Downloads are a single GET streamed to a temp file. The camera's server sends a file only from its first byte to its last, so a movie cannot be sought in or read from its end; whether one can play while it arrives is open (§2.7).
- **Firmware cross-check:** the analyzed GR III and GR IV `WebapiServer::Run` functions register `/v1/ping`, `/v1/liveview`, `/v1/camera/shoot` and other routes for which this app audit found no caller. [Firmware verification](../firmware-protocol-inventory.md#additional-route-verification) follows dispatch wrappers into substantive implementations. This app-use table is not the complete firmware API; hardware operation and public API support are separate questions.
- **Photos cannot be deleted from the phone.** GR IV 1.20 and GR III 2.20 `webapid` register `/v1/photos/<dir>/<file>` for GET only and never call the camera controller's media-delete commands; Bluetooth and USB have no delete either. See §2.6.

## 1. Endpoint table

Base URL is `http://192.168.0.1`. Dart classes store it in a field (`pp+0x1e7c8`, set in ctors `0x590b60` XSb, `0x795758` xCb, `0x830184` iQb). The photos base `http://192.168.0.1/v1/photos/` (`pp+0x29d58`) is stored in PRb field `+0x13` (ctor `0x57c538`).

| # | Method | Path / query | Request headers / body | Response (keys parsed) | Timeout | Caller / evidence |
|---|---|---|---|---|---|---|
| 1 | GET | `/v1/props` | – | `errCode` num, `model`, `serialNo`, `firmwareVersion`, `macAddress`, `ssid`, `key` (Wi-Fi password), `battery` num?, `storages` [storage obj], `bdName` (BLE name) | 10 s connect+read (Java). 3 s in the connectToWifi verify | Java `p308k6/RunnableC3963a.java:96-127` (channel `getPropertyData`, Dart `0xd289c0`). Parse `0x56b118`. Verify `p168T4/RunnableC1626F.java:118-146` |
| 2 | GET | `/v1/status/device` | – | `battery` num, `storages` list of `{name:String, equipped:bool, writable:bool, available:bool, format:String, remain:num}` | 10 s | `RunnableC3963a.java:41-72` (channel `getDeviceStatus`, Dart `0xd29d64`). Parse `0x56c204`, `0x56bb1c` |
| 3 | POST | `/v1/device/finish` | empty body (`write("")`), no Content-Type | HTTP 200 = success (body ignored) | 10 s connect | `RunnableC3963a.java:73-95` (channel `postCameraPower`, Dart `0xe4bfa4`; UI 'camera power off', result enum `off_success`/`off_failure` pp+0x4dc48/0x4dc90) |
| 4 | GET | `/v1/photos[?storage=<in\|sd1>][&\|?after=<dir>/<file>]` | – | `errCode`, `dirs: [{name:String, files:[String]}]` | 10 s | `AbstractActivityC0655d.java:1028-1040` (channel `getPhotosList`, Dart `0xdbc070`/`0xdbb298`). Parse `0x83913c`, `0x839384` |
| 5 | GET | `/v1/photos/<dir>/<file>/info[?storage=<s>]` | – | `errCode` num?, `cameraModel`, `dir`, `file`, `size` num?, `datetime`, `recordedTime`, `orientation` num?, `aspectRatio`, `av`, `tv`, `sv`, `xv`, `latLng`, `gpsInfo`, `duration` num?, `resolution` (others String?) | 15 s. HTTP 404 is returned to Dart as the literal string `"404 Not Found"` | `AbstractActivityC0655d.java:866-880,919-957` (channel `getPhotosInfo`, Dart `0xdb9df8`/`0xdb7750`). Parse `0x838300` |
| 6 | GET | `/v1/photos/infos?storage=<s>[&after=<dir>/<file>]` | – | raw string to Dart | 120 s | `AbstractActivityC0655d.java:683-696,808-839` (channel `getPhotoInfoList`). **Not called from Dart**: no pool xref to the method name [inferred unused] |
| 7 | GET | `/v1/transfers?status=untransferred[&storage=<s>]` | – | `errCode`, `transfers: [{index:num, filepath:String, size:String}]` | 10 s | `AbstractActivityC0655d.java:1230-1240` (channel `getTransfersList`, Dart `0xdc0b9c` with `status` = `"untransferred"` pp+0x31d88). Parse `0x83a904`, `0x83ac74` |
| 8 | PUT | `/v1/photos/<dir>/<file>/transfer` | `Content-Type: application/json`, body literally `storage=<s>` (or empty string when no storage) | HTTP 200 = success | 10 s connect | `AbstractActivityC0655d.java:846-863` + `p062H0/RunnableC0391f.java:313-339` (channel `putTransferState`, Dart `0xdc0e28`, closure `0xdc0d58`) |
| 9 | GET | `/v1/photos/<dir>/<file>?[storage=<in\|sd1>&]size=<full\|xs>` | – | binary file (JPG/DNG/MOV). See §2.4 | none set (stream) | Dart streamed `Request("GET")` `0xdc2064`, URL built in `0xdbe510` |
| 10 | GET | `/v1/photos/<dir>/<file>?[storage=<in\|sd1>&]size=<thumb\|view>` | – | JPEG thumbnail / preview | widget image loader | prefix `0xdb8a38` (`"?storage=sd1&"` pp+0x31988, `"?storage=in&"` pp+0x31990, `"?"` pp+0x15d8). Suffix in UI `0x977b64`, `0x971b54`, `0x9792f4` (`size=thumb` pp+0x323b0, `size=view` pp+0x323b8). Image-control thumbnails `0xe3cac0` |
| 11 | GET | `/v1/photos/<dir>/<file>/imgctrl?storage=<in\|sd1>` | – | binary Image-Control BLOB (`bodyBytes`). See §4.3 | 5 s (pp+0x284d8) | `0xd8f0fc` (`"/imgctrl?storage="` pp+0x32be0). Parse `0xd8e104` |
| 12 | PUT | `/v1/params/device` | `Content-Type: application/json`, body literally `channel=0&ssid=<ssid>&key=<password>` (form-encoded text, no URL-escaping) | HTTP 200 = success | 10 s connect | `RunnableC0391f.java:340-367` (channel `putWifiInfo` with `ssid`,`password`; Dart `0xe2a4c0` called from Wi-Fi settings flow `0xe287f4`) |
| 13 | PUT | `/v1/device/image/endscreen?index=<n>[&sha256=<hex>]` | `Content-Type: image/jpeg`. Body = JPEG bytes (variant A) or no body (variant B) | `errCode`, `errMsg` | 60 s (pp+0xade8) | `0xe2c7b8` (pp+0x34ef0, `&sha256=` pp+0x34ef8). Callers `0xe2bbec` (bytes + sha256), `0xe2e5e0` (no body, no sha256) |
| 14 | GET | `/v1/logs/camera?type=monthly_capture&date=<YYYY-MM>` | – | `errCode`, `errMsg`, `type`, `date`, `dailyData` (see §6) | 10 s (pp+0x20518) | `0xe0a4c0` (pp+0x38ef0). Parse `0x90d178`. Date built in `0xe07a28` |
| 15 | POST | `/v1/configs/firmware/prepare` | `Content-Type: application/x-www-form-urlencoded`, body `filesize=<bytes>` | `errCode`, `errMsg`, `detail{reason}` | 60 s | `0xdd7268` (pp+0x2aff8, `filesize=` pp+0x2b000) |
| 16 | PUT | `/v1/configs/firmware?storage=in&reboot=true` | `Content-Type: application/octet-stream`, body = whole firmware file in one request | `errCode`, `errMsg`, `detail{reason}` | 180 s (pp+0x2af50) | `0xdd698c` (pp+0x2af48) |
| 17 | POST | `/v1/configs/firmware/cancel` | no headers, no body | `errCode`, `errMsg`, `detail` | none | `0xddcca4` (pp+0x2aaa0) |
| 18 | WS | `ws://192.168.0.1/v1/changes` | – | `{"errCode":200,"changed":"storage"\|"battery"\|"camera"}` | none, no ping interval set | `0xd22098` (pp+0x28430). Handler `0xd28f24` |

Storage values: `"in"` (internal memory, pp+0x11290) or `"sd1"` (SD slot, pp+0x31808). The app sends `sd1` when the selected storage enum `aFb` equals `sdSlot` (pp+0x315a8), otherwise `in`. The storage parameter is only added when a per-camera value equals 2 (`0xdbb41c`, `0xdbe6e8`), which is **[inferred]** to be "camera has two storages" (GR IV: internal + SD). Single-storage cameras get the URLs without `storage`.

GR IV webapid 1.20 (found in code, not observed; Rea evidence bundle `firmware/evidence/gr4-webapid-storage-events.json`, 2026-11-09): `GET /v1/photos` checks the storage with `CheckAvailableStorageId` (`0xbbb16`), which requires it to be equipped, accessible, formatted (format state 1) and without error, and answers `InternalServerError` (500) otherwise. That same condition is what `/v1/props` reports as a storage's `available` (`Storage::Fetch` `0xa95f8`, serialized by `0xa90ee`). So a storage that is equipped but not available (an unformatted card, one in an error state) cannot be listed. Other listing failures map through `ConvertResponseToErr` (`0x8e458`): controller results 1, 11, 12 and 13 become 400, 2 and 10 become 412, anything else, including a failed request to the camera's RTOS, 500. Which camera states produce a 412 or 500 for a healthy card is **[unknown]**.

Java request settings (all native calls): `HttpURLConnection`, no custom headers except where listed, `getResponseCode()==200` is the only success test. Non-200 results go back to Dart as `PlatformException("GET error"/"PUT error"/"POST error", "response", "<code>")`. Exceptions go back as `("Exception", "GET error", msg)` (e.g. `AbstractActivityC0655d.java:715-735`). On the Dart side these are mapped to `lTb` ER_WF errors (pp+0x27b38 = `getException` ER_WF_003).

## 2. Gallery import flows

### 2.1 Directory listing (paged)
`0xdbb298`:
1. `storage` = `sd1`/`in` if the two-storage condition holds, else null (`0xdbb414-0xdbb464`).
2. Call `getPhotosList(storage, startFileName)`. The first call has `startFileName` = null (`0xdbb48c-0xdbb4d8`).
3. Native: `GET /v1/photos[?storage=…][&after=<startFileName>]` (10 s).
4. `jsonDecode`, then parse `{errCode, dirs:[{name, files:[…]}]}` (`0x83913c`). If `errCode != 200` or `dirs` is empty, stop (`0xdbb59c-0xdbb5b0`).
5. Sum the file counts over all dirs. `lastFile = "<lastDir.name>/<lastDir.files.last>"` (`0xdbb5e4-0xdbb6cc`, log `", lastFile: "` pp+0x31dd8).
6. If the page held **≥ 3000 files** (`cmp x0,#0xbb8`, `0xdbb728`), request the next page with `after=lastFile`. Otherwise stop. The camera therefore pages at 3000 entries **[inferred]**.

Example (JSON shape from the parser, values illustrative):
```json
{"errCode":200,"dirs":[{"name":"100RICOH","files":["R0000001.JPG","R0000002.DNG"]}]}
```

### 2.2 Per-photo info
`0xdb7750`: `getPhotosInfo(path="<dir>/<file>", storage)` calls `GET /v1/photos/<dir>/<file>/info[?storage=]` (15 s). The result is decoded into the model at `0x838300` (keys in table row 5; `errCode`, `size`, `orientation` and `duration` are typed `num?`, the rest `String?`). On error it logs `": "`/`"\n\n"` and still builds a model with defaults.

GR WORLD requests the info for every listed photo in a background loop (`0xdb6338`, called from `0xdb5b48` after the listing `0xdbb298`). The UI shows "情報取得中です。" (pp+0x66db8, "Getting info"). Starting a transfer cancels the loop ("Cancel getInfo-> transfer start: " pp+0x325b0, "getting info is canceled: " pp+0x31ec8). Results go into the local `photo_info` table (pp+0x20dd0: `datetime INTEGER`, `recorded_time TEXT`, `av`/`tv`/`sv`/`xv`, `lat_lng`, `gps_info`, plus thumbnail and view cache paths). Whether it skips photos already in the table is **[inferred]**. The info has no drive mode or sequence field; see [burst grouping](../burst-grouping.md).

### 2.3 Thumbnails / previews
UI image widgets load `…/v1/photos/<dir>/<file>?storage=<s>&size=thumb` for grid cells and `size=view` for the large preview (`0x977b64` picks thumb vs view on a widget mode field). With one storage the URL is `…/<file>?size=thumb`.

### 2.4 Full download (manual import and auto-transfer)
Size choice:
- Import size enum `hOb`: `thumb`(0), `view`(1), `full`(2), `xs`(3), `single`(4) (`work/cs/blutter_out/objs.txt`:54002-54031).
- Manual import `0xe3a278`: if the setting is `xs` (pp+0x317b8) **and** the extension is `JPG`, the suffix is `?size=xs`. Every other case uses `?size=full`, including DNG and MOV, which are always full (`0xe3a9b0-0xe3aadc`).
- Auto transfer `0xdbdd14` does the same using the transfer item's `size` string: `size == "xs" && ext == "JPG"` gives `?size=xs`, else `?size=full` (`0xdbe304-0xdbe40c`).

URL (`0xdbe510`, `0xdbe6e8-0xdbe7a0`): `http://192.168.0.1/v1/photos/<dir>/<file><suffix>[&storage=<s>]`. Note that storage comes *after* `size` here.

Download engine `0xdc2064`. It runs in the flutter_foreground_task isolate; logs prefixed `FGS:`.
1. `http.Request("GET", Uri.parse(url))`, `client.send()` (`0xdc2264`).
2. If `statusCode != 200` or `contentLength == null`, log `"ErrorCode <code>: 該当画像なし、転送処理をしない"` ("no matching image, skip transfer", pp+0x250/0x258) and report error (`0xdc229c-0xdc22b0`). **A client must expect Content-Length on success.**
3. Stream chunks into `File("<tmp>/TempImage/<name>")` (`0xdc2a38`, `'TempImage'`). Progress is reported as `{status:"loading", receiveAllBytes:n}` (closure `0xdc2d88`).
4. **Error-in-body detection**: on the *first* chunk only, the bytes are UTF-8 decoded. If the text starts with `{` it is `jsonDecode`d, and `errCode != 200` raises `transferException` ER_IMG_004 (`0xdc2e88-0xdc2f48`, eTb pp+0x330). The camera can return HTTP 200 with a JSON error body instead of image bytes **[inferred]**.
5. onDone gives `{status:"success", file, fileName, directory}` (`0xdc2af4`). onError gives `{status:"error", exception}`.
6. No `Range` header and no resume support. A cancel (`isCanceled` flag pp+0x1f8) aborts and the next attempt starts from zero.

### 2.5 Camera-initiated "reserved transfer" (auto transfer)
`0xdbdd14` (caller `0xdbc234`, log `予約転送処理エラー` "reserved transfer processing error", pp+0x31890) loops until it sees `isCanceled` or an empty list:
1. `GET /v1/transfers?status=untransferred[&storage=]`, then `{errCode, transfers:[{index, filepath, size}]}`.
2. If `errCode != 200` or the list is empty, finish (`0xdbe4b0`).
3. For each item: `filepath.split("/")`. `[0]` is the dir, `[1].replaceAll("?xs","")` is the file (`0xdbe250-0xdbe2e8`), so `filepath` may carry a `?xs` suffix **[inferred]**.
4. `GET …/<dir>/<file>/info` (§2.2), then download (§2.4).
5. `PUT /v1/photos/<dir>/<file>/transfer` with body `storage=<s>` to mark the item transferred (`0xdbe470-0xdbe4a4` → `0xdc0d58` → `0xdc0e28`).
6. Re-query the list (step 1).

Other log strings show how the info fetch and an in-flight transfer interact: `"Cancel getInfo-> transfer start: "` (pp+0x325b0, `0xe4054c`), `"転送中のエラーは無視して情報取得を開始する"` ("ignore errors during transfer and start fetching info", `0xdb5b48`), `"getting info is canceled: "` (`0xdb6338`). The app cancels its background info fetch before starting a transfer, and lets an info fetch start after transfer errors.

### 2.6 Deleting photos: not possible over Wi-Fi

Found in code, not tried on hardware (GR IV `webapid` 1.20, SHA-256 `27d3d36f…7f8dd2`, Ghidra 12.1.4 through Rea, 2026-11-10; Ghidra addresses are the ELF's plus `0x10000`). Neither Ricoh app deletes photos on the camera, and the firmware offers no way to:

- **No route accepts DELETE for a photo.** `WebapiServer::Run` (`firmware/evidence/gr4-webapid-run.json`) sets an explicit crow method mask only on `/transfer` (`0x10`, PUT), the params routes (`0x10`), the POST routes (`0x08`) and `/v1/configs/firmware` (`0x11`, PUT and DELETE, whose handler refuses DELETE; see [firmware update §3.1](firmware-update.md)). `/v1/photos`, `/v1/photos/<string>/<string>`, `/info`, `/imgctrl` and `/v1/photos/infos` keep crow's default, GET only, so crow answers any other method itself. The method-labelled literals agree: `GET /v1/photos/{}/{}` and `PUT /v1/photos/{}/{}/transfer` are the only ones under a photo.
- **The photo handler cannot delete.** The `/v1/photos/<string>/<string>` lambda (`0x43938`) calls `Photos::GetAndSendImage` (`0x85280`) without reading the method; that is the only reference to it (`0x43a1a`). `webapi_server::Photos` has no delete function: `GetPhotoList`, `GetPhotoInfo`, `GetPhotoInfoList`, `GetLocalMediaList`, `GetAndSendImage`/`FullImage`/`SmallImage`, `GetAndSendPhotoImageCtrl`, `SendFileImage` and `SetTransferState` only.
- **`webapid` never asks the controller to delete.** `libcamera-controller.so`'s `MediaCommandImpl` has `DeleteMedia` (vtable slot `+0x24`), `DeleteDcfMedia` (`+0x28`) and `DeleteTransferCandidate` (`+0x38`). The six `webapid` functions that fetch `CameraController::GetMediaCommand` (callers of `0x3ddd4`: `PhotoInfo::Fetch` and five `Photos::` handlers) call only slots `+0x0c` (DCF list), `+0x10`, `+0x18` (`GetWebapiMediaInfo`), `+0x20`, `+0x3c` (`GetWebapiMediaList`) and `+0x40` (`GetMediaImageCtrl`). Rea evidence: callers `ev_33f9e9e8…8f0`, decompilation `ev_14035d5c…29b3`, procedure inventory `ev_dd80987d…9a4`.
- **GR III 2.20 is the same.** Its `webapid` has the same `Photos::` functions without a delete, the same GET-only photo literals, and the same masks in `firmware/evidence/gr3-webapid-run.c`.
- **No other channel.** `bled` has no delete characteristic (its only delete is `DeleteBlePairedDevice`); USB answers `DeleteObject` with OperationNotSupported ([usb.md](usb.md)); the Image Sync SDK and GR WORLD send no delete. `DeleteDcfMedia` is reachable only inside the camera (`camctld`, `mtpd`).

A later firmware may add a route; this covers GR IV 1.20 (and the byte-identical GR IV Monochrome image) and GR III 2.20 only.

### 2.7 Movies: sent only from start to end; playing while copying is open

Checked on 2026-11-11 for whether a movie on the camera can play without being copied first. The camera cannot serve part of a file, which rules out seeking and reading a file's end first. It does not rule out playing a movie as its bytes arrive: that depends on two facts nothing here settles, where the file keeps its `moov` box and how fast the camera's Wi-Fi really is.

- **GR WORLD never plays a movie that is on the camera** (found in code). Its camera browser shows a movie as a still: the grid cell (`0x977b64`) loads `size=thumb` and adds a movie badge (`images/image_picker/movie/movie.png`, pp+0x32400), and the single view (`0x9792f4`, `0x971b54`) loads `size=view`. Neither builds a player. The only requests for a MOV's bytes are the two imports of §2.4, always `size=full`, and an imported movie is saved to the phone through `saveVideo` under `Movies/GR WORLD` (`0xdc085c`). The app has one `video_player` constructor, `VideoPlayerController.file` (`0x853f88`: it stores data source type `file`, pp+0x4f5b0, and a file URI of its argument), called from two places (`0x853978`, `0x854260`) with a `File` the widget holds. `DataSourceType.network` (pp+0x4f5a8) is referenced only inside `initialize` (`0xdd18c8`), so no network player is ever built. The viewers with that player draw a play button from `images/gallery/resume.svg` (build functions `0x9aac4c`, `0x9b4ad4`), and the closure created beside it (`0x9ab268`) starts an Android `ACTION_VIEW` intent of type `video/*` (`0xe53fe4`, `0x9ab3b8`) and fails with `asset: null` without a photo-library asset. That these are the viewers of the app's gallery of imported files, and that the closure is the button's handler, is **[inferred]** from the asset paths and the intent.
- **The camera sends a file only whole** (found in code: GR IV `webapid` 1.20, SHA-256 `27d3d36f…7f8dd2`, Ghidra 12.1.4 through Rea, 2026-11-11, Rea evidence `ev_54b545c8…b734`). `Photos::GetAndSendImage` (`0x85280`) reads the `size` and `storage` query parameters and nothing else of the request. `Photos::SendFileImage` (`0x83708`) opens the file, sends a fixed header (a `Content-Type` chosen by file type, `image/jpeg`, `image/x-adobe-dng`, `video/quicktime` or `application/octet-stream`, and a `Content-Length` of the whole size) and then reads the file from its start in 1 MiB pieces, sending each, until that size is sent. It reads no request header and never seeks. `webapid` and `libcamera-controller.so` hold no `Range`, `Content-Range` or `Accept-Ranges` text, and crow's status table has no 206. GR III 2.20's `webapid` exports the same `SendFileImage` and has the same log texts and none of the range ones (symbols and strings only, not decompiled) **[inferred]**.
- **Observed** (GR IV HDF, fw 1.20, 2026-11-11, a GR Lab trace): a `size=full` JPEG response carried `content-type`, `content-length`, `cache-control`, `pragma` and `expires` and no `accept-ranges`, and a file of about 12 MB arrived in 2.6 s, about 39 Mbit/s. That is one sample; the Wi-Fi band and the distance were not recorded. A request with a `Range` header has not been sent to a camera.
- **There is no smaller movie.** Both Ricoh apps ask for `size=xs` for a JPG only (§2.4), and a movie's `thumb` and `view` are JPEG stills. What the firmware answers to `size=xs` for a MOV is **[unknown]**.
- **Whether the Wi-Fi keeps up with a movie's bit rate is [unknown].** The GR IV manual's capacity table (p. 174: a 64 GB card holds 1:37'38" at Full HD 60p, 3:11'53" at 30p and 3:57'48" at 24p) works out to about 85, 43 and 35 Mbit/s **[inferred]**; an actual file's bit rate has not been read. The only throughput measured is the one 39 Mbit/s sample above, of a small file whose time includes the request and the start of the connection, so it is neither the link's ceiling nor its steady rate. If a movie did arrive at that rate, copying would take about 2.2, 1.1 and 0.9 times its length, and the largest movie the camera records (4 GB, or 25 minutes) about 14 minutes. Time a movie's download on each Wi-Fi band and read its bit rate to settle it.
- **Whether a movie can start playing before its copy is complete is [unknown].** A player cannot start before it has the file's `moov` box, and without ranges the end of a file cannot be fetched before the rest. If the camera writes `moov` before the media data, a movie could start playing while its copy runs, for example from a server on the phone's loopback address that answers the player's range requests out of the bytes copied so far; that would also suit iOS's player, which requires byte ranges, and keep Android's player off the camera's network. Seeking ahead would wait for the copy to reach that point. If `moov` comes last, as is usual for files a camera records, nothing can play until the copy is complete. Read the box order at the start of one movie copied from a camera.

GR Lab copies a movie whole into its movie cache and plays the copy (`packages/gr_camera/lib/src/library/movie_cache.dart`).

## 3. Remote shooting / live view
The expanded audit found no app caller for the ten additional firmware routes. Searches covered `work/dis/condensed.txt`, `work/dis/dis.txt`, `work/cs/blutter_out/pp.txt` and the JADX source tree, including fragments, request construction, liveview/remote-preview variants and Japanese UI terminology. Remote-shooting text is present, but does not itself establish a sensor preview. The shutter handler at `0xe52138` calls its release helper at `0xe5247c`; the observed BLE release encoder calls the BLE write routine `0xe5c094` at `0xe61b84` (see [BLE remote shooting](ble.md#remote-shooting-over-ble-no-wi-fi-needed)).

A separate byte search read **all 1,476 regular members / 53,218,932 uncompressed bytes** of the base, arm64, English, Spanish and xxhdpi APKs pulled from the phone, including DEX, native libraries and unextracted assets. Searches for the extra path fragments and `liveview`, `live_view`, `live view` in UTF-8/UTF-16LE/UTF-16BE found no matches. Positive controls found `getPhotoInfoList` and `/v1/photos/infos` in `classes.dex`. Exact archive hashes, terms and matches are retained in `firmware/evidence/grworld-extra-route-archive-search.json`.

`GET /v1/photos/infos` is a separate case: the Android channel implements `getPhotoInfoList` (`p085J6/AbstractActivityC0655d.java:683–696`, duplicated at `1784–1796`), but no corresponding Dart identifier/caller was found. Classify it as **native implementation present, Dart invocation unobserved**, not as a demonstrated request or proven dead code.

The app does use `size=view`/`size=thumb` photo URLs (§2.3). Those retrieve stored images, not changing sensor frames. Obfuscated/computed strings, externally supplied URLs, unobserved dynamic dispatch and other app builds/platforms remain outside a universal absence proof. No app-on-camera traffic capture was obtained. The prior categorical “no live view exists in this app” wording was stronger than the evidence.

Independent product evidence supports the bounded result: [Ricoh's GR WORLD FAQ](https://www.ricoh-imaging.co.jp/english/support/qa/gr-world/) explicitly says **“No. Live View is not supported in the app”**, describes Bluetooth shutter release, and excludes exposure adjustment. [Image Sync](https://www.ricoh-imaging.co.jp/english/products/app/image-sync2/), a different Ricoh app, documents Live View and remote capture for GR III/IIIx. The product distinction does not establish which screen/app/version a user previously observed.

## 4. Settings

### 4.1 Connection setup (all models) – `0xd1d508`
1. `0xd28c9c`: refreshes the connected-SSID state.
2. `getPropertyData` → `GET /v1/props`. Only when the model string contains `GR II` **and does not** contain `GR III` is the raw JSON passed through a regex fix-up (`0xd28a5c`: `tbz` on the `GR III` match jumps straight to return at `0xd28b98`; `0xd28a88`: a failed `GR II` match also returns). The fix-up is `"key" : "([^,]*)` (pp+0x28840, `0xd28a8c-0xd28b84`), then `replaceAll(match, match + <pp+0x1c38>)`. pp+0x1c38 is undecoded by blutter **[unknown]**. Purpose **[inferred]**: repair a malformed `key` (password) field in GR II firmware JSON.
3. Parse props (`0x56b118`). Store the model with `RICOH` stripped, plus serial etc., in the device DB (`0xd28538`).
4. Open the WebSocket (§5). For `GR III`/`GR IV` model strings the message handler is a no-op (`0xcca1bc` just returns null; `0xd1d7e0`). For `GR II` (`deviceModel: GR2` log pp+0x27aa8) the handler `0x56c1c8` → `0xd28f24` processes change events.

The native `connectToWifi` path verifies that it reached the right camera (`RunnableC1626F.java:118-146`). It calls `GET /v1/props` with a 3 s timeout and requires all of:
- `errCode == 200`
- `ssid` equals the expected SSID
- the first 8 characters of `serialNo` (`m792k0(8, …)` = Kotlin `take(8)`) equal the expected serial
- `model` with `"RICOH"` removed and trimmed equals the expected model
- `bdName` equals the expected BLE name.

### 4.2 Wi-Fi SSID/password over HTTP
`0xe287f4` (Wi-Fi settings update) builds a value derived from the stored SSID (it strips pp+0x1c38 from it, `0xe28e94-0xe28e9c`) and `==`-compares it with another value at `0xe28ebc-0xe28ecc`. `putWifiInfo` is called only when that comparison is **true**; on false it branches past the call (`tbnz w0,#4,#0xe29aa4` at `0xe28ed0`). The exact operands were not traced, so treat this as an equality guard of unknown meaning **[unknown]**. The call is `putWifiInfo(ssid, password)` → `PUT /v1/params/device` with body `channel=0&ssid=<ssid>&key=<pw>`. The body is labelled `application/json` even though it is form-style text. **[inferred]** this is the GR II path (GR II has no BLE). For BLE models the same settings are written as BLE characteristics: log strings `write ssid:`, `write pass`, `write wlanFrequency` (`0xe23268`, `0xe25d08`, `0xe23f24`), and `write datetime` (`0xe21cf8`). On the phone, `connectToWifi` uses `setWpa3Passphrase` when the security int is 1 or 2, else WPA2 (`AbstractActivityC0655d.java:640-647`). This selects the join request, not the AP configuration: GR IV's camera-side generator also edits hostapd security and PMF settings from camera properties; see [firmware network configuration](../firmware-network-config.md#gr-iv-band-templates-and-native-generation).

### 4.3 Image Control read (`/imgctrl`) and BLOB header
`0xd8f0fc`: `GET {photosBase}<dir>/<file>/imgctrl?storage=<sd1|in>` with a 5 s timeout. If the status is 200 it returns `bodyBytes`, else it logs `"Image Control get error: <code> …"` (pp+0x30010). `0xd8eb6c` performs the same GET (30 s, pp+0x30008) on a URL stored in a gallery item model. The origin of that URL is **[unknown]**.

BLOB parsing `0xd8e104`:
- Length must be ≥ 4 (`0xd8e148`).
- `byte[0]` = version, which must be in `{1,2,4}` (Set pp+0x2bcb8). Otherwise it logs `未対応のイメコンバージョン` ("unsupported image-control version").
- `byte[2]` = Custom Image id. It is mapped to enum `mRb` by its first int field (`0x7cd184`/`0x7cd218`):

| byte[2] | name | label |
|---|---|---|
| 0 | standard | Standard |
| 1 | vivid | Vivid |
| 2 | monotone | Monotone |
| 3 | softMonotone | Soft Monotone |
| 4 | hardMonotone | Hard Monotone |
| 5 | highContrast | Hi-Contrast B&W |
| 6 | posiFilm | Positive Film |
| 7 | bleachBypass | Bleach Bypass |
| 8 | retro | Retro |
| 9 | hdr | HDR Tone |
| 0xd | negaFilm | Negative Film |
| 0xe | cinemaYellow | – |
| 0xf | cinemaGreen | – |
| 0x10 | crossProcess | Cross Processing |
| 0x11 | standardMono | Standard |
| 0x12 | softMono | Soft |
| 0x13 | highContrastMono | High Contrast |
| 0x14 | grainy | Grainy |
| 0x15 | solid | Solid |
| 0x16 | hdrMono | HDR Tone |
| 0x17 | pallet | Palette |
| 0x18 | solarization | Solarization |
| 0x19 | pictorialist | Pictorialist |

  Unknown ids map to `unknown`, which aborts the parse (`0xd8e35c`). The second int of each enum entry (e.g. standard→1, negaFilm→8) is a different id space **[unknown]** (perhaps the BLE/UI id).
- `byte[3]` = "parameter num" (log `, parameter num:` pp+0x2bce0).
- This is followed by N two-byte `(parameter id, signed int8 value)` pairs. The same parser `0xd8e104` handles the BLE Image Control characteristics; the parameter-id table and value encoding are in `ble.md` § Image Control blob. Parameter ids come from the 36-entry table `nRb` (pp+0x2bcf8), whose entries also carry a second id (e.g. saturation 0→0x64) whose meaning is **[unknown]**. Invalid values log `イメコン不正値:` ("invalid image-control value", pp+0x2bd08).
- *Applying* Image Control to the camera is not done over HTTP (no PUT/POST to imgctrl exists). It is written to the Custom 1–3 data/name characteristics of the BLE Camera Control service (see `ble.md`).

### 4.4 End screen upload
`PUT /v1/device/image/endscreen?index=<n>`:
- Variant A (`0xe2bbec`): body = JPEG bytes, plus `&sha256=<lowercase hex SHA-256 of the JPEG>` (`package:crypto` sha256 `_Bya` pp+0xf4d0; hex via `0xac5c3c` **[inferred lowercase]**).
- Variant B (`0xe2e5e0`): no body and no sha256. **[inferred]** clear/reset slot `n`.
- Header `Content-Type: image/jpeg` in both variants. Timeout 60 s.
- Response `{errCode, errMsg}`. `errCode != 200` maps to `kTb` (`0xe2cef8`): 400 BadRequest ER_API_001, 403 Forbidden ER_API_002, 404 NotFound ER_API_003, 412 PreconditionFailed ER_API_004, 500 InternalServerError ER_API_005, 503 ServiceUnavailable ER_API_006, other ER_API_999.
- The end-screen image itself is fetched beforehand by `0x952890` from a URL held in the end-screen model (60 s). This is **[inferred]** to be a cloud URL (`/v1/endScreen*` on the AWS API), not the camera.

### 4.5 Power off
`POST /v1/device/finish` (row 3). Afterwards the app closes the WebSocket (`0xe4c108` → `0xd44f70` sets state `disconnected`, pp+0x28468, and closes the sink) and tears down the Wi-Fi binding.

## 5. WebSocket `ws://192.168.0.1/v1/changes`

Open (`0xd22098`):
1. Skipped if a channel already exists (`0xd220e8`).
2. `WebSocketChannel.connect(Uri.parse(url))` (`0x551a58`), then `await channel.ready`. State becomes `connected` (KLb pp+0x28438).
3. `stream.listen(onData, onError, onDone, cancelOnError: true)` (`0xd22234-0xd22248`).

No `pingInterval`, protocols or headers are set **[inferred from call args]**.

- onData `0xd27770`: prints the message and calls `handler(message)`.
- onError `0x569a18`: only logs `onError: … closeCode: … closeReason:`.
- onDone `0x569938`: logs and sets state `disconnected` (pp+0x28468). This file contains **no automatic reconnect**. Reconnection happens only when the connection setup (`0xd1d508`) runs again (callers `0xd1d1f4`, `0xdd9fe0`, `0xdda950`), which is driven by the Wi-Fi/BLE connection logic (see the connection-lifecycle doc).
- Close: `0xd44f70` (callers: disconnectWifi `0xd44ea0`, power-off `0xe4c108`, `0xe855a4`).

Message schema (handler `0xd28f24`, GR II path only):
```json
{"errCode":200,"changed":"storage"}   // or "battery" / "camera"
```
- If `errCode != 200` the message is ignored (`0xd29070`).
- If `changed` ∈ {`storage`,`battery`,`camera`}: re-check the connected SSID (`0xd28c9c`), call `getDeviceStatus` → `GET /v1/status/device`, parse `{battery, storages[…]}` (`0x56c204`), and update the device/storage state providers. The model also gets a re-read via the `get:` log path **[inferred]**.
- Other `changed` values are ignored (`0xd2910c`).

For GR III/GR IV the socket is opened but its messages are ignored (no-op handler). It works only as a liveness signal: socket closed ⇒ `disconnected`.

### GR IV firmware: `storage` changes

Found in GR IV webapid 1.20 code, not yet observed on hardware (Rea evidence bundle `firmware/evidence/gr4-webapid-storage-events.json`, 2026-11-09):

- `StorageEvent::Serialize` (`0xab8a8`) sends `{"errCode":200,…,"changed":"storage","action":…,"storage":…,"filepath":…,"captureId":…}`; `captureId` is written as a JSON number.
- The action table (`_INIT_41` `0xabfc4`) maps `add`, `delete` and `format`. `storage_action::ConvertToWebapi` (`0xabc6c`) drops the other raw actions, including 4 ("storage info changed", which libcamera-controller's `CacheController::StorageChanged` `0x69af4` handles internally). `StatusEventHandler::StorageChanged` (`0x8d23c`) sends nothing for an event whose result is not 0, and `StorageEvent::Create` (`0xabd78`) drops paths that are not DCF paths, strips the `DCIM/` prefix, and sends `format` with an empty `filepath`.
- `WebsocketAdapter::IssueEvent` (`0x6b97c`) sends each change to the sockets open at that moment; nothing is queued or replayed, so a client whose socket was closed misses the changes made meanwhile.
- **[inferred]** A delete on the camera body reaches webapid as `delete`: the RTOS has `NotifyFileDeleted` next to `NotifyFileCreated` (strings only, not traced). **[unknown]** Whether a multi-delete or delete-all sends one change per file, whether the camera allows deleting while its Wi-Fi is on, and whether inserting or removing a card sends any change.

Neither Ricoh app acts on a `storage` `delete`: Image Sync acts only on `add`, and GR WORLD ignores the socket on GR III and IV.

## 6. Camera log (GR Log)
`GET /v1/logs/camera?type=monthly_capture&date=<YYYY>-<MM>`. The month is zero-padded with `padLeft(2,"0")` (`0xe07e2c-0xe07ee4`). The app iterates months up to the current one (`CameraLog: currentMonth completed->`). Response parsed by `0x90d178`: `errCode`, `errMsg`, `type`, `date`, `dailyData`. Sub-parsers (exact nesting **[inferred]**):
- `0x90d5c4` keys `still`, `video`.
- Still: `0x90fc38` keys `count`, `exposure`, `effect`, `aspect_ratio`, `crop_size`.
- Video: `0x90d6b8` keys `count`, `exposure`, `effect`, `size`, `drive`.
- Value vocabularies:
  - exposure: `P,TV,AV,M,B,T,BT,SFP` (`0x90f58c`)
  - effect: `off,col_vivid,efc_monochrome,…,efc_pictorialism` (`0x90df58`)
  - aspect: `1:1,3:2,4:3,16:9,5:4,21:9` (`0x910230`)
  - crop: `Off,35mm,50mm,71mm` (`0x90fea8`)
  - video size: `VGA,HD,FHD,4K` (`0x90dbec`)
  - drive: `normal,snap` (`0x90da24`)

## 7. Firmware update over Wi-Fi
**Our app: not in v1.** The firmware screen is in the mock-ups, but v1 won't implement updates. GR WORLD gets the package from Ricoh's online service, which our app doesn't use, and whether the file on Ricoh's public download page has the same format is unverified. See design notes (`design/README.md#not-in-v1`).

The full flow, the camera's handlers and the error reasons are in [firmware update](firmware-update.md). In short:
1. The package comes from Ricoh's cloud (`…/v1/fwDownload` pp+0x2a080) as `update.zip`, unzipped to `updateInfo.json` and `fwdc248b.bin` (`0xddc0d0`).
2. BLE turns WLAN on and the phone joins the camera Wi-Fi (`0xdd3c14`).
3. `POST /v1/configs/firmware/prepare` with body `filesize=<firmware length>` (`0xdd7268`), then `PUT /v1/configs/firmware?storage=in&reboot=true` with the whole file (`0xdd698c`). Both answers are parsed as `{errCode, errMsg, detail:{reason}}` (`0x855200`); `errCode == 200` is success.
4. The camera restarts; the app reconnects over BLE and finishes the update with the BLE start/result characteristics.
5. `POST /v1/configs/firmware/cancel` (`0xddcca4`) is sent only while the upload is in progress.

`detail.reason` values the GR IV firmware sends: `battery_too_low` (412), `err_fw_same`, `err_fw_old`, `err_fw_broken` (400). The `step…` strings in the app are analytics results, not wire values.

## 8. Error codes and status handling
- Every camera JSON response: `errCode` (HTTP-like int; 200 = OK), optional `errMsg` (string), optional `detail` object (`reason`).
- Image transfer errors `eTb`: ER_IMG_001 GetError, 002 PutError, 003 CancelError, 004 TransferError (JSON error body or stream error), 005 SaveError, 006 TimeOutError.
- Wi-Fi/channel errors `lTb`: ER_WF_001 ConnectError, 003 GetError (any native GET/PUT failure), 006 CheckSSIDError, 007 InternalError(iOS), 008 cancellation, 009 ConnectTimeoutError, 010 VPNError (a VPN blocks the camera connection).
- API errors `kTb` (end-screen PUT; same enum used for the cloud API): 400/403/404/412/500/503/other → ER_API_001…006/999.

## Evidence
- URL strings:
  - pp+0x1e7c8 `http://192.168.0.1`
  - pp+0x29d58 `http://192.168.0.1/v1/photos/`
  - pp+0x28430 `ws://192.168.0.1/v1/changes`
  - pp+0x2aff8 / 0x2af48 / 0x2aaa0 firmware paths
  - pp+0x34ef0 endscreen
  - pp+0x38ef0 logs
  - pp+0x32be0 imgctrl
  - pp+0x317f8/0x31800 `?size=xs`/`?size=full`
  - pp+0x323b0/0x323b8 `size=thumb`/`size=view`
  - pp+0x31988/0x31990 storage prefixes
  - pp+0x31f58 `&storage=`
- Java: `p085J6/AbstractActivityC0655d.java:529-1250` (channel switch); `p308k6/RunnableC3963a.java:41-127`; `p062H0/RunnableC0391f.java:313-367`; `p168T4/RunnableC1626F.java:111-150`.
- Dart `package:http`:
  - `get` `0x7cd2d8` (callers `0x952890 0xd8eb6c 0xd8f0fc 0xda42a4 0xddc594 0xe0a4c0 0xe3d768 0xe42cc0`)
  - `post` `0x5854d4` (`0xd38a24` cloud, `0xdd7268`, `0xddcca4`)
  - `put` `0x8556a0` (`0xdd698c`, `0xe2c7b8`)
  - `_sendUnstreamed` `0xd3ad48`; `Request` ctor `0x5866c8`
- Durations (µs): pp+0x284d8 5 s, pp+0x20518 10 s, pp+0x30008 30 s, pp+0xade8 60 s, pp+0x2af50 180 s.
- Parsers: props `0x56b118`; status `0x56c204`; storage `0x56bb1c`; dirs `0x83913c`; info `0x838300`; transfers `0x83ac74`; firmware result `0x85528c`/`0x854ea8`; logs `0x90d178`; image control `0xd8e104`.
- Flows: listing `0xdbb298`; auto-transfer `0xdbdd14`; manual import `0xe3a278`; download `0xdbe510`/`0xdc2064`/`0xdc2d88`; connect `0xd1d508`; WS `0xd22098`/`0xd27770`/`0x569938`/`0xd28f24`; firmware `0xdd3c14`/`0xdd418c`/`0xdd48ac`; power `0xe4b958`/`0xe4bfa4`.
- Scratch notes: `research/notes/http/notes.md`.

## Open questions (confirm with an HTTP proxy / Wi-Fi capture against a real camera)
1. Exact response bodies (field types and example values) for `/v1/props`, `/v1/status/device`, `/v1/photos`, `/info`, `/v1/transfers`. In particular, is `transfers[].size` `"xs"`/`"full"`, and does `filepath` really carry `?xs`?
2. The page size of `/v1/photos` (the app assumes 3000) and the semantics of `after=` (exclusive?).
3. Which condition the "storage count == 2" check reads (`0xdbb41c`), and whether single-storage cameras accept or reject `storage=`.
4. Whether a camera answers a `Range` request with anything but the whole file. The GR IV 1.20 firmware does not read the header (§2.7), and neither app sends it. Also Content-Type and Content-Length for `size=xs`/`thumb`/`view`, and the actual pixel sizes of xs/view/thumb.
5. Whether the camera really returns HTTP 200 with a JSON `{errCode≠200}` body on download failure.
6. The `/imgctrl` BLOB: the meaning of byte[1], how versions 1/2/4 differ, and the value ranges per parameter (the `(id, int8)` pair layout is decoded in `ble.md`).
7. The end-screen PUT without a body (variant B): is it delete/reset? The valid `index` range? Is `sha256` mandatory on newer firmware?
8. `/v1/params/device` on GR II: are the body (`channel=0&ssid=&key=` with JSON content-type) and the escaping of special characters accepted as is? Also what pp+0x1c38 (the regex fix-up for the props `key` field) is.
9. WebSocket: does the camera send other `changed` values, does it send pings or require them, what are the idle timeout and close codes, and is it the camera that drops the socket during Wi-Fi power saving (relevant to the disconnects)?
10. Firmware: maximum upload and update time and whether `storage=sd1` is accepted; see [firmware update §6](firmware-update.md#6-open-questions).
11. The origin of the URL used by `0xd8eb6c` (30 s Image Control GET) and of the end-screen image URL (`0x952890`).
12. Deleting photos on the camera body while connected (see §5 "GR IV firmware: `storage` changes"): is the camera's playback usable while its Wi-Fi is on, does a single delete, a multi-delete or delete-all send `storage` `delete` changes and how soon, does a card swap keep the link and send any change, and which `errCode` do `/info`, a preview and a full download of a deleted file answer? (Deleting from the phone is not possible, §2.6.)
13. Where a GR movie file keeps its `moov` box, before or after the media data (§2.7): it decides whether a movie can start playing while it is copied.
14. A movie's actual bit rate in each frame rate, and the download rate of a large file on each Wi-Fi band (§2.7): together they decide whether a movie played as it arrives would stall.
