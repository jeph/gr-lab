import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gr_protocol/src/http/errors.dart';
import 'package:gr_protocol/src/http/json.dart';
import 'package:gr_protocol/src/http/mjpeg.dart';
import 'package:gr_protocol/src/http/request.dart';
import 'package:gr_protocol/src/trace.dart';

/// Opens a TCP connection to the camera. Supply one that binds to the camera
/// network (e.g. an Android `Network.socketFactory`) when the platform needs
/// it (docs/protocol/connection-lifecycle.md §9).
typedef GrSocketConnector = Future<Socket> Function(
  String host,
  int port,
  Duration timeout,
);

/// Plain `Socket.connect`, without binding to a particular network.
Future<Socket> defaultSocketConnector(
  String host,
  int port,
  Duration timeout,
) => Socket.connect(host, port, timeout: timeout);

/// One live-view JPEG.
final class LiveViewFrame {
  /// Frame [sequence] with its bytes and arrival times.
  new({
    required this.sequence,
    required this.jpeg,
    required this.receivedAt,
    required this.sinceOpen,
  });

  /// 1-based frame number within this stream.
  final int sequence;

  /// The frame's JPEG bytes, SOI through EOI.
  final Uint8List jpeg;

  /// Local time the frame was complete.
  final DateTime receivedAt;

  /// Time since the response head arrived.
  final Duration sinceOpen;

  /// Size from the JPEG's SOF segment, or `null` when it has none.
  late final JpegDimensions? dimensions = readJpegDimensions(jpeg);
}

/// A frame exceeded [LiveViewStream.maxFrameBytes] and was discarded. The
/// stream continues with the next frame.
final class LiveViewFrameTooLargeException implements Exception {
  /// [bytes] were discarded because they passed [limit].
  const new(this.bytes, this.limit);

  /// Bytes discarded.
  final int bytes;

  /// The [LiveViewStream.maxFrameBytes] in force.
  final int limit;

  @override
  String toString() =>
      'LiveViewFrameTooLargeException: frame passed $limit bytes '
      '($bytes discarded)';
}

/// Counters for a live-view session.
final class LiveViewStats {
  /// Frames delivered.
  int frames = 0;

  /// Total bytes of delivered frames.
  int frameBytes = 0;

  /// Smallest delivered frame in bytes; 0 before the first frame.
  int minFrameBytes = 0;

  /// Largest delivered frame in bytes.
  int maxFrameBytes = 0;

  /// Frames dropped for exceeding [LiveViewStream.maxFrameBytes].
  int tooLarge = 0;

  /// Partial frames dropped because a new frame started before their end.
  int interrupted = 0;

  /// Response body bytes received (after de-chunking).
  int bodyBytes = 0;

  /// Time from the response head to the first frame.
  Duration? firstFrame;

  /// Time from the response head to the latest frame.
  Duration? lastFrame;

  /// Size of the latest frame that had one.
  JpegDimensions? lastDimensions;

  /// Every distinct frame size seen, as `WxH`.
  final Set<String> resolutions = {};

  /// Average frame rate between the first and last frame.
  double? get fps {
    final first = firstFrame;
    final last = lastFrame;
    if (first == null || last == null || frames < 2 || last <= first) {
      return null;
    }
    return (frames - 1) * 1e6 / (last - first).inMicroseconds;
  }

  /// Trace/log form, with average frame size.
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
  new _(
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
  /// (§1.3); other values are rejected here. [reso]: syntax is \[unknown\]
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
        fields: {
          'method': 'GET',
          'url': uri.toString(),
          'head': _requestHead(uri),
        },
      ),
    );
    final Socket socket;
    try {
      socket = await connector(host, port, connectTimeout);
    } catch (e) {
      trace?.call(
        TraceEvent(
          channel: TraceChannel.liveview,
          direction: TraceDirection.internal,
          kind: 'error',
          fields: {'error': e.toString()},
        ),
      );
      rethrow;
    }
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
    } catch (e) {
      trace?.call(
        TraceEvent(
          channel: TraceChannel.liveview,
          direction: TraceDirection.internal,
          kind: 'error',
          fields: {'error': e.toString()},
        ),
      );
      socket.destroy();
      rethrow;
    }
    return stream;
  }

  /// The request as written to the socket, also traced in full.
  static String _requestHead(Uri uri) =>
      'GET ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''} HTTP/1.1\r\n'
      'Host: ${uri.host}${uri.port == 80 ? '' : ':${uri.port}'}\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n';

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

  /// The request URL.
  final Uri uri;

  /// Largest frame kept; longer frames are dropped and reported.
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

  /// Counters, updated as frames arrive.
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
    _socket.write(_requestHead(uri));
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
          const GrMalformedResponseException(
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
        case MjpegFrame(:final jpeg, :final partHeader):
          _emit(jpeg, partHeader);
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

  void _emit(Uint8List jpeg, String partHeader) {
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
          if (partHeader.isNotEmpty) 'partHeader': partHeader,
        },
      ),
    );
    _frames.add(frame);
  }

  /// The most of a non-200 body kept, as for every other HTTP response; the
  /// body is traced in full up to this.
  static const int _maxErrorBodyBytes = 32 * 1024 * 1024;

  void _addErrorBody(Uint8List data) {
    final room = _maxErrorBodyBytes - _errorBody.length;
    if (room > 0) {
      _errorBody.add(
        data.length <= room ? data : Uint8List.sublistView(data, 0, room),
      );
    }
    final limit = _contentLength;
    if (room <= data.length || (limit != null && _errorBody.length >= limit)) {
      _finishErrorBody(truncated: room < data.length);
    }
  }

  void _finishErrorBody({bool truncated = false}) {
    final body = _errorBody.takeBytes();
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.liveview,
        direction: TraceDirection.inbound,
        kind: 'errorBody',
        fields: {
          'status': statusCode,
          'body': utf8.decode(body, allowMalformed: true),
          if (truncated) 'truncated': true,
        },
      ),
    );
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
          const GrMalformedResponseException(
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
