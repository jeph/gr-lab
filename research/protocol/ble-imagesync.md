# GR camera BLE protocol: extensions from Image Sync 2.1.32 (static analysis)

Companion to [ble.md](ble.md) (GR WORLD 2.0.0). Ricoh's older **Image Sync** app supports remote shooting, exposure control and BLE wake on GR III/IIIx, so it documents characteristics GR WORLD never touches. Source: `com.ricohimaging.imagesync` 2.1.32 (versionCode 20132000, APK SHA-256 `00756f0c0474c7f6ac0271b817effadf15e92362d49eab9d86cd0d6bba639442`, signer `CN=RicohImaging`), jadx tree `work/imagesync-jadx`. Code paths below are relative to `work/imagesync-jadx/sources`. `SDK/` = `com/ricoh/camera/sdk/wireless/`. Resource paths are relative to `work/imagesync-jadx/resources/res/raw/`. No camera was contacted; **[inferred]** = reasoned from code, **[unknown]** = not settled statically. Image Sync does not recognise GR IV model codes (§3), so for GR IV everything here is a hypothesis to test, not app-observed behaviour.

## 0. Where the GATT map lives: encrypted YAML

The Java classes `Definitation`/`Service`/`Characteristic`/`ValueField`/`Enums`/`ManufacturerSpecificData`/`Format`/`Type` (`SDK/impl/ble/core/*.java`) are SnakeYAML beans with no constants. The GATT and advertising maps are loaded at runtime from two **encrypted** raw resources:

- `def_ble.yaml` (GATT map; loaded by `e.a("def_ble")`, `SDK/impl/ble/core/a.java:616`; the THETA alternative `def_ble_theta_v` is used only when `f605s` is true, and that resource is absent from the APK).
- `def_adv.yaml` (manufacturer-data map; `SDK/impl/ble/core/e.java:355-377`).
- Decryption: Base64 decode, then AES-128-CBC/PKCS5. The key and IV are the **hex strings** stored base64-encoded in `strings.xml:66-67` (`base64_iv`, `base64_shared_key`). Hex decoding: `a.a(String)` `SDK/impl/ble/core/a.java:1023-1033`. Cipher: `e.java:379-390`.
- Reproduce:
  ```sh
  # The key and IV are read from the APK's own resources (decoded with apktool
  # or jadx); they are Ricoh's, so they are not copied here.
  s() { sed -n "s:.*name=\"$1\">\([^<]*\)<.*:\1:p" res/values/strings.xml | base64 -d; }
  K=$(s base64_shared_key); IV=$(s base64_iv)
  base64 -d -i res/raw/def_ble.yaml | openssl enc -d -aes-128-cbc -K $K -iv $IV
  ```
  - Plaintext SHA-256: `def_ble` `906651181674ef23…a8cc40b` (1669 lines); `def_adv` `19d638bf6e1aec2c…02928d521` (33 lines).
  - Below, "def_ble L*n*" means line *n* of the decrypted plaintext.
- The per-model setting maps are **plain** YAML, not encrypted: `camera_ricoh_gr_iii{,x}{,_hdf}_ble.yaml` and `capture_ricoh_gr_iii{,x}{,_hdf}_ble.yaml`.
  - All four GR III-family files are byte-identical per kind (`diff` empty).
  - They are selected by `BleSupportSettingReader.java:161-170`.

## 1. Complete UUID table (from def_ble)

Formats: `sint8`/`uint8` = 1 byte; `sint16`/`uint16` = 2 bytes LE; `sint32` = 4 bytes LE; `float64` = 8 bytes **big-endian**; `utf8s` = raw bytes. Codec: `SDK/impl/ble/core/c.java:325-393` (encode) and `543-613` (decode).

- Multi-field characteristics are the fields concatenated in order with no separators (`c.java:244-280`).
- `type: list` = `[count sint8][count × element]` (`c.java:299-323`, `396-445`).
- **New** = not in our `ble.md`.
- Ops come from the YAML `property` lists. **IS use** = what Image Sync actually does.

### Device Information `180A` (def_ble L2-34)

| UUID | Name | Prop | Format |
|---|---|---|---|
| 2A29 | Manufacturer Name | R | utf8s |
| 2A24 | Model Number | R | utf8s |
| 2A25 | Serial Number | R | utf8s |
| 2A26 | Firmware Revision | R | utf8s |
| 2A28 | Software Revision | R | utf8s |

Image Sync never reads DIS. `setup()` reads the custom Camera Information characteristics instead (`SDK/impl/ImplCameraDeviceBleAdapter.java:552-580`).

### Camera Information Service `9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1` (L35-73)

All six characteristics are Read, utf8s, and identical to `ble.md`:

| UUID | Name |
|---|---|
| F5666A48-… | Manufacturer Name String |
| 35FE6272-… | Model Number String |
| 0D2FC4D5-… | Serial Number String |
| B4EB8905-… | Firmware Revision String |
| 6FE9D605-… | Bluetooth Device Name |
| 97E34DA2-… | Bluetooth MAC Address String |

IS reads Manufacturer, Model and Serial only if they are not already known, plus Firmware every time (`ImplCameraDeviceBleAdapter.java:555-580`). The field name `"Model  Number"` contains a double space (L48, `:563`).

### Shooting Service `9F00F387-8345-4BBC-8B92-B87B52E3091A` (L74-1353)

Our `ble.md` calls this service "Camera Control".

| UUID | Name | Prop | Wire format / enums | New? |
|---|---|---|---|---|
| **671466A5-5535-412E-AC4F-8B2F06AF2237** | Shooting Service Notification | R,N | variable: `[n sint8][include sint8][UUID 16B][changed value…]`. include: 0 not include, 1 include (L77-94) | **New** |
| **2AC97991-A78B-4CD4-9AE8-6E030E1D9EDB** | High Frequency Shooting Service Notification | R,N | same layout (L95-112) | **New** |
| **D3CE2AED-10FA-4648-833D-CD74C6F35905** | Shutter Speed | R,W,N | uint8 index. 0 = B/T mode ("撮影モードB、T"); 1 = 1/25000 … 6 = 1/8000 … 24 = 1/125 … 39 = 1/4 … 45 = 1" … 60 = 30" … 61 = 60". Half-steps 101-112; long exposures 121-164 (7" … 1200") (L113-354) | **New** |
| **3911F22D-9771-479D-B2B9-F729D9BAF9DC** | Aperture | R,W,N | sint8 index. 0 AUTO; 1 = F1.0 … 10 = 2.8 … 19 = 8.0 … 40 = 90; half/other stops 101-111, 121-124 (L355-473) | **New** |
| **206BD02C-78B2-42C4-820A-CF30E0963909** | ISO Sensitivity | R,W,N | **sint32 LE, the literal ISO value**; 0 = AUTO (L474-596). The encoder masks writes with `0x00FFFFFF` (`c.java:379-385`) | **New** |
| **30BCC8EB-725D-4048-A832-E76AE26A57E9** | Exposure Compensation | R,W,N | sint8: key = EV×3 for 1/3 steps (−24…+24 = −8.0…+8.0). Half steps: ±51…±58 = ±0.5…±7.5 (L597-733) | **New** |
| **2361F4FF-2C7E-4FC5-876B-F9B0EFBC06FD** | White Balance | R,W,N | sint8: 0 auto, 1 daylight, 2 shade, 3 cloudy, 4 incandescent, 6 daylight-fl, 7 daywhite-fl, 8 fluorescent (cool white), 9 bulb-fl (warm white), 10-12 colortemp1-3, 13-15 manual1-3, 16 CTE, 17 multi-pattern auto, 18-20 custom1-3 (L734-780) | **New** |
| B29E6DE3-1AEC-48C1-9D05-02CEA57CE664 | Drive Mode | R,W,N | uint8. 0-15 as in `ble.md`. 16-65 add PENTAX remote/continuous H/M/L/motion/DOF/mirror-up/star-stream modes (L781-919) | known |
| A3C51525-DE3E-4777-A1C2-699E28736FCF | Shooting Mode | R,W,N | **3 bytes**: `[mode uint8][user mode sint8][option sint8]`. mode: 0 P, 1 Av, 2 Tv, 3 M, 4 B, 5 BT, 6 T, 7 Auto, 8 TAv, 9 Sv, 10 X, 11-15 Movie P/Tv/Av/TAv/M, 16-18 AstroTracer(/T/BT), 19 SFP, 20 AstroTracerType3. user: 0 none, 1-5 U1-U5. option: 0 none, 1 hyper, 2 shift (L920-992) | ext. |
| **ED58217E-1839-43B2-BCD7-DC48C36AC0DE** | Metering mode | R,W,N | sint8: 0 spot, 1 center-weighted, 2 multi-segment, 3 highlight-weighted (L993-1007) | **New** |
| 78009238-AC3D-4370-9B6F-C9CE2F4E3CA8 | Capture Mode | R,W,N | sint8: 0 image, 2 video (L1008-1018). Image Sync **writes** it; GR WORLD only reads it | known |
| **95BFA8CA-4680-424D-B27C-AAC20D86E48B** | File Type | R,W,N | 4 bytes: `[file type: 0 JPEG,1 PEF,2 DNG,3 JPEG+PEF,4 JPEG+DNG][raw type: 0 PEF,1 DNG][card slot: 0 sd1,1 sd2][slot mode: 0 sequential,1 duplicate,2 RAW/JPEG split]` (L1019-1058) | **New** |
| **9838BB04-4ABB-4C12-AE22-626D02E3704B** | JPEG Size | R,W,N | sint8: 0-3 = L/M/S/XS super-fine, 4-7 fine, 8-11 economy (L1059-1089) | **New** |
| **404F6626-1294-407F-AB3D-DDC6B805B6BC** | Movie Configuration | R,W,N | sint8: 0 FHD60, 1 FHD30, 2 FHD24, 3 4K60, 4 4K30, 5 4K24 (L1090-1108). The 4K values belong to the shared PENTAX/GR enum; GR III/IV record Full HD only (Image Sync's GR III table lists FHD24/30/60; Ricoh's GR IV spec lists 1080 60p/30p/24p) | **New** |
| 559644B8-E0BC-4011-929B-5CF9199851E7 | Operation Request | W | 2 bytes `[OperationCode sint8: 0 NOP, 1 start shooting/recording, 2 stop][Parameter sint8: 0 no AF, 1 AF, 2 green-button function]` (L1109-1130) | known |
| **B355330D-4ADC-4434-A222-7B91404B4788** | Shutter Speed List | R,N | list of uint8 (L1131-1139) | **New** |
| **4866F4A9-2C83-457B-B393-B9535E1447E5** | Aperture List | R,N | list of sint8 | **New** |
| **9C83DF56-FD93-4639-8CA7-857BB7B3CA3D** | ISO Sensitivity List | R,N | list of **sint32** (4 bytes per element) | **New** |
| **01879798-28EE-4D97-92C9-FD249C88BBCC** | Exposure Compensation List | R,N | list of sint8 | **New** |
| **FB673486-2A76-41B8-88F7-F88552FE5745** | White Balance List | R,N | list of sint8 | **New** |
| **F4B6C78C-7873-43F0-9748-F4406185224D** | Drive Mode List | R,N | list of sint8 | **New** |
| **F3BFB222-C62B-4AAA-BB61-EF6486626CC8** | File Type List | R | list of sint8 | **New** |
| **89458F80-50A1-42C1-B031-1BC6082179C0** | Focus Mode | **R,N only** | 2 bytes `[focus mode: 0 MF,1 AF][focus setting: 0 MF,1 auto-area,2 select,3 pinpoint,4 tracking,5 continuous,6 snap,7 infinity,8 movie,9 auto-area(center),10 star AF]` (L1194-1229) | **New** |
| **CDFC734E-EA21-427D-A69F-C1A0F7F1E9A3** | Auto Focus Status | R,N | 2 bytes `[running: 0 stopped,1 running][in focus: 0 no,1 yes]` (L1230-1247) | **New** |
| B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA | Capture Status | R,N | **8 bytes** `[capturing][countdown: 0 none,1 self-timer,2 waiting for scheduled time][still: 0 other,1 continuous,2 bracket,3 multi-exp,4 interval,5 interval-composite][movie: 0 other,1 recording][Type3CaptureState: 0 idle,1 pre-capture,2 main capture][Type3PreCaptureResult: 0 ok,1 motion not detectable,2 exposure-time error][AstroTrackingTime uint16]` (L1248-1309) | ext. |
| **12D262BA-D8BF-44B0-8E85-C414A40230A9** | Shot Count | R,N | 2 bytes `[current sint8][total sint8]` (L1310-1317) | **New** |
| 009A8E70-B306-4451-B943-7F54392EB971 | Self Timer | W | **2 bytes** `[Countdown Cancel: 0 other,1 cancel][Remocon: 0 off,1 on]` (L1318-1335) | known |
| **F662DCD8-AC6E-4E02-A4B2-CE92CD44C7C3** | Shooting Mode List | R,N | list of sint8 | **New** |
| **31B28DAB-BD3C-4C27-AA08-F379BF737C1E** | Focus Setting List | R,N | list of sint8 | **New** |

### Camera Service `4B445988-CAA0-4DD3-941D-37B4F52ACA86` (L1354-1560)

Our `ble.md` calls this service "Camera State".

| UUID | Name | Prop | Wire format | New? |
|---|---|---|---|---|
| **FAA0AEAF-1654-4842-A139-F4E1C1E722AC** | Camera Service Notification | R,N | variable, same layout as 671466A5 | **New** |
| B58CE84C-0666-4DE9-BEC8-2D27B27B3211 | Camera Power | R,W,N | sint8: **0 off, 1 on, 2 sleep** (L1375-1387) | value 2 is new |
| 875FC41D-4980-434C-A653-FD4A4D4410C4 | Battery Level | R,N | 2 bytes `[level sint8][used: 0 battery, 1 AC adapter]` (L1388-1400) | byte1 differs |
| FA46BBDD-8A8F-4796-8CF3-AA58949B130A | Date Time | R,W | `[year sint16 LE][month][day][hours][minutes][seconds]` (L1401-1416) | known |
| 430B80A3-CC2E-4EC2-AACD-08610281FF38 | Operation Mode List | R,N | list of sint8 operation-mode values (L1417-1425). This answers the `ble.md` "operationModeList" question | semantics new |
| 1452335A-EC7F-4877-B8AB-0F72E18BB295 | Operation Mode | R,W,N | sint8: 0 Capture, 1 Playback, 2 BLE Startup, 3 Other, 4 PowerOffTransfer (L1426-1442) | known |
| A36AFDCF-6B67-4046-9BE7-28FB67DBC071 | GEO Tag | R,W,N | sint8 enable | known |
| A0C10148-8865-4470-9631-8F36D79A41A5 | Storage Information | R,N | list: `[N]` + N × **15-byte** entries `[type 0 int/1 sd1/2 sd2][exist][locked][available][formatted][remaining pictures sint32 LE][remaining video s sint32 LE][file type][Active: 1 = write target]` (L1449-1505) | +Active byte |
| D9AE1C06-447D-4DEA-8B7D-FC8B19C2CDAE | File Transfer List | R,N | `[not empty][changed]` | known |
| BD6725FC-5D16-496A-A48A-F784594C8ECB | Power Off During File Transfer | R,W,N | `[behavior: 0 abort transfer & power off, 1 power off after transfer][auto resize: 0 no, 1 yes]` (L1524-1541) | byte0 meaning clarified |
| **209F9869-8540-460E-97A6-5C3AC08F2C73** | Grad ND | R,N | sint8: 0 off, 1 normal, 2 reverse, 3-5 custom1-3 (L1542-1560) | **New** (GR WORLD's model has an unfed `gradNd` field) |

### GPS Control Command `84A0DD62-E8AA-4D0F-91DB-819B6724C69E`

| UUID | Name | Prop | Format |
|---|---|---|---|
| 28F59D60-8B8E-4FCD-A81F-61BDB46595A9 | GPS Information | R,W | 32 bytes `[lat f64 BE][lon f64 BE][alt f64 BE][year s16 LE][mo][d][h][mi][s][datum: 0 WGS84]` (L1564-1590). Same layout as `ble.md` |

### WLAN Control Command `F37F568F-9071-445D-A938-5441F2E82399`

| UUID | Name | Prop | Format | New? |
|---|---|---|---|---|
| 9111CDD0-9F01-45C4-A2D4-E09E8FB0424D | Network Type | R,W,N | sint8: 0 off, 1 AP | known |
| 90638E5A-E77D-409D-B550-78F7E1CA5AB4 | SSID | R,W | utf8s | known |
| 0F38279C-FE9E-461B-8596-81287E8C9A81 | Passphrase | R,W | utf8s | known |
| **51DE6EBC-0F22-4357-87E4-B1FA1D385AB8** | Channel | R,W | sint8: 0 auto, 1-11 = ch1-11 (L1617-1647) | **New** |

Image Sync has no wlanFreq, security or available5GHz characteristics. These are GR IV additions known only from GR WORLD.

### Bluetooth Control Command `0F291746-0C80-4726-87A7-3C501FD3B4B6`

Our `ble.md` calls this service "Client Registration".

| UUID | Name | Prop | Format | New? |
|---|---|---|---|---|
| **D8676C92-DC4E-4D9E-ACCE-B9E251DDCC0C** | BLE Enable Condition | R,W,N | sint8: **0 disable, 1 enable anytime, 2 enable power on** (L1651-1663) | **New** |
| FE3A32F8-A189-42DE-A391-BC81AE4DAA76 | Paired Device Name | W | utf8s (L1664-1669) | known; name confirmed |

### Diff vs `ble.md`

- **27 UUIDs in Image Sync are absent from our `ble.md`** (the bold rows above).
- 25 of them are exactly the "additional shared UUID-shaped constants" in the [firmware inventory](../firmware-protocol-inventory.md#gatt-uuid-inventory-versus-the-app). Image Sync supplies their real names, which match the RTTI candidates, plus their formats.
- The other two, Grad ND `209F9869` and WLAN Channel `51DE6EBC`, are not in that firmware table. A byte search of both `bled` binaries (canonical and byte-reversed forms) settles their scope: **51 of the 53 UUIDs in this document occur in both GR III and GR IV `bled`**; WLAN Channel occurs only in GR III (GR IV has wlanFreq instead); Grad ND occurs in neither and is a PENTAX K-3 III characteristic. Byte presence is not proof that GR IV registers or accepts a characteristic, but it makes the exposure, focus and aggregate-notification characteristics plausible GR IV targets.
- **GR WORLD-only UUIDs absent from Image Sync:**
  - Image Control custom 1-3 name/data (`30adb439`, `e799198f`, `df77dd09`, `3e0673e0`, `0936b04c`, `cd879e7a`)
  - cameraName `ef437870`
  - firmware update available/start/result (`e450ed9b`, `5f0a7ba9`, `39879aac`)
  - end-screen data `f759f4dd`
  - wlanFreq `C4B7DFC0`, security `63BC8463`, available5GHz `460828AC`

  All of these are GR IV-only in firmware (`firmware-protocol-inventory.md:286`).
- An "Auth Bluetooth Device" characteristic is referenced only by the THETA path (`a.java:113-134`, used only when `f605s`). It is not in `def_ble` and is never used for GR.

## 2. Camera power-on / wake from off — definitive answer

**Image Sync can wake a powered-off GR III/IIIx over BLE.** It does **not** write `01` to Camera Power. Its only power-on action is a plain LE GATT link-layer connection to the camera's powered-off advertiser, followed by waiting for the camera to drop the link and re-advertise as ON.

- The **only** Camera Power write in the app is `"off"` = `00`: `setPowerOffWhenOn` (`ImplCameraDeviceBleAdapter.java:483-501`, `cVarA.a("Camera Power","off")` at `:489`).
- Searches for any `"on"`/`"sleep"` write to Camera Power, or any write of Operation Mode (`1452335A`), found none. Image Sync **only reads** Operation Mode: `ImplCameraDeviceBleAdapter.java:1072,1093,1109,1129,1166,1187,1203,1223`, and `m/e6.java:55-64`.
- `BLE Startup`/`PowerOffTransfer` appear only as decode enums (`camera_ricoh_gr_iii_ble.yaml:88-96`; `SDK/api/setting/camera/OperationMode.java:9-10`).

### Off vs on detection

The app uses advertising **tag 03 "Camera Power"** in the manufacturer data, not the service UUID:

- `def_adv`: tag 03, 1 byte; `0x00 OFF`, `0x01 ON`.
- Parsed into `client.B`: `d.java:262-264`, then `a.java:760`.
- Off state → the app makes **no GATT connection**: it marks itself "connected" with `isPower=false` and starts `PowerOnWatcher` (`ImplCameraDeviceBleAdapter.java:1558-1568`).
- Scan filter: service UUIDs `9A5ED1C5…` OR `0F291746…` (`d.java:425-430`). This matches firmware: on-state `bled` advertises one service UUID; BT-only `sysmgrd` advertises `0F291746` with tag `03 = 00`.

### Sequence (from code)

The app entry point is `s/i.java:111-129`: BLE `connect()`, then `if (!isPower) setPower(true)`, tried **twice**. If both attempts fail, the app reports "Failed to power on Bluetooth device".

1. **Precondition:** `connect(true)` rescans for up to 10 s (`a.java:726-775`, `f601o=10000` at `:571`). The rescan picks the device by matching serial (adv tag 02) or by name, and the result reports `B="OFF"`. The adapter state becomes `isConnected=true`, `isPower=false`, `PowerOnWatcher` running.
2. `setPowerOnWhenOff` (`ImplCameraDeviceBleAdapter.java:503-550`):
   1. Set `isWaitingPowerChanged=true`.
   2. Call `client.b()` (`a.java:777-819`): `connectGatt(ctx, autoConnect=false, cb, TRANSPORT_LE=2)` (`:790`). It waits up to **10 s** (`l=10000`, `:568`) for state CONNECT.
   3. Because `f604r=true` (`:574`), CONNECT is set on the link-up callback itself, with **no service discovery, bonding, MTU or any write** (`a.java:266-271`).
3. Wait up to **30 s** (`WorkRequest.DEFAULT_BACKOFF_DELAY_MILLIS = 30000`, `androidx/work/WorkRequest.java:31`) for `isWaitingPowerChanged` to clear.
   - It is cleared only by the `disconnected()` callback (`ImplCameraDeviceBleAdapter.java:100-103`). That callback suppresses the "deviceDisconnected" event.
   - The design therefore expects **the camera to drop the link after the connect** **[inferred: the BT-only firmware boots the main system and restarts BLE]**.
   - If 30 s pass without a disconnect, the app logs a timeout and continues anyway (`:514-520`).
4. In parallel, `PowerOnWatcher` (`:260-323`) runs:
   - It loops every 500 ms. Every 20th iteration (about 10 s) it rescans (10 s scan) and refreshes `B` from adv tag 03.
   - More than 3 failed rescans → deviceDisconnected.
   - Once `B=="ON"`, it calls `connect(false)` (up to 4 attempts), which runs the full connect + bond + discover + setup ([§4.4](#44-connection-pairing-mtu-notifications-timeouts)). Success sets `isSetupForPowerOn=true` (`:1600`).
5. `setPowerOnWhenOff` then waits for `isSetupForPowerOn` and `isPower`. **Both waits share the same 30 s deadline**, started after the GATT connect (`:513`, `:522-546`). It fails early if the watcher thread dies.

### Timing implications for our client

- With the watcher cadence, ON is first noticed about 10–20 s after the wake connect. The 30 s total budget is tight; the app's second `setPower(true)` call is effectively a retry.
- Our client can do better by scanning continuously for tag `03 = 01` from the same address/serial.

### Power off

1. Write `00` to `B58CE84C` (response required; see [§4.4](#44-connection-pairing-mtu-notifications-timeouts)).
2. Set state OFF and start `PowerOnWatcher` (`:483-501`).
3. GR WORLD instead waits 6 s before reconnecting. Image Sync has no such guard; its watcher's first rescan happens at about 10 s anyway.

### Related settings

**BLE Enable Condition `D8676C92`** (0 disable / 1 anytime / 2 power-on only): the app reads it and connects BLE in the background only when the value is 1 or 2 (`m/c6.java:40-44`, `m/d3.java:542-543`). **[inferred]** Waking from off needs value 1 ("enable anytime"); with 2 the camera presumably does not advertise when off. The app never writes this value: there are no `BLEEnableCondition.X` writes outside the converter's available-settings list (`BleCameraSettingConverter.java:236-240`).

### Unexpected disconnect

On a link drop that was not deliberate, the app rescans for 10 s. If **any** advert for the device is found, it treats the camera as **OFF** and starts the watcher (`ImplCameraDeviceBleAdapter.java:109-124`). Otherwise it emits deviceDisconnected.

## 3. Manufacturer data (`def_adv`) vs `camera-models.md` §4.1

`def_adv`: `companyId: 0x065F`, marker (format value) `0xDA`.

| Tag | Name | Length | Enum / encoding |
|---|---|---|---|
| `01` | Model Code | 1 | 0x00 PENTAX K-3 Mark III, 0x01 RICOH GR III, 0x02 PENTAX K-3 Mark III, 0x03 RICOH GR IIIx, 0x04 PENTAX K-3 Mark III Monochrome, 0x05 RICOH GR III HDF, 0x06 RICOH GR IIIx HDF |
| `02` | Serial Number | 4 | uint32 LE, rendered `%07d` (`d.java:316-317`) |
| `03` | **Camera Power** | 1 | **0x00 OFF, 0x01 ON** |

Parser `d.java:286-334`:

1. `getManufacturerSpecificData(0x065F)` (company ID **is** checked, unlike GR WORLD).
2. Byte 0 must equal `0xDA`.
3. Loop: read a tag byte, look up its fixed length, then read the value.

Behaviour that matters:

- **An unknown enum value makes the whole map empty** (`:321-322`), so the device is dropped. Consequently:
  - **GR IV codes 7–10 are not recognised**: Image Sync 2.1.32 cannot discover any GR IV over BLE.
  - The connect path also hard-gates on `SUPPORT_CAMERA` (GR III, GR III HDF, GR IIIx, GR IIIx HDF, K-3 III, K-3 III Mono): `ImplCameraDeviceBleAdapter.java:325-333`, `ImplCameraDevice.java:141-143`.
- An unknown tag byte is consumed and then ignored, with no resync (`:298-327`).
- A device is listed only if tag 03 was present (`d.java:262-265`).
- Additional scan gates:
  - Local name must start with "GR" or "PENTAX" (`BleCameraDeviceDetector.java:22-27`, `d.java:178-198`).
  - Service filter as in §2.
  - `ScanSettings.setScanMode(1)` = **BALANCED** (`d.java:424`). GR WORLD uses LOW_LATENCY.
- Matching our firmware layout: tag `03` = `!bool` in `bled` and `00` in BT-only `sysmgrd`. This **resolves "tag 03 [unknown]" in `camera-models.md`: tag 03 = camera power, 1 = on (main firmware), 0 = off (BT-only)**.
- The `0x00` code for K-3 III does not conflict with the firmware table for GR models.

## 4. Adapter, converters, settings — wire behaviour

### 4.1 Generic codec (`c.java`)

- Integers are little-endian. Writes truncate `sint8` with `&0xFF` and `sint16` with `&0xFFFF`. **`sint32` is masked with `0x00FFFFFF`**, so the top byte is always 0 (`c.java:365-385`).
- `float64` is big-endian (`:386-387`, `:580-581`).
- `utf8s` decode stops counting at NUL bytes: it counts non-zero bytes (`:583-590`). Encode is raw UTF-8 with no terminator (`:389-390`).
- Values are set by enum string and mapped to keys. A non-enum string goes through `Integer.valueOf`.
- An **empty string encodes as 0** (`:329-331`).

### 4.2 Aggregated notifications (Shooting / High-Frequency Shooting / Camera Service Notification)

- Layout: `[count][include][16-byte UUID][value of that characteristic]`.
- The adapter takes the first UUID (field index 2), maps it to a characteristic name (`c.f625h`), and decodes the remaining bytes as that characteristic (`ImplCameraDeviceBleAdapter.java:156-183`; `c.java:169-223`).
- **UUID byte order in these notifications** (`c.java:597-612`):
  - Bytes are read as groups `[0..5]`, `[6..7]`, `[8..9]`, `[10..11]`, `[12..15]` and printed in **reverse group order**, with bytes inside each group in wire order.
  - So wire = `node(6) | clock_seq(2) | time_hi(2) | time_mid(2) | time_low(4)`, each group big-endian. Example: `CD74C6F35905 833D 4648 10FA D3CE2AED` for Shutter Speed.
  - This is **not** the usual fully byte-reversed BLE UUID. **[inferred from parser; unconfirmed on wire]**
- Only the first entry is processed, even if `count > 1`.

### 4.3 Subscriptions

Image Sync enables CCCD notify (`01 00`, `ENABLE_NOTIFICATION_VALUE`) on **exactly six** characteristics (`a.java:605-612`), one at a time, chained through `onDescriptorWrite` (`a.java:136-174`, `301-363`):

1. Shooting Service Notification
2. High Frequency Shooting Service Notification
3. Camera Service Notification
4. Network Type
5. BLE Enable Condition
6. ISO Sensitivity List

All other state arrives through the three aggregators: power, battery, storage, transfer list, capture status, settings, shot count (`ImplCameraDeviceBleAdapter.java:185-254`). There is **no priming read after subscribe**; `setup()` does explicit reads instead.

**GR WORLD instead subscribes directly** to power, battery, GeoTag, storage, file-transfer list, power-off-transfer, capture mode, capture status, drive mode and shooting mode (`ble.md:266-280`).

### 4.4 Connection, pairing, MTU, notifications, timeouts

Sources: `a.java` and `ImplCameraDeviceBleAdapter.connect(boolean)` (`:1547-1611`).

**Connect sequence:**
1. Sleep 60 ms.
2. `connectGatt(autoConnect=false, TRANSPORT_LE)`; connect timeout **10 s**, then `gatt.close()` on timeout.
3. **Pairing** `client.i()` (`a.java:673-724`):
   - If bond state is NONE(10): `createBond()`, then wait for BONDED(12) up to **45 s** (`f602p`). Fail if disconnected meanwhile.
   - Already bonded: skip.
4. **Service discovery** runs only after bonding, posted **600 ms** later on the main looper (`a.java:845-876`); the wait is up to 45 s.
5. Only characteristics whose UUID is in `def_ble` are registered (`a.java:386-430`; `f603q=true` for scanned devices, so unknown ones are also registered by UUID).
6. **`requestMtu(512)` immediately after discovery** (`:431`). Notification setup starts in `onMtuChanged` (`:366-383`).
7. Sleep 500 ms, wait up to 30 s for the characteristic list, sleep 500 ms.
8. `setup()` reads, in order: Manufacturer/Model/Serial (if unknown), Firmware Revision, Battery Level, Storage Information, Capture Status, Camera Power, File Transfer List (`:552-609`).
9. Pairing failure → error `INVALID_SETTING "failure paring"` (`:1574-1578`).

**GATT operations:**
- Every read and write runs on a single-thread executor, so only one op is in flight (`a.java:878-901`, `996-1013`).
- Each op polls for completion every 100 ms. Timeouts: **read 5 s, write 5 s** (`f599m`, `f600n`, `:569-570`).
- **No retries** at the GATT layer.
- Writes use `writeCharacteristic` without `setWriteType`, i.e. the Android default = **Write Request (with response)** unless the characteristic only supports no-response. There are no `setWriteType` calls in the tree.
- There is no connection-priority/PHY call and no GATT cache refresh.

**Other:**
- `disconnectAlreadyConnectedDevice` (`d.java:154-175`) does a connect-then-disconnect on bonded GR/PENTAX devices that are not in the current scan. It is exposed in the API, but no app caller was found.
- Image Sync tears BLE down when Wi-Fi connects, and drops Wi-Fi when BLE connects (`ImplCameraDevice.java:122-160`).

### 4.5 Shutter / capture (Operation Request `559644B8`, Self Timer `009A8E70`)

| Action | Bytes | Citation |
|---|---|---|
| startCapture(AF) | `01 01` | `ImplCameraDeviceBleAdapter.java:1476-1484` |
| startCapture(no AF) | `01 00` | same |
| stopCapture (movie / continuous / interval / T) | `01 00` — the "start" code again, i.e. a toggle; code 2 "stop" is never used | `:858-868`, `:1523-1531` |
| focus() (AF only) | `00 01` (NOP + AF) | `:1010-1027` |
| applyGreenButton | `00 02` | `:955-974` |
| cancel countdown | `01 01` on Self Timer (cancel = 1, remocon = on) | `:368-378`, `:1515-1517` |

- Preconditions: connected, `isPower`, not counting down, not recording.
- Multi-exposure drive modes throw Unsupported (`:341-343`, `:1463`).
- Completion is tracked from Capture Status (`:870-952`).
- **GR WORLD sends Self Timer as 1 byte `01`.** Image Sync sends 2 bytes `01 01`.

### 4.6 Settings read/write

Capture settings: `BleCaptureSettingConverter` + `capture_ricoh_gr_iii_ble.yaml`. Camera settings: `BleCameraSettingConverter` + `camera_ricoh_gr_iii_ble.yaml`.

- **Write procedure:** each write sets the mapped fields on the cached last-read value and writes the whole characteristic (`ImplCameraDeviceBleAdapter.java:1384-1405`, `:1421-1428`). Multi-byte characteristics are read-modify-write from the cache; the app does not re-read first.
- **GR III exposure writes:** ISO, Shutter Speed, FNumber (Aperture), Exposure Compensation, White Balance, ExposureProgram (Shooting Mode byte0), UserExposureProgram (byte1), StillImageCaptureFormat (File Type byte0), MovieCaptureFormat (FHD24/30/60), Metering, CaptureMode (`image`/`video`).
- **Drive mode (CaptureMethod)** writes two characteristics in order: Drive Mode, then Capture Mode (`BleCaptureSettingConverter.java:299-373`).
  - STILL_IMAGE → Drive `00`, Capture Mode `00`.
  - MOVIE → Drive `00`, Capture Mode `02`.
  - Any other method → Drive enum value, Capture Mode `00`.
- **Quirks [inferred]:**
  - JPEG Size: the YAML maps names to `L`/`M`/`S`/`XS`, but the `def_ble` enums are `"L / スーパーファイン"` etc. Neither reading nor writing it can work for GR III.
  - FocusSetting is mapped to "Focus Mode" with field0 `""`. A write would send `[00][setting]` to a characteristic declared R,N only.
  - Writing AutoResize sends Behavior = `""`, which encodes to 0, so it overwrites "power off after transfer". GR WORLD instead writes `[current0, new]`.
- **Date/time:** write CameraTime(now) as 7 bytes in **phone local time** (`BleCameraSettingConverter.java:455-464`). Triggers:
  - A 60 s timer while the preference `p.a.f1734v` is on and the camera is powered and in Operation Mode **Capture**. It is cancelled after the first success (`SvApplication.java:113-133`, `m/e6.java:26-75`, `SvApplication.java:169-172`).
  - A manual path (`m/y2.java:27`).
- **GPS:** 32-byte record. The **timestamp is the fix time converted to UTC** (`BleCameraSettingConverter.java:482-495`), which answers the `ble.md` open question 13 for Image Sync. Push logic (`m/a2.java:42-94`):
  - A Timer every **2 s** (initial delay 1 s, `m/b2.java:56`) writes only when GEO Tag reads true and a new fix is pending (`f1347i`).
  - Otherwise a 600 s handler is armed.
  - Model gate: K-3 III, plus GR III family **[inferred: the decompiled empty `switch` at `a2.java:62-65` mirrors `s/g.java:247-262`, ordinals 3, 4, 10-13]**.
- **WLAN on/off** (Network Type `9111CDD0`, `AP`=`01` / `off`=`00`):
  - Before Wi-Fi, for GR III family models, the app reads Capture Method and Operation Mode. It skips WLAN-on if the camera is in movie + Capture mode, then writes `01` only if the current value is not AP (`s/i.java:56-97`; same in `s/e.java:99-150`, `m/k2.java:112-159`).
  - The manual toggle writes `00` after reconnecting BLE, or `01` and then joins Wi-Fi (`m/k3.java:29-50`).
  - App to background: if the camera is bonded, connect BLE when BLE Enable Condition is 1 or 2, then write WLAN `00` and disconnect Wi-Fi (`m/c6.java:38-53`).
  - Foreground: write WLAN `01` (`SvApplication.java:260-266`).
  - Image Sync reads SSID, Passphrase and Channel (`s/i.java:142-158`) and stores them with security type "WPA".
- **Phone name:** after connect and power-on, the app writes `Build.MODEL` raw (no sanitising) to `FE3A32F8` (`s/i.java:169`, `BleCameraSettingConverter.java:475-477`). This happens **after** bonding; GR WORLD writes it before bonding.
- **Storage:** for GR III-family models, a **29-byte** read (1 + 2×14) is padded to 31 bytes by inserting `00` Active bytes, so GR III sends 14-byte entries without the Active byte (`ImplCameraDeviceBleAdapter.java:717-738`). The notify path does not pad (`:217-220`) **[inferred mis-parse]**.

## 5. Differences from GR WORLD that matter for our client

1. **Power-on is possible.** Wake = plain LE connect to the OFF advertiser (adv tag 03 = 00), no writes. Then wait for the link drop and rescan until tag 03 = 01, and do a full connect. The power-off write is unchanged (`00`). Never write `01`/`02` to Camera Power; the app never does.
2. **Power state source:** use manufacturer tag `03` (1 on / 0 off). GR WORLD infers the state from the advertised service UUID; both are consistent with firmware. Camera Power characteristic value `02` = "sleep" also exists.
3. **27 extra characteristics with full encodings:** exposure (shutter, aperture, ISO sint32, EV, WB, metering), file type, JPEG size, movie configuration, focus, AF status, shot count, lists, Grad ND, WLAN Channel, BLE Enable Condition, plus three aggregate notification characteristics. Exposure control over BLE is therefore available on GR III/IIIx without Wi-Fi.
4. **Notification model:** Image Sync subscribes to 3 aggregators plus 3 direct characteristics (6 in total); GR WORLD subscribes to about 10 characteristics directly. The unusual UUID group order in the aggregator payload must be confirmed on the wire.
5. **Payload length differences:**

   | Characteristic | Image Sync | GR WORLD |
   |---|---|---|
   | Self Timer | 2 B (`01 01`) | 1 B |
   | Shooting Mode | 3 B | 2 B |
   | Capture Status | 8 B | 2 B read |
   | Battery byte1 | power source | long-form end-screen flag |
   | Storage entries | 15 B with Active; GR III sends 14 | 14 B |

6. **Link parameters:**

   | Parameter | Image Sync | GR WORLD |
   |---|---|---|
   | Connect timeout | 10 s | 35 s |
   | Bond timeout | 45 s | 90 s |
   | MTU 512 request | right after discovery | 350 ms delay |
   | Discovery | after bonding, +600 ms | — |
   | Read/write timeout | 5 s each | — |
   | GATT retries | none | 3 × 50 ms |
   | Scan mode | BALANCED | LOW_LATENCY |
   | Name-prefix filter | "GR"/"PENTAX" | — |
   | Company-ID check | yes | no |

7. **Model coverage:** Image Sync 2.1.32 BLE supports only GR III/IIIx (+HDF) and K-3 III (+Mono). Unknown model codes (GR IV 7–10) make the advert unparseable. For GR IV, GR WORLD remains the only reference for wlanFreq/security/cameraName/firmware characteristics.
8. **GPS time is UTC in Image Sync**; GR WORLD's timezone is unknown. Date Time is local in both.
