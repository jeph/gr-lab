import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// [PhoneLocation] over the `io.jeph.grphoto/location` method channel, served
/// by this package's native code.
///
/// Android reads fixes from the fused provider (GPS where the phone has
/// none) and holds a run with a foreground service of the location type,
/// whose notification is the [LocationNotice]. iOS keeps Core Location
/// updates going in the background and shows its own indicator instead of
/// a notification, so nothing there can ask for a stop
/// ([stopRequests] never emits) and a run never fails for beginning in the
/// background. Neither asks for location "all the time".
///
/// Every line the native code logs goes to [TraceChannel.location]. Calls,
/// fixes and events are traced by the environment's
/// [TracingPhoneLocation].
final class PlatformPhoneLocation implements PhoneLocation {
  /// A phone location on the native method channel, logging to the trace
  /// sink.
  new({
    required this._trace,
    this._channel = const MethodChannel('io.jeph.grphoto/location'),
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'fix':
          final fix = _fix(call.arguments);
          if (fix != null) _fixes.add(fix);
        case 'stopRequested':
          _stopRequests.add(null);
        case 'accessChanged':
          _accessChanges.add(_access(call.arguments));
        case 'log':
          _trace(
            TraceEvent(
              channel: TraceChannel.location,
              direction: TraceDirection.internal,
              kind: 'native',
              fields: {'message': call.arguments},
            ),
          );
      }
    });
  }

  final TraceSink _trace;
  final MethodChannel _channel;
  final _fixes = StreamController<PhoneFix>.broadcast();
  final _stopRequests = StreamController<void>.broadcast();
  final _accessChanges = StreamController<LocationAccess>.broadcast();

  @override
  Stream<PhoneFix> get fixes => _fixes.stream;

  @override
  Stream<void> get stopRequests => _stopRequests.stream;

  @override
  Stream<LocationAccess> get accessChanges => _accessChanges.stream;

  @override
  Future<LocationAccess> access() => _readAccess('access');

  @override
  Future<LocationAccess> requestAccess() => _readAccess('requestAccess');

  Future<LocationAccess> _readAccess(String method) async {
    try {
      return _access(await _channel.invokeMethod<String>(method));
    } on MissingPluginException {
      return LocationAccess.unsupported;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // No native code, so no settings to open.
    }
  }

  @override
  Future<void> start({
    required LocationNotice notice,
    required Duration interval,
  }) => _run(
    () => _channel.invokeMethod<void>('start', {
      ...notice.toJson(),
      'intervalMs': interval.inMilliseconds,
    }),
  );

  @override
  Future<void> setMode(LocationMode mode) =>
      _run(() => _channel.invokeMethod<void>('setMode', mode.name));

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No native code, so no run to end.
    }
  }

  /// Turns the native location code's logging on or off: its logcat or
  /// unified log lines and the `log` lines it sends here. It follows the
  /// app's debug logging setting and is off until this is called.
  Future<void> setLogging({required bool enabled}) async {
    try {
      await _channel.invokeMethod<void>('setLogging', enabled);
    } on MissingPluginException {
      // No native code, so nothing to log.
    }
  }

  Future<void> _run(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException catch (e) {
      throw LocationStartException(switch (e.code) {
        'background' => LocationStartFailure.background,
        'denied' => LocationStartFailure.denied,
        _ => LocationStartFailure.failed,
      }, '${e.code}: ${e.message ?? ''}');
    } on MissingPluginException {
      throw const LocationStartException(
        LocationStartFailure.failed,
        'location is not available on this platform',
      );
    }
  }

  /// A word this build does not know is no permission to locate.
  static LocationAccess _access(Object? name) {
    for (final access in LocationAccess.values) {
      if (access.name == name) return access;
    }
    return LocationAccess.blocked;
  }

  /// The native side's fix; null when it lacks what a fix must have.
  static PhoneFix? _fix(Object? arguments) {
    if (arguments is! Map<Object?, Object?>) return null;
    final latitude = arguments['latitude'];
    final longitude = arguments['longitude'];
    final accuracy = arguments['accuracy'];
    final timeMs = arguments['timeMs'];
    if (latitude is! double ||
        longitude is! double ||
        accuracy is! double ||
        timeMs is! int) {
      return null;
    }
    final altitude = arguments['altitude'];
    final speed = arguments['speed'];
    return PhoneFix(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      time: DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true),
      altitude: altitude is double ? altitude : null,
      speed: speed is double ? speed : null,
    );
  }
}

/// Wraps a [PhoneLocation] so every call with its arguments and outcome,
/// every fix and every event reaches [TraceChannel.location]. The
/// environment applies it to whatever phone location it is given (the
/// device's native one or a scripted one), so a log shows the same steps in
/// both.
///
/// The log then holds where the phone was while a camera was on: it is
/// meant to show exactly what was sent to the camera.
final class TracingPhoneLocation implements PhoneLocation {
  /// Traces every call on the wrapped phone location to the trace sink.
  new(this._inner, this._trace);

  final PhoneLocation _inner;
  final TraceSink _trace;

  @override
  late final Stream<PhoneFix> fixes = _traced(
    _inner.fixes,
    'fix',
    (fix) => fix.toJson(),
  );

  @override
  late final Stream<void> stopRequests = _traced(
    _inner.stopRequests,
    'stopRequested',
    (_) => const {},
  );

  @override
  late final Stream<LocationAccess> accessChanges = _traced(
    _inner.accessChanges,
    'accessChanged',
    (access) => {'access': access.name},
  );

  @override
  Future<LocationAccess> access() =>
      _call('access', const {}, _inner.access, _accessFields);

  @override
  Future<LocationAccess> requestAccess() =>
      _call('requestAccess', const {}, _inner.requestAccess, _accessFields);

  @override
  Future<void> openSettings() =>
      _call('openSettings', const {}, _inner.openSettings);

  @override
  Future<void> start({
    required LocationNotice notice,
    required Duration interval,
  }) => _call('start', {
    ...notice.toJson(),
    'intervalMs': interval.inMilliseconds,
  }, () => _inner.start(notice: notice, interval: interval));

  @override
  Future<void> setMode(LocationMode mode) =>
      _call('setMode', {'mode': mode.name}, () => _inner.setMode(mode));

  @override
  Future<void> stop() => _call('stop', const {}, _inner.stop);

  static Map<String, Object?> _accessFields(LocationAccess access) => {
    'access': access.name,
  };

  Future<T> _call<T>(
    String kind,
    Map<String, Object?> arguments,
    Future<T> Function() call, [
    Map<String, Object?> Function(T result)? describe,
  ]) async {
    _emit(TraceDirection.outbound, kind, arguments);
    final watch = Stopwatch()..start();
    final T result;
    try {
      result = await call();
    } catch (e) {
      _emit(TraceDirection.inbound, '$kind.error', {
        'error': '$e',
        'ms': watch.elapsedMilliseconds,
      });
      rethrow;
    }
    _emit(TraceDirection.inbound, '$kind.done', {
      ...?describe?.call(result),
      'ms': watch.elapsedMilliseconds,
    });
    return result;
  }

  /// One subscription to [source] while the stream has listeners, so an
  /// event is traced once however many listeners there are.
  Stream<T> _traced<T>(
    Stream<T> source,
    String kind,
    Map<String, Object?> Function(T event) describe,
  ) {
    StreamSubscription<T>? inner;
    late final StreamController<T> controller;
    controller = StreamController<T>.broadcast(
      onListen: () => inner = source.listen((event) {
        _emit(TraceDirection.inbound, kind, describe(event));
        controller.add(event);
      }),
      onCancel: () => inner?.cancel(),
    );
    return controller.stream;
  }

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

/// A phone with no location code: desktop builds and tests that do not
/// script one.
final class NoPhoneLocation implements PhoneLocation {
  /// The phone location of a platform that has none.
  const new();

  @override
  Future<LocationAccess> access() async => LocationAccess.unsupported;

  @override
  Future<LocationAccess> requestAccess() async => LocationAccess.unsupported;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> start({
    required LocationNotice notice,
    required Duration interval,
  }) => throw const LocationStartException(LocationStartFailure.failed);

  @override
  Future<void> setMode(LocationMode mode) =>
      throw const LocationStartException(LocationStartFailure.failed);

  @override
  Future<void> stop() async {}

  @override
  Stream<PhoneFix> get fixes => const Stream.empty();

  @override
  Stream<void> get stopRequests => const Stream.empty();

  @override
  Stream<LocationAccess> get accessChanges => const Stream.empty();
}
