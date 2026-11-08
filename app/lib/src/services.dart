import 'dart:io';

import 'package:gr_protocol/gr_protocol.dart';

/// Saves downloaded camera files into the device photo library.
abstract interface class MediaSaver {
  /// Saves the files of one shot. [files] holds a JPEG, a DNG, both halves
  /// of a RAW+JPEG pair (same base name), or one movie. iOS stores a pair as
  /// one Photos asset (JPEG primary, DNG alternate); Android writes one
  /// MediaStore entry per file under `Pictures/<album>` or
  /// `Movies/<album>`. Throws [MediaSaveException].
  Future<void> saveShot(List<File> files, {required String album});
}

final class MediaSaveException implements Exception {
  const MediaSaveException(this.code, this.message);

  /// `permissionDenied`, `unsupported` or `failed`.
  final String code;
  final String message;

  bool get permissionDenied => code == 'permissionDenied';

  @override
  String toString() => 'MediaSaveException($code): $message';
}

/// Everything that differs between the real device and the demo camera,
/// built once at start-up and reached through `AppScope.of(context).services`.
final class AppServices {
  AppServices({
    required this.ble,
    required this.wifi,
    required this.media,
    required this.clientName,
    required this.dataDir,
    required this.cacheDir,
    required this.ensureBluetoothPermission,
    this.cameraHost = '192.168.0.1',
    this.httpFactory,
    this.sessionOptions = const GrSessionOptions(),
    this.redialDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ],
    this.askBeforeWifiJoin = false,
    this.wifiApprovalShown = const Stream.empty(),
    this.isDemo = false,
  });

  final BleTransport ble;
  final WifiNetworkControl wifi;
  final MediaSaver media;

  /// Asks for Bluetooth scan/connect permission where the OS requires it
  /// (Android 12+). Returns false when the user denied it.
  final Future<bool> Function() ensureBluetoothPermission;

  /// Written to the camera's Paired Devices list during pairing.
  final String clientName;

  /// Persistent app data (paired cameras, settings, download records).
  final Directory dataDir;

  /// Disposable data (thumbnails, partial downloads).
  final Directory cacheDir;

  final String cameraHost;

  /// Overrides the HTTP client the session builds (the demo camera serves
  /// on a loopback port).
  final GrHttpClient Function(String host, TraceSink? trace)? httpFactory;
  final GrSessionOptions sessionOptions;

  /// Pauses before each quiet retry of a Wi-Fi join that failed because
  /// the app was in the background; its length is the number of tries
  /// before the failure is shown.
  final List<Duration> redialDelays;

  /// Explain the camera network before the first join of each camera.
  /// Android's approval screen names only the network, and on some phones
  /// fills the screen like a settings page; iOS asks in a small alert.
  final bool askBeforeWifiJoin;

  /// Emits when the OS's own network screen covers the app while a [wifi]
  /// join is in progress (Android's approval list). It also comes back for
  /// a camera that was approved before, after its network was disconnected
  /// by hand in Wi-Fi settings; a join that then fails is explained and
  /// retried only if the user agrees.
  final Stream<void> wifiApprovalShown;

  /// Running against the simulated camera.
  final bool isDemo;
}
