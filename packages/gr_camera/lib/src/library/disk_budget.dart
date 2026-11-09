import 'dart:async';
import 'dart:io';

/// Keeps the files of one on-disk cache within [maxBytes]: past it the
/// least recently used files are deleted, once the existing files have been
/// indexed at start and after each new file, except those [keep] protects
/// and those [hold] holds. When a file was last used is kept in its
/// modification time, so the order survives a restart.
///
/// The files are those in `<cacheDir>/<camera>/<folder>/` for each of
/// [folders]. Staging files ([isStaging]) count only once nothing has
/// written to them for [staleStaging]; younger ones belong to a copy in
/// progress. Changes run one at a time, in the order they were asked for.
final class DiskBudget {
  /// Indexes the cache's files and trims them to [maxBytes].
  new({
    required this.cacheDir,
    required this.folders,
    required this.maxBytes,
    required this.isStaging,
    this.keep = _keepNone,
    this.staleStaging = const Duration(minutes: 10),
  }) {
    _run(_scan);
  }

  /// Holds by path, across every budget of this process (two caches can
  /// share a folder for a moment, as when the camera pages open again).
  static final _held = <String, int>{};

  static bool _keepNone(String path) => false;

  /// Root of the cache; each camera has a folder in it.
  final Directory cacheDir;

  /// Folders of each camera's folder that hold this cache's files.
  final List<String> folders;

  /// Bytes the cache may hold, not counting files [keep] protects or
  /// [hold] holds.
  final int maxBytes;

  /// The file at this path is in use and must stay.
  final bool Function(String path) keep;

  /// The file at this path is an unfinished copy.
  final bool Function(String path) isStaging;

  /// \[design\] A copy in progress writes continuously and ends at its
  /// idle timeout, so a staging file older than this is a leftover (of an
  /// app that was stopped mid-copy).
  final Duration staleStaging;

  // Size by path, least recently used first.
  final _files = <String, int>{};
  int _bytes = 0;
  Future<void> _work = Future.value();

  /// Bytes of the indexed files.
  int get bytes => _bytes;

  /// Completes when every change asked for so far is done.
  Future<void> get settled => _work;

  /// [file], [length] bytes long, was just written; trims the cache.
  void added(File file, int length) => _run(() async {
    _put(file.path, length);
    await _trim();
  });

  /// [file] was just read, so it is now the most recently used.
  void used(File file) => _run(() async {
    final length = _files.remove(file.path);
    if (length == null) return;
    _files[file.path] = length;
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // The order still holds until the app stops.
    }
  });

  /// [file] was deleted.
  void removed(File file) => _run(() async {
    final length = _files.remove(file.path);
    if (length != null) _bytes -= length;
  });

  /// Keeps [file] from being deleted until the hold is released, also when
  /// it is written only later: something reads it from disk, as a player
  /// does. Releasing trims the cache again.
  CacheHold hold(File file) {
    final path = file.path;
    _held[path] = (_held[path] ?? 0) + 1;
    return CacheHold._(() {
      final left = _held[path]! - 1;
      if (left == 0) {
        _held.remove(path);
      } else {
        _held[path] = left;
      }
      _run(_trim);
    });
  }

  void _run(Future<void> Function() change) {
    _work = _work.then((_) => change());
  }

  void _put(String path, int length) {
    _bytes += length - (_files.remove(path) ?? 0);
    _files[path] = length;
  }

  Future<void> _scan() async {
    final found = <({String path, int length, DateTime used})>[];
    final staleBefore = DateTime.now().subtract(staleStaging);
    try {
      await for (final camera in cacheDir.list()) {
        if (camera is! Directory) continue;
        for (final folder in folders) {
          final dir = Directory('${camera.path}/$folder');
          if (!dir.existsSync()) continue;
          await for (final entry in dir.list()) {
            final stat = entry.statSync();
            if (stat.type != FileSystemEntityType.file) continue;
            if (isStaging(entry.path) && stat.modified.isAfter(staleBefore)) {
              continue;
            }
            found.add((
              path: entry.path,
              length: stat.size,
              used: stat.modified,
            ));
          }
        }
      }
    } on FileSystemException {
      // No cache yet, or a folder removed while listing: what was found
      // is indexed, the rest when it is written again.
    }
    found.sort((a, b) => a.used.compareTo(b.used));
    for (final f in found) {
      _put(f.path, f.length);
    }
    await _trim();
  }

  Future<void> _trim() async {
    for (final path in _files.keys.toList()) {
      if (_bytes <= maxBytes) return;
      if (keep(path) || _held.containsKey(path)) continue;
      _bytes -= _files.remove(path)!;
      try {
        await File(path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }
}

/// Keeps one cached file on disk until [release]; see [DiskBudget.hold].
final class CacheHold {
  new _(this._release);

  final void Function() _release;
  bool _released = false;

  /// Lets the cache delete the file again. Later calls do nothing.
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}
