# GR IV fw 1.20: BLE pairing, bonding, Paired Devices, reconnect, power-off (firmware RE)

Sources (GR IV rootfs `firmware/gr4-root/firmware.bin_extract`):
- `usr/bin/bled`, sha256 `cace4337…35df`, Ghidra 12.1.4 via REA.
- `usr/bin/sysmgrd`, sha256 `be957973…ea7c`.
- `usr/lib/libBtStack.so`, sha256 `310a759d…d02a`. This is a Blue SDK-style stack (`ME_`/`SEC_`/`LESEC_`/`SMP`/`CMGR_`/`DDB_`).

Labels: **[observed in code]**, **[inferred]**, **[unknown]**. All addresses are Ghidra addresses. For bled, llvm-objdump addresses equal the Ghidra address minus 0x10000.

## Evidence index

| Evidence id | File | Content |
|---|---|---|
| `ev_b1d49308…0a30` | `firmware/evidence/gr4-bled-security-setup.c` | BleServerInit 0x48560, SetDisplayPairingMode 0x45910, SetNonSecureMode 0x45814, Enable/DisablePairing 0x44fe4/0x450f8 |
| `ev_31371c56…f4c8` | `gr4-bled-pairing-events.c` | OnNCConfirmNotify 0x455b0, OnPairingComplete 0x4968c, OnSecurityRequest 0x48284, OnDDBUpdate 0x478c0, SaveDDB 0x46574, SavePairedDeviceTable 0x46668, DeletePairedDevice 0x467d0 |
| `ev_6a22cede…a6f0` | `gr4-bled-paired-table.c` | PairedDeviceTable::{Contains, Create, AddPairedDevice, SyncWithPairedDeviceList, SetConnected, SetDeviceName, DeletePairedDevice, SyncWithDDB} |
| `ev_fe2dfaae…76c9` | `gr4-bled-callback-dispatch.c` | CallbackBleEvent 0x48f04, btlib wrappers |
| — | `work/firmware-bonding/bled-aic-callback-thumb.txt` | Thumb disassembly of the AIC event trampoline 0x95924 (objdump 0x85924) |
| `ev_39b8cb10…7c60` | read_bytes 0xc2a50 | BleServer BtCallback vtable |
| `ev_dd777426…ee0b` | `gr4-bled-pairing-manager.c` | SetNumericComparisonConfirmResult 0x47d58, OnNegativeReply 0x48188, Recv{DeleteBlePairedDevice, ExecBlePairing, CancelBlePairing, SetBleNCConfirmResult, ChangeBleRunningState}, Stop |
| `ev_e99afe13…0bb1` | `gr4-bled-bluetoothcontrol.c` | BluetoothControl::InitService 0x55a08, PairedDeviceName::Write 0x55e30 |
| `ev_448b17c8…f174` | `gr4-bled-addchar-devname.c` | SetConnectedDeviceName 0x4678c, Service::AddCharacteristic 0x6eff0 |
| `ev_51edfad9…86dc` | `gr4-bled-gatt-initservices.c` | All six InitService functions |
| `ev_818dec57…e6ae` | `gr4-bled-main-nosec.c` | main 0x37b84 (`nosec` argv) |
| `ev_fac7b9c5…013b` | `gr4-bled-opmode-power.c` | OperationMode::Write 0x5ea00, CameraPower::Write 0x5afc4 |
| `ev_377504fd…58c4` | `gr4-sysmgr-btonly-full.c` | load_bt_only_fw::{Run 0x2e034, Init, GetBTModuleState, setAdvertData 0x2dd64, setAdvertParams, restoreDDBDataToAic 0x2d600, CallbackAicEvent} |
| `ev_6942e595…c45b` | `work/firmware-bonding/libBtStack-decomp/functions/<addr>.c` | Ghidra decompile-all of libBtStack (CLI, 2619 functions); index in `decompile-index.json` |

## 1. SMP configuration

| Item | Value | Evidence |
|---|---|---|
| Security mode chosen by bled | `SetDisplayPairingMode` unless argv[1] = `nosec`. `rc.local:190` starts `bled` with no args, so secure mode is used | 0x48560 `this[0x24]` test; main 0x37b84 `strncmp(argv[1],"nosec",5)` |
| SetDisplayPairingMode | `AIC_SetSecurity(1,1)`, `AIC_LeSetSecurityLevel(3)`, `AIC_LeSetRpaEnable(0,1)` | 0x45910 **[observed in code]** |
| `AIC_SetSecurity(1,1)` | Stack is in SSP mode (AIC_ME_Start set level 0x7c), so it calls `AIC_SEC_SetLevel(0x7d)` (MITM on) and then `AIC_SEC_SetSSP(1,4)`. That leads to `SEC_SetIoCapabilities(1)`, which writes `bt[0x6d9a]=1`, and `SEC_SetBondingMode(4)`, which sets the bonding bit in `bt[0x6d9b]` | libBtStack 0x54e68, 0x5ad9c, 0x5b090, 0x7a908, 0x7a878 |
| IO capability in the SMP Pairing Response | `bt[0x6d9a]` = **1, DisplayYesNo** | SmpStartOperation 0xd603c (response branch: `ctx+0x90 = bt[0x6d9a]`) |
| AuthReq | Link authreq OR'd with `bt[0x6d9b]` (Bonding, MITM via `SEC_SetAuthRequirements`). The SC bit is added when both sides support it; SMP_Init sets `bt._28672_4_=1` (SC supported). CT2/keypress bit 0x20 is mirrored from the peer | 0xd603c, SMP_Init 0xd4888 |
| Pairing method | LE Secure Connections. DisplayYesNo against a Mac KeyboardDisplay peer gives **Numeric Comparison** **[inferred from spec + IO caps]** | — |
| Max key size | 16. Min key size is 7 (`bt._28060_4_=0x710` puts 0x10 in 0x6d9c and 0x07 in 0x6d9d). `AIC_SECLE_StartLeSecurity` calls `SetEncryptKeySize(0x10)` | SMP_Init 0xd4888, 0x5b624 |
| Key distribution | `AIC_SECLE_SetKeyDistribution(3, ?)` gives EncKey+IdKey. The decompiler shows only the first argument; the second (initiator distribution) is probably also 3 **[inferred]**. In the response, distributions are AND-ed with the peer's request, and EncKey is cleared under SC. **Observed** (HCI trace, 2026-11-07 19:33:32, Mac offering init `0x01` / resp `0x0B`): Pairing Response `authReq=0x0d`, IO 1, init `0x00`, resp `0x02`. The camera dropped LinkKey from its own distribution (`0x0B & 0x03`, EncKey cleared) and sent its IRK and public identity address `F0:3E:05:xx:xx:xx`. With a stock Mac (init `0x0B` offered, 19:41) the response was init `0x02` / resp `0x02`: the camera accepts IdKey but not LinkKey from the initiator, consistent with a mask of 3 for both directions | 0x5b624, 0x5b5c8, 0xd603c; `captures/2026-11-07/hci-1933-initkeys01.pklg` |
| Camera's own address | `AIC_LeSetRpaEnable(0,1)` calls `AIC_ME_SetRandomAddress(0,0,1)`, which with a zero first argument calls `CMGR_EnablePrivacy(0)` (0x59c90): the camera does not use its own RPA, matching the public address in its adverts. Peer address resolution is separate (§7(a).1) | 0x55b84 |
| Peer RPA resolution | **Yes.** `SecFindDeviceRecordEx` 0x81aec: for a resolvable private peer address (type random, top bits 01), it walks DDB records that have an IRK (flag `+0xe3 & 2`) and matches with `SmpGenRandomAddrHash(IRK, prand)`. Otherwise it does an exact 6-byte match (`DDB_FindRecord` 0x416c0). `MeLeReportLinkUp` 0xe2c04 then loads LTK/IRK/CSRK and the identity address into the link | **[observed in code]** |
| DDB capacity | 10 records × 0xe4 bytes at 0x131b14, plus a used-flag array at 0x1323fc. A lookup moves the record to the front (MRU) and calls `DDB_Flush` | DDB_FindRecord 0x416c0 |

## 2. Accept/reject, numeric comparison, OK button, storing the bond

AIC events reach `BleServer` through the trampoline at 0x95924 and BtCallback vtable 0xc2a5c **[observed in code]**:

| AIC event | Handler |
|---|---|
| 0x100b | OnDDBUpdate (+0x08) |
| 0xa003 | OnAdvertiseStart |
| 0xa004 | OnAdvertiseStop |
| 0xc000 | OnConnect (+0x14) |
| 0xc001 | OnDisconnect (+0x18) |
| 0xa006 | OnNCConfirmNotify (+0x1c) |
| 0xa009 | OnPairingComplete (+0x20) |
| 0xa00b | OnNegativeReply (+0x24) |
| 0xa00c | OnSecurityRequest (+0x28) |
| 0xa005, 0xa007, 0xa008, 0xa00a | Generic CallbackBleEvent |

libBtStack produces them as follows:
- 0xa00c: `AIC_SECLE_RespSecurityProc` 0x5b65c, on stack event 0x1200, an incoming SMP Pairing Request that needs app authorisation.
- 0xa006: from `ConfirmJustWorksRequest` 0x5b76c (value 0xffffffff) or `NotifyPasskey` 0x5b694 (numeric-compare value).
- 0xa009: from `SecurityComplete` 0x5b6d0. `AIC_ME_CallbackLe` 0x5a550 also turns 0xa00a ("link encrypted with a stored key") into 0xa009 when no pairing is in progress. **On every encrypted reconnect, bled therefore receives OnPairingComplete(status, addr).**
- 0xa00b: `AIC_SECLE_NegativeReply` 0x5b7ec, which the LTK-request handler calls when it has no key (§4).

**State machine (bled, `this[0x26]` = pairing-enabled flag):**

1. **Idle (not pairing).** An SMP Pairing Request reaches OnSecurityRequest 0x48284 → `UserConfirmSecurity(ctx,false)` → `LESEC_UserConfirmSecurity` 0xd3190 → `SmpPairingFailed(ctx, 5 /*Pairing Not Supported*/)`. Then `GsDisconnect` ("force disconnected because not in pairing mode"), UI event +0x14(1). **If the address is in PairedDeviceTable, `PairedDeviceTable::DeletePairedDevice(addr, delDDB=true)` deletes the bond from the DDB as well** (0x6c198 → `btlib::DeleteDDB`).
2. **Execute Pairing** (camera UI → `RecvExecBlePairing` 0x4e164 → `EnablePairing` 0x44fe4). This sets `this[0x26]=1` and either restarts advertising or force-disconnects the current link. OnConnect 0x45290 then clones PairedDeviceTable into `this+0x48`.
3. **Pairing Request in pairing mode** (0x48284). It is denied and the link dropped in two cases:
   - the address equals the last NegativeReply address (`this+0xbe`): "because of NegativeReply";
   - the address is already in the table: "pairing request from paired device", which also deletes that entry and its DDB record.

   Otherwise `UserConfirmSecurity(ctx,true)` sends the SMP Pairing Response.
4. **Numeric comparison.** OnNCConfirmNotify 0x455b0 stores ctx at `this+0x28c` and raises UI event +0x18(number); the camera shows the code. **The camera OK button is `RecvSetBleNCConfirmResult(isAccept)` 0x4e89c** → `SetNumericComparisonConfirmResult` 0x47d58 → `AIC_LeUserConfirm` → `LESEC_UserConfirm` 0xd346c.
   - Accept: `SmpGenLtkMacKey`, or state 7→10 to wait for the peer's DHKey check.
   - Reject: `SmpPairingFailed(ctx, 0x0c /*Numeric Comparison Failed*/)`.
   - In LESC, the camera's DHKey check (Eb), and therefore the LTK and encryption, should follow only after OK **[inferred from code + spec]**.
5. **Completion.** OnPairingComplete 0x4968c:
   - Status 0, address not in the clone: `SetConnected(addr,1)` → `AddPairedDevice` (inserted at the front) → `SavePairedDeviceTable` (DeviceCommand slot 1) → UI events +0x10 and +0x1c(0) ("pairing success").
   - Failure: `GsDisconnect` and UI +0x1c(1).
   - Address already in the clone: "force disconnected in pairing mode and already paired".
   - In every case `this[0x26]=0`. Pairing mode is one-shot.
   - libBtStack `SecurityComplete` 0x5b6d0 on failure of a new pairing (`dev+0x19==1`) calls `DS_DeleteDevice`.
6. **Bond persistence.** The stack writes keys with `DDB_AddRecord` (callers: `SmpScStoreLtkDeviceRecord` 0xd6fa0, `LESEC_Authorize` 0xd3afc, and others), and `DDB_Flush` raises 0x100b. OnDDBUpdate 0x478c0 then:
   - calls `SaveDDB` 0x46574 to persist the raw DDB (DeviceCommand slot 0);
   - calls `PairedDeviceTable::SyncWithDDB` 0x6c3b4, which drops table entries without a DDB record, adds DDB records missing from the table, and **evicts the oldest entry once there are more than 6** (`size > 0xf0` with 0x28-byte entries), deleting its DDB record too;
   - saves the table.

   At BLE start, `SyncWithPairedDeviceList` 0x6bc14 deletes DDB records that are not in the table.
7. **Cancel / Delete.** `RecvCancelBlePairing` → `DisablePairing`. `RecvDeleteBlePairedDevice` → `DeletePairedDevice` 0x467d0 disconnects the address if it is connected and deletes the entry and the DDB record.

**Bond completed without OK.** With the code paths above, the LTK cannot be generated on the camera side without `AIC_LeUserConfirm(accept)`. That conflicts with the observation that encrypted reads worked without OK. Possible reasons, none verified:
- the camera UI process sent the NC result itself (that process was not analysed);
- the user's OK was not needed because the pairing did not use NC;
- the encrypted reads ran on a link the Mac believed encrypted.

**[unknown]**. Whichever it was, the Paired Devices list is **not** proof of a DDB/LTK record (§3).

## 3. Paired Devices list vs bond database vs Client Registration

- The list is `PairedDeviceTable`, a vector of 0x28-byte entries:
  - byte 0: connected flag;
  - bytes 1–6: address;
  - bytes 7+: name, defaulting to "XX:XX:XX:XX:XX:XX".
- It is serialised with the "PDT\0" magic (GetData 0x6b578) and kept MRU-ordered by `SetConnected(…,1)` **[observed in code]**.
- **Sources:** entries are added by OnPairingComplete success (`SetConnected`→`AddPairedDevice`, independent of the DDB) and by `SyncWithDDB` from DDB records.
- **Link to Client Registration.** The registration write `FE3A32F8` (`BluetoothControl::PairedDeviceName::Write` 0x55e30) only renames the entry for the currently connected address `this+0xb8`. That address is set by OnPairingComplete status 0, i.e. pairing or encrypted reconnect. The write goes through `SetConnectedDeviceName` 0x4678c → `PairedDeviceTable::SetDeviceName` 0x6c044.
  - If no entry matches, the write fails: "cannot set PairedDeviceName", ATT error.
  - Names longer than 32 bytes are truncated; non-printable characters are rejected.
- Registration does not create bonds, and bonds are not discarded for missing registration **[observed in code]**.
- The two stores can diverge: an entry added by OnPairingComplete is removed at the next OnDDBUpdate/SyncWithDDB if no DDB record exists for that exact address. The next BLE start (`SyncWithPairedDeviceList`) prunes DDB records not in the table.
- **[inferred]** "GR Lab Mac" being listed proves only that pairing complete (status 0) was reported for the Mac's then-current address.
- Maximum: 6 table entries, 10 DDB slots.

## 4. Encrypted reconnect

- **Link up** (`MeLeReportLinkUp` 0xe2c04) → `SecFindDeviceRecordExx` 0x81bbc / `SecFindDeviceRecordEx` 0x81aec. The lookup is by RPA resolution with stored IRKs, or by exact address+type. On a hit, it loads LTK/EDIV/Rand into `remDev+0x13f/0x14e/0x154/0x15c`, the IRK, the CSRK and the identity address.
- **LTK Request** (HCI LE subevent 5, `MeLeHandleMetaEvent` 0xde7ec case 5). The camera replies with the LTK only if all of these hold:
  - LTK flag (`+0x14c&1`) is set;
  - key length is non-zero;
  - EDIV equals the stored EDIV;
  - Rand equals the stored Rand.

  Otherwise it sends **LTK Negative Reply** (op state 0x97) and `AIC_SECLE_NegativeReply` → 0xa00b → bled `OnNegativeReply` 0x48188 records the address at `this+0xbe`. The camera itself does not disconnect at this point. The central sees "PIN or Key Missing" **[inferred: spec behaviour of Negative Reply]**.
- **After a Negative Reply:**
  - a Pairing Request from that address is denied (reason 5) and disconnected in **both** modes. In pairing mode this is the "because of NegativeReply" branch; outside it, the not-in-pairing-mode branch also deletes any table entry;
  - PairingComplete events for that address are ignored.
- **Successful encryption** gives 0xa00a → 0xa009 status 0 → OnPairingComplete: `SetConnected(addr,1)` and save (not in pairing mode).
- **Failure while not in pairing mode** only logs "pairing failed not in pairing mode".
- Why the Mac's reconnect fails: see §7(a).
- The Mac's reconnect drop (reason 762) is link-layer: HCI `0x3E`, with no packet from the camera and so no LTK request **[observed]**: §7(a).1.

## 5. Attribute security

- Every custom characteristic is added with `Service::AddCharacteristic(uuid, 0x10, props, perm, maxlen)` using **identical props and perm bytes** (0x02, 0x08, 0x0a, 0x12, 0x1a). There is no per-characteristic encryption flag in bled (`ev_51edfad9…`, 65 calls) **[observed in code]**.
- Security is global: `AIC_LeSetSecurityLevel(3)` → `LESEC_SetDefaultSecurityLevel(3,3)` (`bt[0x27c4/5]`), which is consulted by `LESEC_AccessRequest` 0xd4320. Level 3 = authenticated (MITM) encryption **[inferred]**.
- That fits the hardware results:
  - DIS (`AIC_GsSetDeviceInfoService`, stack-owned) reads unencrypted;
  - the first Camera Information read returns "insufficient authentication/encryption".
- How `GattServerCheckPermissionsForRead/Write` (0xc2194 / 0xc2a1c) exempt DIS is **[unknown]** (not read).
- Client Registration service `0F291746`:
  - `D8676C92-DC4E-4D9E-ACCE-B9E251DDCC0C` (BLE Enable Condition): R/W/N, 1 byte.
  - `FE3A32F8-A189-42DE-A391-BC81AE4DAA76`: write-only, 0x21 bytes.
  - Both are subject to the same global level.
- Operation Mode write (`OperationMode::Write` 0x5ea00) forwards the byte to `DeviceCommand` vtbl+0xc.
- Camera Power write (`CameraPower::Write` 0x5afc4) in the on state: `00` → power-off command; **`01` → no action, success response**.

## 6. Powered-off (BT-only) mode, sysmgrd

`load_bt_only_fw::Run` 0x2e034 (`ev_377504fd…`) runs:

1. `system("ble_loadBTonlyFW.sh")`. The script loads the NXP firmware `uartuart_n61x_v1.bin.se` and runs `hciattach` / vendor command 0x3f/0x0009.
2. `restoreDDBDataToAic`: memcpy of the saved DDB (DeviceCommand slot 0, written by bled `SaveDDB`) into `AIC_GetDDBPtr`, **before** `AIC_Init`.
3. `AIC_Init(0x80620, bdName, CallbackAicEvent)`. This is **no `AIC_SetSecurity` / `AIC_LeSetSecurityLevel`**: the defaults are IO cap 0 and bonding 0, from `AIC_SEC_SetSSP(0,0)` in AIC_Init 0x54640.
4. `setAdvertData`:
   - Advert: `02 01 06` + `11 07` + UUID `0F291746-0C80-4726-87A7-3C501FD3B4B6`.
   - Scan response: name, plus manufacturer data `DA 01` with tag 01 = model, 02 = serial and **03 = 00**.
5. `AIC_LeSetAdvertParms` with struct {type 0, ch 0, intMin 0x152, intMax 0x1fe, 0xffffffff, 0x01fe0152, 0xffffffff}. bled uses the same layout with intMin 0x20, intMax 0x30 and 30000 / 0x01fe0152 / 0xffffffff (BleServerInit 0x48560).
   - **No filter-policy / accept-list call is made by sysmgrd or bled.** Neither imports `MELE_AddWhiteList`.
   - Whether `AIC_LeSetAdvertParms` derives a filter policy internally is **[unknown]** (not read).
   - libBtStack does contain white/resolving-list code, used by `CmgrLeSetupWhiteList` (from `CmgrLeFinishCreateLink`) and `CmgrLeAddToResolveList` (from `ConnLeManager`).
6. `AIC_LeStartAdvertising`, then wait for 0xa003, then `AIC_EnterSleepMode(1,0)` and `AIC_POWER_Down()`. After that the host is down and the **controller firmware** owns advertising and connection handling.

Open points:
- How the controller treats an incoming connection, and whether it accepts only DDB peers (RPA resolution against IRKs handed over from the DDB), is **[unknown]**. It is in the NXP blob, not analysed.
- Which GATT is served while off is **[unknown]**. The GR WORLD reading of operationMode `02` after connect implies the camera boots into a bleStartup state with bled serving GATT **[inferred]**.
- `power-on-grworld.md` (read operationMode `02`, write `01`/`00`) is consistent with `OperationMode::Write` forwarding the byte. The exact bleStartup handling in camctld was not verified **[unknown]**.

### 6.1 The radio runs a different firmware image in each power state

Found in code (GR IV firmware 1.20 root file system, `firmware/gr4-root/firmware.bin_extract`):

- **On.** `etc/rc.local` loads the Wi-Fi driver `moal.ko` with `mod_para=nxp/wifi_mod_para.conf`, whose active block names the image `nxp/sduart_nw61x_v1.bin.se` ([network configuration](../firmware-network-config.md)). bled brings Bluetooth up with `usr/bin/ble_enable.sh <reload>` (strings `ble_enable.sh ` and `fail to ble_enable.sh` in `usr/bin/bled`). With `reload` = 1 the script first unbinds and rebinds the radio's SDIO host (`1b000000.mmc` on `sdhci-milbeaut`) and waits 2 s. Either way it then attaches HCI on `/dev/ttyUSI1`, runs the board's `bt_power_config_ALL.sh`, sends vendor command `0x3f/0x0009` and detaches. Which argument bled passes, and when, is **[unknown]**: the call site was not read.
- **Off.** sysmgrd's `load_bt_only_fw::Run` (step 1 above) runs `usr/bin/ble_loadBTonlyFW.sh`: unbind the SDIO host, turn UART flow control off, `fw_loader_linux /dev/ttyUSI1 115200 0 /lib/firmware/nxp/uartuart_n61x_v1.bin.se 4000000`, turn flow control on, then the same HCI attach, power configuration and vendor command. camctld has the matching interfaces `IfDeviceCmdset::IfLoadBTOnlyFW` and `IfStatChangedCmdset::IfBTOnlyFWBleSleepTransitionStartNotified`.

So turning off downloads a second image into the radio over its UART. Going by the names and the SDIO unbind, `sduart_nw61x` is the combined image (Wi-Fi over SDIO, Bluetooth over UART) and `uartuart_n61x` the one without SDIO Wi-Fi **[inferred]**.

What follows for a client:

- **Turning off ends the link.** A radio that is given a new image restarts, so no LE link can outlive the camera turning off **[inferred]**. GR WORLD's 6 s wait after a power-off notification ([ble.md, path B](ble.md#b-connect-and-wlan-on-inside-the-reconnect-flow-0xd2e93c)) fits the swap taking about that long **[inferred]**; what a connect inside those 6 s does is **[unknown]**. The session code records that a GR IV HDF (fw 1.20, 2026-11-08) switched off over Bluetooth could be linked again about 15 s after the drop (`GrSessionOptions.bleLostAfter`); GR Photo then redialled 1 s after the drop, without the 6 s wait.
- **Turning on from off.** The first link to an off camera drops about 5.5 s after it opens, before any GATT traffic; a link opened right after it holds, reads Operation Mode `02` and survives the power-on write ([GR WORLD power-on §3](power-on-grworld.md#3-power-on-sequence-home-power-button-import-and-remote-differ-only-where-noted), observed). That fits the connect waking the host, which boots into bleStartup and puts the combined image back through `ble_enable.sh 1`, ending the link the BT-only image had accepted; bled then serves the second link, and the power-on write needs nothing more from the radio **[inferred]**.
- **A link to the off camera does not last** (observed: GR IV HDF, fw 1.20, 2026-11-11). A link that held, read Operation Mode `02` and had nothing written on it was dropped by the camera 8.0–8.4 s after it opened: Camera Power `00` was notified and the link ended 0.5 s later with "Remote User Terminated Connection", four times out of four ([hardware results](../hardware-validation.md#4-results-log)). That fits the host, woken into bleStartup by the connect, shutting down again and giving the radio back to the BT-only image **[inferred]**. Until 2026-11-12 GR Photo linked again after each drop, so for as long as it held a session to an off camera it woke the camera's host about every 23 s **[inferred]**; what that cost the camera's battery was not measured. It now lets go of a camera that is off and links it again when its advertisement says it is on ([GR WORLD power-on §8](power-on-grworld.md#8-gr-photo-link-drops-at-power-changes)).
- **Not established [unknown]:** whether a link that has been held in bleStartup for some of those 8 s survives the power-on write (GR Photo stays linked to a camera it turned off, so its power-on is usually this case). On 2026-11-10 the user reported GR Photo's card saying "Reconnecting…" after every power-on as well as every power-off (from the UI; no trace, body and firmware not recorded), so some link did drop at power-on. Hardware test: [session F](../hardware-validation.md#2-capture-sessions-phone-apps).

## 7. Ranked firmware-backed explanations and client requirements

### (a) The Mac cannot reconnect after pairing

1. **Cause: the Mac sends its IRK during pairing and then connects from its public identity address. The camera puts that IRK in its resolving list in Network Privacy Mode, so its controller never answers the Mac.** The firmware chain below is **[observed in code]**. On hardware, the only negotiated difference between a failing stock pairing and a working one is the Mac's IdKey, and the failing reconnects end in HCI `0x3E` with no packet from the camera **[observed]** (last bullets). That the silence comes from the camera's NXP controller applying Network Privacy Mode, rather than some other controller-level filter, is the remaining **[inferred]** step.
   - Firmware: an IRK received during pairing goes into the controller resolving list (`SmpAddToResolvingList` 0xd6c70 copies a non-zero IRK → `CmgrLeStartAddToResolveList` 0x99658 → `CmgrLePerformNextAddrResolveOp` 0x9f020 → `MELE_AddResolvingList` 0xe7024), and address resolution is enabled (`CmgrLePerformAddrResolveOp` 0x9f188 → `MELE_SetAddressResolutionEnable(1)`). Each new entry gets device-privacy flag 0 (`CmgrLeAddToResolveList` 0x98038 sets `+0x18d = 0`). `HCI LE Set Privacy Mode` (`MELE_SetPrivacyMode` 0xe77d0) is only issued for entries queued by `CMGR_EnableDevicePrivacyMode*` (0x987e8, 0x98a2c), and no binary in the rootfs imports those. Entries therefore stay in the controller default, **Network Privacy Mode**. In that mode the Core spec (Vol 6 Part B §4.7) requires the controller to ignore a listed peer that uses its identity address instead of an RPA.
   - macOS: bluetoothd logs "Using public address because device … isn't a cloud pair device" before **every** connect to the camera, pairing included; the alternative message in the same binary is "Still using random address to connect". The Mac offers IdKey in pairing (`localKeyDist=0x0B`). The choice is made in bluetoothd (macOS 27.0.1, arm64e) by the function at 0x10079df54 **[observed in code]**: it walks the pending-connection device set (`this+0x158`), looks up each device's iCloud pairing identifier (0x1007c2244), and returns 1 ("use public address") if **any** device has none; only when every pending device is iCloud ("cloud") paired does it return 0 and keep the random address. Its single caller (0x1007842b0) passes the result unchanged as the own-address argument of the stack's LE create-connection call (0x10024d1b0); no app-supplied option is consulted on that path, and CoreBluetooth has no API for the own address type. So on macOS every third-party peripheral, the camera included, is connected from the Mac's public identity address.
   - iOS 27.2 (24B119, iPhone17,1; `bluetoothd` sha256 `2cac9060…95a9`, extracted from Apple's IPSW with `ipsw extract --remote`): the stack's accept-list create-connection entry is the same function in both binaries (macOS 0x10024d1b0, iOS 0x1003ac1fc; same strings "We can only be in auto connection mode in Central role." / "Could not start auto-connect"). Its 4th argument (`w3`) is the own-address choice: macOS's single caller passes the result of 0x10079df54 (1 = public); iOS's single caller (0x1008047a4) passes the constant `0` (`mov w3, #0x0` at 0x100804790), the value macOS logs as "Still using random address to connect" **[observed in code]**. Neither of the two macOS log messages exists in the iOS binary. This was the path for every traced camera connect on the Mac (HCI `LE Ext Create Connection filter=1`); whether iOS has another create-connection path that sets the own address differently, and which address type the stack then uses for `0` (its private-address state, `gPrivateMode`), was not traced **[unknown]**. On iOS `OverrideUsePublicAddress` is a real setting (setter 0x1003c0b50 stores global 0x100c2f544, empty on macOS), but its only reader (0x1003bed08 in the SMP key-distribution function) picks which identity address goes into the Identity Address Information packet, not the connect address **[observed in code]**. That an iPhone connects to the camera from a resolvable private address, and therefore reconnects like Android, is **[inferred]** (untested; Apple documents RPAs for iOS in [Platform Security: Bluetooth](https://support.apple.com/guide/security/bluetooth-security-sec82597d97e/web)).
   - Hardware:
     - every failed connect drops 170–210 ms after "connection complete", about 6 connection events at 30 ms. The HCI trace shows the Mac's controller reporting Disconnection Complete reason `0x3E` (Connection Failed to be Established) **[observed]**; macOS logs the same drops as reason 762 (19:41–19:45: 233 `0x3E` in the HCI trace, 233 "reason 762" in bluetoothd, and 722 for the one local `0x16` disconnect, so macOS reports 700 + HCI reason) **[observed]**. In the Core spec (Vol 6 Part B §4.5) a central reports `0x3E` when it receives nothing from the peripheral within the first 6 connection events, i.e. the camera's controller never answered. The 4803/634 codes are still not documented by Apple;
     - the drop also happens when the Mac holds **no** key (18:17: status 4803, `encryptionPending 0`), as expected if the camera's controller never answers the link, whatever the Mac would do on it;
     - connections from the same public address stayed up when the camera had no entry for the Mac: the first-ever connect, and pairing after the camera-side entry was deleted;
     - when the camera had deleted the Mac but the Mac kept its keys, the link stayed up long enough for an LTK Negative Reply, reported by CoreBluetooth as "Peer removed pairing information".
   - The Android phone bonded by GR WORLD reconnects; Android uses resolvable private addresses by default **[inferred]**.
   - **Intervention, 2026-11-07 19:33:** with `com.apple.MobileBluetooth.debug` → `LE` → `OverrideInitiatorKeys = 1` (bluetoothd logged "Warning: Overriding initiator keys to 0x1"), the Mac's Pairing Request offered `localKeyDist=0x01` (EncKey) instead of `0x0B` (EncKey `0x01` | IdKey `0x02` | LinkKey `0x08`; SignKey `0x04` was never offered), so neither the IRK nor cross-transport link-key derivation. The address path was unchanged ("Using public address"), as were the camera and the test. Pairing succeeded, then **both** later connects encrypted with the stored key (19:33:39.2 and 19:34:06.5), read Camera Information and the Wi-Fi credentials, and joined the camera's Wi-Fi (`research/hardware-validation.md` §4). Every earlier reconnect from this Mac after a bond had failed. On its own this changed two keys (IdKey and LinkKey); the stock control below shows the camera refuses LinkKey anyway, which isolates IdKey.
   - The setter is real: `OverrideInitiatorKeys` (section `LE`, read at 0x10082565c in the arm64e bluetoothd of macOS 27) stores into a global that the SMP code reads (0x100260918 etc.) as `initiatorKeys = (byte == 0xFF) ? 0x0B : byte`. `OverrideUsePublicAddress` is read in the same place but its setter (0x1000d5b00) is an empty function in this release build, so the Mac's own address type cannot be changed this way.
   - HCI trace of the 19:33 run (`captures/2026-11-07/hci-1933-initkeys01.pklg`, bluetoothd `HCITraces` → `HCIFileTraces`) **[observed]**: every connect is `LE Extended Create Connection` with own address type 0 (public) and the accept-list filter. Pairing Response init `0x00` / resp `0x02`; the Mac sent no IRK. The camera answers each reconnect with an SMP Security Request within 4–12 ms, and `LE Enable Encryption` (EDIV 0) succeeds in about 0.5 s.
   - **Stock control, 2026-11-07 19:41** (`captures/2026-11-07/hci-1941-stock.pklg`, override removed, bluetoothd restarted) **[observed]**: Pairing Request `authReq=0x2d` init `0x0B` / resp `0x0B`; Pairing Response `authReq=0x2d` init `0x02` / resp `0x02`. The camera refused LinkKey in both directions, so the stock pairing distributes exactly the same keys as the working 19:33 run plus the Mac's IdKey: the Mac sent IdentityInfo (non-zero IRK) and IdentityAddrInfo with address type 0, the same public address its connects use. The only other difference is the CT2 bit in AuthReq (`0x2d` vs `0x0d`), which only selects the h7 function for cross-transport link-key derivation, and none was negotiated. Then 233 reconnects in 3.7 minutes, all the same: connection complete status 0, `LE Enable Encryption` sent, Disconnection Complete `0x3E` 179–210 ms later, no Encryption Change and no SMP traffic from the camera. The 7 completions with status `0x02` follow `LE Create Connection Cancel` at the app's 35 s timeouts.
   - *Consequence:* on a stock Mac, which connects from its public address and distributes its IRK, a bonded Mac cannot reconnect, and every characteristic that needs encryption (§5) is only reachable on the link that did the pairing. A Mac can reconnect if it pairs without distributing IdKey (`OverrideInitiatorKeys = 1` is the tested value), which needs a root-only debug default. An app cannot set it.
2. **Bond keys not committed because OK was not pressed on the camera.** Ruled out as the Mac failure: on 2026-11-07 19:02 the user pressed OK, the camera listed "GR Lab Mac", and both reconnects still failed. Pressing OK is still required for a stored bond (0xd346c) **[inferred]**.
3. **Address/identity mismatch in the LTK lookup** (0x81aec: exact address or IRK-resolved RPA). Ruled out for the Mac: this would end in an LTK Negative Reply, but on the failing reconnects the camera never transmits at all (HCI `0x3E`, no SMP or Encryption Change; stock control in item 1) **[observed]**.
4. **A new SMP Pairing Request outside Execute Pairing destroys the camera's bond.** OnSecurityRequest (0x48284) runs only on an incoming Pairing Request (AIC 0xa00c, stack event 0x1200). It denies with reason 5, disconnects, and calls `DeletePairedDevice(addr, delDDB=true)` (0x48284 → 0x6c198). After a Negative Reply, pairing requests from that address are refused.
   - Ordinary connection retries and encryption (LTK) failures do **not** reach this path in firmware; they end at the LTK Negative Reply (§4) without deleting anything.
   - Retries can delete the bond **only if macOS sends a new SMP Pairing Request** (e.g. auto-pairing after "insufficient encryption"). Whether macOS does so after an LTK Negative Reply is **[unknown]**: the only traced failures (19:41, 233 reconnects) ended at HCI `0x3E` before any LTK exchange, so their lack of SMP traffic does not answer it, and the loops that reached a Negative Reply ("Peer removed pairing information") were not traced. The reason-9 responses (`SmpIsRepeatedAttemptsActive` 0xd5f0c) seen during the unbonded 3 s retry loop do show that Pairing Requests were sent in that earlier phase.
   - *Requirement:* do not let a reconnect on an unbonded or failed link turn into a new Pairing Request outside Execute Pairing. Treat a Negative Reply or "insufficient encryption" on reconnect as "re-pair needed", not as something to retry.
5. **Pairing mode is one-shot and refuses known addresses** (0x48284, 0x4968c). Re-pairing an address that is still listed fails.
   - *Requirement:* delete the entry on the camera (and the Mac's bond) before re-pairing.

### (b) Connects to the off camera fail

1. **The off state runs the controller-only firmware with the DDB restored from the bond store** (0x2d600 before AIC_Init). If the Mac has no valid DDB record (see (a)), the off camera cannot authenticate or wake for it. Accept-list gating is **[inferred/unknown]**.
   - *Requirement:* get a camera-confirmed bond first (a.1–a.2; on a Mac see a.1), then connect directly to the bonded camera.
2. **The host is powered down.** Advertising and connection handling belong to the NXP firmware, and its acceptance and wake rules are **[unknown]**. GR WORLD succeeds from a bonded Android phone; which address the phone uses (Android defaults to private addresses) is **[unknown]**.
   - *Requirement:* reconnect from the same bonded identity the camera stored. A bonded GR WORLD phone has that; the Mac's suspect bond does not.
3. **Waking after connect** is not done by Camera Power `01` (a no-op in bled, 0x5afc4). Follow GR WORLD: read operationMode and write `01`/`00` when it reads `02`.

## Unknowns

- How the Mac's encrypted reads succeeded without the camera OK. The camera UI process that issues `RecvSetBleNCConfirmResult` was not analysed.
- Exact second argument of `AIC_SECLE_SetKeyDistribution(3, ?)` (initiator key distribution). Check the disassembly at 0x5b624.
- `AIC_LeSetAdvertParms` struct→HCI mapping and filter policy, in both on and off state.
- NXP controller firmware behaviour while off: accept list, RPA resolution, and which event wakes the host.
- `GattServerCheckPermissionsForRead/Write` exemption rules (why DIS is open).
- Mapping of the macOS status codes 4803 / 634 / 719. Reason 762 is HCI `0x3E` (§7(a).1).
- Whether the camera's NXP controller applies Network Privacy Mode, or some other filter, to produce the silence behind `0x3E` (§7(a).1). Only an air sniffer can show the camera receiving the connect request and staying silent.
- Whether macOS sends a new SMP Pairing Request after the LTK Negative Reply on reconnect, the only firmware path that deletes the camera's bond (§7(a).4). Needs an HCI trace of a reconnect where the camera has deleted the Mac but the Mac kept its keys.
- How camctld/sysmgrd handle the bleStartup state and the operationMode `02` → `01` transition.
