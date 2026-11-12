import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// [PowerOnWatch] over the `io.jeph.grphoto/watch` method channel, served
/// by this package's native code.
///
/// Android watches through a companion device association, which also lets
/// the app start from the background when a camera is seen; iOS scans in
/// the background for the service a camera advertises while it is on. Both
/// keep the watched cameras natively, so the watch goes on with no Flutter
/// engine running.
///
/// Every line the native code logs and the native errors this class turns
/// into an inert answer go to [TraceChannel.ble]: these are Bluetooth
/// events. Calls, their outcomes and sightings are traced by the
/// environment's [TracingPowerOnWatch].
final class PlatformPowerOnWatch implements PowerOnWatch {
  /// A watch on the native method channel, logging to the trace sink.
  new({
    required this._trace,
    this._channel = const MethodChannel('io.jeph.grphoto/watch'),
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'seenOn':
          final arguments = call.arguments;
          final deviceId = arguments is Map<Object?, Object?>
              ? arguments['deviceId']
              : null;
          if (deviceId is String) {
            _sightings.add(deviceId);
          } else {
            _emit(TraceDirection.inbound, 'native.seenOn.unreadable', {
              'arguments': '$arguments',
            });
          }
        case 'log':
          _emit(TraceDirection.internal, 'native', {'message': call.arguments});
      }
    });
  }

  final TraceSink _trace;
  final MethodChannel _channel;
  final _sightings = StreamController<String>.broadcast();

  @override
  Stream<String> get sightings => _sightings.stream;

  @override
  Future<bool> supported() async => await _invoke('supported') == true;

  @override
  Future<bool> associated(String deviceId) async =>
      await _invoke('associated', {'deviceId': deviceId}) == true;

  @override
  Future<bool> associate(WatchedCamera camera) async =>
      await _invoke('associate', camera.toJson()) == true;

  @override
  Future<void> watch(List<WatchedCamera> cameras) => _invoke('watch', {
    'cameras': [for (final camera in cameras) camera.toJson()],
  });

  @override
  Future<List<String>> takeLaunchSightings() async {
    final reply = await _invoke('takeLaunchSightings');
    if (reply is! List<Object?>) return const [];
    return reply.whereType<String>().toList();
  }

  /// Turns the native watch code's logging on or off: its logcat or
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
  /// inert answer (not supported, not associated, nothing seen).
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

  void _emit(
    TraceDirection direction,
    String kind, [
    Map<String, Object?> fields = const {},
  ]) => _trace(_watchEvent(direction, kind, fields));
}

/// Wraps a [PowerOnWatch] so every call, with its arguments, outcome and
/// duration, and every sighting reaches [TraceChannel.ble] (kinds
/// `powerOnWatch.…`). The environment applies it to whatever watch it is
/// given (the device's native one or a simulated phone's), so a log shows
/// the same steps in both.
final class TracingPowerOnWatch implements PowerOnWatch {
  /// Traces every call on the wrapped watch to the trace sink.
  new(this._inner, this._trace) {
    // One subscription to the inner stream while [sightings] has
    // listeners, so a sighting is traced once however many listeners
    // there are.
    StreamSubscription<String>? inner;
    _sightings = StreamController<String>.broadcast(
      onListen: () => inner = _inner.sightings.listen((deviceId) {
        _emit(TraceDirection.inbound, 'seenOn', {'deviceId': deviceId});
        _sightings.add(deviceId);
      }),
      onCancel: () => inner?.cancel(),
    );
  }

  final PowerOnWatch _inner;
  final TraceSink _trace;
  late final StreamController<String> _sightings;

  @override
  Stream<String> get sightings => _sightings.stream;

  @override
  Future<bool> supported() => _traced(
    'supported',
    _inner.supported,
    result: (supported) => {'supported': supported},
  );

  @override
  Future<bool> associated(String deviceId) => _traced(
    'associated',
    () => _inner.associated(deviceId),
    arguments: {'deviceId': deviceId},
    result: (associated) => {'associated': associated},
  );

  @override
  Future<bool> associate(WatchedCamera camera) => _traced(
    'associate',
    () => _inner.associate(camera),
    arguments: camera.toJson(),
    result: (associated) => {'associated': associated},
  );

  @override
  Future<void> watch(List<WatchedCamera> cameras) => _traced(
    'watch',
    () => _inner.watch(cameras),
    arguments: {
      'cameras': [for (final camera in cameras) camera.toJson()],
    },
  );

  @override
  Future<List<String>> takeLaunchSightings() => _traced(
    'takeLaunchSightings',
    _inner.takeLaunchSightings,
    result: (deviceIds) => {'deviceIds': deviceIds},
  );

  /// Runs [run], recording [call] with [arguments] before it and its
  /// outcome ([result]'s fields, or the error) and duration after it.
  Future<T> _traced<T>(
    String call,
    Future<T> Function() run, {
    Map<String, Object?> arguments = const {},
    Map<String, Object?> Function(T value)? result,
  }) async {
    _emit(TraceDirection.outbound, call, arguments);
    final watch = Stopwatch()..start();
    final T value;
    try {
      value = await run();
    } catch (e) {
      _emit(TraceDirection.inbound, '$call.error', {
        'type': e.runtimeType.toString(),
        'error': '$e',
        'ms': watch.elapsedMilliseconds,
      });
      rethrow;
    }
    _emit(TraceDirection.inbound, '$call.done', {
      ...?result?.call(value),
      'ms': watch.elapsedMilliseconds,
    });
    return value;
  }

  void _emit(
    TraceDirection direction,
    String kind, [
    Map<String, Object?> fields = const {},
  ]) => _trace(_watchEvent(direction, kind, fields));
}

/// One power-on watch step on [TraceChannel.ble], its kind prefixed so it
/// stands apart from the GATT traffic there.
TraceEvent _watchEvent(
  TraceDirection direction,
  String kind,
  Map<String, Object?> fields,
) => TraceEvent(
  channel: TraceChannel.ble,
  direction: direction,
  kind: 'powerOnWatch.$kind',
  fields: fields,
);
