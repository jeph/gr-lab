import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import 'camera_link.dart';
import 'request_queue.dart';
import 'shot.dart';

/// A pending image load; [cancel] drops it while it waits for the camera.
final class ImageRequest {
  ImageRequest._(this.future, this._cancel);

  final Future<Uint8List?> future;
  final void Function() _cancel;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

final class _InFlight {
  _InFlight(this.request);
  final QueuedRequest<Uint8List?> request;
  int waiters = 0;
}

/// Thumbnails (`size=thumb`) and previews (`size=view`) of camera files,
/// cached on disk under `<cacheDir>/<serial>/thumbs|views` so the grid shows
/// them offline, plus a small in-memory cache for scrolling.
final class CameraImages {
  CameraImages({
    required this.cacheDir,
    required this.link,
    required this.queue,
    this.memoryThumbs = 600,
    this.memoryViews = 6,
  });

  final Directory cacheDir;
  final ValueListenable<CameraLink?> link;
  final RequestQueue queue;
  final int memoryThumbs;
  final int memoryViews;

  // Insertion-ordered maps double as LRU caches: a hit is moved to the end.
  final _thumbs = <String, Uint8List>{};
  final _views = <String, Uint8List>{};
  final _inFlight = <String, _InFlight>{};

  static String _dirName(GrImageSize size) => switch (size) {
    GrImageSize.thumb => 'thumbs',
    GrImageSize.view => 'views',
    GrImageSize.full => 'full',
    GrImageSize.xs => 'xs',
  };

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
      '$serial|${size.name}|${f.key}';

  Map<String, Uint8List> _memory(GrImageSize size) =>
      size == GrImageSize.thumb ? _thumbs : _views;

  /// The image if it is in memory.
  Uint8List? cached(String serial, CameraFile f, GrImageSize size) {
    final memory = _memory(size);
    final key = _key(serial, f, size);
    final bytes = memory.remove(key);
    if (bytes != null) memory[key] = bytes;
    return bytes;
  }

  /// Loads the image from memory, disk or, when [serial]'s camera is
  /// connected, the camera. Completes with null when the camera is not
  /// connected or the request failed.
  ImageRequest load(String serial, CameraFile f, GrImageSize size) {
    final hit = cached(serial, f, size);
    if (hit != null) return ImageRequest._(Future.value(hit), () {});
    final key = _key(serial, f, size);
    var cancelled = false;
    _InFlight? waitingOn;
    Future<Uint8List?> run() async {
      final file = _file(serial, f, size);
      try {
        if (file.existsSync()) {
          return _remember(size, key, await file.readAsBytes());
        }
      } on FileSystemException {
        // Fall through to the camera.
      }
      if (cancelled) return null;
      final current = link.value;
      if (current == null || current.serial != serial) return null;
      final flight = _inFlight[key] ??= _InFlight(
        queue.add(() => _fetch(current.http, f, size, file, key)),
      );
      flight.waiters++;
      waitingOn = flight;
      try {
        return await flight.request.future;
      } on RequestCancelled {
        return null;
      } on Object {
        return null;
      } finally {
        if (identical(_inFlight[key], flight) && --flight.waiters == 0) {
          _inFlight.remove(key);
        }
      }
    }

    return ImageRequest._(run(), () {
      cancelled = true;
      final flight = waitingOn;
      if (flight != null && flight.waiters <= 1) flight.request.cancel();
    });
  }

  Future<Uint8List?> _fetch(
    GrHttpClient http,
    CameraFile f,
    GrImageSize size,
    File file,
    String key,
  ) async {
    await file.parent.create(recursive: true);
    await http.downloadToFile(f.path, file, size: size, storage: f.storage);
    return _remember(size, key, await file.readAsBytes());
  }

  Uint8List _remember(GrImageSize size, String key, Uint8List bytes) {
    final memory = _memory(size);
    final limit = size == GrImageSize.thumb ? memoryThumbs : memoryViews;
    memory
      ..remove(key)
      ..[key] = bytes;
    while (memory.length > limit) {
      memory.remove(memory.keys.first);
    }
    return bytes;
  }

  /// Forgets every image in memory (the disk cache stays).
  void clearMemory() {
    _thumbs.clear();
    _views.clear();
  }
}
