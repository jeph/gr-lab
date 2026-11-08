import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../trace.dart';
import 'json.dart';
import 'request.dart';

/// One message from `ws://<host>/v1/changes`
/// (docs/protocol/http-api.md §5, docs/protocol/remote-shooting.md §2.3).
///
/// GR WORLD only knows `storage|battery|camera`; Image Sync also dispatches
/// `cameraDirect`, `lens`, `capture` and `transfer`. Whether GR IV emits the
/// Image Sync payloads is [unknown] (remote-shooting.md §8): the key strings
/// exist in GR IV webapid. Parsing never throws.
sealed class GrChangeEvent {
  GrChangeEvent(this.raw, this.receivedAt);

  /// Parses a WebSocket message (text or UTF-8 bytes).
  factory GrChangeEvent.parse(Object? message, {DateTime? receivedAt}) {
    final at = receivedAt ?? DateTime.now();
    final text = switch (message) {
      final String s => s,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => '$message',
    };
    final json = decodeCameraJson(text);
    final map = json.object;
    if (map == null) {
      return GrUnparsedChange(text, json.issue ?? 'not a JSON object', at);
    }
    final f = JsonFields(map);
    // Image Sync: `if changed == null use change` (SyncTrigger.java:58-61).
    final kind = f.string('changed') ?? f.string('change');
    return switch (kind) {
      'storage' => GrStorageChange(map, at),
      'battery' => GrBatteryChange(map, at),
      'camera' => GrCameraChange(map, at),
      'cameraDirect' => GrCameraDirectChange(map, at),
      'lens' => GrLensChange(map, at),
      'capture' => GrCaptureChange(map, at),
      'transfer' => GrTransferChange(map, at),
      _ => GrUnknownChange(map, at),
    };
  }

  /// Complete message object, unknown keys included.
  final Map<String, Object?> raw;
  final DateTime receivedAt;

  JsonFields get fields => JsonFields(raw);

  /// `changed`, falling back to Image Sync's `change` alias.
  String? get changed => fields.string('changed') ?? fields.string('change');

  int? get errCode => fields.integer('errCode');

  /// GR WORLD ignores messages whose errCode is not 200 (http-api.md §5).
  bool get ok => errCode == 200;

  Map<String, Object?> toJson() => {
    'receivedAt': receivedAt.toIso8601String(),
    'changed': changed,
    'raw': raw,
  };
}

/// `changed:"storage"`; Image Sync reads `action`, `filepath`, `storage`,
/// `captureId`. `action == "add"` with a non-`"0"` captureId names a newly
/// captured file.
final class GrStorageChange extends GrChangeEvent {
  GrStorageChange(super.raw, super.receivedAt);

  String? get action => fields.string('action');
  String? get filepath => fields.string('filepath');
  String? get storage => fields.string('storage');
  String? get captureId => fields.string('captureId');

  GrPhotoPath? get path =>
      filepath == null ? null : GrPhotoPath.tryParseCamera(filepath!);
}

/// `changed:"battery"`: both apps re-read status/props.
final class GrBatteryChange extends GrChangeEvent {
  GrBatteryChange(super.raw, super.receivedAt);
}

/// `changed:"camera"`: settings changed; re-read `/v1/props`.
final class GrCameraChange extends GrChangeEvent {
  GrCameraChange(super.raw, super.receivedAt);
}

/// `changed:"cameraDirect"`: capture state (remote-shooting.md §2.3 table).
final class GrCameraDirectChange extends GrChangeEvent {
  GrCameraDirectChange(super.raw, super.receivedAt);

  String? get stateStill => fields.string('stateStill');
  String? get stateMovie => fields.string('stateMovie');

  /// `idle|busy2s|busy10s|busy12s|time`.
  String? get countDown => fields.string('countDown');
  bool? get capturing => fields.boolean('capturing');
  int? get shotsCurrent => fields.integer('shotsCurrent');
  int? get shotsTotal => fields.integer('shotsTotal');
  String? get shootMode => fields.string('shootMode');

  /// Image Sync's GR III still-capture completion rule: `stateStill` in
  /// {idle, continuous}, `countDown == idle` and not `capturing`.
  bool get stillCaptureComplete =>
      (stateStill == 'idle' || stateStill == 'continuous') &&
      countDown == 'idle' &&
      capturing == false;

  /// Image Sync's movie completion rule: `stateMovie == idle`.
  bool get movieCaptureComplete => stateMovie == 'idle';
}

/// `changed:"lens"`: focus result for a `captureId` (`"0"` is ignored by
/// Image Sync).
final class GrLensChange extends GrChangeEvent {
  GrLensChange(super.raw, super.receivedAt);

  String? get captureId => fields.string('captureId');
  bool? get focused => fields.boolean('focused');
}

/// `changed:"capture"`: the capture with `captureId` finished.
final class GrCaptureChange extends GrChangeEvent {
  GrCaptureChange(super.raw, super.receivedAt);

  String? get captureId => fields.string('captureId');
  bool? get result => fields.boolean('result');
}

/// `changed:"transfer"` (connection-imagesync.md §4): `action` in
/// `add|state|delete|format`; `state` `untransferred|transferred`.
final class GrTransferChange extends GrChangeEvent {
  GrTransferChange(super.raw, super.receivedAt);

  String? get action => fields.string('action');
  String? get storage => fields.string('storage');
  int? get index => fields.integer('index');
  String? get filepath => fields.string('filepath');
  String? get size => fields.string('size');
  String? get state => fields.string('state');
}

/// Any other `changed` value (or none); kept raw.
final class GrUnknownChange extends GrChangeEvent {
  GrUnknownChange(super.raw, super.receivedAt);
}

/// A message that is not a JSON object.
final class GrUnparsedChange extends GrChangeEvent {
  GrUnparsedChange(this.text, this.issue, DateTime receivedAt)
    : super(const {}, receivedAt);

  final String text;
  final String issue;

  @override
  Map<String, Object?> toJson() => {
    'receivedAt': receivedAt.toIso8601String(),
    'unparsed': text,
    'issue': issue,
  };
}

/// What [GrChangesSocket] does after an established socket drops.
sealed class GrReconnectPolicy {
  const GrReconnectPolicy();

  /// Delay before reconnect [attempt] (1-based), or `null` to give up.
  Duration? delayBefore(int attempt);
}

/// Never reconnect: GR WORLD's behaviour (http-api.md §5, "no automatic
/// reconnect").
final class GrNoReconnect extends GrReconnectPolicy {
  const GrNoReconnect();

  @override
  Duration? delayBefore(int attempt) => null;
}

/// Reopen at once, forever: Image Sync's `onFailure` behaviour
/// (connection-imagesync.md §2.2). A refused connection retries in a tight
/// loop throttled only by the connect timeout.
final class GrImmediateReconnect extends GrReconnectPolicy {
  const GrImmediateReconnect();

  @override
  Duration? delayBefore(int attempt) => Duration.zero;
}

/// Capped backoff with a bounded number of attempts (the default; a design
/// choice following connection-lifecycle.md §9's "rejoin with backoff").
final class GrBackoffReconnect extends GrReconnectPolicy {
  const GrBackoffReconnect({
    this.delays = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
    this.maxAttempts = 10,
  });

  /// Delay per attempt; the last entry repeats.
  final List<Duration> delays;

  /// `null` retries forever.
  final int? maxAttempts;

  @override
  Duration? delayBefore(int attempt) {
    final max = maxAttempts;
    if (max != null && attempt > max) return null;
    if (delays.isEmpty) return Duration.zero;
    return delays[attempt - 1 < delays.length
        ? attempt - 1
        : delays.length - 1];
  }
}

enum GrSocketState {
  idle,
  connecting,
  open,

  /// Dropped; a reconnect is scheduled.
  reconnectWaiting,

  /// Dropped and the policy gave up.
  disconnected,

  /// [GrChangesSocket.close] was called.
  closed,
}

final class GrSocketStatus {
  const GrSocketStatus(this.state, {this.attempt = 0, this.error});
  final GrSocketState state;

  /// Reconnect attempt number while reconnecting.
  final int attempt;
  final Object? error;

  @override
  String toString() =>
      '${state.name}${attempt > 0 ? ' attempt=$attempt' : ''}'
      '${error == null ? '' : ' error=$error'}';
}

/// Client for `ws://<host>/v1/changes`.
///
/// No ping interval and no extra headers, like both apps; `dart:io` offers
/// `permessage-deflate` as Image Sync's OkHttp does
/// (connection-imagesync.md §2.2).
final class GrChangesSocket {
  GrChangesSocket(
    this.host, {
    this.port = 80,
    HttpClient? httpClient,
    this.connectTimeout = const Duration(seconds: 7),
    this.reconnect = const GrBackoffReconnect(),
    this._trace,
    DateTime Function()? clock,
  }) : _http = httpClient,
       _now = clock ?? DateTime.now;

  final String host;
  final int port;

  /// Image Sync uses 7 s (connection-imagesync.md §2.2).
  final Duration connectTimeout;
  final GrReconnectPolicy reconnect;
  final HttpClient? _http;
  final TraceSink? _trace;
  final DateTime Function() _now;

  // Synchronous so every event reaches listeners before a later status
  // (e.g. `disconnected`) on the separate async [statuses] stream; listeners
  // cannot re-enter [_onMessage].
  final StreamController<GrChangeEvent> _events = StreamController.broadcast(
    sync: true,
  );
  final StreamController<GrSocketStatus> _statuses =
      StreamController.broadcast();
  WebSocket? _socket;
  StreamSubscription<Object?>? _sub;
  Timer? _retry;
  Object? _lastError;
  int _attempt = 0;
  bool _closed = false;
  GrSocketStatus _status = const GrSocketStatus(GrSocketState.idle);

  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: '/v1/changes');

  Stream<GrChangeEvent> get events => _events.stream;
  Stream<GrSocketStatus> get statuses => _statuses.stream;
  GrSocketStatus get status => _status;

  /// Opens the socket. Throws the handshake failure (or [TimeoutException])
  /// of this first attempt; the reconnect policy applies only after a socket
  /// was established.
  Future<void> connect() async {
    if (_closed) throw StateError('GrChangesSocket is closed');
    if (_socket != null) return;
    await _open();
  }

  /// The first event matching [test] within [timeout], or `null`. Subscribe
  /// before triggering the request whose event you expect.
  Future<T?> waitFor<T extends GrChangeEvent>(
    bool Function(T event) test, {
    required Duration timeout,
  }) async {
    try {
      final event = await events
          .firstWhere((e) => e is T && test(e))
          .timeout(timeout);
      return event as T;
    } on TimeoutException {
      return null;
    } on StateError {
      return null;
    }
  }

  Future<void> _open() async {
    _setStatus(GrSocketStatus(GrSocketState.connecting, attempt: _attempt));
    _emitTrace(TraceDirection.outbound, 'connect', {'url': uri.toString()});
    final pending = WebSocket.connect(uri.toString(), customClient: _http);
    final WebSocket ws;
    try {
      ws = await pending.timeout(connectTimeout);
    } on TimeoutException {
      unawaited(pending.then<void>((w) => w.close(), onError: (Object _) {}));
      _emitTrace(TraceDirection.internal, 'connectTimeout', {
        'timeoutMs': connectTimeout.inMilliseconds,
      });
      rethrow;
    } catch (e) {
      _emitTrace(TraceDirection.internal, 'connectError', {'error': '$e'});
      rethrow;
    }
    if (_closed) {
      await ws.close(WebSocketStatus.normalClosure);
      return;
    }
    _socket = ws;
    _attempt = 0;
    _lastError = null;
    _emitTrace(TraceDirection.inbound, 'open', {'url': uri.toString()});
    _setStatus(const GrSocketStatus(GrSocketState.open));
    _sub = ws.listen(
      _onMessage,
      onError: (Object error) {
        _lastError = error;
        _emitTrace(TraceDirection.internal, 'error', {'error': '$error'});
      },
      onDone: _onDone,
    );
  }

  void _onMessage(Object? message) {
    final event = GrChangeEvent.parse(message, receivedAt: _now());
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.websocket,
        direction: TraceDirection.inbound,
        kind: 'message',
        fields: {
          'changed': event.changed,
          'text': message is String ? message : null,
          if (event is GrUnparsedChange) 'issue': event.issue,
        },
        bytes: message is List<int> ? Uint8List.fromList(message) : null,
      ),
    );
    if (!_events.isClosed) _events.add(event);
  }

  void _onDone() {
    final ws = _socket;
    _socket = null;
    _sub = null;
    _emitTrace(TraceDirection.inbound, 'closed', {
      'closeCode': ws?.closeCode,
      'closeReason': ws?.closeReason,
    });
    if (_closed) return;
    _scheduleReconnect(_lastError);
  }

  void _scheduleReconnect(Object? error) {
    _attempt++;
    final delay = reconnect.delayBefore(_attempt);
    if (delay == null) {
      _setStatus(
        GrSocketStatus(
          GrSocketState.disconnected,
          attempt: _attempt - 1,
          error: error,
        ),
      );
      return;
    }
    _emitTrace(TraceDirection.internal, 'reconnectScheduled', {
      'attempt': _attempt,
      'delayMs': delay.inMilliseconds,
    });
    _setStatus(
      GrSocketStatus(
        GrSocketState.reconnectWaiting,
        attempt: _attempt,
        error: error,
      ),
    );
    _retry = Timer(delay, () async {
      if (_closed) return;
      try {
        await _open();
      } catch (e) {
        if (!_closed) _scheduleReconnect(e);
      }
    });
  }

  void _setStatus(GrSocketStatus status) {
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }

  void _emitTrace(
    TraceDirection direction,
    String kind,
    Map<String, Object?> fields,
  ) => _trace?.call(
    TraceEvent(
      channel: TraceChannel.websocket,
      direction: direction,
      kind: kind,
      fields: fields,
    ),
  );

  /// Stops reconnecting, closes the socket (code 1000) and both streams.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _retry?.cancel();
    final ws = _socket;
    _socket = null;
    if (ws != null) {
      _emitTrace(TraceDirection.outbound, 'close', {
        'closeCode': WebSocketStatus.normalClosure,
      });
      await ws.close(WebSocketStatus.normalClosure);
    }
    await _sub?.cancel();
    _sub = null;
    _setStatus(const GrSocketStatus(GrSocketState.closed));
    await _events.close();
    await _statuses.close();
  }
}
