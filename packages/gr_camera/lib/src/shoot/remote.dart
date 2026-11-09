import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Remote shooting over Bluetooth for one session (mock `b-remote`): the
/// camera turned on in shooting mode, its readouts, the shutter, the
/// self-timer and the drive mode. Battery and shots left are the
/// session's `CameraStatus`.
///
/// Every readout and control is BLE (ble.md, Camera Control and Camera
/// State services); the shutter is Operation Request `01 01` (release with
/// AF), in live view too. The readouts are those of the session's camera:
/// a new session starts with none.
final class CameraRemote extends ChangeNotifier {
  new _(this._session, this._camera, this._onModeChanged) {
    _events = _session.events.listen((e) {
      // Every (re)link after the wake: notifications are per link.
      if (e.kind == 'ble.ready' && _watching) _subscribe();
    });
  }

  final GrSession _session;
  final GrCameraEnvironment _camera;

  /// Tells the session's live view that the mode dial moved.
  final void Function() _onModeChanged;

  late final StreamSubscription<GrSessionEvent> _events;
  StreamSubscription<GrBleNotification<Object>>? _watch;
  bool _watching = false;
  bool _closed = false;

  BleShootingMode? _exposure;
  BleEnumValue<BleDriveMode>? _reportedDrive;
  BleEnumValue<BleDriveMode>? _pendingDrive;
  int _driveWrites = 0;
  bool _capturing = false;
  DateTime? _countdownEnds;
  Duration? _countdown;

  /// Mode dial position, from Shooting Mode.
  BleShootingMode? get exposure => _exposure;

  /// Drive Mode being written, else as the camera last reported it.
  BleEnumValue<BleDriveMode>? get drive => _pendingDrive ?? _reportedDrive;

  /// The camera is taking a picture (Capture Status byte 0).
  bool get capturing => _capturing;

  /// When a running self-timer fires, and its full length; null when no
  /// countdown runs (Capture Status byte 1).
  DateTime? get countdownEnds => _countdownEnds;

  /// Full length of the running self-timer countdown; null when none runs.
  Duration? get countdown => _countdown;

  /// Turns the camera on in shooting mode, or switches a camera that is on
  /// to shooting (Operation Mode capture), like GR WORLD's Remote button
  /// (power-on-grworld.md §1.2, 0xe4d738). Throws [GrSessionException].
  Future<void> wake() => _session.wake(BleOperationMode.capture);

  /// Whether the readouts follow the camera: Capture Status, Shooting
  /// Mode and Drive Mode notifications, read once when watching starts and
  /// again after every Bluetooth relink.
  bool get watching => _watching;
  set watching(bool value) {
    if (_closed || _watching == value) return;
    _watching = value;
    _camera.event('shoot.remote.watch', {'watching': value});
    if (value) {
      _subscribe();
    } else {
      _unsubscribe();
    }
  }

  /// The camera was switched off: it takes no picture and runs no
  /// countdown any more. The other readouts keep their last values.
  void cameraSwitchedOff() {
    _capturing = false;
    _countdownEnds = null;
    _countdown = null;
    if (!_closed) notifyListeners();
  }

  /// Releases the shutter, or cancels a running self-timer. Throws when
  /// the camera does not take the request; does nothing without a link.
  Future<void> shutter() async {
    final ble = _session.ble;
    if (ble == null) return;
    if (_countdownEnds != null) {
      _camera.event('shoot.remote.cancelSelfTimer');
      // GR WORLD's 1-byte cancel (0xe61dd8); the camera ends the
      // countdown and Capture Status reports it.
      await ble.cancelSelfTimer(BleSelfTimerCancelFormat.grWorld);
    } else {
      await ble.shutter();
    }
  }

  /// Sets Drive Mode (drive and self-timer in one value). [drive] shows
  /// [mode] at once; if the camera refuses it, and no newer write is under
  /// way, [drive] goes back to what the camera reports, and this throws.
  /// Does nothing without a link or when [mode] is set.
  Future<void> setDriveMode(BleDriveMode mode) async {
    final ble = _session.ble;
    if (ble == null || drive?.known == mode) return;
    final value = BleEnumValue.of(mode);
    final write = ++_driveWrites;
    _pendingDrive = value;
    notifyListeners();
    try {
      await ble.setDriveMode(mode);
    } on Object catch (e) {
      _camera.event('shoot.remote.driveRefused', {
        'mode': mode.name,
        'error': '$e',
      });
      if (!_closed && write == _driveWrites) {
        _pendingDrive = null;
        notifyListeners();
      }
      rethrow;
    }
    if (_closed) return;
    // The camera took it; its notification may not have arrived yet. A
    // newer write still under way keeps showing, but if it is refused,
    // this is what the camera has.
    _reportedDrive = value;
    if (write != _driveWrites) return;
    _pendingDrive = null;
    notifyListeners();
  }

  static final _watched = <GrBleCharacteristic<Object>>[
    GrBleCatalog.captureStatus,
    GrBleCatalog.shootingMode,
    GrBleCatalog.driveMode,
  ];

  void _subscribe() {
    _unsubscribe();
    final ble = _session.ble;
    if (ble == null) return;
    final present = [
      for (final c in _watched)
        if (ble.isPresent(c) ?? true) c,
    ];
    _watch = ble
        .watchAll(present, prime: true)
        .listen(_onNotification, onError: (Object _) {});
  }

  void _unsubscribe() {
    unawaited(_watch?.cancel());
    _watch = null;
  }

  void _onNotification(GrBleNotification<Object> n) {
    if (_closed) return;
    final value = n.decoded.value;
    switch (value) {
      case BleCaptureStatus():
        _onCaptureStatus(value);
      case BleShootingMode():
        final before = _exposure;
        _exposure = value;
        // The dial decides which settings can be changed and what their
        // lists offer; the camera may not announce that over Wi-Fi.
        if (before != null && !_sameMode(before, value)) {
          _camera.event('shoot.modeDial', {
            'from': before.mode.raw,
            'to': value.mode.raw,
            'userMode': value.userMode.raw,
          });
          _onModeChanged();
        }
      case BleEnumValue<BleDriveMode>():
        _reportedDrive = value;
      default:
        return;
    }
    notifyListeners();
  }

  void _onCaptureStatus(BleCaptureStatus status) {
    _capturing = status.capturing.known == BleCapturing.capturing;
    final counting = status.countdown.known == BleCountdown.selfTimer;
    if (!counting) {
      _countdownEnds = null;
      _countdown = null;
    } else if (_countdownEnds == null) {
      // The camera says a countdown runs, not how long is left; the
      // self-timer it was set to gives the length, 10 s when that drive
      // mode has none or is unknown.
      final length =
          _reportedDrive?.known?.selfTimer ?? const Duration(seconds: 10);
      _countdown = length;
      _countdownEnds = DateTime.now().add(length);
    }
  }

  static bool _sameMode(BleShootingMode a, BleShootingMode b) =>
      a.mode.raw == b.mode.raw && a.userMode.raw == b.userMode.raw;

  void _close() {
    _closed = true;
    _watching = false;
    unawaited(_events.cancel());
    _unsubscribe();
  }
}

/// Creates the remote of [session]; [onModeChanged] runs when the mode
/// dial moves. Used by `CameraSession` only.
CameraRemote createCameraRemote(
  GrSession session,
  GrCameraEnvironment camera, {
  required void Function() onModeChanged,
}) => CameraRemote._(session, camera, onModeChanged);

/// What `CameraSession` does to its remote. Not exported.
extension CameraRemoteInternals on CameraRemote {
  /// The session ended: stops watching and notifying.
  void close() => _close();
}
