# GR WORLD 2.0.0: how it powers on an OFF camera (static analysis)

Sources: `work/dis/dis.txt` (addresses `0x...`), `work/cs/blutter_out/pp.txt` (`pp+0x...`), `work/cs/blutter_out/objs.txt` (line numbers), jadx `work/jadx/sources`. Labels: **[inferred]** = deduced from code shape, not directly visible; **[unknown]** = not determinable statically.

## TL;DR

GR WORLD does **not** write `01` to Camera Power `B58CE84C`. It turns the camera on by writing the **Operation Mode** characteristic `1452335A-EC7F-4877-B8AB-0F72E18BB295`:

- It connects normally (no wake-up scan, no bond step, no Image Sync style "connect, wait for drop, rescan").
- It reads the Camera State service. If operationMode reads **`02` (bleStartup)**, it writes **`01` (playback)**, or **`00` (capture)** when the connect came from the Remote button.
- It keeps the link and carries on with the normal post-connect sequence.
- On hardware the first link to an off camera drops while it wakes; GR WORLD's connect retry makes the second link (see the end of §3).

The old docs claim "GR WORLD has no wake path" is wrong. The narrower claim "never writes `01` to `B58CE84C`" is still true.

## 1. Every write that can happen while the camera is off

### 1.1 Camera Power `B58CE84C` (class YFb, cid 0x68a): only `00`, re-confirmed

- The UUID string is pp+0x41280, referenced only by the UUID getter block 0xb1be5c (`0xb1c210`).
- Characteristic selection by cid 0x68a happens in exactly two places:
  - closure 0x57d528 (`cmp x1,#0x68a` at 0x57d544), used by the notify setup 0xd37f68 and by the writer 0xe4b1c8;
  - the read-all 0xd40f68 (`cmp x0,#0x68a` at 0xd4119c).
- The single writer 0xe4b1c8 passes the constant `false` into the write-op factory: `add x3, x22, #0x30` at **0xe4b304**, then dispatch `sub x30,x0,#0xebd` at 0xe4b308.
- The bool encoder 0xe5d568 maps true→`[01]` and false→`[00]` (0xe5d5a8..0xe5d650). Its only caller is 0xe5d4c4, inside the op `execute` 0xe5d340.
- **Result:** `B58CE84C` only ever receives `00`. Its callers are the power-off branch of the home power button (0xe49d2c → 0xe4b060 → closure 0x99bc5c → 0xe4b1c8) and the post-firmware-update power-off (0xe86104).

### 1.2 Operation Mode `1452335A` (class bGb, cid 0x687): **this is the power-on write**

- Enum SFb (`work/cs/blutter_out/objs.txt` 56083-56121; `off_14` = wire byte):

  | Value | Name | Pool object |
  |---|---|---|
  | 0 | capture | pp+0x2a280 |
  | 1 | playback | pp+0x2a278 |
  | 2 | bleStartup | pp+0x2a270 |
  | 3 | other | pp+0x2a340 |
  | 4 | powerOffTransfer | — |

- Write path: 0xd40ae8 → closure 0x58d584 → **0xd40c54**.
  - The characteristic filter closure 0x58d5dc (pp+0x2a308) matches cid **0x687** (`cmp x1,#0x687` at 0x58d5f8).
  - Write op 0xe5eea4 loads `SFb.off_14` (`ldur x2,[x1,#0x13]` at 0xe5eee4) and passes it to encoder **0xa12fd4**, a one-byte `Int8List` (`strb` at 0xa13004).
  - It then calls FBP `writeCharacteristic` 0xe5c094 at 0xe5ef50.
- FBP write parameters: write type `withResponse` (Wpb@868fd1 pp+0x40f58, `work/cs/blutter_out/objs.txt` 56962) and timeout `mov x0,#0xf` = 15 s (0xe5c2f4) **[inferred: seconds]**.
- Callers of 0xd40ae8 (and therefore every operationMode write):
  - **0xd403b8**, the post-connect power-on check (§3 step 7):
    - `bl` at 0xd404c8 writes **playback**;
    - `bl` at 0xd40518 writes **capture**.
  - **0xe4d738**, the "ensure mode" helper:
    - It reads the mode (0xd40e04 at 0xe4d7fc).
    - It writes the requested mode at 0xe4d860 only when the current mode differs from the requested one **and** is not `other` (0xe4d818-0xe4d82c).
    - Callers: Remote 0xe4d4b8 (requested capture, pp+0x2a280 at 0xe4d644) and Import 0xe4f058 (requested playback, pp+0x2a278 at 0xe4f2c8 / 0xe4f4cc).

### 1.3 WLAN Control `9111CDD0` = `01`: conditional, and **before** the mode check

- In the reconnect flow 0xd2e93c, the `01` write (0xd2f474 `add x2,x22,#0x20` → 0xd419d0 at 0xd2f478) runs only when the named arg `WAi` is true (`tbnz w1,#4` at 0xd2f43c).
- It sits **before** the operation-mode check at 0xd2f60c. So when a path passes `WAi=true` against an off camera, WLAN-on is written while the camera is still in bleStartup.
- `WAi=true` is passed by ZQb closures 0xe49658 (0xe497a4) and 0xe499a0 (0xe49aec), reached from the Import flow via 0xe47bd8. It is also passed by the firmware-update closure 0xdd8fdc (0xdd90cc).
- The power button path does **not** pass `WAi` (ArgDesc pp+0x2adb0 has no `WAi`), so the default is false.
- A failed WLAN write throws ER_BL_005 writeException (zSb@8655c1, pp+0x26ee8, 0xd41cc0-0xd41cd4). That aborts the connect before the mode write **[inferred]**.

### 1.4 Other characteristics

- These come **after** the operationMode write, inside the same flow:
  - pending camera-name write 0xd3fdf8 (only when the record's field @0xf == 2, 0xd2f634);
  - date/time sync (0xd2ff7c, only if `is_time_sync`);
  - GPS push (0xd46f20).
- Never written in the power-on paths:
  - registration `FE3A32F8` (lives in the `0F291746` service, getter 0x82e874; written only by `/pairing` 0xda5fd4);
  - BLE-enable-condition and operationModeList (`430B80A3`, read-only in GR WORLD).
- Reachability check (call graph depth 7 from 0xd2e93c and 0xe49d2c): no `createBond` (0xda965c/0xda9958), `getBondState` (0xda6ee0), bond-state handler (0xd32294) or `FE3A32F8` write (0xda5fd4).

## 2. UI / provider paths that can hit an OFF camera

### 2.1 Scan classifier (does not trigger connects to an off camera)

`bleScanProvider` (pp+0x2a758, class oFb). The constructor 0x59151c stores `9a5ed1c5-…` (pp+0x270e8) at field +0xf and `0F291746-…` (pp+0x2a760) at field +0x13. The scan function is 0xd46a9c:

1. Read prefs `lastConnectedDevice` (pp+0x27d30, 0xd46af0) and require the MAC regex (0x5907c4, pp+0x2a680).
2. `startScan(withServices: [9A5ED1C5, 0F291746], timeout 20 s)` at 0xd46cac. The 20 s timeout is la@8704f1 = 0x1312d00 µs, pp+0x1d360; the service list is built at 0xd46c5c-0xd46c94.
3. Poll every 100 ms (la@870441, pp+0x1cd8, 0xd46d14) while scanning and no match.
4. Result enum qFb (`work/cs/blutter_out/objs.txt` 56157-56185):
   - no match → `undetected` (pp+0x2a710, 0xd46d58);
   - `serviceUuids.contains(9A5ED1C5)` → `on`, otherwise `initialized` (0xd46d7c-0xd46d94);
   - then `contains(0F291746)` → **`off`**, which takes precedence (0xd46da4-0xd46db0).
   - Manufacturer tag `03` is **not** used.

All three consumers test only `== on` (pp+0x27590). They skip the connect otherwise:

- app-resume auto-connect 0xd2b5b4 (0xd2b7ec-0xd2b7f4 → ensureConnected at 0xd2b838);
- home closure 0xdd140c (0xdd1570);
- firmware repository closure 0xdd6150 (0xdd6248).

**So background/auto reconnect never wakes an off camera.**

### 2.2 Paths that do connect regardless of scan state (these wake the camera)

All of them call `ensureConnected` 0xd2b990 with an explicit device (`VJd`). That routes to 0xd2dc0c → 0xd2e93c with `oDi=false` (the d2dc0c call at 0xd2ddcc passes only `VAi` / `WAi`, ArgDesc pp+0x288c0).

**Home camera-card power button**, cameraInfoViewModel ZQb (`cameraInfoViewModelProvider`, pp+0x1fee8):
- Handler 0xe49d2c, entered from closure 0xe49bd0.
- If the card's power flag (`[fp-0x138]`, field @0xb, tested at 0xe4a0b8) is false, it takes the **power-on branch** 0xe4a3c8. The flag is shown as `CameraPowerModel(isPower:` pp+0x471d8 **[inferred]**.
- Branch steps:
  1. Save `lastConnectedDevice` (0xe4a53c/0xe4a540).
  2. Permission checks 0xdd0e88 / 0xdd078c **[inferred]**.
  3. Wrapper 0xdd0224 runs closure **0xe4b36c** (pp+0x4dc60, at 0xe4a7d4).
  4. Closure 0xe4b36c shows the progress overlay 0x99b270 **[inferred]**, disconnects the current camera with 0xe1f068 (on failure it logs `切断失敗:`, "disconnect failed", pp+0x33990), then calls `ensureConnected` with `VJd`, `eLd` and `hLd` (0xe4b754, ArgDesc pp+0x2adb0). `VAi` defaults to true, so the camera powers on to **playback**.
- Analytics: `on_success` (WLb@867761, pp+0x4dc68, 0xe4a908) and `on_failure` (WLb@867721, pp+0x4dc98, 0xe4ae38). Enums are at `work/cs/blutter_out/objs.txt` 55518-55548.
- The power-off branch is the one that writes `B58CE84C=00` and records `off_success` (WLb@867781, 0xe4a3a8).

**Import button** (aRb closure 0xe4f058, route `/imagePicker` pp+0x8448):
- If not connected: 0xe47bd8 → `ensureConnected` with `WAi=true`, `VAi` default true. Then 0xe4d738 ensures playback.

**Remote button** (aRb closure 0xe4d4b8, `images/home/remote.svg` in 0x99c46c):
- 0xe4db08 → closures 0xe4ed78/0xe4eee8 call `ensureConnected` with **`VAi=false`**: `add x16,x22,#0x30` at 0xe4eeb4 / 0xe4f024, ArgDesc pp+0x4de18, where `VAi` is in the last stack slot. Then 0xe4d738 ensures **capture** (0xe4d648).

Other explicit-device callers of 0xd2b990: 0xdd6850, 0xe07338, 0xe20ad0, 0xe50bc8, 0xe50d60, and 0xdd8fdc (firmware).

### 2.3 UI copy (pool)

| Pool | Text |
|---|---|
| pp+0x694c0 | "Turning on the camera failed." |
| pp+0x66c18 | "カメラの電源オンに失敗しました。" |
| pp+0x694b8 | "Turning off the camera failed." |
| pp+0x697d8 | "The camera will be turned off." |
| pp+0x66f50 | "カメラの電源がオフになりました。" |
| pp+0x698d8 | "Connecting via Bluetooth..." |

- "Turning on the camera failed." and its Japanese twin are in the l10n getter at 0x6d0d98, which dis merges into 0x6d0154.
- The power-button error handler picks strings through l10n selectors 0xf5e/0xf56 (0xe4ab28/0xe4ab6c). The exact selector→string mapping is **[unknown]** (dispatch table not dumped).
- No dedicated "power on" button string was found. The power action is the card's power toggle.

## 3. Power-on sequence (home power button; Import and Remote differ only where noted)

1. The home card shows the camera as not powered (power flag false; scan state `off` / `undetected` / `initialized` all count) → user taps power → 0xe49d2c power-on branch.
2. Disconnect any other camera (0xe1f068) and show the progress overlay.
3. `ensureConnected` 0xd2b990: `VJd` != null → 0xd2dc0c → **0xd2e93c** with `VAi=true`, `WAi=false`, `oDi=false`.
   - Import: `WAi=true`.
   - Remote: `VAi=false`.
   - The prologue stores `VAi` at `[fp-0x120]` (0xd2e9a4), `WAi` at `-0x118` and `oDi` at `-0x110` (0xd2ea5c). Neither slot is overwritten before 0xd2f60c.
4. Device record lookup. If the stored `remote_id` is not MAC-shaped, run a 15 s resolve scan (0xd2eb9c 0x5907c4 → 0xd45404, la@8704e1). Save `lastConnectedDevice`, then disconnect other devices (0xd431f0 at 0xd2f174).
5. **6 s guard:** if the camera-power notification reported off less than 6000 ms ago (`ZBi`, pp+0x29748), wait the remainder (0xd2f1c0-0xd2f370; log `6秒経過済み:`, "6 s already elapsed", pp+0x29758).
6. **Connect** with `FSb.connect` 0xd41ce8 at 0xd2f40c → 0xd42080 (parameters in research/protocol/ble.md §Connect parameters):
   - autoConnect false; LE transport; 35 s timeout; 3 attempts 50 ms apart; MTU 512 after 350 ms; discoverServices timeout 15 s.
   - **No firmware check and no bonding step.**
   - On Android, FBP connects straight to the stored public MAC: `getRemoteDevice(mac).connectGatt(app, false, cb, 2)` (`p326m6/C4069h.java:1618-1621`). No scan result is needed.
7. *(Import only, `WAi`)* Write `01` to `9111CDD0` (0xd2f478).
8. **Power-on check 0xd403b8** (called at 0xd2f60c with x2 = `oDi`, x3 = `VAi`):
   1. Read the whole Camera State service: 0xd40e04 → closure 0x58d60c → 0xd40f68. This includes operationMode (cid 0x687 at 0xd41310) and cameraPower.
   2. If `operationMode == bleStartup (02)` (0xd40474-0xd40480):
      - `oDi == true` (auto/background connect): log, disconnect (0xd408b0), throw **ER_BL_010** `autoConnectException` "自動接続に失敗しました。" ("auto-connect failed"; zSb@8656a1, pp+0x27650, `work/cs/blutter_out/objs.txt` 53709).
      - else `VAi == true`: **write `01` (playback) to `1452335A`** (0xd404c8).
      - else: **write `00` (capture)** (0xd40518).
   3. If it reads any other value: no write.
   4. Store the model (0xd40628-0xd40790) and return. **No delay, no disconnect wait, no rescan, no wait for a notification.**
9. Continue the normal flow on the same link:
   - camera-name write (GR IV, 0xd3fdf8);
   - Camera Information / WLAN refresh;
   - firmware check;
   - subscribe all notifications (0xd30c30 at 0xd2fb28). This includes CameraPower `B58CE84C` (0xd37c94; parser DHb 0x57d558 → `cameraPowerNotifierProvider` pp+0x2a058; `DeviceManager _onCameraPowerChanged` 0xe84c3c);
   - location push;
   - time sync.
10. Import / Remote then call 0xe4d738, which rewrites the mode if it is still not the wanted one. The power button does not.

Whether the camera keeps the BLE link while it boots after the `1452335A` write is **[unknown]**. The app assumes it does: there is no reconnect logic after step 8.

**Observed on hardware (GR IV HDF fw 1.20, Android 17, phone bonded by GR WORLD):** the **first** link to an off camera drops before any GATT traffic, about 5.5 s after it opens, with a link supervision timeout (`CONNECTION_TIMEOUT 0x08`); no encryption is attempted on it. GR WORLD's own power-on shows the same drop and reconnects 86 ms later through its connect retry (3 attempts, [ble.md §Connect parameters](ble.md#connect-parameters)); that second link encrypts with the stored bond. On the second link Operation Mode reads `02` (bleStartup); writing `01` succeeds and the link stays up through the identity and Wi-Fi credential reads. Without that reconnect the camera did not end up on: our single-attempt probe, run twice 70 s apart, saw the same drop both times. Whether it briefly booted in between is **[unknown]**. A client must therefore retry the connect promptly, and treat a drop before setup completes as "camera waking", not as an error ([results log](../hardware-validation.md#4-results-log)). Whether the drop is the controller handing the link to the booting host is **[inferred]**.

Independent corroboration: Ricoh Image Sync does the same thing on `OperationMode == BLE_STARTUP`. It writes CAPTURE from the shooting icon and PLAYBACK otherwise (research/protocol/connection-imagesync.md §1.4 step 3, `m/k2.java:118-142`).

## 4. Camera-on detection rule

- **Before connecting (scan):** advertised service `9A5ED1C5` → on. Advertised `0F291746` → off, and this wins if both appear (0xd46d60-0xd46db8). Only `on` triggers automatic connects.
- **After connecting:** operationMode `02` = BLE-only standby; the app treats it as "needs power-on" and writes `01`/`00`. Values `00`/`01`/`03`/`04` = already running; no write.
- **Afterwards:** CameraPower notifications (`01` on / `00` off, parser 0x57d558) drive the UI. The app never blocks on them.

## 5. Bond / registration gating evidence

- No reconnect or power-on path bonds, checks bond state or writes `FE3A32F8` (§1.4 reachability).
  - `FE3A32F8` (in the off-state advertised service `0F291746`, 0x82e874) is written only during `/pairing`.
  - `createBond` (90 s) is called only from pairing (0xda965c/0xda9958).
- GR WORLD only ever connects to cameras already in its `device_info` table. The connect-flow lookup failure throws ER_BL_001; error enum zSb, `work/cs/blutter_out/objs.txt` 53637-53726.
- So the app assumes the phone↔camera bond made at pairing time (camera "Execute Pairing", camera on) already exists. On Android the OS re-encrypts with the stored LTK when needed.
- No error string is specific to the off-state rejection. A refused off-state connect surfaces as connect timeout → ER_BL_001 "接続に失敗しました。" ("connection failed", zSb@865681), or as auto-connect failure ER_BL_010.
- Firmware lead (not app code): at power-off `sysmgrd` loads the stored Bluetooth device database into the controller (`load_bt_only_fw::restoreDDBDataToAic`; research/hardware-validation.md row "Power on from the app"). Together with the app never bonding in this path, this suggests the BT-only controller only accepts identities bonded on the camera side **[inferred]**.
- The Mac's failure, where the link never completes even before "Forget", is consistent with that. It may also involve the address type: Android dials the public identity MAC; CoreBluetooth dials by peripheral UUID from its own address **[unknown]**.

## 6. Corrected statement for research/protocol/ble.md

> GR WORLD writes Camera Power `B58CE84C` only with `00` (power off, 0xe4b304). It **does** wake an off camera.
>
> 1. It connects directly to the registered camera, with no scan and no bonding step.
> 2. It reads operationMode `1452335A`.
> 3. If the value is `02` (bleStartup), it writes `01` (playback), or `00` (capture) from the Remote button. See 0xd403b8; the writes are at 0xd404c8 and 0xd40518.
> 4. It then continues on the same link.
>
> Background/auto-connect never does this: it connects only when the scan shows `9A5ED1C5`, and aborts with ER_BL_010 if it finds bleStartup.

## 7. What a third-party client must replicate

1. **Be bonded with the camera before it is off.** Pair with the camera on (Execute Pairing) and keep both halves of the bond. A one-sided "forget" breaks reconnects. GR WORLD never bonds in the power-on path.
2. **Connect directly to the known peripheral**, without waiting for an "on" advert. Use LE, no autoConnect, allow up to 35 s, and retry 3×. Honour the 6 s guard after a power-off.
3. Discover services, request MTU 512 (optional), and read operationMode `1452335A-EC7F-4877-B8AB-0F72E18BB295`.
4. If it reads `02`, **write `01` (playback) with response**, or `00` for shooting. Do not write `01` to `B58CE84C`; GR WORLD never does, and its effect is **[unknown]**.
5. Keep the link. Subscribe to `B58CE84C` notifications and treat `01` as "powered on". GR WORLD does not wait for it, but a client should, with a timeout; this is a design choice.
6. If WLAN is needed, follow GR WORLD's Import order: write `9111CDD0 = 01` right after the connect and **before** the operationMode check and write (0xd2f478 precedes 0xd2f60c). Writing the mode first and WLAN-on afterwards is an untested alternative, not a requirement. Which order an off GR IV accepts is **[unknown]** until tested on hardware.
7. If the connect itself never completes, the problem is below GATT (bond/accept-list), not the write sequence. Nothing in the app explains a Mac-only failure.
