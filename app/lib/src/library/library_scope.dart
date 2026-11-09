import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/connection/idle_disconnect.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/camera_link.dart';
import 'package:grlab/src/library/library_model.dart';

/// The library's models, created by the Library screen for the app's
/// lifetime with a paired camera.
final class LibraryContext {
  new({
    required this.link,
    required this.model,
    required this.images,
    required this.movies,
    required this.engine,
    IdleDisconnect? idle,
  }) : _idle = idle {
    if (idle != null) engine.addListener(_holdWhileDownloading);
  }

  factory create(AppModels app) {
    final services = app.services;
    final link = ConnectionLink(app.connection);
    final queue = RequestQueue();
    return LibraryContext(
      idle: app.idle,
      link: link,
      model: LibraryModel(
        cacheDir: services.cacheDir,
        link: link,
        queue: queue,
      ),
      images: CameraImages(
        cacheDir: services.cacheDir,
        link: link,
        queue: queue,
      ),
      movies: MovieCache(cacheDir: services.cacheDir),
      engine: DownloadEngine(
        dataDir: services.dataDir,
        cacheDir: services.cacheDir,
        media: services.media,
        link: link,
      ),
    );
  }

  /// Owned: disposed with the context.
  final ValueNotifier<CameraLibrary?> link;
  final LibraryModel model;
  final CameraImages images;
  final MovieCache movies;
  final DownloadEngine engine;

  /// A running download keeps the camera's Wi-Fi from being left for
  /// lack of use.
  final IdleDisconnect? _idle;
  VoidCallback? _release;

  void _holdWhileDownloading() {
    final running = engine.current != null;
    if (running && _release == null) {
      _release = _idle!.hold();
    } else if (!running && _release != null) {
      _release!();
      _release = null;
    }
  }

  void dispose() {
    engine.removeListener(_holdWhileDownloading);
    _release?.call();
    _release = null;
    engine.dispose();
    model.dispose();
    link.dispose();
  }
}

class LibraryScope extends InheritedWidget {
  const new({required this.library, required super.child, super.key});

  final LibraryContext library;

  static LibraryContext of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LibraryScope>()!.library;

  @override
  bool updateShouldNotify(LibraryScope oldWidget) =>
      library != oldWidget.library;
}
