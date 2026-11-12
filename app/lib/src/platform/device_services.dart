import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/debug/debug_log.dart';
import 'package:grphoto/src/platform/app_dirs.dart';
import 'package:grphoto/src/platform/background_downloads.dart';
import 'package:grphoto/src/platform/media_saver.dart';
import 'package:grphoto/src/services.dart';

/// Services for a real camera: the camera layer on the phone's Bluetooth
/// and Wi-Fi, downloads saved to the photo library.
///
/// Android also starts the app with no screen, when a camera with live
/// geotagging is switched on. Nothing here needs one: the channels that
/// only exist with a screen are called when they are needed, and fall back
/// when they are missing ([deviceClientName], `PlatformMediaSaver`,
/// `PlatformBackgroundDownloads`).
Future<AppServices> buildDeviceServices() async {
  final dirs = await appDirectories();
  final trace = TraceRelay();
  return AppServices(
    camera: GrCameraEnvironment.device(trace: trace.call),
    trace: trace,
    media: PlatformMediaSaver(),
    background: PlatformBackgroundDownloads(),
    clientName: deviceClientName,
    dataDir: dirs.data,
    cacheDir: dirs.cache,
    debugLogDir: await DebugLog.platformDirectory(),
    askBeforeWifiJoin: Platform.isAndroid,
  );
}

/// The phone's name as the camera lists it under Paired Devices: the
/// user-set device name on Android, the generic model name on iOS, cleaned
/// up the way GR WORLD does (printable ASCII, at most 32 characters).
/// Falls back to 'GR Photo' when the platform gives nothing usable.
Future<String> deviceClientName({
  MethodChannel channel = const MethodChannel('io.jeph.grphoto/device'),
}) async {
  const fallback = 'GR Photo';
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
