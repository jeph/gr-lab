# GR camera BLE protocol (from GR WORLD 2.0.0, static analysis)

Source: RICOH GR WORLD for Android, `com.ricohimaging.grworld` 2.0.0 (versionCode 26101500), Flutter with an obfuscated Dart AOT snapshot (`libapp.so`, Dart 3.11.1) using `flutter_blue_plus` (FBP). Everything here comes from reading the disassembly and the object pool. Nothing was checked against a real camera; items marked **[inferred]** follow from code structure, and **[unknown]** items were not recoverable statically. Addresses are code addresses in `work/dis/dis.txt`; `[pp+0x…]` are object-pool entries in `work/cs/blutter_out/pp.txt`.

## Quick reference

- The camera exposes six custom services plus the standard Device Information service (`180A`). Every characteristic the app uses is listed in [Service and characteristic map](#service-and-characteristic-map).
- All writes use **ATT Write Request (with response)**: FBP write 0xe5c094 hard-codes `withResponse` ([pp+0x40f58] loaded at 0xe5c17c).
- Encodings: booleans are 1 byte (`0x01`/`0x00`; decoded as `byte0 == 1`), small enums are 1 signed byte, multi-byte integers are **little-endian**, the GPS float64 fields are **big-endian**, strings are raw UTF-8 with no length prefix or terminator (NUL padding is stripped on read **[inferred]**).
- Turn the camera's Wi-Fi AP on: write `01` to `9111CDD0-9F01-45C4-A2D4-E09E8FB0424D`; read SSID `90638E5A-…` and passphrase `0F38279C-…`; join the AP. Off: write `00`.
- Remote shutter: write `01 01` to `559644B8-E0BC-4011-929B-5CF9199851E7`. To cancel a running 10 s self-timer countdown, write `01` to `009A8E70-B306-4451-B943-7F54392EB971`.
- Clock sync: write 7 bytes `yearLE16, month, day, hour, minute, second` (phone local time) to `FA46BBDD-8A8F-4796-8CF3-AA58949B130A`.
- GPS: write a 32-byte record to `28F59D60-8B8E-4FCD-A81F-61BDB46595A9` every 5, 30 or 180 s. The camera takes it only while GEO Tag `A36AFDCF` is on and keeps it for 600 s ([geotagging.md](geotagging.md)).
- Camera power off: write `00` to `B58CE84C-0666-4DE9-BEC8-2D27B27B3211`. The app never writes `01` there. **Power on (GR WORLD):** connect directly to the bonded camera while it is off, read Operation Mode `1452335A-EC7F-4877-B8AB-0F72E18BB295`, and if it reads `02` (bleStartup) write `01` (playback) or `00` (capture), then continue on the same link. On hardware the **first** link drops about 5.5 s after opening while the camera wakes; reconnect at once (GR WORLD's connect retry) and do the mode check on the second link. See [GR WORLD power-on](power-on-grworld.md). Image Sync (GR III/IIIx) uses a bare connection instead: [Image Sync BLE §2](ble-imagesync.md#2-camera-power-on--wake-from-off--definitive-answer).
- **Exposure, focus status and more:** Image Sync documents 27 further characteristics (shutter, aperture, ISO, EV, WB, metering, file type, focus mode/AF status, shot count, setting lists, three aggregate-notification characteristics, BLE Enable Condition, WLAN channel). See [ble-imagesync.md](ble-imagesync.md).
- **Firmware comparison:** all 46 app-known custom UUID constants occur in the analyzed GR IV `bled`; 32 occur in GR III's, with 25 additional shared UUID-shaped candidates not used by this app. These byte matches do not establish active GATT registration or permissions. The GR IV WLAN-write handler separately corroborates `byte0 == 1` versus other values for the on/off request. See [firmware inventory](../firmware-protocol-inventory.md#gatt-uuid-inventory-versus-the-app) for model hashes, exact matches and native evidence.

## Camera models

- **BLE models: GR III, GR IIIx, GR IV and their variants.** Discovery decodes a model code from the manufacturer-specific advertising data (0xda542c). GR WORLD accepts:

  | Code | Model (firmware string) | Accepted by GR WORLD 2.0.0 |
  |---|---|---|
  | 1, 5 | `RICOH GR III`, `RICOH GR III HDF` | yes (GR III family) |
  | 3, 6 | `RICOH GR IIIx`, `RICOH GR IIIx HDF` | yes (GR III family) |
  | 7, 8 | `RICOH GR IV`, `RICOH GR IV HDF` | yes (GR IV family) |
  | 9 | `RICOH GR IV Monochrome` | yes (GR IV family). The app's log label "RICOH GR IV Monochrome / RICOH GR IVx" [pp+0x36038] is the app's; firmware gives GR IVx code 10 |
  | 10 | `RICOH GR IVx` (unannounced) | no |
  | 2, 4 | `PENTAX K-3 Mark III`, `… Monochrome` (same `bled` table) | no |

  Which codes are accepted depends on the camera family chosen in the UI (bool provider `SCf` [pp+0x20018]): IV family accepts 7, 8, 9 (0xda560c..0xda5674); III family accepts 1, 5, 3, 6 (0xda56d0..0xda5740). Firmware source of the codes, the full scan-response layout and model-identification guidance: [camera models](../camera-models.md#41-before-connecting-ble-advertising-recommended).
- **GR II has no BLE path.** It appears only in the minimum-firmware table (0x54b6c0: GR IV ≥ 0.00, GR IIIx ≥ 1.50, GR III ≥ 2.00, GR II ≥ 3.00) and in the Wi-Fi verification code. There is no BLE model code for it. **[inferred]** GR II is Wi-Fi-only; this matches the Wi-Fi-only registration flow (connection type 0, `WifiDeviceRegister*`).
- No GATT encoder or decoder branches on model. Differences between models show up in two ways:
  - **Optional characteristics.** WLAN read-all substitutes defaults for missing characteristics, and the settings writer checks that wlanFreq exists. **[inferred]** wlanFreq, security and available5GHz may be absent on GR III/IIIx.
  - **GR IV-only steps in registration:** pending camera-name restore 0xd3fdf8 and a cloud firmware check 0xda8ec4. The default name "MY GR IV" also points to GR IV.
- Exact model match: the firmware check compares the Camera Information / DIS model string with `==` against "GR IV", "GR IIIx", "GR III" and "GR II"; any other string fails (0x54b7d4). A model string such as "GR IV Monochrome" would therefore be rejected unless the camera reports one of those four **[inferred]**. Firmware strings must be exactly `major.minor`. The minor part is compared as an integer, so "1.6" < "1.50".

## How the app models GATT (for reading the evidence)

Each service has a Dart "family" of classes, one class per characteristic. A builder function allocates one instance of each class into a list. A finder pairs each instance with the FBP `BluetoothCharacteristic` by calling the class's virtual `uuid` getter. Code that needs one characteristic filters the pairs with a closure comparing the class id (for example closure 0x579158 does `cmp x1, #0x649`).

The `uuid` getters are three-instruction functions (`add x0, x27, …; ldr x0, [x0, #off]; ret`) laid out in blocks, one block per family. Within a block they appear in **descending class-id order**. This was validated three ways:
1. The six custom-service getters (0xb1c1ac..0xb1c1f4) match the literal UUIDs used by the service finders (five finders load a literal; the WLAN finder calls the getter).
2. In the DIS getter block (0xcb2b54..0xcb2b84), the classes the connect path reads for model (cid 0x659) and firmware (cid 0x657) map to `2A24` and `2A26`, and they feed the model→minimum-firmware check 0x54b6c0.
3. The l10n getter block at 0xcb2b90 lines up with the locale classes from the l10n lookup at 0xb15968.

The WLAN family's mapping was also confirmed by per-class type checks in its read-all function 0xd3eff0.

Each characteristic class also has two virtual factories: a read factory and a write factory. Each returns a command object `{characteristic, op (yFb read=0 / write=1), parameter}`. The generic executor 0xd30588 takes a per-service mutex (0x56ac88), runs `command.execute()` (dispatch selector +0xd6a7) and unlocks (0x569ae8). So **the app never has two GATT operations in flight on one service**. Most call sites wrap this in retry helper 0x5479e4: 3 attempts with a 50 ms delay (`mov x5,#3` at 0x547aac; delay `Obj!la@8704a1` = 50 000 µs). When retries run out, the app throws ER_BL_005 "WriteError" (writes) or ER_BL_004 "ReadError" (reads).

## Service and characteristic map

"Ops" lists only what GR WORLD does. N = notify (CCCD enabled, followed by one priming read).

### Services

| Service UUID | Name (this doc) | Service class | Evidence |
|---|---|---|---|
| `9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1` | Camera Information | RHb 0x652 | finder 0x58cd4c literal [pp+0x2a178]; lower-case copy [pp+0x270e8] used for the scan filter (0x590f10, 0x59151c) |
| `9F00F387-8345-4BBC-8B92-B87B52E3091A` | Camera Control (shooting) | WHb 0x64d | finder 0x578a18 literal [pp+0x29ad8] |
| `4B445988-CAA0-4DD3-941D-37B4F52ACA86` | Camera State | SHb 0x651 | finder 0x56fed0 literal [pp+0x29878] |
| `F37F568F-9071-445D-A938-5441F2E82399` | WLAN Control | THb 0x650 | service getter 0xb1c1c4 [pp+0x411f8]; finder 0x58d120 uses the getter (selector 0x3fa4) |
| `84A0DD62-E8AA-4D0F-91DB-819B6724C69E` | GPS | UHb 0x64f | finder 0x591998 literal [pp+0x2a7a8] |
| `0F291746-0C80-4726-87A7-3C501FD3B4B6` | Client Registration | VHb 0x64e | finder 0x82e874 literal [pp+0x2a760]; also a scan-filter Guid (0x59151c) |
| `180A` (Device Information) | DIS | XHb 0x64c | finder 0x58dd4c literal [pp+0x2a410] |

The service names are this document's labels. The app has no service names, only the model classes (`CameraInformationServiceModel`, `CameraServiceModel`, `WLANControlCommandModel`).

### Camera Information `9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1`

All six are **read-only** UTF-8 strings: read executors 0xe5c544..0xe5cd0c have no write branch; decoding is `utf8.decode` then the padding strip. Read-all 0xd3e3ac assigns each by class id into `CameraInformationServiceModel` (`_DFb`, field order from toString 0xad5b08). The app reads them on every connect (main connect flow 0xd2e93c → 0xd3e248 → 0xd3e3ac).

| Characteristic UUID | Field | Class (cid) | Evidence |
|---|---|---|---|
| `F5666A48-6A74-40AE-A817-3C9B3EFB59A6` | manufacturerNameString | 0x694 | getter 0xb1b1fc |
| `35FE6272-6AA5-44D9-88E1-F09427F51A71` | modelNumberString (e.g. "GR IV"; gates firmware check 0x54b6c0, compared to "GR IV" at 0xda754c) | 0x693 | getter 0xb1b208 |
| `0D2FC4D5-5CB3-4CDE-B519-445E599957D8` | serialNumberString | 0x692 | getter 0xb1b214 |
| `B4EB8905-7411-40A6-A367-2834C2157EA7` | firmwareRevisionString ("major.minor") | 0x691 | getter 0xb1b220 |
| `6FE9D605-3122-4FCE-A0AE-FD9BC08FF879` | bluetoothDeviceName | KFb 0x690 (cmp at 0xd3e628) | getter 0xb1b22c |
| `97E34DA2-2E1A-405B-B80D-F8F0AA9CC51C` | bluetoothMacAddressString | LFb 0x68f (cmp at 0xd3e64c) | getter 0xb1b238 |

### Camera Control `9F00F387-8345-4BBC-8B92-B87B52E3091A`

Getter block 0xa1f670..0xa1f6f4; builder 0x578cfc; finder 0x578a18.

| Characteristic UUID | Meaning | Ops | Payload |
|---|---|---|---|
| `559644B8-E0BC-4011-929B-5CF9199851E7` | Shutter release (enum member `startOrStopRecording`, so it presumably also starts/stops movie recording **[inferred]**) | W | 2 bytes `01 01` = [startOrStopRecording=1, enableAF=1] (built at 0xe61b40..0xe61b84; enums UIb/VIb each have one member with wire value 1). AF is only requested through byte 1; there is no separate half-press |
| `B29E6DE3-1AEC-48C1-9D05-02CEA57CE664` | Drive mode (includes self-timer) | N, R, W | 1 byte: 0 single, 1 10 s self-timer, 2 2 s self-timer, 3 continuous, 4 bracket, 5 bracket+10 s, 6 bracket+2 s, 7 multi-exposure, 8 multi-exp+10 s, 9 multi-exp+2 s, 10 interval, 11 interval+10 s, 12 interval+2 s, 13 interval composite, 14 interval composite+10 s, 15 interval composite+2 s (decoder 0x579368; other values throw) |
| `A3C51525-DE3E-4777-A1C2-699E28736FCF` | Shooting (exposure) mode + user mode | N, R | byte0: 0 P, 1 Av, 2 Tv, 3 M, 4 B, 5 BT, 6 T, 0x13 SFP; byte1: 0 none, 1 U1, 2 U2, 3 U3 (parser TIb 0xd34e50; other values throw) |
| `78009238-AC3D-4370-9B6F-C9CE2F4E3CA8` | Capture mode | N, R | 1 byte: 0 still, 2 movie (parser RIb 0x579918) |
| `B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA` | Capture status | N, R | byte0: 0 idle, 1 shooting in progress; byte1: 0 no countdown, 1 self-timer counting down, 2 waiting for scheduled time (parser SIb 0x579668) |
| `009A8E70-B306-4451-B943-7F54392EB971` | Cancel. The app uses it only to cancel a running 10 s self-timer countdown | W | 1 byte `01` (WIb.cancel; write 0xe61dd8, caller 0xe53300) |
| `30adb439-1bc0-4b8e-9c8b-2bd1892ad6b0` | Image Control Custom 1 name | R, W | UTF-8 string |
| `e799198f-cf3f-4650-9373-b15dda1b618c` | Image Control Custom 2 name | R, W | UTF-8 string |
| `df77dd09-0a48-44aa-9664-2116d03b6fd7` | Image Control Custom 3 name | R, W | UTF-8 string |
| `3e0673e0-1c7b-4f97-8ca6-5c2c8bc56680` | Image Control Custom 1 data | R, W | blob, see [Image Control blob](#image-control-blob) |
| `0936b04c-7269-4cef-9f34-07217d40cc55` | Image Control Custom 2 data | R, W | blob |
| `cd879e7a-ab9f-4c58-90ed-689bae67ef8e` | Image Control Custom 3 data | R, W | blob |

The "name" reading of the three string characteristics is **[inferred]**: the app looks the slot up in its DB with `"name = ? AND raw = ?"` [pp+0x2bc78] (0xd8db1c). Several notify set-up functions reuse misleading error strings: drive mode logs "BatteryNotify error: " (0xd35014), and capture mode/status log "CaptureModeNotify error: " (0xd35944, 0xd354ac). The meanings above come from the parsers ("driveMode update: " [pp+0x29b38]; toStrings "ShootingModeModel(mode: " [pp+0x46ca8], "CaptureStatusModel(countdown: …, capturing: …)" [pp+0x46cc8]).

### Camera State `4B445988-CAA0-4DD3-941D-37B4F52ACA86`

Getter block 0xb1c200..0xb1c2a0; builder 0x570654; finder 0x56fed0. Read-all 0xd40f68 fills `CameraServiceModel` (`_UFb`; toString 0xad5bbc). The default camera name "MY GR IV" [pp+0x2a358] suggests this service belongs to the GR IV generation **[inferred]**, but no codec branches on model.

| Characteristic UUID | Meaning (model field) | Ops | Payload |
|---|---|---|---|
| `FA46BBDD-8A8F-4796-8CF3-AA58949B130A` | dateTime | R, W | 7 bytes: year uint16 LE, month, day, hour, minute, second (local time; write 0xe5d8cc uses DateTime parts 8,7,5,4,3,2) |
| `B58CE84C-0666-4DE9-BEC8-2D27B27B3211` | cameraPower | N, R, W | 1 byte bool (1 on / 0 off). The app only writes `00` (0xe4b304) |
| `875FC41D-4980-434C-A653-FD4A4D4410C4` | batteryLevel | N, R | byte0 = level (int8). Long form: if len ≥ 130 and byte1 == 1, bytes [2..130) are 128 bytes of end-screen data (0xdb0d10..0xdb0e40) |
| `430B80A3-CC2E-4EC2-AACD-08610281FF38` | operationModeList | R | byte0 int8; meaning **[unknown]** (possibly a mask of allowed operation modes) |
| `1452335A-EC7F-4877-B8AB-0F72E18BB295` | operationMode | R, W | 1 byte: 0 capture, 1 playback, 2 bleStartup, 3 other, 4 powerOffTransfer (enum SFb wire values, `work/cs/blutter_out/objs.txt` 56083..56121) |
| `A36AFDCF-6B67-4046-9BE7-28FB67DBC071` | geoTag enabled | N, R, W | 1 byte bool |
| `A0C10148-8865-4470-9631-8F36D79A41A5` | storageInformation | N, R | count byte N, then N × 14-byte entries, see [Storage information](#storage-information) |
| `D9AE1C06-447D-4DEA-8B7D-FC8B19C2CDAE` | fileTransferList | N, R | 2 bytes: [0]==1 list not empty, [1]==1 list changed |
| `BD6725FC-5D16-496A-A48A-F784594C8ECB` | powerOffDuringTransfer | N, R, W | 2 bytes: [0]==1 behaviour enabled, [1]==1 auto-resize. Write: read current, wait 50 ms, write `[current[0], newAutoResize]` |
| `ef437870-180a-44ae-affd-99dbd85ade43` | cameraName | R, W | UTF-8 string |
| `e450ed9b-dd61-43f2-bdfb-6af500c910c3` | FirmwareUpdateAvailable (name from GR IV `bled`) | W (camera declares Write only; GR WORLD never writes it) | 1 byte, stored in camera property `0xC2` |
| `5f0a7ba9-ae46-4645-abac-58ab2a1f4fe4` | FirmwareUpdateStart | W | 1 byte: `00` nop, `01` start the update; other values and lengths rejected. GR WORLD writes `01` (0xdd5a44) |
| `39879aac-0af6-44b5-afbb-ca50053fa575` | FirmwareUpdateResult | N, R | 1 byte (camera property `0xC3`): 0 invalid, 1 success, 2 failure (0x57d85c). GR WORLD subscribes only on the reconnect after the firmware upload |
| `f759f4dd-5faf-4cac-82f4-5a3fe11737e7` | end-screen data | R | raw bytes, layout **[unknown]** (0xdb09b8 reads it first and falls back to the long battery record) |

`CameraServiceModel.gradNd` (@0x33) is always 0 in read-all (0xd41954); no characteristic feeds it.

### WLAN Control `F37F568F-9071-445D-A938-5441F2E82399`

Plain reads and writes only; the app never subscribes to notifications on this service. Getter block 0xad42ac..0xad42e8; builder 0x58d450; finder 0x58d120. The read-all function 0xd3eff0 type-checks each class (hJb bool, iJb/jJb String, kJb bool, lJb enum, mJb bool), which confirms the getter-order mapping. Model: `WLANControlCommandModel` (`_oJb`, toString 0xad6140).

| Characteristic UUID | Field | Ops | Payload |
|---|---|---|---|
| `9111CDD0-9F01-45C4-A2D4-E09E8FB0424D` | `networkType`, used as **WLAN on/off** | R, W | 1 byte: `01` turn the camera AP on, `00` turn it off |
| `90638E5A-E77D-409D-B550-78F7E1CA5AB4` | ssid | R, W | UTF-8 string |
| `0F38279C-FE9E-461B-8596-81287E8C9A81` | passphrase | R, W | UTF-8 string |
| `C4B7DFC0-80FD-4223-B132-B7D25A59CF85` | wlanFreq | R, W | 1 byte: `01` 5 GHz, `00` 2.4 GHz (analytics label at 0xdd958c) |
| `63BC8463-228F-4698-B30D-FAF8E3D7BD88` | security | R, W | 1 byte: 0 WPA2, 1 WPA3, 2 WPA2/WPA3 transition (write 0xe62d74, read 0xe62e78) |
| `460828AC-94EB-4EDF-9BB0-D31E75F2B165` | available5GHz | R (no write factory) | 1 byte bool |

If a characteristic is missing, read-all substitutes defaults: bools false, empty strings, WPA2 (0xd3f0f8..0xd3f128). The settings writer 0xe25b10 checks that `wlanFreq` exists before writing it. Some models may therefore lack wlanFreq, security and available5GHz **[inferred]**.

### GPS `84A0DD62-E8AA-4D0F-91DB-819B6724C69E`

| Characteristic UUID | Meaning | Ops | Payload |
|---|---|---|---|
| `28F59D60-8B8E-4FCD-A81F-61BDB46595A9` | Phone location for geotagging | W (R implemented, unused) | 32 bytes, see [GPS push](#gps-push) |

### Client Registration `0F291746-0C80-4726-87A7-3C501FD3B4B6`

| Characteristic UUID | Meaning | Ops | Payload |
|---|---|---|---|
| `FE3A32F8-A189-42DE-A391-BC81AE4DAA76` | Phone (client) name shown by the camera **[inferred]** | W (write-only executor 0xe5be3c) | UTF-8 of Android `Build.MODEL`, sanitised (0x82ebc8): keep 0x20..0x7E and U+3000, replace other characters with `?`, stop at 32 characters, trim, empty → "Unknown" |

### Device Information `180A`

| UUID | Field | Used |
|---|---|---|
| `2A29` | manufacturer | built (getter 0xcb2b54), not read by the connect path |
| `2A24` | model number | read by `uFb.connect` 0xd42080 when `checkFirmware` is true (pairing), via 0xd42668 |
| `2A25` | serial number | built, not used |
| `2A26` | firmware revision | same path, via 0xd42424; checked against the model's minimum firmware |
| `2A28` | software revision | built, not used |

### Descriptor

`00002902-0000-1000-8000-00805f9b34fb` (CCCD) is referenced by FBP's `setNotifyValue` ([pp+0x29a80], closure 0x57856c). That function also carries the `force_indications` flag [pp+0x29a60].

## Discovery and identification

### Scan settings

FBP `startScan` (Dart 0xd45898, method-channel map 0x5901ec):

- `android_scan_mode` = 2 (`SCAN_MODE_LOW_LATENCY`, 0x5903b4)
- `continuous_updates` = false
- `android_legacy` = false (extended advertising allowed)
- `android_uses_fine_location` = false
- PHY = all supported (`setPhy(255)`, `work/jadx/sources/p326m6/C4069h.java`:1425-1440)
- The only filter type is service UUIDs (one `ScanFilter` each, OR-ed).
- Any running scan is stopped first.

| Scan site | Purpose | Service filter | Timeout |
|---|---|---|---|
| 0xda4e7c (`bleDeviceDetectViewModelProvider`, route `/detect`) | find cameras to register | `9a5ed1c5-74cc-4c50-b5b6-66a48e7ccff1` ([pp+0x270e8], set in 0x590f10) | 30 s (`la@870591`, 0xda4f04) |
| 0xd46a9c (`bleScanProvider`) | find the last-connected camera and its power state | `9a5ed1c5-…` **or** `0F291746-0C80-4726-87A7-3C501FD3B4B6` (0x59151c) | 20 s (`la@8704f1`, 0xd46ca0) |
| 0xd45404 (reconnect, 0xd2ebd8) | resolve a stored camera whose `remote_id` is not a MAC address | none (result filter closure 0x5905bc) | 15 s (`la@8704e1`, 0xd45524) |

### Identifying a camera in the scan

1. Detect list (0xda502c): the scan stops at the first non-empty batch. Each result goes through 0xda542c with `advertisementData.manufacturerData`.
   - The map must be non-empty. The app takes the first value (the company-specific payload, company id stripped).
   - The payload must be longer than 2 bytes. **modelCode = payload[2]** (0xda5590..0xda55a8).
   - The company ID is never checked by the app. Firmware sends company `0x065F` (Ricoh Company Ltd) in the **scan response**, payload `DA 01 <model> 02 <serial u32 LE> 03 <flag>` (fixed-width tag/value pairs, no length bytes), so `payload[2]` is the value following tag `01` ([camera models §4.1](../camera-models.md#41-before-connecting-ble-advertising-recommended)).
   - Accepted results are sorted by RSSI, strongest first. If none are accepted, the UI shows scan failure.
2. Power state (0xd46a9c, enum `qFb` = AdvertiseResult {initialized, on, off, undetected}): the app looks for the device whose `remoteId` equals SharedPreferences `lastConnectedDevice` (must match the MAC regex `^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$` [pp+0x2a680]). It polls every 100 ms until found or the scan ends.
   - Not found → **undetected**.
   - Advertised service UUIDs contain `9A5ED1C5` → **on**.
   - They contain `0F291746` → **off** (takes precedence).

   So the camera advertises the Camera Information service while on, and the Client Registration service UUID while off/standby. The off half is **observed** on a GR IV HDF (powered off: `0F291746-…` advertised, tag `03` = `00`; [results log](../hardware-validation.md#4-results-log)); the on half is still **[inferred]**. Result model: `BleScanResultModel(advertiseResult, scanResult)` (toString 0xad5a30).
3. Identity key: the Android remote ID (BLE MAC string), stored as `lastConnectedDevice` and in DB table `device_info.remote_id`. The table also has columns `model_name`, `model_type`, `device_name`, `bd_name`, `serial_no`, `firmware_version`, `ssid`, `bssid`, `security`, `password`, `is_time_sync` (schema [pp+0x20dc8], 0x52ce74). `bd_name`, the BLE MAC and the serial number also come from the Camera Information service.

## Connection, pairing and reconnect

### Connect parameters

| Parameter | Value | Evidence |
|---|---|---|
| autoConnect | **false**. The app passes no named args to FBP `connect`; the FBP default is false | 0xd42188 (ArgDesc [pp+0x140]), default at 0xd337b4 |
| Transport | LE (`connectGatt(ctx, autoConnect, cb, 2)`) | `work/jadx/sources/p326m6/C4069h.java`:1621 |
| Connect timeout | **35 s**; on timeout FBP disconnects and reports code 10 "connection canceled" | 0xd33a74, 0xd34044 |
| MTU | **512** requested after a **350 ms** delay; requestMtu timeout 15 s | 0xd33808 (default), 0xd33d20, 0xd33d78, 0xd33ea0 |
| Service discovery timeout | 15 s | 0xd42944 |
| Connection priority / PHY | never set (no Dart call sites) | — |
| Connect retries | 3 attempts, fixed 50 ms gap; stops early on code 10 "connection canceled" | 0x5479e4 / 0xd1b0f4, 0x547aac, 0xd1b308 |
| Disconnect gap | FBP waits until ≥ **2000 ms** have passed since the connect before disconnecting | 0xd43094..0xd431cc |
| Bonding | Android `createBond`, **90 s** timeout | 0xda965c, 0xda97cc |
| CCCD | `01 00` (notify) or `02 00` (indicate-only characteristics) | `work/jadx/sources/p326m6/C4069h.java`:1912-1973 |
| GATT op serialisation | per-service mutex in the app; FBP plugin waits 50 ms before each op while a bond is in progress | 0x56ac88; `work/jadx/sources/p326m6/C4069h.java`:2175-2184 |

`uFb.connect` (0xd42080), used by every connect:

1. If another camera is connected, disconnect it and wait for `disconnected`.
2. FBP connect (above) and wait for `connected`.
3. `discoverServices` (FBP also subscribes Service Changed `2A05` if present).
4. Only when called with `checkFirmware = true` (pairing): read DIS `2A24` model and `2A26` firmware and run the minimum-firmware check. If it fails, throw ER_BL_007 "UnsupportedFirmwareVersionError" [pp+0x2a3c8].
5. Save `lastConnectedDevice`.

### Pairing / registration (`bleDevicePairingViewModelProvider`, route `/pairing`, `WOb` 0xda58b0)

Full sequence with addresses: [GR WORLD connect flow §1](grworld-connect-flow.md#1-pairing--registration-route-pairing-bledevicepairingviewmodelprovider-pp0x35e98-wob-0xda58b0).

1. Connect with `checkFirmware = true` (0xda59b4 → 0xd41ce8 → 0xd42080) to the device found by the `/detect` scan (filter `9A5ED1C5`, 30 s): connect, MTU 512, discover services, unencrypted DIS model/firmware reads and the minimum-firmware check (ER_BL_007 on failure).
2. State `connected`. Subscribe to the FBP bond-state stream (0xda6c34); its first event is Android's current bond state:
   - `none` → **explicit `createBond()`** on the open link (0xda965c at 0xda7018 → `C4069h.java:2079`), 90 s; state `bonding`. SMP is started by this call, not by an insufficient-authentication error.
   - `bonding` → log only.
   - `bonded` → continue. If the phone is already bonded, `createBond` is never called.

   Android shows its own pairing dialog; the app has no pairing-request receiver. The app's instructions: confirm the code in the phone dialog, then "tap [Execute Pairing] on the camera, or press the [OK] button … After you approve pairing on the camera … the camera registration will be completed" [pp+0x695b0]. The failure hint asks whether the user "pressed the OK button on the camera" [pp+0x694d8].
3. After `bonded` (0xda7474), the first encrypted traffic:
   1. Read all Camera Information characteristics (0xd3e248 → 0xd3e3ac).
   2. Read all WLAN characteristics (0xd3ee8c → 0xd3eff0).
   3. GR IV only: write a pending/restored camera name (0xd3fdf8).
   4. Check the model family (`modelTypeError`) and minimum firmware (`firmwareError`).
   5. GR IV: cloud firmware check (out of scope).
   6. Insert a `device_info` row (0xda91e4) → route `/connectionCheck`, `/connectionExist` or `/connectionMissing` (0xda6574).
4. **Last:** write the phone name to `FE3A32F8-…` (Client Registration; 0xda7214 → 0xda5fd4). A failed write is logged and ignored. The only unbonded write of this characteristic is on the ER_BL_007 (unsupported firmware) path (0xda5d50).
5. The link stays open on success; pairing never disconnects. Errors (enum `OOb`: modelTypeError, firmwareError, registerError, connectError, cancelError) disconnect (0xd439ac).

No characteristic write tells the camera that pairing is complete; completion on the camera side is the user's OK press. Security relies on the BLE bond: unbonded Camera Information reads fail with insufficient encryption/authentication on GR IV ([results log](../hardware-validation.md#4-results-log)).

### Camera-side pairing and reconnect rules (observed on GR IV HDF fw 1.20)

From hardware runs on 2026-11-07 ([results log](../hardware-validation.md#4-results-log)) and the firmware analysis in [firmware bonding](firmware-bonding.md). A client must follow all of them:

- **Pair only while the camera shows Execute Pairing.** The user accepts the numeric code on the phone/computer **and** presses OK on the camera. Outside Execute Pairing the camera refuses pairing; rapid retries (every 3 s) get SMP Pairing Failed reason 9 (Repeated Attempts) and a lockout. Retry no faster than every 15 s.
- **Pairing is LE Secure Connections, Numeric Comparison.** The camera distributes its IRK and public identity address and accepts only the central's IRK (no LinkKey either way). DIS and GATT discovery work unencrypted; every custom characteristic needs an encrypted (bonded) link, and on macOS the first encrypted request is what starts OS pairing (Android calls `createBond` explicitly).
- **Bonds must match on both sides.** If the camera deleted the device but the device kept its keys, CoreBluetooth reports "Peer removed pairing information". If the device forgot the camera but the camera still lists it, connects loop silently until timeout. Either way: delete the camera's **Paired Devices** entry and the OS bond, then pair again.
- **Register after the bond completes.** The Client Registration write (`FE3A32F8-…`) is rejected with "Encryption is insufficient" before bonding; GR WORLD writes it last.
- **A powered-off camera drops the first link after about 5.5 s while it wakes.** Reconnect at once (GR WORLD retries 3 × 50 ms), then read Operation Mode and write `01`/`00` if it reads `02`.
- **The camera AP appears about 16 s after WLAN-on.** A join attempted immediately fails with "network not found"; keep retrying for up to 60 s.
- **macOS cannot reconnect to a bonded camera.** macOS connects every third-party peripheral from its public identity address and distributes its IRK; the camera then ignores it at the link layer (HCI `0x3E`, macOS reason 762). A Mac gets encrypted access only on the link that did the pairing. See [firmware bonding §7(a)](firmware-bonding.md#a-the-mac-cannot-reconnect-after-pairing). Android reconnects with the same bond fine. In iOS 27.2 `bluetoothd` the connect call that macOS feeds its public-address decision gets a constant "not public" argument, so an iPhone is expected to reconnect like Android (static analysis, one code path, untested on hardware); Windows is untested.

### Reconnect / normal connect (`ILb` 0xd2b990 → 0xd2dc0c / 0xd465b8 → 0xd2e93c)

Reconnects happen **on demand only**: a feature (gallery, transfer, remote, location push, firmware) calls `ensureConnected` 0xd2b990. No timer-driven reconnect loop was found **[inferred from absence]**. The only retries are the 3 × 50 ms connect attempts. Sequence of 0xd2e93c:

1. Look up the registered `device_info` row (missing → ER_BL_001). If `remote_id` is not MAC-shaped, run an unfiltered 15 s scan to resolve it ("remoteId変換").
2. Save `lastConnectedDevice` and disconnect other cameras (0xd431f0).
3. **6 s power-off guard** (see [Wi-Fi on, path B](#b-connect-and-wlan-on-inside-the-reconnect-flow-0xd2e93c)).
4. Connect without the firmware check (0xd2f40c).
5. Optionally write WLAN-on (`WAi`).
6. Read operation mode (0xd403b8), write the pending camera name (0xd3fdf8), and refresh Camera Information and WLAN records into the DB (0xd3f640, 0xd3e874, 0xd3e248).
7. Firmware fetch and check (0xd38644, 0x54b6c0; result stored, not thrown).
8. **Subscribe to notifications** (0xd30c30 at 0xd2fb28; see below): 10 always, plus FirmwareUpdateResult only when the flag computed at 0xd2fb04..0xd2fb10 (`local == 2`, meaning **[unknown]**) is true.
9. Start the location push service (0xd46f20).
10. Analytics "success".
11. If the device record's `is_time_sync` field is set, sync the date/time (0xd2ff7c).

The whole flow runs inside a `CancelableOperation`. Cancel → ER_BL_009. Failures are logged as `bg_connect_failure` (app in background), `auto_connect_failure` (ER_BL_010), `connect_failure` (ER_BL_001) or `other_failure`.

### Notification subscriptions (0xd30c30)

Each subscription: find the characteristic, listen with the parser, `setNotifyValue(true)` (0xd3469c → CCCD write), then **read once** to prime the value (0xd314d0). The order is sequential and awaited. Item 1 is conditional. A client only needs it while waiting for a firmware-update result; the other 10 are the normal set.

1. *(conditional)* FirmwareUpdateResult `39879aac` (0xd3812c). Subscribed only when the bool argument (x2) is true. The test `tbnz w0,#4` at 0xd30c60 skips it when false. The reconnect flow passes `true` only when a local value == 2 (0xd2fb04 `cmp x0,#2` / `csel`). 0xd30c30 is also called from 0xe1e300.
2. Camera power `B58CE84C` (0xd37c94)
3. Battery `875FC41D` (0xd377fc)
4. GeoTag `A36AFDCF` (0xd37368)
5. Storage `A0C10148` (0xd36e30)
6. File transfer list `D9AE1C06` (0xd36274)
7. Power-off-during-transfer `BD6725FC` (0xd35ddc)
8. Capture mode `78009238` (0xd35944)
9. Capture status `B5589C08` (0xd354ac)
10. Drive mode `B29E6DE3` (0xd35014)
11. Shooting mode `A3C51525` (0xd31250)

Each notify setup logs `"<Name>Notify error: "` on failure. Parsers log `"onNotifyChanged, bytes: …"` [pp+0x29978].

### Disconnect handling

- `DeviceManager _onBleConnectionStateChanged` (0xe855a4): on `disconnected`, if the app is not paused and a flag is set, show a 3 s in-app snackbar.
- The `bleConnectionStateNotifierProvider` listener 0xe86418 logs `"ble: isIgnore: …, next: …"`. If `isIgnore` is false it posts the local notification "Ble接続が切断されました。" ("BLE connection was lost") [pp+0x51ee0]. `isIgnore` is set while the app disconnects deliberately **[inferred]**.
- Neither handler reconnects. The next feature that needs the camera calls `ensureConnected`.
- `DeviceManager _onCameraPowerChanged` (0xe84c3c), driven by the camera-power notification, records the power-off time (`ZBi`) that the 6 s guard uses.

### Android plugin / OS settings (flutter_blue_plus, jadx `p326m6/C4069h.java`)

- `connectGatt(..., autoConnect=false, ..., TRANSPORT_LE)` (1621).
- `requestMtu` (1982-1997).
- `requestConnectionPriority` exists (2011-2026) but the app never calls it.
- `createBond` returns false if already bonded (2069-2087).
- `clearGattCache` uses the reflected `refresh`, but no app call was found.
- FBP's own auto-reconnect (0x576ea0, `autoConnect=true`) applies only to devices connected with autoConnect, so it is unused.
- Manifest (AndroidManifest.xml:15-24): `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `WAKE_LOCK`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `RECEIVE_BOOT_COMPLETED`, fine/coarse location.
- Location push: geolocator with a foreground notification (option builders 0x5923cc / 0x5924f0, in 0xd46f20).
- `flutter_foreground_task`: started for reservation/background transfer (0xdc143c); option values **[unknown]**.
- The BLE link itself is not held by a dedicated foreground service.

## Turning the camera's Wi-Fi on (BLE → Wi-Fi hand-off)

There are two code paths that write WLAN-on. Both write `01` to `9111CDD0-…` and nothing else; the app sends no follow-up command and waits for no notification.

### A. On-demand Wi-Fi connect (`ILb` 0xdd91ac; callers 0xdd8fdc firmware wizard, 0xe07338, 0xe47bd8, 0xe49658, 0xe499a0)

1. Look up the registered camera record (closure 0x551888). If there is none, throw ER_BL_001.
2. If the phone has an active VPN (connectivity list contains `vpn`), wait 1 s (`la@870401` = 1 000 000 µs at 0xdd9724) and fail with ER_WF_010 "VPNError".
3. Branch on the record's connection-type field (+0xf, 0x58f270):
   - **0** → 0xdda950: no WLAN-on write. The app writes WLAN off (0xd43cd4), then joins with the stored credentials. **[inferred]** this is the Wi-Fi-only / non-BLE registration path.
   - **1 or 2** → the BLE path, 0xdd9fe0:
     1. Read all six WLAN characteristics (0xd3e874 → 0xd3ee8c → 0xd3eff0; 3 tries, 50 ms apart). Store ssid, passphrase, security, wlanFreq and available5GHz in the device DB record (0xd1e96c).
     2. Save SharedPreferences `lastConnectedDevice` [pp+0x27d30].
     3. **Write `01` to `9111CDD0-…`** (0xdda19c `add x2,x22,#0x20` = true → 0xd419d0 → 0xd41b3c). On failure (after 3 tries) throw ER_BL_005.
     4. Immediately call MethodChannel `com.pavct.jp.grapp/wifiConnection` → `connectToWifi` {ssid, password, serialNo, model, bdName, securityType} (0xdda5c4). Android implementation: `p085J6/AbstractActivityC0655d.java:582-664` uses `WifiNetworkSpecifier` with `setWpa2Passphrase` (securityType 0) or `setWpa3Passphrase` (1 or 2), then `requestNetwork` with a **60 s** timeout (`postDelayed 60000L`, line 658). There is a "TIMEOUT … try WPA2" fallback.
     5. 0xd1d508: verify over HTTP (model/firmware, including 0x54b6c0). A failure is ER_WF_003.
4. The whole operation is a cancelable operation (0x56f82c) stored on the `ILb` object.

The firmware-update wizard wraps this as `step2 _wifiConnect` (0xdd3c14). On failure it re-reads capture mode over BLE (0xdd7d90). If the WLAN-on write failed while the camera is in **movie mode** (capture mode = 2), it logs `step2_ble_wlan_on_video_failure` and the UI explains that the camera refuses WLAN in movie mode or while USB-connected. Other names: `step2_ble_wlan_on_failure` (write failed), `step2_ble_connect_failure` (BLE exception class), `step2_wlan_connect_failure` (Wi-Fi join failed).

### B. Connect-and-WLAN-on inside the reconnect flow 0xd2e93c

`ILb.ensureConnected` (0xd2b990) takes a named bool `WAi` (default false; parsed at 0xd2ba68..0xd2baa0) and passes it to 0xd2e93c (stored at fp-0x118, 0xd2ea04). Only three callers pass `WAi: true`: 0xdd8fdc (the firmware wizard's Wi-Fi connect), 0xe49658 and 0xe499a0. The connect flow runs:

1. **Power-off guard.** If the static `ZBi` (a nullable DateTime) is set and less than **6000 ms** old (`mov x17,#0x1770` / `cmp` at 0xd2f2c0), the flow waits out the remainder (Future.delayed at 0xd2f320; log closure 0x590c00). Otherwise it logs `"6秒経過済み: "` ("6 s already elapsed", 0xd2f348). `ZBi` is set to `DateTime.now()` only by `DeviceManager _onCameraPowerChanged` (0xe84c3c, log [pp+0x52160]). That happens when the camera-power notification goes from on to off while the app is in the foreground (0xe84cf4 / 0xe84e2c / 0xe84e58..0xe84ecc). After a connect, `ZBi` is cleared to null (0xd2f4c8..0xd2f544). So the app never reconnects within 6 s of seeing the camera power off **[inferred: the camera needs about 6 s after power-off before it accepts a new BLE connection]**.
2. BLE connect: `FSb.connect` 0xd41ce8 at 0xd2f40c (3 attempts, 50 ms apart).
3. If `WAi` is true: write `01` to `9111CDD0-…` (0xd2f474 `add x2,x22,#0x20` → 0xd419d0 at 0xd2f478; the skip test `tbnz w1,#4` is at 0xd2f43c). In this snapshot `true` = null+0x20 has bit 4 clear and `false` = null+0x30 has bit 4 set, so `tbnz #4` branches on **false**.
4. Continue with the post-connect reads and subscriptions (see [Connection](#connection-pairing-and-reconnect)).

### Minimal client sequence (derived)

1. Connect over BLE (see [Connection](#connection-pairing-and-reconnect)). If you just saw the camera power off, wait until 6 s have passed since then.
2. Read ssid `90638E5A`, passphrase `0F38279C`, security `63BC8463` (if present) and wlanFreq `C4B7DFC0` (if present).
3. Write `01` to `9111CDD0`.
4. Join the AP with the credentials you read (WPA2 for security 0; WPA3 or transition for 1/2). As the app does, allow up to 60 s for the AP to come up and the join to finish. Neither path waits for or checks anything between the WLAN-on write and the join.
5. Keep the BLE link up, as the app does. Whether the camera needs it is **[unknown]**.

## Turning the camera's Wi-Fi off

The app writes `00` to `9111CDD0-…` from these call sites:

- 0xd43cd4 (phone-side Wi-Fi disconnect; ignores write errors, log `"ble write error skip, "`): writes at 0xd441ec and 0xd44414.
- 0xd45260: writes at 0xd45348 and 0xd453cc.
- 0xe23268: after changing WLAN settings, at 0xe2361c.
- 0xe27bc8: after a reduced settings change, at 0xe27f00.
- Single writes at 0xe2b298 (0xe2b0ac) and 0xe56f0c (0xe56dbc).

## Changing the camera's WLAN settings

Full apply 0xe23268 (camera settings screen, `cameraSettingsViewModelProvider`) runs in order:

1. Write ssid (UTF-8) to `90638E5A` (0xe26be8).
2. Write passphrase to `0F38279C` (0xe25d08).
3. Write wlanFreq `00`/`01` to `C4B7DFC0` (0xe24dec; the app first checks that the characteristic exists).
4. Write security `00`/`01`/`02` to `63BC8463` (0xe23f24).
5. Disconnect the phone's Wi-Fi (0xd43cd4) and write `00` to `9111CDD0` (WLAN off).

The UI warns "Changing the settings will turn off the WLAN function of the camera". A reduced apply (0xe27bc8) writes only ssid and passphrase before WLAN off. It is presumably for models without the frequency/security characteristics **[inferred]**; the selecting branch in 0xe22814 was not decoded. SSID/passphrase length and charset rules are **[unknown]**.

## Date/time sync

0xd303b4: `DateTime.now()` (local, isUtc=false) → write `[year & 0xff, year >> 8, month, day, hour, minute, second]` to `FA46BBDD-…` (encoder 0xe5d8cc). There is no time zone, weekday or milliseconds field. 0xd303b4 is reached from closure 0x56fe88 → 0xd30254 (3 attempts, 50 ms apart; ER_BL_005 on failure). That function has two callers:

- **Every reconnect** in 0xd2e93c (call at 0xd2ff7c), but only if the stored device record's int field +0x53 == 1 (0xd2ff24..0xd2ff44). This field is **[inferred]** to be the `is_time_sync` DB column [pp+0x27e70], i.e. the user's "sync time automatically" setting.
- A settings-screen path 0xe21ac8 → 0xe21cf8. The route `/dataTimeUpdate` [pp+0x8490] (pushed from 0x9459fc and 0xdc45dc) is **[inferred]** to be that UI.

## Remote shooting over BLE (no Wi-Fi needed)

State comes from notifications: drive mode `B29E6DE3`, shooting mode `A3C51525`, capture mode `78009238`, capture status `B5589C08`. Shutter tap handler 0xe52138:

1. Throttle: 1000 ms while a 10 s countdown runs, 300 ms in continuous drive, otherwise 1500 ms (0xe521e4..0xe52218). Taps inside the window are dropped.
2. Ignore the tap while shooting is in progress (capture status byte0 = 1), after capture, or during a 2 s countdown.
3. If a 10 s self-timer countdown is running (byte1 = 1 and the drive mode is a 10 s variant): write `01` to `009A8E70` (cancel).
4. Otherwise: write `01 01` to `559644B8` (release with AF).

Self-timer button (0xe534d0) is allowed only when idle and the drive mode is 0, 1 or 2. It writes drive mode: off → `00`, 2 s → `02`, 10 s → `01` (0xe53918..0xe53948).

## Camera power off

Write `00` to `B58CE84C-…` (0xe4b1c8; constant false at 0xe4b304). The app does this from the power-off/disconnect flow 0xe49d2c (log `"write camera power: "` [pp+0x4dc88]) and after a successful firmware update (0xe86104). It never writes `01` to this characteristic. The camera then loads a different firmware image into its radio, which ends the link: [firmware bonding §6.1](firmware-bonding.md#61-the-radio-runs-a-different-firmware-image-in-each-power-state).

## Camera power on

GR WORLD wakes an off camera through Operation Mode, not Camera Power (static analysis; full sequence, addresses and caveats in [GR WORLD power-on](power-on-grworld.md)):

1. Connect directly to the registered camera (Android: stored public MAC, no scan needed). No bonding step: the bond from pairing must already exist on both sides. If the camera reported power off less than 6 s ago, wait out the rest first.
2. Read the Camera State values. If Operation Mode `1452335A` is `02` (bleStartup), write `01` (playback, home power button and Import) or `00` (capture, Remote) with response (0xd403b8; writes at 0xd404c8 / 0xd40518). Any other value means the camera is already running.
3. Keep the link and continue the normal setup, including Camera Power notifications. The app never waits for the camera to drop the link or advertise on.

Background/auto-connect never powers a camera on: it connects only when the scan shows `9A5ED1C5` and aborts with ER_BL_010 on bleStartup. Image Sync wakes a GR III/IIIx with a bare connection instead ([Image Sync BLE §2](ble-imagesync.md#2-camera-power-on--wake-from-off--definitive-answer)). Hardware results for GR IV: [results log](../hardware-validation.md#4-results-log).

## Firmware update (BLE part)

The firmware file goes over Wi-Fi first; the camera then restarts and the app reconnects (subscribing to FirmwareUpdateResult `39879aac-…` on that connection only). `_firmwareUpdate` 0xdd5398 waits 200 ms (`la@870561`), writes `01` to FirmwareUpdateStart `5f0a7ba9-…` (0xdd5a44) and waits for the FirmwareUpdateResult notification (`01` success / `02` failure). On success it writes camera power `00`. The whole sequence and the camera side are in [firmware update](firmware-update.md).

## Phone name registration

As the last pairing step, after Android reports the bond and the Camera Information and WLAN reads, the app writes the phone's model name to `FE3A32F8-…` (0xda7214 → 0xda5fd4 → 0xda62d8); failures are only logged. See the Client Registration table for the sanitising rules.

## Payload details

### Image Control blob

Parser 0xd8e104 (custom 1–3 data characteristics):

| Offset | Size | Meaning |
|---|---|---|
| 0 | 1 | version; must be 1, 2 or 4 (Set [pp+0x2bcb8]), else the blob is ignored |
| 1 | 1 | **[unknown]** (not read) |
| 2 | 1 | base image (`mRb.off_14`): 0 standard, 1 vivid, 2 monotone, 3 soft monotone, 4 hard monotone, 5 high contrast, 6 positive film, 7 bleach bypass, 8 retro, 9 HDR tone, 0x0d negative film, 0x0e cine yellow, 0x0f cine green, 0x10 cross process, 0x11 standard mono, 0x12 soft mono, 0x13 high-contrast mono, 0x14 grainy, 0x15 solid, 0x16 HDR mono, 0x17 pallet, 0x18 solarization, 0x19 pictorialist |
| 3 | 1 | N = number of parameters |
| 4 + 2i | 1 | parameter id (`nRb.off_14`, list [pp+0x2bcf8]): 0 saturation, 1 hue, 2 key, 3 contrast, 4 contrast high, 5 contrast low, 6 sharpness, 7–0x0b toning (monotone, cinema, bleach bypass, retro, HDR), 0x0c filter effect, 0x0d–0x12 filter R/G/B high/low, 0x13 shading, 0x14 clarity, 0x15 grain, 0x16 grain size, 0x17 grain strength, 0x18 HDR strength, 0x19 cross process, 0x1a base color, 0x1b white point, 0x1c black point, 0x1d–0x22 RGB tone (highlights/midtones/shadows × GM/BA), 0x23 solarization type |
| 5 + 2i | 1 | value, signed int8 (`(b & 0x7f) - (b & 0x80)` at 0xd8e504) |

Unknown parameter ids are logged ("イメコン不正値") and skipped. Which parameters each base image has, what the values mean, the slot-name rules and who builds a blob are in [image-control.md](image-control.md).

Length: every blob the camera produces is 56 bytes, zero after the last pair, so a slot holds at most 26 parameters. Observed on a GR IV HDF, firmware 1.20, on 2026-11-09: all three slots and eight photos' `/imgctrl` answers were 56 bytes with version 1. The camera answered a write-with-response to Custom 1 data with an error for a 74-byte blob (18 parameters followed by 34 zero bytes) and for a 22-byte blob (9 parameters, no padding), and accepted a 56-byte blob identical to what the slot held. A 56-byte blob with new content has not yet been written to a camera. Android reported only "Failed to write". The firmware explains the two refusals differently ([image-control.md §1](image-control.md#1-who-builds-a-blob)): the data characteristics are registered with a 56-byte maximum, and `bled` itself drops a longer write without a response, yet the 74-byte write got its error about 50 ms later, so the Bluetooth stack under `bled` presumably refused it against the registered maximum first **[inferred]**. A shorter write goes to the RTOS unchanged, so the 22-byte refusal came from the RTOS **[inferred]**. Nothing in `bled` requires exactly 56 bytes.

### Storage information

Read 0xe5f82c and notify parser 0x57c5a4. Byte 0 = entry count N; the remaining length must equal N × 14 (0x57ced4), otherwise the app throws a RangeError.

| Entry offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 1 | type | 0 internal memory, 1 SD slot 1, 2 SD slot 2 |
| 1 | 1 | isExistence | `==1` |
| 2 | 1 | isLocked | `==1` |
| 3 | 1 | isAvailable | `==1` |
| 4 | 1 | isFormatted | `==1` |
| 5 | 4 | remainingPictures | int32 LE (0xe5fda4) |
| 9 | 4 | remainingVideoSeconds | int32 LE (0xe5fe40) |
| 13 | 1 | fileType | int8; GR WORLD does not interpret it. From GR IV firmware: 0 JPEG, 1 PEF, 2 DNG, 3 JPEG+PEF, 4 JPEG+DNG (below) |

GR IV `bled` 1.20 builds the value as follows (found in code, 2026-11-10, not yet observed on hardware; decompiled functions in `firmware/evidence/gr4-bled-storageinformation-*.c`, `gr4-bled-manager-storagechanged.c`, `gr4-bled-filetype-getblevalue.c`, `gr4-webapid-storage-name-table-init.c`):

- `CameraService::StorageInformation::GetBLEValue` (0x5b694) asks the camera for its storage id list, sorts the ids ascending and writes one 14-byte entry per id. The ids are the ones `webapid` names in its `storage_name` table (`_INIT_45`, at 0xaee6c): 0 `in`, 1 `sd1`, 2 `sd2`. So **internal memory comes first, then the SD card**, and the type byte is the id.
- The count byte is the constant `02`, not the number of ids. What the id list holds when no card is inserted is **[unknown]**: if it is one id, the value would be `02` plus 14 bytes, which neither GR WORLD nor GR Photo's decoder accepts.
- Per entry: isExistence = `GetEquipped`, isLocked = protection state ≠ 2, isAvailable = accessible, formatted (format state 1) and no error, isFormatted = format state 1, then `GetRemainingStillIamges` and `GetRemainingMovieSeconds`. A storage whose information cannot be read becomes 14 zero bytes.
- fileType is the storage's still record format (`GetStillRecFormat`) through `convFileType`, the table File Type (`95BFA8CA`, [Image Sync table](ble-imagesync.md)) byte 0 also uses.
- **Nothing says which storage the camera saves to.** There is no 15th byte (Image Sync's `Active`), although `libcamera-controller` has `StorageInfo::GetWriteTarget`; only `mtpd` (USB) calls it. `/v1/props` `storages[]` has no such field either: `Storage::Fetch` (0xa95f8) reads name, equipped, available, writable, format, remain, recordable time and the file counts, and the string `active` does not occur in `webapid`.
- The camera notifies the value (29 bytes, `StorageInformation::Notify` 0x5f9fc) when `BleServerManager::StorageChanged` (0x4edb0) gets a storage event with action 4, which is **[inferred]** to be "information changed" (`StorageEvent::CreateInfoChanged` in `libcamera-controller`).

Where a GR IV saves is its Shooting Memory Setting (A4/B4 menu; manual p.90): Internal Memory Priority, or Memory Card Priority, which uses the card whenever one is inserted. The camera does not switch to the other memory when the chosen one is full or fails. A client therefore cannot tell from Storage Information which count applies, so GR Photo shows the count of every storage that is present, on the camera sheet and on Shoot.

A possible source for the setting, **[unknown]** until tested on hardware: File Type (`95BFA8CA`) byte 3. On a GR IV, `Shooting::FileType::GetBLEValue` (0x73640) sends byte 0 from camera property `0x24`, bytes 1 and 2 as `FF`, and byte 3 from camera property `0x23`, which `bled` calls SlotMode (`convSlotMode` 0x73524: 0, 1, 2 pass through, anything else becomes `FF`). On PENTAX bodies that byte is the two-slot mode (sequential, duplicate, RAW/JPEG split); whether a GR IV uses the property for Shooting Memory Setting is not in `bled`.

### GPS push

Write 0xe608e8 to `28F59D60-…`, 32 bytes:

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 8 | latitude (degrees) | float64 **big-endian** (0xa131d0: `Float64List` bytes reversed) |
| 8 | 8 | longitude | float64 BE |
| 16 | 8 | altitude (m) | float64 BE |
| 24 | 2 | year (of the position fix's timestamp) | int16 LE (0xa13034) |
| 26 | 1 | month | |
| 27 | 1 | day | |
| 28 | 1 | hour | |
| 29 | 1 | minute | |
| 30 | 1 | second | |
| 31 | 1 | datum | constant 0 (0xe60b70) |

The timestamp is the **fix time in UTC**: it is geolocator's `Position.timestamp`, built with `isUtc: true` (0xc28bd4) and encoded without conversion ([geotagging.md §2.5](geotagging.md#25-timestamp)). The camera firmware never reads the datum byte ([geotagging.md §1.1](geotagging.md#11-bluetooth-daemon-bled)).

Timing: the location service (0xd46f20) reads the SharedPreferences int `locationFreqNum` [pp+0x2a890] (default 0) and maps it to a periodic timer: 0 → 5 s, 1 → 30 s, 2 → 180 s (0xd482f0/0xd48360; Smi 0xa/0x3c/0x168). Each tick (0xd47664) takes the last stored position and writes it (0xd47794 → 0xd47b00 → 0xd47c6c) when a camera is connected and its GEO Tag is on, with no check that the position is new. The service's start and stop conditions, the background limit and what the camera does with a record are in [geotagging.md](geotagging.md).

## Evidence

All addresses refer to `work/dis/dis.txt` (libapp.so isolate instructions). `pp+0x…` refers to `work/cs/blutter_out/pp.txt`. `Obj!…@…` objects are listed in `work/cs/blutter_out/objs.txt`. Smi integers are stored ×2. Dart `true`/`false` are null+0x20/null+0x30, so `tbnz w,#4` branches on false. `Obj!la@…` Durations hold microseconds.

### UUID index (every 128-bit UUID in the object pool)

The UUID→class mapping comes from the `uuid` getter blocks, which are emitted in descending class-id order:

| Block | Address range |
|---|---|
| services | 0xb1c1ac..0xb1c1f4 |
| Camera Control | 0xa1f670..0xa1f6fc |
| Camera State | 0xb1c200..0xb1c2a4 |
| WLAN Control | 0xad42ac..0xad42f0 |
| Camera Information | 0xb1b1fc..0xb1b240 |
| DIS | 0xcb2b54..0xcb2b84 |

The rule was cross-checked against the service finders' literal UUIDs, the DIS model/firmware reads, the WLAN read-all type checks (0xd3eff0) and the Camera Information read-all cid compares (0xd3e598..0xd3e64c).

| UUID | Role | Owning service | Meaning | Class (cid) | Pool | Load site(s) |
|---|---|---|---|---|---|---|
| `9a5ed1c5-74cc-4c50-b5b6-66a48e7ccff1` | service (scan filter copy) | — | Camera Information | uFb/oFb fields | pp+0x270e8 | 0x590f3c, 0x591540 |
| `258EAFA5-E914-47DA-95CA-C5AB0DC85B11` | not BLE | — | RFC 6455 WebSocket handshake GUID, used by the Wi-Fi/WebSocket code (0x566ca0), not by BLE | — | pp+0x285f8 | 0x567000 |
| `4B445988-CAA0-4DD3-941D-37B4F52ACA86` | service | — | Camera State | SHb 0x651 | pp+0x29878 | 0x56ff10, 0xb1c1bc |
| `00002902-0000-1000-8000-00805f9b34fb` | descriptor | any notify char | CCCD (FBP setNotifyValue) | — | pp+0x29a80 | 0x5785f0 |
| `9F00F387-8345-4BBC-8B92-B87B52E3091A` | service | — | Camera Control | WHb 0x64d | pp+0x29ad8 | 0x578a58, 0xb1c1ec |
| `9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1` | service | — | Camera Information | RHb 0x652 | pp+0x2a178 | 0x58cd8c, 0xb1c1b0 |
| `0F291746-0C80-4726-87A7-3C501FD3B4B6` | service (+ scan filter, "off" advert) | — | Client Registration | VHb 0x64e | pp+0x2a760 | 0x591584, 0x82e8b4, 0xb1c1e0 |
| `84A0DD62-E8AA-4D0F-91DB-819B6724C69E` | service | — | GPS | UHb 0x64f | pp+0x2a7a8 | 0x5919d8, 0xb1c1d4 |
| `28F59D60-8B8E-4FCD-A81F-61BDB46595A9` | char | GPS | location record | PHb 0x654 | pp+0x2a7b0 | 0x591a8c |
| `FE3A32F8-A189-42DE-A391-BC81AE4DAA76` | char | Client Registration | phone name | AFb 0x698 | pp+0x35dd0 | 0x82e968 |
| `63BC8463-228F-4698-B30D-FAF8E3D7BD88` | char | WLAN Control | security | lJb 0x62c | pp+0x41080 | 0xad42e0 |
| `9111CDD0-9F01-45C4-A2D4-E09E8FB0424D` | char | WLAN Control | networkType = WLAN on/off | hJb 0x630 | pp+0x41098 | 0xad42b0 |
| `90638E5A-E77D-409D-B550-78F7E1CA5AB4` | char | WLAN Control | ssid | iJb 0x62f | pp+0x410b0 | 0xad42bc |
| `460828AC-94EB-4EDF-9BB0-D31E75F2B165` | char | WLAN Control | available5GHz | mJb 0x62b | pp+0x410b8 | 0xad42ec |
| `C4B7DFC0-80FD-4223-B132-B7D25A59CF85` | char | WLAN Control | wlanFreq | kJb 0x62d | pp+0x410d0 | 0xad42d4 |
| `0F38279C-FE9E-461B-8596-81287E8C9A81` | char | WLAN Control | passphrase | jJb 0x62e | pp+0x410e8 | 0xad42c8 |
| `cd879e7a-ab9f-4c58-90ed-689bae67ef8e` | char | Camera Control | custom3 data | uIb 0x63f | pp+0x41100 | 0xa1f6f8 |
| `e799198f-cf3f-4650-9373-b15dda1b618c` | char | Camera Control | custom2 name | qIb 0x643 | pp+0x41118 | 0xa1f6c8 |
| `009A8E70-B306-4451-B943-7F54392EB971` | char | Camera Control | cancel | oIb 0x645 | pp+0x41138 | 0xa1f6b0 |
| `df77dd09-0a48-44aa-9664-2116d03b6fd7` | char | Camera Control | custom3 name | rIb 0x642 | pp+0x41140 | 0xa1f6d4 |
| `B29E6DE3-1AEC-48C1-9D05-02CEA57CE664` | char | Camera Control | drive mode | kIb 0x649 | pp+0x41160 | 0xa1f680 |
| `0936b04c-7269-4cef-9f34-07217d40cc55` | char | Camera Control | custom2 data | tIb 0x640 | pp+0x41168 | 0xa1f6ec |
| `78009238-AC3D-4370-9B6F-C9CE2F4E3CA8` | char | Camera Control | capture mode | mIb 0x647 | pp+0x41188 | 0xa1f698 |
| `A3C51525-DE3E-4777-A1C2-699E28736FCF` | char | Camera Control | shooting mode | lIb 0x648 | pp+0x411a8 | 0xa1f68c |
| `B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA` | char | Camera Control | capture status | nIb 0x646 | pp+0x411c0 | 0xa1f6a4 |
| `30adb439-1bc0-4b8e-9c8b-2bd1892ad6b0` | char | Camera Control | custom1 name | pIb 0x644 | pp+0x411c8 | 0xa1f6bc |
| `3e0673e0-1c7b-4f97-8ca6-5c2c8bc56680` | char | Camera Control | custom1 data | sIb 0x641 | pp+0x411d0 | 0xa1f6e0 |
| `559644B8-E0BC-4011-929B-5CF9199851E7` | char | Camera Control | shutter release | jIb 0x64a | pp+0x411f0 | 0xa1f674 |
| `F37F568F-9071-445D-A938-5441F2E82399` | service | — | WLAN Control | THb 0x650 | pp+0x411f8 | 0xb1c1c8 |
| `5f0a7ba9-ae46-4645-abac-58ab2a1f4fe4` | char | Camera State | fw update start [inferred] | iGb 0x680 | pp+0x41250 | 0xb1c288 |
| `FA46BBDD-8A8F-4796-8CF3-AA58949B130A` | char | Camera State | dateTime | XFb 0x68b | pp+0x41268 | 0xb1c204 |
| `B58CE84C-0666-4DE9-BEC8-2D27B27B3211` | char | Camera State | cameraPower | YFb 0x68a | pp+0x41280 | 0xb1c210 |
| `875FC41D-4980-434C-A653-FD4A4D4410C4` | char | Camera State | batteryLevel | ZFb 0x689 | pp+0x41288 | 0xb1c21c |
| `D9AE1C06-447D-4DEA-8B7D-FC8B19C2CDAE` | char | Camera State | fileTransferList | eGb 0x684 | pp+0x41290 | 0xb1c258 |
| `BD6725FC-5D16-496A-A48A-F784594C8ECB` | char | Camera State | powerOffDuringTransfer | fGb 0x683 | pp+0x412a8 | 0xb1c264 |
| `39879aac-0af6-44b5-afbb-ca50053fa575` | char | Camera State | fw update result | jGb 0x67f | pp+0x412b0 | 0xb1c294 |
| `430B80A3-CC2E-4EC2-AACD-08610281FF38` | char | Camera State | operationModeList | aGb 0x688 | pp+0x412b8 | 0xb1c228 |
| `1452335A-EC7F-4877-B8AB-0F72E18BB295` | char | Camera State | operationMode | bGb 0x687 | pp+0x412d8 | 0xb1c234 |
| `A36AFDCF-6B67-4046-9BE7-28FB67DBC071` | char | Camera State | geoTag | cGb 0x686 | pp+0x412f0 | 0xb1c240 |
| `f759f4dd-5faf-4cac-82f4-5a3fe11737e7` | char | Camera State | end-screen data | kGb 0x67e | pp+0x412f8 | 0xb1c2a0 |
| `e450ed9b-dd61-43f2-bdfb-6af500c910c3` | char | Camera State | fw update available [inferred] | hGb 0x681 | pp+0x41310 | 0xb1c27c |
| `A0C10148-8865-4470-9631-8F36D79A41A5` | char | Camera State | storageInformation | dGb 0x685 | pp+0x41318 | 0xb1c24c |
| `ef437870-180a-44ae-affd-99dbd85ade43` | char | Camera State | cameraName | gGb 0x682 | pp+0x41330 | 0xb1c270 |
| `97E34DA2-2E1A-405B-B80D-F8F0AA9CC51C` | char | Camera Information | bluetoothMacAddress | LFb 0x68f | pp+0x41338 | 0xb1b23c |
| `6FE9D605-3122-4FCE-A0AE-FD9BC08FF879` | char | Camera Information | bluetoothDeviceName | KFb 0x690 | pp+0x41340 | 0xb1b230 |
| `35FE6272-6AA5-44D9-88E1-F09427F51A71` | char | Camera Information | modelNumber | 0x693 | pp+0x41348 | 0xb1b20c |
| `F5666A48-6A74-40AE-A817-3C9B3EFB59A6` | char | Camera Information | manufacturerName | 0x694 | pp+0x41350 | 0xb1b200 |
| `B4EB8905-7411-40A6-A367-2834C2157EA7` | char | Camera Information | firmwareRevision | 0x691 | pp+0x41358 | 0xb1b224 |
| `0D2FC4D5-5CB3-4CDE-B519-445E599957D8` | char | Camera Information | serialNumber | 0x692 | pp+0x41360 | 0xb1b218 |

DIS (`180A`) uses 16-bit UUIDs in the pool: `2A29` [pp+0x41210], `2A24` [pp+0x41208], `2A25` [pp+0x41220], `2A26` [pp+0x41218], `2A28` [pp+0x41200]; service `180A` [pp+0x2a410]; getter block 0xcb2b54..0xcb2b84.

### Key functions

| Address | Role |
|---|---|
| 0xe5c094 | FBP `writeCharacteristic`; `withResponse` enum [pp+0x40f58] = `Obj!Wpb@868fd1` (`work/cs/blutter_out/objs.txt`:56962) loaded at 0xe5c17c |
| 0x5479e4 | Generic retry: 3 attempts (`mov x5,#3` 0x547aac), 50 ms delay (`Obj!la@8704a1` = 0xc350 µs, pp+0x1ffb8) |
| 0xd30588 | Execute a characteristic command under the per-service mutex (0x56ac88 lock / 0x569ae8 unlock) |
| 0xd30c30 | Subscribe-all notifications (order in [Notification subscriptions](#notification-subscriptions-0xd30c30)) |
| 0xd42080 / 0xd33764 | App connect / FBP connect (autoConnect false, MTU 512 after 350 ms, 35 s timeout) |
| 0xd41ce8 | Connect with retry (3 × 50 ms) |
| 0xd2b990 → 0xd2dc0c / 0xd465b8 → 0xd2e93c | `ensureConnected` → reconnect flow (6 s guard 0xd2f2c0, connect 0xd2f40c, optional WLAN-on 0xd2f478, subscribe 0xd2fb28, location 0xd2fc9c, time sync 0xd2ff7c) |
| 0xe84c3c | `DeviceManager _onCameraPowerChanged`; sets the power-off timestamp `ZBi` [pp+0x29748] |
| 0xe855a4, 0xe86418 | Disconnect handlers (snackbar; "ble: isIgnore:" notification) |
| 0xd45898 / 0x5901ec | FBP `startScan` / scan settings map (scan mode 2) |
| 0xda4e7c, 0xda502c, 0xda542c | Detect scan (30 s), result listener, manufacturer-data model code |
| 0xd46a9c | Last-device scan (20 s), power state from advertised UUIDs |
| 0xda58b0, 0xda6fa4, 0xda965c, 0xda7474 | Pairing VM start, bond-state listener, `createBond` (90 s), post-bond reads and registration |
| 0xda5fd4 → 0xda62d8, 0x82ebc8 | Phone-name write to FE3A32F8, name sanitiser |
| 0xdd91ac → 0xdd9fe0 → 0xdda19c / 0xdda5c4 | Wi-Fi connect: WLAN read-all, WLAN-on write, `connectToWifi` |
| 0xd3eff0, 0xd419d0 → 0xd41b3c | WLAN read-all; WLAN on/off write |
| 0xe23268, 0xe27bc8 | WLAN settings apply (full / reduced) |
| 0xd303b4, 0xe5d8cc | Date/time write and encoder |
| 0xd46f20, 0xd47c6c, 0xe608e8 | Location service, GPS write site, GPS encoder |
| 0xe52138, 0xe534d0, 0xe61b40 | Shutter tap handler, self-timer button, shutter payload |
| 0xe4b1c8 | Camera power write (constant false) |
| 0xdd5398 / 0xdd5a44 | Firmware-update start write and result wait |
| 0xd8e104 | Image Control blob parser |
| 0xe5f82c / 0x57ce2c | Storage information decoder |
| 0x54b6c0 / 0x54b7f4 | Model → minimum firmware; version compare |

Android (jadx): `p326m6/C4069h.java` (FBP plugin: scan 1399-1495, connect 1607-1632, disconnect 1642-1680, setNotifyValue 1912-1973, requestMtu 1982-1997, connection priority 2011-2026, bond 2059-2098); `p085J6/AbstractActivityC0655d.java:582-664` (`connectToWifi`, 60 s `requestNetwork` timeout); `AndroidManifest.xml:15-24` (permissions).

Working notes with more detail: `research/notes/ble/{CamSvcChars,WfbChars,WlanChars,BleConn}.md`.

## Open questions (confirm with a BLE sniff / live camera)

**Advertising and discovery**
1. Company ID and manufacturer-data layout are resolved statically from firmware ([camera models §4.1](../camera-models.md#41-before-connecting-ble-advertising-recommended)); tag `03` is camera power (1 on, 0 off) per Image Sync's `def_adv.yaml`. Still open: which service UUID `bled` advertises in each state.
2. Does the camera really advertise `9A5ED1C5` when on? Statically, GR IV's powered-off BT-only advertiser (`sysmgrd` `load_bt_only_fw::setAdvertData`) hard-codes `0F291746` and tag `03 = 00`, which supports the app's "off" interpretation; Image Sync's scan filter accepts either UUID. BLE wake by bare connection is documented for GR III/IIIx by Image Sync; confirm on GR IV ([hardware plan](../hardware-validation.md), session D).

**Pairing and security**
3. Pairing method per model (passkey entry vs numeric comparison).
4. Does the camera reject GATT access before bonding? Which characteristics need encryption?
5. Does the camera require the phone-name write (`FE3A32F8`) before or after bonding? How is it used (paired-device list)?

**Link parameters**
6. Negotiated MTU (the app requests 512). Characteristic properties (Write vs Write Without Response support; notify vs indicate), as seen in the GATT discovery dump.
7. What exactly the 6 s guard protects (time since camera power-off). Is a shorter reconnect after power-off rejected? Firmware lead: at power-off the camera downloads its BT-only image into the radio ([firmware bonding §6.1](firmware-bonding.md#61-the-radio-runs-a-different-firmware-image-in-each-power-state)) **[inferred]**.

**WLAN**
8. WLAN: are SSID/passphrase fixed-length NUL-padded on read (the app strips `\u0000` [inferred])? What does `9111CDD0` read back while WLAN is on vs off? How long after the `01` write until the AP beacons? Which ATT error does the camera return when WLAN-on is refused (movie mode, USB connection)? Are new ssid/passphrase/freq/security values applied only at the next WLAN-on?
9. Which models lack wlanFreq / security / available5GHz (GR III/IIIx vs GR IV)? Which branch selects the reduced settings apply?

**Other characteristics and payloads**
10. Shutter `01 01`: does it start/stop movie recording and close a running T/B exposure? Does capture status notify within the write round-trip?
11. Drive-mode writes other than 0/1/2: does the camera accept them?
12. Unrecovered payloads:
    - operationModeList value semantics
    - end-screen data (`f759f4dd`) layout and the long battery record (len ≥ 130, byte1 = 1), including which models send it
    - whether File Type (`95BFA8CA`) byte 3 follows the GR IV's Shooting Memory Setting: read it with the setting on Internal Memory Priority and on Memory Card Priority (see [Storage information](#storage-information))
    - Storage Information with no card inserted: one entry or two, and the count byte (GR IV `bled` always writes `02`)
    - Image Control blob byte 1 and version differences
13. GPS on hardware: the firmware reads the timestamp as UTC, ignores the datum byte and refuses a record while GEO Tag is off, all from code. The tests that confirm it are in [geotagging.md §7](geotagging.md#7-hardware-tests).
14. Camera Information MAC string format (colons, case). Exact DIS `2A24` model number for GR IV Monochrome / HDF: GR WORLD's firmware gate needs exactly "GR IV"/"GR IIIx"/"GR III"/"GR II"; `bled` has no DIS implementation, so the DIS server and strings are unknown. The custom model-name characteristic returns the firmware model property (e.g. `RICOH GR IV Monochrome` **[inferred]**).
