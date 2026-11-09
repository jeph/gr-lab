import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_camera/src/library/camera_library.dart';
import 'package:gr_camera/src/library/disk_budget.dart';

/// Thrown by [MovieDownload.done] after [MovieDownload.cancel].
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
      keep: _handedOut.contains,
      isStaging: (path) =>
          path.endsWith('.download') || path.endsWith('.download.part'),
    );
  }

  /// Root of the on-device cache; movies go to `<serial>/movies/` in it.
  final Directory cacheDir;

  /// \[design\] Budget for the copies, in bytes, across cameras. Past it
  /// the least recently played are deleted, at start and after each new
  /// copy, except a copy in progress and the two copies handed out last
  /// (one playing, one on a page next to it); a deleted movie is copied
  /// again when played.
  final int maxBytes;

  /// How many of the copies handed out last are never deleted.
  static const _keptPlayed = 2;

  /// Per destination, the latest attempt settling (success or failure).
  final Map<String, Future<void>> _latest = {};
  int _attempts = 0;
  late final DiskBudget _disk;

  /// Paths of the copies handed out last, oldest first.
  final _handedOut = <String>{};

  /// Where [serial]'s copy of [f] is kept. Keeps the camera's extension so
  /// the players recognise the container.
  File fileFor(String serial, CameraFile f) =>
      File('${cacheDir.path}/$serial/movies/${f.fileStem}');

  /// The cached copy, if a complete one exists. A copy returned here is
  /// kept while it is one of the last handed out.
  File? cached(String serial, CameraFile f) {
    final file = fileFor(serial, f);
    if (!file.existsSync()) return null;
    _handOut(file);
    return file;
  }

  void _handOut(File file) {
    // Called on every rebuild of a page; only a change of order is news.
    if (_handedOut.isNotEmpty && _handedOut.last == file.path) return;
    _handedOut
      ..remove(file.path)
      ..add(file.path);
    while (_handedOut.length > _keptPlayed) {
      _handedOut.remove(_handedOut.first);
    }
    _disk.used(file);
  }

  /// Copies [f] from [library]'s camera. The file appears under its final
  /// name only when complete, so an interrupted copy is never played.
  ///
  /// Each attempt writes its own staging file and starts only after the
  /// previous attempt for the same movie has settled, so a cancelled copy
  /// that is still unwinding cannot delete or overwrite a retry's data.
  MovieDownload download(CameraLibrary library, CameraFile f) {
    final download = MovieDownload._();
    final file = fileFor(library.serial, f);
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
      try {
        await library.downloadFile(
          f,
          staging,
          onProgress: (received, total) => download._progress.value =
              total == null || total == 0 ? null : received / total,
          abort: download._cancel.future,
        );
        if (download._cancelled) throw const MovieDownloadCancelled();
        await staging.rename(file.path);
      } catch (_) {
        if (staging.existsSync()) await staging.delete();
        rethrow;
      }
      _handOut(file);
      _disk.added(file, await file.length());
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

  /// Completes when the disk budget has caught up with every copy made or
  /// handed out so far.
  @visibleForTesting
  Future<void> get diskSettled => _disk.settled;
}
