import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_camera/src/library/camera_library.dart';
import 'package:gr_camera/src/library/disk_budget.dart';

/// Thrown by [MovieDownload.done] after [MovieDownload.cancel], and when
/// the movie or its camera was forgotten while it was copied
/// ([MovieCache.forget], [MovieCache.forgetCamera]): the copy is not kept,
/// and the next attempt copies whatever the camera has at the path then.
final class MovieDownloadCancelled implements Exception {
  /// The only instance; carries no detail.
  const new();

  @override
  String toString() => 'MovieDownloadCancelled';
}

/// A movie being copied from the camera into the cache.
final class MovieDownload {
  new _();

  final ValueNotifier<double?> _progress = ValueNotifier(0);

  /// The cached file once the copy is complete; fails with the transfer's
  /// error or [MovieDownloadCancelled].
  late final Future<File> done;
  final Completer<Object> _cancel = Completer<Object>();

  bool get _cancelled => _cancel.isCompleted;

  /// 0..1, or null while the camera has not said how large the file is.
  ValueListenable<double?> get progress => _progress;

  /// Stops the transfer, closing its camera request at once; [done] fails
  /// with [MovieDownloadCancelled] and the partial file is removed.
  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete(const MovieDownloadCancelled());
  }
}

/// Movies copied in full to `<cacheDir>/<serial>/movies/` before playing.
///
/// The camera serves plain GETs without byte ranges, which iOS's player
/// requires for network playback, and on Android the player's own HTTP
/// stack would not be bound to the camera's network. Playing a local file
/// avoids both; a copied movie plays again without the camera. The copies
/// are kept within [maxBytes].
final class MovieCache {
  /// Movies cached under [cacheDir].
  new({required this.cacheDir, this.maxBytes = 1 << 30}) {
    _disk = DiskBudget(
      cacheDir: cacheDir,
      folders: const ['movies'],
      maxBytes: maxBytes,
      // A copy in progress is a staging file, which the budget leaves alone.
      isStaging: (path) =>
          path.endsWith('.download') || path.endsWith('.download.part'),
    );
  }

  /// Root of the on-device cache; movies go to `<serial>/movies/` in it.
  final Directory cacheDir;

  /// \[design\] Budget for the copies, in bytes, across cameras. Past it
  /// the least recently played are deleted, at start, after each new copy
  /// and when a hold ends, except a copy in progress and copies [hold]
  /// holds (a movie on screen); a deleted movie is copied again when
  /// played.
  final int maxBytes;

  /// Per destination, the latest attempt settling (success or failure).
  final Map<String, Future<void>> _latest = {};
  int _attempts = 0;
  late final DiskBudget _disk;

  /// Per path, the link the copy there was made from.
  final _copiedFrom = <String, CameraLibrary>{};

  /// Per serial, how often [forgetCamera] dropped the camera, so a copy
  /// begun before is not kept.
  final _forgottenCameras = <String, int>{};

  /// Per path, how often [forget] dropped the copy there, so a copy begun
  /// before is not kept.
  final _forgotten = <String, int>{};

  /// The copy [cached] or [download] handed out last.
  String? _lastUsed;

  /// Where [serial]'s copy of [f] is kept. Keeps the camera's extension so
  /// the players recognise the container.
  File fileFor(String serial, CameraFile f) =>
      File('${cacheDir.path}/$serial/movies/${f.fileStem}');

  /// The cached copy, if a complete one exists. Only a [hold] keeps it on
  /// disk while it plays.
  File? cached(String serial, CameraFile f) {
    final file = fileFor(serial, f);
    if (!file.existsSync()) return null;
    _handOut(file);
    return file;
  }

  /// Keeps [serial]'s copy of [f] on disk, also one copied later, until
  /// the hold is released: a player reads the file while it plays, without
  /// asking the cache again. [forget] still deletes it.
  CacheHold hold(String serial, CameraFile f) => _disk.hold(fileFor(serial, f));

  void _handOut(File file) {
    // Called on every rebuild of a page; only a change of order is news.
    if (_lastUsed == file.path) return;
    _lastUsed = file.path;
    _disk.used(file);
  }

  /// Copies [f] from [library]'s camera. The file appears under its final
  /// name only when complete, so an interrupted copy is never played.
  ///
  /// Each attempt writes its own staging file and starts only after the
  /// previous attempt for the same movie has settled, so a cancelled copy
  /// that is still unwinding cannot delete or overwrite a retry's data.
  ///
  /// A copy [forget] dropped the movie during ends with
  /// [MovieDownloadCancelled] and leaves nothing on disk: the movie left
  /// the camera, or its path now holds another one, but the camera may
  /// still finish sending the file it had (\[inferred\], as webapid's
  /// `GetAndSendSmallImage` does for images).
  MovieDownload download(CameraLibrary library, CameraFile f) {
    final download = MovieDownload._();
    final serial = library.serial;
    final file = fileFor(serial, f);
    final cameraForgotten = _forgottenCameras[serial];
    bool cameraDropped() => _forgottenCameras[serial] != cameraForgotten;
    final key = file.path;
    final previous = _latest[key];
    final staging = File('${file.path}.${_attempts++}.download');
    download.done = () async {
      if (previous != null) await previous;
      if (download._cancelled) throw const MovieDownloadCancelled();
      if (file.existsSync()) {
        _handOut(file);
        download._progress.value = 1;
        return file;
      }
      await file.parent.create(recursive: true);
      // Read as the request goes out: a request sent after [forget] gets
      // the movie now at the path.
      final forgotten = _forgotten[key];
      bool fileDropped() => _forgotten[key] != forgotten;
      final int length;
      try {
        await library.downloadFile(
          f,
          staging,
          onProgress: (received, total) => download._progress.value =
              total == null || total == 0 ? null : received / total,
          abort: download._cancel.future,
        );
        if (download._cancelled || cameraDropped() || fileDropped()) {
          throw const MovieDownloadCancelled();
        }
        await staging.rename(file.path);
        // Read before the last check, so nothing awaited lies between it
        // and recording the copy.
        length = await file.length();
        if (cameraDropped() || fileDropped()) {
          throw const MovieDownloadCancelled();
        }
        _copiedFrom[file.path] = library;
      } catch (_) {
        if (staging.existsSync()) await staging.delete();
        if (cameraDropped()) {
          // The camera was forgotten meanwhile, its folder deleted. A later
          // copy of this movie waits for this one, so the file is this
          // copy.
          await _disk.discard(file);
          throw const MovieDownloadCancelled();
        }
        if (!fileDropped()) rethrow;
        // If it got as far as the rename, that came after [forget] deleted
        // the path: the file is this copy, not counted by the disk budget.
        await _delete(file);
        library.event('movies.forgottenMeanwhile', {'file': '$f'});
        throw const MovieDownloadCancelled();
      }
      _lastUsed = file.path;
      _disk.added(file, length);
      download._progress.value = 1;
      return file;
    }();
    download.done.ignore();
    final settled = download.done.then<void>((_) {}, onError: (Object _) {});
    _latest[key] = settled;
    unawaited(
      settled.whenComplete(() {
        if (identical(_latest[key], settled)) unawaited(_latest.remove(key));
      }),
    );
    return download;
  }

  /// Deletes [serial]'s copy of [f], at once so [cached] no longer finds
  /// it: the file is gone from the camera, or its path now holds another
  /// movie. A copy in progress is not kept either: it may be of the file
  /// that was there, and ends with [MovieDownloadCancelled].
  void forget(String serial, CameraFile f) {
    final file = fileFor(serial, f);
    _forgotten[file.path] = (_forgotten[file.path] ?? 0) + 1;
    _copiedFrom.remove(file.path);
    try {
      if (!file.existsSync()) return;
      file.deleteSync();
      _disk.removed(file);
    } on FileSystemException {
      // Already gone.
    }
  }

  /// Deletes [file], which may be gone already, and tells the disk budget.
  Future<void> _delete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Indexed at the next start and trimmed with the rest.
    }
    _disk.removed(file);
  }

  /// Deletes the copy of [f] unless it was made from [current], the link
  /// whose camera just gave the first info of [f]: a copy made on an
  /// earlier link may be of another movie that was at its path then. True
  /// when one was deleted.
  bool forgetUnlessFrom(CameraLibrary current, CameraFile f) {
    final file = fileFor(current.serial, f);
    if (identical(_copiedFrom[file.path], current)) return false;
    if (!file.existsSync()) return false;
    forget(current.serial, f);
    return true;
  }

  /// Deletes every copy of [serial]'s camera, with the rest of its folder
  /// in [cacheDir]: the camera was removed from the app. A copy still in
  /// progress for it is not kept: it ends with [MovieDownloadCancelled].
  /// Completes once the folder is gone.
  Future<void> forgetCamera(String serial) {
    _forgottenCameras[serial] = (_forgottenCameras[serial] ?? 0) + 1;
    final prefix = '${cacheDir.path}/$serial/';
    _copiedFrom.removeWhere((path, _) => path.startsWith(prefix));
    _forgotten.removeWhere((path, _) => path.startsWith(prefix));
    if (_lastUsed?.startsWith(prefix) ?? false) _lastUsed = null;
    return _disk.forgetCamera(serial);
  }

  /// Completes when the disk budget has caught up with every copy made or
  /// handed out so far.
  @visibleForTesting
  Future<void> get diskSettled => _disk.settled;
}
