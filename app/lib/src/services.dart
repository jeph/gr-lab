import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/platform/window_pose.dart';

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

  /// True while iOS keeps the app running for the queue (its continued
  /// processing task, iOS 26 and later). Without it an app off screen is
  /// suspended within half a minute (`IdleDisconnect`). Android, which runs
  /// a foreground service instead, never sets it.
  ValueListenable<bool> get continued;
}

/// Keeps GR Photo running while the phone is on a camera's Wi-Fi, where
/// the platform would otherwise freeze an app that is not in front and with
/// it the auto-disconnect timer (`IdleDisconnect`): Android runs a
/// foreground service, whose notification shows the Wi-Fi with a
/// Disconnect button while there are no downloads ([BackgroundDownloads]
/// shares it). iOS, where the camera network outlives the app, has its own
/// rule (`GrCameraEnvironment.wifiOutlivesApp`) and nothing here.
/// `research/protocol/connection-lifecycle.md` §9.
abstract interface class CameraWifiService {
  /// Holds the service, showing [notice]; again to change what it shows.
  /// Android starts it only for an app in front.
  Future<void> hold(CameraWifiNotice notice);

  /// Keeps the phone awake for [duration] from now, so the auto-disconnect
  /// runs with the screen off; [Duration.zero] for not at all.
  Future<void> keepAwake(Duration duration);

  /// Lets the service go: the phone left the camera's Wi-Fi.
  Future<void> release();

  /// The user pressed Disconnect outside the app.
  Stream<void> get disconnects;
}

/// The camera's Wi-Fi as the platform shows it while GR Photo holds
/// [CameraWifiService]. The texts are in the app's language.
@immutable
final class CameraWifiNotice {
  const new({
    required this.title,
    required this.text,
    required this.cameraName,
    required this.disconnectLabel,
    required this.channelName,
  });

  /// `Connected to the camera's Wi-Fi`.
  final String title;

  /// When auto-disconnect leaves the Wi-Fi; empty when it never does.
  final String text;

  /// The camera, as the user named it.
  final String cameraName;

  /// The button that leaves the Wi-Fi.
  final String disconnectLabel;

  /// What Android's notification settings call these notifications.
  final String channelName;

  @override
  bool operator ==(Object other) =>
      other is CameraWifiNotice &&
      other.title == title &&
      other.text == text &&
      other.cameraName == cameraName &&
      other.disconnectLabel == disconnectLabel &&
      other.channelName == channelName;

  @override
  int get hashCode =>
      Object.hash(title, text, cameraName, disconnectLabel, channelName);
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
    required this.cameraWifi,
    required this.clientName,
    required this.appVersion,
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
    ValueListenable<WindowPose>? windowPose,
  }) : windowPose = windowPose ?? ValueNotifier(WindowPose.none);

  /// The camera layer: Bluetooth, the camera's Wi-Fi and its tracing.
  final GrCameraEnvironment camera;

  /// The vertical bar and the fold of the app's window on a foldable
  /// iPhone; [WindowPose.none] everywhere else.
  final ValueListenable<WindowPose> windowPose;

  /// The [GrCameraEnvironment]'s trace sink, pointed at the debug log by
  /// `AppModels.load`.
  final TraceRelay trace;
  final MediaSaver media;

  /// Downloads while GR Photo is not in front (`DownloadBackground`).
  final BackgroundDownloads background;

  /// Keeps the app running on a camera's Wi-Fi (`IdleDisconnect`).
  final CameraWifiService cameraWifi;

  /// Written to the camera's Paired Devices list during pairing.
  final String clientName;

  /// GR Photo's version as the App Store and the releases list it
  /// (`0.0.N`, from `flutter build --build-name`), shown at the bottom of
  /// Settings.
  final String appVersion;

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
