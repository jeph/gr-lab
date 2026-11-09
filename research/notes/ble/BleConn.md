# BleConn — scanning, identification, pairing/registration, connect params, reconnect, FBP plugin

Conventions: Smi = 2*n; `x22+0x20` = true, `x22+0x30` = false; Duration objects `Obj!la@…` hold microseconds (objs.txt):
la@870441 = 0x186a0 = 100 ms; la@8704a1 = 0xc350 = 50 ms; la@870531 = 0x2dc6c0 = 3 s; la@8704e1 = 0xe4e1c0 = 15 s; la@8704f1 = 0x1312d00 = 20 s; la@870591 = 0x1c9c380 = 30 s.
Unboxed int fields/args (stored with `stur x`, or passed raw on stack) are NOT Smi-tagged.

## 1. Scanning

### FBP startScan (Dart side, tree-shaken/specialised) 0xd45898
- Only optional named arg left: `"Dng"` = withServices (List<Guid>, default `[]` [pp+0x2a500]) (0xd458bc..0xd458ec). Positional x1 = timeout Duration (used at 0xd45c3c..0xd45c4c: Timer(timeout, stopScan closure 'Eng' [pp+0x2a568])).
- Builds settings object Gpb (0xd45a5c..0xd45aa4): withServices=arg, withRemoteIds/withNames/withKeywords = `[]` [pp+0x3e80], withMsd=[] , withServiceData=[], continuousUpdates=false (0x1f), continuousDivisor=1 (unboxed, 0x23), androidLegacy=false (0x2b), androidScanMode=2 (unboxed, 0x2f), androidUsesFineLocation=false (0x37).
- Method-channel map built by 0x5901ec (called from startScan impl 0xd45e7c → `invokeMethod("startScan")` 0xd45ecc): keys with_services, with_remote_ids, with_names, with_keywords (=[]), with_msd, with_service_data, `continuous_updates`=false (0x590378), `continuous_divisor`=Smi 2 → 1 (0x59038c), `android_legacy`=false (0x5903a0), `android_scan_mode`=Smi 4 → **2 = SCAN_MODE_LOW_LATENCY** (0x5903b4), `android_uses_fine_location`=false (0x5903c8).
- Before scanning it stops any running scan (`"scan"` mutex 0xd45930, `isScanning` check `_qng` 0xd45974 → stopScan 0xd34280).
- Android plugin: one ScanFilter per service UUID (`setServiceUuid`), filters are OR-ed; ScanSettings scanMode=2, phy=255 (PHY_LE_ALL_SUPPORTED), legacy=false (C4069h.java:1425-1440, 1484).

### App scan call sites (callers of 0xd45898)
| caller | purpose | withServices | timeout |
|---|---|---|---|
| 0xda4e7c (BleDeviceDetect VM `LOb`, closure 0xda4e28) | camera discovery for registration (/detect) | `[uFb.field7]` = Guid **9a5ed1c5-74cc-4c50-b5b6-66a48e7ccff1** (uFb = bleServiceProvider object, set in 0x590f10 [pp+0x270e8]) | 30 s (la@870591, 0xda4f04) |
| 0xd46a9c (oFb = bleScanProvider [pp+0x2a758]) | find last-connected camera + derive power state | `[9a5ed1c5…, 0F291746-0C80-4726-87A7-3C501FD3B4B6]` (oFb fields 0xf/0x13 set in 0x59151c) | 20 s (la@8704f1, 0xd46ca0) |
| 0xd45404 (ILb, from reconnect 0xd2e93c at 0xd2ebd8) | re-resolve a registered camera whose stored remote_id is not a MAC | none (no filter) + result filter closure 0x5905bc | 15 s (la@8704e1, 0xd45524), wrapped in Future.timeout 15 s (0x475464) |

### Discovery list (registration) — 0xda502c (LOb scanResults listener)
1. On each scanResults emission: if list empty → return (0xda5094..0xda50a0).
2. Stop scan (0xda5354 → 0xd82f90 → 0xd82fe4 → FBP stopScan 0xd4579c).
3. Filter with closure 0x82e404 → 0xda542c(ref, scanResult.advertisementData.manufacturerData) (AdvertisementData field 0x17 = manufacturerData, confirmed by toString 0xad4b80..0xad4b88).
4. Empty after filter → BleDeviceDetectUiState(scanResults: [], scanStatus: **failure**) (COb@867041, 0xda51b4). Else sort by RSSI descending (closure 0x82e38c compares ScanResult.rssi field 0xf) and emit state(success COb@867021, list) + log `"detected advertise list: "` [pp+0x36020].
- ScanStatus enum COb: scanning 0, success 1, failure 2, cancel 3. BleDeviceDetectUiState(scanResults, scanStatus) [pp+0x47d48].
- NB: scan stops at the first non-empty batch (continuousUpdates=false) **[inferred from 0xda50b0 order]**.

### Manufacturer data → model code (0xda542c)
- `manufacturerData` (Map<int companyId, List<int>>) must be non-empty; takes `values.first` (0x6cb5d0/0x4b443c) and requires length > 2; **modelCode = payload[2]** (`ldrb w0,[x2,#0x19]` = element 2 of Uint8List data at +0x17) (0xda5590..0xda55a8). Company ID is **[unknown]** (Android strips it into the map key; no comparison of the key observed in 0xda542c).
- Accept set depends on provider flag `SCf` (StateProvider<bool>, rHm; true ⇒ GR IV-family UI assets **[inferred]**):
  - SCf true: 7 or 8 → "RICOH GR IV / RICOH GR IV HDF"; 9 → "RICOH GR IV Monochrome / RICOH GR IVx" (0xda560c..0xda5674).
  - SCf false: 1 or 5 → "RICOH GR III / RICOH GR III HDF"; 3 or 6 → "RICOH GR IIIx / RICOH GR IIIx HDF" (0xda56cc..0xda5740).
  - anything else → rejected. Log `"ModelCode <n>: …"`.

### Power state from advertisement (oFb.detect 0xd46a9c) — "AdvertiseResult"
1. SharedPreferences `"lastConnectedDevice"` (0xd46af0); empty or fails MAC regex `^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$` (0x5907c4, [pp+0x2a680]) → target = null.
2. Listen scanResults (closure 0x59136c logs "scanResults: ", firstWhere remoteId == target via 0x591424); startScan(withServices: both UUIDs, timeout 20 s).
3. Poll every 100 ms (Future.delayed la@870441, 0xd46d0c) while no match and FBP isScanning; then stopScan (0xd46e54).
4. Result enum qFb (= AdvertiseResult) {initialized 0, on 1, off 2, undetected 3}:
   - no match → **undetected** (0xd46d58)
   - advertisementData.serviceUuids (field 0x1f) contains 9A5ED1C5 → **on**, else **initialized** (0xd46d7c..0xd46d94)
   - serviceUuids contains 0F291746 → **off** (overrides) (0xd46da4..0xd46db0)
   ⇒ camera advertises the Camera-Information service 9A5ED1C5 when powered on and 0F291746 when off/standby **[inferred]**.
5. Returns BleScanResultModel `_rFb`(advertiseResult, scanResult) (0xd46e20); log "Scan Detected, advertiseResult: …\nscanResult: …".

### Identification / storage
- Identity key = FBP remoteId (Android MAC string). Saved to SharedPreferences `lastConnectedDevice` = device.remoteId.str (0xd42360..0xd4237c, setString 0x58f2cc); also in reconnect (0xd2f090).
- DB table `device_info` ([pp+0x20dc8], 0x52ce74): id, model_name, model_type, device_name, bd_name, remote_id, serial_no, firmware_version, ssid, bssid, security, password, is_time_sync, created_at, updated_at. Registration inserts it (0xda91e4, log "DB保存成功, ID: ").
- Model name normalised by stripping "RICOH" prefix (log "モデル名修正 a -> b", 0xda7ee8..0xda7f6c).

## 2. Pairing / registration (BleDevicePairingViewModel `WOb`, start 0xda58b0)
States: BlePairingStatus NOb {none 0, connected 1, bonding 2, success 3, error 4}; BleErrorStatus OOb {none 0, modelTypeError 1, firmwareError 2, registerError 4, connectError 5, cancelError 6} (value 3 not present); result TLb {success 0, connectFailure 1, unsupportedFirmware 2, otherFailure 5}.

1. `FSb.connect(true, Nod: device)` 0xd41ce8 (0xda59b4) — positional bool true = "check firmware".
   - Retry wrapper 0x5479e4/0xd1b0f4: **max 3 attempts** (OCi default unboxed 3, 0x547aac), **fixed 50 ms delay** (NCi default la@8704a1, 0x547a40); aborts immediately on FlutterBluePlusException code 10 = connectionCanceled (0xd1b308..0xd1b31c); logs "#START, device: " (0x58d96c) / "#ON_EXCEPTION, " (0x58d90c).
   - Each attempt = uFb.connect 0xd42080 (see §3).
2. If the user already cancelled (errorStatus == cancelError) → disconnect 0xd439ac and stop (0xda59e4..0xda5a2c).
3. state(connected, none); subscribe to FBP `bondState` stream (0xda6c34, FBP getBondState/bond events; kpb enum) with listener 0x82eedc → 0xda6fa4:
   - bondState none (0) → **createBond** 0xda965c (FBP "createBond", timeout **90 s** = raw 0x5a at 0xda97cc; waits for bondState bonded gqb@868f31; error "Failed to create bond. ") then state(bonding) (NOb@866fc1).
   - bonding (1) → log only.
   - bonded (2) → cancel bond subscription, run post-bond 0xda7474, state(success) (NOb@866fa1) else error.
   - If already bonded at connect time the first event is "bonded" → no createBond.
4. Post-bond 0xda7474 (GATT ops):
   a. Camera Information reads 0xd3e248 → 0xd3e3ac (svc 9A5ED1C5: manufacturer, BT name, BT MAC, firmware, model, serial; read 0xd30588).
   b. WLAN info reads 0xd3ee8c → 0xd3eff0 (svc F37F568F family gJb, 6 reads, security enum qJb).
   c. GR IV only: restore/write pending camera name (`pendingCameraNames`, 0xd3fdf8 "復元時のカメラ名書き込み") .
   d. Model check: expected family vs read model → "ModelType error: " → modelTypeError; firmware min check → "FirmwareVersion error: " → firmwareError.
   e. GR IV: firmware server check (0xda8ec4, cloud — out of scope).
   f. DB insert device_info (0xda91e4); TLb.success → analytics/route 0xda6574.
   Failure → registerError / TLb.otherFailure (0xda8ae4, 0xda8b4c).
   (Sibling note: 0xda5fd4 writes the phone name to 0F291746/FE3A32F8 after connect.)
5. Exceptions in step 1: zSb@865621 (ER_BL_007 unsupported FW) → firmwareError + TLb.unsupportedFirmware; other → connectError + TLb.connectFailure; then disconnect 0xd439ac (0xda5d14..0xda5f44).
- UI copy (l10n, mapping to model **[inferred]**): "…enter the authentication code displayed on the camera." [pp+0x695a0] (passkey entry), "…make sure that the authentication codes on the camera and the app are the same, then allow pairing" [pp+0x695b8] (numeric comparison), "Next, tap [Execute Pairing] on the camera, or press the [OK] button." [pp+0x695b0]. Pairing observed is Android bonding via FBP createBond; no app-level passkey/PIN handling observed in the inspected pairing path (0xda58b0/0xda6fa4/0xda965c) **[inferred: absence]**.

## 3. Connect parameters

### uFb.connect(device, ref?, bool checkFirmware) 0xd42080
1. Read zRi provider (wFb state) field7 = currently connected device; if it is connected (0xd30a8c: connectionState.first == connected) → disconnect it and wait for `disconnected` (0xd42c60 → 0xd42d30, closure 0x58ee10).
2. FBP `connect(device)` 0xd33764 with **no named args** (ArgDesc [pp+0x140], 0xd42188).
3. Wait `connectionState` == connected (closure 0x58ee30), log "connect device: … connection state: ".
4. discoverServices 0xd42790→0xd427ec (FBP timeout **15 s**, raw 0xf at 0xd42944); FBP then auto-subscribes Service Changed 1801/2A05 if present (0x58eb24, 0xd42a44).
5. If checkFirmware: read DIS model 0xd42668 and firmware 0xd42424 (180A), `0x54b6c0` minimum: GR IV "0.00", GR IIIx "1.50", GR III "2.00", GR II "3.00" → else update state + throw ER_BL_007 (0xd423f0).
6. Update state (0x58da64 "updateState, device: …"), save `lastConnectedDevice`.

### FBP connect 0xd33764 (Dart)
- Named "Jmg" = autoConnect, default false (0xd337b4); "Kmg" = mtu, default Smi 0x400 = **512** (0xd33808).
- Method "connect" map: remote_id + auto_connect (0x577734, [pp+0x29450]).
- Waits for connected with **35 s** timeout (raw 0x23 at 0xd33a74 → fbpTimeout) only when autoConnect=false; on timeout closure 0xd34044 "[FBP] connection timeout" → disconnect; error code 10 "connection canceled" (0xd33b28..0xd33b6c).
- Then, if connected (0x577db8) and mtu != null → requestMtu 0xd33c6c: predelay 0.35 s → Future.delayed **350 ms** ([pp+0x29458]=0.35, [pp+0x29460]=350.0, ×1000 µs at 0xd33d20), request mtu **512** (unboxed 0x200 at 0xd33d78), timeout **15 s** (raw 0xf at 0xd33ea0).
- The only other caller 0x576ea0 is FBP's internal auto-reconnect (on adapter on) with Jmg=true/Kmg=null; the app never sets autoConnect=true, so it is dead in practice **[inferred]**.
- requestConnectionPriority / setPreferredPhy: no app calls found **[not observed]**.
- FBP disconnect 0xd42d30 → 0xd43018 (Android only, 0x5c1f7c): if < **2000 ms** (0x1e8480 µs, logged as Smi 0xfa0) since the device's last connect timestamp, delays the remainder ("[FBP] disconnect: enforcing 2000ms disconnect gap, delaying N ms", 0xd43094..0xd431cc); then invokeMethod "disconnect" and waits for disconnected (fbpTimeout).
- App disconnect 0xd439ac: throws ArgumentError "disconnection target is null" if no device; failures logged "BLE切断失敗: " (0xe1f2f8).

## 4. Auto-connect / reconnect (ILb = deviceManager)
- Entry point ILb.ensureConnected 0xd2b990 (named args VAi/VJd/WAi/eLd/hLd; called on demand by many features, e.g. 0xd2b5b4, 0xdd140c, 0xe07338): sets a "connecting" flag (0x56d068(true), 0xd2bc00); if no explicit target → reads `lastConnectedDevice` (0xd2ac44) and runs the auto path 0xd465b8 (`oDi: true`, 0xd2bd80); else explicit path 0xd2dc0c (0xd2be20); afterwards 0xd2a2b8/0xd1d1f4; clears the flag (0xd2c1a4). Errors map to ER_BL_010 autoConnect / ER_BL_009 cancellation / ER_BL_001 connect (0xd2c138..0xd2c228). No periodic/timer reconnect loop was found: reconnects are on-demand, single-shot, with only the 3×50 ms retry inside FSb.connect **[inferred: absence]**.
- 0xd465b8 (auto path) = same as 0xd2dc0c but without the device_info pre-check; same analytics failure names (0xd46924..0xd469a0).
- Disconnect handling: DeviceManager `_onBleConnectionStateChanged` 0xe855a4 (log [pp+0x52250]); on next == disconnected (fLb@8679c1) and app not paused and flag YBi → in-app snackbar (TCb, 3 s la@870531) via 0xbf4988, then 0xd44f70. Listener 0xe86418 logs "ble: isIgnore: …, next: …", returns early when its isIgnore flag (state field 0x13) is true, otherwise posts the local notification "Ble接続が切断されました。" [pp+0x51ee0]. No automatic reconnect is triggered there **[inferred]**.
- ILb.connect 0xd2dc0c (caller 0xd2b990): cancels any pending CancelableOperation (0x591010); looks up registered device_info by remote id (deviceInfoRepositoryProvider, closure 0x551888); missing → ER_BL_001 connectException; runs 0xd2e93c as CancelableOperation (onCancel 0x5912bc → 0xd46310); cancelled → ER_BL_009. Errors are logged as analytics `bg_connect_failure` (app paused, isPaused [pp+0x274c8]), `auto_connect_failure` (ER_BL_010), `connect_failure` (ER_BL_001), `other_failure` (0xd2e080..0xd2e0f4).
- 0xd2e93c sequence:
  1. If stored remote_id not MAC-like → unfiltered 15 s scan 0xd45404 to resolve, log "remoteId変換: a -> b", update DB.
  2. Save lastConnectedDevice; disconnect other connected cameras (0xd431f0) **[inferred]**.
  3. **6 s guard**: reads timestamp provider ZBi; elapsed ms < 6000 (0x1770, 0xd2f2c0) → Future.delayed(6000-elapsed ms) (log closure 0x590c00 "delay a + b"); else log "6秒経過済み". Timestamp meaning **[unknown]** (sibling: time since BLE connect).
  4. FSb.connect(false, MFd: remote_id) 0xd2f40c → retries 3×/50 ms, no firmware check.
  5. Post-connect: 0xd419d0, 0xd403b8 (operation mode SFb), 0xd3fdf8 pending names, 0xd3f640/0xd3e874 (Camera Info / WLAN reads → DB), 0xd1e41c, firmware fetch 0xd38644 + 0x54b6c0, notification subscribe-all 0xd30c30, geotag/location 0xd46f20; analytics "success". "デバイス未検出: " → ER_BL_001.

## 5. flutter_blue_plus Android plugin (jadx p326m6/C4069h.java)
- startScan: permissions BLUETOOTH_SCAN (+FINE_LOCATION if flag) + BLUETOOTH_CONNECT (1399-1404); ScanSettings scanMode from map, setPhy(255), setLegacy (1425-1429); filters per service UUID / remote id / name / msd / service data (1430-1495); startScan(filters, settings, cb) (1484).
- connect: `remoteDevice.connectGatt(ctx, autoConnect, cb, 2 /*TRANSPORT_LE*/)` (1621); autoConnect devices kept in map f13644O (1627-1632); "already connecting/connected" short-circuits (1607-1615). Each GATT op first calls m7904v() which waits 50 ms if a bond is in progress (2175-2184).
- disconnect: cancels pending connect → close + synthetic OnConnectionStateChanged code 23789258 "connection canceled" (1642-1680); onConnectionStateChange closes gatt unless autoconnect (C4067f.java:183-187).
- setNotifyValue: setCharacteristicNotification, then CCCD 2902 write: NOTIFY (01 00) if notify supported, INDICATE (02 00) if only indicate, or forced with force_indications (1912-1973).
- requestMtu → gatt.requestMtu(mtu) (1982-1997); requestConnectionPriority (2011-2026); createBond: returns false if already bonded, true if bonding (2069-2087); getBondState maps 11→1, 12→2 (2059-2068); removeBond via reflection (2088-2098); clearGattCache via reflected `refresh` (2099-2112).

## 6. Foreground service / manifest
- Manifest perms: ACCESS_FINE/COARSE_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION, FOREGROUND_SERVICE_DATA_SYNC, POST_NOTIFICATIONS, WAKE_LOCK, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, RECEIVE_BOOT_COMPLETED (AndroidManifest.xml:15-24).
- geolocator Android settings (0x5923cc: forceLocationManager, timeInterval, foregroundNotificationConfig, useMSLAltitude; 0x5924f0: enableWakeLock, enableWifiLock, notificationTitle/Icon/Text, channel name, setOngoing, color) built in 0xd46f20 (location tracking for geotags).
- flutter_foreground_task options (0x835dec: taskEventAction, autoRunOnBoot, autoRunOnMyPackageReplaced, allowWakeLock, allowWifiLock, allowAutoRestart; 0x83ae34 startService with serviceId/serviceTypes/notification…), started from 0xdc143c (reservation-transfer task path 0xdc1024 "FGS error: "). Values not yet decoded **[unknown]**.

## Open questions (for a sniff)
- Company ID and full layout of the manufacturer-specific AD (only byte[2] = model code is used).
- Whether 0F291746 is advertised only when the camera is off (power-on wake path).
- Exact pairing method per model (passkey entry vs numeric comparison) and whether GATT reads before bonding are rejected (insufficient authentication).
- Negotiated MTU (app requests 512 after a 350 ms predelay).
- Meaning of ZBi timestamp in the 6 s guard (wait happens before the FSb.connect at 0xd2f40c).
- Whether the camera requires bonding before reads of 9A5ED1C5 / F37F568F (app reads them only after bonded during registration).
