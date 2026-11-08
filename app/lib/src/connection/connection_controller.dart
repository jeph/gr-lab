import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../data/cameras.dart';
import '../data/settings.dart';
import '../services.dart';

enum ConnectionStatus {
  /// No session (never connected, cancelled or disconnected).
  offline,
  connecting,

  /// Wi-Fi and HTTP are up; [ConnectionController.http] is usable.
  connected,
  failed,
}

/// Steps of the connecting sheet (mock `b-connect`), in order. [waking]
/// only appears when the camera was off.
enum ConnectStep { bluetooth, waking, wifiOn, joining }

enum ConnectFailureKind {
  bluetoothOff,
  bluetoothDenied,

  /// The camera did not answer over Bluetooth (out of range, battery empty,
  /// Bluetooth off in the camera's Action Mode).
  unreachable,

  /// The camera refused this phone's bond; only pairing again recovers.
  needsPairing,

  /// Bluetooth worked but the camera's Wi-Fi could not be joined or
  /// verified, or it was lost and recovery gave up.
  wifi,
}

@immutable
final class ConnectFailure {
  const ConnectFailure(this.kind, this.message, {this.step, this.cause});

  final ConnectFailureKind kind;
  final String message;

  /// The step that failed, when the session got that far.
  final ConnectStep? step;
  final Object? cause;

  @override
  String toString() => 'ConnectFailure(${kind.name}): $message';
}

/// One [GrSession] for the current camera, exposed as the states the camera
/// pill and connecting sheet draw. Connecting is explicit ([connect]); the
/// session's own recovery (BLE reconnect, Wi-Fi rejoin) runs underneath and
/// shows as [reconnecting].
final class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required this.services,
    required this.cameras,
    required this.settings,
  }) {
    cameras.addListener(_onCamerasChanged);
    _cameraSerial = cameras.current?.serial;
  }

  final AppServices services;
  final CameraStore cameras;
  final SettingsController settings;

  ConnectionStatus _status = ConnectionStatus.offline;
  ConnectStep? _step;
  bool _waking = false;
  bool _reconnecting = false;
  ConnectFailure? _failure;
  GrSession? _session;
  StreamSubscription<GrSessionEvent>? _events;
  String? _cameraSerial;
  int _generation = 0;
  final _connected = StreamController<GrHttpClient>.broadcast();
  Future<void> _closing = Future.value();

  ConnectionStatus get status => _status;

  /// The step in progress while [status] is connecting.
  ConnectStep? get step => _step;

  /// The camera was off and is being (or was) woken during this attempt.
  bool get waking => _waking;

  /// Connected, but the session is rejoining Wi-Fi after losing it.
  bool get reconnecting => _reconnecting;
  ConnectFailure? get failure => _failure;

  /// The camera this controller connects to.
  SavedCamera? get camera => cameras.current;

  GrSession? get session => _session;

  /// Non-null while [status] is connected.
  GrHttpClient? get http =>
      _status == ConnectionStatus.connected ? _session?.http : null;

  /// `/v1/props` from the identity check.
  GrProps? get props => _session?.props;

  /// Emits the HTTP client every time a connection completes.
  Stream<GrHttpClient> get onConnected => _connected.stream;

  /// The steps the sheet lists for the current attempt.
  List<ConnectStep> get visibleSteps => [
    for (final s in ConnectStep.values)
      if (s != ConnectStep.waking || _waking) s,
  ];

  /// Starts connecting to [camera]. Does nothing while connecting or
  /// connected. Completes when the attempt ends; check [status].
  Future<void> connect() async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected) {
      return;
    }
    final target = camera;
    if (target == null) return;
    final generation = ++_generation;
    _failure = null;
    _waking = false;
    _reconnecting = false;
    _status = ConnectionStatus.connecting;
    _step = ConnectStep.bluetooth;
    notifyListeners();

    // A disconnect may still be releasing the previous BLE link.
    await _closing;
    if (generation != _generation) return;

    if (!await services.ensureBluetoothPermission()) {
      return _fail(
        generation,
        const ConnectFailure(
          ConnectFailureKind.bluetoothDenied,
          'Bluetooth permission was denied',
        ),
      );
    }
    final adapter = await services.ble.adapterState();
    if (generation != _generation) return;
    if (adapter == BleAdapterState.poweredOff) {
      return _fail(
        generation,
        const ConnectFailure(
          ConnectFailureKind.bluetoothOff,
          'Bluetooth is off',
        ),
      );
    }
    if (adapter == BleAdapterState.unauthorized) {
      return _fail(
        generation,
        const ConnectFailure(
          ConnectFailureKind.bluetoothDenied,
          'Bluetooth permission was denied',
        ),
      );
    }

    final session = GrSession(
      transport: services.ble,
      wifi: services.wifi,
      host: services.cameraHost,
      options: services.sessionOptions,
      httpFactory: services.httpFactory,
    );
    _session = session;
    _events = session.events.listen((e) => _onEvent(generation, e));
    try {
      await session.connect(
        deviceId: target.paired.deviceId,
        serial: target.serial,
        powerOn: settings.powerOnWhenConnecting,
      );
    } on GrSessionException catch (e) {
      if (generation != _generation) return;
      await _closeSession();
      return _fail(generation, _failureFor(e));
    } on Object catch (e) {
      if (generation != _generation) return;
      await _closeSession();
      return _fail(
        generation,
        ConnectFailure(
          ConnectFailureKind.unreachable,
          '$e',
          step: _step,
          cause: e,
        ),
      );
    }
    if (generation != _generation) return;
    _status = ConnectionStatus.connected;
    _step = null;
    notifyListeners();
    final http = session.http;
    if (http != null) _connected.add(http);
  }

  /// Ends the session or cancels an attempt; the camera's Wi-Fi is left on.
  /// The state goes offline at once so a [connect] issued in the same tick
  /// (switching cameras) starts a new attempt instead of seeing the old one.
  Future<void> disconnect() {
    _generation++;
    _status = ConnectionStatus.offline;
    _step = null;
    _reconnecting = false;
    final closing = _closing = _closeSession();
    notifyListeners();
    return closing;
  }

  /// Clears a failure so the pill returns to its idle state.
  void dismissFailure() {
    if (_status != ConnectionStatus.failed) return;
    _status = ConnectionStatus.offline;
    _failure = null;
    notifyListeners();
  }

  void _onEvent(int generation, GrSessionEvent e) {
    if (generation != _generation) return;
    switch (e.phase) {
      case GrSessionPhase.idle ||
          GrSessionPhase.scanning ||
          GrSessionPhase.bleConnecting:
        if (_status == ConnectionStatus.connecting) {
          _step = ConnectStep.bluetooth;
        }
      case GrSessionPhase.waking:
        _waking = true;
        _step = ConnectStep.waking;
      case GrSessionPhase.wlanOn:
        _step = ConnectStep.wifiOn;
      case GrSessionPhase.joining || GrSessionPhase.verifying:
        if (_status == ConnectionStatus.connecting) {
          _step = ConnectStep.joining;
        }
      case GrSessionPhase.connected:
        _reconnecting = false;
      case GrSessionPhase.recovering:
        _reconnecting = true;
      case GrSessionPhase.lost:
        _reconnecting = false;
        unawaited(_closeSession());
        _fail(
          generation,
          const ConnectFailure(
            ConnectFailureKind.wifi,
            "Lost the camera's Wi-Fi",
            step: ConnectStep.joining,
          ),
        );
        return;
      case GrSessionPhase.closed:
        break;
    }
    notifyListeners();
  }

  ConnectFailure _failureFor(GrSessionException e) {
    final step = switch (e.phase) {
      GrSessionPhase.waking => ConnectStep.waking,
      GrSessionPhase.wlanOn => ConnectStep.wifiOn,
      GrSessionPhase.joining ||
      GrSessionPhase.verifying ||
      GrSessionPhase.connected ||
      GrSessionPhase.recovering ||
      GrSessionPhase.lost => ConnectStep.joining,
      _ => ConnectStep.bluetooth,
    };
    final kind = e.needsPairing
        ? ConnectFailureKind.needsPairing
        : switch (step) {
            ConnectStep.bluetooth ||
            ConnectStep.waking => ConnectFailureKind.unreachable,
            ConnectStep.wifiOn ||
            ConnectStep.joining => ConnectFailureKind.wifi,
          };
    return ConnectFailure(kind, e.message, step: step, cause: e);
  }

  void _fail(int generation, ConnectFailure failure) {
    if (generation != _generation) return;
    _status = ConnectionStatus.failed;
    _failure = failure;
    _step = null;
    notifyListeners();
  }

  Future<void> _closeSession() async {
    final session = _session;
    _session = null;
    await _events?.cancel();
    _events = null;
    if (session != null) {
      try {
        await session.close();
      } on Object {
        // Closing a half-open session is best effort.
      }
    }
  }

  void _onCamerasChanged() {
    final serial = cameras.current?.serial;
    if (serial == _cameraSerial) return;
    _cameraSerial = serial;
    _failure = null;
    unawaited(disconnect());
  }

  @override
  void dispose() {
    cameras.removeListener(_onCamerasChanged);
    _generation++;
    unawaited(_closeSession());
    unawaited(_connected.close());
    super.dispose();
  }
}
