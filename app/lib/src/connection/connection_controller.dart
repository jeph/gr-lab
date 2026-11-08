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
  /// verified, or it was lost and every quiet reconnect failed.
  wifi,

  /// The user chose not to join the camera's Wi-Fi (GR Lab's explanation or
  /// the OS prompt). Only the user asking again continues.
  wifiDeclined,
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

/// A join waiting for the user to agree to the camera network; answered
/// with [ConnectionController.answerWifiConsent].
@immutable
final class WifiConsentRequest {
  const WifiConsentRequest({required this.ssid, required this.cameraName});

  final String ssid;
  final String cameraName;
}

/// One [GrSession] for the current camera, exposed as the states the camera
/// pill and connecting sheet draw. Connecting is explicit ([connect]); the
/// session's own recovery (BLE reconnect, Wi-Fi rejoin) runs underneath and
/// shows as [reconnecting]. When that recovery gives up, the controller
/// reconnects quietly a few times ([AppServices.redialDelays]), waiting
/// while the app is in the background, since the OS only joins camera
/// networks for the app in front.
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

  bool _foreground = true;
  int _redials = 0;
  Timer? _redialTimer;
  bool _redialOnResume = false;

  WifiConsentRequest? _consent;
  Completer<bool>? _consentAnswer;

  ConnectionStatus get status => _status;

  /// The step in progress while [status] is connecting.
  ConnectStep? get step => _step;

  /// The camera was off and is being (or was) woken during this attempt.
  bool get waking => _waking;

  /// Rejoining after the camera's Wi-Fi was lost: the session's recovery
  /// while [status] is connected, or a quiet reconnect while connecting.
  bool get reconnecting => _reconnecting;
  ConnectFailure? get failure => _failure;

  /// Non-null while a join waits for the user to agree to the camera
  /// network (see [AppServices.askBeforeWifiJoin]).
  WifiConsentRequest? get wifiConsent => _consent;

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

  /// Whether the app is in front. A quiet reconnect that comes due in the
  /// background waits until this turns true again.
  bool get foreground => _foreground;
  set foreground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (value && _redialOnResume) {
      _redialOnResume = false;
      _redials = 0;
      unawaited(_connect(quiet: true));
    }
  }

  /// Starts connecting to [camera]. Does nothing while connecting or
  /// connected, except that it cuts short the wait before a quiet
  /// reconnect. Completes when the attempt ends; check [status].
  Future<void> connect() {
    final waitingToRedial = _redialTimer != null || _redialOnResume;
    if (_status == ConnectionStatus.connected ||
        (_status == ConnectionStatus.connecting && !waitingToRedial)) {
      return Future.value();
    }
    _cancelRedial();
    _redials = 0;
    return _connect(quiet: false);
  }

  /// Answers [wifiConsent]: join the camera network, or not now.
  void answerWifiConsent(bool join) {
    final answer = _consentAnswer;
    _consentAnswer = null;
    _consent = null;
    notifyListeners();
    if (answer != null && !answer.isCompleted) answer.complete(join);
  }

  Future<void> _connect({required bool quiet}) async {
    final target = camera;
    if (target == null) return;
    final generation = ++_generation;
    _failure = null;
    _waking = false;
    _reconnecting = quiet;
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
      wifi: _ConsentWifi(
        services.wifi,
        ask: (ssid) => _askWifi(generation, target, ssid),
        joined: () => cameras.markWifiApproved(target.serial),
      ),
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
      return _attemptFailed(generation, _failureFor(e));
    } on Object catch (e) {
      if (generation != _generation) return;
      await _closeSession();
      return _attemptFailed(
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
    _reconnecting = false;
    _redials = 0;
    notifyListeners();
    final http = session.http;
    if (http != null) _connected.add(http);
  }

  /// Ends the session or cancels an attempt; the camera's Wi-Fi is left on.
  /// The state goes offline at once so a [connect] issued in the same tick
  /// (switching cameras) starts a new attempt instead of seeing the old one.
  Future<void> disconnect() {
    _generation++;
    _cancelRedial();
    _status = ConnectionStatus.offline;
    _step = null;
    _reconnecting = false;
    _declineConsent();
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

  Future<bool> _askWifi(int generation, SavedCamera target, String ssid) {
    if (!services.askBeforeWifiJoin) return Future.value(true);
    final current = cameras.cameras.where((c) => c.serial == target.serial);
    if (current.isNotEmpty && current.first.wifiApproved) {
      return Future.value(true);
    }
    if (generation != _generation) return Future.value(false);
    _declineConsent();
    final answer = _consentAnswer = Completer<bool>();
    _consent = WifiConsentRequest(ssid: ssid, cameraName: target.name);
    notifyListeners();
    return answer.future;
  }

  void _declineConsent() {
    final answer = _consentAnswer;
    _consentAnswer = null;
    _consent = null;
    if (answer != null && !answer.isCompleted) answer.complete(false);
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
        _closing = _closeSession();
        final declined = e.fields['declined'] == true;
        _attemptFailed(
          generation,
          ConnectFailure(
            declined
                ? ConnectFailureKind.wifiDeclined
                : ConnectFailureKind.wifi,
            declined
                ? "Joining the camera's Wi-Fi was declined"
                : "Lost the camera's Wi-Fi",
            step: ConnectStep.joining,
          ),
          dropped: true,
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
        : e.wifiDeclined
        ? ConnectFailureKind.wifiDeclined
        : switch (step) {
            ConnectStep.bluetooth ||
            ConnectStep.waking => ConnectFailureKind.unreachable,
            ConnectStep.wifiOn ||
            ConnectStep.joining => ConnectFailureKind.wifi,
          };
    return ConnectFailure(kind, e.message, step: step, cause: e);
  }

  /// Ends an attempt (or a dropped connection, [dropped]) that failed:
  /// reconnects quietly when the camera was connected before, or when the
  /// join failed because the app was in the background; otherwise shows
  /// [failure].
  void _attemptFailed(
    int generation,
    ConnectFailure failure, {
    bool dropped = false,
  }) {
    if (generation != _generation) return;
    final transient =
        failure.kind == ConnectFailureKind.wifi ||
        failure.kind == ConnectFailureKind.unreachable;
    final redial =
        transient &&
        (dropped ||
            _reconnecting ||
            (!_foreground && failure.kind == ConnectFailureKind.wifi));
    if (redial && _scheduleRedial(generation)) return;
    _fail(generation, failure);
  }

  /// Shows a quiet reconnect as pending; false when the tries are used up.
  bool _scheduleRedial(int generation) {
    if (_foreground && _redials >= services.redialDelays.length) return false;
    _status = ConnectionStatus.connecting;
    _reconnecting = true;
    _step = null;
    _failure = null;
    notifyListeners();
    if (!_foreground) {
      _redialOnResume = true;
      return true;
    }
    final delay = services.redialDelays[_redials++];
    _redialTimer = Timer(delay, () {
      _redialTimer = null;
      if (generation != _generation) return;
      if (!_foreground) {
        _redialOnResume = true;
        return;
      }
      unawaited(_connect(quiet: true));
    });
    return true;
  }

  void _cancelRedial() {
    _redialTimer?.cancel();
    _redialTimer = null;
    _redialOnResume = false;
  }

  void _fail(int generation, ConnectFailure failure) {
    if (generation != _generation) return;
    _status = ConnectionStatus.failed;
    _failure = failure;
    _step = null;
    _reconnecting = false;
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
    _cancelRedial();
    _declineConsent();
    unawaited(_closeSession());
    unawaited(_connected.close());
    super.dispose();
  }
}

/// The platform Wi-Fi control, asking the user first ([ask], once per
/// session: the join loop retries) and recording a successful join
/// ([joined]) so later joins skip the question.
final class _ConsentWifi implements WifiNetworkControl {
  _ConsentWifi(this._inner, {required this.ask, required this.joined});

  final WifiNetworkControl _inner;
  final Future<bool> Function(String ssid) ask;
  final Future<void> Function() joined;
  bool _agreed = false;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
  }) async {
    if (!_agreed) {
      if (!await ask(ssid)) {
        throw const WifiJoinDeclined("not joining the camera's Wi-Fi now");
      }
      _agreed = true;
    }
    await _inner.join(
      ssid: ssid,
      passphrase: passphrase,
      security: security,
      timeout: timeout,
    );
    await joined();
  }

  @override
  Future<String?> currentSsid() => _inner.currentSsid();

  @override
  Future<void> leave() => _inner.leave();
}
