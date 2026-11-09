import 'dart:async';

import 'package:gr_protocol/gr_protocol.dart';

/// Wraps a [WifiNetworkControl] so every call, with its arguments and
/// outcome, and every reported loss reaches [TraceChannel.wifi]. The
/// environment applies it to whatever control it is given (the device's
/// native one or a simulated camera's), so a log shows the same Wi-Fi steps
/// in both.
///
/// The join arguments include the camera's passphrase: the log is meant to
/// show exactly what was asked of the OS.
final class TracingWifiControl implements WifiNetworkControl {
  /// Traces every call on the wrapped control to the trace sink.
  new(this._inner, this._trace) {
    // One subscription to the inner stream while [lost] has listeners, so
    // a loss is traced once however many listeners there are.
    StreamSubscription<void>? inner;
    _lost = StreamController<void>.broadcast(
      onListen: () => inner = _inner.lost.listen((_) {
        _emit(TraceDirection.inbound, 'lost');
        _lost.add(null);
      }),
      onCancel: () => inner?.cancel(),
    );
  }

  final WifiNetworkControl _inner;
  final TraceSink _trace;
  late final StreamController<void> _lost;

  @override
  Stream<void> get lost => _lost.stream;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    _emit(TraceDirection.outbound, 'join', {
      'ssid': ssid,
      'passphrase': passphrase,
      'security': security.name,
      'timeoutMs': timeout.inMilliseconds,
      'approved': approved,
    });
    final watch = Stopwatch()..start();
    try {
      await _inner.join(
        ssid: ssid,
        passphrase: passphrase,
        security: security,
        timeout: timeout,
        approved: approved,
      );
    } catch (e) {
      _failed('join', e, watch);
      rethrow;
    }
    _emit(TraceDirection.inbound, 'join.done', {
      'ssid': ssid,
      'ms': watch.elapsedMilliseconds,
    });
  }

  @override
  Future<String?> currentSsid() async {
    _emit(TraceDirection.outbound, 'currentSsid');
    final watch = Stopwatch()..start();
    try {
      final ssid = await _inner.currentSsid();
      _emit(TraceDirection.inbound, 'currentSsid.done', {
        'ssid': ssid,
        'ms': watch.elapsedMilliseconds,
      });
      return ssid;
    } catch (e) {
      _failed('currentSsid', e, watch);
      rethrow;
    }
  }

  @override
  Future<void> leave() async {
    _emit(TraceDirection.outbound, 'leave');
    final watch = Stopwatch()..start();
    try {
      await _inner.leave();
    } catch (e) {
      _failed('leave', e, watch);
      rethrow;
    }
    _emit(TraceDirection.inbound, 'leave.done', {
      'ms': watch.elapsedMilliseconds,
    });
  }

  void _failed(String call, Object error, Stopwatch watch) =>
      _emit(TraceDirection.inbound, '$call.error', {
        'type': error.runtimeType.toString(),
        'error': '$error',
        'ms': watch.elapsedMilliseconds,
      });

  void _emit(
    TraceDirection direction,
    String kind, [
    Map<String, Object?> fields = const {},
  ]) => _trace(
    TraceEvent(
      channel: TraceChannel.wifi,
      direction: direction,
      kind: kind,
      fields: fields,
    ),
  );
}
