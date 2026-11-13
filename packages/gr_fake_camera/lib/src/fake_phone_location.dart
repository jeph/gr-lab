import 'dart:async';

import 'package:gr_protocol/gr_protocol.dart';

/// A simulated phone's location service, scripted by a test: it has the
/// access the test gives it, reports the positions the test emits and
/// records what was asked of it (the run held for live geotagging and its
/// notices, settings pages opened, permission requests, the exemption from
/// the phone's background restrictions).
final class FakePhoneLocation implements PhoneLocation {
  /// A phone whose location may be used as [access] says; by default the
  /// user allowed precise location while the app is in use.
  new({this._access = whileInUse});

  /// Precise location allowed while the app is in use, location on.
  static const whileInUse = LocationAccess(
    permission: LocationPermission.whileInUse,
    precise: true,
    serviceOn: true,
  );

  /// Precise location allowed at all times, location on.
  static const always = LocationAccess(
    permission: LocationPermission.always,
    precise: true,
    serviceOn: true,
  );

  LocationAccess _access;
  final _accessChanges = StreamController<LocationAccess>.broadcast();
  final _updates = StreamController<LocationFix>.broadcast();
  final _runStops = StreamController<void>.broadcast();
  final _runStopPending = StreamController<void>.broadcast();
  String? _runStop;
  final _historyPending = StreamController<void>.broadcast();
  final _settingsOpened = <LocationSettingsPage>[];
  final _runHolds = <({LocationRunNotice notice, bool awake})>[];
  final _history = <LocationFix>[];

  /// The waits of [current] calls that have no position to answer with.
  final _waits = <Timer, Completer<LocationFix?>>{};
  int _whileInUseRequests = 0;
  int _alwaysRequests = 0;
  int _currentRequests = 0;
  int _runReleases = 0;
  int _unrestrictedRequests = 0;
  bool _runHeld = false;
  bool _runShown = false;
  bool _historyEnabled = false;
  bool _closed = false;

  // --------------------------------------------------------------- script

  /// The access the phone gives now.
  LocationAccess get currentAccess => _access;

  /// The user or the system changes the access to [access], or the app
  /// comes back on screen with it unchanged: either way [accessChanges]
  /// emits it.
  void setAccess(LocationAccess access) {
    _access = access;
    _accessChanges.add(access);
  }

  /// The access [requestWhileInUse] leaves the phone with: the user's
  /// answer to the prompt. Null leaves it as it is (no prompt shown).
  LocationAccess? whileInUseAnswer;

  /// The access [requestAlways] leaves the phone with; null leaves it as
  /// it is.
  LocationAccess? alwaysAnswer;

  /// What [alwaysSettingsChoice] answers: the choice named on the settings
  /// page a phone opens for [requestAlways] (Android). Null for a phone
  /// that asks over the app (iOS).
  String? alwaysChoice;

  /// How often [requestWhileInUse] was called.
  int get whileInUseRequests => _whileInUseRequests;

  /// How often [requestAlways] was called.
  int get alwaysRequests => _alwaysRequests;

  /// Every settings page [openSettings] opened, in order.
  List<LocationSettingsPage> get settingsOpened =>
      List.unmodifiable(_settingsOpened);

  /// The phone is being located: [updates] has a listener.
  bool get locating => _updates.hasListener;

  /// The phone takes [fix]. It reaches [updates] only while the phone is
  /// being located ([locating]) and the access is usable, as on a phone.
  void emitFix(LocationFix fix) {
    if (locating && _access.usable) _updates.add(fix);
  }

  /// What [current] answers; null lets it run out its timeout and answer
  /// null. Unused while [onCurrent] is set.
  LocationFix? currentFix;

  /// Answers [current] instead of [currentFix], given its timeout.
  Future<LocationFix?> Function(Duration timeout)? onCurrent;

  /// How often [current] was called.
  int get currentRequests => _currentRequests;

  /// While set, [holdRun] is refused for this reason.
  LocationRunRefusal? runRefusal;

  /// A run is held: [holdRun] succeeded and [releaseRun] has not ended it,
  /// also after [pressStop].
  bool get runHeld => _runHeld;

  /// The notice of the run held now; null when none is held, and once
  /// [pressStop] took it away.
  LocationRunNotice? get runNotice => _runShown ? _runHolds.last.notice : null;

  /// Whether the run held now keeps the processor on; null when none is
  /// held.
  bool? get runAwake => _runHeld ? _runHolds.last.awake : null;

  /// Every [holdRun] that succeeded, in order: the first of a run, and
  /// each change of its notice or of `awake`.
  List<({LocationRunNotice notice, bool awake})> get runHolds =>
      List.unmodifiable(_runHolds);

  /// How often [releaseRun] ended a held run.
  int get runReleases => _runReleases;

  /// Called when [releaseRun] ends a held run, which is when a phone that
  /// keeps the app only for the run may end the app.
  void Function()? onRunReleased;

  /// Whether the phone leaves the app alone while it runs off screen
  /// ([backgroundUnrestricted]): true on a phone with nothing to allow.
  bool unrestricted = true;

  /// What [requestBackgroundUnrestricted] leaves [unrestricted] at: the
  /// user's answer. Null leaves it as it is.
  bool? unrestrictedAnswer;

  /// How often [requestBackgroundUnrestricted] was called.
  int get unrestrictedRequests => _unrestrictedRequests;

  /// The user presses Stop on the run's notice: the notice goes and
  /// [runStops] emits; the run stays held until [releaseRun]. Nothing
  /// happens when no notice is shown.
  void pressStop() {
    if (!_runShown) return;
    _runShown = false;
    _runStops.add(null);
  }

  /// The user presses Stop on a notice of the run [run] that outlived the
  /// app, or that the phone still shows after the run was released:
  /// [takeRunStop] hands [run] over and [runStopPending] emits.
  void pressLeftoverStop(String run) {
    _runStop = run;
    _runStopPending.add(null);
  }

  /// The platform's own recording is on ([setHistory]).
  bool get historyEnabled => _historyEnabled;

  /// The platform records [fix] for the history: [takeHistory] hands it
  /// over and [historyPending] emits.
  void recordHistory(LocationFix fix) {
    _history.add(fix);
    _historyPending.add(null);
  }

  /// The recorded positions [takeHistory] has not handed over yet.
  List<LocationFix> get pendingHistory => List.unmodifiable(_history);

  /// Ends every stream and answers the [current] calls still waiting with
  /// null.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final MapEntry(key: timer, value: answer) in _waits.entries) {
      timer.cancel();
      answer.complete(null);
    }
    _waits.clear();
    await Future.wait([
      _accessChanges.close(),
      _updates.close(),
      _runStops.close(),
      _runStopPending.close(),
      _historyPending.close(),
    ]);
  }

  // -------------------------------------------------------- PhoneLocation

  @override
  Future<LocationAccess> access() async => _access;

  @override
  Stream<LocationAccess> get accessChanges => _accessChanges.stream;

  @override
  Future<LocationAccess> requestWhileInUse() async {
    _whileInUseRequests++;
    return _answered(whileInUseAnswer);
  }

  @override
  Future<LocationAccess> requestAlways() async {
    _alwaysRequests++;
    return _answered(alwaysAnswer);
  }

  /// The access after a permission request the user answered with
  /// [answer]; the platform reports it on [accessChanges] too.
  LocationAccess _answered(LocationAccess? answer) {
    if (answer != null) _access = answer;
    if (!_closed) _accessChanges.add(_access);
    return _access;
  }

  @override
  Future<String?> alwaysSettingsChoice() async => alwaysChoice;

  @override
  Future<void> openSettings(LocationSettingsPage page) async {
    _settingsOpened.add(page);
  }

  @override
  Stream<LocationFix> get updates => _updates.stream;

  @override
  Future<LocationFix?> current({required Duration timeout}) {
    _currentRequests++;
    if (!_access.usable || _closed) return Future.value();
    final answer = onCurrent;
    if (answer != null) return answer(timeout);
    final fix = currentFix;
    if (fix != null) return Future.value(fix);
    final waiting = Completer<LocationFix?>();
    late final Timer timer;
    timer = Timer(timeout, () {
      _waits.remove(timer);
      waiting.complete(null);
    });
    _waits[timer] = waiting;
    return waiting.future;
  }

  @override
  Future<void> holdRun(LocationRunNotice notice, {required bool awake}) async {
    final refusal = runRefusal;
    if (refusal != null) throw LocationRunException(refusal);
    if (_access.permission == LocationPermission.denied || !_access.serviceOn) {
      throw const LocationRunException(LocationRunRefusal.noAccess);
    }
    _runHeld = true;
    _runShown = true;
    _runHolds.add((notice: notice, awake: awake));
  }

  @override
  Future<void> releaseRun() async {
    if (!_runHeld) return;
    _runHeld = false;
    _runShown = false;
    _runReleases++;
    onRunReleased?.call();
  }

  @override
  Stream<void> get runStops => _runStops.stream;

  @override
  Future<String?> takeRunStop() async {
    final run = _runStop;
    _runStop = null;
    return run;
  }

  @override
  Stream<void> get runStopPending => _runStopPending.stream;

  @override
  Future<bool> backgroundUnrestricted() async => unrestricted;

  @override
  Future<bool> requestBackgroundUnrestricted() async {
    _unrestrictedRequests++;
    return unrestricted = unrestrictedAnswer ?? unrestricted;
  }

  @override
  Future<void> setHistory({required bool enabled}) async {
    _historyEnabled = enabled;
  }

  @override
  Future<List<LocationFix>> takeHistory() async {
    final taken = List.of(_history);
    _history.clear();
    return taken;
  }

  @override
  Stream<void> get historyPending => _historyPending.stream;
}
