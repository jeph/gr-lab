import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/shoot/live_view_controller.dart';
import 'package:grlab/src/shoot/shoot_format.dart';

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
/// turned on in shooting mode, the session's [CameraRemote] readouts, the
/// shutter, self-timer and drive (mock `b-remote`), and [liveView].
///
/// Like GR WORLD's Remote button, showing Shoot turns an off camera on in
/// capture mode, or switches a camera that is on to capture
/// ([CameraRemote.wake]), once per visit.
final class ShootModel extends ChangeNotifier {
  new({required this.connection, required this.settings})
    : liveView = LiveViewController(connection: connection) {
    connection.addListener(_sync);
    _sync();
  }

  final ConnectionController connection;
  final SettingsController settings;
  final LiveViewController liveView;

  final _messages = StreamController<String>.broadcast();

  CameraSession? _session;
  CameraRemote? _remote;
  bool _visible = false;
  bool _disposed = false;
  int _wakeRun = 0;

  ShootPower _power = ShootPower.idle;
  String? _powerError;

  /// Short notes for a snack bar: a shutter or setting the camera refused.
  Stream<String> get messages => _messages.stream;

  ShootPower get power => _power;
  String? get powerError => _powerError;

  /// Mode dial position, from Shooting Mode.
  BleShootingMode? get exposure => _remote?.exposure;

  /// Battery percent, from Battery Level.
  int? get battery => _remote?.battery;

  /// Pictures that fit on the storage in use, from Storage Information.
  int? get shotsLeft => _remote?.shotsLeft;

  /// Drive Mode as the camera reports it.
  BleEnumValue<BleDriveMode>? get drive => _remote?.drive;

  /// [drive] split into drive and self-timer; null when unknown or outside
  /// the GR III/IV table.
  (ShootDrive, ShootTimer)? get driveAndTimer => ShootDrive.split(drive?.known);

  /// The camera is taking a picture (Capture Status byte 0).
  bool get capturing => _remote?.capturing ?? false;

  /// When a running self-timer fires, and its full length; null when no
  /// countdown runs (Capture Status byte 1).
  DateTime? get countdownEnds => _remote?.countdownEnds;
  Duration? get countdown => _remote?.countdown;

  /// The shutter can be pressed: the camera is on in shooting mode and the
  /// Bluetooth link is up.
  bool get canShoot => _power == ShootPower.ready && linked;

  /// The Bluetooth link to the camera is up.
  bool get linked => _remote?.linked ?? false;

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
    _updateRemote();
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
    final remote = _remote;
    if (!canShoot || remote == null) return;
    try {
      await remote.shutter();
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
    final remote = _remote;
    if (remote == null) return;
    try {
      await remote.setDriveMode(mode);
    } on Object catch (e) {
      _say("The camera didn't change the drive mode ($e)");
    }
  }

  void _say(String message) {
    if (!_disposed) _messages.add(message);
  }

  void _sync() {
    if (_disposed) return;
    final session = connection.cameraSession;
    if (!identical(session, _session)) _attach(session);
    final remote = _remote;
    final linked =
        remote != null &&
        (connection.status == ConnectionStatus.bluetooth ||
            connection.status == ConnectionStatus.connected);
    if (_power == ShootPower.ready && connection.cameraOff) {
      // Switched off with its power button, or by the session after a
      // failed Wi-Fi recovery.
      _power = ShootPower.off;
      _updateRemote();
      remote?.cameraSwitchedOff();
    }
    if (_visible && linked && _power == ShootPower.idle) {
      unawaited(_wake(remote));
    }
    _updateLiveView();
    notifyListeners();
  }

  /// A new session (or none): everything learned about the camera is gone.
  void _attach(CameraSession? session) {
    _session = session;
    _wakeRun++;
    _remote
      ?..removeListener(_onRemote)
      ..watching = false;
    _remote = session?.remote;
    _remote?.addListener(_onRemote);
    _power = ShootPower.idle;
    _powerError = null;
  }

  void _onRemote() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _wake(CameraRemote remote) async {
    final run = ++_wakeRun;
    _power = ShootPower.waking;
    _powerError = null;
    notifyListeners();
    try {
      await remote.wake();
    } on Object catch (e) {
      if (_disposed || run != _wakeRun) return;
      _power = ShootPower.failed;
      _powerError = e is GrSessionException ? e.message : '$e';
      notifyListeners();
      return;
    }
    if (_disposed || run != _wakeRun) return;
    _power = ShootPower.ready;
    _updateRemote();
    _updateLiveView();
    notifyListeners();
  }

  /// The readouts follow the camera while Shoot shows and the camera is on
  /// in shooting mode.
  void _updateRemote() {
    _remote?.watching = _visible && _power == ShootPower.ready;
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
    _remote
      ?..removeListener(_onRemote)
      ..watching = false;
    liveView.dispose();
    unawaited(_messages.close());
    super.dispose();
  }
}
