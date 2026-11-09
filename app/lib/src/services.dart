import 'dart:io';

import 'package:gr_camera/gr_camera.dart';

/// Saves downloaded camera files into the device photo library.
abstract interface class MediaSaver {
  /// Saves the files of one shot. [files] holds a JPEG, a DNG, both halves
  /// of a RAW+JPEG pair (same base name), or one movie. iOS stores a pair as
  /// one Photos asset (JPEG primary, DNG alternate); Android writes one
  /// MediaStore entry per file under `Pictures/<album>` or
  /// `Movies/<album>`. Throws [MediaSaveException].
  Future<void> saveShot(List<File> files, {required String album});
}

/// Why the photo library did not take a shot.
enum MediaSaveFailure {
  /// The user has not allowed GR Lab to add to the photo library.
  permissionDenied,

  /// The files are not one shot GR Lab can save, or the platform cannot
  /// save to its photo library.
  unsupported,

  /// The platform failed to save.
  failed,
}

final class MediaSaveException implements Exception {
  const new(this.failure, [this.detail]);

  final MediaSaveFailure failure;

  /// What went wrong, for the debug log. Never shown to the user: the app
  /// describes [failure].
  final String? detail;

  bool get permissionDenied => failure == MediaSaveFailure.permissionDenied;

  @override
  String toString() => 'MediaSaveException(${failure.name}): $detail';
}

/// Hands camera trace events to the debug log once it is open: the camera
/// environment is built before the app's models load (see
/// `AppModels.load`). Events before that have no log to go to.
final class TraceRelay {
  TraceSink? target;

  void call(TraceEvent event) => target?.call(event);
}

/// Everything that differs between the real device and the demo camera,
/// built once at start-up and reached through `AppScope.of(context).services`.
final class AppServices {
  new({
    required this.camera,
    required this.trace,
    required this.media,
    required this.clientName,
    required this.dataDir,
    required this.cacheDir,
    required this.debugLogDir,
    this.redialDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ],
    this.askBeforeWifiJoin = false,
    this.isDemo = false,
  });

  /// The camera layer: Bluetooth, the camera's Wi-Fi and its tracing.
  final GrCameraEnvironment camera;

  /// The [GrCameraEnvironment]'s trace sink, pointed at the debug log by
  /// `AppModels.load`.
  final TraceRelay trace;
  final MediaSaver media;

  /// Written to the camera's Paired Devices list during pairing.
  final String clientName;

  /// Persistent app data (paired cameras, settings, download records).
  final Directory dataDir;

  /// Disposable data (thumbnails, partial downloads).
  final Directory cacheDir;

  /// Where the debug log keeps its trace files.
  final Directory debugLogDir;

  /// Pauses before each quiet retry of a Wi-Fi join that failed because
  /// the app was in the background; its length is the number of tries
  /// before the failure is shown.
  final List<Duration> redialDelays;

  /// Explain the camera network before the first join of each camera.
  /// Android's approval screen names only the network, and on some phones
  /// fills the screen like a settings page; iOS asks in a small alert.
  final bool askBeforeWifiJoin;

  /// Running against the simulated camera.
  final bool isDemo;
}
