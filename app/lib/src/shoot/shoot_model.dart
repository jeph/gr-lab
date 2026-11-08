import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../connection/connection_controller.dart';
import '../data/settings.dart';
import 'live_view_controller.dart';
import 'shoot_format.dart';

/// Whether the camera can take a picture from the app.
enum ShootPower {
  /// Not linked yet, or not asked to turn on yet.
  idle,

  /// Turning on, or switching to shooting (Operation Mode capture).
  waking,

  /// On and in shooting mode.
  ready,

  /// Switched off after it was on; turning it on again is the user's call.
  off,

  /// Turning it on failed; [ShootModel.powerError] says why.
  failed,
}

/// The Shoot tab's state for one visit to the camera's pages: the camera
/// turned on in shooting mode over Bluetooth, its readouts, the shutter,
/// self-timer and drive (mock `b-remote`), and [liveView].
///
/// Like GR WORLD's Remote button (power-on-grworld.md §1.2, 0xe4d738),
/// showing Shoot turns an off camera on in capture mode, or switches a
/// camera that is on to capture. Every readout and control is BLE
/// (ble.md, Camera Control and Camera State services); the shutter is
/// Operation Request `01 01` (release with AF), in live view too.
final class ShootModel extends ChangeNotifier {
  ShootModel({required this.connection, required this.settings})
    : liveView = LiveViewController(connection: connection) {
    connection.addListener(_sync);
    _sync();
  }

  final ConnectionController connection;
  final SettingsController settings;
  final LiveViewController liveView;

  final _messages = StreamController<String>.broadcast();

  GrSession? _session;
  StreamSubscription<GrSessionEvent>? _events;
  StreamSubscription<GrBleNotification<Object>>? _watch;
  bool _visible = false;
  bool _disposed = false;
  int _wakeRun = 0;

  ShootPower _power = ShootPower.idle;
  String? _powerError;
  BleShootingMode? _exposure;
  int? _battery;
  int? _shotsLeft;
  BleEnumValue<BleDriveMode>? _drive;
  bool _capturing = false;
  DateTime? _countdownEnds;
  Duration? _countdown;

  /// Short notes for a snack bar: a shutter or setting the camera refused.
  Stream<String> get messages => _messages.stream;

  ShootPower get power => _power;
  String? get powerError => _powerError;

  /// Mode dial position, from Shooting Mode.
  BleShootingMode? get exposure => _exposure;

  /// Battery percent, from Battery Level.
  int? get battery => _battery;

  /// Pictures that fit on the storage in use, from Storage Information.
  int? get shotsLeft => _shotsLeft;

  /// Drive Mode as the camera reports it.
  BleEnumValue<BleDriveMode>? get drive => _drive;

  /// [drive] split into drive and self-timer; null when unknown or outside
  /// the GR III/IV table.
  (ShootDrive, ShootTimer)? get driveAndTimer =>
      ShootDrive.split(_drive?.known);

  /// The camera is taking a picture (Capture Status byte 0).
  bool get capturing => _capturing;

  /// When a running self-timer fires, and its full length; null when no
  /// countdown runs (Capture Status byte 1).
  DateTime? get countdownEnds => _countdownEnds;
  Duration? get countdown => _countdown;

  /// The shutter can be pressed: the camera is on in shooting mode and the
  /// Bluetooth link is up.
  bool get canShoot =>
      _power == ShootPower.ready && connection.session?.ble != null;

  ShootMode get mode => settings.shootMode;
  set mode(ShootMode value) {
    if (settings.shootMode == value) return;
    settings.shootMode = value;
    _updateLiveView();
    // Back to Remote turns the camera's Wi-Fi off (mock `b-shoot`); the
    // Library joins it again when opened.
    if (value == ShootMode.remote && _visible) {
      unawaited(connection.leaveWifi());
    }
    notifyListeners();
  }

  /// Whether the Shoot tab is showing. Showing it turns the camera on (once
  /// per visit) and watches its readouts; hiding it stops watching them and
  /// stops live view.
  bool get visible => _visible;
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    if (value && _power == ShootPower.ready) {
      _subscribe();
    } else if (!value) {
      _unsubscribe();
    }
    _updateLiveView();
    _sync();
  }

  /// Turns the camera on again after it was switched off, or after a
  /// failed attempt.
  void turnOn() {
    if (_power != ShootPower.off && _power != ShootPower.failed) return;
    _power = ShootPower.idle;
    _sync();
  }

  /// Releases the shutter, or cancels a running self-timer.
  Future<void> shutter() async {
    final ble = connection.session?.ble;
    if (!canShoot || ble == null) return;
    try {
      if (_countdownEnds != null) {
        // GR WORLD's 1-byte cancel (0xe61dd8); the camera ends the
        // countdown and Capture Status reports it.
        await ble.cancelSelfTimer(BleSelfTimerCancelFormat.grWorld);
      } else {
        await ble.shutter();
      }
    } on Object catch (e) {
      _say("The camera didn't take the picture ($e)");
    }
  }

  /// Sets the self-timer, keeping the drive.
  Future<void> setTimer(ShootTimer timer) {
    final drive = driveAndTimer?.$1 ?? ShootDrive.single;
    return _setDrive(drive.withTimer(timer));
  }

  /// Sets the drive, keeping the self-timer where the drive has one.
  Future<void> setDrive(ShootDrive drive) {
    final timer = driveAndTimer?.$2 ?? ShootTimer.off;
    return _setDrive(drive.withTimer(timer));
  }

  Future<void> _setDrive(BleDriveMode mode) async {
    final ble = connection.session?.ble;
    if (ble == null || _drive?.known == mode) return;
    final before = _drive;
    _drive = BleEnumValue.of(mode);
    notifyListeners();
    try {
      await ble.setDriveMode(mode);
    } on Object catch (e) {
      if (_disposed) return;
      _drive = before;
      notifyListeners();
      _say("The camera didn't change the drive mode ($e)");
    }
  }

  void _say(String message) {
    if (!_disposed) _messages.add(message);
  }

  void _sync() {
    if (_disposed) return;
    final session = connection.session;
    if (!identical(session, _session)) _attach(session);
    final linked =
        session != null &&
        (connection.status == ConnectionStatus.bluetooth ||
            connection.status == ConnectionStatus.connected);
    if (_power == ShootPower.ready && connection.cameraOff) {
      // Switched off with its power button, or by the session after a
      // failed Wi-Fi recovery.
      _power = ShootPower.off;
      _unsubscribe();
      _clearCapture();
    }
    if (_visible && linked && _power == ShootPower.idle) {
      unawaited(_wake(session));
    }
    _updateLiveView();
    notifyListeners();
  }

  /// A new session (or none): everything learned about the camera is gone.
  void _attach(GrSession? session) {
    _session = session;
    _wakeRun++;
    unawaited(_events?.cancel());
    _events = null;
    _unsubscribe();
    _power = ShootPower.idle;
    _powerError = null;
    _exposure = null;
    _battery = null;
    _shotsLeft = null;
    _drive = null;
    _clearCapture();
    if (session == null) return;
    _events = session.events.listen((e) {
      // Every (re)link after the wake: notifications are per link.
      if (e.kind == 'ble.ready' && _power == ShootPower.ready && _visible) {
        _subscribe();
      }
    });
  }

  Future<void> _wake(GrSession session) async {
    final run = ++_wakeRun;
    _power = ShootPower.waking;
    _powerError = null;
    notifyListeners();
    try {
      await session.wake(BleOperationMode.capture);
    } on Object catch (e) {
      if (_disposed || run != _wakeRun) return;
      _power = ShootPower.failed;
      _powerError = e is GrSessionException ? e.message : '$e';
      notifyListeners();
      return;
    }
    if (_disposed || run != _wakeRun) return;
    _power = ShootPower.ready;
    if (_visible) _subscribe();
    _updateLiveView();
    notifyListeners();
  }

  static final _watched = <GrBleCharacteristic<Object>>[
    GrBleCatalog.captureStatus,
    GrBleCatalog.shootingMode,
    GrBleCatalog.driveMode,
    GrBleCatalog.batteryLevel,
    GrBleCatalog.storageInformation,
  ];

  void _subscribe() {
    _unsubscribe();
    final ble = connection.session?.ble;
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
          liveView.modeChanged();
        }
      case BleBatteryLevel():
        _battery = value.level < 0 ? null : value.level;
      case BleStorageInformation():
        _shotsLeft = _remaining(value);
      case BleEnumValue<BleDriveMode>():
        _drive = value;
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
      // self-timer it was set to gives the length.
      final length = driveAndTimer?.$2.delay ?? const Duration(seconds: 10);
      _countdown = length;
      _countdownEnds = DateTime.now().add(length);
    }
  }

  static bool _sameMode(BleShootingMode a, BleShootingMode b) =>
      a.mode.raw == b.mode.raw && a.userMode.raw == b.userMode.raw;

  void _clearCapture() {
    _capturing = false;
    _countdownEnds = null;
    _countdown = null;
  }

  /// The storage pictures go to: the one marked active, else the first
  /// usable one.
  static int? _remaining(BleStorageInformation info) {
    final entries = info.entries;
    for (final e in entries) {
      if (e.active == true) return e.remainingPictures;
    }
    for (final e in entries) {
      if (e.exists && e.available) return e.remainingPictures;
    }
    return null;
  }

  /// Live view waits for the camera to be on in shooting mode: the wake
  /// and a Wi-Fi join must not overlap.
  void _updateLiveView() {
    liveView.wanted =
        _visible && mode == ShootMode.liveView && _power == ShootPower.ready;
  }

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_sync);
    unawaited(_events?.cancel());
    _unsubscribe();
    liveView.dispose();
    unawaited(_messages.close());
    super.dispose();
  }
}
