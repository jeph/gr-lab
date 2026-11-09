# Framework choice for a cross-platform GR client

Recommendation: **Flutter for the UI on all four platforms, with the camera protocol in a pure-Dart package (`gr_protocol`) and small native plugins for the parts no framework covers (joining the camera's Wi-Fi and binding traffic to it).** Revisit a Rust core only if a non-GUI consumer (CLI, sync daemon, other apps) becomes a real requirement.

## What the protocol requires

The reverse-engineered protocol (see `protocol/`) splits into two links, and both are needed on every platform:

- **BLE is the control plane** on GR III / IIIx / IV: pairing (OS bonding), turning the camera's Wi-Fi AP on and off, reading the AP's SSID and passphrase, remote shutter, drive mode, clock sync, GPS push, Wi-Fi settings, Image Control slots, battery/storage/capture-state notifications. GR WORLD does remote shooting over BLE only; it has no live view.
- **Wi-Fi (HTTP + one WebSocket at 192.168.0.1) is the data plane**: photo listing, thumbnails, downloads, camera-initiated auto-transfer, Image Control read, end-screen upload, camera logs, firmware upload. GR II is Wi-Fi only.

A desktop client therefore needs working BLE too, not only Wi-Fi: without it, it cannot switch on the camera's AP.

**macOS limitation (observed, GR IV HDF fw 1.20):** a Mac can pair, but a bonded Mac cannot reconnect. macOS connects third-party peripherals from its public address and distributes its IRK, and the camera's controller then ignores it; no CoreBluetooth or app-level option changes this ([firmware bonding §7(a)](protocol/firmware-bonding.md#a-the-mac-cannot-reconnect-after-pairing)). Encrypted BLE (Wi-Fi credentials, WLAN-on, shutter, clock) is therefore only available on the link that did the pairing. A macOS client has to be designed around that, for example by reading and storing the Wi-Fi credentials during pairing and then working over Wi-Fi with the camera's AP switched on from the camera's own menu (whether the GR IV menu can do this without a paired app is untested), or by leaving camera control to a phone. Whether Windows has the same problem is untested; it depends on the address Windows connects from.

## What the app has to do on every platform

| Capability | Android | iOS | macOS | Windows |
|---|---|---|---|---|
| BLE central (scan, bond, GATT read/write/notify) | BluetoothGatt | CoreBluetooth | CoreBluetooth | WinRT `Windows.Devices.Bluetooth` |
| Join camera Wi-Fi AP programmatically | `WifiNetworkSpecifier` + `requestNetwork` | `NEHotspotConfiguration` (Hotspot Configuration entitlement) | CoreWLAN `CWInterface.associate(to:password:)` | WinRT `WiFiAdapter.ConnectAsync` or `WlanConnect` |
| Keep camera traffic on the camera network while cellular/other Wi-Fi exists | `Network.bindSocket` / NDK `android_setsocknetwork` per socket, or `bindProcessToNetwork` | Automatic for the AP's subnet | Automatic for the AP's subnet | Automatic for the AP's subnet |
| HTTP + WebSocket to 192.168.0.1 | any | any (needs `NSLocalNetworkUsageDescription`) | any | any |
| Background location → camera (GPS tagging) | foreground service | background location mode | n/a | n/a |
| Optional wired import (USB PTP, read-only; see `protocol/usb.md`) | USB host + `android.mtp.MtpDevice` (raw PTP via `UsbDeviceConnection` for device properties) | ImageCaptureCore (iOS/iPadOS 13+, untested with a GR) | ImageCaptureCore (do not use libusb: the system PTP daemon claims the camera) | WPD `IPortableDevice` (WinUSB/libusb would hide the camera from Explorer) |

No framework provides the Wi-Fi join, per-network binding or USB PTP rows on all four platforms; every option below needs per-platform native code there. Wired import is optional: it covers browse/download/battery only, and the camera refuses Wi-Fi while USB is connected, so it is a separate session mode rather than a second transport for the same session. The PTP framing and object parsing are small enough to live in the shared protocol package; the transports stay native. The choice is therefore mostly about UI reuse and BLE maturity.

## Options

### 1. Flutter + Dart protocol package (recommended)
- One UI codebase for Android, iOS, macOS and Windows; the gallery grid, image viewer, remote-control and settings screens are the bulk of the app and are shared.
- BLE: `universal_ble` (3.2.0 on pub.dev, BSD-3-Clause) covers Android, iOS, macOS, Windows and Linux; the lab app (`apps/gr_lab`) uses it behind `gr_protocol`'s `BleTransport` interface. GR WORLD uses `flutter_blue_plus`, but since 2.x its `connect()` takes a required `License` argument: the FlutterBluePlus License is free only for personal, nonprofit and educational use, and for-profit use needs a paid commercial licence. `universal_ble` avoids that constraint; the trade-off is that the camera firmware was exercised by Ricoh against `flutter_blue_plus`'s Android/iOS behaviour, not this library's. Because only the adapter touches the plugin, swapping libraries is a one-file change.
- HTTP/WebSocket: `dart:io` `HttpClient`/`WebSocket` are sufficient for a JSON + JPEG API on a local subnet.
- Native shims needed: a `camera_wifi` plugin with four implementations (Kotlin, Swift shared iOS/macOS, C++/WinRT). Roughly 150–300 lines each.
- Weak spot: Android per-network routing. `dart:io` sockets cannot be bound to a specific `Network`, so the choices are `bindProcessToNetwork` (what GR WORLD does; breaks cloud calls while connected, and its `onLost` handling leaves the process bound to a dead network) or routing camera HTTP through a Kotlin client created from `Network.openConnection`/`getSocketFactory()`. Plan for the latter, with the `NetworkCallback` owned by a foreground service for the session's lifetime.

### 2. Native UIs + Rust core (UniFFI)
- Rust core: `btleplug` (BLE on Windows 10+, macOS, iOS, Android, Linux; central-only), `reqwest`/`hyper` + `tokio-tungstenite`, the connection state machine and transfer queue. Bindings to Swift and Kotlin via UniFFI; Windows via a C ABI or a C# binding generator.
- Strongest control over networking: on Android the core can call `android_setsocknetwork()` on each socket so only camera traffic goes over the camera AP, with no process binding.
- Cost: three UI codebases (SwiftUI for iOS+macOS, Jetpack Compose, WinUI 3). btleplug on Android requires a JNI companion, class-loader initialisation from the right thread and R8 keep rules; on Apple platforms it requires static-lib packaging into Xcode.
- Worth it if a native look on each platform or a headless CLI/daemon matters more than development speed.

### 3. Kotlin Multiplatform + Compose Multiplatform
- Shared Kotlin UI and logic; Android networking is first-class (OkHttp on `network.socketFactory`).
- BLE via Kable; its desktop/Windows support runs on the JVM through a btleplug FFI bridge and is newer than its mobile support. Desktop apps ship a JVM runtime; macOS Wi-Fi join from the JVM needs a native bridge.
- Viable, but Windows/macOS are the least mature targets for exactly the parts this app depends on.

### Not recommended
- **React Native**: Windows BLE support in the RN ecosystem is thin; desktop targets are second-class.
- **.NET MAUI**: no native macOS target (Mac Catalyst only) and uneven BLE plugin support on Windows.
- **Tauri 2**: viable through `tauri-plugin-blec` (btleplug), but mobile support is young and the UI is a web view, which is a poor fit for large thumbnail grids and full-resolution image viewing.

## Why not a Rust core by default
The disconnect problems documented in `protocol/connection-lifecycle.md` come from platform networking and connection-state handling, not from the language the protocol is written in. Those fixes live in native platform code under any option. A Dart protocol package keeps the BLE → Wi-Fi → HTTP state machine in one language next to the UI and avoids an FFI boundary for streaming data (downloads, BLE notification streams). If a CLI or background sync daemon is later required, the protocol (which is small: a GATT table and a REST/WebSocket API) can be ported to Rust then.
