# Camera service 9F00F387 (iIb family) + Camera Information 9A5ED1C5 + DIS — notes (CamSvcChars)

All addresses = libapp.so isolate code (work/dis/dis.txt); `[pp+0x…]` = object pool. Enum values from work/cs/blutter_out/objs.txt (~line 55600-56200: `off_8` = Dart index, `off_14` = wire value).

## 0. Corrections to context.md
- **kIb (B29E6DE3) is DRIVE MODE, not battery.** Its notify parser EHb closure 0x579188 decodes byte0 → vIb via 0x579368 and logs `"driveMode update: "` [pp+0x29b38] (0x579250). The setup fn 0xd35014 merely reuses the error string `"BatteryNotify error: "` (copy/paste in app). Real battery = ZFb (WFb family, 0xd377fc / CHb parser 0x57d334, same error string).
- **nIb (B5589C08) is CAPTURE STATUS (capturing + countdown), not capture mode**; **mIb (78009238) is CAPTURE MODE (image/video)**. Both setup fns (0xd354ac nIb, 0xd35944 mIb) reuse `"CaptureModeNotify error: "`.
- lIb (A3C51525) = SHOOTING (exposure) MODE + user-mode slot ("ShootingNotifier error: " 0xd31250).

## 1. Architecture (how the app talks to these characteristics)
- Each iIb char class has two virtual factory methods returning a *command object*: write-factory selector **-0xe6d** (call sites e.g. 0xe53140, 0xe53444, 0xe53a6c, 0xe346bc, 0xe34e6c) and read-factory selector **+0xcbc3** (0xe33e60, 0xe33a70, 0xdd7ef4). Command classes (cids 0x6a6..0x6ac): bIb, cIb, dIb, eIb, fIb, gIb, hIb. Command fields: +7 = FBP characteristic (dpb), +0xb = op `yFb` {read=0 [pp+0x34c70], write=1 [pp+0x2a798]}, +0xf = parameter.
- Write factories (each allocates cmd with op=write, type-checks param): 0xcb0cec dIb(List<_Enum>), 0xcb0dc8 cIb(vIb), 0xcb0ec0 XIb-param **removed by TFA** ("Attempt to execute code removed by Dart AOT compiler" [pp+0x2188]), 0xcb0f18 + 0xcb0f70 aIb-param **removed by TFA**, 0xcb0fc8 eIb(WIb), 0xcb10c0 hIb(String), 0xcb11b4 gIb(List<int>).
- Read factories (op=read): 0xa14920 dIb, 0xa14954 cIb, 0xa14988 fIb, 0xa149bc bIb, 0xa149f0 eIb, 0xa14a24 hIb, 0xa14a58 gIb.
- Mapping char→command: both factory lists are laid out in char-class order j,k,l,m,n,o,{p,q,r},{s,t,u} and agree with every independently confirmed pair (jIb write takes [UIb,VIb] = dIb; kIb write takes vIb = cIb; oIb write takes WIb = eIb; p/q/r writes use <String>; s/t/u use <List<int>>; mIb read is used by 0xdd7ef4 whose result is compared to aIb = bIb). **[inferred: code-layout order]** for lIb↔fIb/XIb.
- Command `execute()` impls (switch on op index: 0 read / 1 write / else throw `"<op> command is not supported"` [pp+0x40f40]): bIb 0xe612d8, cIb 0xe6156c, dIb 0xe618b0, eIb 0xe61c6c, fIb 0xe61fac, gIb 0xe62240, hIb 0xe62494 (address order = cid order).
- Execution: caller builds pairs via finder 0x578a18 (WHb svc, builder 0x578cfc), picks the char with a cid-compare closure, calls the factory, then `0xd30588(mutex, cmd)` = lock (0x56ac88) → `cmd.execute<T>()` (selector 0xd6a7) → unlock (0x569ae8). Writes go through FBP write 0xe5c094 (with response — `[unknown]` withoutResponse flag; owned by BleConn slice). Write commands log `"write params: …, value: …"`; null param → UnsupportedError "write parameter is null, please call the setParameter() before writing" [pp+0x40f50].
- Common decoders: `0x5794c0` = `Uint8List.fromList(bytes).buffer.asByteData().getInt8(0)` (signed byte 0, `ldrsb` at 0x57961c). `0xa12fd4(v)` = `Int8List(1)..[0]=v` → `asUint8List` (single byte). Bool read 0xe5d6a4: `getInt8(0) == 1`.

## 2. Characteristics of service 9F00F387-8345-4BBC-8B92-B87B52E3091A (svc class WHb 0x64d)
UUIDs from getter block 0xa1f670..0xa1f6fc (descending cid order).

| class (cid) | UUID | meaning | ops used | Dart type | wire layout |
|---|---|---|---|---|---|
| jIb (0x64a) | 559644B8-E0BC-4011-929B-5CF9199851E7 | **Shutter / remote release** ("startOrStopRecording + enableAF") | WRITE (0xe52fac → dIb.write 0xe61a1c); read impl exists (bool, 0xe5d6a4) but no caller found | List<_Enum> [UIb, VIb] | **2 bytes `01 01`** = [UIb.startOrStopRecording.value=1, VIb.enableAF.value=1]. Built at 0xe61b40..0xe61b84 (growable int list, both elements Smi 2 = 1); values constant-folded because UIb/VIb each have one member (objs: UIb@867c41 off_14=1, VIb@867c21 off_14=1). |
| kIb (0x649) | B29E6DE3-1AEC-48C1-9D05-02CEA57CE664 | **Drive mode** (incl. self-timer) | NOTIFY (setup 0xd35014: finder 0xd352e8/closure 0x579158, parser EHb 0x579188 → model _UGb, provider "driveModeNotifierProvider" [pp+0x29f78]); initial READ after subscribe; WRITE (0xe538ec → cIb.write 0xe616d8); read impl 0xe617dc | vIb | **1 byte, uint8 = vIb value**: 0 oneFrame, 1 tenSecondFrame, 2 twoSecondFrame, 3 continuousShootingFrame, 4 bracketFrame, 5 bracketTenSecondFrame, 6 bracketTwoSecondFrame, 7 multipleExposureFrame, 8 multipleExposureTenSecondFrame, 9 multipleExposureTwoSecondFrame, 10 intervalFrame, 11 intervalTenSecondFrame, 12 intervalTwoSecondFrame, 13 intervalCompositionFrame, 14 intervalCompositionTenSecondFrame, 15 intervalCompositionTwoSecondFrame (decode 0x579368; other values throw). Write = `Int8List(1)[vIb.off_14]` (0xe61718 loads param+0x13). |
| lIb (0x648) | A3C51525-DE3E-4777-A1C2-699E28736FCF | **Shooting (exposure) mode + user-mode slot** | NOTIFY (0xd31250, finder 0xd34b68/closure 0x578f5c, parser TIb 0xd34e50 → model ZIb, "shootingModeNotifierProvider" [pp+0x29f58], toString "ShootingModeModel(mode: " [pp+0x46ca8]); initial READ; write factory removed by TFA (0xcb0ec0) | (XIb, YIb) | byte0 → XIb (0x5790a0): **0 P, 1 Av, 2 Tv, 3 M, 4 B, 5 BT, 6 T, 0x13 SFP** (others throw); byte1 → YIb (0x579038): **0 Other, 1 U1, 2 U2, 3 U3**. Read impl (fIb, 0xe6216c) decodes only byte0 → XIb. |
| mIb (0x647) | 78009238-AC3D-4370-9B6F-C9CE2F4E3CA8 | **Capture mode (still/movie)** | NOTIFY (0xd35944, finder 0xd35c18/closure 0x5798e8, parser RIb 0x579918 → model _BIb, "captureModeNotifierProvider" [pp+0x29fb8], "CaptureModeModel(mode: "); READ on demand (0xdd7ef4 via bIb 0xe61498); write removed by TFA | aIb | **1 byte: 0 image, 2 video** (0x579a94; other values throw). |
| nIb (0x646) | B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA | **Capture status** (shooting-in-progress + self-timer countdown) | NOTIFY (0xd354ac, finder 0xd35780/closure 0x579638, parser SIb 0x579668 → model _IIb(countdown, capturing), toString "CaptureStatusModel(countdown: …, capturing: …)" [pp+0x46cc8]); initial READ; write removed by TFA | (YHb, ZHb) | **byte0 → YHb capturing: 0 notInShootingProcess, 1 inShootingProcess** (0x5798a8); **byte1 → ZHb countdown: 0 notInCountdown, 1 selfTimerCountdown, 2 scheduledTimeWaiting** (0x579854). Bytes read with `List[]` (unsigned). Log text "drivemode, bytes: …, countdownStatus: …, capturingStatus: …" (misleading prefix). |
| oIb (0x645) | 009A8E70-B306-4451-B943-7F54392EB971 | **Cancel** (app uses it only to cancel a running 10 s self-timer countdown, see §3) | WRITE (0xe53300 → eIb.write 0xe61dd8); read impl exists (0xe61ed8, 1→WIb.cancel) but unused | WIb | **1 byte `01`** (WIb.cancel value 1; `mov x1,#1` at 0xe61e18 → 0xa12fd4). |
| pIb (0x644) | 30adb439-1bc0-4b8e-9c8b-2bd1892ad6b0 | Image-Control **Custom1** name/string | READ (0xe33cb4 xFb idx0) / WRITE (0xe344fc idx0) via hIb | String | UTF-8 (write: Utf8Encoder eg@85fe91 at 0xe6263c; read: Utf8Decoder(allowMalformed:false) dg@85fdb1 at 0xe62748, then `replaceAll([pp+0x6e30], "")` — pattern prints as "" in dump, almost certainly "\u0000" → NUL padding stripped **[inferred]**). |
| qIb (0x643) | e799198f-cf3f-4650-9373-b15dda1b618c | Image-Control **Custom2** name/string | as pIb (xFb idx1) | String | as pIb |
| rIb (0x642) | df77dd09-0a48-44aa-9664-2116d03b6fd7 | Image-Control **Custom3** name/string | as pIb (xFb idx2) | String | as pIb |
| sIb (0x641) | 3e0673e0-1c7b-4f97-8ca6-5c2c8bc56680 | Image-Control **Custom1 data** | READ (0xe338c4 idx0, gIb read 0xe5df6c returns raw bytes) / WRITE (0xe34cac idx0, gIb write 0xe623ac raw List<int>) | List<int> | ImageControlData blob, see §4. |
| tIb (0x640) | 0936b04c-7269-4cef-9f34-07217d40cc55 | Image-Control **Custom2 data** | as sIb (idx1) | List<int> | §4 |
| uIb (0x63f) | cd879e7a-ab9f-4c58-90ed-689bae67ef8e | Image-Control **Custom3 data** | as sIb (idx2) | List<int> | §4 |

xFb = {custom1 0, custom2 1, custom3 2} ([pp+0x2bd78]/[pp+0x2bd70]/[pp+0x2bd50]); selection index→class in 0xe344fc (0→pIb closure 0x95e95c, 1→qIb 0x95e92c, 2→rIb 0x95e8fc) and 0xe34cac (s/t/u closures 0x95e8cc/0x95e89c/0x95e86c).
Meaning of the p/q/r string: the app looks the slot up in its local DB with `"name = ? AND raw = ?"` [pp+0x2bc78] (0xd8db1c, called from read-all 0xe326f4 with the s/t/u bytes as `raw`) → string = image-control **name** **[inferred]**. Write path 0xe34120 logs `"Custom<n> write-> <string>"`.

## 3. Remote shooting over BLE (yes — no Wi-Fi needed)
UI: remote-shutter page (assets images/remote_shutter/*, closures 0x9a85f0 shutter.svg, 0x9a92c8 timer_off.svg). State models come from the notifies above (kIb drive mode, lIb exposure mode, mIb capture mode, nIb capturing/countdown). UI enum CRb {preCapture 0, capturing 1, postCapture 2}.

Derived flags (computed in shutter widget closure 0x9a85f0, stored in the context read by the tap handler; the drive mode is mapped to a timer kind by jump tables [pp+0x58b10]/[pp+0x58b18]: vIb idx 1,5,8,11,14 (ten-second variants) → 2, idx 2,6,9,12,15 (two-second variants) → 1, others → 0; targets 0x9a8900=0/0x9a8908=2/0x9a8910=1 and 0x9a89a0/0x9a89a8/0x9a89b0):
- `ctx+0x23` (0x9a88b0..0x9a8940) = ZHb == selfTimerCountdown && timer kind == two-second.
- `ctx+0x27` (0x9a8944..0x9a89d4) = YHb == notInShootingProcess && ZHb == selfTimerCountdown && timer kind == ten-second → "**ten-second countdown running**".
- `ctx+0x2b` (0x9a89d8..0x9a8a18) = YHb == inShootingProcess || UI state == CRb.postCapture.
(Dart bools: true = null+0x20, false = null+0x30, so `tbz w,#4` branches when true.)

Shutter tap handler 0xe52138:
1. Throttle via 0x9a8fa0: interval 1000 ms if ctx+0x27 (0x3e8 at 0xe521e4); else continuousShootingFrame drive (vIb@867de1) → 300 ms, any other drive → 1500 ms (0xe52200..0xe52218: `0xbb8 + (eq ? -0x960 : 0)` tagged). If the throttle returns true the tap is dropped (0xe52244).
2. If ctx+0x2b (in shooting process, or postCapture) → tap ignored (0xe52254). If ctx+0x23 (two-second countdown) → tap ignored (0xe52260).
3. If ctx+0x27 (ten-second self-timer countdown in progress) → **write oIb = `01`** (0xe522e8 → 0xe531a0 → 0xe53300) = **cancel the 10 s countdown**. (L10n getter 0x68a948 holds both "Tap again to cancel" [pp+0x68ed8] and "Tap again to stop shooting" [pp+0x68ee0]; which UI state shows which is **[unknown]**.)
4. Otherwise → **write jIb = `01 01`** (0xe5247c → 0xe52e2c → 0xe52fac). Same command for still release, movie start/stop (UIb name "startOrStopRecording") and Time-exposure open/close [inferred from enum names]: after write, UI goes preCapture→capturing; if exposure mode == T (XIb@867b21) and state==capturing → postCapture (0xe5259c..0xe526b0).
5. Completion is observed via nIb notifications (YHb inShootingProcess / ZHb countdown) [inferred: UI reads YHb at 0xe526dc].
- Consequence: while the camera reports inShootingProcess, the shutter button sends nothing; no generic "stop shooting" write exists on this button. How movie-stop / T-close taps get through while YHb==inShootingProcess (e.g. camera not flagging movie recording as in-process) is **[unknown]** — sniff.
- Both writes are wrapped by 0x5479e4 (allocates nFb; retry/timeout wrapper **[unknown]** details) and errors → zSb@8655c1 [pp+0x26ee8].
- AF: only via the VIb `enableAF=1` byte inside the jIb write (no separate half-press); no separate AF characteristic found.

Self-timer button 0xe534d0: allowed only if UI state != capturing, YHb == notInShootingProcess and ZHb == notInCountdown, and current drive mode index ∈ {0,1,2} (jump table [pp+0x58ca0]); maps UI selection (ZLb timerOff 0 / timerTwoSecond 1 / ten-second 2) → **write kIb**: 0→`00` oneFrame, 1→`02` twoSecondFrame, 2→`01` tenSecondFrame (0xe53918..0xe53948).

## 4. Image-Control data blob (sIb/tIb/uIb), parser 0xd8e104
- len ≥ 4 required. byte0 = version ∈ {1,2,4} (Set [pp+0x2bcb8]; else log "未対応のイメコンバージョン" and ignore). byte1 = [unknown, not read]. byte2 = base image type → mRb by `off_14` (0x7cd184): standard 0, vivid 1, monotone 2, softMonotone 3, hardMonotone 4, highContrast 5, posiFilm 6, bleachBypass 7, retro 8, hdr 9, negaFilm 0xd, cinemaYellow 0xe, cinemaGreen 0xf, crossProcess 0x10, standardMono 0x11, softMono 0x12, highContrastMono 0x13, grainy 0x14, solid 0x15, hdrMono 0x16, pallet 0x17, solarization 0x18, pictorialist 0x19 (else unknown → abort). byte3 = N parameters.
- Then N pairs at offset 4+2i: `id u8`, `value s8` (`(b&0x7f)-(b&0x80)` at 0xd8e504). id matched against nRb.off_14: saturation 0, hue 1, key 2, contrast 3, contrastHigh 4, contrastLow 5, sharpness 6, toningMonotone 7, toningCinema 8, toningBleachBypass 9, toningRetro 0xa, toningHdr 0xb, filterEffect 0xc, filterEffectRHigh 0xd, RLow 0xe, GHigh 0xf, GLow 0x10, BHigh 0x11, BLow 0x12, shading 0x13, clarity 0x14, grain 0x15, grainSize 0x16, grainStrength 0x17, hdrStrength 0x18, crossProcess 0x19, baseColor 0x1a, whitePoint 0x1b, blackPoint 0x1c, rgbToneHighlightsGM 0x1d, HighlightsBA 0x1e, MidtonesGM 0x1f, MidtonesBA 0x20, ShadowsGM 0x21, ShadowsBA 0x22, solarizationType 0x23 (list [pp+0x2bcf8]); unknown id → "イメコン不正値" logged, entry skipped.

## 5. Camera Information service 9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1 (svc class RHb 0x652, family FFb)
**Correction to context.md:** the FFb-family classes are NOT the DIS classes. h.py's `cid` dict collapses duplicate obfuscated names: the FFb builder 0x58d030 uses alloc stubs 0xd3e85c..0xd3e820 whose tags give cids **0x694, 0x693, 0x692, 0x691, KFb=0x690, LFb=0x68f** (IsType_FFb stub 0xd3e7fc: cid-0x68f <= 5), while DIS uses different classes also named GFb..JFb (cids 0x65a..0x657, stubs 0xd42650..0xd4262c).
- UUID getter block 0xb1b1fc..0xb1b238 (descending-cid rule): 0x694 F5666A48, 0x693 35FE6272, 0x692 0D2FC4D5, 0x691 B4EB8905, 0x690 6FE9D605, 0x68f 97E34DA2. **[inferred: getter-block order]**
- Reader 0xd3e3ac: finds pairs (0x58cd4c), for each char builds a read cmd (selector 0x3fb0) and runs `0xd30588<String>`; assigns by cid (0xd3e598..0xd3e64c) into model _DFb (cid 0x696, alloc 0xd3e6a4, stores +7..+0x1b at 0xd3e6b0..0xd3e6d8). Field names from toString 0xad5b08..0xad5b94: +7 manufacturerNameString, +0xb bluetoothDeviceName, +0xf bluetoothMacAddressString, +0x13 firmwareRevisionString, +0x17 modelNumberString, +0x1b serialNumberString.

| cid | UUID | field |
|---|---|---|
| 0x694 | F5666A48-6A74-40AE-A817-3C9B3EFB59A6 | manufacturerNameString (+7) |
| 0x693 | 35FE6272-6AA5-44D9-88E1-F09427F51A71 | modelNumberString (+0x17); compared to "GR IV" in 0xda7474 (0xda754c..0xda757c), passed to firmware check |
| 0x692 | 0D2FC4D5-5CB3-4CDE-B519-445E599957D8 | serialNumberString (+0x1b) |
| 0x691 | B4EB8905-7411-40A6-A367-2834C2157EA7 | firmwareRevisionString (+0x13) |
| **KFb 0x690** | **6FE9D605-3122-4FCE-A0AE-FD9BC08FF879** | **bluetoothDeviceName** (+0xb) (cmp #0x690 at 0xd3e628) |
| **LFb 0x68f** | **97E34DA2-2E1A-405B-B80D-F8F0AA9CC51C** | **bluetoothMacAddressString** (+0xf) (cmp #0x68f at 0xd3e64c; also the fall-through default) |

(context.md's KFb=F5666A48 / LFb=35FE6272 and GFb..JFb UUID assignment for this service is wrong; it used the colliding DIS cids.)
- Ops: **READ only** (command execs 0xe5c544..0xe5cd0c: read -> 0xe5c6ac, no write branch). Type String: UTF-8 decode (Utf8Decoder dg@85fdb1, allowMalformed=false) then `replaceAll([pp+0x6e30] (NUL [inferred]), "")` (0xe5c6e0..0xe5c710). MAC text format = whatever ASCII the camera sends **[unknown]** (no reformatting in the reader). Unread fields default "".
- When read: on **every BLE connect** in the main connect flow 0xd2e93c (0xd2f76c: 0xd3e248 -> 0x58cd04 -> 0xd3e3ac), after steps 0xd403b8/0xd3fdf8/0xd3f640/0xd3e874 and before notify subscription 0xd30c30 (0xd2fb28). firmwareRevisionString (+0x13) passed to persistence 0xd1e41c (0xd2f788..0xd2f7cc). Also read in restore flow 0xda7474 ("restored camera name check failed: ").
- Firmware gate in the main flow: `0x54b6c0(model=+0x17, fw=+0x13)` at 0xd2fa60; result stored into a state bool (+0x1b at 0xd2fa6c), not thrown here.

## 6. Device Information 180A (svc XHb 0x64c) and min-firmware check
- Alternate connect path 0xd42080 (log "connect device: ... connection state: "): if a flag arg is true (0xd422a8) it reads DIS 2A24 model (0xd42668) and 2A26 firmware (0xd42424), then `0x54b6c0(model, fw)` (0xd422ec); false -> 0xd4239c -> throws zSb@865621 [pp+0x2a3c8] (ER_BL_007 UnsupportedFirmwareVersion per context.md); true -> continues, saves "lastConnectedDevice" [pp+0x27d30]. 0x54b6c0 also called from 0xd1d508.
- `0x54b6c0(model, fw)`: exact String `==` (dispatch selector -0x1000) in order "GR IV"->min "0.00", "GR IIIx"->"1.50", "GR III"->"2.00", "GR II"->"3.00"; any other model string -> log + return **false** (0x54b7d4). So a camera reporting e.g. "GR IV Monochrome" would be rejected unless its model string is exactly one of the four **[inferred]**.
- `0x54b7f4(fw, min)`: fw.split(".") must have **exactly 2 parts** (0x54b848), each `int.tryParse` non-null (0x54b8bc/0x54b8f8), else log "FirmwareVersion validation error: FirmwareVersionの形式が正しくない" -> false. min split on '.' (0x4b1924) + int.parse. Result (0x54bb70..0x54bbb4): `fwMajor > minMajor || (fwMajor == minMajor && fwMinor >= minMinor)`. Minor is compared as an integer ("1.6" -> 6 < 50 fails against "1.50"; "1.50"/"1.51" pass).

## 7. Flows
1. **Connect (main flow 0xd2e93c)**: ... -> read Camera Information (all 6 chars, §5) -> firmware gate 0x54b6c0 -> `0xd30c30` subscribes notifications in this order (each: find pair -> listen parser -> setNotifyValue(true) 0xd3469c -> read 0xd314d0 to prime; read result itself is not used in Dart, the parser receives it via the value stream [inferred]): FirmwareUpdateResult jGb (0xd3812c), CameraPower YFb (0xd37c94), Battery ZFb (0xd377fc), GeoTag cGb (0xd37368), Storage dGb (0xd36e30), FileTransferList eGb (0xd36274), PowerOffDuringFileTransfer fGb (0xd35ddc), **mIb capture mode (0xd35944), nIb capture status (0xd354ac), kIb drive mode (0xd35014), lIb shooting mode (0xd31250)**. 0xd30c30 is called from 0xd2e93c (0xd2fb28) and 0xe1e300.
2. **Remote shutter**: see §3 (jIb `01 01` = release; oIb `01` only while a 10 s self-timer countdown runs; taps ignored during 2 s countdown, inShootingProcess or postCapture; kIb for self-timer).
3. **WLAN-on failure diagnostics**: in 0xdd3c14 the app reads mIb (0xdd7d90 -> 0xdd7ef4) and if it equals aIb.video (0xdd4070) reports "step2_ble_wlan_on_video_failure", else "step2_ble_wlan_on_failure" — i.e. the camera refuses Wi-Fi while in movie mode [inferred].
4. **Image Control write (/imageControlWrite, closure 0xe32160)**: write slot data (0xe34888 -> s/t/u via 0xe34cac, `List<int>`), write slot name (0xe34120 -> p/q/r via 0xe344fc, String), store prefs "imageControlLastImageCustom<n>" (0xe34004), then read back all six (0xe326f4: p,q,r via 0xe33cb4 and s,t,u via 0xe338c4), parse blobs (0xd8e104) and match local DB (0xd8db1c).

## Open questions (sniff)
- Write type (with/without response) used by FBP write 0xe5c094 for jIb/oIb/kIb/p..u (BleConn slice).
- jIb `01 01` for every mode (still, movie start/stop, T open/close, continuous) — confirm camera semantics and the resulting nIb sequence (capturing 0->1->0; countdown 1 during self-timer).
- oIb `01`: confirm it cancels the 10 s countdown; does it also cancel 2 s countdown / interval / bulb (app never sends it then)? How does the app stop movie / close T if YHb==inShootingProcess blocks taps?
- lIb: is byte1 (user mode U1..U3) always present; values for Auto/Snap modes (only P/Av/Tv/M/B/BT/T/SFP=0x13 decoded; any other byte throws in the app).
- mIb: only 0 and 2 accepted; does the camera ever send 1?
- kIb writes for modes other than 0/1/2 never issued by app; does camera accept writing e.g. 3 (continuous)?
- p/q/r: string length limit, NUL padding; s/t/u: blob byte1 and max N; version 1/2/4 differences.
- Camera Information: exact MAC string format (with colons? upper-case?) and device-name encoding; KFb/LFb UUID assignment rests on the getter-order rule — confirm by reading 6FE9D605 (expect name) and 97E34DA2 (expect MAC).
- jIb/oIb/lIb/kIb read factories exist (0xa14920/0xa149f0/0xa14988/0xa14954) but no read call sites besides notify priming — confirm chars are readable.
