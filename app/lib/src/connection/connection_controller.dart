import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../data/cameras.dart';
import '../data/settings.dart';
import '../services.dart';

enum ConnectionStatus {
  /// No session (never connected, or ended by switching or forgetting the
  /// camera).
  offline,

  /// [ConnectionController.step] says which link is being set up.
  connecting,

  /// Linked over Bluetooth; the camera's Wi-Fi is not in use.
  bluetooth,

  /// Wi-Fi and HTTP are up; [ConnectionController.http] is usable.
  connected,

  /// The Bluetooth link could not be made, or was lost for good.
  failed,
}

/// The two links of a connection, in the order they come up.
enum ConnectStep { bluetooth, wifi }

enum ConnectFailureKind {
  bluetoothOff,
  bluetoothDenied,

  /// The camera did not answer over Bluetooth (out of range, battery empty,
  /// Bluetooth off in the camera's Action Mode).
  unreachable,

  /// The camera refused this phone's bond; only pairing again recovers.
  needsPairing,

  /// The camera is off and turning it on when connecting is switched off
  /// in Settings.
  cameraOff,

  /// The camera's Wi-Fi could not be joined or verified, or it was lost.
  wifi,

  /// The user chose not to join the camera's Wi-Fi (GR Lab's explanation or
  /// the OS prompt). Only the user asking again continues.
  wifiDeclined,
}

@immutable
final class ConnectFailure {
  const ConnectFailure(
    this.kind,
    this.message, {
    this.step,
    this.cause,
    this.lost = false,
  });

  final ConnectFailureKind kind;
  final String message;

  /// The link that failed.
  final ConnectStep? step;
  final Object? cause;

  /// The link had been up and was lost (mock `b-home-lost`), rather than an
  /// attempt that never got through.
  final bool lost;

  ConnectFailure _asLost() =>
      ConnectFailure(kind, message, step: step, cause: cause, lost: true);

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

/// One [GrSession] for the current camera, in two stages. Bluetooth
/// ([connect]) is meant to run by itself whenever a camera is current; the
/// camera's Wi-Fi ([openLibrary]) is joined only when the user opens the
/// Library, and [closeLibrary] leaves it again while Bluetooth stays.
///
/// The session's BLE reconnect runs underneath and shows as
/// [reconnecting]. When the camera's Wi-Fi is lost the app goes back to
/// the Cameras screen; it never rejoins by itself, except that a join that
/// failed because the app was in the background is tried again on return
/// ([AppServices.redialDelays]), since the OS only joins camera networks
/// for the app in front.
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
  bool _reconnecting = false;
  ConnectFailure? _failure;
  GrSession? _session;
  StreamSubscription<GrSessionEvent>? _events;
  String? _cameraSerial;

  /// The session's BLE reconnect gave up; the link will not come back.
  bool _bleGaveUp = false;

  /// Bumped for every session; events and results of older ones are
  /// dropped.
  int _generation = 0;

  /// Bumped for every Wi-Fi start and [closeLibrary].
  int _wifiRun = 0;
  final _connected = StreamController<GrHttpClient>.broadcast();
  Future<void> _closing = Future.value();
  Future<void> _stoppingWifi = Future.value();

  bool _foreground = true;
  int _redials = 0;
  Timer? _redialTimer;
  bool _redialOnResume = false;

  WifiConsentRequest? _consent;
  Completer<bool>? _consentAnswer;

  ConnectionStatus get status => _status;

  /// The link being set up while [status] is connecting.
  ConnectStep? get step => _step;

  /// Getting a lost link back: Bluetooth while [status] is bluetooth, the
  /// camera's Wi-Fi while the Library is open.
  bool get reconnecting => _reconnecting;

  /// Why the last attempt failed. Set with [ConnectionStatus.failed] for
  /// Bluetooth, and next to [ConnectionStatus.bluetooth] when only the
  /// Wi-Fi failed.
  ConnectFailure? get failure => _failure;

  /// Wi-Fi is up: the app shows the camera's Library rather than the
  /// Cameras screen.
  bool get inSession => _status == ConnectionStatus.connected;

  /// A Library request failed: asks the camera once whether its Wi-Fi
  /// still works; when it does not, the app returns to the Cameras screen
  /// (through the session's `wifi.lost`). True while the camera answers.
  Future<bool> checkWifi() async {
    final session = _session;
    if (session == null || _status != ConnectionStatus.connected) {
      return false;
    }
    return session.checkWifi();
  }

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

  /// The camera network's name, once the session has read it.
  String? get ssid => _session?.credentials?.ssid;

  /// Emits the HTTP client every time the Wi-Fi link comes up.
  Stream<GrHttpClient> get onConnected => _connected.stream;

  /// Whether the app is in front. A quiet rejoin that comes due in the
  /// background waits until this turns true again, and a camera that could
  /// not be reached over Bluetooth is tried again on return.
  bool get foreground => _foreground;
  set foreground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) return;
    if (_redialOnResume) {
      _redialOnResume = false;
      _redials = 0;
      unawaited(_startWifi(quiet: true));
    } else if (_status == ConnectionStatus.failed &&
        _failure?.kind == ConnectFailureKind.unreachable) {
      unawaited(connect());
    }
  }

  /// Links [camera] over Bluetooth. Does nothing unless offline or failed.
  /// Completes when the attempt ends; check [status].
  Future<void> connect() {
    if (_status != ConnectionStatus.offline &&
        _status != ConnectionStatus.failed) {
      return Future.value();
    }
    return _connectBluetooth();
  }

  /// Makes the paired camera [serial] the current one and links it;
  /// changing the current camera ends any attempt or session with the
  /// previous one.
  Future<void> connectTo(String serial) async {
    if (cameras.current?.serial != serial) await cameras.select(serial);
    return connect();
  }

  /// Joins the camera's Wi-Fi so the Library can open, linking Bluetooth
  /// first when needed. Does nothing while Wi-Fi is up or being joined,
  /// except that it cuts short the wait before a quiet rejoin.
  Future<void> openLibrary() async {
    final waitingToRedial = _redialTimer != null || _redialOnResume;
    if (_status == ConnectionStatus.connected ||
        (_status == ConnectionStatus.connecting &&
            _step == ConnectStep.wifi &&
            !waitingToRedial)) {
      return;
    }
    if (_status == ConnectionStatus.connecting &&
        _step == ConnectStep.bluetooth) {
      return;
    }
    if (_status == ConnectionStatus.offline ||
        _status == ConnectionStatus.failed) {
      await connect();
      if (_status != ConnectionStatus.bluetooth) return;
    }
    _cancelRedial();
    _redials = 0;
    return _startWifi(quiet: false);
  }

  /// Leaves the camera's Wi-Fi, or stops joining it, and keeps Bluetooth;
  /// the app returns to the Cameras screen.
  Future<void> closeLibrary() async {
    final session = _session;
    final onWifi =
        _status == ConnectionStatus.connected ||
        (_status == ConnectionStatus.connecting && _step == ConnectStep.wifi);
    if (session == null || !onWifi) return;
    _wifiRun++;
    _cancelRedial();
    _declineConsent();
    _status = ConnectionStatus.bluetooth;
    _step = null;
    _reconnecting = false;
    _failure = null;
    notifyListeners();
    final stopping = _stoppingWifi = session.stopWifi();
    await stopping;
    if (_bleGaveUp && identical(session, _session)) await _relinkLater();
  }

  /// Answers [wifiConsent]: join the camera network, or not now.
  void answerWifiConsent(bool join) {
    final answer = _consentAnswer;
    _consentAnswer = null;
    _consent = null;
    notifyListeners();
    if (answer != null && !answer.isCompleted) answer.complete(join);
  }

  Future<void> _connectBluetooth() async {
    final target = camera;
    if (target == null) return;
    final generation = ++_generation;
    _failure = null;
    _reconnecting = false;
    _bleGaveUp = false;
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
          step: ConnectStep.bluetooth,
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
          step: ConnectStep.bluetooth,
        ),
      );
    }
    if (adapter == BleAdapterState.unauthorized) {
      return _fail(
        generation,
        const ConnectFailure(
          ConnectFailureKind.bluetoothDenied,
          'Bluetooth permission was denied',
          step: ConnectStep.bluetooth,
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
    _events = session.events.listen((e) {
      // One line per step in the device log (logcat tag `flutter`), the
      // only record of what a real camera did when connecting fails.
      debugPrint(
        'gr.session ${jsonEncode(e.toJson(), toEncodable: (o) => '$o')}',
      );
      _onEvent(generation, e);
    });
    try {
      await session.connectBluetooth(
        deviceId: target.paired.deviceId,
        serial: target.serial,
      );
    } on Object catch (e) {
      if (generation != _generation) return;
      await _closeSession();
      return _fail(
        generation,
        e is GrSessionException
            ? _failureFor(e, ConnectStep.bluetooth)
            : ConnectFailure(
                ConnectFailureKind.unreachable,
                '$e',
                step: ConnectStep.bluetooth,
                cause: e,
              ),
      );
    }
    if (generation != _generation) return;
    _status = ConnectionStatus.bluetooth;
    _step = null;
    notifyListeners();
  }

  Future<void> _startWifi({required bool quiet}) async {
    final session = _session;
    if (session == null) return;
    final generation = _generation;
    final run = ++_wifiRun;
    bool stale() => generation != _generation || run != _wifiRun;
    _failure = null;
    _reconnecting = quiet;
    _status = ConnectionStatus.connecting;
    _step = ConnectStep.wifi;
    notifyListeners();

    // A lost link is still being released before the rejoin.
    await _stoppingWifi;
    if (stale()) return;
    try {
      await session.startWifi(powerOn: settings.powerOnWhenConnecting);
    } on Object catch (e) {
      if (stale()) return;
      return _wifiFailed(
        e is GrSessionException
            ? _failureFor(e, ConnectStep.wifi)
            : ConnectFailure(
                ConnectFailureKind.wifi,
                '$e',
                step: ConnectStep.wifi,
                cause: e,
              ),
      );
    }
    if (stale()) return;
    _status = ConnectionStatus.connected;
    _step = null;
    _reconnecting = false;
    _redials = 0;
    notifyListeners();
    final http = session.http;
    if (http != null) _connected.add(http);
  }

  /// Ends the session or cancels an attempt; used when the current camera
  /// changes or is forgotten. The state goes offline at once so a
  /// [connect] issued in the same tick (switching cameras) starts a new
  /// attempt instead of seeing the old one.
  Future<void> disconnect() {
    _generation++;
    _wifiRun++;
    _cancelRedial();
    _status = ConnectionStatus.offline;
    _step = null;
    _reconnecting = false;
    _declineConsent();
    final closing = _closing = _closeSession();
    notifyListeners();
    return closing;
  }

  /// Clears a failure so the camera's card returns to its idle state.
  void dismissFailure() {
    if (_failure == null) return;
    if (_status == ConnectionStatus.failed) _status = ConnectionStatus.offline;
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
    switch (e.kind) {
      case 'ble.lost' when _status == ConnectionStatus.bluetooth:
        _reconnecting = true;
      case 'ble.restored' when _status == ConnectionStatus.bluetooth:
        _reconnecting = false;
      case 'ble.gaveUp' || 'ble.needsPairing':
        _bleGaveUp = true;
        // With the Library open, Wi-Fi carries on without Bluetooth; the
        // link is dealt with when the Library closes.
        if (_status == ConnectionStatus.bluetooth) {
          _closing = _closeSession();
          return _fail(
            generation,
            ConnectFailure(
              e.kind == 'ble.needsPairing'
                  ? ConnectFailureKind.needsPairing
                  : ConnectFailureKind.unreachable,
              'Lost the Bluetooth link',
              step: ConnectStep.bluetooth,
            )._asLost(),
          );
        }
      case 'wifi.lost':
        return _wifiDropped();
    }
    notifyListeners();
  }

  /// The camera's Wi-Fi is gone (the phone left it, or the camera turned
  /// it off or went out of range): back to the Cameras screen on
  /// Bluetooth with a note. Joining again is the user's call, through the
  /// card's Library button.
  void _wifiDropped() {
    final session = _session;
    if (session == null || _status != ConnectionStatus.connected) return;
    _wifiRun++;
    _status = ConnectionStatus.bluetooth;
    _step = null;
    _reconnecting = false;
    _failure = session.cameraOff
        ? null
        : const ConnectFailure(
            ConnectFailureKind.wifi,
            "Lost the camera's Wi-Fi",
            step: ConnectStep.wifi,
            lost: true,
          );
    notifyListeners();
    final stopping = _stoppingWifi = session.stopWifi();
    if (_bleGaveUp) {
      unawaited(
        stopping.then((_) {
          if (identical(session, _session)) return _relinkLater();
        }),
      );
    }
  }

  ConnectFailure _failureFor(GrSessionException e, ConnectStep step) {
    final kind = e.needsPairing
        ? ConnectFailureKind.needsPairing
        : e.wifiDeclined
        ? ConnectFailureKind.wifiDeclined
        : e.cameraOff
        ? ConnectFailureKind.cameraOff
        : step == ConnectStep.bluetooth
        ? ConnectFailureKind.unreachable
        : ConnectFailureKind.wifi;
    return ConnectFailure(kind, e.message, step: step, cause: e);
  }

  /// A Wi-Fi start failed: tries again quietly when the join failed
  /// because the app was in the background (or a quiet retry failed
  /// again); otherwise shows [failure] next to the Bluetooth link.
  void _wifiFailed(ConnectFailure failure) {
    final transient =
        failure.kind == ConnectFailureKind.wifi ||
        failure.kind == ConnectFailureKind.unreachable;
    final redial =
        transient &&
        (_reconnecting ||
            (!_foreground && failure.kind == ConnectFailureKind.wifi));
    if (redial && _scheduleRedial()) return;
    _failure = failure;
    _step = null;
    _reconnecting = false;
    _status = ConnectionStatus.bluetooth;
    notifyListeners();
    if (_bleGaveUp) unawaited(_relinkLater());
  }

  /// Bluetooth went for good while Wi-Fi was in use: end the session so the
  /// camera can be linked again.
  Future<void> _relinkLater() async {
    _generation++;
    _status = ConnectionStatus.failed;
    _failure ??= const ConnectFailure(
      ConnectFailureKind.unreachable,
      'Lost the Bluetooth link',
      step: ConnectStep.bluetooth,
      lost: true,
    );
    notifyListeners();
    await (_closing = _closeSession());
  }

  /// Shows a quiet rejoin as pending; false when the tries are used up.
  bool _scheduleRedial() {
    if (_foreground && _redials >= services.redialDelays.length) return false;
    final generation = _generation;
    _status = ConnectionStatus.connecting;
    _step = ConnectStep.wifi;
    _reconnecting = true;
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
      unawaited(_startWifi(quiet: true));
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
    _bleGaveUp = false;
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

  @override
  Stream<void> get lost => _inner.lost;
}
