import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gr_protocol/src/camera_address.dart';
import 'package:gr_protocol/src/http/json.dart';
import 'package:gr_protocol/src/http/models.dart';
import 'package:gr_protocol/src/http/request.dart';
import 'package:gr_protocol/src/trace.dart';

/// One message from `ws://<host>/v1/changes`
/// (research/protocol/http-api.md §5, research/protocol/remote-shooting.md §2.3).
///
/// GR WORLD only knows `storage|battery|camera`; Image Sync also dispatches
/// `cameraDirect`, `lens`, `capture` and `transfer`. Whether GR IV emits the
/// Image Sync payloads is \[unknown\] (remote-shooting.md §8): the key strings
/// exist in GR IV webapid. Parsing never throws.
sealed class GrChangeEvent {
  new(this.raw, this.receivedAt);

  /// Parses a WebSocket message (text or UTF-8 bytes).
  factory parse(Object? message, {DateTime? receivedAt}) {
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

  /// Local time the message arrived (not a camera timestamp).
  final DateTime receivedAt;

  /// Typed, non-throwing accessors over [raw].
  JsonFields get fields => JsonFields(raw);

  /// `changed`, falling back to Image Sync's `change` alias.
  String? get changed => fields.string('changed') ?? fields.string('change');

  /// Camera's result code in the message; 200 means success.
  int? get errCode => fields.integer('errCode');

  /// GR WORLD ignores messages whose errCode is not 200 (http-api.md §5).
  bool get ok => errCode == 200;

  /// Trace/log form: arrival time, [changed] and the raw message.
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
  /// Wraps a parsed `storage` message.
  new(super.raw, super.receivedAt);

  /// What happened to the file; `add` is the only value Image Sync acts on.
  String? get action => fields.string('action');

  /// Camera path of the affected file, e.g. `100RICOH/R0000001.DNG`.
  String? get filepath => fields.string('filepath');

  /// Storage the file is on, as the camera names it.
  String? get storage => fields.string('storage');

  /// Capture that produced the file; `"0"` when not a remote capture.
  String? get captureId => fields.string('captureId');

  /// [filepath] parsed into a photo path, or `null` when absent or malformed.
  GrPhotoPath? get path =>
      filepath == null ? null : GrPhotoPath.tryParseCamera(filepath!);
}

/// `changed:"battery"`: both apps re-read status/props.
final class GrBatteryChange extends GrChangeEvent {
  /// Wraps a parsed `battery` message.
  new(super.raw, super.receivedAt);
}

/// `changed:"camera"`: settings changed; re-read `/v1/props`.
final class GrCameraChange extends GrChangeEvent {
  /// Wraps a parsed `camera` message.
  new(super.raw, super.receivedAt);
}

/// `changed:"cameraDirect"`: capture state and how the camera is held
/// (remote-shooting.md §2.3 table). The GR IV sends it when one of them
/// changes (§1.5).
final class GrCameraDirectChange extends GrChangeEvent {
  /// Wraps a parsed `cameraDirect` message.
  new(super.raw, super.receivedAt);

  /// Still capture state, e.g. `idle` or `continuous`; other values
  /// unknown.
  String? get stateStill => fields.string('stateStill');

  /// Movie capture state; `idle` when no movie is recording.
  String? get stateMovie => fields.string('stateMovie');

  /// `idle|busy2s|busy10s|busy12s|time`.
  String? get countDown => fields.string('countDown');

  /// Whether the camera is taking a picture right now.
  bool? get capturing => fields.boolean('capturing');

  /// Shots taken so far in the current drive sequence; exact meaning
  /// unknown.
  int? get shotsCurrent => fields.integer('shotsCurrent');

  /// Shots the current drive sequence will take; exact meaning unknown.
  int? get shotsTotal => fields.integer('shotsTotal');

  /// Drive mode, e.g. `single`, `continuous`, `self2s` (the `/v1/props`
  /// `shootMode` values).
  String? get shootMode => fields.string('shootMode');

  /// How the camera is held; null when absent or not a known value.
  GrCameraOrientation? get cameraOrientation =>
      GrCameraOrientation.parse(fields.string('cameraOrientation'));

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
  /// Wraps a parsed `lens` message.
  new(super.raw, super.receivedAt);

  /// Capture or focus request this result belongs to.
  String? get captureId => fields.string('captureId');

  /// Whether the autofocus locked.
  bool? get focused => fields.boolean('focused');
}

/// `changed:"capture"`: the capture with `captureId` finished.
final class GrCaptureChange extends GrChangeEvent {
  /// Wraps a parsed `capture` message.
  new(super.raw, super.receivedAt);

  /// Capture that finished, as returned by the shoot request.
  String? get captureId => fields.string('captureId');

  /// Outcome flag; Image Sync does not read it, meaning unknown.
  bool? get result => fields.boolean('result');
}

/// `changed:"transfer"` (connection-imagesync.md §4): `action` in
/// `add|state|delete|format`; `state` `untransferred|transferred`.
final class GrTransferChange extends GrChangeEvent {
  /// Wraps a parsed `transfer` message.
  new(super.raw, super.receivedAt);

  /// `add`, `state`, `delete` or `format`.
  String? get action => fields.string('action');

  /// Storage of the affected file, as the camera names it.
  String? get storage => fields.string('storage');

  /// Transfer-list index of the file (`/v1/transfers` `index`).
  int? get index => fields.integer('index');

  /// Camera path of the affected file.
  String? get filepath => fields.string('filepath');

  /// File size in bytes, sent by the camera as a string.
  String? get size => fields.string('size');

  /// `untransferred` or `transferred`.
  String? get state => fields.string('state');
}

/// Any other `changed` value (or none); kept raw.
final class GrUnknownChange extends GrChangeEvent {
  /// Wraps a message with an unrecognised or missing `changed` key.
  new(super.raw, super.receivedAt);
}

/// A message that is not a JSON object.
final class GrUnparsedChange extends GrChangeEvent {
  /// Keeps the undecodable [text] and why it failed to parse.
  new(this.text, this.issue, DateTime receivedAt) : super(const {}, receivedAt);

  /// The message as received, decoded as UTF-8.
  final String text;

  /// Why the message is not a JSON object.
  final String issue;

  @override
  Map<String, Object?> toJson() => {
    'receivedAt': receivedAt.toIso8601String(),
    'unparsed': text,
    'issue': issue,
  };
}

/// What [GrChangesSocket] does after its socket drops or an open fails.
sealed class GrReconnectPolicy {
  const new();

  /// Delay before reconnect [attempt] (1-based), or `null` to give up.
  Duration? delayBefore(int attempt);
}

/// Never reconnect: GR WORLD's behaviour (http-api.md §5, "no automatic
/// reconnect").
final class GrNoReconnect extends GrReconnectPolicy {
  /// Never reconnects.
  const new();

  @override
  Duration? delayBefore(int attempt) => null;
}

/// Reopen at once, forever: Image Sync's `onFailure` behaviour
/// (connection-imagesync.md §2.2). A refused connection retries in a tight
/// loop throttled only by the connect timeout.
final class GrImmediateReconnect extends GrReconnectPolicy {
  /// Reconnects with no delay, without limit.
  const new();

  @override
  Duration? delayBefore(int attempt) => Duration.zero;
}

/// Capped backoff with a bounded number of attempts (the default; a design
/// choice following connection-lifecycle.md §9's "rejoin with backoff").
final class GrBackoffReconnect extends GrReconnectPolicy {
  /// Defaults: 0.5 s, 1 s, 2 s, 5 s, then 10 s between attempts, 10
  /// attempts at most.
  const new({
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

/// Lifecycle of a [GrChangesSocket].
enum GrSocketState {
  /// [GrChangesSocket.connect] has not been called yet.
  idle,

  /// A WebSocket handshake is in progress.
  connecting,

  /// The socket is up and delivering events.
  open,

  /// Dropped; a reconnect is scheduled.
  reconnectWaiting,

  /// Dropped and the policy gave up.
  disconnected,

  /// [GrChangesSocket.close] was called.
  closed,
}

/// A [GrSocketState] change, with the reconnect attempt and its cause.
final class GrSocketStatus {
  /// Status in [state]; [attempt] and [error] describe a reconnect.
  const new(this.state, {this.attempt = 0, this.error});

  /// Current lifecycle state.
  final GrSocketState state;

  /// Reconnect attempt number while reconnecting.
  final int attempt;

  /// Error that dropped the socket or failed the last attempt, if any.
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
  /// Socket for camera [host]; nothing connects until [connect].
  new(
    this.host, {
    this.port = grCameraHttpPort,
    HttpClient? httpClient,
    this.connectTimeout = const Duration(seconds: 7),
    this.reconnect = const GrBackoffReconnect(),
    this._trace,
    DateTime Function()? clock,
  }) : _http = httpClient,
       _now = clock ?? DateTime.now;

  /// Camera address, [grCameraHost] on the camera's own access point.
  final String host;

  /// HTTP port of the camera's web API, [grCameraHttpPort] on a camera.
  final int port;

  /// Image Sync uses 7 s (connection-imagesync.md §2.2).
  final Duration connectTimeout;

  /// What to do after the socket drops or an open fails.
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

  /// The open in progress; [connect] and a reconnect share it, so only one
  /// socket is ever being opened or open.
  Future<void>? _opening;
  Timer? _retry;
  Object? _lastError;
  int _attempt = 0;
  bool _closed = false;
  GrSocketStatus _status = const GrSocketStatus(GrSocketState.idle);

  /// `ws://<host>:<port>/v1/changes`.
  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: '/v1/changes');

  /// Every message from the camera, across reconnects (broadcast).
  Stream<GrChangeEvent> get events => _events.stream;

  /// Every [status] change (broadcast).
  Stream<GrSocketStatus> get statuses => _statuses.stream;

  /// Current lifecycle state.
  GrSocketStatus get status => _status;

  /// Opens the socket, or joins the open already in progress; a reconnect
  /// waiting to run is dropped in favour of this open. Throws the handshake
  /// failure (or [TimeoutException]) of the attempt, after which the
  /// reconnect policy retries as after a drop: Image Sync reopens the
  /// channel on any failure (connection-imagesync.md §2.2), so a refused
  /// first upgrade is not final.
  Future<void> connect() async {
    if (_closed) throw StateError('GrChangesSocket is closed');
    if (_socket != null) return;
    _retry?.cancel();
    _retry = null;
    await (_opening ??= _openOrRetry());
  }

  /// The first event matching [test] within [timeout], or `null`. Subscribe
  /// before triggering the request whose event you expect.
  Future<T?> waitFor<T extends GrChangeEvent>(
    bool Function(T event) test, {
    required Duration timeout,
  }) async {
    try {
      final event = await events
          .where((e) => e is T && test(e))
          .cast<T?>()
          .firstWhere((_) => true, orElse: () => null)
          .timeout(timeout);
      return event;
    } on TimeoutException {
      return null;
    }
  }

  /// One open ([_opening] while it runs); a failure goes to the reconnect
  /// policy.
  Future<void> _openOrRetry() async {
    try {
      await _open();
    } on Object catch (e) {
      if (!_closed) _scheduleReconnect(e);
      rethrow;
    } finally {
      _opening = null;
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
        if (identical(_socket, ws)) _lastError = error;
        _emitTrace(TraceDirection.internal, 'error', {'error': '$error'});
      },
      onDone: () => _onDone(ws),
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

  /// [ws] closed. Only the current socket's end clears it and reconnects;
  /// one [close] already let go of is just traced.
  void _onDone(WebSocket ws) {
    _emitTrace(TraceDirection.inbound, 'closed', {
      'closeCode': ws.closeCode,
      'closeReason': ws.closeReason,
    });
    if (!identical(_socket, ws)) return;
    _socket = null;
    _sub = null;
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
    _retry = Timer(delay, () {
      _retry = null;
      // An explicit connect may have opened the socket meanwhile.
      if (_closed || _socket != null || _opening != null) return;
      final opening = _opening = _openOrRetry();
      // A failure has gone to the policy already.
      unawaited(opening.then<void>((_) {}, onError: (_) {}));
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
