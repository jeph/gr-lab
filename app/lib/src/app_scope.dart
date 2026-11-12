import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/connection/idle_disconnect.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/debug/debug_log.dart';
import 'package:grphoto/src/downloads/download_engine.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/library/camera_link.dart';
import 'package:grphoto/src/library/library_scope.dart';
import 'package:grphoto/src/looks/looks_store.dart';
import 'package:grphoto/src/services.dart';

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
    required this.idle,
    required this.geotag,
    required this.downloads,
    required this.library,
  });

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
    final connection = ConnectionController(
      services: services,
      cameras: cameras,
    );
    final idle = IdleDisconnect(connection: connection, settings: settings);
    final geotag = await GeotagController.open(
      services: services,
      connection: connection,
      cameras: cameras,
      settings: settings,
    );
    // One link for the app: the Library and the download engine see the
    // same camera library.
    final link = ConnectionLink(connection);
    final downloads = DownloadEngine(
      dataDir: services.dataDir,
      cacheDir: services.cacheDir,
      media: services.media,
      link: link,
      album: DownloadEngine.albumFor(appFlavor),
      // Background geotagging: a photo the camera gave no location gets
      // one from the phone's history before it reaches the photo library.
      beforeSave: geotag.geotagger.tag,
    );
    final models = AppModels(
      services: services,
      settings: settings,
      cameras: cameras,
      connection: connection,
      debugLog: debugLog,
      looks: looks,
      idle: idle,
      geotag: geotag,
      downloads: downloads,
      library: LibraryContext.create(
        services: services,
        cameras: cameras,
        link: link,
        downloads: downloads,
        idle: idle,
      ),
    );
    await geotag.start();
    return models;
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

  /// Live and background geotagging, run without a screen too.
  final GeotagController geotag;

  /// The download queue, one engine for the app's lifetime so only it uses
  /// `downloads.json` and the job files: a photo-library save still running
  /// when the camera pages close finishes in it, and the queue carries on
  /// when they open again.
  final DownloadEngine downloads;

  /// The current camera's photos, for the Library and the Cameras screen;
  /// its cached listing is read at start.
  final LibraryContext library;

  /// Lets screens know when another route covers them (the Cameras screen
  /// stops scanning then).
  final routes = RouteObserver<ModalRoute<void>>();

  /// Removes [serial]'s camera from the app with everything kept about it:
  /// its pairing, cached listing, images and movies, downloads waiting and
  /// the record of its files saved to the phone. The photos themselves
  /// stay in the photo library. Forgetting the current camera also ends
  /// its connection.
  Future<void> forgetCamera(String serial) => Future.wait([
    cameras.remove(serial),
    library.forgetCamera(serial),
    downloads.forgetCamera(serial),
  ]);
}

class AppScope extends InheritedWidget {
  const new({required this.models, required super.child, super.key});

  final AppModels models;

  static AppModels of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.models;

  @override
  bool updateShouldNotify(AppScope oldWidget) => models != oldWidget.models;
}
