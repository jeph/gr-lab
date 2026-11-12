import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// The oldest position that may be written, by its own fix time
/// \[design\]: the camera does not check a position's age and keeps any it
/// accepts for 600 s (research/protocol/geotagging.md §1.3), so the age is
/// judged here.
const _maxFixAge = Duration(seconds: 60);

/// The least accurate position that may be written, in metres \[design\].
const _maxFixAccuracy = 100.0;

/// How far the phone has to move from the last written position, in
/// metres, before another is written; a fix less accurate than that has to
/// move by its own accuracy instead, or the noise of the positioning would
/// count as movement \[design\].
const _minMove = 5.0;

/// The shortest time between two writes \[design\]; GR WORLD's fastest
/// setting writes every 5 s too (geotagging.md §2.2).
const _minWriteGap = Duration(seconds: 5);

/// After this long without a write a new position is asked for and
/// written \[design\]: well inside the 600 s the camera keeps one for,
/// and GR WORLD's slowest setting.
const _keepAliveAfter = Duration(seconds: 180);

/// How long the camera keeps a position it accepted (found in the GR IV
/// 1.20 and GR III 2.20 firmware; geotagging.md §1.3).
const _cameraValidity = Duration(seconds: 600);

/// How long [PhoneLocation.current] gets to take a position \[design\].
const _currentTimeout = Duration(seconds: 30);

/// The camera refuses an altitude beyond this, in metres (found in the
/// firmware; geotagging.md §1.2).
const _maxAltitude = 9999.0;

/// How often the camera's clock is compared with the phone's while the
/// camera stays on and linked \[design\].
const _clockCheckEvery = Duration(minutes: 60);

/// The camera's clock is set only when it is this far off \[design\]: it
/// has whole seconds, so a clock that is right reads up to a second
/// behind, and on a GR IV every change of it clears the location the
/// camera holds (geotagging.md §1.3).
const _clockTolerance = Duration(seconds: 2);

/// How long after a clock write a position is written again \[design\]:
/// a GR IV clears its location 1 s after its clock changes (found in the
/// GR IV 1.20 firmware; geotagging.md §1.3).
const _clockSettle = Duration(seconds: 2);

/// How long the run that keeps live geotagging going off screen waits for
/// a camera that is not on before it is released \[design\].
const _cameraWait = Duration(minutes: 60);

/// How long after a failed read of the camera's Store Location Info it is
/// read again \[design\].
const _settingRetry = Duration(seconds: 10);

/// What live geotagging is doing for one camera.
enum GeotagStatus {
  /// Not turned on for this camera.
  off,

  /// The camera has no location characteristics.
  unsupported,

  /// The app may not locate the phone.
  permissionDenied,

  /// Only approximate location is allowed.
  preciseNeeded,

  /// Location is off for the whole phone.
  locationOff,

  /// The user ended it from the notification; [CameraGeotagging.resume] or
  /// the camera's next power-on restarts it.
  stopped,

  /// The camera came on while the app was not on screen and the phone
  /// would not let the run start from there.
  needsApp,

  /// The camera is off or out of reach.
  waitingForCamera,

  /// Store Location Info is off on the camera (turned off in its menu).
  offOnCamera,

  /// The camera is on; no position good enough yet.
  waitingForLocation,

  /// The camera holds a position this session wrote and it is still valid.
  sending,
}

/// What the app decides for one camera.
@immutable
final class GeotagSettings {
  /// Settings with live geotagging on or off ([live]), the clock kept or
  /// not ([syncClock]) and a Store Location Info value still to write
  /// ([storeLocationInfoPending]).
  const new({
    required this.live,
    required this.syncClock,
    this.storeLocationInfoPending,
  });

  /// Live geotagging is on: the phone's position is written to the camera
  /// while the camera is on.
  final bool live;

  /// The camera's clock is kept on the phone's time. Always done while
  /// [live], whatever this says.
  final bool syncClock;

  /// The value of the camera's Store Location Info the app still has to
  /// write (the user flipped the switch while the camera was off or away);
  /// null when nothing is pending.
  final bool? storeLocationInfoPending;

  @override
  bool operator ==(Object other) =>
      other is GeotagSettings &&
      other.live == live &&
      other.syncClock == syncClock &&
      other.storeLocationInfoPending == storeLocationInfoPending;

  @override
  int get hashCode => Object.hash(live, syncClock, storeLocationInfoPending);

  @override
  String toString() =>
      'GeotagSettings(live: $live, syncClock: $syncClock, '
      'storeLocationInfoPending: $storeLocationInfoPending)';

  Map<String, Object?> _toJson() => {
    'live': live,
    'syncClock': syncClock,
    'storeLocationInfoPending': storeLocationInfoPending,
  };
}

/// Live geotagging and clock sync for one session: while the camera is on
/// and linked over Bluetooth, the phone's position is written to it (GPS
/// Information), and its clock is kept on the phone's time (Date Time).
///
/// The camera takes a position only while its Store Location Info setting
/// (GEO Tag) is on, keeps it for 600 s and saves it in every picture it
/// takes meanwhile, without checking how old it is
/// (research/protocol/geotagging.md §1). So a position is judged here
/// before it is written, a written one is never sent again, and with no
/// position good enough nothing is written and the camera's runs out.
///
/// The phone is located only while the camera is on, linked and has the
/// setting on; nothing is ever written to a camera that is off. Every
/// decision is traced on [TraceChannel.session] (`geotag.…`, `clock.…`).
final class CameraGeotagging extends ChangeNotifier {
  new _(this._session, this._camera, this._body) {
    _events = _session.events.listen(_onSessionEvent);
  }

  final GrSession _session;
  final GrCameraEnvironment _camera;

  /// The camera's model and firmware, as `CameraSession.body` has them.
  final CameraBody Function() _body;

  late final StreamSubscription<GrSessionEvent> _events;
  StreamSubscription<LocationAccess>? _accessChanges;
  StreamSubscription<void>? _runStops;
  StreamSubscription<LocationFix>? _updates;
  final _fixes = StreamController<LocationFix>.broadcast();
  final _storeLocationInfoWritten = StreamController<bool>.broadcast();

  GeotagSettings? _settings;
  LocationRunNotice Function(GeotagStatus status)? _notice;

  /// What the phone lets the app do; null until it answered.
  LocationAccess? _access;
  GeotagStatus _status = GeotagStatus.off;
  DateTime? _lastSentAt;
  bool _closed = false;

  /// The camera being on and linked now; null while it is not.
  _OnPeriod? _period;

  /// The period the phone is being located for.
  _OnPeriod? _locatingFor;

  /// The pending Store Location Info value that was written and reported;
  /// it is not written again while the app still passes it.
  bool? _writtenPending;

  /// Live was turned off in this session without a pending value: Store
  /// Location Info is turned off when the camera is next on and linked.
  bool _turnOffWanted = false;

  /// The user ended live geotagging from the platform's notice.
  bool _stopped = false;

  /// The session saw the camera off, or gave it up, since [_stopped].
  bool _offSinceStop = false;

  /// The phone refused the run because the app is not on screen. Asked
  /// again when the app is on screen (the access is reported then) or the
  /// camera next comes on.
  bool _needsApp = false;

  /// The phone cannot hold a run now; asked again when the access changes
  /// or the camera next comes on.
  bool _runUnavailable = false;

  /// The camera was not on for [_cameraWait], so the run was released.
  bool _waitedOut = false;
  Timer? _cameraWaitTimer;

  /// What was last asked of the phone's run; null when none is asked for.
  _RunRequest? _runAsked;

  /// The phone holds a run for this session.
  bool _runHeld = false;

  /// What live geotagging is doing now.
  GeotagStatus get status => _status;

  /// When the last position was written to the camera in this session.
  DateTime? get lastSentAt => _lastSentAt;

  /// Completes each time the pending Store Location Info value was written
  /// to the camera, with the value written, so the app can clear what it
  /// persisted.
  Stream<bool> get storeLocationInfoWritten => _storeLocationInfoWritten.stream;

  /// Every position taken for the camera while live runs, written or not
  /// (for the app's history).
  Stream<LocationFix> get fixes => _fixes.stream;

  /// Applies the app's settings; call at session start and on every
  /// change. [notice] gives the platform notice for a status
  /// ([GeotagStatus.sending], [GeotagStatus.waitingForLocation],
  /// [GeotagStatus.waitingForCamera], [GeotagStatus.offOnCamera]), in the
  /// user's language.
  ///
  /// A pending Store Location Info value is written as soon as the camera
  /// is on and linked. Turning [GeotagSettings.live] off without one turns
  /// the camera's setting off as well, which clears the location the
  /// camera holds.
  void configure(
    GeotagSettings settings, {
    required LocationRunNotice Function(GeotagStatus status) notice,
  }) {
    if (_closed) return;
    final wasLive = _live;
    _settings = settings;
    _notice = notice;
    _camera.event('geotag.configure', settings._toJson());
    final pending = settings.storeLocationInfoPending;
    if (pending == null) _writtenPending = null;
    _turnOffWanted =
        pending == null && !settings.live && (wasLive || _turnOffWanted);
    // A value the camera refused is tried again when the app says so.
    _period?.settingRefused = null;
    if (settings.live != wasLive) {
      // A new start: what ended or held up the last one no longer counts.
      _stopped = false;
      _needsApp = false;
      _runUnavailable = false;
      _waitedOut = false;
      _access = null;
    }
    if (settings.live) {
      _accessChanges ??= _camera.location.accessChanges.listen(
        _onAccessChanged,
      );
      _runStops ??= _camera.location.runStops.listen((_) => _onRunStopped());
      if (_access == null) unawaited(_readAccess());
    }
    _reconcile();
  }

  /// Writes Store Location Info on (from [GeotagStatus.offOnCamera], the
  /// user asked for it in the app). Throws [BleException] when the camera
  /// is not on and linked, or refuses.
  Future<void> turnOnStoreLocationInfo() async {
    final period = _period;
    if (period == null) throw _notOn;
    await _setStoreLocationInfo(period, on: true, why: 'user');
  }

  /// Starts again after [GeotagStatus.stopped].
  void resume() {
    if (_closed) return;
    _camera.event('geotag.resume');
    _stopped = false;
    _needsApp = false;
    _runUnavailable = false;
    _waitedOut = false;
    _reconcile();
  }

  // ---------------------------------------------------------------- state

  static const _notOn = BleException(
    BleErrorCode.notConnected,
    'the camera is not on and linked',
  );

  static final _needed = <GrBleCharacteristic<Object>>[
    GrBleCatalog.gpsInformation,
    GrBleCatalog.geoTag,
  ];

  bool get _live => _settings?.live ?? false;

  bool get _clockWanted => _live || (_settings?.syncClock ?? false);

  /// The camera is known not to take a position: its model does not
  /// (`CameraFeature.geotagging`), or the link found it without the
  /// characteristics.
  bool get _unsupported {
    final ble = _session.ble;
    if (ble != null && _needed.any((c) => ble.isPresent(c) == false)) {
      return true;
    }
    final body = _body();
    // Before the first link of a camera nothing is recorded for, nothing
    // says what it is.
    if (body.model == null && _session.identity == null) return false;
    return !body.supports(CameraFeature.geotagging);
  }

  /// Live geotagging runs: it is on, the camera can take a position and
  /// the phone may be located.
  bool get _active =>
      !_closed && _live && !_unsupported && (_access?.usable ?? false);

  /// [period] is still the camera's current time on: the link is the
  /// session's and the camera has not reported turning off, nor is the
  /// session turning it off. Checked before every write, so nothing
  /// reaches a camera that is off.
  bool _isCurrent(_OnPeriod period) =>
      !_closed &&
      !period.ended &&
      identical(_session.ble, period.ble) &&
      !_session.cameraOff &&
      !_session.turningOff;

  /// The Store Location Info value still to write to the camera.
  bool? get _settingWanted {
    final pending = _settings?.storeLocationInfoPending;
    if (pending != null) return pending == _writtenPending ? null : pending;
    return _turnOffWanted ? false : null;
  }

  void _onSessionEvent(GrSessionEvent event) {
    // The session stopped linking a camera that is off or gone.
    if (event.kind == 'ble.gaveUp' || event.kind == 'ble.parked') {
      _offSinceStop = true;
    }
    _reconcile();
  }

  Future<void> _readAccess() async {
    final access = await _camera.location.access();
    if (_closed) return;
    _access = access;
    _reconcile();
  }

  /// The access changed, or the app is on screen again: a run the phone
  /// refused may be held now.
  void _onAccessChanged(LocationAccess access) {
    if (_closed) return;
    _access = access;
    _needsApp = false;
    _runUnavailable = false;
    _reconcile();
  }

  /// The user pressed Stop on the platform's notice, which released the
  /// run already.
  void _onRunStopped() {
    if (_closed || !_live) return;
    _runAsked = null;
    _runHeld = false;
    _stopped = true;
    _offSinceStop = false;
    _camera.event('geotag.stopped');
    _reconcile();
  }

  /// Brings everything in line with the settings, the phone's access and
  /// the session: the camera's time on, what is asked of the camera, the
  /// locating of the phone, the run and the status. Runs after every
  /// change of any of them, and on every session event.
  void _reconcile({bool notify = false}) {
    if (_closed || _settings == null) return;
    _followCamera();
    final period = _period;
    if (period != null) _serve(period);
    _syncCameraWait();
    _syncLocating();
    _syncRun();
    final next = _statusNow();
    final changed = next != _status;
    if (changed) {
      _camera.event('geotag.status', {'from': _status.name, 'to': next.name});
      _status = next;
    }
    if (changed || notify) notifyListeners();
  }

  GeotagStatus _statusNow() {
    if (!_live) return GeotagStatus.off;
    if (_unsupported) return GeotagStatus.unsupported;
    final access = _access;
    // The phone has not answered yet: nothing new to say.
    if (access == null) return _status;
    if (access.permission == LocationPermission.denied) {
      return GeotagStatus.permissionDenied;
    }
    if (!access.serviceOn) return GeotagStatus.locationOff;
    if (!access.precise) return GeotagStatus.preciseNeeded;
    if (_stopped) return GeotagStatus.stopped;
    // A camera that is off is waited for, with or without the run.
    if (_needsApp && _period != null) return GeotagStatus.needsApp;
    return _runningStatus();
  }

  /// The status while live geotagging runs, which the platform's notice
  /// shows.
  GeotagStatus _runningStatus() {
    final period = _period;
    if (period == null) return GeotagStatus.waitingForCamera;
    // Until the camera's setting is read it counts as on, as it is on
    // most links: the status does not pass through another on the way.
    if (period.storeLocationInfo == false) return GeotagStatus.offOnCamera;
    final writtenAt = period.writtenAt;
    if (writtenAt != null &&
        clock.now().difference(writtenAt) < _cameraValidity) {
      return GeotagStatus.sending;
    }
    return GeotagStatus.waitingForLocation;
  }

  // --------------------------------------------------------------- camera

  /// Starts a period when the camera is on and linked, and ends it when
  /// the camera turns off, the link goes or another link took its place.
  void _followCamera() {
    final ble = _session.ble;
    // A camera the session is turning off counts as off from the write.
    final cameraOff = _session.cameraOff || _session.turningOff;
    if (cameraOff) _offSinceStop = true;
    final period = _period;
    if (period != null && (cameraOff || !identical(period.ble, ble))) {
      period.end();
      _period = null;
      _camera.event('geotag.cameraAway', {
        'linked': ble != null,
        'cameraOff': cameraOff,
      });
    }
    if (ble == null || cameraOff || _period != null) return;
    _period = _OnPeriod(ble);
    _waitedOut = false;
    _needsApp = false;
    _runUnavailable = false;
    _camera.event('geotag.cameraOn');
    if (_stopped && _offSinceStop) {
      // Switched on after being off: the user's Stop was for the last
      // time it was on.
      _stopped = false;
      _camera.event('geotag.resume', {'reason': 'cameraOn'});
    }
  }

  /// Asks of the camera what the settings want for [period], in this
  /// order: a Store Location Info value still to write, the camera's own
  /// setting (read and followed), and its clock. One at a time; each is
  /// asked for once per period.
  void _serve(_OnPeriod period) {
    final wanted = _settingWanted;
    if (wanted != null &&
        !_unsupported &&
        !period.settingBeingWritten &&
        period.settingRefused != wanted) {
      period.settingBeingWritten = true;
      period.run(() => _writeWantedSetting(period, on: wanted));
    }
    if (_live && !_unsupported && !period.settingFollowed) {
      period.settingFollowed = true;
      period.run(() => _followSetting(period));
    }
    if (_clockWanted && !period.clockFollowed) {
      period
        ..clockFollowed = true
        // The clock is checked before the first position is written.
        ..writesHeld = true
        ..run(() => _checkClock(period));
    } else if (!_clockWanted && period.clockFollowed) {
      period
        ..clockFollowed = false
        ..clockTimer?.cancel();
    }
  }

  Future<void> _writeWantedSetting(_OnPeriod period, {required bool on}) async {
    final pending = _settings?.storeLocationInfoPending == on;
    try {
      await _setStoreLocationInfo(
        period,
        on: on,
        why: pending ? 'pending' : 'liveOff',
      );
    } on Object {
      // Traced where it failed. Tried again on the next link, the camera's
      // next power-on or the next configure, not in a loop.
      period.settingRefused = on;
    }
    period.settingBeingWritten = false;
    _reconcile();
  }

  /// Writes Store Location Info and takes note of the camera's new
  /// setting; reports a pending value as written. Throws when the camera
  /// is not on and linked, or refuses.
  Future<void> _setStoreLocationInfo(
    _OnPeriod period, {
    required bool on,
    required String why,
  }) async {
    if (!_isCurrent(period)) throw _notOn;
    _camera.event('geotag.storeLocationInfo.write', {'value': on, 'why': why});
    try {
      await period.ble.setGeoTag(enabled: on);
    } on Object catch (e) {
      _camera.event('geotag.storeLocationInfo.failed', {
        'value': on,
        'error': '$e',
      });
      rethrow;
    }
    if (_closed) return;
    _camera.event('geotag.storeLocationInfo.written', {'value': on});
    if (!on) _turnOffWanted = false;
    if (_settings?.storeLocationInfoPending == on) {
      _writtenPending = on;
      _storeLocationInfoWritten.add(on);
    }
    if (!period.ended) _onSetting(period, on: on);
    _reconcile();
  }

  /// Follows GEO Tag's notifications on [period]'s link and reads it once,
  /// as GR WORLD does after subscribing.
  Future<void> _followSetting(_OnPeriod period) async {
    unawaited(period.settingWatch?.cancel());
    try {
      period.settingWatch = period.ble.watch(GrBleCatalog.geoTag).listen(
        (n) {
          final on = n.decoded.value;
          if (on == null || period.ended) return;
          // The user changed it in the camera's menu.
          _camera.event('geotag.storeLocationInfo', {
            'value': on,
            'source': 'notified',
          });
          _onSetting(period, on: on);
          _reconcile();
        },
        onError: (Object e) => _camera.event(
          'geotag.storeLocationInfo.watchFailed',
          {'error': '$e'},
        ),
      );
    } on BleException catch (e) {
      _camera.event('geotag.storeLocationInfo.watchFailed', {'error': '$e'});
    }
    if (await _readSetting(period, source: 'link')) return;
    if (period.ended) return;
    period.settingRetry?.cancel();
    period.settingRetry = Timer(_settingRetry, () {
      period.settingFollowed = false;
      _reconcile();
    });
  }

  /// Reads the camera's Store Location Info; false when the read failed.
  Future<bool> _readSetting(_OnPeriod period, {required String source}) async {
    final bool? on;
    try {
      on = (await period.ble.read(GrBleCatalog.geoTag)).value;
    } on Object catch (e) {
      _camera.event('geotag.storeLocationInfo.readFailed', {
        'source': source,
        'error': '$e',
      });
      return false;
    }
    if (on == null) return false;
    if (period.ended) return true;
    _camera.event('geotag.storeLocationInfo', {'value': on, 'source': source});
    _onSetting(period, on: on);
    _reconcile();
    return true;
  }

  /// The camera's Store Location Info is [on]. Turned off, the camera
  /// cleared the location it held (geotagging.md §1.3), so the next
  /// position after it is turned on again is the first.
  void _onSetting(_OnPeriod period, {required bool on}) {
    if (period.storeLocationInfo == on) return;
    period.storeLocationInfo = on;
    if (!on) period.forgetWritten();
  }

  // ---------------------------------------------------------------- clock

  /// Compares the camera's clock with the phone's and sets it when it is
  /// off, then holds position writes until the camera has settled and
  /// writes a newly taken position; checks again [_clockCheckEvery] later.
  Future<void> _checkClock(_OnPeriod period) async {
    final written = await _syncClock(period);
    if (period.ended) return;
    if (written) {
      // A GR IV clears the location it holds; the next position is the
      // first again.
      period.forgetWritten();
      _reconcile();
      await period.pause(_clockSettle);
      if (period.ended) return;
    }
    period.writesHeld = false;
    if (period.clockFollowed) {
      period.clockTimer?.cancel();
      period.clockTimer = Timer(
        _clockCheckEvery,
        () => period.run(() => _checkClock(period)),
      );
    }
    final held = period.heldFix;
    period.heldFix = null;
    if (written) {
      unawaited(_takeFresh(period, reason: 'clock'));
    } else if (held != null) {
      _consider(period, held);
    }
  }

  /// Reads Date Time and writes the phone's time when the two differ by
  /// [_clockTolerance] or more. True when a write was sent: it may have
  /// changed the clock even if it failed.
  Future<bool> _syncClock(_OnPeriod period) async {
    final ble = period.ble;
    if (ble.isPresent(GrBleCatalog.dateTime) == false) {
      _camera.event('clock.unsupported');
      return false;
    }
    final BleDateTime? camera;
    try {
      camera = (await ble.read(GrBleCatalog.dateTime)).value;
    } on Object catch (e) {
      _camera.event('clock.readFailed', {'error': '$e'});
      return false;
    }
    if (!_isCurrent(period) || !_clockWanted) return false;
    // Both are local time without a zone, as the camera keeps it
    // (ble.md §Date/time sync), so they are compared field by field.
    final phone = clock.now().toLocal();
    final cameraTime = camera?.toLocalDateTime();
    final offset = cameraTime == null
        ? null
        : _withoutZone(cameraTime).difference(_withoutZone(phone));
    final write = offset == null || offset.abs() >= _clockTolerance;
    _camera.event('clock.offset', {
      'camera': camera?.iso,
      'phone': BleDateTime.fromDateTime(phone).iso,
      'offsetMs': offset?.inMilliseconds,
      'write': write,
    });
    if (!write) return false;
    period.writesHeld = true;
    try {
      // The camera's clock has whole seconds: the nearest one is written.
      final time = await ble.syncDateTime(
        clock.now().toLocal().add(const Duration(milliseconds: 500)),
      );
      _camera.event('clock.written', {'time': time.iso});
    } on Object catch (e) {
      _camera.event('clock.writeFailed', {'error': '$e'});
    }
    return true;
  }

  static DateTime _withoutZone(DateTime time) => DateTime.utc(
    time.year,
    time.month,
    time.day,
    time.hour,
    time.minute,
    time.second,
    time.millisecond,
  );

  // ------------------------------------------------------------ positions

  /// Locates the phone exactly while the camera is on, linked and has
  /// Store Location Info on, and live geotagging runs.
  void _syncLocating() {
    final period = _period;
    final locate =
        period != null &&
        _active &&
        !_stopped &&
        !_needsApp &&
        (period.storeLocationInfo ?? false);
    if (!locate) {
      if (_locatingFor == null) return;
      _locatingFor?.stopLocating();
      _locatingFor = null;
      unawaited(_updates?.cancel());
      _updates = null;
      _camera.event('geotag.locating', {'on': false});
      return;
    }
    if (identical(_locatingFor, period)) return;
    _locatingFor = period;
    _armKeepAlive(period);
    _camera.event('geotag.locating', {'on': true});
    _updates ??= _camera.location.updates.listen(_onFix);
  }

  void _onFix(LocationFix fix) {
    final period = _locatingFor;
    if (_closed || period == null) return;
    _fixes.add(fix);
    // A newer position replaces one that waited for its turn.
    period.deferred?.cancel();
    _consider(period, fix);
  }

  /// Writes [fix] when it is good enough and due: the first of this
  /// period ([first] names why it is one), one the phone moved for, or one
  /// after [_keepAliveAfter] without a write.
  void _consider(_OnPeriod period, LocationFix fix, {String first = 'first'}) {
    if (!identical(_locatingFor, period)) return;
    final now = clock.now();
    final unusable = _unusable(fix, now);
    if (unusable != null) {
      _skipped(fix, unusable);
      return;
    }
    if (period.writesHeld) {
      period.heldFix = fix;
      _skipped(fix, 'clock');
      return;
    }
    if (period.writing) {
      _skipped(fix, 'writing');
      return;
    }
    var reason = first;
    final last = period.written;
    final lastAt = period.writtenAt;
    if (last != null && lastAt != null) {
      reason = 'keepAlive';
      if (now.difference(lastAt) < _keepAliveAfter) {
        final moved = _metresBetween(last, fix);
        final needed = math.max(_minMove, fix.accuracy);
        if (moved <= needed) {
          _skipped(fix, 'notMoved', {
            'movedMetres': moved,
            'neededMetres': needed,
          });
          return;
        }
        reason = 'moved';
      }
    }
    final attemptedAt = period.attemptedAt;
    final wait = attemptedAt == null
        ? Duration.zero
        : _minWriteGap - now.difference(attemptedAt);
    if (wait > Duration.zero) {
      // Written when its turn comes, unless a newer one arrives first.
      _skipped(fix, 'tooSoon', {'waitMs': wait.inMilliseconds});
      period.deferred?.cancel();
      period.deferred = Timer(wait, () => _consider(period, fix, first: first));
      return;
    }
    unawaited(_write(period, fix, reason: reason));
  }

  /// Why [fix] may not be written at all: `invalid`, `age` or `accuracy`.
  static String? _unusable(LocationFix fix, DateTime now) {
    if (!fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude.abs() > 90 ||
        fix.longitude.abs() > 180) {
      return 'invalid';
    }
    if (now.difference(fix.time) > _maxFixAge) return 'age';
    // A fix without an accuracy has an infinite one.
    if (!(fix.accuracy <= _maxFixAccuracy)) return 'accuracy';
    return null;
  }

  void _skipped(
    LocationFix? fix,
    String reason, [
    Map<String, Object?> detail = const {},
  ]) => _camera.event('geotag.skipped', {
    'reason': reason,
    if (fix != null) ...{
      'ageMs': clock.now().difference(fix.time).inMilliseconds,
      'accuracy': fix.accuracy.isFinite ? fix.accuracy : null,
    },
    ...detail,
  });

  /// Writes [fix] to the camera. The record carries the fix time in UTC,
  /// as both of Ricoh's apps send it (geotagging.md §2.5, §3), and an
  /// altitude of 0 when the phone gave none.
  Future<void> _write(
    _OnPeriod period,
    LocationFix fix, {
    required String reason,
  }) async {
    if (!_isCurrent(period)) {
      // The camera is turning off, or the link went, a moment ago.
      _skipped(fix, 'cameraAway');
      return;
    }
    final altitude = fix.altitude;
    final record = BleGpsInformation.at(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitude: altitude == null || !altitude.isFinite
          ? 0
          : altitude.clamp(-_maxAltitude, _maxAltitude),
      time: fix.time.toUtc(),
    );
    period
      ..writing = true
      ..attemptedAt = clock.now();
    _camera.event('geotag.write', {'reason': reason, ...record.toJson()});
    try {
      await period.ble.sendGps(record);
    } on Object catch (e) {
      period.writing = false;
      await _onWriteFailed(period, e);
      return;
    }
    period.writing = false;
    if (_closed) return;
    final now = clock.now();
    _lastSentAt = now;
    _camera.event('geotag.written', {'reason': reason});
    if (!period.ended) {
      period.wrote(fix, at: now, expires: Timer(_cameraValidity, _reconcile));
      if (identical(_locatingFor, period)) _armKeepAlive(period);
    }
    _reconcile(notify: true);
  }

  /// A position write failed. With the link still up the camera refused
  /// it, which it does while Store Location Info is off (geotagging.md
  /// §1.2): the setting is read again, and the link is left alone.
  Future<void> _onWriteFailed(_OnPeriod period, Object error) async {
    // A link that dropped under the write reaches the session a moment
    // later.
    await Future<void>.delayed(Duration.zero);
    if (!_isCurrent(period)) {
      _camera.event('geotag.writeLost', {'error': '$error'});
      return;
    }
    _camera.event('geotag.refused', {'error': '$error'});
    await _readSetting(period, source: 'refusal');
  }

  void _armKeepAlive(_OnPeriod period) {
    period.keepAlive?.cancel();
    period.keepAlive = Timer(
      _keepAliveAfter,
      () => unawaited(_takeFresh(period, reason: 'keepAlive')),
    );
  }

  /// Asks the phone for a new position and writes it when it is good
  /// enough: after [_keepAliveAfter] without a write ([reason]
  /// `keepAlive`), and after a clock write (`clock`). A position written
  /// before is never sent again.
  Future<void> _takeFresh(_OnPeriod period, {required String reason}) async {
    if (!identical(_locatingFor, period) || period.fetching) return;
    period.fetching = true;
    _camera.event('geotag.current', {'reason': reason});
    final fix = await _camera.location.current(timeout: _currentTimeout);
    period.fetching = false;
    if (_closed || !identical(_locatingFor, period)) return;
    if (fix == null) {
      _skipped(null, 'noFix');
    } else {
      _fixes.add(fix);
      // It is newer than a position that waited for its turn.
      period.deferred?.cancel();
      _consider(period, fix, first: reason == 'clock' ? reason : 'first');
    }
    // The next one is asked for when nothing is written for as long again.
    _armKeepAlive(period);
  }

  /// Metres between two positions on a sphere (haversine).
  static double _metresBetween(LocationFix a, LocationFix b) {
    const earthRadius = 6371008.8;
    const radians = math.pi / 180;
    final latitudeA = a.latitude * radians;
    final latitudeB = b.latitude * radians;
    final sinLatitude = math.sin((latitudeB - latitudeA) / 2);
    final sinLongitude = math.sin((b.longitude - a.longitude) * radians / 2);
    final h =
        sinLatitude * sinLatitude +
        math.cos(latitudeA) * math.cos(latitudeB) * sinLongitude * sinLongitude;
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  // ------------------------------------------------------------------ run

  /// Starts the wait for a camera that is not on while a run is wanted,
  /// and releases the run when it lasts [_cameraWait].
  void _syncCameraWait() {
    final waiting = _active && !_stopped && !_waitedOut && _period == null;
    if (!waiting) {
      _cameraWaitTimer?.cancel();
      _cameraWaitTimer = null;
      return;
    }
    _cameraWaitTimer ??= Timer(_cameraWait, () {
      _cameraWaitTimer = null;
      _waitedOut = true;
      _camera.event('geotag.waitedOut');
      _reconcile();
    });
  }

  /// Holds the run while live geotagging runs, with the notice of the
  /// current status and the processor kept on while the camera is on;
  /// releases it otherwise.
  void _syncRun() {
    final notice = _notice;
    final wanted = notice == null || !_active || _stopped || _waitedOut
        ? null
        : _RunRequest(notice(_runningStatus()), awake: _period != null);
    final asked = _runAsked;
    if (wanted == null) {
      if (asked == null && !_runHeld) return;
      _runAsked = null;
      _runHeld = false;
      _camera.event('geotag.run.release');
      unawaited(_camera.location.releaseRun());
      return;
    }
    if (asked != null && asked.sameAs(wanted)) return;
    if (asked == null && (_runUnavailable || _needsApp)) return;
    _runAsked = wanted;
    unawaited(_holdRun(wanted));
  }

  Future<void> _holdRun(_RunRequest request) async {
    _camera.event('geotag.run.hold', {
      'text': request.notice.text,
      'awake': request.awake,
    });
    try {
      await _camera.location.holdRun(request.notice, awake: request.awake);
    } on LocationRunException catch (e) {
      // A newer request, or the release, has taken over.
      if (_closed || !identical(_runAsked, request)) return;
      _runAsked = null;
      _camera.event('geotag.run.refused', {'refusal': e.refusal.name});
      if (_runHeld) {
        // The run held before may still be there with its old notice.
        _runHeld = false;
        unawaited(_camera.location.releaseRun());
      }
      switch (e.refusal) {
        case LocationRunRefusal.background:
          _needsApp = true;
        case LocationRunRefusal.noAccess:
          _runUnavailable = true;
          unawaited(_readAccess());
        case LocationRunRefusal.unsupported:
          _runUnavailable = true;
      }
      _reconcile();
      return;
    }
    if (_closed || !identical(_runAsked, request)) return;
    _runHeld = true;
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _period?.end();
    _period = null;
    _locatingFor = null;
    _cameraWaitTimer?.cancel();
    unawaited(_events.cancel());
    unawaited(_accessChanges?.cancel());
    unawaited(_runStops?.cancel());
    unawaited(_updates?.cancel());
    if (_runAsked != null || _runHeld) {
      _runAsked = null;
      _runHeld = false;
      _camera.event('geotag.run.release', {'reason': 'closed'});
      unawaited(_camera.location.releaseRun());
    }
    unawaited(_fixes.close());
    unawaited(_storeLocationInfoWritten.close());
  }
}

/// One stretch of the camera being on and linked over one Bluetooth link.
/// What the camera said and what was written to it count for that stretch
/// only: a camera that comes on again, or a new link, starts over, with
/// its setting read, its clock checked and the next good position written
/// as the first.
final class _OnPeriod {
  new(this.ble);

  /// The link the camera is reached over.
  final GrBleClient ble;

  /// The camera turned off, or the link went or was replaced.
  bool ended = false;
  Future<void> _work = Future.value();

  /// The camera's Store Location Info as it last said; null until read.
  bool? storeLocationInfo;

  /// The setting's read and notifications were asked for.
  bool settingFollowed = false;
  StreamSubscription<GrBleNotification<bool>>? settingWatch;
  Timer? settingRetry;

  /// A wanted value is being written, and the one the camera refused.
  bool settingBeingWritten = false;
  bool? settingRefused;

  /// The clock check runs for this period, and its next turn.
  bool clockFollowed = false;
  Timer? clockTimer;

  /// No position is written now: the clock is being checked, or was just
  /// set. [heldFix] is the newest position that came meanwhile.
  bool writesHeld = false;
  LocationFix? heldFix;
  Timer? _pause;
  Completer<void>? _paused;

  /// The last position written and when; null before the first, and after
  /// the camera cleared its location.
  LocationFix? written;
  DateTime? writtenAt;

  /// When a write was last tried, taken or refused.
  DateTime? attemptedAt;

  /// A position write is under way.
  bool writing = false;

  /// A new position is being asked of the phone.
  bool fetching = false;
  Timer? keepAlive;

  /// A position waiting out the time since the last write.
  Timer? deferred;

  /// Fires when the camera's time for [written] runs out.
  Timer? _expiry;

  /// Runs [task] after every task given before it, unless the period has
  /// ended by then: what is asked of the camera goes in one order.
  void run(Future<void> Function() task) {
    _work = _work.then((_) async {
      if (!ended) await task();
    });
  }

  /// Completes after [time], or as soon as the period ends.
  Future<void> pause(Duration time) {
    final paused = _paused = Completer<void>();
    _pause = Timer(time, paused.complete);
    return paused.future;
  }

  /// [fix] was written at [at]; [expires] fires when the camera drops it.
  void wrote(LocationFix fix, {required DateTime at, required Timer expires}) {
    written = fix;
    writtenAt = at;
    _expiry?.cancel();
    _expiry = expires;
  }

  /// The camera holds no position of this period any more.
  void forgetWritten() {
    written = null;
    writtenAt = null;
    _expiry?.cancel();
    _expiry = null;
  }

  /// The phone is no longer located for this period.
  void stopLocating() {
    keepAlive?.cancel();
    keepAlive = null;
    deferred?.cancel();
    deferred = null;
    heldFix = null;
  }

  /// Stops everything the period started.
  void end() {
    ended = true;
    stopLocating();
    unawaited(settingWatch?.cancel());
    settingRetry?.cancel();
    clockTimer?.cancel();
    _expiry?.cancel();
    _pause?.cancel();
    final paused = _paused;
    if (paused != null && !paused.isCompleted) paused.complete();
  }
}

/// What is asked of the phone's run: its notice and whether the processor
/// is kept on.
final class _RunRequest {
  const new(this.notice, {required this.awake});

  final LocationRunNotice notice;
  final bool awake;

  /// The phone would show and do the same for [other].
  bool sameAs(_RunRequest other) =>
      awake == other.awake &&
      notice.title == other.notice.title &&
      notice.text == other.notice.text &&
      notice.stopLabel == other.notice.stopLabel &&
      notice.channel == other.notice.channel;
}

/// Creates the geotagging of [session], judging what the camera supports
/// by [body]. Used by `CameraSession` only.
CameraGeotagging createCameraGeotagging(
  GrSession session,
  GrCameraEnvironment camera, {
  required CameraBody Function() body,
}) => CameraGeotagging._(session, camera, body);

/// What `CameraSession` does to its geotagging. Not exported.
extension CameraGeotaggingInternals on CameraGeotagging {
  /// The session ended: stops locating the phone, releases the run and
  /// stops notifying.
  void close() => _close();
}
