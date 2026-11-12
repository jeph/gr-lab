import 'dart:async';

import 'package:gr_protocol/gr_protocol.dart';

/// Wraps a [PhoneLocation] so every call, with its arguments, outcome and
/// duration, every position taken for a camera, every change of access and
/// every stop of the run reaches [TraceChannel.location]. The environment
/// applies it to whatever location service it is given (the device's
/// native one or a simulated phone's), so a log shows the same steps in
/// both.
///
/// The positions of the recorded history are never traced: [takeHistory]
/// records only how many it handed over.
final class TracingPhoneLocation implements PhoneLocation {
  /// Traces every call on the wrapped location service to the trace sink.
  new(this._inner, this._trace) {
    _accessChanges = _relayed(
      () => _inner.accessChanges,
      'accessChanged',
      (access) => access.toJson(),
    );
    _updates = _relayed(
      () => _inner.updates,
      'fix',
      (fix) => fix.toJson(),
      listening: 'updates',
    );
    _runStops = _relayed(() => _inner.runStops, 'runStopped', (_) => const {});
    _historyPending = _relayed(
      () => _inner.historyPending,
      'historyPending',
      (_) => const {},
    );
  }

  final PhoneLocation _inner;
  final TraceSink _trace;
  late final StreamController<LocationAccess> _accessChanges;
  late final StreamController<LocationFix> _updates;
  late final StreamController<void> _runStops;
  late final StreamController<void> _historyPending;

  @override
  Stream<LocationAccess> get accessChanges => _accessChanges.stream;

  @override
  Stream<LocationFix> get updates => _updates.stream;

  @override
  Stream<void> get runStops => _runStops.stream;

  @override
  Stream<void> get historyPending => _historyPending.stream;

  @override
  Future<LocationAccess> access() =>
      _traced('access', _inner.access, result: (access) => access.toJson());

  @override
  Future<LocationAccess> requestWhileInUse() => _traced(
    'requestWhileInUse',
    _inner.requestWhileInUse,
    result: (access) => access.toJson(),
  );

  @override
  Future<LocationAccess> requestAlways() => _traced(
    'requestAlways',
    _inner.requestAlways,
    result: (access) => access.toJson(),
  );

  @override
  Future<void> openSettings(LocationSettingsPage page) => _traced(
    'openSettings',
    () => _inner.openSettings(page),
    arguments: {'page': page.name},
  );

  @override
  Future<LocationFix?> current({required Duration timeout}) => _traced(
    'current',
    () => _inner.current(timeout: timeout),
    arguments: {'timeoutMs': timeout.inMilliseconds},
    result: (fix) => {'fix': fix?.toJson()},
  );

  @override
  Future<void> holdRun(LocationRunNotice notice, {required bool awake}) =>
      _traced(
        'holdRun',
        () => _inner.holdRun(notice, awake: awake),
        arguments: {...notice.toJson(), 'awake': awake},
      );

  @override
  Future<void> releaseRun() => _traced('releaseRun', _inner.releaseRun);

  @override
  Future<void> setHistory({required bool enabled}) => _traced(
    'setHistory',
    () => _inner.setHistory(enabled: enabled),
    arguments: {'enabled': enabled},
  );

  @override
  Future<List<LocationFix>> takeHistory() => _traced(
    'takeHistory',
    _inner.takeHistory,
    // Where the phone has been stays out of the log.
    result: (fixes) => {'count': fixes.length},
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

  /// A broadcast stream of [source]'s events, each recorded as [kind] with
  /// [fields]. One subscription to [source] while the stream has
  /// listeners, so an event is traced once however many listeners there
  /// are. With [listening], the first listener and the last cancel are
  /// recorded as `<listening>.start` and `<listening>.stop`: for the
  /// positions, they are when the phone starts and stops being located.
  StreamController<T> _relayed<T>(
    Stream<T> Function() source,
    String kind,
    Map<String, Object?> Function(T event) fields, {
    String? listening,
  }) {
    StreamSubscription<T>? inner;
    late final StreamController<T> controller;
    return controller = StreamController<T>.broadcast(
      onListen: () {
        if (listening != null) {
          _emit(TraceDirection.outbound, '$listening.start');
        }
        inner = source().listen(
          (event) {
            _emit(TraceDirection.inbound, kind, fields(event));
            controller.add(event);
          },
          onError: (Object error, StackTrace stack) {
            _emit(TraceDirection.inbound, '$kind.error', {'error': '$error'});
            controller.addError(error, stack);
          },
        );
      },
      onCancel: () {
        if (listening != null) {
          _emit(TraceDirection.outbound, '$listening.stop');
        }
        unawaited(inner?.cancel());
      },
    );
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
