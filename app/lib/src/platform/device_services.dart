import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/src/debug/debug_log.dart';
import 'package:grlab/src/platform/app_dirs.dart';
import 'package:grlab/src/platform/media_saver.dart';
import 'package:grlab/src/services.dart';

/// Services for a real camera: the camera layer on the phone's Bluetooth
/// and Wi-Fi, downloads saved to the photo library.
Future<AppServices> buildDeviceServices() async {
  final dirs = await appDirectories();
  final trace = TraceRelay();
  return AppServices(
    camera: GrCameraEnvironment.device(trace: trace.call),
    trace: trace,
    media: PlatformMediaSaver(),
    clientName: await deviceClientName(),
    dataDir: dirs.data,
    cacheDir: dirs.cache,
    debugLogDir: await DebugLog.platformDirectory(),
    askBeforeWifiJoin: Platform.isAndroid,
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
  final clean = pairedDeviceName(name);
  return clean == 'Unknown' ? fallback : clean;
}
