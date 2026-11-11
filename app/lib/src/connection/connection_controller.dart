import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/services.dart';

enum ConnectionStatus {
  /// No session (never connected, or ended by switching or forgetting the
  /// camera).
  offline,

  /// [ConnectionController.step] says which link is being set up.
  connecting,

  /// Linked over Bluetooth; the camera's Wi-Fi is not in use.
  bluetooth,

  /// The camera's Wi-Fi is up and verified.
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

  /// The camera's Image Control Custom slots and the saved looks, to load
  /// into them; over Bluetooth. Only on a camera with
  /// [CameraFeature.lookSlots] ([ConnectionController.tabs]).
  looks,
}

/// What the Cameras screen's power button is doing.
enum CameraPowerChange { on, off }

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

  /// The phone joined the camera's Wi-Fi, but Android would not let GR Lab
  /// use it while a VPN carried GR Lab's traffic: a VPN may be blocking it.
  /// Retried like [wifi].
  wifiVpn,
}

/// The link a [ConnectFailure] lost after it had been up.
enum ConnectLoss {
  /// Bluetooth went and the session's reconnect gave up.
  bluetooth,

  /// Neither the camera's Wi-Fi nor Bluetooth came back: the camera was
  /// switched off with its Bluetooth, or is out of range.
  camera,

  /// The camera's Wi-Fi went and could not be got back; Bluetooth stays.
  wifi,
}

/// Why connecting failed, as data: the view words it (AGENTS.md, "Text the
/// user sees").
@immutable
final class ConnectFailure {
  const new(this.kind, {this.step, this.cause, this.loss});

  final ConnectFailureKind kind;

  /// The link that failed.
  final ConnectStep? step;

  /// The error that ended the attempt.
  final Object? cause;

  /// The link that had been up and was lost (mock `b-home-lost`); null for
  /// an attempt that never got through.
  final ConnectLoss? loss;

  /// The link had been up and was lost, rather than an attempt that never
  /// got through.
  bool get lost => loss != null;

  /// What [cause] says, untranslated technical detail: the step the
  /// session reports as failed, or the error's own text.
  String? get detail => switch (cause) {
    null => null,
    GrSessionException(:final message) => message,
    final error => '$error',
  };

  @override
  String toString() =>
      'ConnectFailure(${kind.name}, step: ${step?.name}, '
      'loss: ${loss?.name}): $cause';
}

/// A join waiting for the user to agree to the camera network; answered
/// with [ConnectionController.answerWifiConsent].
@immutable
final class WifiConsentRequest {
  const new({required this.ssid, required this.cameraName, this.again = false});

  final String ssid;
  final String cameraName;

  /// Android showed its network list during a join of a camera network it
  /// had approved before, and the join failed: the question explains why
  /// the list came back and offers to try again.
  final bool again;
}

/// One [CameraSession] for the current camera, in two stages. Bluetooth
/// ([connect]) is meant to run by itself whenever a camera is current; the
/// camera's Wi-Fi ([joinWifi]) is joined when the user opens the Library
/// or live view ([wifiNeeded]), or asks for it on the camera sheet.
/// Joining it is slow, so once it is up it stays up when the user moves on
/// to a page that does not need it, or back to the Cameras screen: it is
/// left when the app was not used for the auto-disconnect time
/// ([leaveUnusedWifi]) or the user disconnects it ([disconnectWifi]), or
/// the camera with it ([disconnect]). [openCamera] opens the camera's
/// pages ([tab]) over the Cameras screen, and [closeCamera] leaves them
/// while Bluetooth stays.
///
/// The session's BLE reconnect runs underneath and shows as
/// [reconnecting]. On Bluetooth alone it ends when the session counts the
/// camera as gone (`GrSessionOptions.bleLostAfter`): the session ends, the
/// app goes back to the Cameras screen and it says the connection was
/// lost. When the camera's Wi-Fi is lost while a page needs it,
/// the session gets it back (turning the camera on again when it was
/// switched off) while the pages stay, also shown as [reconnecting]. When
/// that fails with Bluetooth still there, the pages stay and the Library
/// says the Wi-Fi was lost; without Bluetooth the session ends, the app
/// goes back to the Cameras screen and it says the connection was lost. A
/// Wi-Fi lost while nothing needs it is let go without a word. Leaving the
/// camera's pages turns a camera the app turned on back off, once its
/// Wi-Fi is left too. A join that failed, or a lost Wi-Fi that could not
/// be got back, while the app was in the background is tried again on
/// return ([AppServices.redialDelays]), since the OS only joins camera
/// networks for the app in front.
final class ConnectionController extends ChangeNotifier {
  new({required this.services, required this.cameras}) {
    cameras.addListener(_onCamerasChanged);
    _cameraSerial = cameras.current?.serial;
  }

  final AppServices services;
  final CameraStore cameras;

  ConnectionStatus _status = ConnectionStatus.offline;
  ConnectStep? _step;

  /// The Wi-Fi join under way is a quiet rejoin after a loss, or one
  /// waiting to run ([_scheduleRedial]).
  bool _quietRejoin = false;
  ConnectFailure? _failure;
  CameraSession? _session;
  StreamSubscription<GrSessionEvent>? _events;
  String? _cameraSerial;

  /// The session's BLE reconnect gave up; the link will not come back.
  bool _bleGaveUp = false;

  /// Bumped for every session; events and results of older ones are
  /// dropped.
  int _generation = 0;

  /// Bumped for every Wi-Fi start and [closeCamera].
  int _wifiRun = 0;

  /// The Library (or live view) asked for the camera's Wi-Fi while
  /// Bluetooth was still being linked; [joinWifi] starts it once the link
  /// is up. Closing the pages, leaving the Wi-Fi, switching tabs away and
  /// ending the session cancel the request; the latest of these and a new
  /// request wins.
  bool _wifiWanted = false;
  final _wifiUp = StreamController<void>.broadcast();

  /// The Bluetooth attempt [connect] started last; [joinWifi] waits for it.
  Future<void> _linking = Future.value();

  /// Every session close still running; the next Bluetooth attempt waits
  /// for all of them ([_endSession]).
  Future<void> _closing = Future.value();
  Future<void> _stoppingWifi = Future.value();

  bool _foreground = true;
  int _redials = 0;
  Timer? _redialTimer;
  bool _redialOnResume = false;

  WifiConsentRequest? _consent;
  Completer<bool>? _consentAnswer;
  CameraTab? _tab;
  CameraPowerChange? _powerChange;
  bool _disposed = false;

  ConnectionStatus get status => _status;

  /// The tab of the camera's pages, while they are open over the Cameras
  /// screen; null otherwise. Cleared when the session fails or ends.
  CameraTab? get tab => _tab;

  /// The link being set up while [status] is connecting.
  ConnectStep? get step => _step;

  /// Getting a lost link back: Bluetooth while [status] is bluetooth and
  /// the camera's Wi-Fi while connected (both as the session reports
  /// them), or a quiet rejoin of the Wi-Fi while connecting.
  bool get reconnecting => switch (_status) {
    ConnectionStatus.connecting => _quietRejoin,
    ConnectionStatus.bluetooth => _session?.bleReconnecting ?? false,
    ConnectionStatus.connected => _session?.wifiRecovering ?? false,
    ConnectionStatus.offline || ConnectionStatus.failed => false,
  };

  /// Bluetooth is linked and usable: the connection is set up and the
  /// session's link is up now. Shoot and Looks talk to the camera only
  /// then.
  bool get bleLinked =>
      (_status == ConnectionStatus.bluetooth ||
          _status == ConnectionStatus.connected) &&
      (_session?.bleLinked ?? false);

  /// Bluetooth is being linked: for a new connection, or by the session
  /// after the camera dropped the link (as it does when it is turned off,
  /// and when it is woken for its Wi-Fi) and until its reconnect gives up.
  bool get bleLinking => switch (_status) {
    ConnectionStatus.connecting when _step == ConnectStep.bluetooth => true,
    ConnectionStatus.connecting ||
    ConnectionStatus.bluetooth ||
    ConnectionStatus.connected =>
      !_bleGaveUp && !(_session?.bleLinked ?? false),
    ConnectionStatus.offline || ConnectionStatus.failed => false,
  };

  /// Why the last attempt failed. Set with [ConnectionStatus.failed] for
  /// Bluetooth, and next to [ConnectionStatus.bluetooth] when only the
  /// Wi-Fi failed.
  ConnectFailure? get failure => _failure;

  /// Set when [leaveUnusedWifi] left the camera's Wi-Fi because the app
  /// was not used for this long (see `IdleDisconnect`), with the app on
  /// the Cameras screen or returning to it; cleared by the next Wi-Fi start
  /// or [disconnect]. The Cameras screen notes it while Bluetooth stays
  /// linked.
  Duration? get idleClosedAfter => _idleClosedAfter;
  Duration? _idleClosedAfter;

  /// Wi-Fi is up, or being got back after a loss ([reconnecting]): the
  /// Library and live view can use it.
  bool get inSession => _status == ConnectionStatus.connected;

  /// Live view is wanted on the Shoot page (`LiveViewController.wanted`),
  /// which sets this.
  bool liveViewWanted = false;

  /// Work over the camera's Wi-Fi is running, whatever page shows: a
  /// download, a movie copy or playback (`IdleDisconnect.hold`, which sets
  /// this).
  bool wifiBusy = false;

  /// The camera's Wi-Fi is in use: the Library or live view is showing, or
  /// work over it is running ([wifiBusy]). Only then is a lost Wi-Fi got
  /// back, and only then does leaving the Wi-Fi close the pages
  /// ([leaveUnusedWifi]).
  bool get wifiNeeded =>
      _tab == CameraTab.library || liveViewWanted || wifiBusy;

  /// The camera's Wi-Fi is up and sound, so worth keeping for the next
  /// page that needs it: not being got back after a loss, and not without
  /// its Bluetooth link for good (leaving the Wi-Fi is what links the
  /// camera again then).
  bool get _wifiWorthKeeping =>
      _status == ConnectionStatus.connected &&
      !(_session?.wifiRecovering ?? false) &&
      !_bleGaveUp;

  /// The camera is off (BT-only), or reported turning off.
  bool get cameraOff => _session?.cameraOff ?? false;

  /// The power button's request under way ([powerOn], [powerOff]); null
  /// when none is.
  CameraPowerChange? get powerChange => _powerChange;

  /// Turns [camera] on, as GR WORLD's power button does (the Cameras
  /// screen's power button), linking it over Bluetooth first when needed.
  /// The camera stays on when the app leaves it. A camera found on is left
  /// as it is. Returns false when the camera could not be linked (see
  /// [failure]) or did not turn on.
  Future<bool> powerOn() => _changePower(CameraPowerChange.on, (session) async {
    if (!session.cameraOff) return true;
    try {
      await session.powerOn();
      return true;
    } on GrSessionException {
      return false;
    }
  });

  /// Turns [camera] off over Bluetooth, as GR WORLD's power button does,
  /// linking it first when needed and leaving its Wi-Fi first when in use.
  /// The session stays: it links the camera again in its off state, as
  /// after [closeCamera] turns off a camera the app woke. Returns false
  /// when the camera could not be linked or did not take the request.
  Future<bool> powerOff() =>
      _changePower(CameraPowerChange.off, (session) async {
        if (session.cameraOff) return true;
        await _leaveWifi(reason: WifiStopReason.powerOff, powerOff: false);
        if (!identical(session, _session)) return false;
        return await session.powerOff();
      });

  /// Links the camera when needed, then runs [body] on the session; one
  /// power request at a time.
  Future<bool> _changePower(
    CameraPowerChange change,
    Future<bool> Function(CameraSession session) body,
  ) async {
    if (_powerChange != null) return false;
    _powerChange = change;
    notifyListeners();
    try {
      final linking =
          _status == ConnectionStatus.connecting &&
          _step == ConnectStep.bluetooth;
      await (linking ? _linking : connect());
      final session = _session;
      if (session == null ||
          _status == ConnectionStatus.offline ||
          _status == ConnectionStatus.failed) {
        return false;
      }
      return await body(session);
    } finally {
      _powerChange = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// A Library request failed: asks the camera once whether its Wi-Fi
  /// still works; when it does not, the session counts the link as lost
  /// and gets it back ([reconnecting]). True while the camera answers.
  Future<bool> checkWifi() async {
    final session = _session;
    if (session == null || _status != ConnectionStatus.connected) {
      return false;
    }
    return await session.checkWifi();
  }

  /// Non-null while a join waits for the user to agree to the camera
  /// network (see [AppServices.askBeforeWifiJoin]).
  WifiConsentRequest? get wifiConsent => _consent;

  /// The camera this controller connects to.
  SavedCamera? get camera => cameras.current;

  /// [camera]'s model and firmware, for what it supports: the session's
  /// (`CameraSession.body`, which fills what a link did not read from the
  /// saved camera), else as last saved.
  CameraBody get body => _session?.body ?? camera?.body ?? CameraBody.unknown;

  /// The tabs of [camera]'s pages: Looks only on a model GR Lab can load
  /// looks into ([CameraFeature.lookSlots]). A camera whose firmware is too
  /// old for it keeps the tab, which asks for the update.
  List<CameraTab> get tabs {
    final slots = body.minimumFirmware(CameraFeature.lookSlots) != null;
    return [
      for (final tab in CameraTab.values)
        if (tab != CameraTab.looks || slots) tab,
    ];
  }

  /// The camera layer's session for [camera], from the Bluetooth attempt
  /// until the session ends.
  CameraSession? get cameraSession => _session;

  /// The camera's battery and storages for this session; null without
  /// one. Its changes notify this controller's listeners.
  CameraStatus? get cameraStatus => _session?.status;

  /// The camera network's name, once the session has read it.
  String? get ssid => _session?.ssid;

  /// Emits every time the Wi-Fi link comes up, or comes back after a loss.
  Stream<void> get wifiUp => _wifiUp.stream;

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
    return _linking = _connectBluetooth();
  }

  /// Makes the paired camera [serial] the current one and links it;
  /// changing the current camera ends any attempt or session with the
  /// previous one.
  Future<void> connectTo(String serial) async {
    if (cameras.current?.serial != serial) await cameras.select(serial);
    return await connect();
  }

  /// Opens the camera's pages on [tab] (the camera card's buttons). The
  /// Library joins the camera's Wi-Fi ([joinWifi]); Shoot and Looks link
  /// Bluetooth and need nothing more.
  Future<void> openCamera(CameraTab tab) {
    _tab = tab;
    notifyListeners();
    return tab == CameraTab.library ? joinWifi() : connect();
  }

  /// Switches the open camera pages to [tab]. The Library joins the
  /// camera's Wi-Fi unless it is up or the last join failed; that failure
  /// is shown with Try again instead. While Bluetooth is still being
  /// linked, the join waits for it, and switching away again cancels it.
  void selectTab(CameraTab tab) {
    if (_tab == null || _tab == tab) return;
    _tab = tab;
    notifyListeners();
    if (tab != CameraTab.library) {
      _wifiWanted = false;
      return;
    }
    final linking =
        _status == ConnectionStatus.connecting &&
        _step == ConnectStep.bluetooth;
    if (linking ||
        (_status == ConnectionStatus.bluetooth && _failure == null)) {
      unawaited(joinWifi());
    }
  }

  /// Joins the camera's Wi-Fi for the Library or live view, or ahead of
  /// them from the camera sheet, linking Bluetooth first when needed (or
  /// waiting for the link being made).
  /// Does nothing while Wi-Fi is up or being joined, except that it cuts
  /// short the wait before a quiet rejoin. Leaving the Wi-Fi or the pages
  /// before Bluetooth is up cancels the join.
  Future<void> joinWifi() async {
    final waitingToRedial = _redialTimer != null || _redialOnResume;
    if (_status == ConnectionStatus.connected ||
        (_status == ConnectionStatus.connecting &&
            _step == ConnectStep.wifi &&
            !waitingToRedial)) {
      return;
    }
    final linking =
        _status == ConnectionStatus.connecting &&
        _step == ConnectStep.bluetooth;
    if (linking ||
        _status == ConnectionStatus.offline ||
        _status == ConnectionStatus.failed) {
      _wifiWanted = true;
      await (linking ? _linking : connect());
      // Cancelled meanwhile, already started by another request, or the
      // link did not come up.
      if (!_wifiWanted || _status != ConnectionStatus.bluetooth) return;
    }
    _wifiWanted = false;
    _cancelRedial();
    _redials = 0;
    return await _startWifi(quiet: false);
  }

  /// Closes the camera's pages; the app returns to the Cameras screen with
  /// Bluetooth linked. Wi-Fi that is up stays up for the next visit
  /// ([leaveUnusedWifi] leaves it), and a camera the app turned on stays on
  /// with it. Without such a Wi-Fi this is [disconnectWifi].
  Future<void> closeCamera() {
    if (!_wifiWorthKeeping) return disconnectWifi();
    if (_tab == null) return Future.value();
    _tab = null;
    notifyListeners();
    return Future.value();
  }

  /// Closes the camera's pages and leaves the camera's Wi-Fi, or stops
  /// joining it or getting it back, keeping Bluetooth (the camera sheet's
  /// Wi-Fi row); the app returns to the Cameras screen. A camera
  /// the app turned on (for the Library or Shoot) is turned back off. A
  /// Wi-Fi failure shown in the pages is cleared.
  Future<void> disconnectWifi() {
    final hadTab = _tab != null;
    _tab = null;
    return _leaveWifi(
      reason: WifiStopReason.user,
      powerOff: true,
      changed: hadTab,
    );
  }

  /// Live view was switched back to Remote: stops a join of the camera's
  /// Wi-Fi still under way, or its recovery, and clears a Wi-Fi failure,
  /// keeping the camera's pages open over Bluetooth and the camera on.
  /// Wi-Fi that is up stays up ([leaveUnusedWifi] leaves it).
  Future<void> cancelWifiJoin() => _wifiWorthKeeping
      ? Future.value()
      : _leaveWifi(reason: WifiStopReason.user, powerOff: false);

  /// The app was not used for [idleFor] (`IdleDisconnect`): leaves the
  /// camera's Wi-Fi, keeping Bluetooth. A page that needs the Wi-Fi
  /// ([wifiNeeded]) closes with it; one that does not stays open, with the
  /// camera on. On the Cameras screen, also when a page closed to it, a
  /// camera the app turned on is turned back off and [idleClosedAfter] is
  /// set.
  Future<void> leaveUnusedWifi(Duration idleFor) {
    final hadTab = _tab != null;
    if (wifiNeeded) _tab = null;
    final onCameras = _tab == null;
    return _leaveWifi(
      reason: WifiStopReason.idle,
      powerOff: onCameras,
      idleFor: onCameras ? idleFor : null,
      changed: hadTab && onCameras,
    );
  }

  Future<void> _leaveWifi({
    required WifiStopReason reason,
    required bool powerOff,
    Duration? idleFor,
    bool changed = false,
  }) async {
    _wifiWanted = false;
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
    _quietRejoin = false;
    _failure = null;
    _idleClosedAfter = idleFor;
    notifyListeners();
    final stopping = _stoppingWifi = session.stopWifi(
      reason: reason,
      powerOffIfWoken: powerOff,
    );
    await stopping;
    if (_bleGaveUp && identical(session, _session)) await _relinkLater();
  }

  /// Answers [wifiConsent]: join the camera network, or not now.
  void answerWifiConsent({required bool join}) {
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
    _quietRejoin = false;
    _bleGaveUp = false;
    _status = ConnectionStatus.connecting;
    _step = ConnectStep.bluetooth;
    notifyListeners();

    // A disconnect may still be releasing the previous BLE link.
    await _closing;
    if (generation != _generation) return;

    final adapter = await services.camera.bluetoothState();
    if (generation != _generation) return;
    if (adapter == BleAdapterState.poweredOff) {
      return _fail(
        generation,
        const ConnectFailure(
          ConnectFailureKind.bluetoothOff,
          step: ConnectStep.bluetooth,
        ),
      );
    }
    // Also a denied permission.
    if (adapter == BleAdapterState.unauthorized) {
      return _fail(
        generation,
        const ConnectFailure(
          ConnectFailureKind.bluetoothDenied,
          step: ConnectStep.bluetooth,
        ),
      );
    }

    final session = CameraSession(
      services.camera,
      consent: WifiConsent(
        ask: (ssid) => _askWifi(generation, target, ssid),
        askAgain: (ssid) => _askWifi(generation, target, ssid, again: true),
        cameraApproved: () => _wifiApproved(target),
        joined: () => cameras.markWifiApproved(target.serial),
      ),
    );
    _session = session;
    _events = session.events.listen((e) => _onEvent(generation, e));
    session.status.addListener(notifyListeners);
    try {
      await session.connectBluetooth(
        deviceId: target.paired.deviceId,
        serial: target.serial,
        saved: target.body,
      );
    } on Object catch (e) {
      if (generation != _generation) return;
      await _endSession();
      return _fail(generation, _failureFor(e, ConnectStep.bluetooth));
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
    _quietRejoin = quiet;
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
      return _wifiFailed(_failureFor(e, ConnectStep.wifi));
    }
    if (stale()) return;
    _status = ConnectionStatus.connected;
    _step = null;
    _quietRejoin = false;
    _redials = 0;
    notifyListeners();
    _wifiUp.add(null);
  }

  /// Ends the session or cancels an attempt, leaving the camera's Wi-Fi
  /// with its Bluetooth: when the user disconnects the camera (the camera
  /// sheet) or stops connecting to it (the camera card), and when the
  /// current camera changes or is forgotten. The state goes offline at once
  /// so a [connect] issued in the same tick (switching cameras) starts a
  /// new attempt instead of seeing the old one. Completes once every
  /// session close still running has finished.
  Future<void> disconnect() {
    _generation++;
    _wifiRun++;
    _wifiWanted = false;
    _cancelRedial();
    _tab = null;
    _status = ConnectionStatus.offline;
    _step = null;
    _quietRejoin = false;
    _failure = null;
    _idleClosedAfter = null;
    _declineConsent();
    final closing = _endSession();
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
      case 'ble.ready':
        // A firmware update shows on the next link.
        final firmware = _session?.firmwareRevision;
        final serial = camera?.serial;
        if (firmware != null && serial != null) {
          unawaited(cameras.recordFirmware(serial, firmware));
        }
      case 'ble.gaveUp' || 'ble.needsPairing':
        _bleGaveUp = true;
        // While a page uses the Wi-Fi it carries on without Bluetooth, and
        // the link is dealt with when the Wi-Fi is left: at once when
        // nothing uses it.
        if (_status == ConnectionStatus.connected && !wifiNeeded) {
          unawaited(
            _leaveWifi(
              reason: WifiStopReason.bluetoothLost,
              powerOff: _tab == null,
            ),
          );
          return;
        }
        // On Bluetooth alone nothing reaches the camera now, nor while a
        // Wi-Fi start (or a rejoin still to come) waits for the link: both
        // end with the session.
        final awaitingLink =
            _status == ConnectionStatus.connecting &&
            _session?.phase == GrSessionPhase.bluetooth;
        if (_status == ConnectionStatus.bluetooth || awaitingLink) {
          _wifiRun++;
          _cancelRedial();
          unawaited(_endSession());
          return _fail(
            generation,
            ConnectFailure(
              e.kind == 'ble.needsPairing'
                  ? ConnectFailureKind.needsPairing
                  : ConnectFailureKind.unreachable,
              step: ConnectStep.bluetooth,
              loss: ConnectLoss.bluetooth,
            ),
          );
        }
      case 'wifi.lost'
          when _status == ConnectionStatus.connected && !wifiNeeded:
        // Only kept for the next page that needs it. Leaving it stops the
        // session's recovery before its first try, which would turn a
        // camera the user switched off back on.
        unawaited(
          _leaveWifi(
            reason: WifiStopReason.lostUnneeded,
            powerOff: _tab == null,
          ),
        );
        return;
      case 'recovery.done' when _status == ConnectionStatus.connected:
        notifyListeners();
        _wifiUp.add(null);
        return;
      case 'recovery.gaveUp':
        return _wifiGaveUp(
          noBle: e.fields['noBle'] == true,
          declined: e.fields['declined'] == true,
          vpnSuspected: e.fields['vpnSuspected'] == true,
        );
    }
    notifyListeners();
  }

  /// The session could not get the camera's Wi-Fi back. Without Bluetooth
  /// either ([noBle]) the camera is gone (switched off with its Bluetooth,
  /// or out of range): the session ends and the Cameras screen says the
  /// connection was lost. Otherwise the camera's pages stay on Bluetooth,
  /// the Library says the Wi-Fi was lost (or declined, or that a VPN may
  /// be blocking it: [vpnSuspected]), and the phone leaves the camera's
  /// Wi-Fi. A loss in the background that was not declined is instead
  /// joined again on return, as a join that failed in the background is:
  /// the OS only joins camera networks for the app in front.
  void _wifiGaveUp({
    required bool noBle,
    required bool declined,
    required bool vpnSuspected,
  }) {
    final session = _session;
    if (session == null || _status != ConnectionStatus.connected) return;
    _wifiRun++;
    _step = null;
    _quietRejoin = false;
    if (noBle || _bleGaveUp) {
      _failure = const ConnectFailure(
        ConnectFailureKind.unreachable,
        step: ConnectStep.bluetooth,
        loss: ConnectLoss.camera,
      );
      unawaited(_relinkLater());
      return;
    }
    // Pages that stay keep a camera the app turned on on for Shoot, and
    // [closeCamera] turns it off; with none open it is turned off now. A
    // rejoin waits for this.
    _stoppingWifi = session.stopWifi(
      reason: WifiStopReason.recoveryGaveUp,
      powerOffIfWoken: _tab == null,
    );
    if (!declined && !_foreground && _scheduleRedial()) return;
    _status = ConnectionStatus.bluetooth;
    _failure = declined
        ? const ConnectFailure(
            ConnectFailureKind.wifiDeclined,
            step: ConnectStep.wifi,
          )
        : ConnectFailure(
            vpnSuspected ? ConnectFailureKind.wifiVpn : ConnectFailureKind.wifi,
            step: ConnectStep.wifi,
            loss: ConnectLoss.wifi,
          );
    notifyListeners();
  }

  /// The failure [error] means for the [step] being set up.
  ConnectFailure _failureFor(Object error, ConnectStep step) {
    final kind = switch (error) {
      GrSessionException(needsPairing: true) => ConnectFailureKind.needsPairing,
      GrSessionException(wifiDeclined: true) => ConnectFailureKind.wifiDeclined,
      _ when step == ConnectStep.bluetooth => ConnectFailureKind.unreachable,
      GrSessionException(wifiVpnSuspected: true) => ConnectFailureKind.wifiVpn,
      _ => ConnectFailureKind.wifi,
    };
    return ConnectFailure(kind, step: step, cause: error);
  }

  /// A Wi-Fi start failed: tries again quietly when the join failed
  /// because the app was in the background (or a quiet retry failed
  /// again); otherwise shows [failure] next to the Bluetooth link.
  void _wifiFailed(ConnectFailure failure) {
    final wifi =
        failure.kind == ConnectFailureKind.wifi ||
        failure.kind == ConnectFailureKind.wifiVpn;
    final transient = wifi || failure.kind == ConnectFailureKind.unreachable;
    final redial = transient && (_quietRejoin || (!_foreground && wifi));
    if (redial && _scheduleRedial()) return;
    _failure = failure;
    _step = null;
    _quietRejoin = false;
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
      step: ConnectStep.bluetooth,
      loss: ConnectLoss.bluetooth,
    );
    notifyListeners();
    await _endSession();
  }

  /// Shows a quiet rejoin as pending; false when the tries are used up.
  bool _scheduleRedial() {
    if (_foreground && _redials >= services.redialDelays.length) return false;
    final generation = _generation;
    _status = ConnectionStatus.connecting;
    _step = ConnectStep.wifi;
    _quietRejoin = true;
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
    _wifiWanted = false;
    _status = ConnectionStatus.failed;
    _failure = failure;
    _step = null;
    _quietRejoin = false;
    notifyListeners();
  }

  Future<void> _closeSession() async {
    final session = _session;
    _session = null;
    _bleGaveUp = false;
    await _events?.cancel();
    _events = null;
    session?.status.removeListener(notifyListeners);
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

  /// Closes the session and adds that to [_closing], so the next Bluetooth
  /// attempt waits for every close still running: a later close with no
  /// session left (a second [disconnect]) must not let it reuse a link the
  /// first is still releasing.
  Future<void> _endSession() =>
      _closing = Future.wait([_closing, _closeSession()]);

  void _onCamerasChanged() {
    final serial = cameras.current?.serial;
    if (serial == _cameraSerial) return;
    _cameraSerial = serial;
    _failure = null;
    unawaited(disconnect());
  }

  @override
  void dispose() {
    _disposed = true;
    cameras.removeListener(_onCamerasChanged);
    _generation++;
    _cancelRedial();
    _declineConsent();
    unawaited(_closeSession());
    unawaited(_wifiUp.close());
    super.dispose();
  }
}
