import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Keeps a camera's clock on the phone's time over Bluetooth, for one
/// session.
///
/// The camera's clock has no time zone: it holds local time, and both of
/// Ricoh's apps write the phone's local time to it (ble.md §Date/time
/// sync). GR WORLD writes it on every connect when its option is on;
/// GR Photo reads it first and writes only when it is off by
/// `GeotagOptions.clockTolerance` or more \[design\], because a GR IV
/// clears the location it holds whenever its clock changes
/// (research/protocol/geotagging.md §1.3). It compares when the camera is
/// linked and on, every `GeotagOptions.clockRecheck` while it stays so, and
/// at once when the phone's time zone changes.
///
/// It runs while [enabled] is set, or live geotagging is on (which needs
/// the time and place in a picture to agree).
final class CameraClock extends ChangeNotifier {
  new _(this._session, this._camera) {
    _events = _session.events.listen((e) {
      if (e.kind.startsWith('ble.') || e.kind.startsWith('power.')) _update();
    });
  }

  final GrSession _session;
  final GrCameraEnvironment _camera;
  late final StreamSubscription<GrSessionEvent> _events;
  final _written = StreamController<void>.broadcast();
  Timer? _watch;
  bool _closed = false;
  bool _enabled = false;
  bool _required = false;
  bool _checking = false;

  /// The link the clock was last compared on; a new one is compared again.
  GrBleClient? _checkedLink;
  DateTime? _checkedAt;
  Duration? _zone;
  Duration? _offset;

  /// The user's option: set the camera's clock from the phone.
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_closed || _enabled == value) return;
    _enabled = value;
    _camera.event('clock.enabled', {'enabled': value});
    _update();
  }

  /// How far the camera's clock was from the phone's when last compared
  /// (camera minus phone), before any write; null until compared. A camera
  /// in step reads up to a second behind, as it has no fractions.
  Duration? get offset => _offset;

  bool get _active => !_closed && (_enabled || _required);

  bool get _reachable => _session.ble != null && !_session.cameraOff;

  /// Starts or stops watching, and compares on a link not compared yet.
  void _update() {
    if (!_active || !_reachable) {
      _watch?.cancel();
      _watch = null;
      if (_session.ble == null) _checkedLink = null;
      return;
    }
    _watch ??= Timer.periodic(_camera.geotagOptions.clockWatch, (_) => _tick());
    if (!identical(_checkedLink, _session.ble)) unawaited(_check('linked'));
  }

  void _tick() {
    final zone = DateTime.now().timeZoneOffset;
    final checkedAt = _checkedAt;
    if (_zone != null && zone != _zone) {
      unawaited(_check('zoneChanged'));
    } else if (checkedAt == null ||
        DateTime.now().difference(checkedAt) >=
            _camera.geotagOptions.clockRecheck) {
      unawaited(_check('recheck'));
    }
  }

  /// Reads the camera's clock and sets it when it is off.
  Future<void> _check(String reason) async {
    final ble = _session.ble;
    if (_checking || !_active || ble == null || _session.cameraOff) return;
    if (ble.isPresent(GrBleCatalog.dateTime) == false) return;
    _checking = true;
    _checkedLink = ble;
    try {
      final read = await ble.read(GrBleCatalog.dateTime);
      final now = DateTime.now();
      final cameraTime = read.value?.toLocalDateTime();
      final offset = cameraTime?.difference(now);
      _checkedAt = now;
      _zone = now.timeZoneOffset;
      if (offset != _offset) {
        _offset = offset;
        if (!_closed) notifyListeners();
      }
      final inStep =
          offset != null && offset.abs() < _camera.geotagOptions.clockTolerance;
      _camera.event('clock.compared', {
        'reason': reason,
        'camera': read.value?.iso,
        'phone': now.toIso8601String(),
        'offsetMs': offset?.inMilliseconds,
        'inStep': inStep,
      });
      if (inStep) return;
      // The camera takes whole seconds: written as one begins, its clock
      // is within the write's round trip of the phone's.
      await Future<void>.delayed(
        Duration(milliseconds: 1000 - DateTime.now().millisecond),
      );
      if (!_active || !identical(_session.ble, ble)) return;
      final written = await ble.syncDateTime();
      _camera.event('clock.set', {'reason': reason, 'to': written.iso});
      if (!_closed) _written.add(null);
    } on Object catch (e) {
      // Compared again on the next link or recheck.
      _camera.event('clock.failed', {'reason': reason, 'error': '$e'});
    } finally {
      _checking = false;
    }
  }

  void _close() {
    _closed = true;
    _watch?.cancel();
    unawaited(_events.cancel());
    unawaited(_written.close());
  }
}

/// Creates the clock of [session]. Used by `CameraSession` only.
CameraClock createCameraClock(GrSession session, GrCameraEnvironment camera) =>
    CameraClock._(session, camera);

/// What the camera layer does to a session's clock. Not exported.
extension CameraClockInternals on CameraClock {
  /// Live geotagging is on, which needs the clock in step whatever the
  /// user's option says.
  set requiredByGeotagging(bool value) {
    if (_closed || _required == value) return;
    _required = value;
    _update();
  }

  /// Emits after each write of the camera's clock.
  Stream<void> get written => _written.stream;

  /// The session ended: stops comparing.
  void close() => _close();
}
