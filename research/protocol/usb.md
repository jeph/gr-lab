# GR cameras over USB: GR WORLD wired support and wired-client feasibility

Scope: RICOH GR WORLD 2.0.0 (Android), GR III v2.20 INITFS (shared byte-for-byte with GR IIIx v1.70, see [firmware-protocol-inventory.md](../firmware-protocol-inventory.md)) and GR IV v1.20 firmware. **All firmware findings are static.** No camera was connected. Third-party runtime reports are labelled as such. The official GR II 3.00 package (`rg2_v003.frm`, see [camera-models.md §2](../camera-models.md#2-official-firmware-packages-and-byte-identity)) has no readable strings and was not analyzed, so GR II USB behaviour is **[unknown]**.

Path abbreviations: `G3` = `firmware/gr3-root/firmware.bin_extract/initramfs_extract/gzip.uncompressed_extract`, `G4` = `firmware/gr4-root/firmware.bin_extract`. In G4 `mtpd`, virtual addresses equal file offsets (first `PT_LOAD` at 0). In G3 `mtpd`, virtual address = file offset + 0x10000.

| Binary | SHA-256 |
|---|---|
| G3 `usr/bin/mtpd` (ARM mode) | `c14698334ce0e47922b1967668a51542222c35266d29ddbc5b3007bcf7e21a8c` |
| G4 `usr/bin/mtpd` (Thumb-2, PIE) | `03aa5f836cc660a37c98f9fe6058fc083e0f5de07f18eff0ef76dd61ea3501e1` |
| G3 `usr/bin/sysmgrd` | `0299be25779cda35be7ff55dc285d86ba059c5728e1fea036c570da625fcc959` |
| G4 `usr/bin/sysmgrd` | `be95797377ff2aeb0616ae24ac95e26b216982d16c6ea8887ccf5f692867ea7c` |

## (a) Verdict: GR WORLD has no wired (USB) mode

GR WORLD 2.0.0 is **wireless only**: BLE plus Wi-Fi HTTP. Its only USB awareness is an error message telling the user to **unplug** USB because the camera refuses WLAN while USB-connected.

| Check | Result | Evidence |
|---|---|---|
| Manifest USB host feature / attach filter | None. No `uses-feature`, no `android.hardware.usb.*`, no `USB_DEVICE_ATTACHED`, no `meta-data` device filter. | `work/jadx/resources/AndroidManifest.xml` (0 matches for `usb`, 0 `uses-feature`). `res/xml/` has no device-filter XML. |
| Java/Kotlin USB or MTP APIs | None. No `UsbManager`, `UsbDevice`, `UsbDeviceConnection`, `android.mtp.*`, `MtpDevice`. | Regex search over `work/jadx/sources` (only `fmtp` RTSP hits in `p062H0/C0409x.java`). `com/ricohimaging/grapp/MainActivity.java` registers only the widget/connectivity channels. |
| Flutter plugins | 33 registered. None is USB/MTP/serial: amplify_*, android_intent_plus, app_links, app_settings, battery_plus, connectivity_plus, device_info_plus, disk_space_plus, external_path, firebase_*, flutter_blue_plus_android, flutter_foreground_task, flutter_local_notifications, flutter_secure_storage, geolocator_android, package_info_plus, path_provider_android, permission_handler_android, photo_manager, shared_preferences_android, share_plus, sqflite_android, third_party_auth, url_launcher_android, video_player_android, wakelock_plus, webcrypto, webview_flutter_android. | `work/jadx/sources/io/flutter/plugins/GeneratedPluginRegistrant.java` ("Error registering plugin …" strings) |
| Dart strings | No `usb`/`mtp`/`ptp`/`cable`/`wired`/`tether` identifiers. USB occurs only in one localized error string: "The wireless LAN function cannot be turned on when the camera is in the movie mode or connected to a device with a USB cable…" | `work/lib/arm64-v8a/libapp.so` (SHA-256 `49ced634…2ded85`) at file offset `0xfbe2a` (EN) and `0x43bca` (DE). Object pool `pp+0x694a0` (EN), plus JA `pp+0x66bf8`, ZH `pp+0x62ec8`/`pp+0x64270`, KO `pp+0x65740`, FR `pp+0x680a8`. Usage: [ble.md](./ble.md) "step2_ble_wlan_on_video_failure". |
| Official FAQ | The FAQ lists supported cameras and only BLE/Wi-Fi setup. For Wi-Fi import failures it says: "When the camera is connected to a computer via USB, the wireless LAN function cannot be used. Disconnect the USB cable and try again." | [GR WORLD FAQ](https://www.ricoh-imaging.co.jp/english/support/qa/gr-world/) |

Official camera USB features:

- GR III and GR IV specifications list the USB Type-C interface as "Battery Recharge/Power Supply (Optional AC Adapter required), **Data Transfer: MTP**, Video output: DisplayPort over USB-C (DisplayPort Alternative Mode)". GR IV also lists USB Power Delivery compatibility. Sources: [GR IV spec](https://www.ricoh-imaging.co.jp/english/products/gr-4/spec/) and [GR III spec](https://www.ricoh-imaging.co.jp/english/products/gr-3/spec/).
- Neither spec page lists MSC, PTP tethering, webcam/UVC or USB network functions.
- Ricoh's USB tethering tool, IMAGE Transmitter 2 (v2.6.2), lists 645Z, K-1, KP, 645ZIR, K-1 Mark II, G900SE, K-3 Mark III and K-3 Mark III Monochrome. No GR body appears; the GR II is listed only for Digital Camera Utility 5. Source: [software downloads](https://us.ricoh-imaging.com/pages/software-and-firmware-downloads).

## (b) Camera USB function inventory (firmware)

### Gadget composition

`sysmgrd` runs one of the `usr/bin/usb30dev_mtp_func*.sh` scripts with `<manufacturer> <model> <serial> <version>`. Each script builds a single configfs gadget:

- `bcdUSB=0x0320`, `idVendor=0x25FB`.
- **One function, `functions/mtp.usb0`**, in `configs/c.1`, with `bmAttributes=0xC0` (self-powered).
- UDC `19c00000.dwc3`.
- Default strings when no arguments are given: "RICOH IMAGING COMPANY, LTD." / "RICOH Camera".

**No script creates `mass_storage`, `uvc`, `rndis`, `ncm`, `ecm`, `acm` or `hid` functions.**

The table pairs models with scripts by **[inferred]** adjacency in sysmgrd `.rodata`, where each model string precedes a script name. G4 sysmgrd `0x1e8a0`–`0x1e92c`: `usb30dev_mtp_func.sh`, "RICOH GR IV", "RICOH GR IV HDF", `_h.sh`, "RICOH GR IV Monochrome", `_ow.sh`, "RICOH GR IVx", `_n.sh`, then "model name is invalid. default settings will be used." G3 `0x21f64`–`0x21fe4` uses the same layout for IIIx/`_n`, III HDF/`_h` and IIIx HDF/`_nh`.

| Script | Model (inferred) | idProduct | MaxPower | Script SHA-256 (prefix) | Independent corroboration |
|---|---|---|---|---|---|
| G3 `usb30dev_mtp_func.sh` | GR III | `0x210F` | 96 | `cae81cb1ff3ce9d4` | libgphoto2 "Ricoh:GR III" `0x25fb:0x210f` ([library.c](https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/library.c), [gphoto issue 1099](https://github.com/gphoto/libgphoto2/issues/1099) `lsusb`) |
| G3 `_n.sh` | GR IIIx | `0x2115` | **0** | `57e90644cd9e9ee0` | [libmtp issue 148](https://github.com/libmtp/libmtp/issues/148) `lsusb`/`mtp-detect` |
| G3 `_h.sh` | GR III HDF | `0x211E` | 96 | `d835c462f799796d` | — |
| G3 `_nh.sh` | GR IIIx HDF | `0x2121` | **0** | `567fb596570abea0` | — |
| G4 `usb30dev_mtp_func.sh` | GR IV | `0x2123` | 96 | `7bbbb4e3b84136df` | [libmtp issue 392](https://github.com/libmtp/libmtp/issues/392) `usb-devices`: `Vendor=25fb ProdID=2123`, `MxPwr=96mA`, one interface `Cls=06(still) Sub=01 Prot=01`, bulk OUT `0x01`, bulk IN `0x81`, interrupt IN `0x82` |
| G4 `_h.sh` | GR IV HDF | `0x2125` | 96 | `aefa68ba444ff7ce` | — |
| G4 `_ow.sh` | GR IV Monochrome | `0x2127` | 96 | `471d505a752e5352` | — |
| G4 `_n.sh` | GR IVx | `0x2129` | 96 | `938bf5cbb9dc8741` | — |
| G4 `_nh.sh` | (unused) | `0x2121` | 0 | `567fb596570abea0` | Byte-identical to G3 `_nh.sh`. G4 sysmgrd does not reference `_nh`. |

These USB product IDs are **not** the firmware-header product IDs (`0x024C`, `0x0261`, `0x027C`, `0x0289`, `0x028A`) listed in [camera-models.md §2](../camera-models.md). The two are separate namespaces. For BLE model codes, see [camera-models.md §4.1](../camera-models.md).

### Kernel function drivers and interface class

| Generation | Gadget function modules shipped | Used by a script |
|---|---|---|
| G3 (kernel 4.4.15) | `libcomposite.ko`, `usb_f_mtp.ko` only | `mtp` |
| G4 (kernel 5.15.196) | `libcomposite.ko`, `usb_f_mtp.ko`, `usb_f_mass_storage.ko`, `usb_f_acm.ko`, `usb_f_serial.ko`, `u_serial.ko`, `usb_f_hid.ko`, `sn_usb20_udc.ko`, plus host-side `usbserial`, `ftdi_sio`, `cp210x`, `pl2303`, `usbmon` | `mtp` only. No script, sysmgrd or usbd string references `mass_storage`/`acm`/`hid` (they appear only in `modules.*`). **[inferred]** These modules are factory/debug leftovers. |

- `usb_f_mtp.ko` is the Android `f_mtp` driver (`mtp_ioctl`, `/dev/mtp_usb`, G4 adds `alloc_inst_mtp_ptp`).
- Its only interface descriptors are **`09 04 00 00 03 06 01 01 00`** (class 6 Still Image / PTP). Offsets: G3 `0x2304`/`0x238a`, G4 `0x2113`/`0x2192`. There is no `0xFF` vendor-class (Android MTP) interface and no `MSFT100` OS descriptor. The camera therefore enumerates as a **standard PTP camera**, as the third-party GR IV dump confirms.
- The G4 module's control handler names only `MTP_REQ_CANCEL` and `MTP_REQ_GET_DEVICE_STATUS`. libgphoto2 independently reports that "a Ricoh GR IV answers [the PTP class Device Reset request] with a pipe error" and falls back to a USB port reset ([library.c](https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/library.c), comment near the `ptp_usb_control_device_reset_request` retry).
- **No UVC, RNDIS, NCM or ECM function exists in either rootfs**: no module, no script, no string. The HTTP API (`webapid`) cannot be reached over USB networking in stock firmware.
- `linux.bin` images are compressed. Built-in kernel functions were not enumerated **[unknown]**, but no userspace configures them.
- No `usb`/`mtp` strings occur in `bled`, `webapid`, `netmgrd` or `camctld`. The Linux daemons do not themselves react to USB state. The WLAN-refused-while-USB rule is **[inferred]** to be enforced by the RTOS (stated by the FAQ and the app string).

### mtpd: PTP/MTP responder

`mtpd` is Android's `MtpServer` (namespace `android::`) plus Ricoh's `mtp_server::RicohMtpDatabase`. The Ricoh layer is evidently derived from PENTAX K-3 Mark III code: it contains the string "PENTAX K-3 Mark III Monochrome" (G4 `0x642e4`, G3 `0x6d704`) and `DeviceProperty::IsK3MkIIIMono`. G3 and G4 export the same 54 `MtpServer::` symbols. Their `handleRequest` functions call the same handler set.

**Advertised in GetDeviceInfo.** `doGetDeviceInfo` (G4 `0x3fcc8`) reads `DeviceProperty::GetVendorMode`. With vendor mode 0 it writes a 14-entry operation array. With vendor mode non-zero it writes a 32-entry array that adds PENTAX operations.

| Array (G4 vaddr / G3 file offset) | Contents |
|---|---|
| Standard ops, 14 (G4 `0x60ca4`, G3 `0x69bcc`) | `1001 1002 1003 1004 1005 1006 1007 1008 1009 100A 1014 1015 1016 101B` |
| Vendor-mode ops, 32 (G4 `0x60c58`, G3 `0x69b80`) | Standard ops + `9001 9002 9003 9004 9006 9007 9009 900B 900C 900D 900E 900F 9011 9012 9013 9015 9017 9018` |
| Events, 5 (G4 `0x60c98`) | `4002 ObjectAdded, 4003 ObjectRemoved, 4004 StoreAdded, 4005 StoreRemoved, 400C StorageInfoChanged` (no `4006 DevicePropChanged`, no `400D CaptureComplete`) |
| Device properties, base (`DeviceProperty::GetSupportedDeviceProperties`, G4 `0x525bc`, G3 `0x67be8`) | `5001 BatteryLevel, 5011 DateTime, D406 SessionInitiatorInfo, D407 PerceivedDeviceType, D303 (unnamed)` |
| Device properties, vendor mode (`GetSupportedVendorDeviceProperties`, G4 `0x52ed8`) | Base set + `5005 5007 5010 5014 5015` and PENTAX `D009 LiveViewArea, D00F ShutterSpeed, D013 DriveMode, D014/D015 bracketing, D018 ColorTemp, D01B WritingFileFormat, D01E ExposureIndexEx, D020–D02D image tone/filters/sharpness/contrast/composition, D035 USBLiveViewMode, D036 ContrastAF, D037 LiveViewZoom, D039 MovieMode` (names from the `MtpDebug` table at G4 `0x70838`) |
| Formats | `getSupportedCaptureFormats` → `0x3001` (Association), `getSupportedPlaybackFormats` → `0x3000` (G4 `0x234b8`/`0x2354c`) |

Third-party runtime confirmation for GR IIIx 1.11 ([libmtp issue 148](https://github.com/libmtp/libmtp/issues/148)) shows **exactly the vendor-mode-0 lists** above:

- The 14 ops, the 5 events, and properties `5001 5011 D406 D407 D303`.
- VendorExtensionID 6, "microsoft.com/DeviceServices: 1.0".
- Storages: `0x00010001` SD (removable, DCF, R/W), `0x00080000` Internal Memory (DCF), `0x000F0001` "Software License" (read-only, generic hierarchical).

**What `handleRequest` actually dispatches** (G4 `0x40548`; standard ops through `tbh` at `0x4064c`, table `0x40650`):

| Opcode(s) | Behaviour |
|---|---|
| `1001–1009`, `100A` GetThumb (inlined: param check then thumbnail routine at `0x3b864`), `1014–1017`, `101B` GetPartialObject | Implemented |
| `95C1` GetPartialObject64 | Implemented (falls through to `doGetPartialObject(op)` at `0x4091a`). Not advertised. |
| `95C2–95C5` Android edit ops (SendPartialObject/Truncate/BeginEdit/EndEdit) | Dispatched, not advertised. Effect on a camera with no SendObjectInfo is **[unknown]**; do not use. |
| `100B` DeleteObject, `100C` SendObjectInfo, `100D` SendObject, `100F` FormatStore, `1010` ResetDevice | `0x2005` OperationNotSupported (jump target `0x40728`; `doDeleteObject`/`doFormatStore` at `0x3c018`/`0x3c020` are `movw r0,#0x2005; bx lr`) |
| `100E` InitiateCapture, `1011–1013`, `1018–101A`, all `9001–9019` PENTAX ops | Fall to the "unknown op" log path `0x40790` → `0x2005` |
| `9801–9805`, `9810–9811` MTP object-property ops | `0x2005` |
| `9090–9095` "GENERAL_PURPOSE" ops | Dispatched to `mtp_server::RicohCommand::doGeneralPurpose{SetValue,RunFunc,EndCheck,GetValue,GetData,SetData}` (G4 `0x594dc`–`0x599e4`). All call `camera_controller::CameraController::GetFactoryCommand` / `FactoryData`. **[inferred]** This is a factory/service channel. Not for client use; the risk is unknown. |

The PENTAX tether handlers exist with real bodies but **are unreachable** in GR firmware. No direct call, tail call or code-pointer table references them; the only 4-byte references are `.dynsym` entries. The handlers in question:

- `doInitiatePentaxCapture` `0x3c028`, `doGetLiveViewFrameData` `0x3c364` (uses `LiveviewFrame::GetFrameAddr/Size`, `GetIpcuRemoteLvSize`).
- `doFocusControlNew` `0x3c170`, `doSetPentaxVendorMode` `0x3c0d0`.
- `RicohMtpDatabase::terminatePentaxCapture` `0x211fc` (calls `CaptureController::Release`).

The RTOS images also contain remote-liveview plumbing: `RemoteLvBufferController` (GR III `rtos.bin` `0xc0ec44`, GR IV `0xed401c`), `ChangeRemoteLvMode`/`GetRemoteLvFrame` (GR IV `0xfcccec`/`0xfccd00`) and `IsTetherImageWritingEnable` (GR IV `0xfcea8b`).

**Conclusion:** stock GR III/IIIx/IV firmware exposes a **read-only PTP image-transfer device**. USB capture, USB liveview and USB camera settings are not reachable. This explains the third-party result that `gphoto2 --capture-image-and-download` and `--capture-preview` return "Unsupported operation" on GR III ([gphoto issue 1099](https://github.com/gphoto/libgphoto2/issues/1099)).

Unknowns:

- Whether `GetVendorMode` can ever be non-zero on a GR. Even if it were, the PENTAX ops are not dispatched.
- Whether 5011 DateTime is writable. `DeviceProperty::SetIpcuDateTime` and `MtpToIpcuDateTime` exist, and SetDevicePropValue is dispatched, but the GetSet flag has not been observed.
- The meaning of `D303`.
- RTOS settings `E_RS_SYSTEM_USERDATA_ID_USB_MODE_MODE` (GR III `0x105d1b4`, GR IV `0x139471c`) and `CMD_DEVOPT_MSC_OPERATE_START`. The [GR IV operating manual](https://www.ricoh-imaging.co.jp/resources/english/support/man-pdf/gr-4_en.pdf) setup-menu list (p.124 reference) gives "USB Setting: Image Display, License Display". **[inferred]** License Display corresponds to the "Software License" storage. It is not an MTP/MSC selector.
- Whether the camera can shoot, and so raise `ObjectAdded`, while USB-connected. The same manual (charging from a computer, printed p.42) says that on connecting to a computer "The camera turns on and enters the playback mode."
- Whether BLE stays active during USB.

Third-party runtime notes:

- [libmtp issue 392](https://github.com/libmtp/libmtp/issues/392): GR IV DNG transfers via GVFS/libmtp failed with "Unknown error"; PTP mode (gphoto2) worked.
- libgphoto2 now lists GR III/IIIx/IV as "(PTP mode)".

## (c) Feature parity: wireless path vs wired path

Wireless references: [http-api.md](./http-api.md) and [ble.md](./ble.md).

Wired column = stock PTP over USB, per section (b).

| GR WORLD feature | Wireless path (existing) | Wired (USB PTP) path | Wired available? |
|---|---|---|---|
| Discovery / identity | BLE scan + Camera Information; `GET /v1/props` | USB VID `0x25FB` + PID (table above); GetDeviceInfo Manufacturer/Model/DeviceVersion/SerialNumber | **Yes** |
| Browse (folders/files, per storage) | `GET /v1/photos[?storage=in\|sd1]` | GetStorageIDs (SD `0x00010001`, internal `0x00080000`), GetObjectHandles, GetObjectInfo (filename, size, capture date, format, thumb/image dims) | **Yes** |
| Thumbnails / preview | `?size=thumb\|view` | GetThumb `0x100A` (thumb only). Larger "view" previews require GetPartialObject of the embedded JPEG **[inferred]** or a full GetObject. | Thumbnail yes; "view" size partial |
| Full download (JPG/DNG/MOV) | `GET /v1/photos/<d>/<f>?size=full` (no Range) | GetObject `0x1009`, GetPartialObject `0x101B`, GetPartialObject64 `0x95C1` (resumable and chunked, unlike HTTP) | **Yes**, better resume |
| Photo metadata (av/tv/sv/latLng…) | `/v1/photos/<d>/<f>/info` | ObjectInfo basics only. EXIF must be parsed client-side from a GetPartialObject of the file header. | Yes, with client-side EXIF parsing |
| Image Control blob | `/imgctrl` | None (the PENTAX `D020–D02D` properties are vendor-mode only and unreachable) | **No** |
| Auto/reserved transfer (camera-marked) | `/v1/transfers`, `PUT …/transfer` | PENTAX `900B–900E` "TransferCandidate" ops exist but are not dispatched. Substitute: diff handles against the client DB, or `ObjectAdded` events if shooting while connected is possible **[unknown]**. | **No native**; app-side diff only |
| Delete | (not used by app) | DeleteObject → `0x2005` | No |
| Remote shutter | BLE `559644B8` (`01 01`) | InitiateCapture `0x100E` and PENTAX `9011` → `0x2005` | **No** |
| Liveview | `/v1/liveview` (firmware route; no app caller) | PENTAX `9006` → `0x2005`; no UVC | **No**. The only wired video is DisplayPort Alt Mode to a monitor, not host-readable. |
| Exposure/settings (`/v1/params/*`) | HTTP PUT / BLE | Vendor props unreachable; base props only | **No** |
| Clock sync | BLE `FA46BBDD` | SetDevicePropValue `0x5011` DateTime (`SetIpcuDateTime` exists) | **Probably** [inferred; verify writability] |
| GPS / geotag push | BLE GPS service | None | **No** |
| Battery / storage status | `/v1/status/device`, BLE, WS `/v1/changes` | GetDevicePropValue `0x5001`, GetStorageInfo, events `400C/4004/4005` | **Yes** |
| Firmware update | Wi-Fi `PUT /v1/configs/firmware` + BLE | SendObject unsupported; no USB DFU found | **No** (Wi-Fi or SD card only) |
| Power off | BLE / `POST /v1/device/finish` | None (PENTAX `9002` not dispatched) | No |
| GR Log / end-screen upload | HTTP | None | No |
| Coexistence | — | WLAN refused while USB-connected (app string, FAQ). BLE during USB **[unknown]**. | Wired and Wi-Fi cannot run concurrently |

### Per-platform difficulty (wired path: browse, thumbnails, download, battery/storage, clock)

| Target | API | Difficulty | Notes |
|---|---|---|---|
| Android | USB host, `UsbManager` + `android.mtp.MtpDevice` | **Low** for import. `MtpDevice` covers `getDeviceInfo`, `getStorageIds`, `getObjectHandles`, `getObjectInfo`, `getThumbnail`, `getObject`, `getPartialObject(64)`, `importFile`, `readEvent` ([reference](https://developer.android.com/reference/android/mtp/MtpDevice)). | `MtpDevice` has **no** device-property or vendor-op call. Clock/battery properties need raw PTP over `UsbDeviceConnection.bulkTransfer` on the class-6 interface (**medium**, about 300 lines). Needs `uses-feature android.hardware.usb.host`, a `USB_DEVICE_ATTACHED` filter for VID `0x25FB` (9 decimal-listed PIDs), and the per-device permission prompt. Android's own MTP/PTP documents provider may hold the device **[inferred]**. |
| iOS / iPadOS | ImageCaptureCore | **Low–medium**. `ICDeviceBrowser`, `ICCameraItem.requestThumbnail`, `ICCameraFile.requestDownload`/`requestReadData`, `ICCameraDevice.requestDeleteFiles` and **`requestSendPTPCommand`** are all iOS/iPadOS 13+ ([ICDeviceBrowser](https://developer.apple.com/documentation/imagecapturecore/icdevicebrowser), [requestSendPTPCommand](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:)), [requestReadData](https://developer.apple.com/documentation/imagecapturecore/iccamerafile/requestreaddata(atoffset:length:completion:))). `requestContentsAuthorization`/`requestControlAuthorization` are iOS 14+. | `requestTakePicture`/`requestEnableTethering` are macOS-only. Irrelevant here, since GR has no USB capture. Raw PTP allows `1015/1016` for clock/battery. Not verified on a real GR: **[unknown]** whether iOS ImageCaptureCore surfaces the GR (class-6 PTP suggests yes **[inferred]**). |
| macOS | ImageCaptureCore (same calls, macOS 10.15+; `ptpEventHandler` 12+) | **Low** | Avoid libusb/nusb on macOS. The system PTP daemon (`PTPCamera`/`ptpcamerad`) claims PTP cameras and blocks user-space claimants ([gPhoto FAQ](https://gphoto.sourceforge.io/doc/manual/FAQ.html)). |
| Windows | WPD (`IPortableDevice`) through the in-box MTP/PTP class driver | **Medium** (COM). Use WPD's object-level APIs for standard operations: enumerate objects, read the content/thumbnail resources, and read device-object properties. `WPD_DEVICE_POWER_LEVEL` gives battery (0–100) and `WPD_DEVICE_DATETIME` gives the camera clock ([device properties](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/device-properties)). Whether the driver maps writes of `WPD_DEVICE_DATETIME` to PTP `0x5011` is **[unknown]**. | WPD is **not** a general raw-PTP transport. `WPD_COMMAND_MTP_EXT_EXECUTE_COMMAND_*` takes "a vendor-extended MTP operation code" ([docs](https://learn.microsoft.com/en-us/windows/win32/wpd_sdk/wpd-command-mtp-ext-execute-command-with-data-to-read)), and GR has no vendor op worth calling. Do not plan on sending `1015/1016` through it. libusb/nusb require replacing the driver with WinUSB (Zadig/libwdi), per [nusb docs](https://docs.rs/nusb/latest/nusb/). That removes the camera from Explorer/Photos, so it is unsuitable for end users. |
| Rust core | Transport-independent session trait in the core. Raw PTP only where the OS exposes a raw pipe: `nusb` 0.2.x on Linux, and an Android `UsbDeviceConnection` fd via `Device::from_fd` (or JNI `bulkTransfer`). | **Medium**. The PTP subset needed for the raw backends is small: about 12 ops, the container format, and a 64-bit partial read. Crate `ptp` 0.5.0 is unmaintained (2016). `gphoto2` 3.4.1 wraps C libgphoto2 (LGPL, heavy for mobile). | Recommended shape: the core owns the import model (camera identity, object list, thumbnails, ranged reads, battery/storage, optional clock set), EXIF parsing, deduplication and transfer state. Per-OS backends implement that trait: the raw PTP codec on Linux/Android; ImageCaptureCore item APIs on Apple, plus `requestSendPTPCommand` only for the `0x5011` clock set; WPD object/resource/property APIs on Windows. Do not assume raw PTP everywhere: WPD offers none for standard ops, and raw nusb on macOS/Windows conflicts with OS drivers, as noted above. |

## (d) Recommendation

1. A wired mode can deliver **import only**: discovery, browse, thumbnails, full and resumable download, storage and battery, and probably clock set. The work is low–medium on every platform. It is worth offering as a fast, Wi-Fi-free bulk import, notably for DNG/MOV.
2. Wired mode **cannot** replace remote shutter, liveview, settings, Image Control, GPS, auto-transfer marking, firmware update or power-off on stock firmware. The camera answers those PTP ops with `0x2005`, and there is no UVC or USB-network function to carry the HTTP API. Keep BLE + Wi-Fi as the primary path for those features.
3. Treat wired and Wi-Fi as **mutually exclusive sessions**: the camera refuses WLAN while USB-connected. The UI should detect the USB attach and switch modes rather than attempt both.
4. Keep the core **transport-independent**: put the import model, EXIF and transfer state in the core, behind a per-OS backend trait. Use the shared PTP codec only for raw-pipe backends (Android USB host, Linux). Use ImageCaptureCore on Apple and WPD object/property APIs on Windows. Do not ship a libusb/WinUSB-only design.
5. Hardware checks before committing:
   - GetDevicePropDesc `0x5011` (GetSet flag), then a SetDevicePropValue round-trip.
   - On Windows, whether writing `WPD_DEVICE_DATETIME` through the in-box driver reaches `0x5011`, and what `WPD_DEVICE_POWER_LEVEL` returns.
   - Thumbnail size and format from GetThumb.
   - GetPartialObject64 behaviour on files over 4 GiB (MOV).
   - Whether BLE stays connected during USB.
   - Whether the camera can capture while USB-connected (`ObjectAdded`).
   - iOS ImageCaptureCore enumeration of a GR.
   - GR II USB behaviour (its firmware package was not analyzable).
   - Never send `9090–9095` (factory channel) or `95C2–95C5`.
