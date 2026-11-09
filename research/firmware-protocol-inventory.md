# GR III / GR IV firmware protocol inventory

## Scope and evidence rules

This is an offline inventory of the extracted firmware, compared with the **GR WORLD 2.0.0 app-use baseline** in [BLE](protocol/ble.md) and [HTTP API](protocol/http-api.md). It does not execute camera code, contact a camera, or use the shared native MCP session. ELF headers, dynamic symbols, printable ASCII runs (minimum four bytes), packed UUID constants, file bytes and existing extraction reports were read with Python/pyelftools; C++ names were demangled with `c++filt`. The available parser was loaded from `tools/blutter/.venv/lib/python*/site-packages`.

Evidence classes used below:

- **Observed bytes / metadata / symbols:** reproducible from the exact SHA-256 inputs below. String locations are **file offsets**; symbol locations are raw ELF **`st_value` linked addresses**, not file offsets or observed runtime addresses.
- **Association / inference:** a named function or nearby RTTI record suggests an interpretation. It is not a demonstrated call edge or registration.
- **Unknown:** except for the separately attributed parent decompilation findings below, route installation, reachable methods, GATT properties/permissions, request parsing, error handling, model gates and runtime behavior have **not been decompiled by this inventory**. A method-labelled log string is not proof that the method is registered.

Root aliases, relative to the repository:

- **GR3:** `firmware/gr3-root/firmware.bin_extract/initramfs_extract/gzip.uncompressed_extract` (GR III directory labelled v2.20).
- **GR4:** `firmware/gr4-root/firmware.bin_extract` (GR IV directory labelled v1.20).

Executables are under `usr/bin`; shared libraries below are under `usr/lib`. Coverage is the four requested executables plus every published ELF regular file in those two `usr/lib` directories: **23 GR3 and 68 GR4 libraries**. This is not a scan of every other executable, `/lib` runtime library, RTOS instruction or raw flash region.

At the parent's request, a final focused extension also inspected `sysmgrd` dynamic symbols and RTOS printable strings for idle/AP shutdown leads; those separate inputs and limitations are identified below.

## Main findings

1. **Both webapid binaries contain more HTTP functionality than GR WORLD uses:** method-labelled literals for liveview, ping, camera shoot/compose/cancel, lens focus, camera/lens parameter writes, WLAN-only finish and debug revisions, plus named implementation symbols. This does not contradict the app document's carefully scoped “not used by this app” statement.
2. GR4 adds six method-labelled HTTP literals relative to GR3: camera logs, firmware prepare/upload/cancel, end-screen image upload and photo image-control retrieval. The accompanying firmware/log/image-control symbols also exist. The firmware routes' registration and handlers are decompiled in [firmware update](protocol/firmware-update.md#3-camera-side-gr-iv-120); `/v1/configs/firmware` is registered for PUT and DELETE, but its handler answers anything other than PUT with HTTP 400.
3. No dashed UUID strings occur in either `bled`; the custom GATT identifiers are **canonical-order 16-byte constants**. All **46 custom UUIDs** from the BLE baseline occur in GR4; **32** occur in GR3. Fourteen app-known constants are not found in GR3 in canonical, whole-reversed or GUID-little-endian encodings. That bounded absence is not a proof of runtime GATT absence.
4. There are **25 additional shared UUID-shaped constants**, absent from the app's custom UUID map, alongside useful RTTI/function names for exposure, focus, lists and aggregate notifications. Their bytes and nearby type associations are inventoried below, without asserting active registrations.
5. GR3 and GR3x Linux and INITFS payloads are byte-identical; their RTOS and outer firmware images differ. The local GR IV and GR IV Monochrome outer BIN files are **byte-identical**, despite different ZIP hashes and directory labels. Do not treat them as independent firmware builds.
6. Both v2 extraction reports still say **partial**: all reported regular files are present and match their hashes, but symlinks are metadata-only and GR4 records a removed absolute `telinit` symlink. Earlier extractor failures are superseded by v2, not silently ignored.

## Firmware identity and extraction audit

Directory/version labels are provenance labels, not independently authenticated vendor version claims. SHA-256 establishes local byte identity, not vendor signature validity. All four ZIP BIN members were read and matched to the corresponding local BIN. No firmware was flashed.

| Input path | Bytes | SHA-256 |
|---|---|---|
| `firmware/gr3_v220/decompressed.bin` | 59798532 | `5b475fcc434dec0f12e7956b02b5b38959d599b7a4ff90486263c46816a21b6d` |
| `firmware/gr3_v220/fwdc239b.bin` | 30472516 | `5c53760b3b564c87239dbf7f5c94d0f6fd91accd156ec4ba672ebfd6b861793e` |
| `firmware/gr3_v220/initfs.bin` | 13899776 | `6fb072ceb83c4f13c496b9d759511540f7d1dd07cc4b3d617761a4d48a75d6ca` |
| `firmware/gr3_v220/linux.bin` | 3062784 | `4857386b8fff7b3c1aeac3417255065c789cdadab58aedb437e30fe2684939cc` |
| `firmware/gr3_v220/rtos.bin` | 17520384 | `fb13f9b4e49abec5f036d3f9fc5e4d21ba2a4e65522efb849ac52a7151c87da9` |
| `firmware/gr3x_v170/decompressed.bin` | 59798532 | `1129b9289b3cc68ab6f407a87d60db750483cc5ae41a6609596f6fe676b14521` |
| `firmware/gr3x_v170/fwdc243b.bin` | 30472528 | `aa8e3ae1349d94e83be381c20530e41d5e57b75c27ef24ba81c7b017d6c11592` |
| `firmware/gr3x_v170/initfs.bin` | 13899776 | `6fb072ceb83c4f13c496b9d759511540f7d1dd07cc4b3d617761a4d48a75d6ca` |
| `firmware/gr3x_v170/linux.bin` | 3062784 | `4857386b8fff7b3c1aeac3417255065c789cdadab58aedb437e30fe2684939cc` |
| `firmware/gr3x_v170/rtos.bin` | 17520384 | `3d97f0f541c6711b56dcd66ffc081be97af303708cc1874b29f9bd8ee7a8d0c5` |
| `firmware/gr4_mono_v110/fwdc248b.bin` | 38919904 | `7563d7e462f0c53b6ab2fbab7cdfbbb57151a41192ee82f4f3a2108f9d77650d` |
| `firmware/gr4_v120/decompressed.bin` | 69632740 | `f5cf55a48f65d55f4ebbd40bcd1d64d1ceca3c88432a2a4ceaa93fe1cad5fc3a` |
| `firmware/gr4_v120/fwdc248b.bin` | 38919904 | `7563d7e462f0c53b6ab2fbab7cdfbbb57151a41192ee82f4f3a2108f9d77650d` |
| `firmware/gr4_v120/initfs.bin` | 21975040 | `2abd30be2abcc62248bb5cbb5757bb7541ea2287e757619b76bbf605e536058d` |
| `firmware/gr4_v120/linux.bin` | 5781504 | `748caf5c3202effdbc6f593956f8b11c6aa6975960fc0de4832455ab0e71a0f9` |
| `firmware/gr4_v120/rtos.bin` | 21018112 | `cf51224e6eb6bed79eeafa2e7923acf5434df39629510e75907c1dfbffab61a9` |
| `firmware/zips/gr3_v220.zip` | 28599247 | `7b19f9c03f2448c2b674fb919f6a86d22d6d83801521a9c1226a0e20cf0b5a2f` |
| `firmware/zips/gr3x_v170.zip` | 28599250 | `6a028e90b4f23c9e9af968b03bca5032b71f460be85fd2c49f4078366a71dc6d` |
| `firmware/zips/gr4_mono_v110.zip` | 34702809 | `bde05b3bf56a29c272284556d6795cb772eaccbbd0091d433fd52368d4d8af12` |
| `firmware/zips/gr4_v120.zip` | 34702809 | `dcc1b6fb004f0d855bb46b30a529da894c7b717501276fec2d198b3d7eb76a59` |

**Important identity consequences:**

- GR3 v2.20 and GR3x v1.70 share INITFS SHA-256 `6fb072ceb83c4f13c496b9d759511540f7d1dd07cc4b3d617761a4d48a75d6ca` and Linux SHA-256 `4857386b8fff7b3c1aeac3417255065c789cdadab58aedb437e30fe2684939cc`. Thus this Linux-userspace inventory transfers to that GR3x INITFS byte-for-byte, but not to GR3x RTOS behavior.
- Both GR4 BIN copies and both ZIP BIN members are 38,919,904 bytes with SHA-256 `7563d7e462f0c53b6ab2fbab7cdfbbb57151a41192ee82f4f3a2108f9d77650d`. Separate GR4 Monochrome decompressed/section files were not present; treating this as a separate implementation would double-count the same image. A fresh download from Ricoh's official pages on 2026-11-07 reproduced all four ZIP hashes. The shared image serves GR IV, GR IV HDF and GR IV Monochrome and selects behavior from the hardware-reported model property (BLE model codes 7, 8, 9; code 10 for an unannounced `RICOH GR IVx`). Its outer header declares GR IV 1.20; the RTOS carries per-model records (GR IV 1.20, GR IV HDF 1.20, **GR IV Monochrome 1.10**), matching Ricoh's two version labels. Per-model support matrix, GR II/GR packages and model identification: [camera models](camera-models.md).

### Section boundaries

All nine `section-manifest.json` payloads match the exact offset/length slices in their respective decompressed image and match the manifest SHA-256. These offsets refer to **decompressed.bin**, not the encrypted/compressed outer BIN. Only the three named sections are covered by this manifest.

| Model | Section | Header offset | Payload offset | Length |
|---|---|---|---|---|
| gr3_v220 | RTOS | 0x10860 | 0x10870 | 17520384 |
| gr3_v220 | LINUX | 0x10c5f70 | 0x10c5f80 | 3062784 |
| gr3_v220 | INITFS | 0x13b1b80 | 0x13b1b90 | 13899776 |
| gr3x_v170 | RTOS | 0x10860 | 0x10870 | 17520384 |
| gr3x_v170 | LINUX | 0x10c5f70 | 0x10c5f80 | 3062784 |
| gr3x_v170 | INITFS | 0x13b1b80 | 0x13b1b90 | 13899776 |
| gr4_v120 | RTOS | 0x17d18 | 0x17d28 | 21018112 |
| gr4_v120 | LINUX | 0x1423328 | 0x1423338 | 5781504 |
| gr4_v120 | INITFS | 0x19a6b38 | 0x19a6b48 | 21975040 |

The three payloads cover 34,482,944 of 59,798,532 decompressed bytes for each GR3/GR3x image, leaving **25,315,588 bytes outside these payloads**; GR4 covers 48,774,656 of 69,632,740, leaving **20,858,084 bytes outside**. Those remainders can include other sections, headers and padding; this inventory does not classify them or call them missing filesystem files. RTOS/Linux section hashes are audited, but their code is not analyzed here.

### Published filesystem audit

| Report | Evidence ID | Published files / bytes | Current gaps |
|---|---|---|---|
| `firmware/gr3-extraction-v2.json` | `ev_1c7b3e0eb570482c8e4ff72cc5e40edd1810d20acd70b3266bbc0c87fef1ec6e` | 386 / 79349923 | 178 unpublished symlinks |
| `firmware/gr4-extraction-v2.json` | `ev_bf5fecaacb3b403f19d27bd72cc2021e66e053b5e90a1a8547d87a9eeb7a432c` | 507 / 33674076 | 201 unpublished symlinks |

For **all 386 GR3 and 507 GR4 report-listed regular files**, the local copy exists, size matches, and computed SHA-256 matches the report. There are zero mismatches/missing files, zero failed chunks, and no depth-limited paths in either v2 report. The GR3 extraction expands ROMFS → gzip initramfs → cpio; GR4 expands SquashFS. Published-byte counts include intermediate files where reported, not just the final rootfs.

- GR3: 178 `unpublished-entry` gaps, all symlinks; no v2 diagnostics.
- GR4: 201 `unpublished-entry` gaps, all symlinks. Diagnostic `MaliciousSymlinkRemoved` names `/sbin/telinit` → `/usr/sbin/finit`; this is an extractor safety classification, not proof of malicious firmware.
- Both reports state that only regular files are published, without executable permission bits. Therefore the extracted directories are **analysis copies, not bootable/reconstructed root filesystems**. SONAME symlinks and absolute service links must not be mistaken for missing regular library payloads.
- Nested extracted files generally have `original_file_range: null` / unknown root-file mapping. Their file offsets cannot be added directly to an INITFS offset to obtain an outer firmware address.
- The reports were generated by unblob 26.6.4. `gr3-extraction-failed.json` records ROMFS extraction failure with `OSError: [Errno 12] Cannot allocate memory`; `gr3-extraction.json` progressed to two files but lacked `7z` for gzip; `gr4-extraction.json` lacked `sasquatch` and published zero files. The v2 reports supersede these failed attempts for filesystem availability, while preserving their own partial-coverage limitations.

## ELF comparison

The eight core files in each generation are ELF32 little-endian ARM, `e_flags=0x05000200`; executables request `/lib/ld-linux.so.3`. All have `.dynsym` and **no `.symtab`**. “Defined” below counts named non-undefined dynamic symbols of all types, not just functions. Compiler/library changes and optimization prevent symbol-count changes from measuring feature growth or loss.

GR3 executables are `ET_EXEC`, minimum PT_LOAD vaddr `0x10000`. GR4 executables are `ET_DYN` with an interpreter and minimum load vaddr zero (PIE-style layout). GR3 core shared libraries are `ET_DYN` but have nonzero linked bases: camera-controller `0x41560000`, BtStack `0x417f0000`, cmfwk `0x41110000`, shmem_manager `0x41540000`; GR4 counterparts start at zero. GR4 function symbols commonly have bit 0 set for **Thumb state**. Preserve that bit in symbol records; use `st_value & ~1` only when a disassembler needs the instruction address.

| Model / binary | Bytes | ELF type | Named dynsym / defined | GNU build ID |
|---|---|---|---|---|
| GR3 `webapid` | 1206900 | ET_EXEC | 1764 / 1413 | `676a5c5045f80953343d68f6680aab0287e07a19` |
| GR3 `bled` | 759956 | ET_EXEC | 1717 / 1449 | `761ae9fb450d81dae28325252130620842231122` |
| GR3 `netmgrd` | 214772 | ET_EXEC | 574 / 398 | `36d303c0620884d9e0a902639c34f545870d4ace` |
| GR3 `camctld` | 1164380 | ET_EXEC | 2306 / 2057 | `55b525bf67c2b6217aa5b53aab43238287b343ec` |
| GR3 `libcamera-controller.so` | 1310788 | ET_DYN | 2690 / 2446 | `0ca79ffe2c6dc0ff0cb4ba3d847d4b5b47147f19` |
| GR3 `libBtStack.so` | 550672 | ET_DYN | 1867 / 1810 | `d04f93640d46b256533315e80c286a8a12801749` |
| GR3 `libcmfwk.so` | 24304 | ET_DYN | 73 / 25 | `27bf064a39925ae0df9c2e3eb1fa10f9fcabc80e` |
| GR3 `libshmem_manager.so` | 9468 | ET_DYN | 51 / 30 | `2336ca02b1079256aad20a7ee81cadf1316df30d` |
| GR4 `webapid` | 833940 | ET_DYN | 1664 / 1230 | `d60058a12e0776c8ae1d265245638d8c451566a2` |
| GR4 `bled` | 684436 | ET_DYN | 1511 / 1212 | `65c00de7cbadfaa14eac586fb269b74c1ac018a4` |
| GR4 `netmgrd` | 165800 | ET_DYN | 497 / 300 | `42b210584fcf3394fb9701520fce2c5f9d6f343b` |
| GR4 `camctld` | 638012 | ET_DYN | 1905 / 1640 | `8d8a9ca66e3f9b3e1b1eb6ce51e2744a4a6b9b36` |
| GR4 `libcamera-controller.so` | 867304 | ET_DYN | 2394 / 2149 | `ae393c0d67155d7d10f568f0f3199bb3877a87ea` |
| GR4 `libBtStack.so` | 959852 | ET_DYN | 2488 / 2415 | `5cc14b407d88d8e0439d6b9ba23cb9f32219c8b2` |
| GR4 `libcmfwk.so` | 21896 | ET_DYN | 63 / 16 | `3993e6f62e06231bd0709e8f9860f094a81887f9` |
| GR4 `libshmem_manager.so` | 9448 | ET_DYN | 43 / 21 | `384528ebdcb28eb0bee97ac1c0eb39f27345d518` |

### Dependency observations

`webapid`, `bled` and `netmgrd` all declare `libcamera-controller.so`; `bled` additionally declares `libBtStack.so`. `camctld` and `libcamera-controller.so` declare shmem_manager, cmfwk, protobuf and gRPC C++ libraries. This is dependency metadata, not a recovered execution trace.

Notable GR3 → GR4 library changes: protobuf 15.0.1 → 30.0.6; grpc++_unsecure 1.8.5 → 1.46.7; grpc_unsecure/gpr ABI 4 → 24; TBB 2 → 12.5; OpenSSL 1.0.0 → 3; libstdc++ 6.0.22 → 6.0.29; Boost filesystem 1.61 → 1.78. GR4's published `usr/lib` also contains Abseil/upb/address_sorting libraries and libiperf. GR3 webapid declares boost_system and pthread, while GR4 does not; absence from DT_NEEDED is not proof of removed threading or networking.

No `/v1/` ASCII literal was found in the 91 scanned shared-library files. Their role is supported instead by named camera commands, RPC paths and dependencies. Full per-file hashes are at the end.

## HTTP and WebSocket literal inventory

The following are **complete standalone method-labelled ASCII strings** found in webapid (19 GR3, 25 GR4), plus the standalone changes path. These are observed log/dispatch-description literals, **not decompiled route registrations**. Offsets are the first byte of the whole displayed string. `<string>` route-template literals separately occur for photo binary/info/transfer paths in both builds and imgctrl in GR4; the table uses the method-labelled `{}` forms.

“App” refers to the app-use table in `http-api.md` §1, not arbitrary mentions elsewhere in that document. “Not used” means the app analysis does not list a caller; it does not mean an inaccessible firmware route.

| Literal | GR3 offset | GR4 offset | App baseline |
|---|---|---|---|
| `GET /v1/debug/revisions` | 0xe57f4 | 0xaf368 | Not used |
| `GET /v1/ping` | 0xe5890 | 0xaf404 | Not used |
| `GET /v1/photos` | 0xe58a0 | 0xaf414 | Listed |
| `GET /v1/photos/infos` | 0xe58b0 | 0xaf424 | Native-only; no Dart caller |
| `GET /v1/props` | 0xe58c8 | 0xaf43c | Listed |
| `PUT /v1/params/device` | 0xe58d8 | 0xaf44c | Listed |
| `PUT /v1/params/lens` | 0xe58f0 | 0xaf494 | Not used |
| `PUT /v1/params/camera` | 0xe5904 | 0xaf464 | Not used |
| `GET /v1/liveview` | 0xe591c | 0xaf4d0 | Not used |
| `GET /v1/transfers` | 0xe5930 | 0xaf4e4 | Listed |
| `POST /v1/device/finish` | 0xe5944 | 0xaf4f8 | Listed |
| `POST /v1/device/wlan/finish` | 0xe595c | 0xaf510 | Not used |
| `POST /v1/lens/focus` | 0xe5978 | 0xaf4a8 | Not used |
| `POST /v1/camera/shoot` | 0xe598c | 0xaf47c | Not used |
| `POST /v1/camera/shoot/compose` | 0xe59a4 | 0xaf52c | Not used |
| `POST /v1/camera/shoot/cancel` | 0xe59c4 | 0xaf54c | Not used |
| `GET /v1/photos/{}/{}` | 0xe59e4 | 0xaf5f0 | Listed |
| `GET /v1/photos/{}/{}/info` | 0xe59fc | 0xaf608 | Listed |
| `PUT /v1/photos/{}/{}/transfer` | 0xe5a18 | 0xaf624 | Listed |
| `GET /v1/logs/camera` | not found | 0xaf4bc | Listed |
| `PUT /v1/configs/firmware` | not found | 0xaf56c | Listed |
| `POST /v1/configs/firmware/prepare` | not found | 0xaf588 | Listed |
| `POST /v1/configs/firmware/cancel` | not found | 0xaf5ac | Listed |
| `PUT /v1/device/image/endscreen` | not found | 0xaf5d0 | Listed |
| `GET /v1/photos/{}/{}/imgctrl` | not found | 0xaf644 | Listed |
| `/v1/changes` | 0xe5b50 | 0xaf7b8 | WS listed; literal does not establish upgrade behavior |

**Baseline mismatch to retain, not paper over:** the app uses `GET /v1/status/device`, but that exact path/method-labelled literal is not present among the scanned webapid strings in either build. This does not prove an absent route: status routes can be assembled or registered from fragments. Route-builder decompilation is required. Conversely, `/v1/liveview` and `/v1/camera/shoot` are firmware observations even though the official app uses BLE remote shooting and no HTTP liveview.

Liveview data-plane clues in **both** webapid files:

- `Content-Type: multipart/x-mixed-replace; boundary=--boundary`: GR3 file offset `0xea13c`, GR4 `0xb5290`.
- `--boundary`: GR3 `0xea180`, GR4 `0xb52d4`.
- Source-path diagnostics name `src/server/liveview.cpp` and frame address/size, FPS, valid-socket changes and socket close operations.
- Symbols include `Liveview::ExecLiveview`, `SendHeader`, `SendFrame`, `SendSingleFrame`, `SendFrameLoop`, `SendDummyFrame`, `IsValidRequest`, and `LiveviewStatus::Fetch`.

These are strong **static candidates for a multipart liveview stream**, not verification of JPEG framing, query syntax, frame rate, streaming lifetime, permissions or actual output. Do not invent a `size`, `fps`, autofocus or shoot payload from symbol names.

## Additional-route verification

This follow-up distinguishes four independent questions: **app caller**, **firmware implementation**, **historical production use**, and **successful execution on a particular camera**. None substitutes for the others. “Not used” in the inventory above is only the earlier app-analysis baseline, not proof of universal absence.

### Native implementation and registration

The ten additional paths are registered in the inspected GR III and GR IV `WebapiServer::Run` implementations without a per-route experimental/model/environment check around those registration statements. The GR III conditional blocks in this region perform object/function-wrapper cleanup; they are not feature switches. This says nothing about downstream camera state, supported settings, or future API guarantees.

On GR IV, Ghidra did not classify several Thumb dispatch wrappers as functions; consequently a plain `xrefs` query to their handlers returned empty results. **That was an analysis gap, not evidence of dead code.** The registration pointers were followed with explicit Thumb disassembly. All ten wrappers call the corresponding handlers. Saved commands, raw disassembly and binary SHA-256: `firmware/evidence/gr4-extra-route-wrappers.json`. This is an LLVM observation, not a fabricated REA Evidence record. Provider pointers are rebased by `0x10000`; clear Thumb bit 0 before comparing to linked ELF addresses.

| Route | Verified GR IV implementation | What remains unproved |
|---|---|---|
| `GET /v1/liveview` | `Liveview::ExecLiveview` parses resolution/FPS query parameters, selects a valid request, serializes execution, reads/sets resolution, requests remote-LV ON, sends a header/frame loop, then requests OFF and closes the socket. `SendFrame` fetches a camera frame and sends its buffer. handler (`firmware/evidence/gr4-route-liveview.json`), frame path (`firmware/evidence/gr4-route-send-frame.json`) | Actual image frames, accepted settings and camera-state prerequisites on hardware; a dummy-frame fallback also exists. HTTP 200 alone is not a liveview test. |
| `POST /v1/camera/shoot` | Parses form-style key/value data, validates focus position and shutter mode, constructs a release option, calls capture release and returns its result. handler (`firmware/evidence/gr4-route-shoot.json`) | Actual capture and saved photo, supported modes, busy-state behavior. |
| `POST /v1/lens/focus` | Parses focus position and issues a capture-release operation with a different release option. handler (`firmware/evidence/gr4-route-focus.json`) | Physical focus response and exact coordinate contract; decompiler argument types are not a payload specification. |
| `POST /v1/camera/shoot/compose` | Calls the capture interface's compose operation and maps the result. handler (`firmware/evidence/gr4-route-compose.json`) | Applicable capture mode and physical outcome; the name alone does not define the UI behavior. |
| `POST /v1/camera/shoot/cancel` | Calls the capture interface's timer-cancel operation and maps the result. handler (`firmware/evidence/gr4-route-cancel.json`) | Cancellation in a supported active timer state. Do not assume generic cancellation of every exposure. |
| `PUT /v1/params/lens` | Parses key/value body, reads capture mode and dispatches through `LensParams::SetParams`; that implementation validates keys, invokes setters and handles failures. entry (`firmware/evidence/gr4-route-lens-params.json`), setter (`firmware/evidence/gr4-route-lens-set.json`) | Supported parameter/value combinations and effective state changes. |
| `PUT /v1/params/camera` | Parses body, reads capture mode, dispatches camera parameter setters and fetches the resulting parameter response. entry (`firmware/evidence/gr4-route-camera-params.json`), setter (`firmware/evidence/gr4-route-camera-set.json`) | Supported parameter/value combinations and effective state changes. |
| `POST /v1/device/wlan/finish` | Calls device command `ChangeWlanMode` with zero; this is a real disconnect operation, not a health probe. handler (`firmware/evidence/gr4-route-wlan-finish.json`) | AP shutdown and recovery on hardware. Test last, deliberately. |
| `GET /v1/ping` | Reads camera datetime and serializes a response. handler (`firmware/evidence/gr4-webapid-ping.json`) | Runtime response and indirect power-policy effects. No explicit keep-awake reset was identified. |
| `GET /v1/debug/revisions` | Executes the fixed command `cat /etc/revisions/*`, returning output or a failure string. handler (`firmware/evidence/gr4-route-revisions.json`) | Public support/stability. This is explicitly a diagnostic route, even though its implementation is present. |

These are **substantive shipped implementations**, not merely unused strings or unconditional “not implemented” handlers. This does not prove that every downstream camera command succeeds. The GR III counterparts also contain real parsing/controller/frame paths; the saved `gr3-route-*.json` records corroborate a cross-generation implementation rather than a GR IV-only addition. Several GR III decompilations have unreachable-block warnings, so they are not proof that all omitted error paths are absent.

### Controller linkage, not just handler names

GR IV `CameraController::GetCaptureCommand` initializes the concrete capture-command object with the vtable at provider address `0xf02e8` (factory (`firmware/evidence/gr4-controller-get-capture-command.json`), vtable bytes (`firmware/evidence/gr4-capture-vtable.json`)). Slots `+0x08`, `+0x0c`, `+0x10`, `+0x14`, `+0x18` resolve to `Release`, `Compose`, `CancelTimer`, `ChangeRemoteLvMode`, `GetRemoteLvFrame`, respectively. The named implementations construct `CameraRequest` objects, call `CameraCommandClient::CameraCommandSync` and check responses. Frame retrieval builds a `LiveviewFrame` from returned parameters; it is not a constant success stub.

Key records: `ev_84e1b0b755405bd1bb59f023d6d3d9d5a56c0d5dd9e1b22405e0d77f3420323e` (GR IV liveview), `ev_63954d8dd173336a3c89cfddc9d8caede053783d0a82dfc6f17011f5fc261e28` (LV mode IPC), `ev_6006eedbafc4f13e45353ec07eeb500c51bbc034cf481e220b095f41cbef06b1` (frame IPC), `ev_68ca0cfb08f175d38b8aa799bb3ffea2f1aa727285fd2106b621dbcfabfb17d0` (GR III liveview). Full session evidence: `firmware/evidence/extra-route-analysis-bundle.json`. Backend/RTOS state acceptance is not established by a successful decompilation.

### App use and historical production evidence

The expanded [GR WORLD app audit](protocol/http-api.md#3-remote-shooting--live-view) found no caller for these ten routes, including after searching all 1,476 APK members and checking request builders/UI paths. This is build-scoped static evidence. Independently, [Ricoh's current GR WORLD FAQ](https://www.ricoh-imaging.co.jp/english/support/qa/gr-world/) explicitly answers: **“No. Live View is not supported in the app.”** It describes remote shooting as Bluetooth shutter release and says exposure adjustment is unsupported. **Image Sync is a different app:** [its official release history](https://www.ricoh-imaging.co.jp/english/products/app/image-sync2/) added GR III remote capture on 2019-08-08 (Image Sync 2.0.5, camera firmware 1.10+) and documents III/IIIx Live View rotation in 2022. Its [functional manual](https://www.ricoh-imaging.co.jp/english/products/app/image-sync2/manual-00.html) documents Live View, exposure control and touch AF.

All ten exact method/path pairs appear in a [2022-06-16 GR IIIx firmware investigation](https://notes.secretsauce.net/notes/2022/06/16_ricoh-gr-iiix-80211-reverse-engineering.html). The author reports liveview JPEG output, but does not individually demonstrate every other operation. This argues against “new ongoing-development-only route strings”; it is not a guarantee of mature behavior or public support for every route.

| Route | Independent historical evidence | Safe conclusion |
|---|---|---|
| `/v1/liveview` | Ricoh's [GR II GR Remote client](https://www.ricoh-imaging.co.jp/english/products/gr_remote/app/latest/gr/js/grist.js); IIIx 2022 camera report; [GR IV 2026-10-09 report](https://github.com/sky18Dragon/RICOH-GR-Live-View-Shooting/blob/8c4fc0f768b8a14369b9b2a426d90177d7405efb/logs/2026-10-09-maxfps7-gr4-smoke.md) and associated raw log record `/v1/liveview?maxfps=7` and decoded/rendered 720×480 JPEGs. | Strongest operational corroboration. GR IV firmware version is unspecified; our camera/firmware combinations remain untested. |
| `/v1/ping` | Official GR Remote 1.2.1 GR II scanner sends this GET; [official release page](https://www.ricoh-imaging.co.jp/english/products/gr_remote/) dates 1.2.1 to 2015-12-25. | Established historical client use, not proof of keep-awake semantics on III/IV. |
| `/v1/params/camera` | Official [GR Remote UI](https://www.ricoh-imaging.co.jp/english/products/gr_remote/app/latest/gr/js/gr-app.js) issues exposure PUTs on II; Image Sync documents III/IIIx exposure controls. | Production feature history is strong; exact stock-IV parameter compatibility is not established. |
| `/v1/params/lens` | IIIx 2022 inventory and [community Image Sync 2.1.17-derived schema](https://github.com/CursedHardware/ricoh-wireless-protocol/blob/main/openapi.yaml), specifying `focusSetting`. | Historical static/schema corroboration, not a captured successful stock-IV write. |
| `/v1/lens/focus` | Same schema specifies `pos=x,y`; Image Sync documents III/IIIx touch AF. | Do not borrow GR II `/lens/focus/lock` behavior/coordinate units for this distinct route. Stock-IV focus operation remains unverified. |
| `/v1/camera/shoot` | Official GR II UI sends `af=camera` or touch position; III/IIIx Image Sync has production remote capture. | Historical implementation is real, but the GR IV liveview client uses BLE shutter. Its successful photos do not prove HTTP shooting. |
| `/v1/device/wlan/finish` | Released [StickS3 v4.0.0 client](https://github.com/sky18Dragon/RICOH-GR-Live-View-Shooting/blob/v4.0.0/src/gr_api.cpp) sends empty POST; IV log records transmission. | Request is exercised by a third-party client, but it does not read the response and also sends BLE WLAN-off. Independent HTTP effect is unproved. |
| `/v1/camera/shoot/compose` | IIIx 2022 inventory and Image Sync-derived schema. | Historical presence, not a demonstrated operation in an applicable mode. |
| `/v1/camera/shoot/cancel` | IIIx 2022 inventory and Image Sync-derived schema. | Historical presence; distinguish it from GR II `shoot/finish`. Current native implementation calls `CancelTimer`; hardware behavior remains unverified. |
| `/v1/debug/revisions` | IIIx 2022 inventory and current native fixed-command implementation. | Real diagnostic implementation, not an advertised stable application API. |

**Do not overgeneralize third-party claims:** [GR4-WebCam](https://github.com/lemonadesaltbagel/GR4-WebCam) has HTTP shooting/exposure callsites but requires modified GR IV 1.11 firmware; that is not stock-IV validation. A [IIIx 1.50 liveview-plus-BLE-shot report](https://github.com/sky18Dragon/RICOH-GR-Live-View-Shooting/blob/8c4fc0f768b8a14369b9b2a426d90177d7405efb/logs/2026-10-12-gr3x-landscape-shot-lockup.md) describes a camera lockup requiring battery removal, with confounded configuration changes. A [deprecated IV-HDF client](https://github.com/sky18Dragon/RicohViewfinder) reports significant heating during sustained BLE+Wi-Fi liveview. These are third-party observations, not our measurements or established causes. They justify controlled, model-specific testing rather than a blanket “all routes work and are production-safe” label.

### Hardware verification boundary

At this pass, `route -n get 192.168.0.1` selected the default gateway on the Mac's wired interface, not a directly attached camera subnet. A read-only `GET http://192.168.0.1/v1/props` failed to connect to port 80. No liveview, shutter, parameter-write, cancel or WLAN-off operation was sent. **None of the ten routes is hardware-verified by this investigation.**

To qualify a camera/model/firmware combination: identify it with `/v1/props`; obtain and decode multiple changing sensor frames (not just a 200 response or dummy frame); verify shutter via a newly saved image; verify focus/settings against observable/read-back state; exercise compose/cancel only in their applicable capture mode; test WLAN-off last and rejoin. Record exact firmware, mode, request, HTTP and application status, payload, and physical outcome. Do not use firmware-upload or arbitrary debug actions as probes. A successful result would establish that combination, not a vendor promise of support across models/releases.

## GATT UUID inventory versus the app

The 46 custom identifiers below are the app's six custom services and 40 characteristics. Each positive offset is an exact canonical-order 16-byte match in `bled`; there are no dashed text UUIDs in either `bled`. “Not found” is bounded to canonical, full-byte-reversed and Windows-GUID little-endian layouts in that binary. Standard short UUIDs (`180A`, `2A24` etc.) and CCCD `2902` require registration/structure decoding; their possible two-byte occurrences are too ambiguous for a literal-only inventory. The full 128-bit CCCD literal is not found in these bled files. The ASCII `258EAFA5-E914-47DA-95CA-C5AB0DC85B11` in webapid is the **WebSocket handshake GUID**, not a GATT service.

| App UUID | App field/service label | GR3 file offset | GR4 file offset |
|---|---|---|---|
| `009a8e70-b306-4451-b943-7f54392eb971` | Cancel. The app uses it only to cancel a running 10 s self-timer countdown | 0x8b8fc | 0x93cb0 |
| `0936b04c-7269-4cef-9f34-07217d40cc55` | Image Control Custom 2 data | not found | 0x91568 |
| `0d2fc4d5-5cb3-4cde-b519-445e599957d8` | serialNumberString | 0x86698 | 0x8e12c |
| `0f291746-0c80-4726-87a7-3c501fd3b4b6` | Client Registration | 0x80830 | 0x8b358 |
| `0f38279c-fe9e-461b-8596-81287e8c9a81` | passphrase | 0x8eac8 | 0x945e8 |
| `1452335a-ec7f-4877-b8ab-0f72e18bb295` | operationMode | 0x87ce8 | 0x8fd90 |
| `28f59d60-8b8e-4fcd-a81f-61bdb46595a9` | Phone location for geotagging | 0x896dc | 0x90310 |
| `30adb439-1bc0-4b8e-9c8b-2bd1892ad6b0` | Image Control Custom 1 name | not found | 0x91518 |
| `35fe6272-6aa5-44d9-88e1-f09427f51a71` | modelNumberString (e.g. "GR IV"; gates firmware check 0x54b6c0, compared to "GR IV" at 0xda754c) | 0x86660 | 0x8e118 |
| `39879aac-0af6-44b5-afbb-ca50053fa575` | FirmwareUpdateResult (`bled` name; [firmware update](protocol/firmware-update.md#36-ble-characteristics-in-bled)) | not found | 0x8ee90 |
| `3e0673e0-1c7b-4f97-8ca6-5c2c8bc56680` | Image Control Custom 1 data | not found | 0x91554 |
| `430b80a3-cc2e-4ec2-aacd-08610281ff38` | operationModeList | 0x87cb0 | 0x8ee54 |
| `460828ac-94eb-4edf-9bb0-d31e75f2b165` | available5GHz | not found | 0x94610 |
| `4b445988-caa0-4dd3-941d-37b4f52aca86` | Camera State | 0x80810 | 0x8b338 |
| `559644b8-e0bc-4011-929b-5cf9199851e7` | Shutter release (enum member startOrStopRecording, so it presumably also starts/stops movie recording **[inferred]**) | 0x8b8c4 | 0x93ca0 |
| `5f0a7ba9-ae46-4645-abac-58ab2a1f4fe4` | FirmwareUpdateStart (`bled` name) | not found | 0x8ee7c |
| `63bc8463-228f-4698-b30d-faf8e3d7bd88` | security | not found | 0x945fc |
| `6fe9d605-3122-4fce-a0ae-fd9bc08ff879` | bluetoothDeviceName | 0x86708 | 0x8e154 |
| `78009238-ac3d-4370-9b6f-c9ce2f4e3ca8` | Capture mode | 0x8b7dc | 0x93c60 |
| `84a0dd62-e8aa-4d0f-91db-819b6724c69e` | GPS | 0x80840 | 0x8b368 |
| `875fc41d-4980-434c-a653-fd4a4d4410c4` | batteryLevel | 0x87c40 | 0x8fd80 |
| `90638e5a-e77d-409d-b550-78f7e1ca5ab4` | ssid | 0x8ea90 | 0x945d4 |
| `9111cdd0-9f01-45c4-a2d4-e09e8fb0424d` | networkType, used as **WLAN on/off** | 0x8ea58 | 0x945c0 |
| `97e34da2-2e1a-405b-b80d-f8f0aa9cc51c` | bluetoothMacAddressString | 0x86740 | 0x8e168 |
| `9a5ed1c5-74cc-4c50-b5b6-66a48e7ccff1` | Camera Information | 0x80800 | 0x8b328 |
| `9f00f387-8345-4bbc-8b92-b87b52e3091a` | Camera Control (shooting) | 0x80820 | 0x8b348 |
| `a0c10148-8865-4470-9631-8f36d79a41a5` | storageInformation | 0x87d58 | 0x8fdb0 |
| `a36afdcf-6b67-4046-9be7-28fb67dbc071` | geoTag enabled | 0x87d20 | 0x8fda0 |
| `a3c51525-de3e-4777-a1c2-699e28736fcf` | Shooting (exposure) mode + user mode | 0x8b764 | 0x93c40 |
| `b29e6de3-1aec-48c1-9d05-02cea57ce664` | Drive mode (includes self-timer) | 0x8b720 | 0x93c24 |
| `b4eb8905-7411-40a6-a367-2834c2157ea7` | firmwareRevisionString ("major.minor") | 0x866d0 | 0x8e140 |
| `b5589c08-b5fd-46f5-be7d-ab1b8c074caa` | Capture status | 0x8bb7c | 0x93d60 |
| `b58ce84c-0666-4de9-bec8-2d27b27b3211` | cameraPower | 0x87c08 | 0x8fd70 |
| `bd6725fc-5d16-496a-a48a-f784594c8ecb` | powerOffDuringTransfer | 0x87dd0 | 0x8fdd0 |
| `c4b7dfc0-80fd-4223-b132-b7d25a59cf85` | wlanFreq | not found | 0x94624 |
| `cd879e7a-ab9f-4c58-90ed-689bae67ef8e` | Image Control Custom 3 data | not found | 0x9157c |
| `d9ae1c06-447d-4dea-8b7d-fc8b19c2cdae` | fileTransferList | 0x87d90 | 0x8fdc0 |
| `df77dd09-0a48-44aa-9664-2116d03b6fd7` | Image Control Custom 3 name | not found | 0x91540 |
| `e450ed9b-dd61-43f2-bdfb-6af500c910c3` | FirmwareUpdateAvailable (`bled` name) | not found | 0x8fde0 |
| `e799198f-cf3f-4650-9373-b15dda1b618c` | Image Control Custom 2 name | not found | 0x9152c |
| `ef437870-180a-44ae-affd-99dbd85ade43` | cameraName | not found | 0x8ee68 |
| `f37f568f-9071-445d-a938-5441f2e82399` | WLAN Control | 0x80850 | 0x8b378 |
| `f5666a48-6a74-40ae-a817-3c9b3efb59a6` | manufacturerNameString | 0x86628 | 0x8e104 |
| `f759f4dd-5faf-4cac-82f4-5a3fe11737e7` | end-screen data | not found | 0x8eea4 |
| `fa46bbdd-8a8f-4796-8cf3-aa58949b130a` | dateTime | 0x87c78 | 0x8ee40 |
| `fe3a32f8-a189-42de-a391-bc81ae4daa76` | Phone (client) name shown by the camera **[inferred]** | 0x85730 | 0x8de14 |

The fourteen GR4-only matches are six image-control custom name/data UUIDs; camera name; firmware-update available/start/result; end-screen data; WLAN frequency/security/available-5GHz. This strengthens the app document's optional-characteristic hypothesis for this particular GR3 build without proving runtime service exposure. In particular, the nine older Camera State identifiers already occur in GR3, so the app's “default MY GR IV” label is not sufficient to classify the entire service as GR4-only.

### Additional shared UUID-shaped constants

These 25 constants are absent from the app's custom UUID map but occur byte-for-byte in **both** firmware bled files. Discovery was a four-byte-aligned UUID-v4/variant scan of GR4 `.rodata`, corroborated by an exact 16-byte match in GR3. That produced 57 shared candidates: 32 app-known plus these 25. It is not an exhaustive search for every possible UUID version/encoding.

The **candidate type association** comes from the adjacent GR3 record: a pointer at UUID offset +20 resolves to an RTTI record, whose name pointer resolves to the displayed C++ type. This is observed data proximity and valid RTTI decoding, **not proof that a service constructor registers the UUID with that type or advertises it**. GR4 shares the bytes but its layout differs. `InitService` and the named handlers below are the next authority needed for registration, access properties and payloads.

| Additional UUID constant | Candidate RTTI type (ble_server:: prefix omitted) | GR3 offset | GR4 offset |
|---|---|---|---|
| `d8676c92-dc4e-4d9e-acce-b9e251ddcc0c` | `BluetoothControl::BLEEnableCondition` | 0x856f8 | 0x8de00 |
| `faa0aeaf-1654-4842-a139-f4e1c1e722ac` | `CameraService::CamSrvNotification` | 0x87bd0 | 0x8fd60 |
| `671466a5-5535-412e-ac4f-8b2f06af2237` | `Shooting::ShootingNotification` | 0x8b568 | 0x93bb4 |
| `2ac97991-a78b-4cd4-9ae8-6e030e1d9edb` | `Shooting::HFShootingNotification` | 0x8b5a0 | 0x93bc4 |
| `d3ce2aed-10fa-4648-833d-cd74c6f35905` | `Shooting::ShutterSpeed` | 0x8b5e0 | 0x93bd4 |
| `3911f22d-9771-479d-b2b9-f729d9baf9dc` | `Shooting::Aperture` | 0x8b620 | 0x93be4 |
| `206bd02c-78b2-42c4-820a-cf30e0963909` | `Shooting::ISO` | 0x8b660 | 0x93bf4 |
| `30bcc8eb-725d-4048-a832-e76ae26a57e9` | `Shooting::ExposureCompensation` | 0x8b6a0 | 0x93c04 |
| `2361f4ff-2c7e-4fc5-876b-f9b0efbc06fd` | `Shooting::WhiteBalance` | 0x8b6e0 | 0x93c14 |
| `ed58217e-1839-43b2-bcd7-dc48c36ac0de` | `Shooting::MeteringMode` | 0x8b7a4 | 0x93c50 |
| `95bfa8ca-4680-424d-b27c-aac20d86e48b` | `Shooting::FileType` | 0x8b814 | 0x93c70 |
| `9838bb04-4abb-4c12-ae22-626d02e3704b` | `Shooting::JPEGResolution` | 0x8b84c | 0x93c80 |
| `404f6626-1294-407f-ab3d-ddc6b805b6bc` | `Shooting::MovieConfiguration` | 0x8b88c | 0x93c90 |
| `b355330d-4adc-4434-a222-7b91404b4788` | `Shooting::ShutterSpeedList` | 0x8b93c | 0x93cc0 |
| `4866f4a9-2c83-457b-b393-b9535e1447e5` | `Shooting::ApertureList` | 0x8b97c | 0x93cd0 |
| `9c83df56-fd93-4639-8ca7-857bb7b3ca3d` | `Shooting::ISOList` | 0x8b9bc | 0x93ce0 |
| `01879798-28ee-4d97-92c9-fd249c88bbcc` | `Shooting::ExposureCompensationList` | 0x8b9fc | 0x93cf0 |
| `fb673486-2a76-41b8-88f7-f88552fe5745` | `Shooting::WhiteBalanceList` | 0x8ba3c | 0x93d00 |
| `f4b6c78c-7873-43f0-9748-f4406185224d` | `Shooting::DriveModeList` | 0x8ba7c | 0x93d10 |
| `f3bfb222-c62b-4aaa-bb61-ef6486626cc8` | `Shooting::FileTypeList` | 0x8bab4 | 0x93d20 |
| `89458f80-50a1-42c1-b031-1bc6082179c0` | `Shooting::FocusMode` | 0x8baf4 | 0x93d30 |
| `cdfc734e-ea21-427d-a69f-c1a0f7f1e9a3` | `Shooting::AutoFocusStatus` | 0x8bb34 | 0x93d40 |
| `12d262ba-d8bf-44b0-8e85-c414a40230a9` | `Shooting::ShotCount` | 0x8bbbc | 0x93d70 |
| `f662dcd8-ac6e-4e02-a4b2-ce92cd44c7c3` | `Shooting::ShootingModeList` | 0x8bbfc | 0x93d80 |
| `31b28dab-bd3c-4c27-aa08-f379bf737c1e` | `Shooting::FocusSettingList` | 0x8bc3c | 0x93d90 |

Named functions corroborate the presence of exposure/focus implementation families: `Shooting::{ShutterSpeed,Aperture,ISO,ExposureCompensation,WhiteBalance,MeteringMode,FileType,JPEGResolution,MovieConfiguration,FocusMode}::{Read,Write}` and list/read/notify families are visible in dynamic symbols. This expands firmware investigation targets beyond the app's smaller Camera Control map. It does **not** establish that any particular firmware characteristic permits those operations, accepts arbitrary enum values or is active on this model.

GR4 also retains generic `Characteristic::{Read,Write,Notify,ReadData,WriteData,ReadUint32Data,WriteUint32Data,ReadStringData,WriteStringData}` symbols and specialized image-control/firmware handlers. A missing per-characteristic `Write` symbol may therefore reflect generic dispatch, not read-only access.

## Internal protocol literals and shared-library bridge

The following are local IPC endpoint **literals**, not public camera HTTP routes or observed listening sockets:

| Binary | Literal | GR3 offset | GR4 offset |
|---|---|---|---|
| `bled` | `unix:/tmp/bled_camev.sock` | 0x7f3a8 | 0x88900 |
| `bled` | `unix:/tmp/bled_ifcmd.sock` | 0x7f38c | 0x888e4 |
| `netmgrd` | `unix:/tmp/netmgrd.sock` | 0x257d4 | 0x21304 |
| `camctld` | `unix:/tmp/server.sock` | 0xcdfb8 | 0x89c94 |
| `libcamera-controller.so` | `unix:/tmp/` | 0x119a3c | 0xb5458 |
| `libcamera-controller.so` | `unix:/tmp/server.sock` | 0x124768 | 0xbbf28 |

Both `camctld` and `libcamera-controller.so` contain these gRPC-looking method path literals in both generations (same string set). The socket literals and `_unsecure` library names suggest local RPC plumbing; they do not establish remotely exposed unauthenticated services.

- `/camera_controller.RemoteSharedMemory/Alloc`
- `/camera_controller.RemoteSharedMemory/Free`
- `/camera_controller.remote_cameraif.RemoteCameraCommand/CameraCommandSync`
- `/camera_controller.remote_cameraif.RemoteCameraEvent/IssueEvent`
- `/camera_controller.remote_cameraif.RemoteCameraEventDispatcher/AddExpStatusEventListener`
- `/camera_controller.remote_cameraif.RemoteCameraEventDispatcher/AddPropertyEventListener`
- `/camera_controller.remote_cameraif.RemoteCameraEventDispatcher/AddStatusEventListener`
- `/camera_controller.remote_cameraif.RemoteCameraEventDispatcher/ConnectToServer`
- `/camera_controller.remote_cameraif.RemoteCameraEventDispatcher/RemoveExpStatusEventListener`
- `/camera_controller.remote_cameraif.RemoteCameraEventDispatcher/RemovePropertyEventListener`
- `/camera_controller.remote_cameraif.RemoteCameraEventDispatcher/RemoveStatusEventListener`
- `/camera_controller.remote_cameraif.RemoteInterfaceCommand/InterfaceCommand`
- `/camera_controller.remote_cameraif.RemoteInterfaceCommandDispatcher/ConnectToServer`
- `/camera_controller.remote_cameraif.RemoteInterfaceCommandDispatcher/SetDeviceCommandReceiver`
- `/camera_controller.remote_cameraif.RemoteInterfaceCommandDispatcher/SetPropertyCommandReceiver`
- `/camera_controller.remote_cameraif.RemoteInterfaceCommandDispatcher/UnsetDeviceCommandReceiver`
- `/camera_controller.remote_cameraif.RemoteInterfaceCommandDispatcher/UnsetPropertyCommandReceiver`
- `/camera_controller.remote_cameraif.RemoteInterfaceEvent/IssueEvent`

`CaptureCommandImpl::{Release,FocusControl,ChangeRemoteLvMode,GetRemoteLvFrame,Compose,CancelTimer}` in libcamera-controller are useful bridge targets. `CameraCommandTxTask::Run`, `CameraCommandRxTask::Run`, `CameraIFImpl::RxHandler` and `IpcuChannel::SendCmd` in camctld are useful candidates for following commands toward the RTOS. Their names/dependencies alone do not establish the exact call path or IPC command numbering.

## Named decompilation targets

Addresses below are raw `.dynsym` `st_value`. GR3 shared-library values include their nonzero linked base; GR4 odd values carry Thumb state. Both are **not runtime addresses**. Start with `WebapiServer::Run` and its constructor/callees to establish route registration, then the handler; start with `InitService` to establish GATT registration before relying on nearby UUID/type associations. No call-edge or handler behavior is claimed by this table.

| Binary | Named target (argument list omitted) | GR3 st_value | GR4 st_value |
|---|---|---|---|
| `webapid` | `webapi_server::WebapiServer::Run` | 0x47978 | 0x34271 |
| `webapid` | `webapi_server::Capture::Shoot` | 0x84800 | 0x69e6d |
| `webapid` | `webapi_server::Capture::Focus` | 0x84f68 | 0x6a11d |
| `webapid` | `webapi_server::Capture::Compose` | 0x83438 | 0x6904d |
| `webapid` | `webapi_server::Capture::CancelShootTimer` | 0x834a8 | 0x690c5 |
| `webapid` | `webapi_server::Capture::SetCompAdjustOffset` | 0x83b2c | 0x69621 |
| `webapid` | `webapi_server::Liveview::ExecLiveview` | 0x887e0 | 0x6fbe1 |
| `webapid` | `webapi_server::Liveview::SendHeader` | 0x86c14 | 0x6f01d |
| `webapid` | `webapi_server::Liveview::SendFrameLoop` | 0x88504 | 0x6f5a1 |
| `webapid` | `webapi_server::Liveview::SendSingleFrame` | 0x88274 | 0x6f3c5 |
| `webapid` | `webapi_server::LiveviewStatus::Fetch` | 0xca8f0 | 0x96df9 |
| `webapid` | `webapi_server::PingResponse::Create` | 0x7e24c | 0x659f1 |
| `webapid` | `webapi_server::Property::SetCameraParams` | 0x9513c | 0x7a535 |
| `webapid` | `webapi_server::Property::SetLensParams` | 0x94e18 | 0x7a309 |
| `webapid` | `webapi_server::Device::FinishWlan` | 0x862a4 | 0x6b071 |
| `webapid` | `webapi_server::Firmware::PreSendFirmware` | not found | 0x6cbf5 |
| `webapid` | `webapi_server::Firmware::SaveFirmware` | not found | 0x6d689 |
| `webapid` | `webapi_server::Firmware::DeleteFirmware` | not found | 0x6c3c5 |
| `webapid` | `webapi_server::Device::UpdateEndScreenImage` | not found | 0x6b195 |
| `webapid` | `webapi_server::Logs::GetCameraLog` | not found | 0x71d19 |
| `bled` | `ble_server::CameraInformation::InitService` | 0x5b87c | 0x473dd |
| `bled` | `ble_server::CameraService::InitService` | 0x5fdbc | 0x4ce21 |
| `bled` | `ble_server::Shooting::InitService` | 0x71a2c | 0x63c99 |
| `bled` | `ble_server::WLANControl::InitService` | 0x80f80 | 0x77879 |
| `bled` | `ble_server::GPSControl::InitService` | 0x66d98 | 0x59e21 |
| `bled` | `ble_server::BluetoothControl::InitService` | 0x59e9c | 0x45a09 |
| `bled` | `ble_server::WLANControl::NetworkType::Write` | 0x815a4 | 0x76919 |
| `bled` | `ble_server::WLANControl::SSID::Write` | 0x80cb0 | 0x77115 |
| `bled` | `ble_server::WLANControl::Passphrase::Write` | 0x80e18 | 0x77395 |
| `bled` | `ble_server::Shooting::Shutter::Write` | 0x77a18 | 0x68fed |
| `bled` | `ble_server::Shooting::Shutter::release` | 0x70348 | 0x62335 |
| `bled` | `ble_server::Shooting::Aperture::Write` | 0x6f734 | 0x618cd |
| `bled` | `ble_server::Shooting::ISO::Write` | 0x6f9c8 | 0x61ab5 |
| `bled` | `ble_server::Shooting::FocusMode::Write` | 0x70cf0 | 0x62aed |
| `bled` | `ble_server::Characteristic::Write` | not found | 0x56ee1 |
| `bled` | `ble_server::Characteristic::Read` | not found | 0x56cc9 |
| `bled` | `ble_server::CameraService::FirmwareUpdateStart::ConvertToCommand` | not found | 0x4bfb9 |
| `bled` | `ble_server::CameraService::FirmwareUpdateStart::WriteData` | not found | 0x4cbe9 |
| `netmgrd` | `netmgr::WlanDevice::Start` | 0x21670 | 0xf609 |
| `netmgrd` | `netmgr::WlanDevice::Stop` | 0x20a68 | 0xe541 |
| `netmgrd` | `netmgr::WlanCommandHandler::RecvChangeWlanRunningState` | 0x282c0 | 0x16bb5 |
| `netmgrd` | `netmgr::WlanCommandHandler::RecvGetPropertyCurrent` | 0x28350 | 0x16cb1 |
| `libcamera-controller.so` | `camera_controller::CaptureCommandImpl::Release` | 0x415de110 | 0x636c1 |
| `libcamera-controller.so` | `camera_controller::CaptureCommandImpl::ChangeRemoteLvMode` | 0x415df41c | 0x63ce5 |
| `libcamera-controller.so` | `camera_controller::CaptureCommandImpl::GetRemoteLvFrame` | 0x415df688 | 0x63e75 |
| `libcamera-controller.so` | `camera_controller::CaptureCommandImpl::FocusControl` | 0x415df994 | 0x6406d |
| `libcamera-controller.so` | `camera_controller::DeviceCommandImpl::ChangeWlanMode` | 0x415e4c14 | 0x7bd61 |
| `camctld` | `camera_controller::remote_cameraif::DaemonRpcServer::Run` | 0x8c658 | 0x612a9 |
| `camctld` | `camera_controller::CameraCommandTxTask::Run` | 0x6d180 | 0x4d051 |
| `camctld` | `camera_controller::CameraCommandRxTask::Run` | 0x6ed2c | 0x4cac9 |
| `camctld` | `camera_controller::CameraIFImpl::RxHandler` | 0x7c5c8 | 0x558dd |
| `camctld` | `camera_controller::IpcuChannel::SendCmd` | 0x91474 | 0x647cd |

Exact mangled lookup names for the highest-priority shared targets:

```text
_ZN13webapi_server12WebapiServer3RunEv
_ZN13webapi_server7Capture5ShootERKN4crow7requestE
_ZN13webapi_server8Liveview12ExecLiveviewERKN4crow7requestE
_ZN13webapi_server12PingResponse6CreateERKN4crow7requestE
_ZN10ble_server8Shooting11InitServiceEv
_ZN10ble_server11WLANControl11InitServiceEv
```

Priority questions for the decompiler owner:

1. Are the ten extra method-labelled HTTP routes installed unconditionally, model-gated or disabled? What methods, query/body keys, preconditions and errors are actually accepted?
2. Does ping alter a keep-awake/session timer indirectly? The parent found camera datetime reading, not an apparent explicit idle reset; neither a symbol name nor that limited observation proves the complete absence of side effects.
3. How do liveview headers/frame boundaries, `SendSingleFrame` versus looping, dummy frames and cancellation work? Which controller commands enable/disable remote LV?
4. Do all UUID constants become GATT entries, with which service, read/write/notify flags and authentication requirements? Confirm candidate RTTI associations and generic GR4 dispatch.
5. What IPC/RTOS command IDs and enum values implement the exposure/focus features not used by GR WORLD? A `Write` symbol is not a payload specification.

### Parent decompilation findings (stronger, separately attributed evidence)

The parent reported these findings while this inventory was in progress. Their saved evidence binds to the same GR4 SHA-256 files inventoried here. They supersede literal-only uncertainty for the specific statements below, but do not turn the rest of the literal tables into decoded behavior:

- **Registered GR4 routes:** `WebapiServer::Run` at provider address `0x44270` registers `/v1/ping`, `/v1/liveview`, `/v1/camera/shoot` and additional routes. Saved evidence: `gr4-webapid-run.json`, `ev_098ba99152c22f911039773444c04d8cc041094a3319e9fc4e56d1be1c6fc07d`. The report's raw ELF symbol value is `0x34271`; the provider uses a `0x10000` load-base shift and clears Thumb bit 0. Do not confuse these coordinate systems.
- **Ping:** `PingResponse::Create` at provider `0x759f0` reads camera datetime, with no apparent explicit idle reset in the parent's decompilation. Evidence: `gr4-webapid-ping.json`, `ev_7431377c40d0dfe27b1328a238820e8001c01cb7b8a21005858851eabfaf83bc`. This is not a demonstrated keep-alive contract or a proof of no indirect effects. **The app's lack of ping does not establish why a camera disconnects.**
- **Firmware/WebSocket callback:** `Firmware::WebsocketConnectStatusCallback` at provider `0x7c630` cancels an active update. Evidence: `gr4-webapid-fw-ws-callback.json`, `ev_e19a324b4cc3310ef0a9a5ca6298bbfa37ed11f01b2bd939fb0ef5dcca41412f`. Do not generalize this firmware-transfer behavior into an AP idle policy.
- **BLE WLAN request:** `WLANControl::NetworkType::Write` at provider `0x86918` maps first byte equal to `1` to device-command vtable slot `+0x20` with argument `1`, otherwise `0`. Evidence: `gr4-bled-wlan-write.json`, `ev_7b6b3b3125339263ff0ce929134e5803638410857179c5d248daa0fa160d496d`. That is stronger evidence for the on/off request encoding, not the downstream idle-time policy.

The initial `agent://parent` address did not resolve; subsequent targets were delivered successfully to the parent's registered name `Main`. No shared native MCP session was used by this inventory.

### Additional REA native findings

The following analysis was run through REA/Ghidra against the extracted binaries. Evidence JSON and available pseudocode are retained under `firmware/evidence/`; addresses are provider coordinates within each saved record, not outer firmware offsets.

| Finding | Saved evidence | Evidence ID |
|---|---|---|
| GR III `WebapiServer::Run` (`0x47978`) registers ping, liveview, lens focus, camera shoot/compose/cancel, device/WLAN finish, camera/lens/device parameters, photo/transfer routes, debug revisions and changes. Route registration alone does not specify all accepted payloads or prerequisites. | `firmware/evidence/gr3-webapid-run.json` | `ev_48574057750d91061fedd806cd1a3528346bbb6bfed3326fb4a493a3c3121fdd` |
| GR III ping calls `datetime::GetCurrentValue`, corroborating the GR IV observation; no explicit idle-timer reset was identified in either handler. Indirect effects remain unknown. | `firmware/evidence/gr3-webapid-ping.json` | `ev_f512fad2cc0bc71c47628b223f793859d9456ea93ecae467aeca095697ae87e3` |
| GR IV WLAN state request `0` calls `WlanDevice::Stop`; nonzero calls `Start`, passing whether the mode differs from `1`. This is request dispatch, not proof of an inactivity policy. | `firmware/evidence/gr4-netmgr-wlan-request.json` | `ev_79d5ac256c88ebb93b5e189a3006b41448106e2edf2673131d543ac822d19cec` |
| GR IV network-manager worker registers device/property handlers, starts its WLAN monitor, waits for shutdown, then stops the monitor, unregisters handlers and stops the WLAN device. | `firmware/evidence/gr4-netmgr-manager-worker.json` | `ev_e3f11d4f8b9905941780ffe0414c6758d8940aa28db7f72aba0e4ae4b661d7e3` |
| GR IV WebSocket close removes the connection from a set and calls registered callbacks with state `2`. The separately analyzed firmware-update callback does not establish a general AP-off policy. | `firmware/evidence/gr4-webapid-close.json` | `ev_ca3b200184f366b8622e3e4d236efae3dfab74f9d489e19ce16deed849895c60` |
| GR III Crow HTTP deadline code queues a callback; separate cleanup deletes a connection object when neither reading nor writing. Neither is an AP inactivity timer. No timeout duration is claimed. | `firmware/evidence/gr3-http-deadline.json`, `firmware/evidence/gr3-http-idle-delete.json` | `ev_f74eded94283ef38f37c955f5fde5e0ae7dd07f566876584839b19daa3261afc`, `ev_dd14f72f47de05223543b6ef03e13b479ff1750f966e114935980f15d2c78200` |

**AP startup:** the GR IV extracted `usr/bin/start_wlan.sh` selects `/tmp/hostapd.conf`, rejects station mode, starts hostapd, assigns `192.168.0.1/24` to `uap0`, and starts udhcpd. It checks `hostapd_cli -i uap0 ping` for `PONG` up to 30 times with 100 ms sleeps. This approximately three-second polling budget excludes command time and proves neither beacon visibility nor client association. It is not an idle shutdown timer. The saved `gr4-netmgr-device-start` and `gr4-netmgr-device-stop` decompilations show construction of the start/stop shell commands.

**Power-policy boundary:** the analyzed GR IV sysmgr property handler synchronizes datetime for property `8` when its changed flag is set; other properties are logged as not interesting. Its shutdown and Bluetooth-only handlers are retained separately. These Linux-side handlers do not establish the RTOS auto-off threshold or which activity resets it. The WLAN monitor async wrapper was recovered, but the underlying worker body was not resolved to a Ghidra procedure; do not describe the wrapper as a decoded monitor policy.

**Decompiler limitation:** `gr3-liveview-busy-timeout` contains numerous unreachable-block warnings, including code associated with a busy-timeout string. Do not infer a numeric liveview timeout from that pseudocode or interpret eliminated blocks as proof that the timeout never runs.

**RTOS provider coverage:** REA CLI 6.8.0 with Ghidra 12.1.4 successfully analyzed GR IIIx v1.70 `rtos.bin` as raw little-endian ARM using the caller-supplied mapping `0x53000000`, after the MCP request exceeded its 300-second transport deadline. The configured CLI search completed in 243.51 seconds and returned 93 string matches for `wlan|wifi|auto.?off`. Evidence `firmware/evidence/gr3x-rtos-wireless-strings.json`, `ev_dacd332543b69cd9087e85acce46e66ad7a0d1c7b5037521cdecc8bbe4d17b97`, includes `[AutoOffFactor]` at `0x53d19a2c`. Addresses depend on that supplied mapping; string presence is not recovered timer logic or proof of a hardware address.

The corresponding REA xref query returned one reference, `0x5409280c`, retained in `firmware/evidence/gr3x-rtos-autooff-xrefs.json`, `ev_e41dfaaa38e5d08a8e93d170880ed81302e8b835d7e2724aa32f052fff6e1c34`. This raw reference has not been resolved into a timer/reset implementation. Neither the reference nor the `[AutoOffFactor]` label supplies a duration or establishes WLAN shutdown causality.

### Camera idle / AP auto-off investigation leads

These are **new symbol/string observations, not decompiled causes**. `sysmgrd` lives at `<root>/usr/bin/sysmgrd`: GR3 SHA-256 `0299be25779cda35be7ff55dc285d86ba059c5728e1fea036c570da625fcc959`; GR4 SHA-256 `be95797377ff2aeb0616ae24ac95e26b216982d16c6ea8887ccf5f692867ea7c`.

- `sysmgr::SystemCommandHandler::RecvShutdown(unsigned int)`, exact symbol `_ZN6sysmgr20SystemCommandHandler12RecvShutdownEj`: GR3 raw `0x244fc` (4296 bytes), GR4 raw `0x12615` (4040 bytes; provider likely `0x22614`). Both contain `received Shutdown logging={}`, `shutdown.sh`, `Shutdown result: {}`. This looks like a shutdown executor; the deciding timer/caller is not established.
- GR4 `camctld` data symbols: `DeviceCmdset::ChangeWlanMode` at `0xab7c0`, `IfDeviceCmdset::IfChangeWlanRunningState` at `0xabe28`, `IfStatChangedCmdset::IfBTOnlyFWBleSleepTransitionStartNotified` at `0xabf4c` (all in `camera_controller`). These are command/event constants, **not function entries**. Follow them through `CameraCommandTxTask::Run`, `CameraCommandRxTask::Run` and `CameraIFImpl::RxHandler` listed above.
- GR4 `libcamera-controller.so`: `InterfaceEventImpl::IssueBTOnlyFWBleSleepTransitionStartNotified()` raw `0x83c89`, and `DeviceCommandImpl::ChangeWlanMode(unsigned int)` raw `0x7bd61` are useful event/command bridge targets. `netmgrd`'s `RecvChangeWlanRunningState`, `WlanDevice::Start` and `Stop` distinguish requested shutdown from autonomous policy.
- GR4 `bled` raw `BleServer::Sleep()` `0x37195`, `OnDisconnect(...)` `0x37a75`, and `btlib::EnterSleepMode(...)` `0x8560d` are BLE-specific leads. Their names do not imply Wi-Fi/AP shutdown.

RTOS **file offsets** (use the exact section hashes above; no load address was recovered here):

| Literal | GR3 RTOS offset | GR4 RTOS offset |
|---|---|---|
| `SetupAutoPowerOff` | `0xb2b620` | `0xdb6da0` |
| `EnableUniqueAutoPowerOffTime` | `0xb4d824` | `0xde3e94` |
| `[AutoOffFactor]` | `0xd19a2c` | `0xfc4b58` |
| `Auto Power Off...` | `0xd3315c` | `0xfe061c` |
| `CF No AutoPowerOff Time` | not found in this string search | `0xfc6470` |
| `invalid control state : wlan %d \| ble off` | not found in this string search | `0xedb160` |

These seed RTOS xrefs for camera auto-off configuration and transition reasons. They do not yet establish whether camera power-off, Wi-Fi-only idle timeout, client link loss, or a host command explains a disconnect.

## Exact analyzed ELF hashes

Paths are `<root>/usr/bin/<name>` for the four executables and `<root>/usr/lib/<name>` for all other rows. These hashes were computed from the analyzed local bytes and agree with the corresponding v2 extraction-file records. This appendix includes every scanned published shared library, not only the four camera-specific libraries. SONAME symlinks remain report metadata as described above.

| Generation | File | Bytes | SHA-256 |
|---|---|---|---|
| GR3 | `bled` | 759956 | `fd2b2678eea1bf8191c1f4346dfaade458fdcb4cea2952b06c6d3aa09f449740` |
| GR3 | `camctld` | 1164380 | `ec86ff1f592d61e1ca5c2e4dba72f3787b6cbf0d46c064efc11fbbfdff0d9b77` |
| GR3 | `libBtStack.so` | 550672 | `59b682b846f3bc2c05582acca30ef8fe105eeae085b7af26d2543173c4674435` |
| GR3 | `libboost_filesystem.so.1.61.0` | 79060 | `a5c74469ecfcc885ca669a5d60e07c2bde305ef4cf52d95c057bbe29b7ed013c` |
| GR3 | `libboost_system.so.1.61.0` | 10464 | `0aa70c7e82887e244987c63403fcf178fd7692792331a5f553aeee6d6835eb6e` |
| GR3 | `libcamera-controller.so` | 1310788 | `040b7deeebf5e26342b3c4e365b06a5301dd172ede895be226be6922ded668e7` |
| GR3 | `libcares.so.2.2.0` | 62312 | `03009c5c8fc1ca55bdd14ee4421728a3ec612b5ff5c6f5f58e5146634f6767dd` |
| GR3 | `libcmfwk.so` | 24304 | `b58ccaf47141dc8ba2142b7bdde6504b9a63922cb18c3c21648fb7196c722c30` |
| GR3 | `libcrypto.so.1.0.0` | 1462956 | `0445f089d50c6f1a3813c244471db17dbd70298894f7d21f586dfdc5e748de0c` |
| GR3 | `libdbus-1.so.3.14.7` | 256664 | `2aef72e9d3ec2b25e267aacf2ab963219add89301c0c55acef02ac469ed87159` |
| GR3 | `libexpat.so.1.6.2` | 135936 | `7e0d0898666ff7f2757385340189475bc17a91c42ae260008ff7d8f642f61eb5` |
| GR3 | `libgpr.so.4.0.0` | 45456 | `1207816250268fe1bbf3b1f5208d36c00f10b474edc0d2b510153e4a246ac0d5` |
| GR3 | `libgrpc++_unsecure.so.1.8.5` | 221380 | `cbc19dbeb9494502ea7ab583d0f2ba4018417f402685e7b73dd3d10a7a19b314` |
| GR3 | `libgrpc_unsecure.so.4.0.0` | 787344 | `cc9a266e93f63cbc9fbe3a61a4c002d04a8f58acc39b76672383f610f330924f` |
| GR3 | `libkmod.so.2.3.1` | 61728 | `49028061f7617fa2b332cc6c988bc85fa78669f688f72ca85d18dfa02db7d87b` |
| GR3 | `liblzma.so.5.2.2` | 128956 | `1f7d92c4a4629c2a73717cb85cf63fee06644fa0e07e67ec9425c7812f1e4e89` |
| GR3 | `libnl-3.so.200.23.0` | 105164 | `1c93f61c8fb7fdedfe417e4acaf72783e619874c4d0f24d73601501be98b1f30` |
| GR3 | `libnl-genl-3.so.200.23.0` | 17524 | `84a594ebf6808a0da25329f125726989e8ee959f37be2dc57a044df491a5c10d` |
| GR3 | `libnss_myhostname.so.2` | 59060 | `71a18db4158a91efafd26d93ce5d7123143e03479c87efabc4b28afbe2ac69d8` |
| GR3 | `libnss_mymachines.so.2` | 236204 | `046ed9fcc3d934cf263ad3e465cf7fbb9c00da5cbdecc6b76d9fd9e5a6006569` |
| GR3 | `libprotobuf.so.15.0.1` | 2225640 | `f9ca1d1463a66672f2268716505725a0c2d5edeb098a4ed84f6beaf529115c73` |
| GR3 | `libshmem_manager.so` | 9468 | `6f23fe414cf7bb007909898575042c2e7ffa948856037b9ba616e49899f3dbad` |
| GR3 | `libssl.so.1.0.0` | 313332 | `b316b3a6be92d70d4dc7fd0c387f0c39ddde8cc3ec9fc29c731892b0b4aaa18f` |
| GR3 | `libstdc++.so.6.0.22` | 1278420 | `55b522c03c2c6efb047280671cf8d3c38dd464da2efc9450fa47fcc5b8a519d8` |
| GR3 | `libtbb.so.2` | 167024 | `5f8272cd9f8e38a3ce8c2ba48ec20a8ae5d328d700727d9528dc530fb5292f7b` |
| GR3 | `netmgrd` | 214772 | `97b8b715a1e4180a975a5f0c3bb79c9c6a375778b871e8296d10bbc11f0be912` |
| GR3 | `webapid` | 1206900 | `75ffb326f53a469b48f2c29285963a76b3613419d5c80a9e0b633d28bb039797` |
| GR4 | `bled` | 684436 | `cace4337af0dd4b9dcf2a8078a4efedb585da9318bbfb1a30fe296c956ec35df` |
| GR4 | `camctld` | 638012 | `1342d9efde7c8c3604478cd2c5b468214063d3bc9233e5bcedb52d388f0f802f` |
| GR4 | `libBtStack.so` | 959852 | `310a759dd8ca42946cda05752c3f6ecae2bb6f8c73c27feed174707485dcd02a` |
| GR4 | `libabsl_bad_optional_access.so.0` | 5472 | `2cab41045b82dbeba90d4338f200d05f77903c9405701e2295eb68fdb7c9d214` |
| GR4 | `libabsl_bad_variant_access.so.0` | 5520 | `3b3c71d3a1a3e4c5539482b210299743dd0b8f27c64557afa3af8c3d86d939af` |
| GR4 | `libabsl_base.so.0` | 13712 | `4dceb6dd6932be6428a082a56526193306c0796b94be4ac83beb5c4cf7d84faf` |
| GR4 | `libabsl_city.so.0` | 9500 | `6cf49cf88341fcdfbe5a8f7fa81a5910c3f9027249bc5f7f034839a23c5bbccc` |
| GR4 | `libabsl_cord.so.0` | 62796 | `a02f3d082dacbc3de6ce50103381a070d5b3459e5868f6e746d8d02d956aea29` |
| GR4 | `libabsl_cord_internal.so.0` | 83284 | `077129ef7b8ea36f6514a754b32e9f6c813ec513748439228c105e18865df0e3` |
| GR4 | `libabsl_cordz_functions.so.0` | 5512 | `45c4841f915261962754148b793131f26c2f6479a7f69727ba35d00f7a8700be` |
| GR4 | `libabsl_cordz_handle.so.0` | 9620 | `59f87454c8e04b08fe2103c169603ee1dfd19b299d84afb6bb3693afde7fa760` |
| GR4 | `libabsl_cordz_info.so.0` | 17808 | `f4a821716a2833e41afac852538775a9b076f3789817da94306d1e8666c3ad00` |
| GR4 | `libabsl_debugging_internal.so.0` | 13664 | `9e7303380dcb5ed021d3378cd94ac30bafed869373cacbc9b2e31a14b67d166b` |
| GR4 | `libabsl_demangle_internal.so.0` | 21904 | `06f5e136cd26175544642b47429502ee4f8965cb033371870afe952e858b105a` |
| GR4 | `libabsl_exponential_biased.so.0` | 5464 | `ed5e313417ee387d062304b13e91151f242dc8aa9ba1c9aca3ab744c2d67da80` |
| GR4 | `libabsl_graphcycles_internal.so.0` | 13660 | `318ea75b545c86ad000d0e8b3412a6c225d81c83e02b85b019b0652ca937b57e` |
| GR4 | `libabsl_hash.so.0` | 5456 | `f6713c5b1954f434a7610a1c97783affef1ee41ae3814c16b3abc77d69ab0392` |
| GR4 | `libabsl_int128.so.0` | 21836 | `965ceccab9c527d4589e1edc536d51840b838b1160537569b3449f48d19ac806` |
| GR4 | `libabsl_low_level_hash.so.0` | 5412 | `5e9d9086e30f363cc53fc00f90e3415a07314ac31d9c2757bb3a066dca2500ca` |
| GR4 | `libabsl_malloc_internal.so.0` | 13708 | `91c48fb8868e61e76766a712959600297937dc33f0fa2131dd20a4ab634c96b3` |
| GR4 | `libabsl_random_internal_platform.so.0` | 9360 | `c4ba9f24a08bd28e4ed81a457b8befab7e68b6353c14980e10469ad5f59e5dd8` |
| GR4 | `libabsl_random_internal_pool_urbg.so.0` | 13712 | `96ae96848014100cd5b8f585df9ba769a18b4cb94ef34d039cb62f6ec46567da` |
| GR4 | `libabsl_random_internal_randen.so.0` | 5468 | `acfbc93efb696e4ac9336616bb07b48d10066e8b0fc43e2de734cd10fb02bfc3` |
| GR4 | `libabsl_random_internal_randen_slow.so.0` | 9524 | `ffc17bb091c11c981ac9a82083e5181b6e9cff8095c7f5fd69e49bd0b4c12bd9` |
| GR4 | `libabsl_random_internal_seed_material.so.0` | 5476 | `6274d5a9439141dbc80aab6d5ac582e49f8b0127ba6867cf53e4213e94e67ead` |
| GR4 | `libabsl_random_seed_gen_exception.so.0` | 5476 | `39c45e98434405460d3973b8e7b08bf3a69c1943f7d8f395e6b7822578db2f37` |
| GR4 | `libabsl_raw_logging_internal.so.0` | 9588 | `b863673010ad2e6321ce0aaea287eb889147ecba7756744a2d54bf916a910bbf` |
| GR4 | `libabsl_spinlock_wait.so.0` | 5460 | `133756f99ddd7ddb643c23a69262c3350d4adc73e9f2829bbe8daec8d19936d7` |
| GR4 | `libabsl_stacktrace.so.0` | 5452 | `025020cbb988bfead816f08f18e3d196c46f6a9a74af724b82a3276b00a232ae` |
| GR4 | `libabsl_status.so.0` | 25940 | `19061f63c2ed8432797fdcebb2df57fb509f927eda69d8518cc49d49b5fc5b89` |
| GR4 | `libabsl_statusor.so.0` | 9608 | `7f2da4fbc5df4260edc678e2a2300e10ae9813371c11907c2c7863342d1c879e` |
| GR4 | `libabsl_str_format_internal.so.0` | 75100 | `ee3a94a8a3968d7f31080d6c7bb77160969412249fdd406cf49df009a47e7f83` |
| GR4 | `libabsl_strerror.so.0` | 5456 | `7c44e65da4db6a766c72f00d84042087c25e6335918f482d1b1d37c7c3fb0538` |
| GR4 | `libabsl_strings.so.0` | 91472 | `397300db2c30e2150357c9e97efa1b8aa552d413d49e7cb8bc7a1c09e16bea37` |
| GR4 | `libabsl_strings_internal.so.0` | 9564 | `7b37993b338b30bc7a404d07b8ae112703c8782c9f5ae35fa35d1a058d67b3c8` |
| GR4 | `libabsl_symbolize.so.0` | 17744 | `31144e1b9013b5c6f1d84f3751e1219ecf50ee4d2d0b3338767579b60df41633` |
| GR4 | `libabsl_synchronization.so.0` | 42420 | `1637ce2dfb5d5e5f9e080a68c931ba8ab592378df8fbd718980b55eaf2914a51` |
| GR4 | `libabsl_throw_delegate.so.0` | 13652 | `5ce0cca710c5e9ff51da574c53bccb10542bbeec6776bb58eb6260c680f516d6` |
| GR4 | `libabsl_time.so.0` | 58808 | `47ff3c0af87466a66f50da879c7b4fc459463f8cbc7e7bc5cdcc936d280f41e7` |
| GR4 | `libabsl_time_zone.so.0` | 75160 | `4e25eb0be9373965b169b7c955fadd9fee29e83e18a5bb5a86472bb5659485cc` |
| GR4 | `libacl.so.1.1.2301` | 21792 | `3fb036bf1b97b8e6f468a6a95b37ec2c770768a4dcbb298408049f5e8b95c9d6` |
| GR4 | `libaddress_sorting.so.24.0.0` | 5416 | `46e39f15e9f8b3732243747321cc7522fe9ac582b0f8fa593795a08f74a896ce` |
| GR4 | `libatomic.so.1.2.0` | 17696 | `358d6466df95290ef9d7c300cf4b37437feb649723aa0aa9adb809c062e34fbb` |
| GR4 | `libattr.so.1.1.2501` | 13600 | `52bc5a2e6fdf9f3517e500e4457b0bf755cdec9e304d917066c7613cf95d56ee` |
| GR4 | `libboost_filesystem.so.1.78.0` | 87596 | `dd26096ee028550278f1f068bcfb5944e6202e6ba9743fda8483d3d7408bb15d` |
| GR4 | `libcamera-controller.so` | 867304 | `f7377d13737ebce283b418f1a76925bc174fcee29bd078d7643d7357d578fb8b` |
| GR4 | `libcares.so.2.5.1` | 58712 | `dbfbd9ed6e74cfd8d5b4cd5c65e20b90d695cf1369f43f19626b92875374f19b` |
| GR4 | `libcmfwk.so` | 21896 | `55d9398d41689eabdd848712173c4a8fb7bb4b1567426ac7f34416b833d9f92b` |
| GR4 | `libcrypt.so.2.0.0` | 177544 | `2aff32e8da7fb08e827e68ea4a1dd94ac305b8ce9381d79c9b41c5350adca188` |
| GR4 | `libcrypto.so.3` | 2586276 | `8d9b14d1e941cc759b7ba8b1738a23d9ed57e8df5491366cf3777dc300fe8430` |
| GR4 | `libdbus-1.so.3.32.3` | 362772 | `1272500e27ba110fb520ac64ee49ef1a044263c518e0238c695c1515095cdc8a` |
| GR4 | `libexpat.so.1.11.0` | 115996 | `779a0e465ad763cdb2b551f6419a0739fe2c21e2d63efb31b9a19b0fa11ae29e` |
| GR4 | `libgpr.so.24.0.0` | 67156 | `bfa879dfe0908e6856a0e8b6400b5ac08067ed06e10d839371ee8f7d272d1319` |
| GR4 | `libgrpc++_unsecure.so.1.46.7` | 292248 | `ad6a0b6eccbc894ac10f84aab4873989c22ccfe5b782c4f0d594ba3720537e27` |
| GR4 | `libgrpc_unsecure.so.24.0.0` | 2048040 | `104a3f76269c6db8908c4184fe45d5df16df2b02820f0d6186d18dd5b9b95efa` |
| GR4 | `libiperf.so.0.0.0` | 137608 | `c45fef907b34e17782672c02cb8c6ca55dbf2736ebd9196c2cca2703e69e5873` |
| GR4 | `libkmod.so.2.3.7` | 50588 | `3f66fc745d9c3bbc0e9662147bdc76f5c3a533f31605bf150bdafad2c5da61ee` |
| GR4 | `libnl-3.so.200.26.0` | 91600 | `361ca3dcb4cac6f84a58027471034757babcc3b51dd82a7d976e7c66edd92c3a` |
| GR4 | `libnl-genl-3.so.200.26.0` | 18156 | `22b8112afd5ca0829c7f2bb60628f3dddde69041b5bf6aeb72b36bd1d7dc4606` |
| GR4 | `libnl-route-3.so.200.26.0` | 342532 | `d006a46ad7ced7433cd144b60a1a69a7eef68db95d6042d9b10d8976eb7dbe36` |
| GR4 | `libprotobuf.so.30.0.6` | 2101640 | `d61509c86efbc848f620be707f713c211d380a47bc7254e5abcc439184a0ee70` |
| GR4 | `libseccomp.so.2.5.3` | 103756 | `84144599d7a15d110012c72030e92ff96616e82efe6c8518db8de877a4444e9c` |
| GR4 | `libshmem_manager.so` | 9448 | `e36f2ecdb2467117f5b19a0453d007bb7258f5c01cc6c833898dab7bcbb95ab3` |
| GR4 | `libssl.so.3` | 586792 | `55205e95b67d8eabc9796fe34437c34b5d9420ed63046cab08c84f31ff8feae2` |
| GR4 | `libstdc++.so.6.0.29` | 1386156 | `2d9cb916565c7f581d5170662f50c6785f28c50815db0d77bf32ecbfdf009f00` |
| GR4 | `libtbb.so.12.5` | 185796 | `e9350257145709e399f7de9877297e2c9098013a57175ac30830ec1bbb1ecad7` |
| GR4 | `libudev.so.1.6.3` | 91592 | `0e44073c091ede9b18481c7c66766add7bc494214923bda7ece36dc22b93450e` |
| GR4 | `libupb.so.24.0.0` | 108036 | `e5a6a63c6cf7eb20d597e07579adc69e8ae49a6a136788364e0d86baee9d1d81` |
| GR4 | `libuuid.so.1.3.0` | 21936 | `1bc318fc14194731cd7af373213af15e194d2f5a0dc42e9cbaad3a051b4543a7` |
| GR4 | `libzstd.so.1.5.2` | 480876 | `42a157f558e43d07e1480e84b7a1eebd45e2f501fd069bc1001169868104abdb` |
| GR4 | `netmgrd` | 165800 | `33dc04843893256e4d7137bd2661b1e9702253c53eb09ff8700a0ae4581bcd40` |
| GR4 | `webapid` | 833940 | `27d3d36fbb8d6d5681f6901beb901600ab0a6bae34b51f3103d5e553717f8dd2` |

## Coverage limits and hand-off

Completed: exact local image/section/ZIP hashes, reported-regular-file extraction audit, requested ELF metadata and symbol comparison, HTTP/IPC literal inventory, app UUID matches and additional shared UUID candidates, precise decompiler targets, and focused sysmgrd/RTOS shutdown leads. No build, test suite, firmware execution, live-camera probe or native decompilation was performed by this inventory worker; the parent's separately supplied decompilation findings are cited above. Static findings are not runtime validation.

Not established by this inventory: authenticity of downloaded firmware, completeness of remaining decompressed image regions, restored symlinks/permissions, registration beyond the parent's specific findings, supported request/response schemas, GATT access/security flags, runtime availability, behavioral equivalence across models, any RTOS behavior, or the cause of camera/AP disconnections. Those are explicit evidence boundaries, not inferred negative results. The parent can use the exact hashes and linked addresses above to bind subsequent decompilation to the right binaries.
