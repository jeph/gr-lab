import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grphoto/src/connection/idle_disconnect.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/downloads/download_engine.dart';
import 'package:grphoto/src/library/camera_link.dart';
import 'package:grphoto/src/library/library_model.dart';
import 'package:grphoto/src/library/shot.dart';
import 'package:grphoto/src/services.dart';

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

  /// What the Library's grid shows of [model]'s listing.
  late final LibraryGrid grid = LibraryGrid(model, engine);

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

  /// Deletes what the library keeps of [serial]'s camera, removed from the
  /// app: its cached listing, images and movies. Waits first for the
  /// listing to switch away from it, which writes its listing a last time.
  Future<void> forgetCamera(String serial) async {
    await model.switched;
    await Future.wait([
      images.forgetCamera(serial),
      movies.forgetCamera(serial),
    ]);
  }

  void dispose() {
    engine.removeListener(_holdWhileDownloading);
    _release?.call();
    _release = null;
    model.dispose();
  }
}

/// What the grid shows of the listing, worked out over the whole card: the
/// shots a filter leaves, and the lines they make. The Library rebuilds
/// whenever the library, the downloads or the connection report anything,
/// far more often than these change, so each is worked out again only
/// when what it is made from does. Kept with the library's models, so the
/// Library opens with them.
final class LibraryGrid {
  new(this._model, this._engine);

  final LibraryModel _model;
  final DownloadEngine _engine;
  final _filtered =
      _Kept<(List<Shot>, LibraryFilter, String?, int), FilteredShots>();
  final _lines = _Kept<(List<Shot>, int, int), GridLines>();

  /// The listing's shots that pass [filter], with each filter's count;
  /// null without a listing.
  FilteredShots? filtered(LibraryFilter filter) {
    final all = _model.shots;
    if (all == null) return null;
    final serial = _model.serial;
    return _filtered.of(
      (all, filter, serial, _engine.downloadedRevision),
      () => FilteredShots.of(
        all,
        filter,
        (s) => serial != null && _engine.isShotDownloaded(serial, s),
      ),
    );
  }

  /// [shots] (from [filtered]) by day, as the lines of a grid [columns]
  /// wide.
  GridLines lines(List<Shot> shots, int columns) =>
      _lines.of((shots, _model.datesRevision, columns), () {
        final lines = gridLines(
          daySections(shots, (s) => _model.info(s.primary)?.taken),
          columns,
        );
        return (
          lines: lines,
          indexOf: {for (final (i, line) in lines.indexed) line.id: i},
        );
      });
}

/// The grid's lines top to bottom, and where each is by its [GridLine.id].
typedef GridLines = ({List<GridLine> lines, Map<String, int> indexOf});

/// A value worked out from [K], and worked out again only when that
/// changes. A list in a record [K] counts as changed when it is another
/// list.
final class _Kept<K, V> {
  (K, V)? _last;

  V of(K from, V Function() make) {
    final last = _last;
    if (last != null && last.$1 == from) return last.$2;
    final value = make();
    _last = (from, value);
    return value;
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
  void gone(String serial, CameraFile f) {
    stale(serial, f);
    unawaited(downloads.fileGone(serial, f));
  }

  @override
  bool dropUnchecked(CameraLibrary current, CameraFile f) {
    final droppedImages = images.forgetUnlessFrom(current, f);
    return movies.forgetUnlessFrom(current, f) || droppedImages;
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
