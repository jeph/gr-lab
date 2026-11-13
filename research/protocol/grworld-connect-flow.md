# GR WORLD 2.0.0: pairing, bonding, registration, reconnect, disconnect and power-on (static analysis)

Scope: RICOH GR WORLD 2.0.0 for Android (`com.ricohimaging.grworld`), Dart AOT layer plus the flutter_blue_plus (FBP) Android plugin. Each claim below cites its evidence. Nothing here was observed at runtime.

## Sources and labels

- **Dart addresses** (`0x…`) are in `work/dis/dis.txt`.
  - `pp+0x…` = `work/cs/blutter_out/pp.txt`.
  - `Obj!X@…` = `work/cs/blutter_out/objs.txt`.
  - Dart `true` is `x22+0x20` and `false` is `x22+0x30`, so `tbnz w,#4` branches when the value is false.
  - `la@…` Durations hold microseconds.
- **Java citations** are `file:line` in `work/jadx/sources/p326m6/`. This package is FBP's Android plugin: `C4069h` = FlutterBluePlusPlugin, `C4067f` = the GATT callback, `C4065d` = the broadcast receivers.
- **REA evidence**: `ev_7c86497f…a34b42` (`identify_flutter_build`, saved in `firmware/evidence/grworld-connect-flow.rea-evidence.json`).
  - The libapp.so SHA-256 it observed in `split_config.arm64_v8a.apk` is `49ced634…ded85`. That is identical to `work/lib/arm64-v8a/libapp.so`, the file the disassembly was made from.
  - The REA Android tools returned `capability_unavailable` (REA_JADX_MCP_JAR is not configured). Java claims therefore come from the existing jadx tree.
- **Labels**:
  - **[observed in code]** = read directly from the instructions or Java.
  - **[inferred]** = deduced from code shape or UI copy.
  - **[unknown]** = not determinable statically.

### Plugin API surface (settles Q1 and Q5 negatives)

The object pool contains these FBP method-channel names and no others: `connect`, `disconnect`, `requestMtu`, `discoverServices`, `setNotifyValue`, `startScan`, `stopScan`, `turnOn`, `getAdapterState`, `connectedCount`, `flutterRestart`, `createBond` (pp+0x35d60) and `getBondState` (pp+0x35e70).

`removeBond`, `clearGattCache`, `requestConnectionPriority`, `setPreferredPhy`, `getSystemDevices`, `getBondedDevices` and `readRssi` are **absent from the pool**. The Dart code therefore never calls them **[observed in code: pool search of `work/cs/blutter_out/pp.txt`]**. The Java handlers for these methods exist but are unreachable (`C4069h.java:2018`, `2088-2097`, `2099-2112`).

`createBond` has exactly one Dart caller, the pairing bond handler (0xda965c ← 0xda7018). `getBondState` is reached only from FBP's `bondState` stream (0xda6ee0 ← 0x82ee40 ← 0xda6c34), whose only caller is pairing (0xda5adc) **[observed in code]**.

---

## 1. Pairing / registration (route `/pairing`, `bleDevicePairingViewModelProvider` pp+0x35e98, `WOb` 0xda58b0)

### 1.0 Pages before `/pairing`

- **Route order**: `/connectionCheck` → (`/connectionExist` | `/connectionMissing`) → `/connectionStart` → `/detect` → `/pairing`. The route table is at pp+0x8320..0x83a0. The pairing result is logged per entry route by 0xda6574 (strings at 0xda6718/0xda6798/0xda6818) **[observed in code]**.
- **Before scanning**, the user is told: "Display the wireless communication settings in the setup menu of the camera, enable the operation mode, and then start pairing. Then tap the button below to start searching for the camera." (pp+0x69600) **[observed]**. So the camera is already in **Execute Pairing** before the app scans.
- **`/detect` scan** (0xda4e7c → FBP `startScan` 0xd45898 at 0xda4f10):
  - service filter `9A5ED1C5-…` (Camera Information, the camera's on-state advert);
  - timeout `la@870591` = 30 s (0xda4f04);
  - FBP Android scan mode LOW_LATENCY and all PHYs (`research/protocol/ble.md` §Scan settings).
  - The scanned `BluetoothDevice` (Android public/identity MAC) is passed into pairing as the named arg `Nod` **[observed in code]**.

### 1.1 Ordered steps in 0xda58b0 (all **[observed in code]** unless marked)

1. **Connect.** Call 0xd41ce8 at 0xda59b4 with `checkFirmware=true` (`x2 = true`, 0xda59a8) and `Nod = scanned device` (ArgDesc pp+0x35bd0). Inside 0xd41ce8:
   - Retry wrapper 0x5479e4 at 0xd41ec8: default **3 attempts, 50 ms apart** (`mov x5,#3` at 0x547aac; delay `la@8704a1` = 0xc350 µs = 50 ms at 0x547a40). It stops early on FBP code 10 "connection canceled" (`cmp w0,#0x14` at 0xd1b318).
   - Each attempt runs 0xd42080:
     1. If another camera is connected, disconnect it (0xd30a8c / 0xd42c60).
     2. FBP `connect` 0xd33764 at 0xd4218c with **no named args** (ArgDesc pp+0x140). So:
        - `autoConnect = false` (default `x22+0x30` at 0xd337b4);
        - `mtu = 512` (Smi 0x400 at 0xd33808);
        - **timeout 35 s** (`mov x0,#0x23` at 0xd33a74).
     3. FBP then sends `requestMtu(512)` (0xd33b00 → 0xd33c6c, 0x200 at 0xd33d78, 15 s timeout at 0xd33ea0) after a 350 ms pre-delay.
     4. Wait for `connected` (closure 0x58ee30 compares `jpb@8691b1` = connected).
     5. `discoverServices` (0xd42790 → 0xd427ec, 15 s). FBP also enables the Service Changed `2A05` CCCD if present (0xd42a44 `setNotifyValue`).
     6. Because `checkFirmware` is true: read DIS `180A` model (cid 0x659, 0xd42668 / 0x58e0f4) and firmware (cid 0x657, 0xd42424 / 0x58e0c4), then run the minimum-firmware check 0x54b6c0. On failure, throw **ER_BL_007** (0xd423f0).
     7. Save `lastConnectedDevice` (0xd4237c).
   - Any non-ER_BL_007 exception becomes **ER_BL_001** (0xd4205c).
2. **If cancelled meanwhile** (state error == `cancelError` `OOb@866f41`, 0xda59e4): disconnect 0xd439ac and stop.
3. **Set state `connected`** (`NOb@866fe1`, 0xda5a88) and subscribe to FBP `device.bondState` (0xda6c34 at 0xda5adc).
   - This `async*` stream first yields the **current** state from `getBondState`: `remoteDevice.getBondState()` mapped to none/bonding/bonded (`C4069h.java:2059-2068`).
   - After that it yields every `OnBondStateChanged` broadcast (`C4065d.java:95-145`; receiver registered at `C4069h.java:715`).
   - `.listen(closure 0x82eedc → 0xda6fa4)`; the subscription is stored at WOb+0x17 (0xda5b20).
   - The view model then **awaits a Completer** (WOb+0x23, 0xda5b3c-0xda5b54) **with no timeout wrapper**.
4. **Bond-state handler 0xda6fa4** (enum `kpb`: none=0 `@869171`, bonding=1 `@869151`, bonded=2 `@869131`; branch at 0xda6fd4-0xda6fe4):
   - **`none`**: log, then **`createBond`** (0xda965c at 0xda7018). FBP createBond:
     - throws "device is not connected" if disconnected (0xda9848);
     - takes the "global" mutex;
     - listens for the next `OnBondStateChanged` that is not `bonding`;
     - invokes `createBond` (Java `C4069h.java:2069-2087`: returns false if already bonded (12), true if bonding (11), else calls `remoteDevice.createBond()`);
     - waits up to **90 s** (`mov x0,#0x5a` at 0xda97cc);
     - throws "Failed to create bond." (pp+0x35d78) unless the result is `bonded`.
     - After it returns, the UI state becomes `bonding` (`NOb@866fc1`, 0xda7088).
   - **`bonding`**: log only (0xda70e4).
   - **`bonded`**:
     1. Log, then **cancel the bond subscription** (WOb+0x17 `.cancel()`, 0xda711c-0xda7130).
     2. Run post-bond 0xda7474 (§1.2).
     3. If it returns true: state **`success`** (`NOb@866fa1`, 0xda71b8), then **registration write 0xda5fd4** (0xda7214).
     4. Otherwise: state `error` (`NOb@866f81`).
   - **Catch** (0xda72e8-0xda7408): if the Completer is not yet complete, cancel the subscription and `completeError` (0x487c08). The pairing VM then sets `connectError` and disconnects (0xda5e08 → 0xda5f38 `0xd439ac`).
5. **SMP trigger.**
   - The SMP pairing is started by **Android `BluetoothDevice.createBond()` on the already-open LE link** (`C4069h.java:2079`). It is *not* started by an insufficient-authentication ATT error **[observed in code]**.
   - Before `createBond`, the app has done only unencrypted operations: connect, MTU, discovery (plus a possible 2A05 CCCD write) and the two DIS reads.
   - If Android is **already bonded**, the stream's first event is `bonded`, `createBond` is never called, and the flow goes straight to §1.2 **[observed in code]**.
   - The SMP method and parameters (IO capabilities, MITM, Secure Connections, key distribution) are chosen by the Android stack and the camera. **[unknown]** from the app.
6. **Pairing-request handling.** No `ACTION_PAIRING_REQUEST` receiver, `setPairingConfirmation` or `setPin` exists anywhere in the jadx tree (`grep` over `work/jadx/sources`). FBP registers only `ACTION_STATE_CHANGED` and `BOND_STATE_CHANGED` (`C4069h.java:714-715`). The passkey/confirmation dialog is Android's own **[observed in code]**.

### 1.2 Post-bond 0xda7474 (runs only after Android reports `bonded`; first encrypted traffic)

1. Read all Camera Information characteristics (0xd3e248 at 0xda74f4).
2. Read all WLAN Control characteristics (0xd3ee8c at 0xda7524).
3. GR IV only (model string "GR IV" pp+0x1a320 at 0xda756c): pending/restored camera-name write 0xd3fdf8 (0xda7644). On failure, log "restored camera name check failed:" and read back 0xd3fc0c.
4. Model-family check ("ModelType error:", `modelTypeError` `OOb@866f21`) and minimum-firmware check ("FirmwareVersion error:", `firmwareError` `OOb@866ec1`).
5. Insert the `device_info` row (0xda91e4 at 0xda7fb4).
6. GR IV cloud firmware lookup (0xda8ec4 / 0xda8c18; errors only logged, "fetch firmware error:").
7. Analytics `success` (0xd2e194 at 0xda8a04, 0xda6574 at 0xda8a38).
8. Return true.
9. Failures set `registerError` (`OOb@866f01`) and log `other_failure` (TLb@8678a1).

### 1.3 Registration write 0xda5fd4 (Client Registration `FE3A32F8-A189-42DE-A391-BC81AE4DAA76`)

- **Value**: the Android model name from `DeviceInfoPlugin` (0xcf5d90 at 0xda6004), sanitised by 0x82ebc8:
  - "Unknown" (pp+0x9450) if empty;
  - non-printable characters replaced by "?" (pp+0x15d8);
  - spaces handled with "_" (pp+0x50f0).
- **Call chain**: written via the 3×/50 ms retry wrapper (0xda616c → closure 0x82e7dc → 0xda62d8). The UUID pair `0F291746…` / `FE3A32F8…` comes from getter 0x82e874 (pp+0x2a760, pp+0x35dd0). A failed write throws ER_BL_005 (pp+0x26ee8, 0xda62b4), but **0xda5fd4 catches and only logs it** (0xda607c-0xda6140) **[observed in code]**.
- **Callers (exactly two)**:
  - **0xda7214**: success path, **after** `bonded`, after the post-bond reads, the DB insert and the analytics `success`.
  - **0xda5d50**: the catch path of the connect, taken only when the exception equals **ER_BL_007** (unsupported firmware; `tbnz w0,#4,#0xda5e08` after `== zSb@865621`, 0xda5d2c-0xda5d44). It is then followed by `firmwareError` + `unsupported_firmware` analytics. Here the write happens **before any bonding**, and its failure is swallowed.
- **Correction to `research/protocol/ble.md`** §Pairing step 2 and §Phone name registration: the name write is *not* "right after the BLE connect, skipped on ER_BL_007". In the normal path it is the **last** pairing operation, after bonding; it is made unbonded **only** on ER_BL_007.

### 1.4 After success

- No disconnect on the success path. The only `0xd439ac` calls in pairing are the cancel path (0xda5a0c) and the error path (0xda5f38) **[observed in code]**.
- The Completer at WOb+0x23 is completed elsewhere. The success-side completion site was not located **[unknown]**.
- **No write other than FE3A32F8 and the optional camera-name write follows bonding.** After bonding, the only writes are the optional GR IV camera-name write (0xd3fdf8) and FE3A32F8. Nothing is written to the Camera State or Control services in this route **[observed in code]**. What those writes do on the camera side is **[unknown]**. FE3A32F8 may itself finalise registration or persist the bond on the camera. GR WORLD's best-effort error handling (failures only logged) does not rule that out, because a swallowed failure says nothing about the effect of a successful write.

### 1.5 What the user must do on the camera (Q2, UI copy, **[observed]** strings)

- **pp+0x695b8**: "When the pairing request dialog appears in the app, make sure that the authentication codes on the camera and the app are the same, then allow pairing in the app." This is numeric-comparison style.
- **pp+0x695a0**: "When the pairing request dialog box appears, enter the authentication code displayed on the camera." This is passkey-entry style; there are two variants.
- **pp+0x695b0**: "Next, tap [Execute Pairing] on the camera, or press the [OK] button.\n\nAfter you approve pairing on the camera, wait a moment and the camera registration will be completed."
  - JA: pp+0x66d08.
  - The "Next after pairing" button is pp+0x695a8 / pp+0x66d00.
- **pp+0x694d8** (failure hint): "When the pairing request dialog appears, check whether you approved the pairing on the smartphone as instructed on the screen, and whether you pressed the “OK” button on the camera."
- Other failure hints:
  - pp+0x69500: "Check that pairing has been started on the camera."
  - pp+0x69550: "…pairing … may not have been saved correctly … register the camera again."

**[inferred]**: GR WORLD's only gate before declaring success is Android `BOND_BONDED`. The copy says registration completes *after* the user approves on the camera, and lists "did you press OK on the camera" as a failure cause. Together these imply that on Android the bond does not reach `BONDED` (or the flow fails) until the camera-side OK. In other words, the camera, not the app, holds pairing completion behind OK. Which getter maps to which pairing UI state (passkey vs comparison; GR III vs GR IV) is **[unknown]**: the l10n getters 0x6d22c8 and 0x6d2690 are reached only by dispatch, not by direct `bl`.

### 1.6 Pairing timeouts summary

| Step | Value |
|---|---|
| Detect scan | 30 s |
| Connect | 35 s × up to 3 attempts, 50 ms apart |
| MTU | 512, after 350 ms, 15 s timeout |
| Discovery | 15 s |
| `createBond` | 90 s |
| Overall pairing timer | none: the Completer wait has no timeout **[observed in code]** |

---

## 2. Reconnect / normal connect (`ILb.ensureConnected` 0xd2b990)

### 2.1 Entry

- **Named args** (0xd2b9b4-0xd2bb24):
  - `VAi`: playback vs capture power-on, default true;
  - `VJd`: explicit device;
  - `WAi`: WLAN-on, default false;
  - `eLd`, `hLd`.
- **`VJd == null`** (auto/background): 0xd2ac44 reads prefs `lastConnectedDevice` (0xd2acf8). A null value throws ER_BL_001 (0xd2bcf0 → 0xd2c1b0). Otherwise **0xd465b8 → 0xd2e93c with `oDi=true`** (0xd2bd68-0xd2bd80).
  - Only caller: app-resume 0xd2b5b4. It runs `bleScanProvider` first and calls `ensureConnected` only when the scan result `== on` (`qFb@8681a1`, 0xd2b7ec-0xd2b7f4).
- **`VJd != null`** (UI actions: power button, Import, Remote, firmware, Wi-Fi register …): **0xd2dc0c → 0xd2e93c with `VAi`/`WAi`** (ArgDesc pp+0x288c0 at 0xd2ddcc); `oDi` defaults to false.
- Both paths are wrapped in a `CancelableOperation` (0x56f82c / 0x56f51c). Cancel → closure 0x5912bc → disconnect (0xd46310 → 0xd431f0). A timeout or cancel maps to ER_BL_009 / ER_BL_001.

### 2.2 Sequence of 0xd2e93c (**[observed in code]**)

1. Look up the `device_info` row (closure 0x551888). If it is missing: log "デバイス未検出:" ("device not detected") and throw ER_BL_001 (0xd2fe18-0xd2fe44).
2. If `remote_id` is **not** MAC-shaped (regex 0x5907c4 at 0xd2eb9c): unfiltered 15 s resolve scan (0xd45404 at 0xd2ebd8, log "remoteId変換:"). **Otherwise no scan.**
3. Save `lastConnectedDevice` (0xd2f094) and disconnect any *other* device (0xd431f0 at 0xd2f174).
4. **6 s power-off guard**: if `ZBi` (time of the last camera-power-off notification, pp+0x29748) is under 6000 ms ago (`mov x17,#0x1770` / `cmp` / `b.ge` at 0xd2f2c0-0xd2f2c8), `Future.delayed` the remainder (0xd2f320). Otherwise log "6秒経過済み:" ("6 s already elapsed").
5. **Connect** 0xd41ce8 at 0xd2f40c with `checkFirmware=false` (`x2 = false`, 0xd2f400) and **`MFd = stored remote_id string`** (ArgDesc pp+0x29760).
   - 0xd41ce8 builds `BluetoothDevice(remoteId: DeviceIdentifier(MFd))` (0xd41e08 `Allocateapb`, 0xd41e1c `Allocategpb`), i.e. `BluetoothDevice.fromId`. **No scan result is needed.**
   - Same connect core as pairing: autoConnect false, 35 s, MTU 512, discovery, 3 × 50 ms retries. No DIS check, **no bond step**.
6. If `WAi`: write WLAN `9111CDD0 = 01` (0xd419d0 at 0xd2f478).
7. **Operation-mode power-on check 0xd403b8** (at 0xd2f60c). See §4.
8. Pending camera-name write 0xd3fdf8 (0xd2f66c). Refresh WLAN / Camera Information into the DB (0xd3f640, 0xd3e874, 0xd3e248).
9. Firmware fetch and check (0xd38644 at 0xd2f878; 0x54b6c0 at 0xd2fa60). Errors are logged only.
10. Subscribe notifications 0xd30c30 (0xd2fb28). Analytics `success` (0xd2fde0). Time sync 0xd30254 if `is_time_sync` (0xd2ff7c). The location push 0xd46f20 is **not** started here on success: its call at 0xd2fc9c is in the exception handler entered at 0xd2fb40, which the success path jumps past (0xd2fb3c → 0xd2fe64; re-read 2026-11-12, correcting this step). What does start it is in [geotagging.md §2.1](geotagging.md#21-acquiring-location).

### 2.3 Failure handling and bond loss (Q3)

- **FBP Android `onConnectionStateChange`** (`C4067f.java:129-199`):
  - forwards `status` only as `disconnect_reason_code` / `disconnect_reason_string`;
  - closes the gatt on disconnect unless autoconnect (`183-187`).
  - There is **no special handling** of status 5/8/0x13/0x16/0x3d/133 (133 is only named "ANDROID_SPECIFIC_ERROR", `C4069h.java:154`) and no bond, encryption or retry logic in Java **[observed in code]**.
- **Dart side**:
  - Every failure in `connect` is retried 3 × 50 ms (§1.1 step 1) and then becomes **ER_BL_001** "接続に失敗しました。" ("connection failed"; `zSb@865681`).
  - The catch in 0xd2dc0c / 0xd465b8 classifies the failure for analytics as `bg_connect_failure` (app paused) / `auto_connect_failure` (ER_BL_010) / `connect_failure` (ER_BL_001) / `other_failure` (0xd2e080-0xd2e0f4), then rethrows.
  - **No path checks bond state, calls `createBond`/`removeBond`, or re-pairs on a reconnect failure** (§0 API surface) **[observed in code]**.
- **Recovery is manual and UI-driven**:
  - Hint pp+0x69490: "If the connection cannot be established even after retrying, reconfigure the connection with [Reconfigure connection] in the camera settings."
  - "Reconfigure connection" (pp+0x69890, 0x656640) path, handler 0xe46c9c:
    1. disconnect the current camera (0xe1f068 at 0xe46e18; this writes WLAN-off, see §5);
    2. navigate to `/reconnect` (0xe46f4c), which maps to `BleConnectionMissingPage` (route builder 0x842708: 0x842778 "/reconnect" → pp+0x8350).
  - That page tells the user to **unpair on both sides**:
    - pp+0x69530: "(1) Display the list of paired devices in the wireless communication settings of the camera and unpair this smartphone…";
    - pp+0x69528: "(2) … on the smartphone and unpair the camera…";
    - then "After canceling the Bluetooth pairing, tap [Next]" (pp+0x69520).
  - The user then re-runs `/connectionStart` → `/detect` → `/pairing` (fresh `createBond`) **[inferred from route table and copy]**.
- **When Android starts link encryption** with the stored LTK on a reconnect (at link-up, or at the first protected ATT access) is decided by the Android stack and is **[unknown]** from the app. A missing-key failure would surface as a disconnect status in `connect` or as a GATT error in a later read. Either way it ends in ER_BL_001 / ER_BL_004 **[inferred]**.

---

## 3. Disconnect and background (Q6)

1. **Explicit disconnect of the current camera** (0xe1f068; used by camera switch, the power-on branch 0xe4b36c, Reconfigure 0xe46c9c, Wi-Fi register 0xe200f4 and Import 0xe4f9d4):
   1. 0xd49450 → 0xd43cd4 writes **WLAN `9111CDD0 = 00`** (0xd419d0 at 0xd441ec / 0xd44414 with `x22+0x30` = false). On a write error it logs "ble write error skip," and continues.
   2. Then 0xe1f2f8 → 0xd431f0 → FBP disconnect.
   3. On failure it logs "切断失敗:" ("disconnect failed").
   **[observed in code]**
2. **Power off**: `B58CE84C = 00` is written only from the power button's off branch and after a firmware update (single writer 0xe4b1c8, caller closure 0x99bc5c). Disconnect never writes it **[observed in code]**.
3. **No GATT write** announces "leaving" other than WLAN-off.
4. **No disconnect on pause/background** was found. Every caller of 0xe1f068 / 0xd431f0 / 0xd439ac is one of:
   - a UI handler closure (0xe1eb00, 0xe1fab8, 0xe1fec4, 0x998014, 0xe4f058, 0xe20014);
   - a connect flow;
   - a cancel closure (0x5912dc).
   So the link stays open while the process lives. The link is not held by a foreground service; only location / transfer use `flutter_foreground_task` (ble.md §Android plugin) **[observed for the bounded caller set; absence elsewhere inferred]**.
5. **Unexpected link loss**: `DeviceManager _onBleConnectionStateChanged` (0xe855a4) shows a snackbar, and listener 0xe86418 posts "Ble接続が切断されました。" ("BLE connection was lost"). Neither reconnects; the next feature calls `ensureConnected` (ble.md §Disconnect handling, re-checked call graph).

---

## 4. Power-on from off (Q4; verifies `research/protocol/power-on-grworld.md`)

### 4.1 Verified sequence (home power button; Import / Remote differences noted)

1. **Home card power flag false** → handler 0xe49d2c, power-on branch.
   - Closure 0xe4b36c disconnects any current camera (0xe1f068 at 0xe4b4fc), then calls **`ensureConnected(VJd: device, …)`** (0xe4b754).
   - Import passes `WAi=true` (0xe47bd8). Remote passes `VAi=false` (0xe4eeb4 / 0xe4f024).
   - (power-on-grworld.md §2.2; the callers of 0xe1f068 were re-checked.)
2. **0xd2dc0c → 0xd2e93c, `oDi=false`.**
   - **No scan precedes the connect.** The device is `BluetoothDevice.fromId(stored MAC)` (§2.2 step 5).
   - On Android this becomes `BluetoothAdapter.getRemoteDevice(mac).connectGatt(app, autoConnect=false, cb, TRANSPORT_LE=2)` (`C4069h.java:1584-1634`, call at **1621**) after `m7904v()` (50 ms sleep only if a bond is in progress, `2175-2185`).
   - No PHY argument, so the 4-arg overload uses the default LE 1M. No connection priority.
   - **[observed in code]**
3. 6 s guard (§2.2 step 4). Connect: 35 s × 3, 50 ms apart; MTU 512; discovery. **No bonding call, no bond-state check** (§0) **[observed in code]**.
4. *(Import only)* WLAN `01` before the mode check (0xd2f478 precedes 0xd2f60c).
5. **0xd403b8**:
   1. Read the Camera State service (0xd40e04 at 0xd40458).
   2. If `operationMode == bleStartup` (`SFb@868061` pp+0x2a270, compare at 0xd40474-0xd40480):
      - `oDi` true → disconnect and throw ER_BL_010 (branch 0xd40488 → 0xd40894);
      - `VAi` true → **write playback** (`SFb@868041` pp+0x2a278, 0xd404c8);
      - otherwise **write capture** (`SFb@868021` pp+0x2a280, 0xd40518).
      - The write is via 0xd40ae8: Write Request, 15 s.
   3. Any other value: no write.
   **[observed in code; matches power-on-grworld.md §3 step 8]**
6. Continue on the same link: notifications including CameraPower `B58CE84C`, etc. No wait for a power notification and no reconnect logic **[observed in code]**.

### 4.2 Scan role

- `bleScanProvider` 0xd46a9c (`startScan` with `withServices [9A5ED1C5, 0F291746]`, 20 s, `la@8704f1` at 0xd46ca0; 100 ms poll `la@870441`) only drives the card state and the app-resume auto-connect.
- `0F291746` in the advert → `off` (0xd46da4-0xd46db0). The manufacturer tag 03 is not used.
- The power button does **not** depend on it: it connects whatever the scan says **[observed in code]**.

### 4.3 Android-specific dependencies

| Dependency | Detail |
|---|---|
| Identity | Connect by **stored public/identity MAC** (`lastConnectedDevice` / `device_info.remote_id`, MAC regex pp+0x2a680) |
| autoConnect | false |
| Transport | `TRANSPORT_LE` |
| PHY | default |
| Bond | the bond created at pairing |

Nothing else (no connection priority, PHY, cache clear or bond call) **[observed in code]**.

The Android stack, not the app, chooses the phone's own address (RPA vs identity), and whether the off camera's BT-only controller resolves it with the IRK from the stored bond. **[unknown]** from the app. The firmware lead is `restoreDDBDataToAic` (research/hardware-validation.md §4).

### 4.4 What this binary cannot say about the iOS app

Everything above comes from the Android build. Dart's `Platform.operatingSystem` and the `Platform.isIOS` / `isAndroid` getters carry `@pragma("vm:platform-const")` (Dart SDK `lib/io/platform.dart`, Flutter 3.47.9), so the AOT compiler folds them for the target OS and drops the other platforms' branches. The absence of iOS code in this `libapp.so` therefore says nothing about the iOS app. What is known without the iOS binary:

- `flutter_blue_plus` (listed in this build's NOTICES without a version; checked in 2.3.15) throws `android-only` from `createBond`, `removeBond`, `requestMtu` and `requestConnectionPriority` on iOS (`bluetooth_device.dart`, `!Platform.isAndroid` checks) **[observed in code]**. The iOS app therefore cannot use the explicit `createBond` step of §1.1 or the MTU 512 request (`connect(mtu:)` only acts on Android); on iOS, pairing has to be started by CoreBluetooth when the first encrypted read fails **[inferred]**, which is what our macOS client does.
- Address choice belongs to iOS `bluetoothd`. Its accept-list connect call passes a constant "not public" own-address argument where macOS passes its public-address decision; other iOS connect paths were not traced ([firmware bonding §7(a)](firmware-bonding.md#a-the-mac-cannot-reconnect-after-pairing)).

Reading the iOS Dart code needs a decrypted copy of the iOS app (App Store binaries are FairPlay-encrypted).

---

## 5. GR WORLD vs our client

> **Historical: a snapshot of GR Lab's client as of 2026-11-07.** The "Our client" column, its file and line references and the `apps/gr_lab` paths describe code that has since changed. In particular, rows 5–6 describe a bare-link wake that no longer exists. The session now wakes the camera with GR WORLD's Operation Mode write (`session.dart`, `_wakeAndWlanOn`), and `wakeCamera` was removed on 2026-11-08. For current behaviour, read the source. The GR WORLD column and the ranking reasoning still stand.

Our paths:

- `packages/gr_protocol/lib/src/ble/pairing.dart` (`pairCamera`);
- `.../session/session.dart` (`GrSession.connect` / `_connectBle` / `_reconnectBle`);
- `.../ble/wake.dart` (`wakeCamera`; removed 2026-11-08, it applied Image Sync's bare-link wake, which did not wake a GR IV HDF / 1.20 — see `research/hardware-validation.md`);
- `apps/gr_lab/lib/src/ble/universal_ble_transport.dart`;
- `apps/gr_lab/integration_test/{pair_and_pull,wake_probe}_test.dart`.

Ranked by how likely each difference explains **(a)** the reconnect encryption failure after our pairing and **(b)** the failure to connect / power on while off.

| Rank | Difference | GR WORLD (evidence) | Our client (evidence) | (a) | (b) |
|---|---|---|---|---|---|
| 1 | **Camera-side approval before "done"** | Requires the user to press [Execute Pairing]/[OK] on the camera after approving on the phone (pp+0x695b0). Proceeds only on Android `BOND_BONDED` (0xda6fd4 → 0xda70f0). Lists "did you press OK on the camera" as a failure cause (pp+0x694d8). | `pairCamera` declares success as soon as an encrypted Camera Information read works (`pairing.dart:195-203`), then registers. The hardware run did **not** press OK on the camera. No prompt or wait for it (`GrPairingStage`, `pairing.dart:54-64`). | **High**: if the camera commits the LTK/IRK only on OK, the Mac holds keys the camera discarded. That gives exactly "encryption with stored LTK fails → link drop". **[inferred]**; firmware confirmation needed. | **High**: the off-state controller loads the stored device DB (`restoreDDBDataToAic`). Without a committed bond it cannot accept or resolve the Mac **[inferred]**. |
| 2 | **Bonding trigger and single-link pairing** | One connect, unencrypted DIS reads, then explicit `createBond()` on the open link (`C4069h.java:2079`), awaited up to 90 s. No reconnects during pairing. Already bonded → no SMP at all. | No explicit bond API on macOS (`universal_ble` darwin `pair` returns notImplemented, `UniversalBlePlugin.swift:556-558`). Pairing is triggered by an insufficient-auth error on an encrypted read. On failure the client **reconnects every 15 s** and retries (`pairing.dart:192-226`). The hardware log shows link drops while the dialog was open (hardware-validation row 86). | **Medium**: repeated or interrupted SMP attempts can leave the camera with a partial or overwritten key set **[inferred]**. | Medium, via (a). |
| 3 | **Link kept after registration vs immediate disconnect** | No disconnect on pairing success (only cancel/error paths call 0xd439ac: 0xda5a0c, 0xda5f38). The link stays as the app's live connection. | `pairCamera` disconnects right after the FE3A32F8 write (`pairing.dart:248`). The test reconnects after 5-8 s (`pair_and_pull_test.dart:105`). | **Medium**: if the camera finalises the bond after the registration or OK screen while still linked, our disconnect cuts it short **[inferred]**. | Low |
| 4 | **Order: registration after bonding and post-bond reads** | FE3A32F8 is the **last** step (0xda7214), after bonded, Camera Information + WLAN reads, DB insert and firmware check. Failures are swallowed. Value = phone model. | Same order: identity read (encrypted) then `setPairedDeviceName` (`pairing.dart:195-230`). Failure aborts pairing. | Low for the order, which matches. Unknown if FE3A32F8 itself finalises the bond on the camera: ours was written before any camera OK and followed by an immediate disconnect (rows 1 and 3) **[unknown]**. | Low |
| 5 | **Power-on method** | Direct connect to the stored identity, no scan gate. Read Operation Mode `1452335A`; if `02` write `01`/`00` and keep the link (0xd403b8, 0xd404c8/0xd40518). | `GrSession.connect` scans first (`session.dart:238`). If off and `wake`, it runs Image Sync's bare connect / wait-for-drop / rescan with a 10 s connect and **never writes Operation Mode** (`session.dart:239-262`, `wake.dart:155-180`). Only `wake_probe_test.dart:44-89` does the GR WORLD sequence. | n/a | **Medium**: the method is wrong even after the link works. It cannot explain link-level timeouts, which happen before any GATT. |
| 6 | **Connect timeouts and retries** | 35 s × 3 attempts, 50 ms apart; MTU 512 requested; 15 s discovery (0xd33a74, 0x547aac, 0x547a40). | Session BLE connect 10 s (`session.dart:70,373`), pairing 20 s (`pairing.dart:118`), wake 10 s (`wake.dart:176`). `wake_probe` uses 35 s × 3 (`wake_probe_test.dart:44-49`). | Low | Low-Medium: the off-camera timeouts already occurred at 35 s × 3, so a timeout alone does not explain them. |
| 7 | **Identity used for reconnect** | Android public/identity MAC from the scan (`remote_id`), `getRemoteDevice(mac)` (`C4069h.java:1618`). Bond keyed by identity. | CoreBluetooth peripheral UUID (`retrievePeripherals`, `UniversalBlePlugin.swift:1135-1139`). macOS chooses its own address (RPA vs public). | Low | **Unknown**: depends on whether the BT-only controller resolves RPAs with the bonded IRK **[unknown]**. |
| 8 | **Bond-loss recovery** | No automatic detection. The user is told to unpair on **both** camera and phone, then re-pair (BleConnectionMissingPage via `/reconnect`, pp+0x69528/0x69530). | Similar manual need (hardware-validation row 85); no UI guidance in the client. | Diagnostic only | — |
| 9 | Connection priority, PHY, cache clear, `removeBond`, autoConnect | Never used (absent from the pool). autoConnect false (0xd337b4). | Not used; autoConnect false (`universal_ble_transport.dart:93`). | None | None |

---

## 6. Unknowns (explicit)

1. Whether the camera commits (persists) the bond only after its OK / [Execute Pairing] confirmation, or at SMP completion. GR WORLD's code cannot tell. The UI copy (pp+0x695b0, pp+0x694d8) suggests OK gates completion. Needs firmware (`bled`/`sysmgrd`) or an air capture.
2. The SMP association model and key distribution for GR III. For GR IV fw 1.20 it is observed with a Mac central (HCI trace, [firmware bonding §1](firmware-bonding.md#1-smp-configuration)): LE Secure Connections, camera IO DisplayYesNo, Numeric Comparison; the camera distributes its IRK and accepts only the central's IRK (no LinkKey). For GR III fw 2.20 the association model is found in firmware: camera IO DisplayOnly, so Passkey Entry with the camera showing the code ([GR III firmware bonding §1](firmware-bonding-gr3.md#1-smp-configuration)); its key distribution was not read. Both UI variants exist (pp+0x695b8 vs pp+0x695a0); the app code that selects one is unresolved (dispatch-only l10n getters), but the firmware fits numeric comparison for the GR IV family and passkey entry for the GR III family **[inferred]**.
3. Where the pairing Completer (WOb+0x23) is completed on success.
4. When Android starts LE encryption on a reconnect for a bonded device (at link-up or on demand), and how a camera-side key loss surfaces in FBP (disconnect status vs GATT error).
5. Whether the off camera's BT-only controller accepts a central using a resolvable private address (needs the bonded IRK), or filters by identity address only.
6. Whether the camera keeps the BLE link while booting after the Operation Mode write (power-on-grworld.md §3; unchanged).
7. The camera-side effect of the FE3A32F8 write: whether it finalises registration or bond persistence, and whether it must come after the camera OK. This includes the unbonded write in the ER_BL_007 path, whose failure is swallowed either way. Needs firmware or runtime evidence.

## 7. Corrections to existing docs (not edited here)

1. `research/protocol/ble.md` §Pairing step 2 and §Phone name registration: FE3A32F8 is written **after** bonding as the final step (0xda7214). It is written before bonding only on ER_BL_007 (0xda5d50). Write failures are swallowed (0xda607c-0xda6140).
2. `research/protocol/ble.md` §Pairing step 3: the bond stream emits the **current** state first (`getBondState`, 0xda6ee0). The 90 s `createBond` is awaited inside the `none` branch, and state `bonding` is set only after it returns (0xda7088).
3. `research/protocol/ble.md` §Pairing: add that pairing never disconnects on success. Add the Reconfigure connection → `/reconnect` → BleConnectionMissingPage (unpair both sides) recovery path.
4. `research/protocol/power-on-grworld.md` §1–§3: all re-checked addresses hold (0xd403b8 / 0xd404c8 / 0xd40518, 6 s guard 0xd2f2c0, connect by `fromId` 0xd41e08, `connectGatt(…, false, …, 2)` `C4069h.java:1621`).
