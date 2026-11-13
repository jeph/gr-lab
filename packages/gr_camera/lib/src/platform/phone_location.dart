import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// [PhoneLocation] over the `io.jeph.grphoto/location` method channel,
/// served by this package's native code.
///
/// Android locates the phone with its `LocationManager` and keeps a run
/// going with a foreground service of the location type, whose notification
/// is the run's notice; iOS uses Core Location, and the app shows the notice
/// as a Live Activity. Only a Live Activity can outlive the app, so only iOS
/// ever has a Stop to hand over later ([takeRunStop]). Only Android has a
/// battery optimisation to be exempted from
/// ([backgroundUnrestricted]); iOS always answers that nothing restricts
/// the app, because it has no such setting. Both record the history
/// natively, so it goes on with no Flutter engine running, and hand it over
/// through [takeHistory].
///
/// Every line the native code logs and the native errors this class turns
/// into an inert answer go to [TraceChannel.location]. Calls, their
/// outcomes and the positions taken are traced by the environment's
/// `TracingPhoneLocation`. The history's positions are traced by neither.
final class PlatformPhoneLocation implements PhoneLocation {
  /// A location service on the native method channel, logging to the
  /// trace sink.
  new({
    required this._trace,
    this._channel = const MethodChannel('io.jeph.grphoto/location'),
  }) {
    // The phone is located only while someone listens: the first listener
    // starts the native updates and the last one to cancel stops them.
    _updates = StreamController<LocationFix>.broadcast(
      onListen: () => unawaited(_invoke('startUpdates')),
      onCancel: () => unawaited(_invoke('stopUpdates')),
    );
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'fix':
          final fix = _fix(call.arguments);
          if (fix == null) {
            _emit(TraceDirection.inbound, 'native.fix.unreadable', {
              'arguments': '${call.arguments}',
            });
          } else {
            _updates.add(fix);
          }
        case 'accessChanged':
          _accessChanges.add(_access(call.arguments));
        case 'runStopped':
          _runStops.add(null);
        case 'runStopPending':
          _runStopPending.add(null);
        case 'historyPending':
          _historyPending.add(null);
        case 'log':
          _emit(TraceDirection.internal, 'native', {'message': call.arguments});
      }
    });
  }

  final TraceSink _trace;
  final MethodChannel _channel;
  late final StreamController<LocationFix> _updates;
  final _accessChanges = StreamController<LocationAccess>.broadcast();
  final _runStops = StreamController<void>.broadcast();
  final _runStopPending = StreamController<void>.broadcast();
  final _historyPending = StreamController<void>.broadcast();

  @override
  Stream<LocationAccess> get accessChanges => _accessChanges.stream;

  @override
  Stream<LocationFix> get updates => _updates.stream;

  @override
  Stream<void> get runStops => _runStops.stream;

  @override
  Stream<void> get runStopPending => _runStopPending.stream;

  @override
  Stream<void> get historyPending => _historyPending.stream;

  @override
  Future<LocationAccess> access() async => _access(await _invoke('access'));

  @override
  Future<LocationAccess> requestWhileInUse() async =>
      _access(await _invoke('requestWhileInUse'));

  @override
  Future<LocationAccess> requestAlways() async =>
      _access(await _invoke('requestAlways'));

  @override
  Future<void> openSettings(LocationSettingsPage page) =>
      _invoke('openSettings', {'page': page.name});

  @override
  Future<LocationFix?> current({required Duration timeout}) async {
    // A non-positive window still gets one native attempt rather than an
    // argument error.
    final ms = timeout.inMilliseconds < 1 ? 1 : timeout.inMilliseconds;
    return _fix(await _invoke('current', {'timeoutMs': ms}));
  }

  @override
  Future<void> holdRun(LocationRunNotice notice, {required bool awake}) async {
    try {
      await _channel.invokeMethod<void>('holdRun', {
        ...notice.toJson(),
        'awake': awake,
      });
    } on PlatformException catch (e) {
      throw LocationRunException(switch (e.code) {
        'background' => LocationRunRefusal.background,
        'noAccess' => LocationRunRefusal.noAccess,
        _ => LocationRunRefusal.unsupported,
      }, e.message);
    } on MissingPluginException {
      throw const LocationRunException(LocationRunRefusal.unsupported);
    }
  }

  @override
  Future<void> releaseRun() => _invoke('releaseRun');

  @override
  Future<String?> takeRunStop() async {
    final reply = await _invoke('takeRunStop');
    return reply is String ? reply : null;
  }

  // Without an answer (a native error, or no native code) there is nothing
  // the user could allow.
  @override
  Future<bool> backgroundUnrestricted() async =>
      await _invoke('backgroundUnrestricted') != false;

  @override
  Future<bool> requestBackgroundUnrestricted() async =>
      await _invoke('requestBackgroundUnrestricted') != false;

  @override
  Future<void> setHistory({required bool enabled}) =>
      _invoke('setHistory', {'enabled': enabled});

  @override
  Future<List<LocationFix>> takeHistory() async {
    final reply = await _invoke('takeHistory');
    if (reply is! List<Object?>) return const [];
    return [for (final entry in reply) ?_fix(entry)];
  }

  /// Turns the native location code's logging on or off: its logcat or
  /// unified log lines and the `log` lines it sends here. It follows the
  /// app's debug logging setting and is off until this is called.
  Future<void> setLogging({required bool enabled}) async {
    try {
      await _channel.invokeMethod<void>('setLogging', {'enabled': enabled});
    } on MissingPluginException {
      // No native code, so nothing to log.
    }
  }

  /// Calls the native [method]. A native error, or no native code at all,
  /// is traced and answered with null, which every caller reads as its
  /// inert answer (no access, no position, nothing done).
  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (e) {
      _emit(TraceDirection.inbound, 'native.$method.error', {
        'code': e.code,
        'message': e.message,
      });
    } on MissingPluginException {
      _emit(TraceDirection.inbound, 'native.$method.error', {
        'code': 'unsupported',
      });
    }
    return null;
  }

  static LocationAccess _access(Object? reply) => reply is Map<Object?, Object?>
      ? LocationAccess.fromJson(reply)
      : LocationAccess.none;

  static LocationFix? _fix(Object? reply) =>
      reply is Map<Object?, Object?> ? LocationFix.fromJson(reply) : null;

  void _emit(
    TraceDirection direction,
    String kind, [
    Map<String, Object?> fields = const {},
  ]) => _trace(
    TraceEvent(
      channel: TraceChannel.location,
      direction: direction,
      kind: kind,
      fields: fields,
    ),
  );
}
