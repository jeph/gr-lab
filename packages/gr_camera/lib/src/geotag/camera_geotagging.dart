import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_camera/src/geotag/camera_clock.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Where live geotagging stands, for the app to put into words.
enum GeotagStatus {
  /// Turned off in GR Photo.
  off,

  /// This camera cannot take a location from a phone.
  unsupported,

  /// The phone has not been asked for its location yet, or refused it.
  needsLocation,

  /// The phone only allows approximate location, which is too rough to
  /// record in a picture.
  needsPreciseLocation,

  /// The phone's location is turned off for every app.
  locationOff,

  /// The camera is off or not linked: the phone is not being located.
  waitingForCamera,

  /// Store Location Info is off in the camera's menu (or the camera
  /// refused to turn it on), so it takes no location.
  offOnCamera,

  /// A camera is near, but no run was under way when it came and the
  /// system only lets one begin while the app is in front.
  needsApp,

  /// The user stopped it from the notification; opening the app starts it
  /// again.
  stopped,

  /// The camera is on and no fix recent and accurate enough has come yet.
  waitingForLocation,

  /// The camera has a location from this phone.
  sending,
}

/// Live geotagging: while the camera it is turned on for is on and linked,
/// the phone's location is written to it, and the camera records it in the
/// pictures it takes. One for the environment, because it outlives camera
/// sessions: a session attaches while it lasts.
///
/// What the camera does with a location is in
/// research/protocol/geotagging.md §1: it takes one only while its Store
/// Location Info setting (GEO Tag) is on, keeps it for 600 s after each
/// write, and does not look at how old the position is. So:
///
/// - A run of the phone's location begins once the camera is linked, on or
///   off, and idles until the camera is on with the setting on: only then
///   is the phone located ([LocationMode.precise]). A camera that is off
///   takes nothing and is not woken. The idle run is what lets the camera
///   coming on later start the location with the app not in front: neither
///   Android nor iOS lets a run begin there. It ends after
///   `GeotagOptions.idleLimit` without a camera that is on, and until then
///   [keepsLooking] asks the app to keep linking the camera.
/// - A fix is written only when it is recent and accurate enough, when the
///   phone moved, and at least every `GeotagOptions.keepAlive` while fixes
///   still come. When they stop (indoors, underground) nothing is written
///   and the camera lets its location run out, rather than tagging with a
///   position that is no longer known to be right \[design\].
/// - Turning it on here turns Store Location Info on; turning it off turns
///   that off, which clears the camera's location at once. The camera's
///   own menu is respected: turned off there, nothing is written until it
///   is on again or the user turns it on here ([GeotagStatus.offOnCamera]).
/// - The camera's clock is kept in step ([CameraClock]), and the location
///   is written again after a clock write, which clears it on a GR IV.
final class CameraGeotagging extends ChangeNotifier {
  new _(this._camera) {
    final location = _camera.location;
    _subscriptions = [
      location.fixes.listen(_onFix),
      location.stopRequests.listen((_) => _onStopRequested()),
      location.accessChanges.listen((access) {
        _access = access;
        _update();
      }),
    ];
  }

  final GrCameraEnvironment _camera;
  late final List<StreamSubscription<void>> _subscriptions;

  /// The attached session, its clock and its camera's model and firmware.
  GrSession? _session;
  CameraClock? _clock;
  CameraBody Function() _body = () => CameraBody.unknown;
  List<StreamSubscription<void>> _attached = const [];

  bool _closed = false;
  bool _enabled = false;
  LocationNotice? _waitingNotice;
  LocationNotice? _sendingNotice;
  LocationAccess? _access;
  GeotagStatus _status = GeotagStatus.off;

  /// The user turned it on in this session and the camera's setting has
  /// not been turned on since.
  bool _turnOnCameraSetting = false;

  /// The camera's Store Location Info on the current link; null until
  /// read.
  bool? _cameraSetting;
  GrBleClient? _watchedLink;
  StreamSubscription<GrBleNotification<bool>>? _settingWatch;

  bool _running = false;
  LocationNotice? _runNotice;
  LocationMode _mode = LocationMode.idle;
  Timer? _idleLimit;
  bool _needsApp = false;
  bool _stoppedByUser = false;

  bool _applying = false;
  bool _stale = false;

  PhoneFix? _sent;
  DateTime? _sentAt;
  bool _writing = false;
  Timer? _afterClock;

  /// Where it stands.
  GeotagStatus get status => _status;

  /// Turned on for this camera.
  bool get enabled => _enabled;

  /// When the camera last took a location from this phone on the current
  /// link; null when it has none from it.
  DateTime? get lastSentAt => _sentAt;

  /// A run is under way, so a camera that comes on is geotagged without
  /// the app in front: the app keeps linking the camera meanwhile, also
  /// after a link that could not be got back.
  bool get keepsLooking => _running && !_closed;

  /// What the app knows of the current camera and its own language:
  /// whether live geotagging is on for the camera, and the texts of the
  /// run's notification while it waits for the camera ([waitingNotice])
  /// and while the phone is located ([sendingNotice]). Writes nothing to
  /// the camera.
  void configure({
    required bool enabled,
    required LocationNotice waitingNotice,
    required LocationNotice sendingNotice,
  }) {
    if (_closed) return;
    _waitingNotice = waitingNotice;
    _sendingNotice = sendingNotice;
    if (_enabled != enabled) {
      _enabled = enabled;
      _camera.event('geotag.configured', {'enabled': enabled});
    }
    _update();
  }

  /// The user turned live geotagging on or off. On turns the camera's
  /// Store Location Info on, now or when the camera is next on while the
  /// app runs; off turns it off when the camera is on and linked, which
  /// clears the location it holds. Call again with true to turn the
  /// camera's setting back on after [GeotagStatus.offOnCamera].
  Future<void> setEnabled({required bool enabled}) async {
    if (_closed) return;
    _camera.event('geotag.set', {'enabled': enabled});
    _enabled = enabled;
    _turnOnCameraSetting = enabled;
    if (enabled) {
      _stoppedByUser = false;
      _access = await _camera.location.access();
    } else {
      await _writeCameraSetting(on: false);
    }
    _update();
  }

  /// The app came to the front: reads what the phone allows again (the
  /// user may have been to the system settings), and begins a run that had
  /// to wait for the app or that the user stopped from the notification.
  Future<void> appResumed() async {
    if (_closed || !_enabled) return;
    _needsApp = false;
    _stoppedByUser = false;
    _access = await _camera.location.access();
    _update();
  }

  /// Whether the camera can be geotagged, as far as is known: a session
  /// reads its camera's model and characteristics on linking, and until
  /// then (a session that is still linking, or linking again) nothing
  /// speaks against it, so a run that waits for the camera goes on.
  bool get _supported {
    final ble = _session?.ble;
    if (ble == null) return true;
    if (!_body().supports(CameraFeature.geotagging)) return false;
    return (ble.isPresent(GrBleCatalog.gpsInformation) ?? true) &&
        (ble.isPresent(GrBleCatalog.geoTag) ?? true);
  }

  /// Brings the run, the camera's setting and [status] in line with the
  /// session; changes that arrive meanwhile are applied after.
  void _update() {
    if (_closed) return;
    _clock?.requiredByGeotagging = _enabled;
    final looked = keepsLooking;
    _stale = true;
    if (_applying) return;
    _applying = true;
    unawaited(() async {
      try {
        while (_stale && !_closed) {
          _stale = false;
          _setStatus(await _apply());
        }
      } finally {
        _applying = false;
        // The app follows this to keep the camera linked.
        if (looked != keepsLooking && !_closed) notifyListeners();
      }
    }());
  }

  Future<GeotagStatus> _apply() async {
    if (!_enabled) {
      _unwatchSetting();
      await _endRun('off');
      return GeotagStatus.off;
    }
    if (!_supported) {
      _unwatchSetting();
      await _endRun('unsupported');
      return GeotagStatus.unsupported;
    }
    final access = _access ??= await _camera.location.access();
    final missing = switch (access) {
      LocationAccess.precise => null,
      LocationAccess.approximate => GeotagStatus.needsPreciseLocation,
      LocationAccess.off => GeotagStatus.locationOff,
      LocationAccess.unsupported => GeotagStatus.unsupported,
      LocationAccess.undetermined ||
      LocationAccess.blocked => GeotagStatus.needsLocation,
    };
    if (missing != null) {
      _unwatchSetting();
      await _endRun('access.${access.name}');
      return missing;
    }
    if (_stoppedByUser) return GeotagStatus.stopped;

    final session = _session;
    final ble = session?.ble;
    if (session == null || ble == null || session.cameraOff) {
      _unwatchSetting();
      // Linked while off: the run begins now, so that the camera coming
      // on finds it under way whatever is in front then.
      if (ble != null && !await _hold(precise: false)) return _runFailure;
      await _idle();
      return GeotagStatus.waitingForCamera;
    }
    if (!identical(_watchedLink, ble)) await _watchSetting(ble);
    if (_turnOnCameraSetting && _cameraSetting != true) {
      await _writeCameraSetting(on: true);
    }
    if (_cameraSetting != true) {
      await _idle();
      return GeotagStatus.offOnCamera;
    }
    if (!await _hold(precise: true)) return _runFailure;
    return _sentAt == null
        ? GeotagStatus.waitingForLocation
        : GeotagStatus.sending;
  }

  void _setStatus(GeotagStatus status) {
    if (_closed || status == _status) return;
    _camera.event('geotag.status', {'status': status.name});
    _status = status;
    notifyListeners();
  }

  // ------------------------------------------------- the camera's setting

  /// Reads Store Location Info on [ble] and follows its notifications: the
  /// user changing the camera's menu.
  Future<void> _watchSetting(GrBleClient ble) async {
    _unwatchSetting();
    _watchedLink = ble;
    // A new link may be a camera that was off for longer than it keeps a
    // location: what was sent before says nothing about what it holds.
    _forgetSent();
    try {
      _settingWatch = ble.watch(GrBleCatalog.geoTag).listen((n) {
        if (!identical(_watchedLink, ble)) return;
        _onCameraSetting(n.decoded.value, 'notified');
      }, onError: (Object _) {});
      final read = await ble.read(GrBleCatalog.geoTag);
      if (identical(_watchedLink, ble)) _onCameraSetting(read.value, 'read');
    } on Object catch (e) {
      // Left unknown: nothing is written until the next link reads it.
      _camera.event('geotag.settingReadFailed', {'error': '$e'});
    }
  }

  void _unwatchSetting() {
    unawaited(_settingWatch?.cancel());
    _settingWatch = null;
    _watchedLink = null;
    _cameraSetting = null;
  }

  void _onCameraSetting(bool? on, String source) {
    if (on == _cameraSetting) return;
    _camera.event('geotag.cameraSetting', {'on': on, 'source': source});
    _cameraSetting = on;
    // Off clears the camera's location.
    if (on != true) _forgetSent();
    _update();
  }

  /// Writes Store Location Info when the camera is on and linked.
  Future<void> _writeCameraSetting({required bool on}) async {
    final session = _session;
    final ble = session?.ble;
    if (session == null || ble == null || session.cameraOff) return;
    if (!(ble.isPresent(GrBleCatalog.geoTag) ?? true)) return;
    try {
      await ble.setGeoTag(enabled: on);
    } on Object catch (e) {
      // Shown as off on the camera; turning it on here tries again.
      _camera.event('geotag.settingRefused', {'on': on, 'error': '$e'});
      _turnOnCameraSetting = false;
      return;
    }
    _camera.event('geotag.settingWritten', {'on': on});
    if (on) _turnOnCameraSetting = false;
    if (!on) _forgetSent();
    if (identical(_watchedLink, ble)) _cameraSetting = on;
  }

  // ---------------------------------------------------------- the run

  GeotagStatus get _runFailure =>
      _needsApp ? GeotagStatus.needsApp : GeotagStatus.unsupported;

  /// Begins the run when none is under way and, with [precise], has the
  /// phone located; false when the run could not begin.
  Future<bool> _hold({required bool precise}) async {
    final notice = precise ? _sendingNotice : _waitingNotice;
    if (notice == null) return false;
    final location = _camera.location;
    try {
      if (!_running || notice != _runNotice) {
        await location.start(
          notice: notice,
          interval: _camera.geotagOptions.fixInterval,
        );
        _running = true;
        _runNotice = notice;
      }
      if (precise && (_mode != LocationMode.precise || _idleLimit != null)) {
        _idleLimit?.cancel();
        _idleLimit = null;
        await location.setMode(LocationMode.precise);
        _mode = LocationMode.precise;
      }
      _needsApp = false;
      return true;
    } on LocationStartException catch (e) {
      _camera.event('geotag.runFailed', {'failure': e.failure.name});
      switch (e.failure) {
        case LocationStartFailure.background:
          _needsApp = true;
        case LocationStartFailure.denied:
          // The answer changed since it was read.
          _access = await location.access();
          _stale = true;
        case LocationStartFailure.failed:
      }
      return false;
    }
  }

  /// No camera wants fixes: the run idles, and ends when none has for
  /// `GeotagOptions.idleLimit`.
  Future<void> _idle() async {
    if (!_running || _idleLimit != null) return;
    _idleLimit = Timer(_camera.geotagOptions.idleLimit, () {
      _idleLimit = null;
      unawaited(_endRun('idleLimit'));
    });
    try {
      if (_mode != LocationMode.idle) {
        await _camera.location.setMode(LocationMode.idle);
        _mode = LocationMode.idle;
      }
      final notice = _waitingNotice;
      if (notice != null && notice != _runNotice) {
        await _camera.location.start(
          notice: notice,
          interval: _camera.geotagOptions.fixInterval,
        );
        _runNotice = notice;
      }
    } on LocationStartException {
      // The run ended underneath (the system stopped it).
      await _endRun('idleFailed');
    }
  }

  Future<void> _endRun(String reason) async {
    _idleLimit?.cancel();
    _idleLimit = null;
    if (!_running) return;
    _running = false;
    _runNotice = null;
    _mode = LocationMode.idle;
    _camera.event('geotag.runEnded', {'reason': reason});
    await _camera.location.stop();
  }

  void _onStopRequested() {
    if (_closed) return;
    _stoppedByUser = true;
    _update();
    unawaited(_endRun('stoppedByUser'));
  }

  // -------------------------------------------------------- writing fixes

  void _forgetSent() {
    if (_sent == null && _sentAt == null) return;
    _sent = null;
    _sentAt = null;
    _update();
  }

  /// A GR IV clears its location a second after its clock changes: the
  /// next fix is written whether or not the phone moved.
  void _onClockWritten() {
    _afterClock?.cancel();
    _afterClock = Timer(_camera.geotagOptions.clockClearDelay, _forgetSent);
  }

  void _onFix(PhoneFix fix) {
    if (_closed || _writing) return;
    if (_status != GeotagStatus.waitingForLocation &&
        _status != GeotagStatus.sending) {
      return;
    }
    final ble = _session?.ble;
    if (ble == null || !identical(ble, _watchedLink)) return;
    final write = _decide(fix, DateTime.now());
    if (write == null) return;
    unawaited(_write(ble, write));
  }

  /// What to write for [fix], or null to write nothing; the decision is
  /// traced either way.
  PhoneFix? _decide(PhoneFix fix, DateTime now) {
    final options = _camera.geotagOptions;
    PhoneFix? skip(String why) {
      _camera.event('geotag.skipped', {'why': why, 'fix': fix.toJson()});
      return null;
    }

    if (now.toUtc().difference(fix.time) > options.maximumFixAge) {
      return skip('old');
    }
    if (fix.accuracy > options.maximumAccuracy) return skip('inaccurate');
    final sent = _sent;
    final sentAt = _sentAt;
    if (sent == null || sentAt == null) return fix;
    final since = now.difference(sentAt);
    if (since < options.minimumGap) return skip('tooSoon');
    final moved = _metres(sent, fix);
    if (moved > math.max(options.minimumMove, fix.accuracy)) return fix;
    if (since < options.keepAlive) return skip('notMoved');
    // Still where the better fix put it, as far as this one can tell: the
    // better position, known to hold at this fix's time.
    if (fix.accuracy <= sent.accuracy) return fix;
    return PhoneFix(
      latitude: sent.latitude,
      longitude: sent.longitude,
      altitude: sent.altitude,
      accuracy: sent.accuracy,
      time: fix.time,
      speed: fix.speed,
    );
  }

  Future<void> _write(GrBleClient ble, PhoneFix fix) async {
    _writing = true;
    try {
      await ble.sendGps(
        BleGpsInformation.at(
          latitude: fix.latitude,
          longitude: fix.longitude,
          // The camera refuses an altitude beyond ±9999 m.
          altitude: (fix.altitude ?? 0).clamp(-9999, 9999).toDouble(),
          time: fix.time.toUtc(),
        ),
      );
    } on Object catch (e) {
      _camera.event('geotag.refused', {'error': '$e', 'fix': fix.toJson()});
      await _afterRefusal(ble);
      return;
    } finally {
      _writing = false;
    }
    if (_closed || !identical(ble, _watchedLink)) return;
    _sent = fix;
    _sentAt = DateTime.now();
    _camera.event('geotag.sent', {'fix': fix.toJson()});
    notifyListeners();
    _update();
  }

  /// The camera refuses a location while Store Location Info is off: reads
  /// the setting again, in case its notification was missed.
  Future<void> _afterRefusal(GrBleClient ble) async {
    if (!identical(ble, _session?.ble) || !identical(ble, _watchedLink)) return;
    try {
      final read = await ble.read(GrBleCatalog.geoTag);
      if (identical(ble, _watchedLink)) _onCameraSetting(read.value, 'reread');
    } on Object catch (e) {
      _camera.event('geotag.settingReadFailed', {'error': '$e'});
    }
  }

  /// Great-circle distance between two fixes.
  static double _metres(PhoneFix a, PhoneFix b) {
    const earthRadius = 6371000.0;
    double radians(double degrees) => degrees * math.pi / 180;
    final sinLat = math.sin(radians(b.latitude - a.latitude) / 2);
    final sinLon = math.sin(radians(b.longitude - a.longitude) / 2);
    final h =
        sinLat * sinLat +
        math.cos(radians(a.latitude)) *
            math.cos(radians(b.latitude)) *
            sinLon *
            sinLon;
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  void _attach(
    GrSession session,
    CameraClock clock,
    CameraBody Function() body,
  ) {
    if (_closed) return;
    _detach(_session);
    _session = session;
    _clock = clock;
    _body = body;
    _attached = [
      session.events.listen((e) {
        if (e.kind.startsWith('ble.') || e.kind.startsWith('power.')) _update();
      }),
      clock.written.listen((_) => _onClockWritten()),
    ];
    _update();
  }

  void _detach(GrSession? session) {
    if (session == null || !identical(session, _session)) return;
    for (final s in _attached) {
      unawaited(s.cancel());
    }
    _attached = const [];
    _session = null;
    _clock = null;
    _body = () => CameraBody.unknown;
    _afterClock?.cancel();
    _unwatchSetting();
    _forgetSent();
    _update();
  }

  void _close() {
    _detach(_session);
    _closed = true;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_endRun('closed'));
  }
}

/// Creates the live geotagging of [camera]. Used by `GrCameraEnvironment`
/// only.
CameraGeotagging createCameraGeotagging(GrCameraEnvironment camera) =>
    CameraGeotagging._(camera);

/// What the camera layer does to the environment's geotagging. Not
/// exported.
extension CameraGeotaggingInternals on CameraGeotagging {
  /// [session] began: its camera is the one geotagged from now on, with
  /// [clock] kept in step and [body] its model and firmware.
  void attach(
    GrSession session, {
    required CameraClock clock,
    required CameraBody Function() body,
  }) => _attach(session, clock, body);

  /// [session] ended: the run idles until another attaches or its time
  /// runs out.
  void detach(GrSession session) => _detach(session);

  /// The environment is done: ends the run.
  void close() => _close();
}
