import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/connection/idle_disconnect.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/debug/debug_log.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/camera_link.dart';
import 'package:grlab/src/looks/looks_store.dart';
import 'package:grlab/src/services.dart';

/// App-wide models, created once in `main` and reached through
/// [AppScope.of]. Widgets listen to the individual notifiers.
final class AppModels {
  new({
    required this.services,
    required this.settings,
    required this.cameras,
    required this.connection,
    required this.debugLog,
    required this.looks,
  }) : idle = IdleDisconnect(connection: connection, settings: settings),
       downloads = DownloadEngine(
         dataDir: services.dataDir,
         cacheDir: services.cacheDir,
         media: services.media,
         link: ConnectionLink(connection),
       );

  static Future<AppModels> load(AppServices services) async {
    final settings = await SettingsController.load(services.dataDir);
    final cameras = await CameraStore.load(services.dataDir);
    final looks = await LooksStore.load(services.dataDir);
    final debugLog = await DebugLog.open(
      dir: services.debugLogDir,
      defaultEnabled: DebugLog.defaultEnabledFor(appFlavor),
      settings: settings,
    );
    // Every camera exchange from now on goes to the log.
    services.trace.target = debugLog.sink;
    // The native code logs only while the setting is on; tell it now and on
    // every change (the log also notifies when its size changes).
    var nativeLogging = debugLog.enabled;
    unawaited(services.camera.setNativeLogging(enabled: nativeLogging));
    debugLog.addListener(() {
      if (debugLog.enabled == nativeLogging) return;
      nativeLogging = debugLog.enabled;
      unawaited(services.camera.setNativeLogging(enabled: nativeLogging));
    });
    return AppModels(
      services: services,
      settings: settings,
      cameras: cameras,
      connection: ConnectionController(services: services, cameras: cameras),
      debugLog: debugLog,
      looks: looks,
    );
  }

  final AppServices services;
  final SettingsController settings;
  final CameraStore cameras;
  final ConnectionController connection;

  /// The app's debug log, camera traffic included, for bug reports
  /// (Settings).
  final DebugLog debugLog;

  /// The user's saved Image Control looks.
  final LooksStore looks;

  /// Leaves the camera's Wi-Fi after the app was not used for a while.
  final IdleDisconnect idle;

  /// The download queue, one engine for the app's lifetime so only it uses
  /// `downloads.json` and the job files: a photo-library save still running
  /// when the camera pages close finishes in it, and the queue carries on
  /// when they open again.
  final DownloadEngine downloads;

  /// Lets screens know when another route covers them (the Cameras screen
  /// stops scanning then).
  final routes = RouteObserver<ModalRoute<void>>();
}

class AppScope extends InheritedWidget {
  const new({required this.models, required super.child, super.key});

  final AppModels models;

  static AppModels of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.models;

  @override
  bool updateShouldNotify(AppScope oldWidget) => models != oldWidget.models;
}
