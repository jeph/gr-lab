# Firmware update over Wi-Fi and BLE (GR WORLD 2.0.0, GR IV firmware 1.20)

How GR WORLD updates a camera's firmware from the phone, and what the camera does with each request. Researched on 2026-11-09 by static analysis only: GR WORLD 2.0.0 for Android (Dart AOT disassembly, `work/dis/dis.txt`, object pool `work/cs/blutter_out/pp.txt`) and, with REA (Ghidra 12.1.4), the GR IV 1.20 `webapid`, `bled` and `libcamera-controller.so` plus a string scan of the GR IV `rtos.bin`. **Nothing here has been run against a camera or Ricoh's cloud.**

Tags: **[app 0x…]** address in GR WORLD's `dis.txt`; **[pp+0x…]** object-pool entry; **[webapid 0x…]**, **[bled 0x…]**, **[camctl 0x…]** Ghidra addresses in the GR IV 1.20 binaries (Ghidra loads them at image base `0x10000`, so `objdump` file addresses are `0x10000` lower); **[rtos "…"]** a string in GR IV `rtos.bin`, used only as a hint because the RTOS code was not decompiled. Statements are observed in code unless tagged **[inferred]** or **[unknown]**. Decompiled output is kept in the research workspace under `work/fwupdate/` (`gr4-webapid-fw.c`, `gr4-webapid-convert.c`, `gr4-camctl-fw.c`, `gr4-bled-fw.c`, `gr4-bled-camservice-init.c`, `gr4-bled-generic-char.c`).

## 1. Summary

- **Only the GR IV family can be updated from the phone.** The GR IV 1.20 `webapid` registers the firmware routes and its `bled` has the three firmware characteristics. The GR III 2.20 and GR IIIx 1.70 `webapid` and `bled` have neither (only the firmware-revision read). GR WORLD maps only GR IV models to a cloud model code (§2.1).
- The sequence: the app downloads `update.zip` from Ricoh's cloud, turns the camera's Wi-Fi on over BLE, `POST /v1/configs/firmware/prepare` with the file size, `PUT /v1/configs/firmware?storage=in&reboot=true` with the whole file, waits for the camera to restart, reconnects over BLE, writes `01` to FirmwareUpdateStart, waits for FirmwareUpdateResult, and on success powers the camera off over BLE.
- The camera streams the PUT body straight into a memory buffer that the camera core (RTOS) allocates for the declared size. The size must match exactly. The RTOS then checks and stores the file; `detail.reason` reports `battery_too_low`, `err_fw_same`, `err_fw_old` or `err_fw_broken`.
- **Opening or closing any `/v1/changes` WebSocket while an upload is in progress cancels the update on the camera** (§3.4).
- The camera does not authenticate the phone over HTTP; anyone on the camera's Wi-Fi network can start these requests. The camera's own checks (model, version, battery, data integrity) are the only gate **[inferred from the absence of any auth check in the handlers]**.

## 2. App side (GR WORLD 2.0.0, Android)

### 2.1 Finding an update (Ricoh's cloud)

- One cloud endpoint, `fwDownload`, serves both the version check and the download link: `POST https://<id>.execute-api.ap-northeast-1.amazonaws.com/v1/fwDownload` [pp+0x2a080], or `https://grworld.ricoh-imaging.com.cn/api/fwDownload` [pp+0x2a078] when a build/region flag is set (that the flag means China is **[inferred]**). Request helper [app 0xd38a24], header builder [app 0xd3b5a4].
- Body: JSON `{"model": <code>}` and nothing else (no serial, current version, region or language). Codes from the stored model name [app 0x587180]: `GR IV` → `gr4`, `GR IV HDF` → `gr4_hdf`, `GR IV Monochrome` → `gr4_mono`, `GR IVx` → `gr4_x`, `GR IVx Monochrome` → `gr4_x_mono`, anything else → `unknown`.
- Headers: `accept`, `content-type: application/json`, an API key and a secret key (two pairs in the app, one per host; not reproduced here), `Authorization: Bearer <token>` from secure-storage key `gr_world_cn.auth.token` (presumably empty outside the China login **[inferred]**), and `phone_model`, `phone_os` (`Android`), `phone_os_version`, `phone_language`, `phone_app_ver`.
- Response: `{version, expirationDate, presignedUrl}` [app 0x587480]. The app reuses the URL until `expirationDate` [app 0xddc9c4]. A non-200 body is `{errorCode, errorMessage}`.
- The camera's current version comes from the BLE Camera Information firmware-revision read at connect, stored in the app's database; not from `/v1/props`.
- Version comparison converts both strings with `double.parse`, so `1.10` sorts below `1.9` [app 0x9bdbb0, 0x855850, 0xda8824]. The check screen disables the button when the cloud version is not higher. The pairing flow checks the cloud only when the model string is exactly `GR IV` [app 0xda86d4].

### 2.2 The package

- `GET <presignedUrl>` with a 120 s timeout, saved as `<temp>/firmwareUpdate/update.zip` [app 0xddc594, 0xddc2e4]. No size, hash or signature check in the app.
- Unzip [app 0xddb578]: any `*.json` entry is written as `updateInfo.json`, any `*.bin` entry as `fwdc248b.bin`, whatever their names in the zip.
- `updateInfo.json` [app 0x855920]: `{"version": "<string>", "releaseNote": {"ja", "en", "fr", "de", "ko", "zh_CN", "zh_TW"}}`. No file name, size, checksum or model field. A missing file fails the flow ("Firmwareupdate version info jsonFile is null").
- Ricoh's public download page ships the same file name: the GR IV 1.20 and GR IV Monochrome 1.10 ZIPs both contain only `fwdc248b.bin` (38,919,904 bytes, SHA-256 `7563d7e4…77650d`; header in [camera models](../camera-models.md)). Whether the cloud's `fwdc248b.bin` is byte-identical to the public file is **[unknown]**: fetching it needs the app's API keys, which we do not use.
- There is no other way to load firmware into the app: no file picker, no document intent, and the unzip always starts from the downloaded `update.zip`.

### 2.3 Preconditions (check screen)

Built by [app 0x9bc840] from [app 0xe55b00]. Each failure has an analytics code (`step0_*`), not a wire value.

| Check | Fails when |
|---|---|
| Phone battery | ≤ 20 % |
| Camera battery (BLE battery level) | ≤ 33 % |
| Phone free space | ≤ 50 MB |
| VPN | a VPN is active |
| Cloud reachable | no network, HTTP 429/500/503, 5 s timeout |
| Version | cloud version not higher than the camera's |

The app does not check the camera's card, capture mode or anything else; movie mode only shows up later as a WLAN-on failure.

### 2.4 Steps

| Step (UI text) | What the app does | Timeout |
|---|---|---|
| 1 "Get Firmware" | wait 1 s, get the presigned URL, download, unzip [app 0xdd2fbc] | cloud 60 s, download 120 s |
| 2 "Send Firmware to Camera" | wait 1 s; BLE WLAN Control `9111CDD0` = `01` and join the camera AP [app 0xdd809c]; `POST …/prepare`; `PUT /v1/configs/firmware…` [app 0xdd3c14, 0xdd418c, 0xdd48ac] | prepare 60 s, PUT 180 s |
| 3 "Restart Camera" | check Bluetooth permissions and adapter, wait 5 s, scan and reconnect; this connection also subscribes to FirmwareUpdateResult [app 0xdd4f54, 0xd2fb04] | 60 s for the reconnect |
| 4 "Update" | wait 200 ms, write `01` to FirmwareUpdateStart, wait for the FirmwareUpdateResult notification [app 0xdd5398, 0xdd5a44] | none found |
| done | result `01`: write Camera Power `B58CE84C` = `00` (camera off) [app 0xe86104]; result `02`: "Camera update failed." [app 0xe85c70] | — |

- The `step2_…`/`step3_…`/`step4_…` strings are only analytics results (event `firmware_update`, [app 0xd2e194]), never sent to the camera.
- No automatic retries. The process screen can restart from step 1 or jump straight to step 2 with the files already unzipped [app 0xe57ed8].
- After the power-off write there is no reconnect and no version re-read.
- No timeout on the step-4 notification was found, so a camera that never notifies may leave the screen waiting **[inferred]**.
- Cancel [app 0x85c558 → 0xddcb14]: only while the upload state is active does the app send `POST /v1/configs/firmware/cancel` [app 0xddcca4]. In every step it then drops the phone's Wi-Fi, writes WLAN Control `00` and disconnects BLE [app 0xd43cd4, 0xd431f0]. Which UI actions call cancel is **[unknown]**.
- The firmware flow neither opens nor closes the `/v1/changes` WebSocket itself. Whether one opened by the normal connect flow is still open during the PUT is **[unknown]**; the cancel path closes it (§3.4).

### 2.5 HTTP requests the app sends

| Request | Headers and body | App timeout |
|---|---|---|
| `POST /v1/configs/firmware/prepare` | `Content-Type: application/x-www-form-urlencoded`, body `filesize=<length of fwdc248b.bin>` [app 0xdd7268] | 60 s |
| `PUT /v1/configs/firmware?storage=in&reboot=true` | `Content-Type: application/octet-stream`, body the whole `fwdc248b.bin` in one buffer [app 0xdd698c] | 180 s |
| `POST /v1/configs/firmware/cancel` | no body [app 0xddcca4] | none |

Responses are parsed as `{errCode, errMsg, detail: {reason}}` [app 0x855200]; success is `errCode == 200`. The app checks `detail.reason` first, then `errCode` [app 0x854ea8, 0x854bc4]:

| Camera answer | App's error |
|---|---|
| `reason: battery_too_low` | camera battery low |
| `reason: err_fw_same` | same version |
| `reason: err_fw_old` | older version |
| no reason | other camera failure |
| `errCode` 412, other reason | "NG condition" |
| `errCode` 400, other reason (`err_fw_broken` lands here) | illegal firmware |
| other `errCode` | other camera failure |
| exception containing "Timeout" | app timeout |

## 3. Camera side (GR IV 1.20)

### 3.1 Routes in `webapid`

Registered in `WebapiServer::Run` (`firmware/evidence/gr4-webapid-run.json`); crow method masks: `/v1/configs/firmware` = `0x11` (DELETE and PUT), `/prepare` and `/cancel` = `0x08` (POST).

- The `/v1/configs/firmware` route installs a body handler, `Firmware::ReceiveFirmwareHandler` [webapid 0x7d540], so the request body is passed to the handler in chunks as it arrives instead of being buffered. The request handler then always calls `Firmware::SaveFirmware` [webapid 0x7d688] and answers with HTTP 200 and a JSON body. `Firmware::DeleteFirmware` [webapid 0x7c3c4] has no caller, so `DELETE` behaves like `PUT` **[inferred from the handler; not tried]**.
- As on other routes, failures are carried in the JSON `errCode` with HTTP status 200 (GR IV HDF 1.20 does this for unknown routes, see [remote shooting](remote-shooting.md)).

### 3.2 Prepare: `POST /v1/configs/firmware/prepare`

`Firmware::PreSendFirmware` [webapid 0x7cbf4]:

1. Parse the body as `key=value` pairs. Unparsable body → 400.
2. Read `filesize` as a decimal integer (`stoull`) [webapid 0x7c1f0]. Missing, non-numeric or `0` → 400.
3. If a transfer is already in progress → 400 (log "Firmware update is already in progress"). The flag is cleared by a PUT that passes the `storage` check (complete or not), a cancel, or a WebSocket open or close (§3.4), so a client that lost an earlier upload should send cancel first **[inferred]**.
4. RTOS command `PreSendFirmware` [camctl 0x8d068]. A failure is answered through the result mapping in §3.5, so `battery_too_low` can already appear here.
5. RTOS command `CreateFirmware(filesize)` [camctl 0x8c6f0] returns the physical address of a buffer in RTOS memory ("rtosMemAddr"). Address 0 → 500.
6. `FirmwareTransferManager::Start` [webapid 0x7c9ec] maps that buffer through `/dev/mem` with a page-aligned `mmap` [webapid 0x7c73c] and zeroes the byte count. Failure → 500.
7. Answer 200.

### 3.3 Upload: `PUT /v1/configs/firmware`

While the body arrives, `FirmwareTransferManager::PutData` [webapid 0x7d310] copies each chunk into the mapped RTOS buffer. Chunks arriving when no transfer was prepared are dropped; bytes beyond the declared size are refused and logged ("Transfer data size exceeds memory area").

Then `Firmware::SaveFirmware` [webapid 0x7d688]:

1. `storage` query parameter, mapped like the other routes (`in`, `sd1`). An unknown name → 400. If it is absent the storage id is `0` (meaning **[unknown]**). The storage must be available (`StorageManager::CheckAvailableStorageId`), else its error.
2. `reboot` query parameter: exactly `true` → `2000`, anything else or absent → `0`. The number is passed to the RTOS in step 5; that it is a restart delay in milliseconds is **[inferred]**.
3. If the received byte count is not exactly `filesize` → unmap, 500 [webapid 0x7d562].
4. Unmap, then RTOS command `SaveFirmware(storageId)` [camctl 0x8c928]. Failure → answer with `errCode` and `detail.reason` from §3.5. This is where the camera rejects a wrong, older, identical or damaged file, or a low battery.
5. RTOS command `PostSendFirmware(0 or 2000)` [camctl 0x8d264]. Failure → `errCode` only.
6. Answer 200.

**[inferred from rtos strings]** `SaveFirmware` writes the file to the selected storage under the name the camera's own card update uses (`C:\FWDC%ldB.BIN` for internal memory, `H:\FWDC%ldB.BIN`; "Save Update File = %s", "found User Update FW in Internal"), and the restart sets a "forced boot factor" of 8, "remote update" (`<forced boot factor(3:acc, 5:ble, 8:remote update, 0xFF:off)>`). The RTOS checks behind the error reasons include "project number is different!", "chek data error!", "Update Version is older than Current Version!!" and "update battery NG!". This matches the app's step 3 "Restart Camera" coming right after the PUT.

### 3.4 Cancel and WebSocket open or close

- `POST /v1/configs/firmware/cancel` → `Firmware::CancelFirmware` [webapid 0x7c4e4]: unmap the buffer and clear the transfer flag, then RTOS command `CancelFirmware` [camctl 0x8d424]. The body is ignored.
- `FirmwareTransferManager` registers a WebSocket connection-status callback at start-up [webapid 0x7bf98]. `WebsocketAdapter::OnOpen` and `OnClose` both run the registered callbacks (`firmware/evidence/gr4-webapid-open.json`, `gr4-webapid-close.json`). `Firmware::WebsocketConnectStatusCallback` [webapid 0x7c630] ignores its arguments and calls `CancelFirmware` whenever a transfer is in progress (log "websocket has been disconnected. Firmware update will be canceled."). So opening or closing **any** `/v1/changes` connection during an upload cancels it. A client must not open, reopen or close the WebSocket between prepare and the PUT's answer.

### 3.5 Result mapping

`ConvertResponseToErr` [webapid 0x8e458] and `ConvertResponseToDetail` [webapid 0x8e3a4] turn the RTOS result code into the answer:

| RTOS result | `errCode` | `detail.reason` |
|---|---|---|
| 0 | 200 | — |
| 1 | 400 | — |
| 2 | 412 | — |
| 10 | 412 | `battery_too_low` |
| 11 | 400 | `err_fw_same` |
| 12 | 400 | `err_fw_old` |
| 13 | 400 | `err_fw_broken` |
| other | 500 | — |

`errMsg` is the standard text for the code ("Bad Request" for 400, as seen on hardware for other routes). Which RTOS conditions produce codes 1 and 2 is **[unknown]**.

### 3.6 BLE characteristics in `bled`

Registered in `CameraService::InitService` [bled 0x5ce20] with their names. Ricoh's names replace the inferred ones in [BLE](ble.md).

| UUID | `bled` name | GATT properties | Behaviour |
|---|---|---|---|
| `e450ed9b-dd61-43f2-bdfb-6af500c910c3` | FirmwareUpdateAvailable | Write | Generic 1-byte property characteristic: the written byte is stored in camera property `0xC2`. GR WORLD never writes it; that it tells the camera an update exists is **[inferred]** from the name |
| `5f0a7ba9-ae46-4645-abac-58ab2a1f4fe4` | FirmwareUpdateStart | Write | Exactly 1 byte [bled 0x5bfb8]: `00` does nothing, `01` sends the RTOS command `StartFirmwareUpdate` [bled 0x5cbe8, camctl 0x8d620], `02`–`FF` or any other length is rejected |
| `39879aac-0af6-44b5-afbb-ca50053fa575` | FirmwareUpdateResult | Read, Notify | Generic 1-byte property characteristic reading camera property `0xC3`. GR WORLD reads `01` success, `02` failure |

The `libcamera-controller` DeviceCommand interface has eight firmware commands, all thin IPC wrappers to the RTOS: CreateFirmware, SaveFirmware, GetFirmwareInfo, DeleteFirmware, PreSendFirmware, PostSendFirmware, CancelFirmware, StartFirmwareUpdate (vtable offsets `0x34`–`0x54`). `webapid` uses six, `bled` uses StartFirmwareUpdate; GetFirmwareInfo has no caller in either.

## 4. End-to-end sequence

```
Phone                                         Camera (GR IV)
  BLE  W 9111CDD0 = 01 (WLAN on), join AP
  HTTP POST /v1/configs/firmware/prepare  ──▶ PreSendFirmware; CreateFirmware(N) → RTOS buffer
       filesize=N                         ◀── {"errCode":200}
  HTTP PUT /v1/configs/firmware           ──▶ body copied into the buffer; size must equal N
       ?storage=in&reboot=true <N bytes>      SaveFirmware(storage): model/version/battery/data checks
                                              PostSendFirmware(2000)
                                          ◀── {"errCode":200} | {"errCode":400|412,"detail":{"reason":…}}
  (camera restarts; Wi-Fi gone)
  BLE  reconnect, subscribe 39879aac
  BLE  W 5f0a7ba9 = 01                    ──▶ StartFirmwareUpdate
                                          ◀── N 39879aac = 01 (success) | 02 (failure)
  BLE  W B58CE84C = 00 (power off, GR WORLD on success)
```

## 5. GR Lab

GR Lab does not implement firmware updates. To build it without Ricoh's cloud, the app would have to take the `fwdc248b.bin` from Ricoh's public download page, which is the same file name and format but not proven to be the same bytes the cloud serves (§2.2). The checks the camera runs before accepting a file (§3.3) make a wrong file fail with 400 rather than be flashed **[inferred]**.

## 6. Open questions

1. Hardware confirmation of the whole sequence on a GR IV, with an HTTP proxy or the camera log: answer bodies, the restart after the PUT, how long the update takes after FirmwareUpdateStart and whether the result notification arrives on the reconnected link.
2. Whether the cloud's `fwdc248b.bin` is byte-identical to Ricoh's public download for the same version, and whether GR IV, HDF and Monochrome get the same file from the cloud as they do from the download page.
3. What `reboot=false` does (the camera stores the file but does not restart **[inferred]**), and whether a camera that is restarted by hand still accepts FirmwareUpdateStart.
4. Whether `storage=sd1` works, and what storage id `0` (no `storage` parameter) selects.
5. What FirmwareUpdateAvailable (`0xC2`) changes on the camera.
6. The RTOS conditions behind result codes 1 and 2, and whether PreSendFirmware itself checks the battery.
7. Whether the camera's WLAN-check option for remote updates ("remote update fw option : wlan check") affects the upload.
8. The iOS GR WORLD flow (not analysed; the Android AOT snapshot only contains Android branches).
