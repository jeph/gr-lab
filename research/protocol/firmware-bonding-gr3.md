# GR III fw 2.20: BLE pairing (firmware RE)

How a GR III pairs, read from its firmware, and where that differs from the GR IV ([firmware bonding](firmware-bonding.md)). The short version: a GR III shows a code that the user types into the phone's pairing prompt (Passkey Entry); a GR IV shows the same code on both and waits for OK (Numeric Comparison). The Execute Pairing gate is the same on both.

Nothing here was run on a camera: no GR III has been paired with GR Photo. §6 lists what a camera has to settle.

Sources (GR III 2.20 rootfs, `firmware/gr3-root/firmware.bin_extract/initramfs_extract/gzip.uncompressed_extract`):
- `usr/bin/bled`, sha256 `fd2b2678…9740`, Ghidra 12.1.4 via REA `decompile-all`. Evidence `ev_71f79f6f…39b1`, files in `work/gr3-bonding/bled-decomp/functions/<addr>.c`.
- `usr/lib/libBtStack.so`, sha256 `59b682b8…4435`, same tooling. Evidence `ev_122a7a28…5f05`, files in `work/gr3-bonding/libBtStack-decomp/functions/<addr>.c` (2238 functions).
- Menu text: the tables of `firmware/gr3_v220/rtos.bin` (GR III 2.20) and `firmware/gr3x_v170/rtos.bin` (GR IIIx 1.70), printed with `research/tools/menu_strings.py`.
- Ricoh's GR III Operating Manual (English PDF, `ricoh-imaging.co.jp/english/support/man-pdf/gr-3.pdf`, read 2026-11-13), pp. 111-112.

The GR III and GR IIIx packages share one INITFS ([camera models §2](../camera-models.md)), so `bled` and `libBtStack.so` are the same files on the GR III, GR IIIx and their HDF variants.

Labels: **[observed in code]**, **[inferred]**, **[unknown]**. Addresses are Ghidra addresses.

## 1. SMP configuration

| Item | GR III 2.20 | GR IV 1.20 ([§1](firmware-bonding.md#1-smp-configuration)) | Evidence (GR III) |
|---|---|---|---|
| Security mode chosen by `bled` | `SetDisplayPairingMode` unless argv[1] = `nosec`; `rc.local` starts `bled` with no argument | same | BleServerInit 0x4c7ac (`this[0x24]` test), main 0x3997c **[observed in code]** |
| `SetDisplayPairingMode` | `AIC_SetSecurity(0,1)`, `AIC_LeSetSecurityLevel(2)`, `AIC_LeSetRpaEnable(0,1)` | `AIC_SetSecurity(1,1)`, `AIC_LeSetSecurityLevel(3)`, `AIC_LeSetRpaEnable(0,1)` | 0x4c6c0 **[observed in code]** |
| IO capability | `AIC_SetSecurity(0,1)` → `AIC_SEC_SetSSP(0,4)` → `SEC_SetIoCapabilities(0)`: **0, DisplayOnly**. `SmpStartOperation` copies that byte into the Pairing Response | **1, DisplayYesNo** | libBtStack 0x4181610c, 0x4181c7b8, 0x41862dd8, 0x41846988 **[observed in code]** |
| Bonding | `SEC_SetBondingMode(4)` sets the bonding bit | same | 0x41862d48 **[observed in code]** |
| Association model | `FUN_41829a64(…, peer IO, local IO, …)` picks the method. With local IO 0 it returns 2 (passkey) with the "this side displays" flag set when the peer is KeyboardOnly (2) or KeyboardDisplay (4), and 1 (Just Works) when the peer is DisplayOnly, DisplayYesNo or NoInputNoOutput. Android and iOS pair as KeyboardDisplay, so a phone gets **Passkey Entry, camera displays, phone types** **[inferred from code + IO caps]** | Numeric Comparison | 0x41829a64 |
| What `AIC_LeSetSecurityLevel(2)` demands | It stores 2 as the default level for both roles (`LESEC_SetDefaultSecurityLevel(2,2)`); `LESEC_AccessRequest` 0x4183968c checks it against the link's key. Whether level 2 turns away the Just Works key a NoInputNoOutput central would get is **[unknown]** (the check was not decoded) | level 3 | 0x418171ec, 0x41838050 |
| `nosec` mode | `SetNonSecureMode`: `AIC_SetSecurity(3,0)` (NoInputNoOutput). Not used: `rc.local` passes no argument | same idea | 0x4c5a0 **[observed in code]** |
| Camera's own address | `AIC_LeSetRpaEnable(0,1)`, as on the GR IV: no resolvable private address of its own | same | 0x4c6c0 |

## 2. Pairing events, the Execute Pairing gate and storing the bond

Stack events reach `BleServer` through the trampoline at 0x8cc5c **[observed in code]**; which virtual each slot is follows from the argument shapes and the GR IV's table **[inferred]**:

| AIC event | Handler (vtable slot) | GR IV |
|---|---|---|
| 0x100b | OnDDBUpdate (+0x08) | same |
| 0xa003, 0xa004 | OnAdvertiseStart, OnAdvertiseStop | same |
| **0xa008** | **OnPasskeyNotify(addr, passkey)** 0x4a4cc (+0x1c) | no handler of its own |
| 0xa006 | **none** | OnNCConfirmNotify (+0x1c) |
| 0xa009 | OnPairingComplete(status, addr) 0x4bc58 (+0x20) | same |
| 0xa00b | OnNegativeReply(addr) 0x4a618 (+0x24) | same |
| 0xa00c | OnSecurityRequest(ctx, addr) 0x4a760 (+0x28) | same |

- `AIC_SECLE_NotifyPasskey` 0x4181cdb0 raises 0xa008 for a passkey to show and 0xa006 for a numeric comparison value. The GR III's `bled` handles only the first; it has no `OnNCConfirmNotify`, no `SetNumericComparisonConfirmResult` and does not import `AIC_LeUserConfirm`, all of which the GR IV's has **[observed in code]** (symbol lists of both binaries).
- `OnPasskeyNotify` logs the peer address and hands the passkey to the camera core (`CameraController::GetInterfaceEvent()`, slot +0x10), which draws it. `bled` then waits: nothing in it answers the passkey. The pairing ends when the phone has sent the right code, and `OnPairingComplete` arrives **[observed in code]**.

**The Execute Pairing gate is the GR IV's** (`this[0x26]` = pairing enabled, set by `RecvExecBlePairing` 0x51230 → `EnablePairing` 0x48b64, which also drops the current link) **[observed in code]**:

1. **Not on Execute Pairing.** `OnSecurityRequest` refuses (`UserConfirmSecurity(ctx,false)`), disconnects ("force disconnected because not in pairing mode"), tells the UI, and **deletes the device's entry and its bond if it is in the Paired Devices table**.
2. **On Execute Pairing.** Refused and dropped when the address is the one of the last negative reply, or when it is already in the table ("pairing request from paired device", which deletes the entry too). Otherwise accepted.
3. **Pairing complete.** On success `OnPairingComplete` marks the device connected, saves the Paired Devices table and tells the UI; on failure it disconnects. Either way it clears `this[0x26]`: Execute Pairing is one-shot.

So a phone that asks a GR III to pair outside Execute Pairing loses its entry, exactly as with a GR IV ([firmware bonding §2](firmware-bonding.md)). The manual's limit is six paired devices (p. 112).

## 3. Repeated attempts

libBtStack keeps SMP's repeated-attempts timer **[observed in code]**: after a failed pairing `SmpSetupRepeatedAttempts` 0x4183be80 remembers the peer's address and starts a timer, 2 s at first and doubled on each failure up to 32 s; while it runs, `SmpStartOperation` 0x41846988 answers that address with error 0x21 (`SmpIsRepeatedAttemptsActive` 0x4183bd48). `SmpClearRepeatedAttempts` 0x4183c02c resets it to 2 s. The GR IV's libBtStack has the functions of the same names and the 32 s cap. GR Photo's 15 s between bond attempts (`PairingRun.bondInterval`) is unchanged.

## 4. Menu and on-camera text

Found in the GR III 2.20 and GR IIIx 1.70 menu tables (same entries and numbers in both) and in the manual, pp. 111-112:

| | GR III / GR IIIx | GR IV |
|---|---|---|
| Where Bluetooth is set | MENU → E6 Wireless Connection → **Bluetooth Setting** (entry 608) | MENU → E6 → Wireless Communication |
| Action Mode (612) values | **On anytime** (614), **On when power is on** (615), **Disable** (616). Help text 613: "Allows Bluetooth connection even when the camera is turned off." | On, Off |
| Pairing menu | Pairing (618) → Execute Pairing (620), Paired Devices (624) | same entries, same text in all 21 languages |
| Code heading | Authentication Code (622) | same text |
| Help on Execute Pairing (683) | "Pairing. Select Device Name and enter Authentication Code on the device you want to pair with." | "Allow pairing. Confirm that Authentication Code is correct and press OK button." |
| Further text | 684 "Authentication Code is displayed after selecting Device Name."; 685 "Paring failed. Check Action Mode." (sic) | — |

- The manual's steps: Bluetooth Setting → Action Mode → On anytime or On when power is on → Pairing → Execute Pairing; "The camera enters a pairing standby state, and the camera's [Device Name] and [Password] are displayed"; then on the phone "select the device name of the camera and enter the authentication code".
- Wi-Fi has its own entry on a GR III, Wireless LAN Setting (610), with an Action Mode of On or Off (manual p. 114).
- The texts GR Photo's drawing of the camera screen uses (Pairing, Execute Pairing, Paired Devices, Authentication Code) read the same in the GR III 2.20 and GR IV 1.20 tables in every language (compared 2026-11-13).

## 5. What GR Photo does with it

- `CameraFeature.passkeyPairing` and `CameraFeature.bluetoothSettingMenu` (`packages/gr_camera/lib/src/camera_features.dart`) are set for the GR III, GR IIIx and their HDF variants at any firmware. Any firmware is **[inferred]**: only 2.20 and 1.70 were read.
- The pairing pages take the model from the advertisement (`NearbyCamera.body`) and, for these bodies, give the Bluetooth Setting path, say that the phone will ask for the camera's code, draw the code screen without an OK button, and replace "press OK on the camera" in the failure steps with entering the code. The connection failure check names Bluetooth Setting and "isn't Disable" for a saved GR III.
- The hint for a camera that is not listed gives both menu paths, since nothing is known about a camera that does not advertise.
- Nothing changes in the pairing code itself: the phone's system draws the prompt on both platforms (Android's pairing dialog, iOS's Bluetooth Pairing Request), whichever method the camera picks **[inferred]**; `pairCamera` only asks for the bond and waits.
- The simulated camera pairs a GR III model when the simulated user types the code (`FakeGrCamera.enterPairingCode`) and ignores an OK press, so a test that confirms the wrong way fails.

## 6. Unknown, for a hardware test (GR III or GR IIIx, 2.20 / 1.70)

1. **That a phone is asked to type the code.** §1 infers Passkey Entry from the IO capabilities. Test: pair from GR Photo on Android and on iOS; note what the system prompt asks for.
2. **When the code appears and what Execute Pairing shows before it.** The manual says Device Name and "Password" are displayed; entry 684 says the code is displayed after the device is selected. Test: open Execute Pairing, read the screen, tap Pair, read it again.
3. **Whether the camera asks for anything after the code is typed.** The UI lives in the RTOS image and was not read. If it does ask for an OK, the failure steps need it back.
4. **Whether the E6 page is titled Wireless Connection** in the camera, as the manual's menu list has it.
5. **Older firmware** (GR III before 2.20, GR IIIx before 1.70): not read.
6. **iOS.** The manual tells iOS users to connect through Image Sync; whether pairing from a third-party iOS app behaves differently from Android is not known.
