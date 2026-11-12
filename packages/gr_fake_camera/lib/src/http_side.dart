part of 'fake_camera.dart';

/// The firmware pretty-prints its JSON with four spaces (GR IV captures).
const _json = JsonEncoder.withIndent('    ');

extension on FakeGrCamera {
  Future<int> _startHttp() async {
    final running = _server;
    if (running != null) return running.port;
    if (_closed) throw StateError('FakeGrCamera is closed');
    _httpZone = Zone.current;
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
      switch ((request.method, route)) {
        case ('POST', ['camera', 'shoot']):
          return await _shoot(request);
        case ('POST', ['camera', 'shoot', 'cancel']):
          return await _cancelShoot(request);
        case ('POST', ['lens', 'focus']):
          return await _focus(request);
        case ('PUT', ['params', 'camera']):
          return await _putCameraParams(request);
        case ('GET', ['liveview']):
          return await _liveView(request);
      }
      if (request.method != 'GET') {
        return await _error(request, 405, 'Method Not Allowed');
      }
      switch (route) {
        case ['props']:
          if (propsGate case final gate?) await gate.future;
          return await _send(request, _props());
        case ['ping']:
          return await _send(request, {
            'errCode': 200,
            'errMsg': 'OK',
            'datetime': _stamp(clockTime),
          });
        case ['photos']:
          return await _list(request);
        // GR III/IV webapid has no /latest route: errCode 400 under HTTP
        // 200 (hardware-validation.md §4).
        case ['photos', 'latest', 'info']:
          return await _error(request, 400, 'Bad Request', httpStatus: 200);
        case ['photos', final dir, final file, 'info']:
          if (infoGate case final gate?) await gate.future;
          return await _info(request, dir, file);
        case ['photos', final dir, final file, 'imgctrl']:
          return await _imageControl(request, dir, file);
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
    'operationModeList': ['capture', 'playback'],
    'stillFormatList': ['jpeg', 'dng', 'rawdng'],
    'storages': [
      for (final name in _storages)
        {
          'name': name,
          'equipped': true,
          'available': true,
          'writable': true,
          'format': 'rawdng',
          'remain': _remainOn(name),
          'recordableTime': name == GrStorageId.sd
              ? _sdRecordableTime
              : _internalRecordableTime,
          'numOfPhotos': _photos
              .where((p) => p.storage == name && !p.isVideo)
              .length,
          'numOfMovies': _photos
              .where((p) => p.storage == name && p.isVideo)
              .length,
        },
    ],
    'datetime': _stamp(clockTime),
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
    'exposureModeList': _exposureModes,
    'exposureMode': _exposureModeText,
    for (final key in _settingLists.keys) ...{
      key: key == 'shootMode' ? _shootMode : _settings[key],
      '${key}List': _listFor(key),
    },
    'focusMode': 'af',
    'focusEffectiveArea': _focusEffectiveArea,
    // Image Sync's `state` key; its values are [unknown].
    'state': _releaseBusy ? 'busy' : 'idle',
    'capturing': _capturing,
    'countDown': _countDownText,
    'stateStill': _capturing ? 'busy' : 'idle',
    'stateMovie': 'idle',
    'cameraOrientation': _orientation.wire,
  };

  Future<String> _body(HttpRequest request) =>
      utf8.decoder.bind(request).join();

  /// `POST /v1/camera/shoot`, body `""`, `af=on` or `af=on&pos=X,Y`
  /// (remote-shooting.md §2.1): a release as over BLE. The picture follows
  /// as change events; `captured` false says it is not on the card yet
  /// \[design\].
  Future<void> _shoot(HttpRequest request) async {
    final params = _keyValues(await _body(request));
    final pos = params?['pos'];
    if (params == null || (pos != null && _focusPos(pos) == null)) {
      return await _error(request, 400, 'Bad Request');
    }
    if (_releaseRefusal() case (final code, final why)?) {
      return await _error(request, code, why);
    }
    final id = _release();
    return await _send(request, {
      'errCode': 200,
      'errMsg': 'OK',
      'captureId': id,
      'captured': false,
      'focused': true,
    });
  }

  /// `POST /v1/camera/shoot/cancel` (firmware `CancelShootTimer`): ends a
  /// self-timer countdown; OK without one too \[design\].
  Future<void> _cancelShoot(HttpRequest request) async {
    await _body(request);
    _cancelSelfTimer();
    return await _send(request, {'errCode': 200, 'errMsg': 'OK'});
  }

  /// `POST /v1/lens/focus`, body `""` or `pos=X,Y` (remote-shooting.md
  /// §3.1), on the point (the centre without one). Answered as the GR IV
  /// does, with a `ShootResponse`: `errCode`, `errMsg` and `captureId`
  /// only (`Capture::Focus`; a GR IV HDF answered without `focused` or
  /// `focusRunning`, 2026-11-08). The result follows as a `lens` change
  /// with that `captureId` after [FakeCameraConfig.focusTime]. A focus
  /// sent while one runs is answered once that one ends, as the GR IV's
  /// answers came later and later in a quick series of taps. Refused
  /// outside capture mode \[design\].
  Future<void> _focus(HttpRequest request) async {
    final params = _keyValues(await _body(request));
    final posText = params?['pos'];
    final pos = posText == null ? (50, 50) : _focusPos(posText);
    if (params == null || pos == null) {
      return await _error(request, 400, 'Bad Request');
    }
    if (_mode != BleOperationMode.capture.wire) {
      return await _error(request, 400, 'not in capture mode');
    }
    final previous = _focusEnd;
    final end = Completer<void>();
    _focusEnd = end.future;
    await previous;
    final id = '${++_captureIds}';
    _focusPoints.add(pos);
    void lens() {
      _push({
        'errCode': 200,
        'changed': 'lens',
        'captureId': id,
        'focused': true,
      });
      end.complete();
    }

    final answer = {'errCode': 200, 'errMsg': 'OK', 'captureId': id};
    if (config.lensBeforeFocusAnswer) {
      await Future<void>.delayed(config.focusTime);
      if (_closed) return;
      lens();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return await _send(request, answer);
    }
    await _send(request, answer);
    _after(config.focusTime, lens);
  }

  /// `PUT /v1/params/camera` with `key=value[&…]` (remote-shooting.md
  /// §4.2): every value must be in its `<key>List`, else nothing changes
  /// and errCode 400 answers. Replies with the props without the lists
  /// the GR IV builds in `CameraConstants` (`_constantLists`). An empty
  /// body is the green button, which changes nothing here \[design\].
  Future<void> _putCameraParams(HttpRequest request) async {
    final params = _keyValues(await _body(request));
    if (params == null) return await _error(request, 400, 'Bad Request');
    final refused = _applyCameraParams(params);
    if (refused != null) {
      return await _error(request, 400, 'Bad Request: $refused');
    }
    return await _send(
      request,
      _props()..removeWhere((k, _) => _constantLists.contains(k)),
    );
  }

  /// Lists the GR IV's `/v1/props` takes from `CameraConstants::Fetch`
  /// (`*::GetSupportedValues`), which its `PUT /v1/params/camera` answer
  /// (`ParamsCameraResponse::Fetch`: `CameraStatus` + `CameraParams`)
  /// leaves out (webapid 0x9c290, 0x74a78).
  static const _constantLists = {
    'captureModeList',
    'effectList',
    'exposureModeList',
    'meteringModeList',
    'movieSizeList',
    'resoList',
    'shootModeList',
    'stillSizeList',
    'WBModeList',
  };

  /// `GET /v1/liveview[?maxfps=N]` as the firmware sends it
  /// (remote-shooting.md §1.2-1.3): the header block declaring
  /// `boundary=--boundary`, then `--boundary` parts without Content-Length
  /// until the client hangs up or the access point goes down. Frames are
  /// the views of the newest stills on the card, in turn. A non-digit
  /// `maxfps` is a BadRequest; 1–90 lowers the rate, anything else is
  /// clamped (to the default).
  Future<void> _liveView(HttpRequest request) async {
    var fps = _liveViewFps;
    final maxFps = request.uri.queryParameters['maxfps'];
    if (maxFps != null) {
      if (!RegExp(r'^\d+$').hasMatch(maxFps)) {
        return await _error(request, 400, 'Bad Request');
      }
      final n = int.parse(maxFps);
      if (n >= 1 && n < fps) fps = n;
    }
    final frames = await _liveViewFrames();
    if (!_httpReachable) return await _hangUp(request);
    final socket = await request.response.detachSocket(writeHeaders: false);
    socket.done.ignore();
    _liveViews.add(socket);
    var open = true;
    socket.listen(
      (_) {},
      onDone: () => open = false,
      onError: (Object _) => open = false,
      cancelOnError: true,
    );
    final interval = Duration(
      microseconds: Duration.microsecondsPerSecond ~/ fps,
    );
    try {
      socket.add(
        latin1.encode(
          'HTTP/1.1 200 OK\r\n'
          'Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n'
          'Expires: 0\r\n'
          'Pragma: no-cache\r\n'
          'Content-Type: multipart/x-mixed-replace; boundary=--boundary\r\n'
          '\r\n',
        ),
      );
      for (var i = 0; open && _httpReachable; i++) {
        socket
          ..add(latin1.encode('--boundary\r\nContent-Type: image/jpeg\r\n\r\n'))
          ..add(frames[i % frames.length])
          ..add(const [0x0D, 0x0A]);
        await socket.flush();
        await Future<void>.delayed(interval);
      }
    } on Object {
      // The client hung up mid-frame.
    } finally {
      _liveViews.remove(socket);
      socket.destroy();
    }
  }

  /// Views of up to four of the newest stills; a plain JPEG when the card
  /// has none or the media source fails.
  Future<List<Uint8List>> _liveViewFrames() async {
    final frames = <Uint8List>[];
    for (final photo in _photos.reversed.where((p) => !p.isVideo).take(4)) {
      try {
        frames.add(await _media(photo, GrImageSize.view));
      } on Object {
        // Skipped; another still or the fallback stands in.
      }
    }
    if (frames.isEmpty) {
      frames.add(
        await syntheticMedia()(
          FakePhoto('100RICOH', 'R0000001.JPG', DateTime(2000)),
          GrImageSize.view,
        ),
      );
    }
    return frames;
  }

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
      return await _error(request, 400, 'Bad Request');
    }
    if (failingListings.contains(storage)) {
      return await _error(request, 500, 'Internal Server Error');
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
    return await _send(request, {'errCode': 200, 'errMsg': 'OK', 'dirs': dirs});
  }

  FakePhoto? _requested(HttpRequest request, String dir, String file) => _find(
    request.uri.queryParameters['storage'] ?? _defaultStorage,
    dir,
    file,
  );

  Future<int> _fullSize(FakePhoto photo) async =>
      photo.size ??
      _fullSizes[photo] ??
      (_fullSizes[photo] = (await _media(photo, GrImageSize.full)).length);

  Future<void> _info(HttpRequest request, String dir, String file) async {
    final photo = _requested(request, dir, file);
    if (photo == null) return await _error(request, 404, 'Not Found');
    final int size;
    try {
      size = await _fullSize(photo);
    } on Object {
      return await _error(request, 500, 'Internal Server Error');
    }
    // Stored (sensor) layout for every still, as the EXIF image size of a
    // portrait GR IV HDF file reads (6192×4128); what the camera's own
    // `resolution` says for a portrait frame is untested.
    final (resolution, aspect) = photo.isVideo
        ? ('1920x1080', '16:9')
        : ('6000x4000', '3:2');
    return await _send(request, {
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

  /// `/imgctrl`: the photo's Image Control blob (http-api.md §4.3).
  Future<void> _imageControl(
    HttpRequest request,
    String dir,
    String file,
  ) async {
    final blob = _requested(request, dir, file)?.imageControl;
    if (blob == null) return await _error(request, 404, 'Not Found');
    request.response
      ..statusCode = 200
      ..contentLength = blob.length
      ..headers.contentType = ContentType.binary
      ..add(blob);
    await request.response.close();
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
    if (size == null) return await _error(request, 400, 'Bad Request');
    final photo = _requested(request, dir, file);
    if (photo == null) return await _error(request, 404, 'Not Found');
    if (size != GrImageSize.full) {
      final key = '$photo|${size.name}';
      final served = _previewRequests[key] = (_previewRequests[key] ?? 0) + 1;
      if (served <= config.previewFailures) {
        return await _error(request, 503, 'Service Unavailable');
      }
      if (served <= config.previewFailures + config.brokenPreviews) {
        final broken = [0xFF, 0xD8, 0x00, 0x00];
        request.response
          ..statusCode = 200
          ..contentLength = broken.length
          ..headers.contentType = ContentType('image', 'jpeg')
          ..add(broken);
        await request.response.close();
        return;
      }
    }
    final Uint8List bytes;
    try {
      bytes = await _media(photo, size);
    } on Object {
      return await _error(request, 500, 'Internal Server Error');
    }
    if (!_httpReachable) return await _hangUp(request);

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
