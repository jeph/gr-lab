# GR camera protocol research

How Ricoh GR cameras talk to phones, reverse-engineered for GR Lab. Sources include the official Android app **RICOH GR WORLD 2.0.0** (`com.ricohimaging.grworld`, versionCode 26101500), Ricoh's older Image Sync 2.1.32, and extracted GR III/IIIx and GR IV firmware. Findings come from static analysis unless the [hardware results log](hardware-validation.md#4-results-log) or a file's own "observed" note says otherwise. On a GR IV HDF (fw 1.20) the following has been run end to end: pairing from a Mac, BLE identity and Wi-Fi credential reads, WLAN-on, joining the camera AP, `/v1/props`, photo listing and download, power-on from off (Android), and live view, focus and exposure changes (GR Lab on Android). No GR III/IIIx has been tested.

Paths such as `apk/…`, `work/…`, `firmware/…`, `captures/…` and `tools/blutter/` refer to the local research workspace (`../gr` beside this repository). It holds Ricoh's APKs, their decompilation, the extracted firmware and its decompiled evidence; those are Ricoh's copyrighted files and are not in this repository. See `AGENTS.md` for how to keep these notes current.

## Documents

| File | Contents |
|---|---|
| [camera-models.md](camera-models.md) | Which bodies we can support, byte-identical firmware groups (GR IV = IV HDF = IV Monochrome; GR III/IIIx share BLE/HTTP binaries), and how to identify the model (BLE scan-response model code, model characteristic, `/v1/props`) |
| [protocol/ble.md](protocol/ble.md) | BLE GATT map (6 custom services + Device Information, every UUID), payload encodings, scanning, pairing, reconnect, Wi-Fi-on hand-off, remote shutter, clock and GPS push |
| [protocol/ble-imagesync.md](protocol/ble-imagesync.md) | BLE extensions from Ricoh's Image Sync 2.1.32: 27 extra characteristics (exposure, focus, lists, aggregate notifications), BLE wake from power-off, advert tag `03` = power, link parameters versus GR WORLD |
| [protocol/http-api.md](protocol/http-api.md) | Camera HTTP API at `http://192.168.0.1/v1/...` (18 endpoints), photo import and auto-transfer flows, firmware update, WebSocket `ws://192.168.0.1/v1/changes`, error codes |
| [protocol/remote-shooting.md](protocol/remote-shooting.md) | Wi-Fi remote shooting from Ricoh's Image Sync 2.1.32: live view MJPEG stream, HTTP shutter/focus/compose/cancel, exposure writes and value tables, WebSocket completion tracking, per-model behaviour, firmware cross-check, GR IV observations |
| [protocol/image-control.md](protocol/image-control.md) | Image Control looks: GR WORLD never builds a blob (it copies camera bytes), the parameters of each base image from GR IV firmware keys, value ranges and names, slot-name rules, and GR Lab's choices where facts stop |
| [protocol/usb.md](protocol/usb.md) | Wired support: GR WORLD has none; camera USB is a read-only PTP device (VID/PIDs, supported ops, unreachable Pentax tether code), wired-vs-wireless feature parity and per-platform effort |
| [protocol/connection-lifecycle.md](protocol/connection-lifecycle.md) | How the app joins and loses camera Wi-Fi, connection state machine, observed defects versus causal hypotheses, per-platform fixes |
| [protocol/connection-imagesync.md](protocol/connection-imagesync.md) | How Ricoh's Image Sync keeps the link: 2 Hz `/v1/props` heartbeat, loss rule, WebSocket auto-reopen, BSSID pinning, 60 s background WLAN-off, BLE↔Wi-Fi handoff, per-model capability matrix, liveness comparison with GR WORLD |
| [protocol/grworld-connect-flow.md](protocol/grworld-connect-flow.md) | GR WORLD's connect sequence step by step, from the decompiled app |
| [protocol/power-on-grworld.md](protocol/power-on-grworld.md) | How GR WORLD powers an off camera on over BLE |
| [protocol/firmware-bonding.md](protocol/firmware-bonding.md) | The camera firmware's Bluetooth pairing and bonding rules, and why a Mac cannot reconnect |
| [framework.md](framework.md) | Framework recommendation for Windows/macOS/iOS/Android |
| [firmware-protocol-inventory.md](firmware-protocol-inventory.md) | Firmware hashes/extraction coverage, HTTP routes beyond the app, GATT UUID comparison, REA native findings and camera-side shutdown limits |
| [firmware-network-config.md](firmware-network-config.md) | Camera boot/AP startup, hostapd generation, DHCP, radio power settings and timeout distinctions |
| [hardware-validation.md](hardware-validation.md) | Phone/Mac traffic-capture setup (iPhone PacketLogger + `rvictl`, Android HCI snoop), capture sessions, safe direct probes and a results log |
| [burst-grouping.md](burst-grouping.md) | Idea: grouping continuous shots in the library. What the camera exposes per photo, what is unknown (GR IV drive-mode values, thumbnail EXIF, range requests) and the test to settle it |
| [notes/](notes) | Working notes behind the documents above: per-service BLE analysis of GR WORLD (`notes/ble/`), HTTP notes, and public-source history of the extra HTTP routes. Superseded where a document says otherwise |
| [tools/dartdis.py](tools/dartdis.py) | Linear disassembler for GR WORLD's Dart AOT snapshot (see "Reproducing the analysis") |

## Protocol in one paragraph

The observed GR WORLD paths control GR III, IIIx and IV over **BLE**, with ordinary OS bonding. The phone writes `01` to WLAN Control `9111CDD0-…`, reads the SSID/passphrase and joins the camera AP. Shutter, drive mode, clock, GPS, Wi-Fi settings and Image Control slots also use BLE writes. Images move over **Wi-Fi**: plain HTTP/1.1 JSON + image data at `192.168.0.1`, plus a change-notification WebSocket. GR II is Wi-Fi only. GR WORLD has no live view; Ricoh's older **Image Sync** app does, for GR II and GR III/IIIx (it rejects GR IV): `GET /v1/liveview` streams MJPEG, `POST /v1/lens/focus` and `POST /v1/camera/shoot` take `pos=X,Y` / `af=on` bodies, and `PUT /v1/params/camera` sets exposure ([remote shooting](protocol/remote-shooting.md)). Image Sync also wakes a powered-off camera by a bare BLE connection and controls exposure over BLE ([Image Sync BLE](protocol/ble-imagesync.md)). The GR IV firmware carries the same routes and almost all the same characteristics, but GR IV behaviour is untested.

## Connectivity defects and unresolved causes

Detail and evidence are in `connection-lifecycle.md` §8. In short:
1. The app sends no periodic Wi-Fi heartbeat. Firmware registers ping and liveview routes, but ping reads camera time; neither its keep-awake effect nor the camera's Wi-Fi idle threshold is established. Missing heartbeats are a hypothesis, not a confirmed cause.
2. The Android Wi-Fi request is held by `MainActivity`, with no foreground service during a normal session. A `requestNetwork` request lives until it is unregistered or the process exits, so backgrounding alone does not release it. The risk is that a backgrounded app without a foreground service is likely to be killed by Android or an OEM battery manager, and process death releases the request and drops the camera network **[inferred]**.
3. The app's BLE "release" routine writes WLAN-off and disconnects Wi-Fi; it runs from the BLE auto-connect path.
4. Lost networks are handled silently or not at all. After a WPA2-fallback join, `onLost` does nothing and the whole process stays bound to a dead network.
5. Background losses update WebSocket state but suppress the dialog; nothing ever rejoins automatically.

## Hardware findings that shape the client

From the [results log](hardware-validation.md#4-results-log); rules for clients are in [BLE §camera-side pairing and reconnect rules](protocol/ble.md#camera-side-pairing-and-reconnect-rules-observed-on-gr-iv-hdf-fw-120).

- **A bonded Mac cannot reconnect to the camera.** macOS connects third-party Bluetooth devices from its fixed public address and hands the camera its identity key (IRK) during pairing; the camera's controller then ignores that address. Only the link that did the pairing gets encrypted access. Isolated with an HCI trace and a control run; no app-level fix exists ([firmware bonding §7(a)](protocol/firmware-bonding.md#a-the-mac-cannot-reconnect-after-pairing)). Android reconnects fine; iOS and Windows are untested.
- **Pairing is strict:** only on the camera's Execute Pairing screen, with the code accepted on the device **and** OK pressed on the camera; retries faster than about 15 s lock pairing out; a bond deleted on one side only breaks every later connect until both sides are cleared.
- **Power-on from off works from a bonded Android phone** using GR WORLD's method (connect, Operation Mode `02` → write `01`), but the first link always drops after about 5.5 s while the camera wakes; the client must reconnect at once.
- **The camera AP takes about 16 s to appear** after WLAN-on; join with retries.
- **`GET /v1/photos/latest/info` does not exist on GR IV** (errCode 400); use the photo list.

## Recommended stack

Flutter for the UI on all four platforms, a pure-Dart `gr_protocol` package for BLE + HTTP + the connection state machine (BLE through `universal_ble`, BSD-3-Clause; `flutter_blue_plus` 2.x needs a paid licence for for-profit use), and a small native `camera_wifi` plugin per platform for joining the AP and, on Android, binding camera sockets to that network. A Rust core (btleplug + UniFFI behind native UIs) is the alternative if native UIs or a headless CLI matter more than a single UI codebase. See [framework.md](framework.md). GR Lab follows this: `packages/gr_protocol`, and `packages/gr_camera` as the plugin and camera layer.

## Code

GR Lab's own code is in this repository (`packages/gr_protocol`, `packages/gr_camera`, `packages/gr_fake_camera`, `app`). The early prototypes used for the first hardware runs stay in the local research workspace (`../gr`):

| Path in `../gr` | What |
|---|---|
| `packages/gr_cli` | `gr` command-line tool for the camera's HTTP/WebSocket API (`dart run gr_cli:gr --help`). |
| `apps/gr_lab` | Flutter test app: `universal_ble` transport, scan, BLE-only or full sessions, camera actions and a trace file. Wi-Fi join is automatic on macOS (`networksetup`, so the macOS app is not sandboxed) and manual elsewhere. `flutter run -d macos`. |
| `packages/gr_protocol` | The prototype of this repository's `gr_protocol`. |

How to use them against a camera: [hardware validation §1.1](hardware-validation.md#11-repo-tools).

## Still to verify on hardware

Each document ends with "Open questions". The highest-value remaining checks:
1. A GR III/IIIx: GATT discovery, bonding rules and Wi-Fi hand-off (only GR IV has been tested).
2. iOS and Windows reconnects to a bonded camera (the Mac fails; static analysis of iOS `bluetoothd` suggests iOS does not force the public address, untested: [firmware bonding §7(a)](protocol/firmware-bonding.md#a-the-mac-cannot-reconnect-after-pairing)).
3. Whether the camera drops idle HTTP/WebSocket clients, and its Wi-Fi idle timeout with and without periodic `GET /v1/props`.
4. HTTP proxy capture of GR WORLD's own `/v1/transfers` and WebSocket traffic.

Two in-app inconsistencies to keep in mind: the firmware gate in code requires GR II ≥ "3.00" (`0x54b6c0`) while the UI text says 1.10; and the gate compares model strings exactly against "GR IV", "GR IIIx", "GR III", "GR II".

## Reproducing the analysis

Binaries and derived output live only in the local research workspace (`../gr`: `apk/`, `work/`, `firmware/`, `tools/blutter/`); the commands below run from there.

1. **APK.** Split APK set installed from Google Play on a phone (installer `com.android.vending`) and pulled from it with `adb`, saved to `apk/grworld-play/`. Base APK SHA-256 `daa375bc…8d1b8b`, signed (v2+v3) with certificate SHA-256 `648876f2…2240f6` and a Play source stamp. That certificate is Google Play App Signing's, so the APK matches what Play distributes, but Ricoh's authorship is not verified cryptographically. The arm64 split carries `libapp.so` (Dart AOT, Dart 3.11.1, obfuscated) and `libflutter.so`.
2. **REA** (`identify_flutter_build`, `inspect_apk_signature`) for the build and signer facts. REA's Android/JADX provider was not configured (`REA_JADX_MCP_JAR` unset), so the Java side was decompiled with the local `jadx` CLI into `work/jadx/`.
3. **blutter** (github.com/worawit/blutter, built for Dart 3.11.1) for the object pool (`pp.txt`), const objects (`objs.txt`) and names. Run it on a **case-sensitive** volume: obfuscated library names differ only by case and overwrite each other on default macOS APFS (`hdiutil create -fs "Case-sensitive APFS" …`). blutter only emits asm for functions that still have Code objects (~3 % here).
4. **`research/tools/dartdis.py`** for full coverage: linear Capstone disassembly of `_kDartIsolateSnapshotInstructions`, with object-pool loads (x27) resolved against `pp.txt` and call targets named from blutter's `addNames.py`.
   ```
   tools/blutter/.venv/bin/python ../gr-lab/research/tools/dartdis.py work/lib/arm64-v8a/libapp.so work/cs/blutter_out work/dis
   ```
   Outputs `dis.txt`, `xrefs.json` (pool offset → referencing functions). The docs cite `0x…` addresses in `dis.txt` and `pp+0x…` offsets in `pp.txt`.
