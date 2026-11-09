import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/connection/idle_disconnect.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/camera_link.dart';
import 'package:grlab/src/library/library_model.dart';
import 'package:grlab/src/services.dart';

/// The library's models for the current camera, created with the app's
/// models (`AppModels.library`) for the app's lifetime: the Library and
/// the Cameras screen's card show the same listing and images.
final class LibraryContext {
  new _({
    required this.link,
    required this.model,
    required this.images,
    required this.movies,
    required this.engine,
    required this._idle,
  }) {
    engine.addListener(_holdWhileDownloading);
    // The app's engine may already be running a resumed job.
    _holdWhileDownloading();
  }

  factory create({
    required AppServices services,
    required CameraStore cameras,
    required ConnectionLink link,
    required DownloadEngine downloads,
    required IdleDisconnect idle,
  }) {
    final queue = RequestQueue();
    final images = CameraImages(
      cacheDir: services.cacheDir,
      link: link,
      queue: queue,
    );
    final movies = MovieCache(cacheDir: services.cacheDir);
    return LibraryContext._(
      idle: idle,
      link: link,
      model: LibraryModel(
        cacheDir: services.cacheDir,
        cameras: cameras,
        link: link,
        queue: queue,
        copies: LibraryCopies(
          images: images,
          movies: movies,
          downloads: downloads,
        ),
      ),
      images: images,
      movies: movies,
      engine: downloads,
    );
  }

  /// The camera's library while connected; the app's one link, which the
  /// download engine uses too.
  final ConnectionLink link;
  final LibraryModel model;
  final CameraImages images;
  final MovieCache movies;

  /// The app's download queue (`AppModels.downloads`).
  final DownloadEngine engine;

  /// A running download keeps the camera's Wi-Fi from being left for
  /// lack of use.
  final IdleDisconnect _idle;
  VoidCallback? _release;

  void _holdWhileDownloading() {
    final running = engine.current != null;
    if (running && _release == null) {
      _release = _idle.hold();
    } else if (!running && _release != null) {
      _release!();
      _release = null;
    }
  }

  void dispose() {
    engine.removeListener(_holdWhileDownloading);
    _release?.call();
    _release = null;
    model.dispose();
  }
}

/// The library's copies of camera files: what [LibraryModel] finds out
/// about a path reaches its images, movie and download record.
final class LibraryCopies implements FileCopies {
  new({required this.images, required this.movies, required this.downloads});

  final CameraImages images;
  final MovieCache movies;
  final DownloadEngine downloads;

  @override
  bool isRecorded(String serial, CameraFile f) =>
      downloads.isFileDownloaded(serial, f);

  @override
  void stale(String serial, CameraFile f) {
    images.forget(serial, f);
    movies.forget(serial, f);
    unawaited(downloads.fileStale(serial, f));
  }

  @override
  void checked(
    String serial,
    CameraFile f,
    FileInfo now, {
    required bool vouched,
  }) => unawaited(downloads.checkFile(serial, f, now, vouched: vouched));
}

/// Hands the [LibraryContext] to the Library's widgets and the routes it
/// opens.
class LibraryScope extends InheritedWidget {
  const new({required this.library, required super.child, super.key});

  final LibraryContext library;

  static LibraryContext of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LibraryScope>()!.library;

  @override
  bool updateShouldNotify(LibraryScope oldWidget) =>
      library != oldWidget.library;
}
