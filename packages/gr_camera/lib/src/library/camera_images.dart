import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_camera/src/library/camera_library.dart';
import 'package:gr_camera/src/library/disk_budget.dart';
import 'package:gr_camera/src/library/request_queue.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// A pending image load; [cancel] drops it while it waits for the camera.
///
/// [future] completes with the image, with null when the camera is not
/// connected or the load was cancelled, and with an error when the camera
/// failed to send it (an error answer, a timeout, or bytes that are not a
/// JPEG).
final class ImageRequest {
  new _();

  new _done(Uint8List bytes) {
    _result.complete(bytes);
  }

  final Completer<Uint8List?> _result = Completer<Uint8List?>();
  RequestTicket<Uint8List>? _ticket;
  bool _cancelled = false;

  /// The image, or null when not connected or cancelled; see the class doc.
  Future<Uint8List?> get future => _result.future;

  /// Drops the load if it is still waiting; [future] then completes with
  /// null. Does nothing a second time.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _ticket?.cancel();
    if (!_result.isCompleted) _result.complete(null);
  }
}

/// The camera sent something other than a JPEG.
final class NotAnImageException implements Exception {
  /// [length] is the size of the body the camera sent.
  const new(this.length);

  /// Bytes the camera sent instead of a JPEG.
  final int length;

  @override
  String toString() =>
      'NotAnImageException: $length bytes without a JPEG start';
}

/// Images of camera files: thumbnails (`size=thumb`) and previews
/// (`size=view`), cached on disk under `<cacheDir>/<serial>/thumbs|views` so
/// the grid shows them offline, plus full-size JPEGs for zooming, which
/// stay in memory only. Each camera request has a deadline ([timeouts]).
/// The disk copies are kept within [diskBytes].
final class CameraImages {
  /// Images of [link]'s camera, fetched through [queue], cached under
  /// [cacheDir].
  new({
    required this.cacheDir,
    required this.link,
    required this.queue,
    this.memoryThumbs = 600,
    this.memoryViewBytes = 48 << 20,
    this.memoryFull = 2,
    this.diskBytes = 256 << 20,
    this.timeouts = const {
      GrImageSize.thumb: Duration(seconds: 10),
      GrImageSize.xs: Duration(seconds: 20),
      GrImageSize.view: Duration(seconds: 20),
      GrImageSize.full: Duration(minutes: 2),
    },
  }) : _requests = SharedRequests(queue) {
    _disk = DiskBudget(
      cacheDir: cacheDir,
      folders: [
        for (final size in GrImageSize.values)
          if (_onDisk(size)) _dirName(size),
      ],
      maxBytes: diskBytes,
      // Images in memory are on screen or were just shown.
      keep: (path) => _thumbs.containsKey(path) || _views.containsKey(path),
      isStaging: (path) => path.endsWith('.tmp'),
    );
  }

  /// Root of the on-disk thumbnail and preview cache.
  final Directory cacheDir;

  /// The connected camera's library, null while none is connected.
  final ValueListenable<CameraLibrary?> link;

  /// Shared queue for camera requests.
  final RequestQueue queue;

  /// Thumbnails kept in memory (count).
  final int memoryThumbs;

  /// Budget for previews kept in memory, in bytes: the grid shows them
  /// for every cell larger than a thumbnail.
  final int memoryViewBytes;

  /// Full-size images kept in memory (count).
  final int memoryFull;

  /// \[design\] Budget for the images on disk, in bytes, across cameras.
  /// Past it the least recently used are deleted, at start and after each
  /// new one, except images in memory; a deleted image is fetched again
  /// when shown. The default holds a few thousand previews.
  final int diskBytes;

  /// Deadline for one camera request of each image size.
  final Map<GrImageSize, Duration> timeouts;

  final SharedRequests<Uint8List> _requests;
  late final DiskBudget _disk;

  // Insertion-ordered maps double as LRU caches: a hit is moved to the end.
  // Keys are disk paths ([_key]), so the disk budget can see what is shown.
  final _thumbs = <String, Uint8List>{};
  final _views = <String, Uint8List>{};
  final _full = <String, Uint8List>{};
  int _viewBytes = 0;

  /// Per `<serial>|<file key>`, how often [forget] dropped the file's
  /// images, so a disk read begun before is not kept.
  final _forgotten = <String, int>{};

  /// Per serial, how often [forgetCamera] dropped the camera, so a load
  /// begun before keeps its image off disk.
  final _forgottenCameras = <String, int>{};

  /// Per disk path, the link its image was last fetched from, so one cached
  /// on an earlier link can be told apart ([forgetUnlessFrom]).
  final _fetchedFrom = <String, CameraLibrary>{};

  static String _dirName(GrImageSize size) => switch (size) {
    GrImageSize.thumb => 'thumbs',
    GrImageSize.view => 'views',
    GrImageSize.full => 'full',
    GrImageSize.xs => 'xs',
  };

  /// Full-size files can be tens of megabytes; they are not kept on disk.
  static bool _onDisk(GrImageSize size) => size != GrImageSize.full;

  /// Where [serial]'s [size] image of [f] is kept on disk.
  static File diskFile(
    Directory cacheDir,
    String serial,
    CameraFile f,
    GrImageSize size,
  ) => File('${cacheDir.path}/$serial/${_dirName(size)}/${f.fileStem}.jpg');

  File _file(String serial, CameraFile f, GrImageSize size) =>
      diskFile(cacheDir, serial, f, size);

  String _key(String serial, CameraFile f, GrImageSize size) =>
      _file(serial, f, size).path;

  Map<String, Uint8List> _memory(GrImageSize size) => switch (size) {
    GrImageSize.thumb => _thumbs,
    GrImageSize.full => _full,
    GrImageSize.view || GrImageSize.xs => _views,
  };

  /// The image if it is in memory.
  Uint8List? cached(String serial, CameraFile f, GrImageSize size) {
    final memory = _memory(size);
    final key = _key(serial, f, size);
    final bytes = memory.remove(key);
    if (bytes != null) memory[key] = bytes;
    return bytes;
  }

  /// The image is in memory or on disk, so [load] needs no camera.
  bool isLocal(String serial, CameraFile f, GrImageSize size) =>
      cached(serial, f, size) != null ||
      (_onDisk(size) && _file(serial, f, size).existsSync());

  /// Loads the image from memory, disk or, when [serial]'s camera is
  /// connected, the camera. A [background] request waits behind every other
  /// camera request.
  ImageRequest load(
    String serial,
    CameraFile f,
    GrImageSize size, {
    bool background = false,
  }) {
    final hit = cached(serial, f, size);
    if (hit != null) return ImageRequest._done(hit);
    final key = _key(serial, f, size);
    final request = ImageRequest._();
    final id = '$serial|${f.key}';
    final forgotten = _forgotten[id];
    final cameraForgotten = _forgottenCameras[serial];
    bool cameraDropped() => _forgottenCameras[serial] != cameraForgotten;
    Future<Uint8List?> run() async {
      final file = _file(serial, f, size);
      if (_onDisk(size)) {
        try {
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            // A copy [forget] or [forgetCamera] dropped while it was read is
            // never shown.
            final kept = _forgotten[id] == forgotten && !cameraDropped();
            if (kept && isJpeg(bytes)) {
              _disk.used(file);
              return _remember(size, key, bytes);
            }
            if (kept) {
              // A broken copy would be shown (as nothing) forever.
              await file.delete();
              _disk.removed(file);
            }
          }
        } on FileSystemException {
          // Fall through to the camera.
        }
      }
      if (request._cancelled) return null;
      final current = link.value;
      if (current == null || current.serial != serial) return null;
      final ticket = _requests.join(
        key,
        current,
        (signal) => _fetch(current, f, size, file, key, signal, cameraDropped),
        timeout: timeouts[size]!,
        background: background,
        abortWhenUnwanted: size == GrImageSize.full,
      );
      request._ticket = ticket;
      try {
        return await ticket.future;
      } on RequestCancelled {
        if (request._cancelled) return null;
        rethrow;
      }
    }

    unawaited(
      run().then(
        (bytes) {
          if (!request._result.isCompleted) request._result.complete(bytes);
        },
        onError: (Object e, StackTrace st) {
          if (!request._result.isCompleted) {
            request._result.completeError(e, st);
          }
        },
      ),
    );
    return request;
  }

  /// [cameraDropped] says [forgetCamera] dropped the camera while it was
  /// fetched; the image is then kept neither on disk nor in memory.
  Future<Uint8List> _fetch(
    CameraLibrary library,
    CameraFile f,
    GrImageSize size,
    File file,
    String key,
    RequestSignal signal,
    bool Function() cameraDropped,
  ) async {
    // Into memory rather than through `<file>.part`: a run that missed its
    // deadline may still be writing when the next attempt starts.
    final sink = _BytesSink();
    await library.http.download(
      f.path,
      sink,
      size: size,
      storage: f.storage,
      abort: signal.aborted,
    );
    final bytes = sink.takeBytes();
    if (!isJpeg(bytes)) {
      library.event('images.notJpeg', {
        'file': '$f',
        'size': size.name,
        'length': bytes.length,
      });
      throw NotAnImageException(bytes.length);
    }
    if (signal.abandoned) throw const RequestCancelled();
    if (cameraDropped()) return bytes;
    if (!_onDisk(size)) return _remember(size, key, bytes);
    final stored = await _store(file, bytes);
    if (cameraDropped()) {
      // Forgotten while it was written. One request at a time has this
      // path, so the file is this copy.
      await _disk.discard(file);
      return bytes;
    }
    _fetchedFrom[key] = library;
    // Remembered before the disk budget hears of it, so it counts as shown.
    _remember(size, key, bytes);
    if (stored) _disk.added(file, bytes.length);
    return bytes;
  }

  /// Writes [bytes] under a name of its own first, so a reader never sees a
  /// partial file. False when the phone could not write it.
  Future<bool> _store(File file, Uint8List bytes) async {
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await file.parent.create(recursive: true);
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      return true;
    } on FileSystemException {
      // The image still shows; it is fetched again next time.
      try {
        if (temp.existsSync()) await temp.delete();
      } on FileSystemException {
        // A leftover counts against the disk budget once it is stale.
      }
      return false;
    }
  }

  Uint8List _remember(GrImageSize size, String key, Uint8List bytes) {
    final memory = _memory(size);
    final old = memory.remove(key);
    memory[key] = bytes;
    switch (size) {
      case GrImageSize.thumb:
        while (memory.length > memoryThumbs) {
          memory.remove(memory.keys.first);
        }
      case GrImageSize.full:
        while (memory.length > memoryFull) {
          memory.remove(memory.keys.first);
        }
      case GrImageSize.view || GrImageSize.xs:
        _viewBytes += bytes.length - (old?.length ?? 0);
        while (_viewBytes > memoryViewBytes && memory.length > 1) {
          _viewBytes -= memory.remove(memory.keys.first)!.length;
        }
    }
    return bytes;
  }

  /// Forgets an image that turned out not to decode, in memory and on
  /// disk, so the next [load] asks the camera again.
  void evict(String serial, CameraFile f, GrImageSize size) {
    _fetchedFrom.remove(_key(serial, f, size));
    final removed = _memory(size).remove(_key(serial, f, size));
    if (removed != null &&
        (size == GrImageSize.view || size == GrImageSize.xs)) {
      _viewBytes -= removed.length;
    }
    if (!_onDisk(size)) return;
    try {
      final file = _file(serial, f, size);
      if (file.existsSync()) {
        file.deleteSync();
        _disk.removed(file);
      }
    } on FileSystemException {
      // Replaced on the next successful load.
    }
  }

  /// Forgets every image of [serial]'s [f], in memory and on disk, so the
  /// next [load] asks the camera: the file is gone from the camera, or its
  /// path now holds another shot. A disk read begun before is not shown.
  void forget(String serial, CameraFile f) {
    final id = '$serial|${f.key}';
    _forgotten[id] = (_forgotten[id] ?? 0) + 1;
    for (final size in GrImageSize.values) {
      evict(serial, f, size);
    }
  }

  /// Forgets each image of [f] not fetched from [current], the link whose
  /// camera just gave the first info of [f]: an image cached on an earlier
  /// link may be of another file that was at its path then. True when one
  /// was dropped.
  bool forgetUnlessFrom(CameraLibrary current, CameraFile f) {
    final serial = current.serial;
    var dropped = false;
    for (final size in GrImageSize.values) {
      final key = _key(serial, f, size);
      if (identical(_fetchedFrom[key], current)) continue;
      if (!isLocal(serial, f, size)) continue;
      if (!dropped) {
        final id = '$serial|${f.key}';
        _forgotten[id] = (_forgotten[id] ?? 0) + 1;
      }
      dropped = true;
      evict(serial, f, size);
    }
    return dropped;
  }

  /// Forgets every image in memory (the disk cache stays).
  void clearMemory() {
    _thumbs.clear();
    _views.clear();
    _full.clear();
    _viewBytes = 0;
  }

  /// Forgets every image of [serial]'s camera, in memory and on disk, with
  /// the rest of its folder in [cacheDir]: the camera was removed from the
  /// app. A load still running for it keeps its image off disk. Completes
  /// once the folder is gone.
  Future<void> forgetCamera(String serial) {
    _forgottenCameras[serial] = (_forgottenCameras[serial] ?? 0) + 1;
    _forgotten.removeWhere((id, _) => id.startsWith('$serial|'));
    final prefix = '${cacheDir.path}/$serial/';
    bool ofCamera(String key) => key.startsWith(prefix);
    _fetchedFrom.removeWhere((key, _) => ofCamera(key));
    _thumbs.removeWhere((key, _) => ofCamera(key));
    _full.removeWhere((key, _) => ofCamera(key));
    _views.removeWhere((key, bytes) {
      if (!ofCamera(key)) return false;
      _viewBytes -= bytes.length;
      return true;
    });
    return _disk.forgetCamera(serial);
  }

  /// Completes when the disk budget has caught up with every image written,
  /// read or deleted so far.
  @visibleForTesting
  Future<void> get diskSettled => _disk.settled;
}

/// Starts with the JPEG start-of-image marker.
bool isJpeg(Uint8List bytes) =>
    bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8;

final class _BytesSink implements StreamSink<List<int>> {
  final _builder = BytesBuilder(copy: false);
  final _done = Completer<void>();

  Uint8List takeBytes() => _builder.takeBytes();

  @override
  void add(List<int> data) => _builder.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
