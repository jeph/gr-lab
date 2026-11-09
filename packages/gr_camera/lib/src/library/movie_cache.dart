import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_camera/src/library/camera_library.dart';

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
  bool _cancelled = false;

  /// 0..1, or null while the camera has not said how large the file is.
  ValueListenable<double?> get progress => _progress;

  /// Stops the transfer; [done] fails with [MovieDownloadCancelled] and the
  /// partial file is removed.
  void cancel() => _cancelled = true;
}

/// Movies copied in full to `<cacheDir>/<serial>/movies/` before playing.
///
/// The camera serves plain GETs without byte ranges, which iOS's player
/// requires for network playback, and on Android the player's own HTTP
/// stack would not be bound to the camera's network. Playing a local file
/// avoids both; a copied movie plays again without the camera.
final class MovieCache {
  /// Movies cached under [cacheDir].
  new({required this.cacheDir});

  /// Root of the on-device cache; movies go to `<serial>/movies/` in it.
  final Directory cacheDir;

  /// Per destination, the latest attempt settling (success or failure).
  final Map<String, Future<void>> _latest = {};
  int _attempts = 0;

  /// Where [serial]'s copy of [f] is kept. Keeps the camera's extension so
  /// the players recognise the container.
  File fileFor(String serial, CameraFile f) =>
      File('${cacheDir.path}/$serial/movies/${f.fileStem}');

  /// The cached copy, if a complete one exists.
  File? cached(String serial, CameraFile f) {
    final file = fileFor(serial, f);
    return file.existsSync() ? file : null;
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
        download._progress.value = 1;
        return file;
      }
      await file.parent.create(recursive: true);
      try {
        await library.downloadFile(
          f,
          staging,
          onProgress: (received, total) {
            if (download._cancelled) throw const MovieDownloadCancelled();
            download._progress.value = total == null || total == 0
                ? null
                : received / total;
          },
        );
        if (download._cancelled) throw const MovieDownloadCancelled();
        await staging.rename(file.path);
      } catch (_) {
        if (staging.existsSync()) await staging.delete();
        rethrow;
      }
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
}
