# WFb family (svc 4B445988) + PHb (84A0DD62/28F59D60) + AFb (0F291746/FE3A32F8) — notes (WfbChars)

## How the char → codec mapping was recovered
- Each characteristic class has two virtual "operation factories":
  - `readOp(dpb)` = dispatch selector **cid-0xffe** (call sites e.g. 0xd41138, 0xdb0af8); allocates an op object `{@7 dpb, @0xb yFb.read [pp+0x34c70]}`. Factory bodies: block 0xcb28e4..0xcb2b4c (op classes in order pGb, oGb, lGb, xGb, wGb, vGb, zGb, rGb, yGb, nGb, tGb, qGb).
  - `writeOp(dpb, param)` = selector **cid-0xebd** (call sites 0xd30520 XFb, 0xdd5b84 iGb); allocates op `{@7 dpb, @0xb yFb.write [pp+0x2a798], @0xf param}` and calls the op's typed `setParameter` (type test). Factory bodies 0xcb12b4..0xcb193c: pGb(ka DateTime, 0xcb12f8), oGb(bool 0xcb13f0), wGb(SFb 0xcb14c8), vGb(bool 0xcb15c0), yGb(bool 0xcb1698), nGb(String 0xcb1770), sGb(bool 0xcb1864), uGb(bool 0xcb193c).
  - Both factory blocks follow descending char-class cid (same rule as uuid getters 0xb1c200..0xb1c2a0); every slot is type-consistent with "read all" 0xd40f68, so mapping below is [inferred: block order] but cross-checked by types and by cid-compare users.
- Op execute methods (dispatch targets, descending op-class cid, 0xe5c544..0xe6309c) switch on yFb (0=read → read impl, 1=write → write impl, else UnsupportedError " command is not supported").
- Generic executor 0xd30588(op) → op.execute (selector +0xd6a7).
- All writes go through FBP write 0xe5c094 which hardcodes **writeType = withResponse** ([pp+0x40f58] Obj!Wpb "withResponse", 0xe5c17c) and allowLongWrite=false (0xe5c184). Log "write params: <list>".
- Common byte reader 0x5794c0(bytes,{start,end}) = `ByteData.view(Uint8List.fromList(bytes.sublist(start,end))).getInt8(0)` → **signed int8 of bytes[start]** (default start=0).
- Encoders: 0xa12fd4(v) = `Int8List([v]).buffer.asUint8List()` (1 byte); 0xa13034(v) = `Int16List([v])...asUint8List()` → **2 bytes little-endian** (native arm64); 0xa131d0(d) = `Float64List([d])` bytes then `.reversed.toList()` (0x5bcae8 AllocateSh=ReversedListIterable, 0x46bbec) → **8-byte IEEE754 big-endian**.
- Decoders: 0xa13094 = int16 read with no byte swap (ldrsh, 0xa13138) → little-endian; 0xa13244 = float64 read with byte swap (0xa13324..) → big-endian.
- Bool decode: `bytes[0] == 1` (e.g. 0xe5d6f4-0xe5d704). Bool encode: true → `[0x01]`, false → `[0x00]` (0xe5d5a8..0xe5d650; same in 0xe5ec0c, 0xe5e920, 0xe5e3fc).

## Per-class table (WFb, svc 4B445988-CAA0-4DD3-941D-37B4F52ACA86)
| class (cid) | UUID | meaning (model field / provider) | ops used by app | op class (cid) / impl | Dart type | byte layout |
|---|---|---|---|---|---|---|
| XFb 0x68b | FA46BBDD-8A8F-4796-8CF3-AA58949B130A | **dateTime** (CameraServiceModel @0x13) | read (0xd40f68), write (0xd303b4) | pGb 0x6bd; read 0xe5db84, write 0xe5d8cc | ka (DateTime) | 7 bytes: [0..1] year int16 **LE**, [2] month, [3] day, [4] hour, [5] minute, [6] second (local time). Read log "DateTimeCommand.read, カメラ時間取得:" [pp+0x4b2e0] |
| YFb 0x68a | B58CE84C-0666-4DE9-BEC8-2D27B27B3211 | **cameraPower** (@7, cameraPowerNotifierProvider DHb) | read, write (0xe4b1c8), notify (CameraPowerNotify 0xd37c94; setup 0xd37f68; parser DHb 0x57d558) | oGb 0x6be; read 0xe5d6a4, write 0xe5d568 | bool | 1 byte: 1=on(true), 0=off |
| ZFb 0x689 | 875FC41D-4980-434C-A653-FD4A4D4410C4 | **batteryLevel** (@0xb, batteryLevelNotifierProvider CHb) | read, notify (BatteryNotify 0xd377fc; setup 0xd37ad0; parser CHb 0x57d334 → battery_empty/low/half/full svg), raw read for end-screen fallback (0xdb09b8, op mGb 0x6c0 raw 0xe5d0b0) | lGb 0x6c1; read 0xe5cfdc | int? | byte0 = level (int8). Long form (older cams?): len≥130 && byte1==1 → bytes[2..130) = 128-byte end-screen data (0xdb0d10..0xdb0e40) |
| aGb 0x688 | 430B80A3-CC2E-4EC2-AACD-08610281FF38 | **operationModeList** (@0x17) | read only | xGb 0x6b5; read 0xe5f1e4 | int | byte0 int8 [semantics of value: unknown — likely bitmask of allowed SFb modes, unverified] |
| bGb 0x687 | 1452335A-EC7F-4877-B8AB-0F72E18BB295 | **operationMode** (@0x1f) | read, write (0xd40c54) | wGb 0x6b6; read 0xe5efa8 (0xa13154), write 0xe5eea4 | SFb | 1 byte: 0 capture, 1 playback, 2 bleStartup, 3 other, 4 powerOffTransfer (SFb.off_14 = wire value; objs.txt 56083-56121). Default when absent: other |
| cGb 0x686 | A36AFDCF-6B67-4046-9BE7-28FB67DBC071 | **geoTag** enabled (@0x23, geoTagNotifierProvider HHb, GeoTagModel(isEnabled)) | read, write (0xe47628), notify (GeoTagNotify 0xd37368; setup 0xd3763c; parser HHb 0x57d198) | vGb 0x6b7; read 0xe5d6a4, write 0xe5ec0c | bool | 1 byte 1/0 |
| dGb 0x685 | A0C10148-8865-4470-9631-8F36D79A41A5 | **storageInformation** (@0x27, storageInformationNotifierProvider JHb) | read, notify (StorageNotify 0xd36e30; setup 0xd37104; parser JHb 0x57c5a4) | zGb 0x6b3; read 0xe5f82c | List<yHb> StorageInformationModel(type zHb, isExistence, isLocked, isAvailable, isFormatted, remainingPictures, remainingVideoSeconds, fileType) | see "Storage layout" |
| eGb 0x684 | D9AE1C06-447D-4DEA-8B7D-FC8B19C2CDAE | **fileTransferList** (@0x2b, fileTransferListNotifierProvider FHb) | read, notify (FileTransferListNotify 0xd36274; setup 0xd36548; parser FHb 0x579d58) | rGb 0x6bb; read 0xe5e168 | _bHb {isNotEmpty, isChanged} | 2 bytes: [0]==1 → isNotEmpty, [1]==1 → isChanged |
| fGb 0x683 | BD6725FC-5D16-496A-A48A-F784594C8ECB | **powerOffDuringTransfer** (@0x2f, powerOffDuringFileTransferNotifierProvider IHb) | read, write (0xe45ba0), notify (PowerOffDuringFileTransferNotify 0xd35ddc; setup 0xd360b0; parser IHb 0x579b04) | yGb 0x6b4; read 0xe5f598, write 0xe5f3fc | rHb/_wHb {behavior, autoResize} | 2 bytes: [0]==1 behavior, [1]==1 autoResize. Write = read current, wait 50 ms (Duration 0xc350 µs [pp+0x1ffb8]), write `[current.behavior?1:0, param?1:0]` (param = new autoResize bool) |
| gGb 0x682 | ef437870-180a-44ae-affd-99dbd85ade43 | **cameraName** (@0x3b, default "MY GR IV" [pp+0x2a358]) | read (0xd3fc5c), write (0xd4020c) | nGb 0x6bf; read 0xe5c6ac, write 0xe5d340 | String? | UTF-8 bytes (utf8 decode [pp+0x240] / encode [pp+0x13a0] 0xb58618), no length prefix/terminator added |
| hGb 0x681 | e450ed9b-dd61-43f2-bdfb-6af500c910c3 | **FirmwareUpdateAvailable** [inferred: block order; log string [pp+0x4b290]] | write only (no app caller found besides read-all skip) | sGb 0x6ba; write 0xe5e3fc | bool | 1 byte 1/0 |
| iGb 0x680 | 5f0a7ba9-ae46-4645-abac-58ab2a1f4fe4 | **FirmwareUpdateStart** [inferred: block order; log [pp+0x4b250]] | write `true` in FW update step4 (0xdd5a44 ← 0xdd59f0 ← 0xdd5740 "_firmwareUpdate") | uGb 0x6b8; write 0xe5e920 | bool | `[0x01]` |
| jGb 0x67f | 39879aac-0af6-44b5-afbb-ca50053fa575 | **FirmwareUpdateResult** (firmwareUpdateResultNotifierProvider GHb) | notify (FirmwareUpdateResultNotify 0xd3812c via 0xd38400; parser GHb 0x57d6f4 "FirmwareUpdateResult, onNotifyChanged, bytes: "), read op exists | tGb 0x6b9; read 0xe5e6e4 (0x57d85c) | AGb | byte0: 0 invalid, 1 success, 2 failure (else throws) |
| kGb 0x67e | f759f4dd-5faf-4cac-82f4-5a3fe11737e7 | **end-screen data** (終了画面データ) | read (0xdb09b8, first choice; falls back to ZFb long form) | qGb 0x6bc; read 0xe5df6c | List<int> | raw bytes [layout unknown] |

Notes: CameraServiceModel (_UFb, toString 0xad5bbc) fields: @7 cameraPower, @0xb batteryLevel, @0x13 dateTime, @0x17 operationModeList, @0x1f operationMode, @0x23 geoTag, @0x27 storageInformation, @0x2b fileTransferList, @0x2f powerOffDuringTransfer, @0x33 gradNd (always 0 in 0xd41954; no char reads it — [unknown] source), @0x3b cameraName. Read-all 0xd40f68: classes 0x681..0x67e hit 0x54505c (not read). Defaults when char missing: dateTime=DateTime(1990) (0xd417e4 #0x7c6), operationMode=other, lists empty, name "MY GR IV".

## PHb (svc 84A0DD62-E8AA-4D0F-91DB-819B6724C69E, char 28F59D60-8B8E-4FCD-A81F-61BDB46595A9) — GPS location push
- op NHb 0x6ad (writeOp factory 0x591958, yFb.write), execute 0xe6077c → read 0xe60c40, write 0xe608e8; param type Fzb = geolocator `Position` (lat @7, lon @0xf, timestamp @0x17, alt @0x1b; reader logs "parse: latitude/longitude/altitude/year/month/day/hours/minutes/seconds/datum").
- **Write layout (32 bytes)**, 0xe608e8:
  1. [0..7] latitude float64 big-endian (0xa131d0)
  2. [8..15] longitude float64 BE
  3. [16..23] altitude float64 BE
  4. [24..25] year int16 little-endian (0xa13034) of Position.timestamp
  5. [26] month, [27] day, [28] hour, [29] minute, [30] second (int8 each)
  6. [31] datum = 0 (0xe60b70 constant)
- Read 0xe60c40 decodes the same 32 bytes back (byte 31 logged as ", datum: ").
- Caller chain: 0xd46f20 (location service UPb, log "Location error: " [pp+0x27518]) → 0xd47794 → 0xd47b00 (wraps closure 0x591900 in retry/guard helper 0x5479e4) → 0xd47c6c: finds 84A0DD62 pairs (0x591c64/0x591998), selects PHb via closure 0x592230, writeOp 0x591958 (NHb, yFb.write, param=Position), execute via 0xd30588 typed `<Fzb>` [pp+0x2a790].
- **Interval** (0xd482f0/0xd48360): SharedPreferences int `locationFreqNum` [pp+0x2a890] (default 0 when absent, 0xd483b4) → List<hBb>[high, normal, low] [pp+0x2a898] → timer seconds: high(0) → **5 s** (Smi #0xa), normal(1) → **30 s** (#0x3c), low(2) → **180 s** (#0x168). Log "start timer N seconds." (0xd4753c, [pp+0x27528]/[pp+0x27530]).
- Timer tick closure 0xd47664: fetches position via geolocator (0x592260, last position; log "write timer lastPosition: " [pp+0x27540]) and calls 0xd47794 → write. Position source in 0xd46f20: LocationSettings Gzb with accuracy Kzb.high [pp+0x274e8], timeLimit = N s ×1 000 000 µs (0xd47194) → 0x592354 (position request/stream) [inferred: geolocator API identity from field layout only].
- Preconditions checked in 0xd47794 (static providers lTi/IKi/JKi/YRi/isPaused) — [unknown] semantics; [inferred] GeoTag enabled (cGb) and camera connected.
- No model branch observed in the PHb path.

## AFb (svc 0F291746-0C80-4726-87A7-3C501FD3B4B6, char FE3A32F8-A189-42DE-A391-BC81AE4DAA76) — phone (client) device name
- op BFb 0x6c8 (writeOp factory 0x82e834: `{@7 dpb, @0xb yFb.write [pp+0x2a798], @0xf String}`), executed via 0xd30588 typed `<String>` [pp+0xc08] (0xda641c). Op execute 0xe5be3c (first in the descending-cid execute block, so highest op cid = BFb [inferred: block order]) supports write only (read → " command is not supported") → 0xe5bfb0: `utf8.encode(value)` (0xb58618, [pp+0x13a0]) → FBP write 0xe5c094 withResponse. Payload = raw UTF-8 bytes, no length/terminator. No read caller in app.
- Value = Android `Build.MODEL`: 0xda5fd4 → device_info_plus "getDeviceInfo" [pp+0xada0] (0xcf5ffc) → AndroidDeviceInfo (Jza) field @0xf = "model" [pp+0xab88] (0x4dc304..0x4dc9a4) → sanitizer 0x82ebc8:
  1. empty → "Unknown" [pp+0x9450]; 2. keep chars 0x20..0x7E and U+3000, replace others with "?" [pp+0x15d8]; 3. stop when buffer ≥ **32** chars (0x82ecf0); 4. trim (0xaa7418); empty → "Unknown"; if 0x47b414 yields empty → "_" [pp+0x50f0] [exact 0x47b414 semantics unknown].
- Then 0xda616c → closure 0x82e7dc → 0xda62d8: find 0F291746 pairs (0x82eb40/0x82e874), select AFb (0x82eb98), write name.
- When: pairing flow WOb 0xda58b0 (states NOb scanning/connected/success/error; errors OOb none/firmwareError/registerError/connectError/cancelError) calls 0xda5fd4 at 0xda5d50 after connect, unless the connect step threw zSb ER_BL_007 UnsupportedFirmwareVersionError [pp+0x2a3c8] (0xda5d30-0xda5d44) → /connectionCheck / /connectionExist / /connectionMissing routes (0xda6574). [inferred] Camera shows/stores this as the paired phone's name.

## Storage layout (dGb, read 0xe5f82c; list split 0x57ce2c; also used by notify parser JHb)
- byte0 = entry count N (int8, 0x57ce60). Remaining bytes must be exactly N×**14** (0x57ced4 `mul 0xe`), else RangeError "listLength: …, elementLength: …, totalBytes: …" (0x57d0d4).
- Per 14-byte entry (sublist(start,end) calls 0xe5f998..0xe5fe5c; model AHb 0xe5fee0):

| off | size | field | encoding |
|---|---|---|---|
| 0 | 1 | type (zHb) | 0 internalMemory, 1 sdSlot1, 2 sdSlot2 (0xe5fa24-0xe5fa54) |
| 1 | 1 | isExistence | ==1 → true |
| 2 | 1 | isLocked | ==1 |
| 3 | 1 | isAvailable | ==1 |
| 4 | 1 | isFormatted | ==1 |
| 5 | 4 | remainingPictures | int32 LE (ldrsw, no byte swap, 0xe5fda4) |
| 9 | 4 | remainingVideoSeconds | int32 LE (0xe5fe40) |
| 13 | 1 | fileType | int8 raw (0xe5fed8) [meaning unknown] |

(Field-name order = AHb store order @7..@0x2b matching StorageInformationModel toString order.)

## Flows
### Date/time sync
1. 0xd303b4: find WFb pairs (0x570654/0x56fed0), select XFb (closure 0x571348).
2. `DateTime.now()` (AllocateKa + _GCc 0xcf1680, isUtc=false → local time).
3. writeOp(XFb) → pGb; 0xe5d8cc builds `[year_lo, year_hi, month, day, hour, minute, second]` and writes withResponse (7 bytes, no TZ/weekday).
### GPS push
1. Location service starts (0xd46f20), reads `locationFreqNum` → 5/30/180 s periodic timer.
2. Each tick: get latest Position, write 32-byte PHb record (lat/lon/alt float64 BE, year int16 LE, mo/d/h/mi/s, datum 0) withResponse to 84A0DD62/28F59D60.
### Camera power off
- YFb write (0xe4b1c8) always passes constant **false** (0xe4b304 `add x3, x22, #0x30`) → payload `[0x00]`. Callers: power-off/disconnect flow 0xe49d2c (log "write camera power: " [pp+0x4dc88], also touches "lastConnectedDevice") and after FirmwareUpdateResult success 0xe85c70→0xe86104 ("cameraPowerOff Error" [pp+0x51ec8]). The app never writes `true` (power-on) [no other YFb write caller].
### Pairing name registration
- See AFb: after BLE connect in pairing, write sanitized phone model (≤32 printable ASCII) to FE3A32F8.
### Firmware update (BLE part)
- 0xdd5398 "_firmwareUpdate": write iGb=[0x01] (FirmwareUpdateStart), await FirmwareUpdateResult notify on jGb (error "step4_ble_notify_not_received" [pp+0x2ac18]); on success → camera power off ([0x00] on YFb).
### Other UI writes (variable param)
- geoTag cGb write 0xe47628 (caller 0x998d88), powerOffDuringTransfer fGb write 0xe45ba0 (caller 0x994dd8), cameraName gGb write 0xd4020c (caller 0xd401b4), operationMode bGb write 0xd40c54.

## Model notes
- Default camera name "MY GR IV" when gGb absent (0xd418e4) — WFb service is the GR IV-generation camera service [inferred].
- Model code byte (index 2 of a byte list, 0xda55a8; caller 0x82e404 — scan/adv data, BleConn slice) mapping in 0xda542c: 1/5 → "GR III / GR III HDF", 3/6 → "GR IIIx / GR IIIx HDF", 7/8 → "GR IV / GR IV HDF", 9 → "GR IV Monochrome / GR IVx"; a bool provider SCf [pp+0x20018] selects whether GR IV codes (7,8,9) or GR III codes (1,5,3,6) are accepted. Model list "GR III","GR IIIx","GR III HDF","GR IIIx HDF","GR IV","GR IV HDF","GR IV Monochrome","GR IVx" in 0xda6904.
- No model branch found inside WFb/PHb/AFb codecs themselves.

## Open questions (sniff to confirm)
- aGb operationModeList value semantics (bitmask of SFb?).
- kGb end-screen payload format; ZFb long form (byte1==1, ≥130 bytes) — which models.
- gradNd source (no characteristic read).
- Storage fileType values; confirm int32 LE for remaining counts.
- AFb: whether the camera requires the name write before bonding/registration completes, and how it uses it (display in paired-device list?).
- PHb: confirm float64 big-endian vs int16 little-endian mix; datum byte meaning; whether writes stop when geoTag (cGb) is off.
- Whether any path powers the camera on over BLE (app only writes cameraPower=0).
