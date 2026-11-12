import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

/// Saves downloaded camera files into the device photo library.
abstract interface class MediaSaver {
  /// Saves the files of one shot into the album named [album], creating the
  /// album when the photo library has none of that name. [files] holds a
  /// JPEG, a DNG, both halves of a RAW+JPEG pair (same base name), or one
  /// movie. iOS stores a pair as one Photos asset (JPEG primary, DNG
  /// alternate) and leaves the shot out of the album unless GR Photo has full
  /// access to Photos; Android writes one MediaStore entry per file under
  /// `Pictures/<album>`. Throws [MediaSaveException].
  Future<void> saveShot(List<File> files, {required String album});
}

/// Why the photo library did not take a shot.
enum MediaSaveFailure {
  /// The user has not allowed GR Photo to add to the photo library.
  permissionDenied,

  /// The files are not one shot GR Photo can save, or the platform cannot
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

/// Keeps the download queue running while GR Photo is not in front, and
/// shows it outside the app, each platform in its own way. Android runs a
/// foreground service, whose notification carries the progress and the
/// buttons. iOS 26 and later runs a continued processing task, which the
/// system shows as a Live Activity (Lock Screen and Dynamic Island) with
/// a stop button; older iOS only gets the short time it gives every app
/// that leaves the screen (`research/protocol/connection-lifecycle.md`
/// §9).
abstract interface class BackgroundDownloads {
  /// Shows [status], starting the platform's background work when none is
  /// running.
  Future<void> show(BackgroundDownloadStatus status);

  /// Ends the background work and removes what [show] put up. [finished]
  /// says the queue ended with nothing left and nothing failed (saved, or
  /// cancelled by the user), rather than stopping short: iOS closes its
  /// Live Activity as done or as failed.
  Future<void> hide({required bool finished});

  /// What the user pressed outside the app. iOS only reports
  /// [BackgroundDownloadAction.pause], also when the system itself stops
  /// the task.
  Stream<BackgroundDownloadAction> get actions;
}

/// A button of the platform's download display.
enum BackgroundDownloadAction { pause, resume, cancel }

/// The download queue as the platform shows it while GR Photo is not in
/// front. The texts are in the app's language.
@immutable
final class BackgroundDownloadStatus {
  const new({
    required this.paused,
    required this.title,
    required this.detail,
    required this.cameraName,
    required this.fraction,
    required this.toggleLabel,
    required this.cancelLabel,
    required this.channelName,
  });

  /// Paused by the user: nothing is being transferred.
  final bool paused;

  /// `Downloading`, `Downloads paused`.
  final String title;

  /// `2 of 6 · 31 MB/s`, `4 left`.
  final String detail;

  /// The camera the shots come from, as the user named it.
  final String cameraName;

  /// 0..1 across the batch.
  final double fraction;

  /// The button that pauses, or resumes while [paused].
  final String toggleLabel;

  /// The button that removes every download.
  final String cancelLabel;

  /// What Android's notification settings call these notifications.
  final String channelName;

  @override
  bool operator ==(Object other) =>
      other is BackgroundDownloadStatus &&
      other.paused == paused &&
      other.title == title &&
      other.detail == detail &&
      other.cameraName == cameraName &&
      other.fraction == fraction &&
      other.toggleLabel == toggleLabel &&
      other.cancelLabel == cancelLabel &&
      other.channelName == channelName;

  @override
  int get hashCode => Object.hash(
    paused,
    title,
    detail,
    cameraName,
    fraction,
    toggleLabel,
    cancelLabel,
    channelName,
  );
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
    required this.background,
    required this.clientName,
    required this.dataDir,
    required this.cacheDir,
    required this.debugLogDir,
    this.redialDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ],
    this.lookAgainDelay = const Duration(seconds: 20),
    this.askBeforeWifiJoin = false,
    this.isDemo = false,
  });

  /// The camera layer: Bluetooth, the camera's Wi-Fi and its tracing.
  final GrCameraEnvironment camera;

  /// The [GrCameraEnvironment]'s trace sink, pointed at the debug log by
  /// `AppModels.load`.
  final TraceRelay trace;
  final MediaSaver media;

  /// Downloads while GR Photo is not in front (`DownloadBackground`).
  final BackgroundDownloads background;

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

  /// With the app not in front and live geotagging waiting for the camera,
  /// the pause before a camera that could not be reached over Bluetooth is
  /// linked again (`ConnectionController`). \[design\]
  final Duration lookAgainDelay;

  /// Explain the camera network before the first join of each camera.
  /// Android's approval screen names only the network, and on some phones
  /// fills the screen like a settings page; iOS asks in a small alert.
  final bool askBeforeWifiJoin;

  /// Running against the simulated camera.
  final bool isDemo;
}
