import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../data/cameras.dart';
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

/// The tabs of the camera's pages, opened over the Cameras screen.
enum CameraTab {
  /// Photos on the camera; needs its Wi-Fi.
  library,

  /// Remote over Bluetooth, or live view over Wi-Fi.
  shoot,
}

enum ConnectFailureKind {
  bluetoothOff,
  bluetoothDenied,

  /// The camera did not answer over Bluetooth (out of range, battery empty,
  /// Bluetooth off in the camera's Action Mode).
  unreachable,

  /// The camera refused this phone's bond; only pairing again recovers.
  needsPairing,

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
  const WifiConsentRequest({
    required this.ssid,
    required this.cameraName,
    this.again = false,
  });

  final String ssid;
  final String cameraName;

  /// Android showed its network list during a join of a camera network it
  /// had approved before, and the join failed: the question explains why
  /// the list came back and offers to try again.
  final bool again;
}

/// One [GrSession] for the current camera, in two stages. Bluetooth
/// ([connect]) is meant to run by itself whenever a camera is current; the
/// camera's Wi-Fi ([joinWifi]) is joined only when the user opens the
/// Library or live view. [openCamera] opens the camera's pages ([tab]) over
/// the Cameras screen, and [closeCamera] leaves them, and the Wi-Fi, while
/// Bluetooth stays.
///
/// The session's BLE reconnect runs underneath and shows as
/// [reconnecting]. When the camera's Wi-Fi is lost, the session gets it
/// back (turning the camera on again when it was switched off) while the
/// pages stay, also shown as [reconnecting]. When that fails with
/// Bluetooth still there, the pages stay and the Library says the Wi-Fi
/// was lost; without Bluetooth the session ends, the app goes back to the
/// Cameras screen and it says the connection was lost. Leaving the camera's
/// pages turns a camera the app turned on back off. A join that
/// failed because the app was in the background is tried again on return
/// ([AppServices.redialDelays]), since the OS only joins camera networks
/// for the app in front.
final class ConnectionController extends ChangeNotifier {
  ConnectionController({required this.services, required this.cameras}) {
    cameras.addListener(_onCamerasChanged);
    _cameraSerial = cameras.current?.serial;
  }

  final AppServices services;
  final CameraStore cameras;

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

  /// Bumped for every Wi-Fi start and [closeCamera].
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
  CameraTab? _tab;

  ConnectionStatus get status => _status;

  /// The tab of the camera's pages, while they are open over the Cameras
  /// screen; null otherwise. Cleared when the session fails or ends.
  CameraTab? get tab => _tab;

  /// The link being set up while [status] is connecting.
  ConnectStep? get step => _step;

  /// Getting a lost link back: Bluetooth while [status] is bluetooth, the
  /// camera's Wi-Fi while the Library is open.
  bool get reconnecting => _reconnecting;

  /// Why the last attempt failed. Set with [ConnectionStatus.failed] for
  /// Bluetooth, and next to [ConnectionStatus.bluetooth] when only the
  /// Wi-Fi failed.
  ConnectFailure? get failure => _failure;

  /// Set when [closeCamera] left the camera's Wi-Fi because the app was
  /// not used for this long (see `IdleDisconnect`); cleared by the next
  /// Wi-Fi start or [disconnect]. The Cameras screen notes it while
  /// Bluetooth stays linked.
  Duration? get idleClosedAfter => _idleClosedAfter;
  Duration? _idleClosedAfter;

  /// Wi-Fi is up, or being got back after a loss ([reconnecting]): the
  /// Library and live view can use [http].
  bool get inSession => _status == ConnectionStatus.connected;

  /// The camera is off (BT-only), or reported turning off.
  bool get cameraOff => _session?.cameraOff ?? false;

  /// A Library request failed: asks the camera once whether its Wi-Fi
  /// still works; when it does not, the session counts the link as lost
  /// and gets it back ([reconnecting]). True while the camera answers.
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

  /// Opens the camera's pages on [tab] (the camera card's buttons). The
  /// Library joins the camera's Wi-Fi ([joinWifi]); Shoot links Bluetooth,
  /// and its Remote needs nothing more.
  Future<void> openCamera(CameraTab tab) {
    _tab = tab;
    notifyListeners();
    return tab == CameraTab.library ? joinWifi() : connect();
  }

  /// Switches the open camera pages to [tab]. The Library joins the
  /// camera's Wi-Fi unless it is up or the last join failed; that failure
  /// is shown with Try again instead.
  void selectTab(CameraTab tab) {
    if (_tab == null || _tab == tab) return;
    _tab = tab;
    notifyListeners();
    if (tab == CameraTab.library &&
        _status == ConnectionStatus.bluetooth &&
        _failure == null) {
      unawaited(joinWifi());
    }
  }

  /// Joins the camera's Wi-Fi for the Library or live view, linking
  /// Bluetooth first when needed. Does nothing while Wi-Fi is up or being
  /// joined, except that it cuts short the wait before a quiet rejoin.
  Future<void> joinWifi() async {
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

  /// Closes the camera's pages and leaves the camera's Wi-Fi, or stops
  /// joining it, keeping Bluetooth; the app returns to the Cameras screen.
  /// A camera the app turned on (for the Library or Shoot) is turned back
  /// off. A Wi-Fi failure shown in the pages is cleared. [idleFor] is set
  /// when the app leaves because it was not used ([idleClosedAfter]).
  Future<void> closeCamera({Duration? idleFor}) {
    final hadTab = _tab != null;
    _tab = null;
    return _leaveWifi(powerOff: true, idleFor: idleFor, changed: hadTab);
  }

  /// Leaves the camera's Wi-Fi, or stops joining it, keeping the camera's
  /// pages open over Bluetooth (live view was switched back to Remote). The
  /// camera stays on. A Wi-Fi failure is cleared.
  Future<void> leaveWifi() => _leaveWifi(powerOff: false);

  Future<void> _leaveWifi({
    required bool powerOff,
    Duration? idleFor,
    bool changed = false,
  }) async {
    final session = _session;
    final onWifi =
        _status == ConnectionStatus.connected ||
        (_status == ConnectionStatus.connecting && _step == ConnectStep.wifi);
    if (session == null || !onWifi) {
      final wifiFailure = _failure?.step == ConnectStep.wifi;
      if (wifiFailure) _failure = null;
      if (changed || wifiFailure) notifyListeners();
      if (powerOff &&
          session != null &&
          _status == ConnectionStatus.bluetooth) {
        await _stoppingWifi;
        if (identical(session, _session)) await session.powerOffIfWoken();
      }
      return;
    }
    _wifiRun++;
    _cancelRedial();
    _declineConsent();
    _status = ConnectionStatus.bluetooth;
    _step = null;
    _reconnecting = false;
    _failure = null;
    _idleClosedAfter = idleFor;
    notifyListeners();
    final stopping = _stoppingWifi = session.stopWifi(
      powerOffIfWoken: powerOff,
    );
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
        approvalShown: services.wifiApprovalShown,
        ask: (ssid) => _askWifi(generation, target, ssid),
        askAgain: (ssid) => _askWifi(generation, target, ssid, again: true),
        cameraApproved: () => _wifiApproved(target),
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
    _idleClosedAfter = null;
    _reconnecting = quiet;
    _status = ConnectionStatus.connecting;
    _step = ConnectStep.wifi;
    notifyListeners();

    // A lost link is still being released before the rejoin.
    await _stoppingWifi;
    if (stale()) return;
    try {
      await session.startWifi();
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
    _tab = null;
    _status = ConnectionStatus.offline;
    _step = null;
    _reconnecting = false;
    _idleClosedAfter = null;
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

  bool _wifiApproved(SavedCamera target) =>
      cameras.cameras.any((c) => c.serial == target.serial && c.wifiApproved);

  Future<bool> _askWifi(
    int generation,
    SavedCamera target,
    String ssid, {
    bool again = false,
  }) {
    if (!services.askBeforeWifiJoin) return Future.value(!again);
    if (!again && _wifiApproved(target)) return Future.value(true);
    if (generation != _generation) return Future.value(false);
    _declineConsent();
    final answer = _consentAnswer = Completer<bool>();
    _consent = WifiConsentRequest(
      ssid: ssid,
      cameraName: target.name,
      again: again,
    );
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
        // The drop after the app turned the camera off is expected.
        _reconnecting = e.fields['afterPowerOff'] != true;
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
      case 'wifi.lost' when _status == ConnectionStatus.connected:
        _reconnecting = true;
      case 'recovery.done' when _status == ConnectionStatus.connected:
        _reconnecting = false;
        notifyListeners();
        final http = _session?.http;
        if (http != null) _connected.add(http);
        return;
      case 'recovery.gaveUp':
        return _wifiGaveUp(
          noBle: e.fields['noBle'] == true,
          declined: e.fields['declined'] == true,
        );
    }
    notifyListeners();
  }

  /// The session could not get the camera's Wi-Fi back. Without Bluetooth
  /// either ([noBle]) the camera is gone (switched off with its Bluetooth,
  /// or out of range): the session ends and the Cameras screen says the
  /// connection was lost. Otherwise the camera's pages stay on Bluetooth,
  /// the Library says the Wi-Fi was lost (or declined), and the camera's
  /// Wi-Fi is left as [closeCamera] does.
  void _wifiGaveUp({required bool noBle, required bool declined}) {
    final session = _session;
    if (session == null || _status != ConnectionStatus.connected) return;
    _wifiRun++;
    _step = null;
    _reconnecting = false;
    if (noBle || _bleGaveUp) {
      _failure = const ConnectFailure(
        ConnectFailureKind.unreachable,
        'Lost the connection to the camera',
        step: ConnectStep.bluetooth,
        lost: true,
      );
      unawaited(_relinkLater());
      return;
    }
    _status = ConnectionStatus.bluetooth;
    _failure = declined
        ? const ConnectFailure(
            ConnectFailureKind.wifiDeclined,
            "Not joining the camera's Wi-Fi now",
            step: ConnectStep.wifi,
          )
        : const ConnectFailure(
            ConnectFailureKind.wifi,
            "Lost the camera's Wi-Fi",
            step: ConnectStep.wifi,
            lost: true,
          );
    notifyListeners();
    // The pages stay, so a camera the app turned on stays on for Shoot;
    // [closeCamera] turns it off.
    _stoppingWifi = session.stopWifi();
  }

  ConnectFailure _failureFor(GrSessionException e, ConnectStep step) {
    final kind = e.needsPairing
        ? ConnectFailureKind.needsPairing
        : e.wifiDeclined
        ? ConnectFailureKind.wifiDeclined
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
    _tab = null;
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
    _tab = null;
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
        // Leaving a camera the app turned on turns it back off, including
        // one whose wake is still in flight.
        await session.close(powerOffIfWoken: true);
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
///
/// Android can still show its network list for a network it approved
/// before (after the user disconnected it in Wi-Fi settings). When that
/// list covered a failed join of a camera approved before
/// ([cameraApproved]), [askAgain] explains it and, if the user agrees, the
/// join runs again, bringing the list back. Joins of an approved camera tell
/// the platform so ([WifiNetworkControl.join]'s `approved`).
final class _ConsentWifi implements WifiNetworkControl {
  _ConsentWifi(
    this._inner, {
    required this.approvalShown,
    required this.ask,
    required this.askAgain,
    required this.cameraApproved,
    required this.joined,
  });

  final WifiNetworkControl _inner;
  final Stream<void> approvalShown;
  final Future<bool> Function(String ssid) ask;
  final Future<bool> Function(String ssid) askAgain;
  final bool Function() cameraApproved;
  final Future<void> Function() joined;
  bool _agreed = false;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    if (!_agreed) {
      if (!await ask(ssid)) {
        throw const WifiJoinDeclined("not joining the camera's Wi-Fi now");
      }
      _agreed = true;
    }
    while (true) {
      final wasApproved = cameraApproved();
      var shown = false;
      final sub = approvalShown.listen((_) => shown = true);
      try {
        await _inner.join(
          ssid: ssid,
          passphrase: passphrase,
          security: security,
          timeout: timeout,
          approved: wasApproved,
        );
        break;
      } catch (e) {
        // Backing out of Android's list, or leaving it open past the join
        // window. Leaving during the join (Disconnect, a newer join) is
        // not an answer to the list.
        final listOutcome = e is WifiJoinDeclined || e is TimeoutException;
        if (!shown || !wasApproved || !listOutcome) rethrow;
        if (!await askAgain(ssid)) {
          throw const WifiJoinDeclined("not joining the camera's Wi-Fi now");
        }
      } finally {
        await sub.cancel();
      }
    }
    await joined();
  }

  @override
  Future<String?> currentSsid() => _inner.currentSsid();

  @override
  Future<void> leave() => _inner.leave();

  @override
  Stream<void> get lost => _inner.lost;
}
