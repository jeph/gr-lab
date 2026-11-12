import 'dart:async';

import 'package:gr_protocol/src/ble/advertising.dart';
import 'package:gr_protocol/src/ble/catalog.dart';
import 'package:gr_protocol/src/ble/client.dart';
import 'package:gr_protocol/src/ble/enums.dart';
import 'package:gr_protocol/src/ble/model.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:gr_protocol/src/ble/wake.dart';
import 'package:gr_protocol/src/camera_address.dart';
import 'package:gr_protocol/src/http/changes.dart';
import 'package:gr_protocol/src/http/client.dart';
import 'package:gr_protocol/src/http/liveness.dart';
import 'package:gr_protocol/src/http/models.dart';
import 'package:gr_protocol/src/trace.dart';
import 'package:gr_protocol/src/wifi/network_control.dart';

/// Where a [GrSession] is in the BLE → Wi-Fi hand-off
/// (research/protocol/ble.md §Minimal client sequence) and afterwards.
enum GrSessionPhase {
  /// Not connected yet.
  idle,

  /// Scanning for the camera's BLE advertisement.
  scanning,

  /// Turning the camera on over BLE (Operation Mode write).
  waking,

  /// Opening the BLE link, discovering services and reading the identity.
  bleConnecting,

  /// Linked over BLE; the camera's Wi-Fi is not in use ([GrSession.startWifi]
  /// joins it, [GrSession.stopWifi] comes back here).
  bluetooth,

  /// Writing WLAN-on over BLE so the camera starts its access point.
  wlanOn,

  /// The phone is joining the camera's access point.
  joining,

  /// Joined; checking `/v1/props` identifies the expected camera.
  verifying,

  /// Wi-Fi verified; WebSocket and liveness polling running.
  connected,

  /// Wi-Fi liveness was lost; re-issuing WLAN-on and rejoining.
  recovering,

  /// Recovery gave up; the session stays open but has no Wi-Fi link.
  lost,

  /// [GrSession.close] finished; the session cannot be reused.
  closed,
}

/// One observable step of a session, for UIs, logs and hardware validation.
final class GrSessionEvent {
  /// Event [kind] in [phase], stamped with the current time.
  new(this.phase, this.kind, [this.fields = const {}]) : at = DateTime.now();

  /// Local time the event was emitted.
  final DateTime at;

  /// Phase after the step.
  final GrSessionPhase phase;

  /// Dotted event name, e.g. `ble.connect`, `wifi.join`, `power.off`.
  final String kind;

  /// Event detail; JSON-encodable values.
  final Map<String, Object?> fields;

  /// Trace/log form; [fields] are merged in at the top level.
  Map<String, Object?> toJson() => {
    'time': at.toUtc().toIso8601String(),
    'phase': phase.name,
    'kind': kind,
    if (fields.isNotEmpty) ...fields,
  };
}

/// A session step failed in [phase]; [cause] holds the underlying error.
final class GrSessionException implements Exception {
  /// Failure in [phase] described by [message], caused by [cause].
  const new(this.phase, this.message, [this.cause]);

  /// Phase the failing step belonged to.
  final GrSessionPhase phase;

  /// What failed, e.g. `join failed`.
  final String message;

  /// Underlying error, e.g. a [BleException] or [WifiJoinDeclined].
  final Object? cause;

  /// The camera refused this device's bond, or encrypted access failed on
  /// a link that should be bonded. Only pairing again recovers; retrying
  /// cannot (research/protocol/firmware-bonding.md §4).
  bool get needsPairing {
    final c = cause;
    return c is BleException &&
        (c.code == BleErrorCode.bondRejected ||
            c.code == BleErrorCode.unauthorized);
  }

  /// The user declined joining the camera's Wi-Fi; only asking them again
  /// (an explicit connect) can continue.
  bool get wifiDeclined => cause is WifiJoinDeclined;

  /// The join ended with the OS refusing the camera network while a VPN
  /// carried the app's traffic: a VPN may be blocking it
  /// ([WifiJoinVpnSuspected]).
  bool get wifiVpnSuspected => cause is WifiJoinVpnSuspected;

  @override
  String toString() =>
      'GrSessionException(${phase.name}): $message'
      '${cause == null ? '' : ' ($cause)'}';
}

/// Timings and policies. Defaults follow the official apps where the docs
/// establish them and are marked as design choices otherwise.
final class GrSessionOptions {
  /// Options; each defaults to the value its field doc names.
  const new({
    this.scanTimeout = const Duration(seconds: 20),
    this.bleConnectTimeout = const Duration(seconds: 35),
    this.bleConnectAttempts = 3,
    this.bleConnectRetryDelay = const Duration(milliseconds: 50),
    this.wakeSettle = const Duration(seconds: 8),
    this.powerOffGuard = grWorldPowerOffReconnectGuard,
    this.powerOnMode = BleOperationMode.playback,
    this.joinTimeout = const Duration(seconds: 60),
    this.joinRetryDelay = const Duration(seconds: 2),
    this.verifyTimeout = const Duration(seconds: 30),
    this.verifyProbeTimeout = const Duration(seconds: 3),
    this.livenessInterval = const Duration(seconds: 5),
    this.livenessFailureThreshold = 3,
    this.livenessLossAfter = const Duration(seconds: 40),
    this.wifiRecoveryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
    this.maxWifiRecoveryAttempts = 6,
    this.bleReconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
    this.maxBleReconnectAttempts = 10,
    this.bleLostAfter = const Duration(seconds: 40),
  });

  /// How long to scan for the camera's advertisement.
  final Duration scanTimeout;

  /// GR WORLD's connect timeout: 35 s (ble.md §Connect parameters).
  final Duration bleConnectTimeout;

  /// GR WORLD's connect retry: 3 attempts, 50 ms apart (ble.md §Connect
  /// parameters). Needed for an off camera: the first link to it drops
  /// (~5.5 s) before discovery.
  final int bleConnectAttempts;

  /// Pause between BLE connect attempts (GR WORLD: 50 ms).
  final Duration bleConnectRetryDelay;

  /// How long after a wake the session watches for the link to drop. A
  /// drop is linked again; either way WLAN-on is then written once more
  /// unless the join is through. Design choice: links to an off camera drop
  /// ~5.5-8 s after they open.
  final Duration wakeSettle;

  /// How long after the camera powered off the session waits before it
  /// connects again: GR WORLD's 6 s (ble.md §Turning the camera's Wi-Fi
  /// on, path B). The camera swaps its radio's firmware meanwhile
  /// (research/protocol/firmware-bonding.md §6).
  final Duration powerOffGuard;

  /// Written to Operation Mode when a connect finds the camera in
  /// bleStartup (`02`): GR WORLD writes playback, or capture for its
  /// remote screen (research/protocol/power-on-grworld.md).
  final BleOperationMode powerOnMode;

  /// GR WORLD allows 60 s for the AP to come up and the join to finish.
  final Duration joinTimeout;

  /// Pause between join attempts while the AP is still coming up \[design\].
  final Duration joinRetryDelay;

  /// Total time for the first `/v1/props` identity check to succeed after
  /// joining (DHCP and the HTTP server may lag the association) \[design\].
  final Duration verifyTimeout;

  /// GR WORLD's `connectToWifi` verification uses a 3 s timeout.
  final Duration verifyProbeTimeout;

  /// Pause between liveness probes (`/v1/ping`, [LivenessMonitor])
  /// \[design\]. Image Sync polls `/v1/props` every 500 ms, but its poll
  /// also refreshes its settings (connection-imagesync.md §2.2); here a
  /// probe only tells whether the camera still answers. With Image Sync's
  /// rule (3 consecutive failures and 40 s without success) probes 5 s
  /// apart find a loss 40 to 45 s after the last answer, 45 s when each
  /// probe runs into its 10 s read timeout, against 40 to 42 s.
  final Duration livenessInterval;

  /// Consecutive failed polls before loss can be declared (Image Sync: 3).
  final int livenessFailureThreshold;

  /// Time without a successful poll before loss can be declared (40 s).
  final Duration livenessLossAfter;

  /// Rejoin backoff after liveness loss (connection-lifecycle.md §9); the
  /// last delay repeats.
  final List<Duration> wifiRecoveryDelays;

  /// Rejoin attempts before the session gives up in [GrSessionPhase.lost].
  final int maxWifiRecoveryAttempts;

  /// BLE auto-reconnect backoff; independent of Wi-Fi, never writes WLAN.
  final List<Duration> bleReconnectDelays;

  /// BLE reconnect attempts before automatic reconnects stop.
  final int maxBleReconnectAttempts;

  /// How long a lost Bluetooth link may stay down before the camera counts
  /// as gone (switched off with its Bluetooth, or out of range): the BLE
  /// reconnect stops then unless the camera's Wi-Fi is in use, and Wi-Fi
  /// recovery waits this long for the link to come back. Design choice: a
  /// GR IV that was switched off links again ~15 s after the drop (GR IV
  /// HDF, 2026-11-08).
  final Duration bleLostAfter;
}

/// GR WORLD's `connectToWifi` identity check (http-api.md §4.1,
/// `RunnableC1626F.java:118-146`): `ssid` equal, first 8 characters of
/// `serialNo` equal, and `model` without `RICOH`, trimmed, equal. Null
/// expectations are skipped. Returns the mismatches (empty = verified).
List<String> verifyCameraProps(
  GrProps props, {
  String? expectedSsid,
  String? expectedSerial,
  String? expectedModel,
}) {
  final problems = <String>[];
  if (expectedSsid != null && props.ssid != expectedSsid) {
    problems.add('ssid ${props.ssid} != $expectedSsid');
  }
  if (expectedSerial != null) {
    String take8(String s) => s.length <= 8 ? s : s.substring(0, 8);
    final got = props.serialNo;
    if (got == null || take8(got) != take8(expectedSerial)) {
      problems.add('serialNo $got does not start like $expectedSerial');
    }
  }
  if (expectedModel != null) {
    final got = stripRicohPrefix(props.model);
    if (got != stripRicohPrefix(expectedModel)) {
      problems.add('model $got != ${stripRicohPrefix(expectedModel)}');
    }
  }
  return problems;
}

/// One camera connection: BLE link, camera Wi-Fi, HTTP client, change
/// WebSocket and liveness monitor, with independent BLE and Wi-Fi recovery
/// (connection-lifecycle.md §9: a BLE blip never tears down Wi-Fi, and Wi-Fi
/// loss is repaired by re-issuing WLAN-on over BLE and rejoining, unless
/// the camera turned off, which ends the Wi-Fi and leaves the camera off).
final class GrSession {
  /// Session over [transport] and [wifi] for the camera at [host]; nothing
  /// happens until [connect] or [connectBluetooth].
  new({
    required this.transport,
    required this.wifi,
    this.host = grCameraHost,
    this.options = const GrSessionOptions(),
    this._trace,
    GrHttpClient Function(String host, TraceSink? trace)? httpFactory,
  }) : _httpFactory = httpFactory ?? _defaultHttp;

  static GrHttpClient _defaultHttp(String host, TraceSink? trace) =>
      GrHttpClient(host, trace: trace);

  /// The phone's BLE stack.
  final BleTransport transport;

  /// The phone's Wi-Fi control.
  final WifiNetworkControl wifi;

  /// Camera address on its access point.
  final String host;

  /// Timings and policies.
  final GrSessionOptions options;
  final TraceSink? _trace;
  final GrHttpClient Function(String host, TraceSink? trace) _httpFactory;

  final StreamController<GrSessionEvent> _events = StreamController.broadcast();
  final StreamController<GrProps> _propsUpdates = StreamController.broadcast();
  GrSessionPhase _phase = GrSessionPhase.idle;

  String? _serial;
  bool _cameraOff = false;

  /// A wake is responsible for the link: the camera may drop it while it
  /// boots, so a drop clears the link but the wake, not the BLE
  /// reconnect, links again; a wake that fails hands the loss over.
  bool _relinking = false;

  /// The phone joined, or is joining, the camera's network for this
  /// session. Tracked apart from the phase, which a failed start resets to
  /// [GrSessionPhase.bluetooth]: the phone's request is a resource of its
  /// own (connection-lifecycle.md §6), released by [_leaveWifi].
  bool _wifiJoined = false;

  /// Completed by [stopWifi] and [close] to cut the Wi-Fi start's or
  /// recovery's waits short; a new [startWifi] replaces it.
  Completer<void> _wifiStop = Completer<void>();
  bool get _wifiStopped => _wifiStop.isCompleted;

  /// [stopWifi] calls in progress; [startWifi] is refused until they end.
  int _wifiStops = 0;

  /// Completed by [close]: ends a scan and the waits of BLE reconnects.
  final Completer<void> _closeSignal = Completer<void>();

  /// This session turned the camera on ([wake], or a Wi-Fi start); cleared
  /// when the session turns it off again, or the camera turns off without
  /// the session asking.
  bool _wokeCamera = false;

  /// The session turned the camera off and has not linked it again in its
  /// BT-only state yet ([turningOff]).
  bool _turningOff = false;

  /// Ends [_turningOff] for a camera that does not settle.
  Timer? _turnOffLimit;

  /// When a link that has since dropped last saw the camera power off
  /// (`GrBleClient.lastPowerOff`); the next connect waits out
  /// [GrSessionOptions.powerOffGuard] from then.
  DateTime? _poweredOffAt;

  /// The link of a camera that is on dropped without the session turning
  /// it off, and the session is getting it back ([bleReconnecting]).
  bool _bleLostUnexpectedly = false;

  /// The session let go of a camera that is off ([parked]).
  bool _parked = false;

  /// The scan a parked session reads the camera's advertisements from.
  StreamSubscription<BleAdvertisement>? _parkWatch;

  /// The camera no longer holds this phone's keys (`ble.needsPairing`):
  /// nothing links it again by itself.
  bool _bondLost = false;

  /// The wake running now (a Wi-Fi start's, or [wake]'s); the next one
  /// waits for it, so two wakes never overlap.
  Future<void>? _wakeRunning;

  /// The [wake] call in progress, completing without error; awaited by
  /// [stopWifi], [powerOffIfWoken] and [close] after cutting it short.
  Future<void>? _wakeCall;

  /// Completed by [stopWifi], [powerOffIfWoken] or [close] to cut the
  /// running [wake] short, including its waits.
  Completer<void> _wakeStop = Completer<void>();

  /// The phase a [wake] that set [GrSessionPhase.waking] returns to.
  GrSessionPhase? _wakeReturnTo;

  /// The watch over the link after a wake whose early WLAN-on went through
  /// (see [_wakeAndWlanOn]); cancelled by [stopWifi] and [close], and
  /// awaited by [stopWifi] so a relink it started ends before WLAN-off.
  _WakeSettle? _wakeSettle;
  Future<void>? _afterWake;
  Future<void>? _wifiStart;
  String? _deviceId;
  GrAdvertisement? _advertisement;
  GrBleClient? _ble;
  GrBleIdentity? _identity;
  GrWifiCredentials? _credentials;

  /// Security the joins use: the credentials', else what [_joinAndVerify]
  /// read again, else the one a join with unknown security got through
  /// with; null while unknown.
  WifiSecurity? _joinSecurity;
  GrHttpClient? _http;
  GrProps? _props;
  GrChangesSocket? _changes;
  LivenessMonitor? _monitor;
  StreamSubscription<void>? _lostSub;
  StreamSubscription<GrChangeEvent>? _changesSub;

  /// The change socket a `/v1/props` read is running for, and whether
  /// another change came since that read started. A read for a socket the
  /// session has let go of (a Wi-Fi loss) does not count: it may stay
  /// unanswered long after the next socket is open.
  GrChangesSocket? _propsRefreshingFor;
  bool _propsStale = false;
  StreamSubscription<Object?>? _powerSub;
  bool _closing = false;
  Future<void>? _bleReconnect;
  Future<void>? _wifiRecovery;

  /// Set from `wifi.lost` until `recovery.done` or `recovery.gaveUp`, so
  /// readers notified by those events see the outcome.
  bool _wifiRecovering = false;

  /// Every step, in order (broadcast).
  Stream<GrSessionEvent> get events => _events.stream;

  /// Current phase.
  GrSessionPhase get phase => _phase;

  /// Null while BLE is down (reconnecting) or before connecting.
  GrBleClient? get ble => _ble;

  /// The link of a camera that is on dropped on its own and the session is
  /// linking again; false once it is back, or when the reconnect gave up.
  /// A drop while the session turns the camera off ([turningOff]) or while
  /// the camera is off ([cameraOff]) does not count: the camera swaps its
  /// radio's firmware when it turns off, and the first link to it in its
  /// BT-only state drops while its host wakes
  /// (research/protocol/firmware-bonding.md §6); whether a later link to
  /// an off camera holds is \[unknown\].
  bool get bleReconnecting => _ble == null && _bleLostUnexpectedly;

  /// The session turned the camera off ([powerOff], [powerOffIfWoken],
  /// `stopWifi(powerOffIfWoken: true)`) and the camera has not settled:
  /// from the Camera Power write until the camera is linked again in its
  /// BT-only state (`power.offSettled`). Every link drop until then is
  /// expected (`ble.lost` with `afterPowerOff`). Also ends when the
  /// reconnect gives up, when a [wake] or [startWifi] turns the camera on
  /// again, and, for a camera that neither drops the link nor reads off,
  /// after [GrSessionOptions.bleLostAfter] and
  /// [GrSessionOptions.powerOffGuard] (`power.offUnsettled`) \[design\].
  bool get turningOff => _turningOff;

  /// The session let go of a camera that is off and only reads its
  /// advertisements, from `ble.parked` until the camera is linked again.
  ///
  /// A camera in its BT-only state drops a link that is not used to turn
  /// it on about 8 s after it opened, and every link wakes its host (GR IV
  /// HDF, firmware 1.20, 2026-11-11: research/protocol/firmware-bonding.md
  /// §6.1), so the session does not link it again \[design\]. It links
  /// when an advertisement says the camera is on (`ble.seenOn`): the
  /// Camera Information service in place of Client Registration, or power
  /// tag `01` (research/camera-models.md §4.1). [wake] and [startWifi]
  /// link a parked camera themselves.
  bool get parked => _parked;

  /// The camera's Wi-Fi was lost and is being got back: from `wifi.lost`
  /// until `recovery.done` or `recovery.gaveUp`, through every phase the
  /// recovery passes (WLAN-on, joining).
  bool get wifiRecovering => _wifiRecovering;

  /// Model, serial and other identity read over BLE at connect.
  GrBleIdentity? get identity => _identity;

  /// Camera Wi-Fi SSID and passphrase read over BLE; `null` before the
  /// first Wi-Fi start.
  GrWifiCredentials? get credentials => _credentials;

  /// The advertisement the scan found; `null` when connected by device id.
  GrAdvertisement? get advertisement => _advertisement;

  /// The camera answered over BLE in its BT-only (off) state, or reported
  /// turning off; [wake] and [startWifi] power it on, and nothing else
  /// does: Wi-Fi recovery leaves it off.
  bool get cameraOff => _cameraOff;

  /// This session turned the camera on ([wake], or a Wi-Fi start). Stays
  /// set until the session turns the camera off again ([powerOffIfWoken],
  /// `stopWifi(powerOffIfWoken: true)`, `close`), or the camera turns off
  /// without the session asking (its power button, or by itself): nothing
  /// is left to turn off then.
  bool get wokeCamera => _wokeCamera;

  /// The camera HTTP client; non-null from [GrSessionPhase.verifying] on.
  GrHttpClient? get http => _http;

  /// The newest `/v1/props` the session read: the identity check, then
  /// every liveness poll while Wi-Fi services run. Kept after the Wi-Fi
  /// goes, as the last reading.
  GrProps? get props => _props;

  /// Every `/v1/props` reading [props] takes (broadcast).
  Stream<GrProps> get propsUpdates => _propsUpdates.stream;

  /// The `/v1/changes` socket; non-null while Wi-Fi services run.
  GrChangesSocket? get changes => _changes;

  /// The liveness monitor; non-null while Wi-Fi services run.
  LivenessMonitor? get liveness => _monitor;

  /// Runs the full hand-off: [connectBluetooth], then [startWifi], which
  /// powers the camera on when it is off. Throws [GrSessionException] on
  /// the first unrecoverable step; check [GrSessionException.needsPairing].
  Future<void> connect({String? serial, String? deviceId}) async {
    await connectBluetooth(serial: serial, deviceId: deviceId);
    await startWifi();
  }

  /// Connects BLE only (directly to [deviceId] when given, as GR WORLD
  /// does; otherwise after scanning for [serial] or any GR camera) and reads
  /// the identity; ends in [GrSessionPhase.bluetooth]. A camera that is off
  /// is not woken ([cameraOff]); it drops the link soon after, and
  /// [startWifi] links again.
  Future<void> connectBluetooth({String? serial, String? deviceId}) async {
    if (_phase != GrSessionPhase.idle) {
      throw StateError('GrSession.connect called in ${_phase.name}');
    }
    _serial = serial;
    _deviceId = deviceId;

    if (deviceId == null) {
      final ad = await _find(GrSessionPhase.scanning);
      _deviceId = ad.deviceId;
      _serial ??= ad.serialText;
    }

    await _connectBle(initial: true);
    // A close during the last step has let go of the link already.
    if (_closing) throw _closed;
    _set(GrSessionPhase.bluetooth, 'bluetooth', {'cameraOff': _cameraOff});
  }

  /// From [GrSessionPhase.bluetooth]: powers the camera on when it is off,
  /// reads the Wi-Fi credentials, writes WLAN-on, joins, verifies
  /// `/v1/props`, then opens the change WebSocket and starts liveness
  /// polling. On failure, or when [stopWifi] cuts it short, the phone's
  /// join is released and the session is back in
  /// [GrSessionPhase.bluetooth]. Also accepted while a [wake] started from
  /// [GrSessionPhase.bluetooth] runs: the start first waits for it to end,
  /// either way, and then goes on as from bluetooth. A call while a start
  /// runs returns that start; one while [stopWifi] is ending Wi-Fi throws
  /// [StateError].
  Future<void> startWifi() {
    final running = _wifiStart;
    if (running != null && !_wifiStopped) return running;
    if (running != null || _wifiStops > 0) {
      throw StateError('GrSession.startWifi called while Wi-Fi stops');
    }
    final wakingFromBluetooth =
        _phase == GrSessionPhase.waking &&
        _wakeCall != null &&
        _wakeReturnTo == GrSessionPhase.bluetooth;
    if (_closing ||
        (_phase != GrSessionPhase.bluetooth && !wakingFromBluetooth)) {
      throw StateError('GrSession.startWifi called in ${_phase.name}');
    }
    _wifiStop = Completer<void>();
    _endTurnOff();
    final start = _wifiStart = _startWifi();
    return start.whenComplete(() {
      if (identical(_wifiStart, start)) _wifiStart = null;
    });
  }

  Future<void> _startWifi() async {
    try {
      // A wake for BLE-only work ends first; its phase is not this start's.
      await _wakeCall;
      _checkWifiStopped(GrSessionPhase.bluetooth);
      // A dropped link may be coming back; a stop does not wait for it.
      await _until(_wifiStop.future, _bleReconnect);
      _checkWifiStopped(GrSessionPhase.bluetooth);
      if (_ble == null || _cameraOff) {
        await _oneWake(_wakeAndWlanOn);
      } else {
        await _wlanOn();
      }

      await _joinAndVerify();
      await _startWifiServices(GrSessionPhase.verifying);
      _checkWifiStopped(GrSessionPhase.verifying);
      _set(GrSessionPhase.connected, 'connected', {
        'model': _props?.model,
        'serialNo': _props?.serialNo,
        'firmwareVersion': _props?.firmwareVersion,
      });
    } catch (e) {
      // Nothing of the attempt stays, the phone's join included: the
      // phase no longer shows that Wi-Fi was in use.
      await _stopWifiServices();
      _http?.close(force: true);
      _http = null;
      await _leaveWifi();
      if (!_closing) {
        _set(GrSessionPhase.bluetooth, 'wifi.failed', {'error': '$e'});
      }
      rethrow;
    }
  }

  /// Leaves the camera's Wi-Fi and keeps BLE: an attempt or recovery in
  /// progress stops, a [wake] in progress is cut short, supervision and
  /// HTTP close, WLAN-off is written over BLE (GR WORLD's release) and the
  /// phone's join is released. With [powerOffIfWoken], a camera this
  /// session turned on ([wokeCamera]) is turned off over BLE instead
  /// (Camera Power `00`), and the link drop that follows is reported as
  /// expected (`ble.lost` with `afterPowerOff`). Nothing is written to a
  /// camera that is off ([cameraOff]): it has no access point. Ends in
  /// [GrSessionPhase.bluetooth]; does nothing before Wi-Fi was started.
  Future<void> stopWifi({bool powerOffIfWoken = false}) async {
    if (_closing || !_wifiInUse) return;
    _wifiStops++;
    try {
      await _stopWifi(powerOffIfWoken: powerOffIfWoken);
    } finally {
      _wifiStops--;
    }
  }

  Future<void> _stopWifi({required bool powerOffIfWoken}) async {
    _stopWifiWaits();
    _stopWake();
    _wakeSettle?.cancel();
    // Releasing the join first cuts a platform join short.
    await _leaveWifi();
    final start = _wifiStart;
    if (start != null) {
      try {
        await start;
      } on Object {
        // Expected: the attempt was cut short.
      }
    }
    await _wifiRecovery;
    await _afterWake;
    await _wakeCall;
    // A join that completed meanwhile is released too.
    await _leaveWifi();
    if (_closing) return;
    await _stopWifiServices();
    _http?.close(force: true);
    _http = null;
    final ble = _ble;
    if (ble != null && powerOffIfWoken && _wokeCamera) {
      await _powerOff(ble);
    } else if (ble != null && !_cameraOff) {
      await _wlanOff(ble);
    }
    _set(GrSessionPhase.bluetooth, 'wifi.stopped');
  }

  /// Whether the camera's Wi-Fi is in use: a start is running, or the
  /// Wi-Fi is under way ([_wifiUnderWay]).
  bool get _wifiInUse => _wifiStart != null || _wifiUnderWay;

  /// Whether the phone holds a join, a recovery is running, or the session
  /// is past [GrSessionPhase.bluetooth] (seen through a [wake] that set
  /// [GrSessionPhase.waking]). Unlike [_wifiInUse], false while a start
  /// has not got that far: it still waits for the Bluetooth link, or wakes
  /// the camera over it.
  bool get _wifiUnderWay {
    final phase = _phase == GrSessionPhase.waking
        ? _wakeReturnTo ?? _phase
        : _phase;
    return _wifiJoined ||
        _wifiRecovery != null ||
        phase.index > GrSessionPhase.bluetooth.index;
  }

  /// Turns the camera on over BLE with [mode], or puts a camera that is on
  /// into [mode], for BLE-only work such as remote shooting (GR WORLD's
  /// Remote screen wakes with capture, power-on-grworld.md §2.2).
  ///
  /// Allowed in [GrSessionPhase.bluetooth] and [GrSessionPhase.connected],
  /// and while [startWifi] runs; it first waits for a wake already running
  /// (that start's, including its watch over the link while the camera
  /// boots, or another [wake]), so two wakes never overlap, and for a BLE
  /// reconnect in progress.
  ///
  /// - With the link down or the camera off ([cameraOff]), it links again
  ///   if needed and, when the camera is off, writes [mode] to Operation
  ///   Mode (`power.on`), sets [wokeCamera] and watches the link for
  ///   [GrSessionOptions.wakeSettle]: a drop is linked again
  ///   (`power.relink`) and the mode checked on that link as below; a link
  ///   that stays up ends it (`power.onLinked`). At most two wake writes,
  ///   then [GrSessionException] in [GrSessionPhase.waking].
  /// - With the camera on, it runs GR WORLD's ensure-mode helper
  ///   (power-on-grworld.md §1.2, 0xe4d738): it reads Operation Mode and
  ///   writes [mode] only when it differs and is not `other` (`mode.set`).
  ///   With [keepMode] it reads Operation Mode and writes nothing
  ///   (`mode.kept`): the camera stays in the mode the user put it in
  ///   \[design\], for work that needs it on but in no particular mode.
  ///
  /// Ends with [cameraOff] false. While waking the phase is
  /// [GrSessionPhase.waking]; it then returns to the phase before
  /// (`wake.done`, or `wake.failed` on an error). [stopWifi],
  /// [powerOffIfWoken] and [close] cut it short as they do the Wi-Fi
  /// start's wake: it throws [GrSessionException] and writes nothing more.
  Future<void> wake(BleOperationMode mode, {bool keepMode = false}) {
    if (_closing ||
        (_wifiStart == null &&
            _wakeCall == null &&
            _phase != GrSessionPhase.bluetooth &&
            _phase != GrSessionPhase.connected)) {
      throw StateError('GrSession.wake called in ${_phase.name}');
    }
    _endTurnOff();
    // A wake already queued keeps a stop that came for it.
    if (_wakeCall == null) _wakeStop = Completer<void>();
    final run = _oneWake(() => _wake(mode, keepMode: keepMode));
    final call = _wakeCall = run.then<void>((_) {}, onError: (_) {});
    unawaited(
      call.whenComplete(() {
        if (identical(_wakeCall, call)) _wakeCall = null;
      }),
    );
    return run;
  }

  Future<void> _wake(BleOperationMode mode, {required bool keepMode}) async {
    void check() {
      if (_closing) {
        throw const GrSessionException(GrSessionPhase.waking, 'closed');
      }
      if (_wakeStop.isCompleted) {
        throw const GrSessionException(GrSessionPhase.waking, 'wake stopped');
      }
    }

    // The wake of a Wi-Fi start goes on watching the link while the camera
    // boots, and may link again; then a dropped link may be coming back. A
    // stop does not wait for either.
    await _until(_wakeStop.future, _afterWake);
    await _until(_wakeStop.future, _bleReconnect);
    check();
    final returnTo = _phase == GrSessionPhase.waking
        ? GrSessionPhase.bluetooth
        : _phase;
    _wakeReturnTo = returnTo;
    try {
      await _powerOn(
        mode,
        check: check,
        whenOn: ({required afterWake}) async =>
            // A camera that kept the link after the wake write is on in
            // [mode]; after a relink the mode is checked.
            afterWake || await _ensureMode(mode, check, keep: keepMode),
      );
      if (_phase == GrSessionPhase.waking) {
        _set(returnTo, 'wake.done', {
          'mode': mode.name,
          if (keepMode) 'keepMode': true,
        });
      }
    } catch (e) {
      if (_phase == GrSessionPhase.waking) {
        _set(returnTo, 'wake.failed', {'error': '$e'});
      }
      rethrow;
    } finally {
      _wakeReturnTo = null;
      _relinking = false;
      // A relink that failed, or a drop during the wake, leaves BLE to the
      // usual reconnect.
      _reconnectIfDown();
    }
  }

  /// GR WORLD's ensure-mode helper (power-on-grworld.md §1.2, 0xe4d738,
  /// called by its Remote and Import screens): reads Operation Mode and
  /// writes [mode] only when it differs and is not `other`. A value this
  /// client does not know is left alone like `other` \[design\]. With
  /// [keep] the camera's mode is only read, never written. Returns false,
  /// with [cameraOff] set, when the read finds the camera off. [check]
  /// throws when the wake was cut short meanwhile.
  Future<bool> _ensureMode(
    BleOperationMode mode,
    void Function() check, {
    required bool keep,
  }) async {
    final client = _link(GrSessionPhase.waking);
    if (client.isPresent(GrBleCatalog.operationMode) != true) return true;
    final read = await _step(
      GrSessionPhase.waking,
      'operation mode read',
      () => client.read(GrBleCatalog.operationMode),
    );
    final current = read.value?.known;
    _emit('ble.operationMode', {'value': current?.name ?? read.value?.raw});
    if (current == BleOperationMode.bleStartup) {
      _cameraOff = true;
      _emit('ble.cameraOff');
      return false;
    }
    if (keep) {
      _emit('mode.kept', {'mode': current?.name ?? read.value?.raw});
      return true;
    }
    if (current == null ||
        current == mode ||
        current == BleOperationMode.other) {
      return true;
    }
    check();
    await _step(
      GrSessionPhase.waking,
      'operation mode write',
      () => client.setOperationMode(mode),
    );
    _emit('mode.set', {'mode': mode.name, 'from': current.name});
    return true;
  }

  /// Turns the camera on as GR WORLD's home power button does: a [wake]
  /// into playback (power-on-grworld.md §1.2). The user asked for it, so
  /// the camera then does not count as one this session woke
  /// ([wokeCamera]): leaving Wi-Fi or closing the session leaves it on
  /// \[design\]. Throws as [wake] does.
  Future<void> powerOn() async {
    await wake(BleOperationMode.playback);
    _wokeCamera = false;
  }

  /// Turns the camera off as GR WORLD's home power button does (Camera
  /// Power `00`, ble.md "Camera power off"); the link drop that follows is
  /// expected (`power.off`, or `power.offFailed`). Only in
  /// [GrSessionPhase.bluetooth] with no Wi-Fi start running: leave the
  /// Wi-Fi first ([stopWifi]). A [wake] in progress is cut short first.
  /// Returns whether the camera took the write.
  Future<bool> powerOff() => _powerOffOverBle(onlyIfWoken: false);

  /// As [powerOff], but only for a camera this session turned on
  /// ([wokeCamera]), as `stopWifi(powerOffIfWoken: true)` does; a camera
  /// that a [wake] in progress turned on is turned off too. Does nothing
  /// otherwise: use `stopWifi(powerOffIfWoken: true)` while Wi-Fi is in
  /// use.
  Future<void> powerOffIfWoken() => _powerOffOverBle(onlyIfWoken: true);

  Future<bool> _powerOffOverBle({required bool onlyIfWoken}) async {
    final phase = _phase == GrSessionPhase.waking && _wakeCall != null
        ? _wakeReturnTo ?? _phase
        : _phase;
    if (_closing || phase != GrSessionPhase.bluetooth || _wifiStart != null) {
      return false;
    }
    _stopWake();
    await _wakeCall;
    final ble = _ble;
    if (_closing || ble == null || (onlyIfWoken && !_wokeCamera)) return false;
    return await _powerOff(ble);
  }

  /// Cuts a running [wake] short; its waits and drop watch end at once.
  void _stopWake() {
    if (_wakeCall == null) return;
    if (!_wakeStop.isCompleted) _wakeStop.complete();
    _wakeSettle?.cancel();
  }

  /// Turns the camera off (Camera Power `00`, GR WORLD's power-off flow)
  /// and starts waiting for it to settle ([turningOff]); the link drops
  /// that follow are reported as expected. Returns whether the camera took
  /// the write.
  Future<bool> _powerOff(GrBleClient ble) async {
    // The camera may drop the link before the write is answered.
    _turningOff = true;
    _turnOffLimit?.cancel();
    _turnOffLimit = Timer(
      options.bleLostAfter + options.powerOffGuard,
      () => _endTurnOff('power.offUnsettled'),
    );
    try {
      await ble.powerOff();
    } on Object catch (e) {
      _endTurnOff();
      _emit('power.offFailed', {'error': '$e'});
      return false;
    }
    _cameraOff = true;
    _wokeCamera = false;
    _emit('power.off');
    return true;
  }

  /// Ends [turningOff], reporting [event] when the camera settled
  /// (`power.offSettled`) or did not in time (`power.offUnsettled`).
  void _endTurnOff([String? event]) {
    if (!_turningOff) return;
    _turningOff = false;
    _turnOffLimit?.cancel();
    _turnOffLimit = null;
    if (event == null) return;
    _emit(event, {'linked': _ble != null, 'cameraOff': _cameraOff});
  }

  /// Runs [body] once no other wake is running.
  Future<void> _oneWake(Future<void> Function() body) async {
    for (var r = _wakeRunning; r != null; r = _wakeRunning) {
      await r;
    }
    final done = Completer<void>();
    _wakeRunning = done.future;
    try {
      await body();
    } finally {
      _wakeRunning = null;
      done.complete();
    }
  }

  /// Cuts the Wi-Fi start's or recovery's waits short.
  void _stopWifiWaits() {
    if (!_wifiStop.isCompleted) _wifiStop.complete();
  }

  /// Releases the phone's join, when this session holds one.
  Future<void> _leaveWifi() async {
    if (!_wifiJoined) return;
    _wifiJoined = false;
    try {
      await wifi.leave();
    } on Object {
      // Not joined; nothing to release.
    }
  }

  /// Turns the camera's Wi-Fi off over [ble] (WLAN Control `00`, GR
  /// WORLD's release); a write that fails is reported and nothing more.
  Future<void> _wlanOff(GrBleClient ble) async {
    try {
      await ble.setWlan(on: false);
      _emit('wlan.off');
    } on Object catch (e) {
      _emit('wlan.offFailed', {'error': '$e'});
    }
  }

  void _checkWifiStopped(GrSessionPhase phase) {
    if (_closing) throw GrSessionException(phase, 'closed');
    if (_wifiStopped) throw GrSessionException(phase, 'Wi-Fi stopped');
  }

  /// Stops supervision, releases the phone's join, and closes the
  /// WebSocket, HTTP client and BLE link; a scan or a setup step still in
  /// flight ends without changing the phase. A camera that is linked and
  /// on has its Wi-Fi turned off over BLE first ([_wlanOff]), as GR
  /// WORLD's explicit disconnect does
  /// (research/protocol/connection-lifecycle.md), whether or not this
  /// session turned it on \[design\]: a session that ended without
  /// closing (the app was stopped) leaves it on, and nothing else turns
  /// it off. [powerOff] turns the camera off over BLE instead (Camera
  /// Power `00`, as GR WORLD's power-off flow) after Wi-Fi supervision has
  /// stopped, so the loss is not reported. [powerOffIfWoken] does so only
  /// when the session turned the camera on ([wokeCamera]); a wake still in
  /// flight ([wake], or a Wi-Fi start's) is cut short and let finish
  /// first, so one whose write lands during the close is not missed.
  Future<void> close({
    bool powerOff = false,
    bool powerOffIfWoken = false,
  }) async {
    if (_phase == GrSessionPhase.closed) return;
    _closing = true;
    if (!_closeSignal.isCompleted) _closeSignal.complete();
    _wakeSettle?.cancel();
    _endTurnOff();
    _stopWifiWaits();
    _stopWake();
    // Releasing the join first cuts a platform join short; the start,
    // recovery and post-wake relink then end on [_closing], and release a
    // join that completes meanwhile themselves.
    await _leaveWifi();
    var turnOff = powerOff;
    if (powerOffIfWoken) {
      try {
        await _wifiStart;
      } on Object {
        // Expected: the attempt was cut short.
      }
      await _wifiRecovery;
      // A wake that went through meanwhile need not watch for its drop.
      _wakeSettle?.cancel();
      await _afterWake;
      await _wakeCall;
      turnOff = turnOff || _wokeCamera;
    }
    // A camera being turned off takes its access point with it, and one
    // that is off has none.
    final ble = _ble;
    if (ble != null && !turnOff && !_cameraOff) await _wlanOff(ble);
    await _stopWifiServices();
    if (turnOff && ble != null) {
      try {
        await ble.powerOff();
        _wokeCamera = false;
        _emit('power.off');
      } on Object catch (e) {
        _emit('power.offFailed', {'error': '$e'});
      }
    }
    _http?.close(force: true);
    _http = null;
    await _powerSub?.cancel();
    _unpark();
    _ble = null;
    if (ble != null) {
      try {
        await ble.connection.disconnect();
      } on Object {
        // Already down; the link state is what matters.
      }
    }
    _set(GrSessionPhase.closed, 'closed');
    await _events.close();
    await _propsUpdates.close();
  }

  // ------------------------------------------------------------------ BLE

  Future<GrAdvertisement> _find(GrSessionPhase phase) async {
    _set(phase, 'scan.start', {'serial': _serial, 'deviceId': _deviceId});
    final ad = await findGrAdvertisement(
      // close() ends the scan; it fails with [_closed].
      _ScanUntilClosed(transport, _closeSignal.future),
      timeout: options.scanTimeout,
      where: (a) =>
          a.isGrCamera &&
          (_deviceId == null || a.deviceId == _deviceId) &&
          (_serial == null || grSerialMatches(_serial!, a.serialNumber)),
    );
    if (ad == null) {
      throw GrSessionException(
        phase,
        'no GR camera advertisement within ${options.scanTimeout.inSeconds} s',
      );
    }
    _advertisement = ad;
    _emit('scan.found', {
      'deviceId': ad.deviceId,
      'model': ad.model?.name,
      'serial': ad.serialText,
      'powerOn': ad.powerOn,
      'rssi': ad.rssi,
    });
    return ad;
  }

  /// Links over BLE, trying again when a connect fails. With [until], no
  /// connect runs past it and none is started after it.
  Future<void> _connectBle({required bool initial, DateTime? until}) async {
    final poweredOffAt = _poweredOffAt;
    if (poweredOffAt != null) {
      var waited = Duration.zero;
      // close() and the time the caller has left end the wait early.
      await _until(
        _closeSignal.future,
        waitAfterPowerOff(
          poweredOffAt,
          guard: options.powerOffGuard,
          trace: _trace,
        ).then<void>((d) {
          waited = d;
          if (_poweredOffAt == poweredOffAt) _poweredOffAt = null;
        }),
        until?.difference(DateTime.now()),
      );
      if (waited > Duration.zero) {
        _emit('ble.powerOffGuard', {'waitedMs': waited.inMilliseconds});
      }
    }
    // close() may have ended a scan or a power-off guard just now.
    if (_closing) throw _closed;
    if (initial) _set(GrSessionPhase.bleConnecting, 'ble.connect');
    for (var attempt = 1; ; attempt++) {
      try {
        await _openBle(until);
        return;
      } on GrSessionException catch (e) {
        // The first link to an off camera drops (supervision timeout
        // ~5.5 s); GR WORLD reconnects ~0.1 s later. A lost bond is final.
        if (_closing ||
            e.needsPairing ||
            attempt >= options.bleConnectAttempts ||
            _isPast(until)) {
          rethrow;
        }
        _emit('ble.connectRetry', {'attempt': attempt, 'error': '$e'});
        await Future<void>.delayed(options.bleConnectRetryDelay);
      }
    }
  }

  /// One connect: link, discovery, power-on check, encrypted identity. The
  /// link has until [until] to open when that is sooner than
  /// [GrSessionOptions.bleConnectTimeout].
  Future<void> _openBle(DateTime? until) async {
    final left = until?.difference(DateTime.now());
    final timeout = left != null && left < options.bleConnectTimeout
        ? left
        : options.bleConnectTimeout;
    // close() may have started during a retry pause or a power-off guard.
    if (_closing) throw _closed;
    final connection = await _step(
      GrSessionPhase.bleConnecting,
      'BLE connect',
      () => transport.connect(_deviceId!, timeout: timeout),
    );
    final client = GrBleClient(connection, trace: _trace);
    final GrBleDiscoveryReport report;
    try {
      report = await _step(
        GrSessionPhase.bleConnecting,
        'GATT discovery',
        client.discover,
      );
      await _checkOperationMode(client);
      // A bonded link reads Camera Information; an unauthorized read here
      // means the camera no longer holds our keys (needsPairing).
      await _step(
        GrSessionPhase.bleConnecting,
        'serial read',
        () => client.read(GrBleCatalog.serialNumber),
      );
      _identity = await _step(
        GrSessionPhase.bleConnecting,
        'identity read',
        client.readIdentity,
      );
      // close() started while this link was opening (a reconnect or the
      // relink after a wake) and could not reach it.
      if (_closing) throw _closed;
    } on Object {
      // Not yet in [_ble], so close() could not reach this link.
      try {
        await connection.disconnect();
      } on Object {
        // Already down; the setup failure is what matters.
      }
      rethrow;
    }
    _ble = client;
    _bleLostUnexpectedly = false;
    _bondLost = false;
    _unpark();
    _emit('ble.ready', {
      'missingCharacteristics': report.missing.length,
      'identity': {
        'modelName': _identity!.modelName,
        'serialNumber': _identity!.serialNumber,
        'firmwareRevision': _identity!.firmwareRevision,
      },
    });
    if (_cameraOff) _endTurnOff('power.offSettled');
    await _powerSub?.cancel();
    if (client.isPresent(GrBleCatalog.cameraPower) ?? false) {
      _powerSub = client.watch(GrBleCatalog.cameraPower).listen((n) {
        _emit('ble.cameraPower', n.toJson());
        switch (n.decoded.value?.known) {
          case BleCameraPower.off:
            _cameraOff = true;
            // Its power button, or the camera itself: whoever turned it
            // on, nothing is left for this session to turn off later. A
            // power-off this session wrote has cleared this already.
            _wokeCamera = false;
            // With its Wi-Fi in use the access point goes too, ahead of
            // what liveness or the OS would report.
            _wifiLost('cameraOff');
          case BleCameraPower.on:
            _wakeSettle?.cameraOn();
            _cameraTurnedOn();
          case BleCameraPower.sleep || null:
        }
      }, onError: (Object e) => _emit('ble.cameraPowerError', {'error': '$e'}));
    }
    unawaited(
      connection.disconnected.then((d) => _onBleDisconnected(client, d)),
    );
  }

  static const _closed = GrSessionException(
    GrSessionPhase.bleConnecting,
    'the session closed',
  );

  /// GR WORLD's power-on check (0xd403b8, on every connect): Operation Mode
  /// `02` (bleStartup) means the camera is off in its BT-only state. Only
  /// [startWifi] and [wake] wake it ([_powerOn]); automatic reconnects and
  /// Wi-Fi recovery never power a camera on. A camera found off on a link
  /// no wake opened turned off without the session asking, so it no longer
  /// counts as one the session turned on ([wokeCamera]).
  Future<void> _checkOperationMode(GrBleClient client) async {
    if (client.isPresent(GrBleCatalog.operationMode) != true) return;
    final mode = await _step(
      GrSessionPhase.bleConnecting,
      'operation mode read',
      () => client.read(GrBleCatalog.operationMode),
    );
    final known = mode.value?.known;
    _emit('ble.operationMode', {'value': known?.name ?? mode.value?.raw});
    _cameraOff = known == BleOperationMode.bleStartup;
    if (!_cameraOff) return;
    if (!_relinking) _wokeCamera = false;
    _emit('ble.cameraOff');
  }

  /// Reads the Wi-Fi credentials (once per session) and writes WLAN-on.
  Future<void> _wlanOn() async {
    final ble = _link(GrSessionPhase.wlanOn);
    final credentials =
        _credentials ??
        await _step<GrWifiCredentials>(
          GrSessionPhase.bleConnecting,
          'reading Wi-Fi credentials',
          ble.readWifiCredentials,
        );
    _credentials = credentials;
    _emit('wifi.credentials', {
      'ssid': credentials.ssid,
      'wifiSecurity': credentials.wifiSecurity?.name,
      'securityAssumed': credentials.securityAssumed,
      'frequency': credentials.frequency?.toJson(),
      'channel': credentials.channel?.toJson(),
      if (credentials.issues.isNotEmpty) 'issues': credentials.issues,
    });

    // Stopped or closed while the credentials were read: no WLAN-on.
    _checkWifiStopped(GrSessionPhase.wlanOn);
    _set(GrSessionPhase.wlanOn, 'wlan.on');
    await _step(
      GrSessionPhase.wlanOn,
      'WLAN-on write',
      () => ble.setWlan(on: true),
    );
  }

  /// Reads WLAN Security again for credentials that had it present but
  /// unreadable or undocumented (GrWifiCredentials.wifiSecurity null); no
  /// link, a failed read or no known value returns null.
  Future<WifiSecurity?> _readSecurityAgain() async {
    final ble = _ble;
    if (ble == null) {
      _emit('wifi.securityReadFailed', {'error': 'the Bluetooth link dropped'});
      return null;
    }
    try {
      final decoded = await ble.read(GrBleCatalog.wlanSecurity);
      final security = decoded.value?.known?.wifiSecurity;
      _emit('wifi.securityRead', {
        'security': security?.name,
        'raw': decoded.value?.raw,
        if (decoded.issues.isNotEmpty) 'issues': decoded.issues,
      });
      return security;
    } on Object catch (e) {
      _emit('wifi.securityReadFailed', {'error': '$e'});
      return null;
    }
  }

  /// Makes sure a Wi-Fi start has a link to a camera that is on, then
  /// writes WLAN-on: links again when the link is down, and wakes a camera
  /// in its BT-only state.
  ///
  /// After the wake write the camera boots its main firmware. The link may
  /// stay up (GR IV HDF, 2026-11-08) or go silent and drop ~5.5-8 s after it
  /// opened (2026-11-07), and whether WLAN-on written while the camera boots
  /// takes effect is \[unknown\]. So the credentials and WLAN-on go out at
  /// once rather than after [GrSessionOptions.wakeSettle]:
  /// - if they fail, the session waits out wakeSettle for a drop, links
  ///   again if one came (checking the mode on that link), and writes them
  ///   then, as before;
  /// - if they go through, the join starts at once while [_settleAfterWake]
  ///   watches the link for wakeSettle and writes WLAN-on once more if the
  ///   join has not got through by then.
  ///
  /// A wake lost to a drop is written once more ([_powerOn]).
  Future<void> _wakeAndWlanOn() async {
    _relinking = true;
    var watching = false;
    try {
      await _powerOn(
        options.powerOnMode,
        check: () => _checkWifiStopped(GrSessionPhase.waking),
        whenOn: ({required afterWake}) async {
          await _wlanOn();
          return true;
        },
        afterWrite: (settle) async {
          try {
            await _wlanOn();
            _cameraOff = false;
            watching = true;
            final after = _afterWake = _settleAfterWake(settle);
            unawaited(
              after.whenComplete(() {
                if (identical(_afterWake, after)) _afterWake = null;
              }),
            );
            return true;
          } catch (e) {
            if (_closing || _wifiStopped) {
              settle.cancel();
              rethrow;
            }
            _emit('wlan.onEarlyFailed', {'error': '$e'});
            return false;
          }
        },
      );
    } finally {
      if (!watching) {
        _relinking = false;
        // A drop the wake did not link again goes to the usual reconnect.
        _reconnectIfDown();
      }
    }
  }

  /// The wake shared by [wake] and the Wi-Fi start: links again when the
  /// link is down; with the camera on, runs [whenOn] (`afterWake: false` =
  /// it found the camera off after all); otherwise writes [mode] to
  /// Operation Mode (GR WORLD's power-on write, power-on-grworld.md §1.2)
  /// and sets [wokeCamera]. [check] throws when the caller was stopped or
  /// closed, after which nothing more is written. Then [afterWrite], if
  /// given, may finish the wake while the link is watched; otherwise the
  /// link is watched for [GrSessionOptions.wakeSettle]: a link that stays
  /// up has the camera on (`power.onLinked`, then [whenOn] with
  /// `afterWake: true`), a drop is linked again (`power.relink`) and
  /// checked from the top. At most two wake writes.
  Future<void> _powerOn(
    BleOperationMode mode, {
    required void Function() check,
    required Future<bool> Function({required bool afterWake}) whenOn,
    Future<bool> Function(_WakeSettle settle)? afterWrite,
  }) async {
    for (var wakes = 0; ; wakes++) {
      if (_ble == null) await _connectBle(initial: false);
      check();
      if (!_cameraOff && await whenOn(afterWake: false)) return;
      if (wakes == 2) {
        throw const GrSessionException(
          GrSessionPhase.waking,
          'the camera did not turn on',
        );
      }
      final client = _link(GrSessionPhase.waking);
      _set(GrSessionPhase.waking, 'power.on', {'mode': mode.name});
      // The camera may drop the link while it boots; that drop belongs to
      // the wake, not to the BLE reconnect.
      _relinking = true;
      // Reachable by stopWifi and close, which end the watch early.
      // A Wi-Fi start's watch runs its full time: it ends with WLAN-on
      // written once more ([_settleAfterWake]). The watch is there before
      // the write, so that a camera reporting that it is on before the
      // write is answered is heard; its time runs from the answer.
      final settle = _wakeSettle = _WakeSettle(
        client,
        options.wakeSettle,
        endsWhenOn: afterWrite == null,
      );
      try {
        await _step(
          GrSessionPhase.waking,
          'operation mode write',
          () => client.setOperationMode(mode),
        );
        _wokeCamera = true;
        // Stopped or closed while that write was in flight: the caller
        // decides about power from [wokeCamera]; nothing more is written.
        check();
      } on Object {
        settle.cancel();
        if (identical(_wakeSettle, settle)) _wakeSettle = null;
        rethrow;
      }
      settle.start();
      if (afterWrite != null && await afterWrite(settle)) return;
      final dropped = await settle.ended;
      if (identical(_wakeSettle, settle)) _wakeSettle = null;
      check();
      if (!dropped) {
        _cameraOff = false;
        _emit('power.onLinked', {if (settle.reportedOn) 'reportedOn': true});
        await whenOn(afterWake: true);
        return;
      }
      _ble = null;
      _emit('power.relink');
    }
  }

  /// The rest of a wake whose early WLAN-on went through: a drop within
  /// [GrSessionOptions.wakeSettle] is linked again, and WLAN-on is written
  /// once more while the join is still looking for the camera's network, in
  /// case the camera ignored the early write while it booted. A join that
  /// got through is left alone: writing WLAN-on to a running access point is
  /// \[unknown\].
  Future<void> _settleAfterWake(_WakeSettle settle) async {
    try {
      await settle.ended;
      if (_closing) return;
      if (settle.dropped) {
        _ble = null;
        _emit('power.relink');
        await _connectBle(initial: false);
      }
      if (_wifiStopped || _phase != GrSessionPhase.joining) return;
      final ble = _link(GrSessionPhase.joining);
      await _step(
        GrSessionPhase.joining,
        'WLAN-on write',
        () => ble.setWlan(on: true),
      );
      _emit('wlan.again');
    } on Object catch (e) {
      if (!_closing) _emit('wlan.againFailed', {'error': '$e'});
    } finally {
      if (identical(_wakeSettle, settle)) _wakeSettle = null;
      _relinking = false;
      // A relink that failed leaves BLE to the usual reconnect.
      _reconnectIfDown();
    }
  }

  /// [client]'s link dropped. Only the current link counts: a late drop of
  /// an older one must not clear a newer link. During a wake the link is
  /// cleared too, but the wake links again, and hands the loss to the
  /// usual reconnect when it fails. A drop of a camera that is being
  /// turned off, or is off, is linked again without counting as a loss
  /// ([bleReconnecting]).
  void _onBleDisconnected(GrBleClient client, BleDisconnect d) {
    if (_closing || !identical(_ble, client)) return;
    _ble = null;
    _poweredOffAt = client.lastPowerOff ?? _poweredOffAt;
    final fields = {
      'requested': d.requested,
      'reason': d.reason,
      if (d.bondRejected) 'bondRejected': true,
    };
    if (_relinking) {
      _emit('ble.lostWhileWaking', fields);
      return;
    }
    _bleLostUnexpectedly = !_turningOff && !_cameraOff && !d.bondRejected;
    _emit('ble.lost', {
      ...fields,
      if (_turningOff) 'afterPowerOff': true,
      if (_cameraOff) 'cameraOff': true,
    });
    if (d.bondRejected) {
      _endTurnOff();
      _bondLost = true;
      _emit('ble.needsPairing');
      return;
    }
    _reconnectIfDown();
  }

  /// Starts the BLE reconnect when the link is down and nothing else is
  /// linking again. A link that drops as soon as the reconnect restored
  /// it, before that reconnect ended, starts another. A camera that is
  /// off is not linked again ([parked]), except once after the session
  /// turned it off ([turningOff]), to see it settle.
  void _reconnectIfDown() {
    if (_closing ||
        _relinking ||
        _bondLost ||
        _ble != null ||
        _bleReconnect != null) {
      return;
    }
    if (_cameraOff && !_turningOff) {
      _park();
      return;
    }
    _bleReconnect = _reconnectBle().then((restored) {
      _bleReconnect = null;
      if (restored) _reconnectIfDown();
    });
  }

  /// Lets go of a camera that is off and starts reading its
  /// advertisements for the one that says it is on ([parked]).
  void _park() {
    if (_parked) return;
    _parked = true;
    _emit('ble.parked');
    _parkWatch = transport
        .scan(serviceUuids: [GrBleServices.cameraInformation.uuid])
        .listen(
          (ad) {
            final seen = GrAdvertisement(ad);
            if (!_isThisCamera(seen)) return;
            // The service filter is the platform's; the tag is checked
            // too where a result carries it.
            if ((seen.powerOn ?? seen.powerOnFromServices) ?? false) {
              _seenOn();
            }
          },
          // Without a scan (Bluetooth off, or another owner's scan
          // running) only a wake links the camera.
          onError: (Object e) => _emit('ble.parkWatchFailed', {'error': '$e'}),
        );
  }

  /// Whether [ad] is this session's camera: its device id, or without one
  /// its serial number.
  bool _isThisCamera(GrAdvertisement ad) {
    final deviceId = _deviceId;
    if (deviceId != null) return ad.deviceId == deviceId;
    final serial = _serial;
    return serial != null && grSerialMatches(serial, ad.serialNumber);
  }

  /// Ends [parked] and its scan.
  void _unpark() {
    if (!_parked) return;
    _parked = false;
    unawaited(_parkWatch?.cancel());
    _parkWatch = null;
  }

  /// A [parked] camera advertises that it is on: links it. A wake links
  /// by itself.
  void _seenOn() {
    if (!_parked ||
        _closing ||
        _relinking ||
        _bondLost ||
        _wakeRunning != null ||
        _ble != null ||
        _bleReconnect != null) {
      return;
    }
    _emit('ble.seenOn');
    _bleReconnect = _relinkParked().then((_) {
      _bleReconnect = null;
      // A wake that came meanwhile, or a camera that was off after all.
      _reconnectIfDown();
    });
  }

  /// Links a [parked] camera that advertised being on. A link that cannot
  /// be made leaves the session parked, reading advertisements again
  /// after the first [GrSessionOptions.bleReconnectDelays] pause: the
  /// camera was switched off again, or went out of reach.
  Future<void> _relinkParked() async {
    try {
      await _connectBle(initial: false);
      _emit('ble.restored', {'afterPark': true});
    } on Object catch (e) {
      _emit('ble.seenOnFailed', {'error': '$e'});
      if (e is GrSessionException && e.needsPairing) {
        _unpark();
        _bondLost = true;
        _emit('ble.needsPairing');
        return;
      }
      await _until(
        _closeSignal.future,
        Future<void>.delayed(_delay(options.bleReconnectDelays, 0)),
      );
    }
  }

  /// The camera reported being on (Camera Power `01`) over a link that
  /// found it off, with no wake of this session's running: its own power
  /// button. Whether a GR IV notifies this on a link held in its BT-only
  /// state is \[unknown\] (research/protocol/power-on-grworld.md §8); a
  /// camera that drops the link instead is found by its advertisement
  /// ([parked]).
  void _cameraTurnedOn() {
    if (!_cameraOff || _relinking || _wakeRunning != null) return;
    _cameraOff = false;
    _emit('ble.cameraOn');
  }

  /// The current link, for a step in [phase] that needs one.
  GrBleClient _link(GrSessionPhase phase) =>
      _ble ?? (throw GrSessionException(phase, 'the Bluetooth link dropped'));

  /// Reconnects BLE only; Wi-Fi state is untouched (no WLAN writes). Stops
  /// for good when the bond is gone, when the attempts are used up and,
  /// unless the camera's Wi-Fi is in use, once the link has been down for
  /// [GrSessionOptions.bleLostAfter]: nothing reaches the camera then, so
  /// it counts as gone. Returns whether the link is back.
  Future<bool> _reconnectBle() async {
    final lostAt = DateTime.now();
    final goneAt = lostAt.add(options.bleLostAfter);
    // With its Wi-Fi under way the camera is still reached, and a Wi-Fi
    // that goes too has its own wait for this link ([_recoverWifi]). A
    // start that only waits for this link reaches nothing.
    DateTime? deadline() => _wifiUnderWay ? null : goneAt;
    var attempts = 0;
    while (attempts < options.maxBleReconnectAttempts) {
      await _until(
        _closeSignal.future,
        Future<void>.delayed(_delay(options.bleReconnectDelays, attempts)),
        deadline()?.difference(DateTime.now()),
      );
      if (_closing) return false;
      final until = deadline();
      if (_isPast(until)) break;
      attempts++;
      _emit('ble.reconnect', {'attempt': attempts});
      try {
        await _connectBle(initial: false, until: until);
        _emit('ble.restored', {'attempt': attempts});
        return true;
      } on Object catch (e) {
        _emit('ble.reconnectFailed', {'attempt': attempts, 'error': '$e'});
        if (e is! GrSessionException) continue;
        if (e.needsPairing) {
          _bleLostUnexpectedly = false;
          _endTurnOff();
          _bondLost = true;
          _emit('ble.needsPairing');
          return false;
        }
      }
    }
    _bleLostUnexpectedly = false;
    if (_cameraOff) {
      // Turned off by this session and not linked again in its off state:
      // it is left alone like any camera that is off, not given up on.
      _endTurnOff('power.offUnsettled');
      _park();
      return false;
    }
    _endTurnOff();
    _emit('ble.gaveUp', {
      'attempts': attempts,
      'downMs': DateTime.now().difference(lostAt).inMilliseconds,
    });
    return false;
  }

  static bool _isPast(DateTime? time) =>
      time != null && !DateTime.now().isBefore(time);

  // ---------------------------------------------------------------- Wi-Fi

  /// Joins the camera's network and verifies it is the camera.
  ///
  /// One security type per camera: Android approves a camera network per
  /// app and security type, so alternating WPA3 and WPA2 asks the user
  /// twice. Transition-mode APs accept WPA2, which is what GR WORLD's
  /// approval on a test phone records (GR IV HDF, 2026-11-08).
  ///
  /// Security the credentials left unknown (the camera has the
  /// characteristic, but it could not be read or decoded) is read once
  /// more in the joining phase, so a wake's [_settleAfterWake] can still
  /// write WLAN-on again meanwhile; the read counts against
  /// [GrSessionOptions.joinTimeout]. Still unknown, it is tried both ways
  /// \[design\]: WPA2 for the first half of the join time left, then WPA3
  /// for the rest, each attempt traced with its security. WPA2 first
  /// because GR WORLD joins an unknown security type with WPA2
  /// (research/protocol/connection-lifecycle.md §3), the GR IV's hostapd
  /// generator takes its WPA2 branch when its security property cannot be
  /// read or holds an unknown value, and WPA2 joins a transition-mode AP
  /// (research/firmware-network-config.md §2); WPA3 then reaches a
  /// WPA3-only AP, whose SAE-only, PMF-required configuration a WPA2 join
  /// cannot use. Only this case may ask for approval twice. The security
  /// that got through is kept for later joins.
  Future<void> _joinAndVerify() async {
    final c = _credentials!;
    final deadline = DateTime.now().add(options.joinTimeout);
    _joinSecurity ??= c.wifiSecurity;
    if (_joinSecurity == null) {
      _set(_joiningPhase, 'wifi.securityUnknown');
      _joinSecurity = await _readSecurityAgain();
      _checkWifiStopped(GrSessionPhase.joining);
    }
    final known = _joinSecurity;
    final tries = known == null
        ? [
            (WifiSecurity.wpa2, _halfwayTo(deadline)),
            (WifiSecurity.wpa3, deadline),
          ]
        : [
            (
              known == WifiSecurity.wpa3
                  ? WifiSecurity.wpa3
                  : WifiSecurity.wpa2,
              deadline,
            ),
          ];
    for (final (index, (security, until)) in tries.indexed) {
      final last = index == tries.length - 1;
      if (!await _join(c, security, until, last: last)) continue;
      _joinSecurity ??= security;
      _emit('wifi.joined', {'security': security.name});
      await _verify();
      return;
    }
  }

  /// Halfway between now and [deadline].
  static DateTime _halfwayTo(DateTime deadline) {
    final now = DateTime.now();
    return now.add(deadline.difference(now) ~/ 2);
  }

  /// The phase of a join: recovery keeps its own.
  GrSessionPhase get _joiningPhase =>
      _phase == GrSessionPhase.recovering ? _phase : GrSessionPhase.joining;

  /// Joins [c]'s network with [security] until [until]. False when that
  /// passed without a join and another security follows; throws when this
  /// was the [last].
  Future<bool> _join(
    GrWifiCredentials c,
    WifiSecurity security,
    DateTime until, {
    required bool last,
  }) async {
    _set(_joiningPhase, 'wifi.join', {
      'ssid': c.ssid,
      'security': security.name,
    });
    // The AP comes up several seconds after WLAN-on (GR IV HDF: a join at
    // 0 s found no network, one at 16 s succeeded), so retry until [until].
    var attempt = 0;
    // The latest suspected VPN block, kept through timeouts: those say
    // nothing about routing, and the last try is often cut short by the
    // deadline. Any other failure clears it.
    WifiJoinVpnSuspected? vpnSuspected;
    while (true) {
      // close() or stopWifi() during the hand-off must not leave the phone
      // retrying, and possibly joining, the camera's network afterwards.
      _checkWifiStopped(GrSessionPhase.joining);
      attempt++;
      try {
        // Held from the request on: a pending join is released as well.
        _wifiJoined = true;
        await wifi.join(
          ssid: c.ssid,
          passphrase: c.passphrase,
          security: security,
          timeout: until.difference(DateTime.now()),
        );
        // A stop or close released the join while it was pending; it went
        // through all the same, so it is released again here.
        _wifiJoined = true;
        if (_closing || _wifiStopped) {
          await _leaveWifi();
          _checkWifiStopped(GrSessionPhase.joining);
        }
        return true;
      } on WifiJoinDeclined catch (e) {
        _emit('wifi.declined');
        throw GrSessionException(GrSessionPhase.joining, 'declined', e);
      } catch (e) {
        if (e is WifiJoinVpnSuspected) {
          vpnSuspected = e;
        } else if (e is! TimeoutException) {
          vpnSuspected = null;
        }
        final remaining = until.difference(DateTime.now());
        _emit('wifi.joinRetry', {
          'attempt': attempt,
          'security': security.name,
          'remainingMs': remaining.inMilliseconds,
          'error': '$e',
        });
        if (remaining > options.joinRetryDelay) {
          await Future<void>.delayed(options.joinRetryDelay);
          continue;
        }
        if (last) {
          throw GrSessionException(
            GrSessionPhase.joining,
            'join failed',
            vpnSuspected ?? e,
          );
        }
        return false;
      }
    }
  }

  Future<void> _verify() async {
    // close() may have let go of the HTTP client; none is made after it.
    _checkWifiStopped(GrSessionPhase.verifying);
    if (_phase != GrSessionPhase.recovering) {
      _set(GrSessionPhase.verifying, 'verify.start');
    }
    final http = _http ??= _httpFactory(host, _trace);
    final deadline = DateTime.now().add(options.verifyTimeout);
    Object? lastError;
    var probes = 0;
    while (true) {
      probes++;
      _checkWifiStopped(GrSessionPhase.verifying);
      try {
        final props = await http.props(
          connectTimeout: options.verifyProbeTimeout,
          timeout: options.verifyProbeTimeout,
        );
        final problems = verifyCameraProps(
          props,
          expectedSsid: _credentials?.ssid,
          expectedSerial: _identity?.serialNumber,
          expectedModel: _identity?.modelName,
        );
        if (problems.isNotEmpty) {
          throw GrSessionException(
            GrSessionPhase.verifying,
            'joined a different camera: ${problems.join('; ')}',
          );
        }
        _setProps(props);
        _emit('verify.ok', {
          'probes': probes,
          'model': props.model,
          'serialNo': props.serialNo,
          'firmwareVersion': props.firmwareVersion,
        });
        return;
      } on GrSessionException {
        rethrow;
      } on Object catch (e) {
        lastError = e;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw GrSessionException(
          GrSessionPhase.verifying,
          'no /v1/props answer within ${options.verifyTimeout.inSeconds} s '
          'after $probes probes',
          lastError,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Opens the change WebSocket and starts liveness probing, for a start or
  /// recovery in [phase]. Throws when [stopWifi] or [close] came meanwhile,
  /// leaving nothing running. A socket whose first open fails is retried by
  /// its reconnect policy while HTTP probing runs; Wi-Fi is not rejoined
  /// for it (connection-imagesync.md §2.2).
  ///
  /// `/v1/props` was read when the join was verified, as GR WORLD reads it
  /// once per join, and is read again only when the camera announces a
  /// battery or storage change on the socket ([_refreshProps]) \[design\];
  /// the probes do not read it.
  Future<void> _startWifiServices(GrSessionPhase phase) async {
    _checkWifiStopped(phase);
    final http = _http!;
    final changes = _changes ??= http.changesSocket();
    try {
      await changes.connect();
      _emit('changes.open');
    } on Object catch (e) {
      // The WebSocket is an extra signal; liveness polling still runs.
      _emit('changes.failed', {
        'error': '$e',
        'state': changes.status.state.name,
      });
    }
    if (_closing || _wifiStopped) {
      // The stop may have closed the services already; these are not
      // started and the socket is closed.
      if (identical(_changes, changes)) _changes = null;
      await changes.close();
      _checkWifiStopped(phase);
    }
    final monitor = LivenessMonitor(
      http,
      interval: options.livenessInterval,
      failureThreshold: options.livenessFailureThreshold,
      lossAfter: options.livenessLossAfter,
      trace: _trace,
    );
    _monitor = monitor;
    unawaited(
      monitor.lost.then((poll) {
        if (identical(_monitor, monitor)) {
          _wifiLost('liveness', poll.toJson());
        }
      }),
    );
    _lostSub = wifi.lost.listen((_) => _wifiLost('network'));
    _changesSub = changes.events.listen((event) {
      if (event is GrBatteryChange || event is GrStorageChange) {
        unawaited(_refreshProps(changes, http));
      }
    });
    monitor.start();
  }

  /// Reads `/v1/props` over [http] after the camera announced on [changes]
  /// that its battery or storages changed, which is what the session's
  /// readers take from it over Wi-Fi. One read runs at a time for
  /// [changes]; changes it announces during the read are covered by one
  /// more read after it.
  Future<void> _refreshProps(GrChangesSocket changes, GrHttpClient http) async {
    _propsStale = true;
    if (identical(_propsRefreshingFor, changes)) return;
    _propsRefreshingFor = changes;
    try {
      while (_propsStale && identical(_changes, changes)) {
        _propsStale = false;
        try {
          final props = await http.props();
          if (identical(_changes, changes)) _setProps(props);
        } on Object catch (e) {
          // Liveness and the caller's own requests judge the link.
          _emit('props.refreshFailed', {'error': '$e'});
        }
      }
    } finally {
      // A later socket's reads may have taken over meanwhile.
      if (identical(_propsRefreshingFor, changes)) _propsRefreshingFor = null;
    }
  }

  /// Records a `/v1/props` reading taken on this session's HTTP client
  /// outside the session (live view's settings reads), so [props] and
  /// [propsUpdates] stay the newest reading from any source.
  void recordProps(GrProps props) {
    if (_closing) return;
    _setProps(props);
  }

  void _setProps(GrProps props) {
    _props = props;
    if (!_propsUpdates.isClosed) _propsUpdates.add(props);
  }

  /// Whether the camera still answers over Wi-Fi, for a caller whose
  /// request just failed: one identity probe, no retries. When it does not
  /// answer the link counts as lost at once, as when liveness gives up.
  Future<bool> checkWifi() async {
    if (_phase != GrSessionPhase.connected) return false;
    final monitor = _monitor;
    if (await _cameraAnswers()) return true;
    if (identical(_monitor, monitor)) _wifiLost('check');
    return false;
  }

  /// The Wi-Fi link is gone ([reason] `liveness`, `network` when the OS
  /// said so, `check`, or `cameraOff` when the camera reported turning
  /// off): emits `wifi.lost`, then recovers.
  void _wifiLost(String reason, [Map<String, Object?> fields = const {}]) {
    if (_closing || _monitor == null || _wifiRecovery != null) return;
    _wifiRecovering = true;
    _emit('wifi.lost', {'reason': reason, ...fields});
    _wifiRecovery = _recoverWifi().whenComplete(() {
      _wifiRecovery = null;
      _wifiRecovering = false;
    });
  }

  Future<void> _stopWifiServices() async {
    await _lostSub?.cancel();
    _lostSub = null;
    await _changesSub?.cancel();
    _changesSub = null;
    final monitor = _monitor;
    _monitor = null;
    await monitor?.stop();
    final changes = _changes;
    _changes = null;
    await changes?.close();
  }

  /// Gets the camera's Wi-Fi back with backoff. A camera that still
  /// answers is rejoined at once; otherwise the session waits for a lost
  /// Bluetooth link to return (up to [GrSessionOptions.bleLostAfter] from
  /// the loss), writes WLAN-on and rejoins. A camera that is off is left
  /// off and the recovery ends \[design\]: it reported turning off
  /// (Camera Power `00`), or reads off on the link that returned, so
  /// someone pressed its power button or it turned itself off, and only
  /// [startWifi] and [wake] turn a camera on. Ends in
  /// [GrSessionPhase.connected] or [GrSessionPhase.lost];
  /// `recovery.gaveUp` carries `cameraOff` for a camera that is off,
  /// `noBle` when Bluetooth did not come back, and `vpnSuspected` when the
  /// last attempt ended on a suspected VPN block.
  Future<void> _recoverWifi() async {
    final stop = _wifiStop.future;
    final bleDeadline = DateTime.now().add(options.bleLostAfter);
    _set(GrSessionPhase.recovering, 'recovery.start', {
      if (_cameraOff) 'cameraOff': true,
    });
    await _stopWifiServices();
    if (_closing || _wifiStopped) return;
    var declined = false;
    var vpnSuspected = false;
    var noBle = false;
    var attempts = 0;
    // Looked at before the wait too: a camera that reported turning off
    // needs none.
    while (!_cameraOff && attempts < options.maxWifiRecoveryAttempts) {
      await _until(
        stop,
        Future<void>.delayed(_delay(options.wifiRecoveryDelays, attempts)),
      );
      if (_closing || _wifiStopped) return;
      if (_cameraOff) break;
      final attempt = ++attempts;
      _emit('recovery.attempt', {'attempt': attempt});
      try {
        if (await _cameraAnswers()) {
          _emit('recovery.cameraReachable');
        } else {
          final reconnect = _bleReconnect;
          final left = bleDeadline.difference(DateTime.now());
          if (_ble == null && reconnect != null && left > Duration.zero) {
            _emit('recovery.waitingForBle', {'leftMs': left.inMilliseconds});
            await _until(stop, reconnect, left);
            if (_closing || _wifiStopped) return;
          }
          if (_ble == null) {
            noBle = true;
            break;
          }
          // The link that returned may be to a camera that turned off.
          if (_cameraOff) break;
          await _wlanOn();
          _emit('recovery.wlanOn');
          await _joinAndVerify();
        }
        await _startWifiServices(GrSessionPhase.recovering);
        _wifiRecovering = false;
        _set(GrSessionPhase.connected, 'recovery.done', {'attempt': attempt});
        return;
      } on Object catch (e) {
        if (_closing || _wifiStopped) return;
        _emit('recovery.failed', {'attempt': attempt, 'error': '$e'});
        vpnSuspected = e is GrSessionException && e.wifiVpnSuspected;
        if (e is GrSessionException && e.wifiDeclined) {
          declined = true;
          break;
        }
      }
    }
    _wifiRecovering = false;
    _set(GrSessionPhase.lost, 'recovery.gaveUp', {
      'attempts': attempts,
      if (_cameraOff) 'cameraOff': true,
      if (declined) 'declined': true,
      if (vpnSuspected) 'vpnSuspected': true,
      if (noBle) 'noBle': true,
    });
  }

  /// Waits for [future], [stop] or [timeout], whichever comes first; a
  /// null [future] is no wait.
  static Future<void> _until(
    Future<void> stop,
    Future<Object?>? future, [
    Duration? timeout,
  ]) async {
    if (future == null) return;
    await Future.any<void>([
      future.then<void>((_) {}, onError: (_) {}),
      stop,
      if (timeout != null) Future<void>.delayed(timeout),
    ]);
  }

  /// Network reachability check before tearing down and rejoining: one
  /// identity probe, no retries.
  Future<bool> _cameraAnswers() async {
    final http = _http;
    if (http == null) return false;
    try {
      final props = await http.props(
        connectTimeout: options.verifyProbeTimeout,
        timeout: options.verifyProbeTimeout,
      );
      if (verifyCameraProps(
        props,
        expectedSsid: _credentials?.ssid,
        expectedSerial: _identity?.serialNumber,
        expectedModel: _identity?.modelName,
      ).isNotEmpty) {
        return false;
      }
      _setProps(props);
      return true;
    } on Object {
      return false;
    }
  }

  // -------------------------------------------------------------- helpers

  Future<T> _step<T>(
    GrSessionPhase phase,
    String what,
    Future<T> Function() op,
  ) async {
    try {
      return await op();
    } catch (e) {
      throw GrSessionException(phase, '$what failed', e);
    }
  }

  static Duration _delay(List<Duration> delays, int attempt) => delays.isEmpty
      ? Duration.zero
      : delays[attempt.clamp(0, delays.length - 1)];

  void _set(
    GrSessionPhase phase,
    String kind, [
    Map<String, Object?> fields = const {},
  ]) {
    // Closed is final: a step that ends after close() changes nothing.
    if (_phase == GrSessionPhase.closed) return;
    _phase = phase;
    _emit(kind, fields);
  }

  void _emit(String kind, [Map<String, Object?> fields = const {}]) {
    final event = GrSessionEvent(_phase, kind, fields);
    _trace?.call(
      TraceEvent(
        channel: TraceChannel.session,
        direction: TraceDirection.internal,
        kind: 'session.$kind',
        fields: {'phase': _phase.name, ...fields},
      ),
    );
    if (!_events.isClosed) _events.add(event);
  }
}

/// Watches a link after a wake write: from its creation for a drop and for
/// the camera reporting that it is on, and for
/// [GrSessionOptions.wakeSettle] from [start].
final class _WakeSettle {
  new(GrBleClient client, this._settle, {this.endsWhenOn = false}) {
    unawaited(
      client.connection.disconnected.then((_) {
        dropped = true;
        _end();
      }),
    );
  }

  final Duration _settle;

  /// Whether [cameraOn] ends the watch.
  final bool endsWhenOn;
  Timer? _timer;
  final Completer<bool> _ended = Completer<bool>();

  /// Whether the link has dropped since the wake, also after [ended].
  bool dropped = false;

  /// The camera reported being on over this link before the watch ended.
  bool reportedOn = false;

  /// Completes with [dropped] at a drop, after the settle time, when the
  /// camera reports being on ([cameraOn]), or when cancelled.
  Future<bool> get ended => _ended.future;

  /// The wake write was answered: the settle time runs from now.
  void start() {
    if (_ended.isCompleted) return;
    _timer = Timer(_settle, _end);
  }

  void cancel() => _end();

  /// The camera notified Camera Power `01` on the watched link: it has
  /// booted and the link answers, so the watch need not run its full
  /// time. Whether a GR IV sends this after the wake write is \[unknown\]
  /// (research/protocol/power-on-grworld.md §8); without it the watch
  /// runs as before.
  void cameraOn() {
    if (!endsWhenOn || _ended.isCompleted) return;
    reportedOn = true;
    _end();
  }

  void _end() {
    _timer?.cancel();
    if (!_ended.isCompleted) _ended.complete(dropped);
  }
}

/// [BleTransport] whose scans fail with the session's closed error once
/// [_stop] completes, so [GrSession.close] ends a scan the session started
/// rather than leaving it to find the camera or time out.
final class _ScanUntilClosed implements BleTransport {
  new(this._inner, this._stop);

  final BleTransport _inner;
  final Future<void> _stop;

  @override
  Future<BleAdapterState> adapterState() => _inner.adapterState();

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    StreamSubscription<BleAdvertisement>? scan;
    late final StreamController<BleAdvertisement> out;
    out = StreamController<BleAdvertisement>(
      onListen: () {
        scan = _inner
            .scan(serviceUuids: serviceUuids)
            .listen(out.add, onError: out.addError, onDone: out.close);
        unawaited(
          _stop.then((_) {
            if (!out.isClosed) out.addError(GrSession._closed);
          }),
        );
      },
      onCancel: () => scan?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<BleConnection> connect(String deviceId, {required Duration timeout}) =>
      _inner.connect(deviceId, timeout: timeout);

  @override
  Future<void> close() => _inner.close();
}
