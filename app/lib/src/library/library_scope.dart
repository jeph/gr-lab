import 'package:flutter/widgets.dart';

import '../app_scope.dart';
import '../downloads/download_engine.dart';
import 'camera_images.dart';
import 'camera_link.dart';
import 'library_model.dart';
import 'movie_cache.dart';
import 'request_queue.dart';

/// The library's models, created by the Library screen for the app's
/// lifetime with a paired camera.
final class LibraryContext {
  LibraryContext({
    required this.link,
    required this.model,
    required this.images,
    required this.movies,
    required this.engine,
  });

  factory LibraryContext.create(AppModels app) {
    final services = app.services;
    final link = ConnectionLink(app.connection);
    final queue = RequestQueue();
    return LibraryContext(
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
  final ValueNotifier<CameraLink?> link;
  final LibraryModel model;
  final CameraImages images;
  final MovieCache movies;
  final DownloadEngine engine;

  void dispose() {
    engine.dispose();
    model.dispose();
    link.dispose();
  }
}

class LibraryScope extends InheritedWidget {
  const LibraryScope({super.key, required this.library, required super.child});

  final LibraryContext library;

  static LibraryContext of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LibraryScope>()!.library;

  @override
  bool updateShouldNotify(LibraryScope oldWidget) =>
      library != oldWidget.library;
}
