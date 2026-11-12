import 'dart:async';

import 'package:gr_protocol/gr_protocol.dart';

/// A scripted phone for tests and the demo: its location access, its runs
/// and the fixes it delivers are whatever the caller sets and calls.
///
/// With a `source` it also delivers fixes by itself: one at once on
/// entering [LocationMode.precise] and one every [interval] while the run
/// stays there.
final class FakePhoneLocation implements PhoneLocation {
  /// A phone that allows [access] (precise unless given). [source], when
  /// given, makes the fix for a time (UTC) while a run is in
  /// [LocationMode.precise].
  new({
    LocationAccess access = LocationAccess.precise,
    this.accessAfterRequest,
    this.source,
  }) : currentAccess = access;

  /// What [access] answers. Setting it tells nobody; [changeAccess] also
  /// reports the change during a run.
  LocationAccess currentAccess;

  /// What [requestAccess] changes [currentAccess] to; null leaves it as it
  /// is, as when the user dismisses the question or the system does not
  /// ask.
  LocationAccess? accessAfterRequest;

  /// When set, [start] throws it: [LocationStartFailure.background] is a
  /// run the system refuses because the app is not in front.
  LocationStartFailure? startFailure;

  /// Calls of [requestAccess].
  int requests = 0;

  /// Calls of [openSettings].
  int settingsOpened = 0;

  /// Runs begun by [start]. A [start] that only changes the run under way
  /// does not count.
  int starts = 0;

  /// Runs ended by [stop]. A [stop] outside a run and [tapStop] do not
  /// count.
  int stops = 0;

  /// Makes the fix for a time (UTC) while a run is in
  /// [LocationMode.precise]; null leaves the fixes to [emit].
  final PhoneFix Function(DateTime now)? source;
  final _fixes = StreamController<PhoneFix>.broadcast();
  final _stopRequests = StreamController<void>.broadcast();
  final _accessChanges = StreamController<LocationAccess>.broadcast();
  bool _running = false;
  LocationMode _mode = LocationMode.idle;
  LocationNotice? _notice;
  Duration? _interval;
  Timer? _sourceTimer;

  /// A run is under way.
  bool get running => _running;

  /// The mode of the run; [LocationMode.idle] outside one.
  LocationMode get mode => _mode;

  /// The texts the last [start] gave the run; null outside one.
  LocationNotice? get notice => _notice;

  /// The time between fixes the last [start] gave the run; null outside
  /// one.
  Duration? get interval => _interval;

  @override
  Future<LocationAccess> access() async => currentAccess;

  @override
  Future<LocationAccess> requestAccess() async {
    requests++;
    return currentAccess = accessAfterRequest ?? currentAccess;
  }

  @override
  Future<void> openSettings() async {
    settingsOpened++;
  }

  /// Throws a [LocationStartException]: with [startFailure] when one is
  /// set, otherwise with [LocationStartFailure.denied] unless
  /// [currentAccess] is precise or approximate.
  @override
  Future<void> start({
    required LocationNotice notice,
    required Duration interval,
  }) async {
    if (startFailure case final failure?) {
      throw LocationStartException(failure, 'scripted');
    }
    if (currentAccess != LocationAccess.precise &&
        currentAccess != LocationAccess.approximate) {
      throw LocationStartException(
        LocationStartFailure.denied,
        'access is ${currentAccess.name}',
      );
    }
    final intervalChanged = interval != _interval;
    _notice = notice;
    _interval = interval;
    if (!_running) {
      _running = true;
      _mode = LocationMode.idle;
      starts++;
      return;
    }
    if (intervalChanged && _sourceTimer != null) _restartSourceTimer();
  }

  /// Throws a [LocationStartException] with [LocationStartFailure.failed]
  /// outside a run.
  @override
  Future<void> setMode(LocationMode mode) async {
    if (!_running) {
      throw const LocationStartException(
        LocationStartFailure.failed,
        'no run under way',
      );
    }
    if (mode == _mode) return;
    _mode = mode;
    final source = this.source;
    if (mode == LocationMode.idle || source == null) {
      _stopSourceTimer();
      return;
    }
    emit(source(DateTime.now().toUtc()));
    _restartSourceTimer();
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _endRun();
    stops++;
  }

  @override
  Stream<PhoneFix> get fixes => _fixes.stream;

  @override
  Stream<void> get stopRequests => _stopRequests.stream;

  @override
  Stream<LocationAccess> get accessChanges => _accessChanges.stream;

  /// The phone has a position: delivered on [fixes] during a run, in
  /// either mode, and dropped outside one.
  void emit(PhoneFix fix) {
    if (_running) _fixes.add(fix);
  }

  /// The user ends the run from outside the app (the notification's
  /// button): the run is over, then [stopRequests] says so. Does nothing
  /// outside a run.
  void tapStop() {
    if (!_running) return;
    _endRun();
    _stopRequests.add(null);
  }

  /// The phone's answer becomes [to] (location turned off, the permission
  /// changed in the system settings); during a run [accessChanges] reports
  /// it. The run goes on: ending it is the caller's decision.
  void changeAccess(LocationAccess to) {
    currentAccess = to;
    if (_running) _accessChanges.add(to);
  }

  /// Ends the run, if any, and closes the streams.
  void dispose() {
    _endRun();
    unawaited(_fixes.close());
    unawaited(_stopRequests.close());
    unawaited(_accessChanges.close());
  }

  void _endRun() {
    _stopSourceTimer();
    _running = false;
    _mode = LocationMode.idle;
    _notice = null;
    _interval = null;
  }

  /// One fix from the source every [interval] from now.
  void _restartSourceTimer() {
    final source = this.source;
    final interval = _interval;
    _stopSourceTimer();
    if (source == null || interval == null) return;
    _sourceTimer = Timer.periodic(
      interval,
      (_) => emit(source(DateTime.now().toUtc())),
    );
  }

  void _stopSourceTimer() {
    _sourceTimer?.cancel();
    _sourceTimer = null;
  }
}
