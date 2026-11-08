part of 'fake_camera.dart';

/// The firmware pretty-prints its JSON with four spaces (GR IV captures).
const _json = JsonEncoder.withIndent('    ');

extension on FakeGrCamera {
  Future<int> _startHttp() async {
    final running = _server;
    if (running != null) return running.port;
    if (_closed) throw StateError('FakeGrCamera is closed');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) => unawaited(_handle(request)));
    return server.port;
  }

  String get _defaultStorage =>
      config.sdCard ? GrStorageId.sd : GrStorageId.internal;

  List<String> get _storages => [
    GrStorageId.internal,
    if (config.sdCard) GrStorageId.sd,
  ];

  Future<void> _handle(HttpRequest request) async {
    request.response.done.ignore();
    try {
      if (!_httpReachable) return await _hangUp(request);
      if (config.httpLatency > Duration.zero) {
        await Future<void>.delayed(config.httpLatency);
      }
      if (!_httpReachable) return await _hangUp(request);
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments.first != 'v1') {
        return await _error(request, 404, 'Not Found');
      }
      final route = segments.sublist(1);
      if (route case ['changes']
          when WebSocketTransformer.isUpgradeRequest(request)) {
        return await _upgrade(request);
      }
      if (request.method != 'GET') {
        return await _error(request, 405, 'Method Not Allowed');
      }
      switch (route) {
        case ['props']:
          return await _send(request, _props());
        case ['ping']:
          return await _send(request, {
            'errCode': 200,
            'errMsg': 'OK',
            'datetime': _stamp(DateTime.now()),
          });
        case ['photos']:
          return await _list(request);
        // GR III/IV webapid has no /latest route: errCode 400 under HTTP
        // 200 (hardware-validation.md §4).
        case ['photos', 'latest', 'info']:
          return await _error(request, 400, 'Bad Request', httpStatus: 200);
        case ['photos', final dir, final file, 'info']:
          return await _info(request, dir, file);
        case ['photos', final dir, final file]:
          return await _download(request, dir, file);
      }
      return await _error(request, 404, 'Not Found');
    } on Object {
      // The client went away mid-response; nothing is left to answer.
      try {
        await request.response.close();
      } on Object {
        // Already closed or detached.
      }
    }
  }

  /// No route to the camera: the connection dies without a response.
  Future<void> _hangUp(HttpRequest request) async {
    final socket = await request.response.detachSocket(writeHeaders: false);
    socket.destroy();
  }

  Future<void> _send(
    HttpRequest request,
    Map<String, Object?> body, {
    int status = 200,
  }) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(_json.convert(body));
    await request.response.close();
  }

  Future<void> _error(
    HttpRequest request,
    int errCode,
    String errMsg, {
    int? httpStatus,
  }) => _send(request, {
    'errCode': errCode,
    'errMsg': errMsg,
  }, status: httpStatus ?? errCode);

  Map<String, Object?> _props() => {
    'errCode': 200,
    'errMsg': 'OK',
    'manufacturer': FakeGrCamera._manufacturer,
    'model': config.model,
    'serialNo': config.serial,
    'firmwareVersion': config.firmware,
    'macAddress': FakeGrCamera._wifiMac,
    'hot': false,
    'battery': _battery,
    'operationModeList': ['capture'],
    'stillFormatList': ['jpeg', 'dng', 'rawdng'],
    'storages': [
      for (final name in _storages)
        {
          'name': name,
          'equipped': true,
          'available': true,
          'writable': true,
          'format': 'rawdng',
          'remain': name == GrStorageId.sd ? 10000 : 500,
          'recordableTime': name == GrStorageId.sd ? 72000 : 3600,
          'numOfPhotos': _photos
              .where((p) => p.storage == name && !p.isVideo)
              .length,
          'numOfMovies': _photos
              .where((p) => p.storage == name && p.isVideo)
              .length,
        },
    ],
    'datetime': _stamp(DateTime.now()),
    'operationMode': operationMode == BleOperationMode.playback
        ? 'playback'
        : 'capture',
    'stillFormat': 'rawdng',
    'bdName': config.bluetoothName,
    'channel': 0,
    'ssid': _ssid,
    'key': _passphrase,
    'captureModeList': ['still', 'movie'],
    'captureMode': 'still',
    'exposureMode': 'AV',
    'av': '2.8',
    'tv': '1.250',
    'sv': '200',
    'xv': '0.0',
    'capturing': false,
    'stateStill': 'idle',
    'stateMovie': 'idle',
  };

  /// Listing order: by directory, then shot, JPEG before its DNG, as a GR
  /// IV lists RAW+JPEG pairs.
  static int _compare(GrPhotoPath a, GrPhotoPath b) {
    int rank(GrPhotoPath p) => switch (p.extension) {
      'JPG' => 0,
      'DNG' => 1,
      _ => 2,
    };
    String base(GrPhotoPath p) {
      final dot = p.file.lastIndexOf('.');
      return dot < 0 ? p.file : p.file.substring(0, dot);
    }

    var c = a.dir.compareTo(b.dir);
    if (c != 0) return c;
    c = base(a).compareTo(base(b));
    if (c != 0) return c;
    c = rank(a) - rank(b);
    return c != 0 ? c : a.file.compareTo(b.file);
  }

  /// `GET /v1/photos[?storage=][&limit=][&after=dir/file]`; `after` is
  /// exclusive and need not exist.
  Future<void> _list(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final storage = query['storage'] ?? _defaultStorage;
    final limitText = query['limit'];
    final limit = limitText == null ? config.pageSize : int.tryParse(limitText);
    final afterText = query['after'];
    final after = afterText == null
        ? null
        : GrPhotoPath.tryParseCamera(afterText);
    if (!_storages.contains(storage) ||
        limit == null ||
        limit < 1 ||
        (afterText != null && after == null)) {
      return _error(request, 400, 'Bad Request');
    }
    final sorted = [
      for (final p in _photos)
        if (p.storage == storage) p.path,
    ]..sort(_compare);
    var start = after == null
        ? 0
        : sorted.indexWhere((p) => _compare(p, after) > 0);
    if (start < 0) start = sorted.length;
    final page = sorted.sublist(start, math.min(start + limit, sorted.length));
    final dirs = <Map<String, Object?>>[];
    for (final p in page) {
      if (dirs.isEmpty || dirs.last['name'] != p.dir) {
        dirs.add({'name': p.dir, 'files': <String>[]});
      }
      (dirs.last['files']! as List<String>).add(p.file);
    }
    return _send(request, {'errCode': 200, 'errMsg': 'OK', 'dirs': dirs});
  }

  FakePhoto? _requested(HttpRequest request, String dir, String file) => _find(
    request.uri.queryParameters['storage'] ?? _defaultStorage,
    dir,
    file,
  );

  Future<int> _fullSize(FakePhoto photo) async =>
      photo.size ??
      _fullSizes[photo] ??
      (_fullSizes[photo] = (await media(photo, GrImageSize.full)).length);

  Future<void> _info(HttpRequest request, String dir, String file) async {
    final photo = _requested(request, dir, file);
    if (photo == null) return _error(request, 404, 'Not Found');
    final int size;
    try {
      size = await _fullSize(photo);
    } on Object {
      return _error(request, 500, 'Internal Server Error');
    }
    // Stored (sensor) layout for every still, as the EXIF image size of a
    // portrait GR IV HDF file reads (6192×4128); what the camera's own
    // `resolution` says for a portrait frame is untested.
    final (resolution, aspect) = photo.isVideo
        ? ('1920x1080', '16:9')
        : ('6000x4000', '3:2');
    return _send(request, {
      'errCode': 200,
      'errMsg': 'OK',
      'cameraModel': config.model,
      'dir': photo.dir,
      'file': photo.file,
      'size': size,
      'datetime': _stamp(photo.dateTime),
      'orientation': ?photo.orientation,
      'aspectRatio': aspect,
      'resolution': resolution,
      if (photo.videoLength case final length?) 'duration': length.inSeconds,
      if (!photo.isVideo) ...{
        'av': photo.av,
        'tv': photo.tv,
        'sv': photo.sv,
        'xv': photo.xv,
      },
    });
  }

  /// Streams the file with a Content-Length on a connection that closes
  /// afterwards; stops (and closes the socket) when the client hangs up,
  /// the access point goes down or [FakeCameraConfig.cutDownloadsAfterBytes]
  /// is reached.
  Future<void> _download(HttpRequest request, String dir, String file) async {
    final sizeText = request.uri.queryParameters['size'];
    final size = sizeText == null
        ? GrImageSize.full
        : GrImageSize.values.asNameMap()[sizeText];
    if (size == null) return _error(request, 400, 'Bad Request');
    final photo = _requested(request, dir, file);
    if (photo == null) return _error(request, 404, 'Not Found');
    final Uint8List bytes;
    try {
      bytes = await media(photo, size);
    } on Object {
      return _error(request, 500, 'Internal Server Error');
    }
    if (!_httpReachable) return _hangUp(request);

    request.response
      ..statusCode = 200
      ..persistentConnection = false
      ..contentLength = bytes.length
      ..headers.contentType = size != GrImageSize.full
          ? ContentType('image', 'jpeg')
          : switch (photo.extension) {
              'DNG' => ContentType('image', 'x-adobe-dng'),
              'MOV' => ContentType('video', 'quicktime'),
              _ => ContentType('image', 'jpeg'),
            };
    final socket = await request.response.detachSocket();
    socket.done.ignore();
    final cut = size == GrImageSize.full ? config.cutDownloadsAfterBytes : null;
    final end = cut != null && cut < bytes.length ? cut : bytes.length;
    final rate = config.downloadBytesPerSecond;
    final chunk = rate == null
        ? 64 * 1024
        : (rate ~/ 20).clamp(1024, 64 * 1024);
    try {
      for (var offset = 0; offset < end; offset += chunk) {
        if (!_httpReachable) {
          socket.destroy();
          return;
        }
        final n = math.min(chunk, end - offset);
        socket.add(Uint8List.sublistView(bytes, offset, offset + n));
        await socket.flush();
        if (rate != null && rate > 0) {
          await Future<void>.delayed(
            Duration(microseconds: n * Duration.microsecondsPerSecond ~/ rate),
          );
        }
      }
      if (end < bytes.length) {
        socket.destroy();
      } else {
        await socket.close();
      }
    } on Object {
      socket.destroy();
    }
  }

  Future<void> _upgrade(HttpRequest request) async {
    final ws = await WebSocketTransformer.upgrade(request);
    if (!_httpReachable) {
      unawaited(ws.close(WebSocketStatus.goingAway));
      return;
    }
    _sockets.add(ws);
    ws.listen(
      (_) {},
      onDone: () => _sockets.remove(ws),
      onError: (Object _) => _sockets.remove(ws),
      cancelOnError: true,
    );
  }
}

/// Camera-local wall time without zone, as `/v1/props` `datetime`.
String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
