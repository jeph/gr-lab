import 'package:flutter/services.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../services.dart';
import 'app_dirs.dart';
import 'ble_transport.dart';
import 'media_saver.dart';
import 'permissions.dart';
import 'wifi_control.dart';

/// Services for a real camera: BLE through `universal_ble`, the camera AP
/// joined natively, downloads saved to the photo library.
Future<AppServices> buildDeviceServices() async {
  final dirs = await appDirectories();
  return AppServices(
    ble: UniversalBleTransport(),
    wifi: PlatformWifiControl(),
    media: PlatformMediaSaver(),
    clientName: await deviceClientName(),
    dataDir: dirs.data,
    cacheDir: dirs.cache,
    ensureBluetoothPermission: ensureBluetoothPermission,
  );
}

/// The phone's name as the camera lists it under Paired Devices: the
/// user-set device name on Android, the generic model name on iOS, cleaned
/// up the way GR WORLD does (printable ASCII, at most 32 characters).
/// Falls back to 'GR Lab' when the platform gives nothing usable.
Future<String> deviceClientName({
  MethodChannel channel = const MethodChannel('io.jeph.grlab/device'),
}) async {
  const fallback = 'GR Lab';
  String? name;
  try {
    name = await channel.invokeMethod<String>('name');
  } on PlatformException {
    return fallback;
  } on MissingPluginException {
    return fallback;
  }
  if (name == null || name.trim().isEmpty) return fallback;
  final clean = GrBleClient.sanitizePairedDeviceName(name);
  return clean == 'Unknown' ? fallback : clean;
}
