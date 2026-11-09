# GR camera models: firmware identity, support scope and model identification

Scope: which GR bodies a third-party client can target, which official firmware packages are byte-identical, and how a client tells the models apart. Sources are the official Ricoh firmware packages (downloaded again on 2026-11-07), REA/Ghidra decompilation of the extracted Linux userspace, and the GR WORLD 2.0.0 disassembly. No camera was contacted. Labels: **[inferred]** = reasoned from code; **[unknown]** = not settled statically.

## 1. Summary for implementers

- **One protocol family, three firmware images.** GR III/III HDF, GR IIIx/IIIx HDF and GR IV/IV HDF/IV Monochrome all use BLE + Wi-Fi HTTP (`bled`, `webapid`, `netmgrd`). GR II is Wi-Fi-only on an older platform. The original GR (2013) has no wireless interface.
- **GR IV, GR IV HDF and GR IV Monochrome run one byte-identical firmware file.** GR III and GR IIIx ship different packages, but their Linux/INITFS partitions (where the BLE and HTTP servers live) are byte-identical; only the RTOS (camera core) differs.
- **Identify the model from the BLE scan response before connecting**: manufacturer data for company `0x065F` (Ricoh), marker `0xDA`, then tag `01` followed by the 1-byte model code. After connecting, read the Camera Information model-name characteristic or `GET /v1/props` → `model`. Do not use the firmware package or SSID to infer the model.
- **Key compatibility by model + firmware version, not by firmware file.** The same GR IV image is published as GR IV v1.20 and GR IV Monochrome v1.10.
- **USB is import-only on every III/IV body.** GR WORLD has no wired mode. Over USB the camera is a read-only PTP device (VID `0x25FB`, per-body PID, §4.4), and Wi-Fi is refused while USB is connected. See [USB](protocol/usb.md).

## 2. Official firmware packages and byte identity

All six packages were downloaded again from Ricoh's official pages on 2026-11-07. The four current ZIPs were byte-identical to the copies analyzed earlier in `firmware/zips/`, so only the GR II and GR packages were added there (`rg2_v003.zip`, `rg1_v051.zip`, extracted beside them).

| Model(s) | Official page | Version label | ZIP SHA-256 | Inner file | Inner file SHA-256 |
|---|---|---|---|---|---|
| GR IV, GR IV HDF | [gr4_s](https://www.ricoh-imaging.co.jp/english/support/digital/gr4_s.html) | 1.20 | `dcc1b6fb004f0d855bb46b30a529da894c7b717501276fec2d198b3d7eb76a59` | `fwdc248b.bin` (38,919,904 B, CRC `c4cc7d2c`) | `7563d7e462f0c53b6ab2fbab7cdfbbb57151a41192ee82f4f3a2108f9d77650d` |
| GR IV Monochrome | [gr-4-mono_s](https://www.ricoh-imaging.co.jp/english/support/digital/gr-4-mono_s.html) | 1.10 | `bde05b3bf56a29c272284556d6795cb772eaccbbd0091d433fd52368d4d8af12` | `fwdc248b.bin` (same size/CRC) | **identical:** `7563d7e4…77650d` |
| GR III, GR III HDF | [gr3_s](https://www.ricoh-imaging.co.jp/english/support/digital/gr3_s.html) | 2.20 | `7b19f9c03f2448c2b674fb919f6a86d22d6d83801521a9c1226a0e20cf0b5a2f` | `fwdc239b.bin` | `5c53760b3b564c87239dbf7f5c94d0f6fd91accd156ec4ba672ebfd6b861793e` |
| GR IIIx, GR IIIx HDF | [gr3x_s](https://www.ricoh-imaging.co.jp/english/support/digital/gr3x_s.html) | 1.70 | `6a028e90b4f23c9e9af968b03bca5032b71f460be85fd2c49f4078366a71dc6d` | `fwdc243b.bin` | `aa8e3ae1349d94e83be381c20530e41d5e57b75c27ef24ba81c7b017d6c11592` |
| GR II | [gr2_s](https://www.ricoh-imaging.co.jp/english/support/digital/gr2_s.html) | 3.00 | `76d28c8e48c37123f226b8aa6d236e23655146bc08070738d9e734290ea6b13d` | `rg2_v003/rg2_v003.frm` | `3643850f2ae74ae967eb336794048f554caa1b11d05b8569824d5719f1838331` |
| GR (2013) | [gr_s](https://www.ricoh-imaging.co.jp/english/support/digital/gr_s.html) | 5.01 | `a9f41575b8817c27fdfd5d86d2079a7ef8a00fa8319a1239cac18fac21f9cfb4` | `rg1_v051.frm` | `12b503a831d58d031500e24518624d89dcdec965eae52d7699b73040084f38ca` |

The HDF variants have no separate download: Ricoh's pages name "GR III / GR III HDF", "GR IIIx / GR IIIx HDF" and "GR IV / GR IV HDF" on one package each.

Byte-identical groups:

| Group | What is identical | Consequence |
|---|---|---|
| GR IV = GR IV HDF = GR IV Monochrome | Whole firmware file (`7563d7e4…`). Both ZIPs hold the same member with the same DOS timestamp (2026-09-08 15:39:20); only the ZIP container hash differs. | One codebase for three bodies. Everything in the protocol docs that cites GR IV evidence applies to HDF and Monochrome byte-for-byte. Runtime differences come only from the model property the hardware reports. |
| GR III ≈ GR IIIx (incl. HDF) | Linux kernel (`4857386b…`) and INITFS (`6fb072ce…`) partitions. INITFS contains `bled`, `webapid`, `netmgrd`, `sysmgrd`. | The BLE GATT server, HTTP API and Wi-Fi manager are the same binaries on all four III-family bodies. RTOS (`fb13f9b4…` vs `3d97f0f5…`) and outer file differ, so camera-core behavior behind those servers can differ. |
| GR III family vs GR IV family | Nothing byte-identical. | Same protocol family; GR IV adds characteristics and HTTP routes (see [firmware inventory](firmware-protocol-inventory.md)). |
| GR II, GR | Different platform (`.frm`); no readable strings, so not analyzed. | GR II is supported by GR WORLD over Wi-Fi only (minimum firmware 3.00, app table `0x54b6c0`). GR has no Wi-Fi/BLE. |

Firmware header (offsets in the outer `fwdc*.bin`; the same 0x80-byte header starts `rtos.bin` at `0x2000`): bytes `0x00` "RICOH", `0x08` model family ("GR III", "GR IIIx", "GR IV"), `0x30` uint16 LE product ID, `0x38` version as `major, minor` bytes. GR III: product `0x024C`, `02 14` = 2.20. GR IIIx: `0x0261`, `01 46` = 1.70. GR IV: `0x027C`, `01 14` = 1.20.

Only the GR IV RTOS adds a per-model table of 0x80-byte records after the header (`rtos.bin` offsets; product ID, version, name at `+0x1c`):

| Offset | Product ID | Version | Name |
|---|---|---|---|
| `0x2080` | `0x027C` | 1.20 | `GR IV` |
| `0x2100` | `0x0289` | **1.10** | `GR IV Monochrome` |
| `0x2180` | `0x028A` | 1.20 | `GR IV HDF` |

This explains why Ricoh can publish one image under two version labels: it carries a separate version for Monochrome. **[inferred]** A Monochrome body reports 1.10 and GR IV/IV HDF report 1.20 after installing it; the selection code was not traced. These product IDs are distinct per body but are **not** the USB product IDs (see §4.4). There is no `GR IVx` record in this table. Do not try to identify a camera from a firmware package.

## 3. Support matrix

| Body | Transport | BLE model code | Firmware image | GR WORLD 2.0.0 behavior | Target for our client |
|---|---|---|---|---|---|
| GR IV | BLE + Wi-Fi | 7 | `fwdc248b.bin` | supported (min "0.00") | yes, primary (most evidence) |
| GR IV HDF | BLE + Wi-Fi | 8 | same file | supported | yes, same code path as GR IV |
| GR IV Monochrome | BLE + Wi-Fi | 9 | same file | accepted by scan; app's firmware gate compares the model string with `==` against "GR IV"/"GR IIIx"/"GR III"/"GR II" ([BLE §Camera models](protocol/ble.md#camera-models)) | yes; verify the reported model/version strings on hardware |
| GR IIIx | BLE + Wi-Fi | 3 | `fwdc243b.bin` | supported, min 1.50 | yes |
| GR IIIx HDF | BLE + Wi-Fi | 6 | same file | supported | yes |
| GR III | BLE + Wi-Fi | 1 | `fwdc239b.bin` | supported, min 2.00 | yes |
| GR III HDF | BLE + Wi-Fi | 5 | same file | supported | yes |
| GR II | Wi-Fi only (no BLE) | — | `rg2_v003.frm` | supported, min 3.00, Wi-Fi registration flow | possible; separate code path (WebSocket change events, `/v1/params/device` Wi-Fi settings, `key` fix-up). Untested, firmware not analyzed |
| GR (2013) | none | — | `rg1_v051.frm` | not supported | not wirelessly |
| "GR IVx" (not announced) | BLE + Wi-Fi in firmware | 10 | strings in `fwdc248b.bin` | **rejected**: app scan only accepts 7, 8, 9 in the GR IV family | accept code 10 behind a flag only if the product ships |

Codes 2 and 4 are `PENTAX K-3 Mark III` and `PENTAX K-3 Mark III Monochrome`: the same `bled` model table also covers those Pentax bodies. They are outside this project. (Image Sync's advertising map additionally lists code `0` as K-3 Mark III.)

**Image Sync 2.1.32 coverage** (the reference for live view, HTTP shooting, exposure and BLE wake): GR II and the four GR III/IIIx bodies only. Its BLE advertising map stops at code 6, so a GR IV advert fails to parse, and its Wi-Fi support list rejects any `/v1/props` model not in that list ([remote shooting §5](protocol/remote-shooting.md#5-per-model-behavior-implcameradevicewifiadapterfactorycreateoption-273-457), [Image Sync BLE §3](protocol/ble-imagesync.md#3-manufacturer-data-def_adv-vs-camera-modelsmd-41)). Remote-shooting features on GR IV therefore rest on firmware evidence plus extrapolation and need the hardware tests in [hardware validation](hardware-validation.md).

## 4. Identifying the model

### 4.1 Before connecting: BLE advertising (recommended)

Source: `ble_server::BleServer::SetAdvertData(bool)` in `bled` (GR IV linked `0x36ac4`, provider `0x46ac4`; GR III `0x48f20`) and `sysmgr::load_bt_only_fw::setAdvertData()` in GR IV `sysmgrd` (provider `0x2dd64`) for the powered-off "BT-only" mode.

Advertising data (31-byte primary packet), as built by the firmware:

| AD | Bytes | Meaning |
|---|---|---|
| Flags | `02 01 06` | LE General Discoverable, BR/EDR not supported |
| 128-bit service UUIDs (type `0x06`, incomplete list) | `11 06` + 16 bytes reversed | One service UUID, selected by the `bool` argument. The BT-only `sysmgrd` path hard-codes `0F291746-0C80-4726-87A7-3C501FD3B4B6` (Client Registration). The app treats `9A5ED1C5-…` as "on" and `0F291746-…` as "off" ([BLE §Identifying a camera](protocol/ble.md#identifying-a-camera-in-the-scan)). Which `bled` service object sits at each of the two offsets is **[unknown]**. |
| TX power | `02 0A xx` | `00` in BT-only; GR III `bled` reads the controller TX power |

Scan response (needs an active scan; Android/iOS/macOS/Windows scanners request it by default in active mode):

| AD | Bytes | Meaning |
|---|---|---|
| Complete local name | `len 09 <bdName>` | BLE device name (property 0x17) |
| Manufacturer specific | `len FF 5F 06 DA 01 <model> 02 <s0 s1 s2 s3> 03 <power>` | Company ID `0x065F` little-endian = **Ricoh Company Ltd** ([Bluetooth SIG registry](https://bitbucket.org/bluetooth-SIG/public/raw/main/assigned_numbers/company_identifiers/company_identifiers.yaml)). Then a marker byte `0xDA` and tag/value pairs with **fixed, tag-implied widths and no length bytes**: `01` model code (1 byte); `02` serial number as uint32 little-endian (digits extracted from the serial-number string, parsed with `stoi`; 0 on parse failure); `03` **camera power**, `01` = on, `00` = off: `!bool` in `bled`, `00` in BT-only `sysmgrd`. The tag-03 meaning comes from Image Sync's encrypted advertising map `def_adv.yaml` (`Camera Power`: `0x00 OFF`, `0x01 ON`; [Image Sync BLE §3](protocol/ble-imagesync.md#3-manufacturer-data-def_adv-vs-camera-modelsmd-41)). Total payload after the company ID: 10 bytes. |

Model-code table (string compared against model property 2, exact match):

| Code | Model property string | Present in |
|---|---|---|
| 0 | anything else (logs `unknown modelName`) | both |
| 1 | `RICOH GR III` | GR III & GR IV `bled` |
| 2 | `PENTAX K-3 Mark III` | GR III & GR IV `bled` |
| 3 | `RICOH GR IIIx` | GR III & GR IV `bled` |
| 4 | `PENTAX K-3 Mark III Monochrome` | GR III & GR IV `bled` |
| 5 | `RICOH GR III HDF` | GR III & GR IV `bled` |
| 6 | `RICOH GR IIIx HDF` | GR III & GR IV `bled` |
| 7 | `RICOH GR IV` | GR IV `bled`, GR IV `sysmgrd` BT-only |
| 8 | `RICOH GR IV HDF` | GR IV `bled`, `sysmgrd` |
| 9 | `RICOH GR IV Monochrome` | GR IV `bled`, `sysmgrd` |
| 10 | `RICOH GR IVx` | GR IV `bled`, `sysmgrd` |

The GR IV firmware also contains RTOS strings `GR IVx`, `GR IVx HDF`, `GR4x_HDF`, `GR4_HDF`, `MY GR IV Monochrome`, `MY GR IV HDF`. Only the ten codes above are produced by the advertising code.

Parsing rule for our client: require company ID `0x065F`, `payload[0] == 0xDA` and `payload[1] == 0x01`, then read the model code from `payload[2]`. Read the serial from `payload[4..8]` only if `payload[3] == 0x02` and those four bytes are present; read the tag-`03` flag from `payload[9]` only if `payload[8] == 0x03`. The format has no length fields, so an unknown tag cannot be skipped: stop parsing at the first unexpected tag or short payload, keep what was already decoded, and store the raw payload for diagnostics. Never reinterpret later bytes as a model or serial. GR WORLD only reads `payload[2]` with no company-ID check (`0xda542c`). Its log labels code 9 "RICOH GR IV Monochrome / RICOH GR IVx" ([pp+0x36038]); the firmware assigns GR IVx code 10, so that label is the app's, not the camera's.

The serial in tag `02` lets the client match an advertising camera to a stored pairing without connecting, and to check `/v1/props` `serialNo` after joining Wi-Fi.

### 4.2 After BLE connect: Camera Information service

`CameraInformation::ModelName::Read` returns model property 2 as a raw string (GR IV fallback on read failure: `RICOH GR IV`; GR III fallback: `RICOH GR`). Characteristic `35FE6272-6AA5-44D9-88E1-F09427F51A71` under service `9A5ED1C5-…`. Serial number (property 3) and firmware version (property 5) come from the same loader (`BleServer::CreateServer`, provider `0x473fc`). Expected values are the strings in the code table above **[inferred]**: the advertising code compares the same property against them.

The app's model/firmware gate reads Device Information (`180A`) `2A24`/`2A26` instead, comparing "GR IV", "GR IIIx", "GR III", "GR II". `bled` has no DIS implementation, so the DIS server and its exact strings are **[unknown]**.

### 4.3 After Wi-Fi join: `GET /v1/props`

`model` (with a `RICOH` prefix that GR WORLD strips), `serialNo`, `firmwareVersion`, `bdName`, `ssid` ([HTTP API row 1](protocol/http-api.md#1-endpoint-table)). This is the only identification path for GR II, which has no BLE. The `/v1/photos/.../info` `cameraModel` field identifies which body took a photo, not the connected camera.

### 4.4 Over USB (wired import)

The camera enumerates as a standard PTP device (class 6) with vendor ID `0x25FB` and a per-body product ID: GR III `0x210F`, GR IIIx `0x2115`, GR III HDF `0x211E`, GR IIIx HDF `0x2121`, GR IV `0x2123`, GR IV HDF `0x2125`, GR IV Monochrome `0x2127`, GR IVx `0x2129`. The body-to-script pairing is **[inferred]** from `sysmgrd` string order; GR III, IIIx and IV are corroborated by third-party `lsusb` reports. PTP GetDeviceInfo also returns model, version and serial. Details and limits (USB is read-only import): [USB](protocol/usb.md#gadget-composition).

### 4.5 What not to use

- SSID or BLE name: both are user-editable settings, so they are not a reliable model identifier.
- Firmware package or version string alone: one GR IV image serves three bodies under two version labels.
- GR IV `bled` `CameraService::FetchSpecialModel` reads property `0xd0` `SPECIAL_MODEL_FLAG` (0 or 1, otherwise logged and forced to 0). Its meaning is **[unknown]**; do not use it for identification.

## 5. Recommendations for the client

1. Treat model as an enum keyed by advertising code with a string fallback: `{1: GR III, 5: GR III HDF, 3: GR IIIx, 6: GR IIIx HDF, 7: GR IV, 8: GR IV HDF, 9: GR IV Monochrome, 10: GR IVx (unreleased)}`; GR II only from `/v1/props`.
2. Capability flags per family, not per body: `gr3family` (codes 1, 3, 5, 6 — identical `bled`/`webapid`) and `gr4family` (7, 8, 9, 10 — identical firmware file). Add body-specific flags only where hardware differs (e.g. Monochrome image controls, HDF filter), and confirm them on hardware.
3. Minimum firmware: follow GR WORLD (GR III ≥ 2.00, GR IIIx ≥ 1.50, GR II ≥ 3.00, GR IV any). Compare versions per model: GR IV Monochrome's version line is 0.10 behind GR IV for the same image (1.10 vs 1.20).
4. Persist `(model code, serial, BLE address)` at pairing; re-check `serialNo` and `model` from `/v1/props` after every Wi-Fi join, as GR WORLD does.

## 6. Open questions (hardware)

1. Exact `model` and `firmwareVersion` strings reported by GR IV Monochrome and GR IV HDF over BLE (custom characteristic and DIS) and `/v1/props`; confirm Monochrome reports the 1.10 from its RTOS record.
2. Meaning of the `bool` argument selecting the advertised service UUID (tag `03` itself is camera power; see §4.1).
3. GR II `/v1/props` model string and whether GR II firmware 3.00 matches the Wi-Fi-only paths in GR WORLD.

## Evidence

| Finding | Evidence file | Evidence ID |
|---|---|---|
| GR IV `bled` advertising builder and code table | `firmware/evidence/gr4-bled-set-advert-data.json` | `ev_5ce8c205f6213f29f677e2589bedeaf5546509f0f87f5fe83b134e91a16f9e5f` |
| GR III `bled` advertising builder (codes 1–6) | `firmware/evidence/gr3-bled-set-advert-data.json` | `ev_eed2651678d239903e49b4771a7275f43ebbf0cceea85b58a5a0a80ccd0eb487` |
| GR IV BT-only advertising (`sysmgrd`) | `firmware/evidence/gr4-sysmgr-set-advert-data.json` | `ev_ba2a4b3a961e49116b53f779d9eb69b64fc2c1b38fad429aeb4fa0dabab4cec9` |
| GR IV BT-only model codes 7–10 | `firmware/evidence/gr4-sysmgr-get-model-code.json` | `ev_0706614fbc975ae5e4ea7e44301f9a912735be2d10dcb7ae34867fcb0b35e0d8` |
| Model/serial/version property loader | `firmware/evidence/gr4-bled-load-model-serial.json` | `ev_00a2c3f3a6baaa9c9e1f236043848deda28aabdb46f51159e57f67a1e87b1c98` |
| ModelName characteristic read (GR IV / GR III) | `firmware/evidence/gr4-bled-model-name-read.json`, `firmware/evidence/gr3-bled-model-name-read.json` | `ev_f3629708bd3288111ea58f1967fc8685920bb6c633fbffab881bc0201061ea58`, `ev_8da3e902de6555912784f823c8ca369330a7604cf693d05d2f34a3227923fe79` |
| `SPECIAL_MODEL_FLAG` | `firmware/evidence/gr4-bled-fetch-special-model.json` | `ev_b915a89b9103d225aebd52c0435ccb720ea25f96a87f0607d8053f143a91f24b` |
| Full session bundle | `firmware/evidence/model-identification-bundle.json` | 22 records |

Literal operands of the string comparisons were resolved from the instructions with `objdump` (GR IV Thumb `pc`-relative literals in `bled` `0x36ac4..0x37194` and `sysmgrd` `0x1d53c..0x1d594`; GR III ARM `movw/movt` in `bled` `0x48f20..0x49814`). Binary hashes: GR IV `bled` `cace4337…`, GR IV `sysmgrd` `be957973…`, GR III `bled` `fd2b2678…` (full values in the [firmware inventory](firmware-protocol-inventory.md#firmware-identity-and-extraction-audit)). App side: `work/dis/dis.txt` `0xda55a8` (`ldrb` model byte), `0xda560c..0xda5740` (accepted codes per family).
