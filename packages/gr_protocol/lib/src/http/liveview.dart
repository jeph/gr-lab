import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../trace.dart';
import 'errors.dart';
import 'json.dart';
import 'mjpeg.dart';
import 'request.dart';

/// Opens a TCP connection to the camera. Supply one that binds to the camera
/// network (e.g. an Android `Network.socketFactory`) when the platform needs
/// it (docs/protocol/connection-lifecycle.md §9).
typedef GrSocketConnector = Future<Socket> Function(
  String host,
  int port,
  Duration timeout,
);

Future<Socket> defaultSocketConnector(
  String host,
  int port,
  Duration timeout,
) => Socket.connect(host, port, timeout: timeout);

/// One live-view JPEG.
final class LiveViewFrame {
  LiveViewFrame({
    required this.sequence,
    required this.jpeg,
    required this.receivedAt,
    required this.sinceOpen,
  });

  /// 1-based frame number within this stream.
  final int sequence;
  final Uint8List jpeg;
  final DateTime receivedAt;

  /// Time since the response head arrived.
  final Duration sinceOpen;

  late final JpegDimensions? dimensions = readJpegDimensions(jpeg);
}

/// A frame exceeded [LiveViewStream.maxFrameBytes] and was discarded. The
/// stream continues with the next frame.
final class LiveViewFrameTooLargeException implements Exception {
  const LiveViewFrameTooLargeException(this.bytes, this.limit);
  final int bytes;
  final int limit;

  @override
  String toString() =>
      'LiveViewFrameTooLargeException: frame passed $limit bytes '
      '($bytes discarded)';
}

/// Counters for a live-view session.
final class LiveViewStats {
  int frames = 0;
  int frameBytes = 0;
  int minFrameBytes = 0;
  int maxFrameBytes = 0;
  int tooLarge = 0;
  int interrupted = 0;

  /// Response body bytes received (after de-chunking).
  int bodyBytes = 0;
  Duration? firstFrame;
  Duration? lastFrame;
  JpegDimensions? lastDimensions;
  final Set<String> resolutions = {};

  /// Average frame rate between the first and last frame.
  double? get fps {
    final first = firstFrame, last = lastFrame;
    if (first == null || last == null || frames < 2 || last <= first) {
      return null;
    }
    return (frames - 1) * 1e6 / (last - first).inMicroseconds;
  }

  Map<String, Object?> toJson() => {
    'frames': frames,
    'frameBytes': frameBytes,
    'minFrameBytes': minFrameBytes,
    'maxFrameBytes': maxFrameBytes,
    'avgFrameBytes': frames == 0 ? null : frameBytes ~/ frames,
    'fps': fps,
    'resolutions': resolutions.toList(),
    'tooLarge': tooLarge,
    'interrupted': interrupted,
    'bodyBytes': bodyBytes,
  };
}

/// `GET /v1/liveview[?maxfps=N][&reso=…]` as a stream of JPEG frames
/// (docs/protocol/remote-shooting.md §1).
///
/// Runs on a raw socket rather than `HttpClient` so that [close] tears the
/// connection down immediately (Image Sync's stop never closes the socket and
/// can hang on a stalled camera, §1.4) and so that the response is parsed
/// tolerantly: no Content-Length is needed, chunked transfer is decoded, and
/// frames are split by JPEG markers ([MjpegSplitter]).
final class LiveViewStream {
  LiveViewStream._(
    this._socket,
    this.uri,
    this.maxFrameBytes,
    this._idleTimeout,
    this._trace,
    this._now,
  ) : _splitter = MjpegSplitter(maxFrameBytes: maxFrameBytes);

  /// Validates options, connects, sends the request and waits for the
  /// response head. Throws [GrApiException]/[GrHttpStatusException] for a
  /// non-200 response, [GrMalformedResponseException] for an unparsable head,
  /// and transport exceptions as thrown by [connector].
  ///
  /// [maxFps]: the firmware accepts 1..90 and defaults to 90 when absent
  /// (§1.3); other values are rejected here. [reso]: syntax is [unknown]
  /// (third-party clients send `720x480`); it is sent as given after
  /// query-encoding. [idleTimeout] ends the stream with a
  /// [TimeoutException] when no bytes arrive for that long; `null` waits
  /// forever like Image Sync.
  static Future<LiveViewStream> open(
    String host, {
    int port = 80,
    int? maxFps,
    String? reso,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration? idleTimeout = const Duration(seconds: 10),
    int maxFrameBytes = MjpegSplitter.defaultMaxFrameBytes,
    TraceSink? trace,
    GrSocketConnector connector = defaultSocketConnector,
    DateTime Function()? clock,
  }) async {
    final uri = liveViewUri(host, port: port, maxFps: maxFps, reso: reso);
    final now = clock ?? DateTime.now;
    trace?.call(
      TraceEvent(
        channel: TraceChannel.liveview,
        direction: TraceDirection.outbound,
        kind: 'request',
        fields: {'method': 'GET', 'url': uri.toString()},
      ),
    );
    final socket = await connector(host, port, connectTimeout);
    final stream = LiveViewStream._(
      socket,
      uri,
      maxFrameBytes,
      idleTimeout,
      trace,
      now,
    );
    try {
      await stream._start(connectTimeout);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
    return stream;
  }

  /// Builds the live-view URL; throws [ArgumentError] for invalid options.
  static Uri liveViewUri(
    String host, {
    int port = 80,
    int? maxFps,
    String? reso,
  }) {
    if (maxFps != null && (maxFps < 1 || maxFps > 90)) {
      throw ArgumentError.value(maxFps, 'maxFps', 'firmware accepts 1..90');
    }
    if (reso != null && reso.trim().isEmpty) {
      throw ArgumentError.value(reso, 'reso', 'must not be empty');
    }
    final query = {if (maxFps != null) 'maxfps': '$maxFps', 'reso': ?reso};
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: '/v1/liveview',
      query: encodeQuery(query),
    );
  }

  final Socket _socket;
  final Uri uri;
  final int maxFrameBytes;
  final Duration? _idleTimeout;
  final TraceSink? _trace;
  final DateTime Function() _now;
  final MjpegSplitter _splitter;
  final StreamController<LiveViewFrame> _frames = StreamController();
  final Completer<void> _head = Completer();
  final Stopwatch _clock = Stopwatch();
  final BytesBuilder _headBuf = BytesBuilder();
  final BytesBuilder _errorBody = BytesBuilder();
  final LiveViewStats stats = LiveViewStats();
  StreamSubscription<Uint8List>? _sub;
  HttpChunkedDecoder? _chunked;
  Timer? _idle;
  int? _contentLength;
  bool _closed = false;
  bool _headParsed = false;

  /// Response status (200 once [open] returned).
  int statusCode = 0;

  /// Response headers, lower-case names.
  final Map<String, String> headers = {};

  /// JPEG frames. Errors: [LiveViewFrameTooLargeException] (non-fatal),
  /// [TimeoutException] or a transport error (fatal, the stream then closes).
  /// The stream closes when the camera ends the response or [close] is called.
  Stream<LiveViewFrame> get frames => _frames.stream;

  /// Completes when the stream has closed for any reason.
  Future<void> get done => _frames.done;

  Future<void> _start(Duration headTimeout) async {
    _socket.write(
      'GET ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''} HTTP/1.1\r\n'
      'Host: ${uri.host}${uri.port == 80 ? '' : ':${uri.port}'}\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n',
    );
    _sub = _socket.listen(_onData, onError: _onError, onDone: _onDone);
    await _head.future.timeout(
      headTimeout,
      onTimeout: () => throw TimeoutException(
        'no live-view response head within $headTimeout',
        headTimeout,
      ),
    );
  }

  void _onData(Uint8List data) {
    if (_closed) return;
    _armIdle();
    if (!_headParsed) {
      _headBuf.add(data);
      _tryParseHead();
      return;
    }
    if (statusCode != 200) {
      _addErrorBody(data);
      return;
    }
    _body(data);
  }

  void _tryParseHead() {
    final bytes = _headBuf.toBytes();
    var end = -1;
    var sepLen = 0;
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0x0A && bytes[i + 1] == 0x0A) {
        end = i;
        sepLen = 2;
        break;
      }
      if (i + 3 < bytes.length &&
          bytes[i] == 0x0D &&
          bytes[i + 1] == 0x0A &&
          bytes[i + 2] == 0x0D &&
          bytes[i + 3] == 0x0A) {
        end = i;
        sepLen = 4;
        break;
      }
    }
    if (end < 0) {
      if (bytes.length > 16 * 1024) {
        _failHead(
          GrMalformedResponseException(
            route: 'GET /v1/liveview',
            httpStatus: null,
            issue: 'response head exceeds 16 KiB',
          ),
        );
      }
      return;
    }
    final lines = latin1
        .decode(Uint8List.sublistView(bytes, 0, end))
        .split('\n')
        .map((l) => l.trimRight())
        .toList();
    final status = RegExp(r'^HTTP/\d\.\d\s+(\d{3})').firstMatch(lines.first);
    if (status == null) {
      _failHead(
        GrMalformedResponseException(
          route: 'GET /v1/liveview',
          httpStatus: null,
          issue: 'bad status line',
          bodyText: lines.first,
        ),
      );
      return;
    }
    statusCode = int.parse(status.group(1)!);
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim().toLowerCase()] = line
          .substring(colon + 1)
          .trim();
    }
    _contentLength = int.tryParse(headers['content-length'] ?? '');
    if ((headers['transfer-encoding'] ?? '').toLowerCase().contains(
      'chunked',
    )) {
      _chunked = HttpChunkedDecoder();
    }
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.liveview,
        direction: TraceDirection.inbound,
        kind: 'response',
        fields: {'status': statusCode, 'headers': Map.of(headers)},
      ),
    );
    _headParsed = true;
    final rest = Uint8List.sublistView(bytes, end + sepLen);
    if (statusCode != 200) {
      _addErrorBody(rest);
      return;
    }
    _clock.start();
    _head.complete();
    if (rest.isNotEmpty) _body(rest);
  }

  void _body(Uint8List data) {
    if (_closed) return;
    var payload = data;
    final chunked = _chunked;
    if (chunked != null) {
      payload = chunked.add(data);
      if (chunked.error != null) {
        _fail(
          GrMalformedResponseException(
            route: 'GET /v1/liveview',
            httpStatus: statusCode,
            issue: chunked.error!,
          ),
        );
        return;
      }
    }
    final limit = _contentLength;
    if (limit != null && stats.bodyBytes + payload.length > limit) {
      payload = Uint8List.sublistView(payload, 0, limit - stats.bodyBytes);
    }
    stats.bodyBytes += payload.length;
    for (final event in _splitter.add(payload)) {
      switch (event) {
        case MjpegFrame(:final jpeg):
          _emit(jpeg);
        case MjpegDropped(:final reason, :final bytes):
          _trace?.call(
            TraceEvent(
              channel: TraceChannel.liveview,
              direction: TraceDirection.internal,
              kind: 'dropped',
              fields: {'reason': reason.name, 'bytes': bytes},
            ),
          );
          if (reason == MjpegDropReason.tooLarge) {
            stats.tooLarge++;
            if (!_closed) {
              _frames.addError(
                LiveViewFrameTooLargeException(bytes, maxFrameBytes),
              );
            }
          } else {
            stats.interrupted++;
          }
      }
    }
    if ((limit != null && stats.bodyBytes >= limit) ||
        (chunked?.done ?? false)) {
      unawaited(close());
    }
  }

  void _emit(Uint8List jpeg) {
    if (_closed) return;
    final since = _clock.elapsed;
    final frame = LiveViewFrame(
      sequence: ++stats.frames,
      jpeg: jpeg,
      receivedAt: _now(),
      sinceOpen: since,
    );
    stats.frameBytes += jpeg.length;
    stats.minFrameBytes = stats.frames == 1
        ? jpeg.length
        : (jpeg.length < stats.minFrameBytes
              ? jpeg.length
              : stats.minFrameBytes);
    if (jpeg.length > stats.maxFrameBytes) stats.maxFrameBytes = jpeg.length;
    stats.firstFrame ??= since;
    stats.lastFrame = since;
    final dims = frame.dimensions;
    if (dims != null) {
      stats.lastDimensions = dims;
      stats.resolutions.add(dims.toString());
    }
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.liveview,
        direction: TraceDirection.inbound,
        kind: 'frame',
        fields: {
          'sequence': frame.sequence,
          'bytes': jpeg.length,
          'elapsedMs': since.inMilliseconds,
          if (dims != null) 'width': dims.width,
          if (dims != null) 'height': dims.height,
        },
      ),
    );
    _frames.add(frame);
  }

  void _addErrorBody(Uint8List data) {
    final room = 64 * 1024 - _errorBody.length;
    if (room > 0) {
      _errorBody.add(
        data.length <= room ? data : Uint8List.sublistView(data, 0, room),
      );
    }
    final limit = _contentLength;
    if (room <= data.length || (limit != null && _errorBody.length >= limit)) {
      _finishErrorBody();
    }
  }

  void _finishErrorBody() {
    final body = _errorBody.takeBytes();
    final json = decodeCameraJsonBytes(body);
    final map = json.object;
    final errCode = map == null ? null : JsonFields(map).integer('errCode');
    if (map != null && errCode != null && errCode != 200) {
      _failHead(
        GrApiException(
          errCode: errCode,
          errMsg: JsonFields(map).string('errMsg'),
          route: 'GET /v1/liveview',
          httpStatus: statusCode,
          body: map,
        ),
      );
    } else {
      _failHead(
        GrHttpStatusException(
          route: 'GET /v1/liveview',
          httpStatus: statusCode,
          bodyText: json.text,
        ),
      );
    }
  }

  void _failHead(Object error) {
    if (!_head.isCompleted) _head.completeError(error);
    _closed = true;
    _idle?.cancel();
    _socket.destroy();
    unawaited(_frames.close());
  }

  void _onError(Object error, StackTrace stack) {
    if (!_head.isCompleted) {
      _failHead(error);
      return;
    }
    _fail(error, stack);
  }

  void _onDone() {
    if (_closed) return;
    if (!_head.isCompleted) {
      if (statusCode != 0 && statusCode != 200) {
        _finishErrorBody();
      } else {
        _failHead(
          GrMalformedResponseException(
            route: 'GET /v1/liveview',
            httpStatus: null,
            issue: 'connection closed before the response head ended',
          ),
        );
      }
      return;
    }
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.liveview,
        direction: TraceDirection.inbound,
        kind: 'end',
        fields: {...stats.toJson(), 'pendingBytes': _splitter.pendingBytes},
      ),
    );
    unawaited(close());
  }

  void _armIdle() {
    final timeout = _idleTimeout;
    if (timeout == null || _closed) return;
    _idle?.cancel();
    _idle = Timer(timeout, () {
      if (!_head.isCompleted) return;
      _fail(TimeoutException('no live-view data for $timeout', timeout));
    });
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_closed) return;
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.liveview,
        direction: TraceDirection.internal,
        kind: 'error',
        fields: {'error': error.toString()},
      ),
    );
    _frames.addError(error, stack);
    unawaited(close());
  }

  /// Destroys the socket at once (the firmware then leaves remote-LV mode and
  /// closes its side, remote-shooting.md §1.3) and closes [frames].
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    _socket.destroy();
    await _sub?.cancel();
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.liveview,
        direction: TraceDirection.internal,
        kind: 'close',
        fields: stats.toJson(),
      ),
    );
    unawaited(_frames.close());
  }
}
