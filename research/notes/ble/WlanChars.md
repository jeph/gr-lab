# WLAN Control service (F37F568F-9071-445D-A938-5441F2E82399) + Wi-Fi enable flow — notes (WlanChars)

Static analysis of libapp.so (dis.txt addresses). Smi = 2n. In Dart AOT, `true` = null+0x20 and `false` = null+0x30 (`add xN, x22, #0x20/#0x30`).

Addendum: second WLAN-on path (background/auto connect). 0xd2e93c is called from 0xd2dc0c and 0xd465b8, which use the strings "bg_connect_failure", "auto_connect_failure" and "connect_failure".
1. **6-second elapsed-time gate:** if the elapsed time is < 6000 ms (`mov x17,#0x1770` compare at 0xd2f2c0), the app delays for the remainder (Duration ms, 0xd2f2dc..0xd2f330, awaited at 0xd2f330). It then logs "6秒経過済み: " ("6 s already elapsed") at 0xd2f348. The timer baseline is **[unknown]** (the value comes from 0x58ee50 at 0xd2f260).
2. **BLE connect** (after the gate): 0xd41ce8 is called at 0xd2f40c. It does the connect, 0xd42080 ("connect device: … connection state:"), the min-firmware check 0x54b6c0, and saves lastConnectedDevice.
3. **Conditional WLAN-on:** the result is checked at 0xd2f42c/0xd2f43c; the exact condition is **[unknown]**. On that path the app writes hJb ← 0x01 at 0xd2f478 (0xd419d0, 3 attempts / 50 ms).
4. The Wi-Fi join after this is **[inferred]** to go through the same connectToWifi MethodChannel; not traced from 0xd2f478.

## 1. How the characteristic classes work (generic path)
- Characteristic classes hJb..mJb (family gJb, service class THb 0x650) are paired with FBP characteristics by finder 0x58d120 / builder 0x58d450 (see context.md).
- Each class has two virtual factory methods:
  - selector `cid-0xfff` = **read command factory**. The gJb implementations are at 0xcb32b0..0xcb33f0. Each allocates a command object `{+7 = dpb characteristic, +0xb = yFb.read (Obj!yFb@8680c1, value 0)}` (allocations bJb, eJb, cJb, fJb, dJb, aJb).
  - selector `cid-0xfd7` = **write command factory**. The gJb implementations are at 0xcb2cf0..0xcb30cc. Each allocates `{+7 = characteristic, +0xb = yFb.write (Obj!yFb@8680a1, value 1), +0xf = param}`. A setter type-checks the param: bJb needs bool (0xcb2d34), eJb needs String (0xcb2e0c), cJb needs String (0xcb2f00), fJb needs bool (0xcb2ff4), dJb needs qJb (0xcb30cc). **aJb has no write factory, so mJb is read-only.**
- Commands are executed by 0xd30588(service, cmd). It takes the service mutex (0x56ac88), calls virtual `execute` (selector +0xd6a7), then unlocks (0x569ae8). The `execute` dispatchers switch on `cmd.+0xb`: 0 → read impl, 1 → write impl, anything else → UnsupportedError("… command is not supported").
- The gJb command dispatchers, in descending command cid:
  - aJb 0x6a5 → 0xe627c8 (bool read only)
  - bJb 0x6a4 → 0xe62930 (bool read 0xe5d6a4 / write 0xe5ec0c)
  - cJb 0x6a3 → 0xe62a9c (String read 0xe5c6ac / write 0xe5d340)
  - dJb 0x6a2 → 0xe62c08 (qJb read 0xe62e78 / write 0xe62d74)
  - eJb 0x6a1 → 0xe62f30 (String)
  - fJb 0x6a0 → 0xe6309c (bool)
- Writes go through FBP `writeCharacteristic` 0xe5c094. **[unknown]** whether the app uses withResponse or withoutResponse for these writes; this lives in 0xe5c094 / the BLE-core slice.
- Retry wrapper 0x5479e4 (used by every gJb read/write wrapper). Named params NCi/OCi/PCi/QCi/RCi. Defaults: delay NCi = Obj!la@8704a1 = 0xc350 µs = **50 ms**, OCi = **3** (literal `mov x5,#3` at 0x547aac). **[inferred]** semantics: 3 attempts with 50 ms delay. Once retries are exhausted, a write throws zSb ER_BL_005 "WriteError" (Obj!zSb@8655c1) and a read throws ER_BL_004 "ReadError" (Obj!zSb@865601).

### Wire encodings (exact)
- **bool read** 0xe5d6a4: `getInt8(byte[0])` via 0x5794c0 (ByteData from bytes, signed int8 at offset 0). Result is `true` iff the value == 1.
- **bool write** 0xe5ec0c: writes a 1-byte list: `[0x01]` for true, `[0x00]` for false (Smi 2 = 1 stored at 0xe5ec70; `stur wzr` = 0 at 0xe5ecd0).
- **String read** 0xe5c6ac: `utf8.decode(bytes)` (Obj!dg@85fdb1, allowMalformed=false, via 0xb3afb8), then `replaceAll([pp+0x6e30], "")` (0x4864b8). blutter prints [pp+0x6e30] as an empty string, so it is **[inferred]** to be "\u0000" (NUL padding stripped).
- **String write** 0xe5d340: `utf8.encode(s)` (Obj!eg@85fe91 via 0xb58618), written raw. There is no length prefix and no terminator.
- **qJb (security) write** 0xe62d74: 1 byte. 0xa12fd4 builds `Int8List(1)` with `strb` of `qJb.off_14`, so wpa2 = 0x00, wpa3 = 0x01, transition = 0x02.
- **qJb read** 0xe62e78: getInt8(byte0) → 0x754658 maps 0 → wpa2, 1 → wpa3, 2 → transition; any other value throws. Its log text says "decode bool:" (copy-paste in the app).
- qJb enum (objs.txt 55704+): wpa2 {0, "WPA2"}, wpa3 {1, "WPA3"}, transition {2, "Transition"}. UI strings include "WPA2/WPA3 Transition Mode".

## 2. Characteristic table
The UUID→class mapping comes from the getter block 0xad42b0..0xad42ec (descending cid). It is **confirmed independently** by the read-all function 0xd3eff0: its explicit cid compares read hJb→bool, iJb→String, jJb→String, kJb→bool, lJb→qJb, mJb→bool. That matches the factory/dispatcher types in the same order.

| class (cid) | UUID | model field (_oJb offset) | Dart type | ops (app) | encoding / values |
|---|---|---|---|---|---|
| hJb 0x630 | 9111CDD0-9F01-45C4-A2D4-E09E8FB0424D | `networkType` (+7) | bool | read (0xd3eff0); write 0xd41b3c (cid closure 0x58d8dc) via retry wrapper 0xd419d0 | 1 byte: **0x01 = turn camera WLAN ON**, **0x00 = turn WLAN OFF** (see §3/§4). The toString label is "networkType" but the app uses it as the WLAN on/off switch. |
| iJb 0x62f | 90638E5A-E77D-409D-B550-78F7E1CA5AB4 | `ssid` (+0xb) | String | read; write 0xe27918 (closure 0x94a90c) via 0xe277ac | raw UTF-8 |
| jJb 0x62e | 0F38279C-FE9E-461B-8596-81287E8C9A81 | `passphrase` (+0xf) | String | read; write 0xe26a3c (closure 0x94a884) via 0xe268d0 | raw UTF-8 |
| kJb 0x62d | C4B7DFC0-80FD-4223-B132-B7D25A59CF85 | `wlanFreq` (+0x13) | bool | read; write 0xe25b10 (closure 0x94a7fc) via 0xe259a4 | 1 byte: **0x01 = 5 GHz, 0x00 = 2.4 GHz**. Evidence: the stored record field +0x3b = (bool?1:0) at 0xd3eb38/0xe2524c, and the analytics use `+0x3b==1 ? "5GHz" : "2.4GHz"` (0xdd958c). Before writing, 0xe25b10 does an extra existence check and throws ER_BL_005 if it fails (0xe25c18..0xe25c48). |
| lJb 0x62c | 63BC8463-228F-4698-B30D-FAF8E3D7BD88 | `security` (+0x17) | qJb | read; write 0xe24c3c (closure 0x94a774) via 0xe24ad0 | 1 byte: 0 = WPA2, 1 = WPA3, 2 = WPA2/WPA3 transition |
| mJb 0x62b | 460828AC-94EB-4EDF-9BB0-D31E75F2B165 | `available5GHz` (+0x1b) | bool | read only (0xd3eff0; no write factory) | 1 byte: 0x01 = camera supports 5 GHz |

- Model: `_oJb` (cid 0x629), allocated at 0xd3f44c. toString at 0xad6140 prints "WLANControlCommandModel(networkType:, ssid:, passphrase:, wlanFreq:, security:, available5GHz:)" with fields +7..+0x1b.
- Read-all defaults when a characteristic is not present (0xd3f0f8..0xd3f128): bools = false, ssid = "", pass = "", security = wpa2.
- Read-all 0xd3eff0 is called via the retry wrapper 0xd3ee8c. That wrapper is called from 0xd3e874 (device-record refresh) and 0xda7474.
- No notify is used on this service: there are no setNotifyValue calls on gJb classes, and only plain reads/writes reference them. **[inferred]** from the xrefs above.

## 3. Wi-Fi enable + join flow (ILb, library Arn; entry 0xdd91ac)
Callers of 0xdd91ac:
- 0xdd8fdc — firmware-update `_wifiConnect`
- 0xe07338, 0xe47bd8, 0xe49658, 0xe499a0 — other features; closures only, **[unknown]** which screens

Steps:
1. **0xdd91ac** — optional cancel of the prior operation (0x591010). Looks up the registered device record (closure 0x551888); if none, throws ER_BL_001 (Obj!zSb@865681).
2. **VPN check** — connectivity list (0x857100→0x5a7f8c) `.contains(Wxa.vpn)`. If true, wait **1 s** (Obj!la@870401 = 1,000,000 µs, 0xdd9724), then throw ER_WF_010 VPNError (lTb@865351).
3. **Choose path by record field +0xf** (0x58f270):
   - 0 → BTb → 0xdda950: no BLE WLAN-on. It runs 0xd43cd4 (BLE side, writes hJb=false) and then joins with the stored creds. **[inferred]** this is the non-BLE / older-model path.
   - 1 → CTb, or 2 → DTb → **0xdd9fe0** (BLE path below).
   - The path is wrapped in a CancelableOperation (0x56f82c, closure 0x857390) stored at ILb+0x1b and awaited.
4. **0xdd9fe0 — BLE path:**
   1. 0xd3e874: BLE **read all 6 WLAN characteristics** (0xd3ee8c → 0xd3eff0, retry 3×/50 ms). Updates the stored device record `_qEb`: +0x2b = ssid, +0x37 = passphrase, +0x43 = security int (qJb.off_14), +0x3b = wlanFreq (1/0), +0x4b = available5GHz (1/0), +0x63 = now in seconds; saved via 0xd1e96c. networkType is not stored.
   2. Save pref "lastConnectedDevice" (0x58f2cc, [pp+0x27d30]).
   3. **BLE write hJb ← 0x01 (WLAN ON)**: 0xdda19c `add x2,x22,#0x20` (true) → 0xd419d0 → 0xd41b3c. Same 3-attempt retry; a failure throws ER_BL_005.
   4. **No wait or notify** between the WLAN-on write and the join. The app immediately calls 0xdda5c4.
   5. 0xdda5c4 — MethodChannel `com.pavct.jp.grapp/wifiConnection` (Obj!MethodChannel@845371) `connectToWifi` with args {ssid: rec+0x2b, password: rec+0x37, serialNo: rec+0x23, model: rec+0xb, bdName: rec+0x1b, securityType: rec+0x43 (int)}.
      - Returns bool. A non-true result throws ER_WF_001 ConnectError (lTb@865331).
      - A PlatformException whose message contains "NEHotspotConfigurationErrorDomain Code=8" throws ER_WF_007 InternalError (lTb@8652f1).
      - A message containing "timeout" throws ER_WF_009 ConnectTimeoutError (lTb@865311).
      - Anything else throws ER_WF_001.
   6. Android side: p085J6/AbstractActivityC0655d.java:582-664. securityType 0 → setWpa2Passphrase; 1 or 2 → setWpa3Passphrase (lines 643-649); requestNetwork; **60 s timeout** (postDelayed 60000L, line 658; RunnableC4802a "TIMEOUT … try WPA2" fallback). Wi-Fi join details belong to another slice.
   7. 0xd1d508: post-join verification over Wi-Fi (HTTP/model/firmware checks, references "GR III"/"GR IV"/"GR II", calls min-firmware check 0x54b6c0). If it returns not-true, throws ER_WF_003 GetError (lTb@8652b1). HTTP slice.
   8. Update connection state (closure 0x54bbe4 / 0xd2790c under the ILb mutex).
5. **Analytics** (oMb, 0xd2e194):
   - Success → result "success", band "5GHz"/"2.4GHz" from rec+0x3b, security display name (qJb.off_1c via List<qJb> [pp+0x2b130] indexed by rec+0x43), app "foreground"/"background".
   - Failure → connect_failure / vpn_failure / connect_timeout_failure / get_failure / wlan_router_failure / ios_internal_error / other_failure (0xdd9b54..0xdd9cac).

### Firmware-update wrapper steps (MQb, library Lsn; these are the "stepN_*" strings)
1. **step2 = `_wifiConnect`** (0xdd3c14). Optional named arg IZi: if set, waits 1 s (la@870401). Then 0xdd809c: MethodChannel `checkWifiState` (WifiManager.isWifiEnabled), permission/location handling, then closure 0xdd8fdc → ILb 0xdd91ac (above). Failures produce code `_NTb.+7`:
   - code **1** if the exception == ER_BL_005 WriteError, i.e. the BLE WLAN-on write failed (0xdd8c3c..0xdd8c58).
   - code **2** if the exception class cid == 0x21a2 (a BLE exception class, mapped to ZPb.bleError in 0xdacd68).
   - otherwise **-1** ("wifi接続に失敗しました。7").
   - 0xdd4000..0xdd40ac then reads capture mode via 0xdd7d90 (BLE read with retry, closure 0x8560bc) and names the failure:
     - code 1 and mode == aIb.video (Obj!aIb@867e61, wire 2) → "step2_ble_wlan_on_video_failure". The UI text says the camera refuses WLAN in movie mode or on a USB connection.
     - code 1, other mode → "step2_ble_wlan_on_failure"
     - code 2 → "step2_ble_connect_failure"
     - otherwise → "step2_wlan_connect_failure"
2. **step3 = `_bleConnect`** (0xdd4f54 → 0xdd63cc, 0xdd5bf4). Failure → "step3_ble_connect_failure". BLE-connection slice.
3. **step4 = `_firmwareUpdate`** (0xdd5398 → 0xdd5740). Waits **200 ms** (la@870561 = 0x30d40 µs), then 0xdd59f0 / 0xdd5a44 (a WFb-family characteristic chosen by closure 0x854800, executed via 0xd30588). "step4_ble_notify_not_received" is logged when the result is not received. This belongs to the firmware slice (WFb family, FirmwareUpdateResult notify parser 0x57d6f4); not WLAN-service.

## 4. Turning WLAN OFF / Wi-Fi disconnect
- hJb ← 0x00 (false) is written at 0xd441ec and 0xd44414 (inside 0xd43cd4, which logs "ble write error skip, " and ignores write errors), and at 0xd45348, 0xd453cc (0xd45260), 0xe2361c (0xe23268), 0xe27f00 (0xe27bc8), 0xe2b298 (0xe2b0ac), 0xe56f0c (0xe56dbc).
- hJb ← 0x01 (true) is written only at 0xdda1a0 (0xdd9fe0) and 0xd2f478 (0xd2e93c).

## 5. Changing WLAN settings (camera settings screen; SPb / "cameraSettingsViewModelProvider")
- UI state: CameraSettingsUiState (toString 0xad9914) has fields ssid, password, wlanFrequency (VPb = WlanFrequencyButtonState {twoPointFourGHz 0, fiveGHz 1}; name mapping [inferred: toString order 0xb30ac4]), security (qJb), available5GHz.
- Write status enum KPb {none 0, writing 1, canceling 2} = CameraSettingStatus [inferred].
- Initial defaults (0xa0fc70): VPb.twoPointFourGHz, qJb.wpa2.
- Full apply = **0xe23268** (caller 0xe22814). State → KPb.writing, then in order:
  1. write SSID: 0xe26be8 → iJb (log "Update SSID: "), DB record updated
  2. write passphrase: 0xe25d08 → jJb ("Update Password: ")
  3. write wlanFreq bool: 0xe24dec → kJb ("write wlanFrequency" on error)
  4. write security qJb: 0xe23f24 → lJb (its error log also says "write wlanFrequency")
  5. 0xd43cd4: phone-side Wi-Fi disconnect, also writes hJb=0x00 with errors ignored
  6. **write hJb ← 0x00** (WLAN OFF) at 0xe2361c
  7. State → KPb.none
  - This matches the UI text "Changing the settings will turn off the WLAN function of the camera" (0x68a70c) and "The WLAN communication settings have been changed." (0xcb04d4).
  - Byte values: ssid/pass raw UTF-8, freq 0x00/0x01, security 0x00/0x01/0x02.
- Reduced apply = **0xe27bc8** (caller 0xe22814): SSID + passphrase only, then 0xd43cd4, then hJb ← 0x00. **[inferred]** used for models without the freq/security characteristics (GR III/IIIx?). Branch condition in 0xe22814 is **[unknown]**.
- The 5 GHz button is presumably gated by available5GHz (mJb). **[inferred]**; the UI code at 0x948728 builds the "5GHz"/"2.4GHz" and WPA2/WPA3 option rows.
- SSID/password validation rules (length/charset): **[unknown]**, not traced.

## 6. WifiDeviceRegister (Wi-Fi-only registration UI)
- WifiDeviceRegisterUiState(registerSsid, status, errorStatus) — toString 0xad9880.
- WifiRegisterStatus = mPb {none 0, getting 1, registering 2, success 4, error 5}. Value 3 is not in the const pool.
- ErrorStatus = nPb {none 0, firmwareError 2, getError 3, registerError 4, cancelError 5}.
- Name↔enum mapping is [inferred] from toString order (0xb30998 / 0xb309fc) vs obfuscated-name order.
- This page uses the phone's current SSID (WifiDeviceDetectUiState(connectedSsid)), not BLE WLAN chars. **[inferred]**; not traced further.

## Open questions (sniff should confirm)
1. Write type (ATT Write Request vs Write Command) for gJb characteristics; properties of each characteristic.
2. Does the camera need time between hJb=0x01 and the AP being up? The app sends no wait/notify and relies on the Android 60 s requestNetwork timeout.
3. Exact read payload lengths: are SSID/passphrase NUL-padded fixed-length fields? Is pp+0x6e30 really "\u0000"?
4. Does writing hJb=0x00 reboot or disable the AP immediately? Does the camera apply ssid/pass/freq/security only on the next WLAN-on?
5. Is the hJb value really a pure on/off bool? The model calls it "networkType". Check what a read returns while WLAN is on vs off.
6. Behaviour when WLAN-on is refused (movie mode / USB): ATT error code returned by the camera?
7. kJb existence check in 0xe25b10: which camera models lack kJb/lJb/mJb (GR III/IIIx vs GR IV)?
