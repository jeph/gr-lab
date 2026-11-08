import 'dart:async';

import '../ble/advertising.dart';
import '../ble/catalog.dart';
import '../ble/client.dart';
import '../ble/enums.dart';
import '../ble/transport.dart';
import '../ble/wake.dart';
import '../http/changes.dart';
import '../http/client.dart';
import '../http/liveness.dart';
import '../http/models.dart';
import '../trace.dart';
import '../wifi/network_control.dart';

/// Where a [GrSession] is in the BLE → Wi-Fi hand-off
/// (docs/protocol/ble.md §Minimal client sequence) and afterwards.
enum GrSessionPhase {
  idle,
  scanning,
  waking,
  bleConnecting,

  /// Linked over BLE; the camera's Wi-Fi is not in use ([GrSession.startWifi]
  /// joins it, [GrSession.stopWifi] comes back here).
  bluetooth,
  wlanOn,
  joining,
  verifying,
  connected,

  /// Wi-Fi liveness was lost; re-issuing WLAN-on and rejoining.
  recovering,

  /// Recovery gave up; the session stays open but has no Wi-Fi link.
  lost,
  closed,
}

/// One observable step of a session, for UIs, logs and hardware validation.
final class GrSessionEvent {
  GrSessionEvent(this.phase, this.kind, [this.fields = const {}])
    : at = DateTime.now();

  final DateTime at;
  final GrSessionPhase phase;
  final String kind;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => {
    'time': at.toUtc().toIso8601String(),
    'phase': phase.name,
    'kind': kind,
    if (fields.isNotEmpty) ...fields,
  };
}

/// [GrSessionException.cause] when the camera is off and waking it was not
/// allowed.
const _cameraOffCause = 'cameraOff';

final class GrSessionException implements Exception {
  const GrSessionException(this.phase, this.message, [this.cause]);
  final GrSessionPhase phase;
  final String message;
  final Object? cause;

  /// The camera refused this device's bond, or encrypted access failed on
  /// a link that should be bonded. Only pairing again recovers; retrying
  /// cannot (docs/protocol/firmware-bonding.md §4).
  bool get needsPairing {
    final c = cause;
    return c is BleException &&
        (c.code == BleErrorCode.bondRejected ||
            c.code == BleErrorCode.unauthorized);
  }

  /// The user declined joining the camera's Wi-Fi; only asking them again
  /// (an explicit connect) can continue.
  bool get wifiDeclined => cause is WifiJoinDeclined;

  /// The camera is off and powering it on was not allowed.
  bool get cameraOff => identical(cause, _cameraOffCause);

  @override
  String toString() =>
      'GrSessionException(${phase.name}): $message'
      '${cause == null ? '' : ' ($cause)'}';
}

/// Timings and policies. Defaults follow the official apps where the docs
/// establish them and are marked as design choices otherwise.
final class GrSessionOptions {
  const GrSessionOptions({
    this.scanTimeout = const Duration(seconds: 20),
    this.bleConnectTimeout = const Duration(seconds: 35),
    this.bleConnectAttempts = 3,
    this.bleConnectRetryDelay = const Duration(milliseconds: 50),
    this.powerOnMode = BleOperationMode.playback,
    this.joinTimeout = const Duration(seconds: 60),
    this.joinRetryDelay = const Duration(seconds: 2),
    this.verifyTimeout = const Duration(seconds: 30),
    this.verifyProbeTimeout = const Duration(seconds: 3),
    this.livenessInterval = const Duration(milliseconds: 500),
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
  });

  /// How long to scan for the camera's advertisement.
  final Duration scanTimeout;

  /// GR WORLD's connect timeout: 35 s (ble.md §Connect parameters).
  final Duration bleConnectTimeout;

  /// GR WORLD's connect retry: 3 attempts, 50 ms apart (ble.md §Connect
  /// parameters). Needed to power on: the first link to an off camera
  /// drops while it boots.
  final int bleConnectAttempts;
  final Duration bleConnectRetryDelay;

  /// Written to Operation Mode when a connect finds the camera in
  /// bleStartup (`02`): GR WORLD writes playback, or capture for its
  /// remote screen (docs/protocol/power-on-grworld.md).
  final BleOperationMode powerOnMode;

  /// GR WORLD allows 60 s for the AP to come up and the join to finish.
  final Duration joinTimeout;

  /// Pause between join attempts while the AP is still coming up [design].
  final Duration joinRetryDelay;

  /// Total time for the first `/v1/props` identity check to succeed after
  /// joining (DHCP and the HTTP server may lag the association) [design].
  final Duration verifyTimeout;

  /// GR WORLD's `connectToWifi` verification uses a 3 s timeout.
  final Duration verifyProbeTimeout;

  /// Image Sync liveness: 500 ms between polls, loss after 3 consecutive
  /// failures and 40 s without success.
  final Duration livenessInterval;
  final int livenessFailureThreshold;
  final Duration livenessLossAfter;

  /// Rejoin backoff after liveness loss (connection-lifecycle.md §9); the
  /// last delay repeats.
  final List<Duration> wifiRecoveryDelays;
  final int maxWifiRecoveryAttempts;

  /// BLE auto-reconnect backoff; independent of Wi-Fi, never writes WLAN.
  final List<Duration> bleReconnectDelays;
  final int maxBleReconnectAttempts;
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

/// Model string with every `RICOH` removed and trimmed, as GR WORLD stores it.
String? stripRicohPrefix(String? model) =>
    model?.replaceAll('RICOH', '').trim();

/// One camera connection: BLE link, camera Wi-Fi, HTTP client, change
/// WebSocket and liveness monitor, with independent BLE and Wi-Fi recovery
/// (connection-lifecycle.md §9: a BLE blip never tears down Wi-Fi, and Wi-Fi
/// loss is repaired by re-issuing WLAN-on over BLE and rejoining).
final class GrSession {
  GrSession({
    required this.transport,
    required this.wifi,
    this.host = '192.168.0.1',
    this.options = const GrSessionOptions(),
    this._trace,
    GrHttpClient Function(String host, TraceSink? trace)? httpFactory,
  }) : _httpFactory = httpFactory ?? _defaultHttp;

  static GrHttpClient _defaultHttp(String host, TraceSink? trace) =>
      GrHttpClient(host, trace: trace);

  final BleTransport transport;
  final WifiNetworkControl wifi;
  final String host;
  final GrSessionOptions options;
  final TraceSink? _trace;
  final GrHttpClient Function(String host, TraceSink? trace) _httpFactory;

  final StreamController<GrSessionEvent> _events = StreamController.broadcast();
  GrSessionPhase _phase = GrSessionPhase.idle;

  String? _serial;
  bool _powerOn = true;
  bool _cameraOff = false;
  bool _wifiStopped = false;
  bool _relinking = false;
  Future<void>? _wifiStart;
  String? _deviceId;
  GrAdvertisement? _advertisement;
  GrBleClient? _ble;
  GrBleIdentity? _identity;
  GrWifiCredentials? _credentials;
  GrHttpClient? _http;
  GrProps? _props;
  GrChangesSocket? _changes;
  LivenessMonitor? _monitor;
  StreamSubscription<void>? _lostSub;
  StreamSubscription<Object?>? _powerSub;
  bool _closing = false;
  Future<void>? _bleReconnect;
  Future<void>? _wifiRecovery;

  Stream<GrSessionEvent> get events => _events.stream;
  GrSessionPhase get phase => _phase;

  /// Null while BLE is down (reconnecting) or before connecting.
  GrBleClient? get ble => _ble;
  GrBleIdentity? get identity => _identity;
  GrWifiCredentials? get credentials => _credentials;
  GrAdvertisement? get advertisement => _advertisement;

  /// The camera answered over BLE in its BT-only (off) state; [startWifi]
  /// powers it on.
  bool get cameraOff => _cameraOff;

  /// The camera HTTP client; non-null from [GrSessionPhase.verifying] on.
  GrHttpClient? get http => _http;

  /// `/v1/props` from the last successful identity check.
  GrProps? get props => _props;
  GrChangesSocket? get changes => _changes;
  LivenessMonitor? get liveness => _monitor;

  /// Runs the full hand-off: [connectBluetooth], waking the camera on the
  /// same link when it is in its BT-only state and [powerOn] is set, then
  /// [startWifi]. Throws [GrSessionException] on the first unrecoverable
  /// step; check [GrSessionException.needsPairing].
  Future<void> connect({
    String? serial,
    String? deviceId,
    bool powerOn = true,
  }) async {
    await _connectBluetooth(serial: serial, deviceId: deviceId, wake: powerOn);
    await startWifi(powerOn: powerOn);
  }

  /// Connects BLE only (directly to [deviceId] when given, as GR WORLD
  /// does; otherwise after scanning for [serial] or any GR camera) and reads
  /// the identity; ends in [GrSessionPhase.bluetooth]. A camera that is off
  /// keeps the link in its BT-only state ([cameraOff]) and is not woken.
  Future<void> connectBluetooth({String? serial, String? deviceId}) =>
      _connectBluetooth(serial: serial, deviceId: deviceId, wake: false);

  Future<void> _connectBluetooth({
    required String? serial,
    required String? deviceId,
    required bool wake,
  }) async {
    if (_phase != GrSessionPhase.idle) {
      throw StateError('GrSession.connect called in ${_phase.name}');
    }
    _serial = serial;
    _deviceId = deviceId;
    _powerOn = wake;

    if (deviceId == null) {
      final ad = await _find(GrSessionPhase.scanning);
      _deviceId = ad.deviceId;
      _serial ??= ad.serialText;
    }

    await _connectBle(initial: true);
    _set(GrSessionPhase.bluetooth, 'bluetooth', {'cameraOff': _cameraOff});
  }

  /// From [GrSessionPhase.bluetooth]: powers the camera on when it is off
  /// and [powerOn] is set (otherwise throws, see
  /// [GrSessionException.cameraOff]), reads the Wi-Fi credentials, writes
  /// WLAN-on, joins, verifies `/v1/props`, then opens the change WebSocket
  /// and starts liveness polling. On failure, or when [stopWifi] cuts it
  /// short, the session is back in [GrSessionPhase.bluetooth].
  Future<void> startWifi({bool powerOn = true}) {
    if (_phase != GrSessionPhase.bluetooth) {
      throw StateError('GrSession.startWifi called in ${_phase.name}');
    }
    _wifiStopped = false;
    final start = _wifiStart = _startWifi(powerOn: powerOn);
    return start.whenComplete(() {
      if (identical(_wifiStart, start)) _wifiStart = null;
    });
  }

  Future<void> _startWifi({required bool powerOn}) async {
    try {
      // A dropped link may be coming back.
      await _bleReconnect;
      final linked = _ble;
      if (linked == null) {
        throw const GrSessionException(
          GrSessionPhase.bleConnecting,
          'no Bluetooth link',
        );
      }
      if (_cameraOff) {
        if (!powerOn) {
          throw const GrSessionException(
            GrSessionPhase.waking,
            'camera is off (operation mode bleStartup)',
            _cameraOffCause,
          );
        }
        await _wakeAndRelink(linked);
      }
      final ble = _ble!;

      final GrWifiCredentials credentials =
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

      _set(GrSessionPhase.wlanOn, 'wlan.on');
      await _step(
        GrSessionPhase.wlanOn,
        'WLAN-on write',
        () => ble.setWlan(true),
      );

      await _joinAndVerify();
      _checkWifiStopped(GrSessionPhase.verifying);
      await _startWifiServices();
      _set(GrSessionPhase.connected, 'connected', {
        'model': _props?.model,
        'serialNo': _props?.serialNo,
        'firmwareVersion': _props?.firmwareVersion,
      });
    } catch (e) {
      if (_closing) rethrow;
      await _stopWifiServices();
      _http?.close(force: true);
      _http = null;
      _set(GrSessionPhase.bluetooth, 'wifi.failed', {'error': '$e'});
      rethrow;
    }
  }

  /// Leaves the camera's Wi-Fi and keeps BLE: an attempt or recovery in
  /// progress stops, supervision and HTTP close, WLAN-off is written over
  /// BLE (GR WORLD's release) and the phone's join is released. Ends in
  /// [GrSessionPhase.bluetooth]; does nothing before Wi-Fi was started.
  Future<void> stopWifi() async {
    if (_closing ||
        (_wifiStart == null &&
            _phase.index <= GrSessionPhase.bluetooth.index)) {
      return;
    }
    _wifiStopped = true;
    // Releasing the join first cuts a platform join short.
    await _leaveWifi();
    final start = _wifiStart;
    if (start != null) {
      try {
        await start;
      } catch (_) {
        // Expected: the attempt was cut short.
      }
    }
    await _wifiRecovery;
    // A join that completed meanwhile is released too.
    await _leaveWifi();
    if (_closing) return;
    await _stopWifiServices();
    _http?.close(force: true);
    _http = null;
    final ble = _ble;
    if (ble != null) {
      try {
        await ble.setWlan(false);
        _emit('wlan.off');
      } catch (e) {
        _emit('wlan.offFailed', {'error': '$e'});
      }
    }
    _set(GrSessionPhase.bluetooth, 'wifi.stopped');
  }

  Future<void> _leaveWifi() async {
    try {
      await wifi.leave();
    } catch (_) {
      // Not joined; nothing to release.
    }
  }

  void _checkWifiStopped(GrSessionPhase phase) {
    if (_closing) throw GrSessionException(phase, 'closed');
    if (_wifiStopped) throw GrSessionException(phase, 'Wi-Fi stopped');
  }

  /// Stops supervision, closes the WebSocket, HTTP client and BLE link.
  /// [wlanOff] writes WLAN-off over BLE first (GR WORLD's explicit release);
  /// by default the camera's Wi-Fi is left as it is. [powerOff] turns the
  /// camera off over BLE (Camera Power `00`, as GR WORLD's power-off flow)
  /// after Wi-Fi supervision has stopped, so the loss is not reported.
  Future<void> close({bool wlanOff = false, bool powerOff = false}) async {
    if (_phase == GrSessionPhase.closed) return;
    _closing = true;
    if (wlanOff && !powerOff && _ble != null) {
      try {
        await _ble!.setWlan(false);
        _emit('wlan.off');
      } catch (e) {
        _emit('wlan.offFailed', {'error': '$e'});
      }
    }
    await _stopWifiServices();
    if (powerOff && _ble != null) {
      try {
        await _ble!.powerOff();
        _emit('power.off');
      } catch (e) {
        _emit('power.offFailed', {'error': '$e'});
      }
    }
    _http?.close(force: true);
    _http = null;
    await _powerSub?.cancel();
    final ble = _ble;
    _ble = null;
    if (ble != null) {
      try {
        await ble.connection.disconnect();
      } catch (_) {
        // Already down; the link state is what matters.
      }
    }
    _set(GrSessionPhase.closed, 'closed');
    await _events.close();
  }

  // ------------------------------------------------------------------ BLE

  Future<GrAdvertisement> _find(GrSessionPhase phase) async {
    _set(phase, 'scan.start', {'serial': _serial, 'deviceId': _deviceId});
    final ad = await findGrAdvertisement(
      transport,
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

  Future<void> _connectBle({required bool initial}) async {
    final ble = _ble;
    final lastOff = ble?.lastPowerOff;
    if (lastOff != null) {
      final waited = await waitAfterPowerOff(lastOff, trace: _trace);
      if (waited > Duration.zero) {
        _emit('ble.powerOffGuard', {'waitedMs': waited.inMilliseconds});
      }
    }
    if (initial) _set(GrSessionPhase.bleConnecting, 'ble.connect');
    for (var attempt = 1; ; attempt++) {
      try {
        await _openBle(initial: initial);
        return;
      } on GrSessionException catch (e) {
        // A bonded connect to the off camera wakes it, and the first link
        // drops (supervision timeout ~5.5 s) while it boots; GR WORLD
        // reconnects ~0.1 s later. A lost bond is final.
        if (e.needsPairing || attempt >= options.bleConnectAttempts) {
          rethrow;
        }
        _emit('ble.connectRetry', {'attempt': attempt, 'error': '$e'});
        await Future<void>.delayed(options.bleConnectRetryDelay);
      }
    }
  }

  /// One connect: link, discovery, power-on check, encrypted identity.
  Future<void> _openBle({required bool initial}) async {
    final connection = await _step(
      GrSessionPhase.bleConnecting,
      'BLE connect',
      () => transport.connect(_deviceId!, timeout: options.bleConnectTimeout),
    );
    final client = GrBleClient(connection, trace: _trace);
    final GrBleDiscoveryReport report;
    try {
      report = await _step(
        GrSessionPhase.bleConnecting,
        'GATT discovery',
        client.discover,
      );
      await _checkOperationMode(client, initial: initial);
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
    } catch (_) {
      // Not yet in [_ble], so close() could not reach this link.
      try {
        await connection.disconnect();
      } catch (_) {
        // Already down; the setup failure is what matters.
      }
      rethrow;
    }
    _ble = client;
    _emit('ble.ready', {
      'missingCharacteristics': report.missing.length,
      'identity': {
        'modelName': _identity!.modelName,
        'serialNumber': _identity!.serialNumber,
        'firmwareRevision': _identity!.firmwareRevision,
      },
    });
    await _powerSub?.cancel();
    if (client.isPresent(GrBleCatalog.cameraPower) ?? false) {
      _powerSub = client
          .watch(GrBleCatalog.cameraPower)
          .listen(
            (n) => _emit('ble.cameraPower', n.toJson()),
            onError: (Object e) =>
                _emit('ble.cameraPowerError', {'error': '$e'}),
          );
    }
    unawaited(connection.disconnected.then(_onBleDisconnected));
  }

  /// GR WORLD's power-on check (0xd403b8, on every connect): Operation Mode
  /// `02` (bleStartup) means the camera is off in its BT-only state. The
  /// full [connect] wakes it here, on the same link; otherwise the link
  /// stays up with [cameraOff] set and [startWifi] wakes it. Automatic
  /// reconnects never power a camera on: the user turned it off.
  Future<void> _checkOperationMode(
    GrBleClient client, {
    required bool initial,
  }) async {
    if (client.isPresent(GrBleCatalog.operationMode) != true) return;
    final mode = await _step(
      GrSessionPhase.bleConnecting,
      'operation mode read',
      () => client.read(GrBleCatalog.operationMode),
    );
    final known = mode.value?.known;
    _emit('ble.operationMode', {'value': known?.name ?? mode.value?.raw});
    if (known != BleOperationMode.bleStartup) {
      _cameraOff = false;
      return;
    }
    if (initial && _powerOn) {
      await _wake(client);
      _set(GrSessionPhase.bleConnecting, 'power.onWritten');
      return;
    }
    _cameraOff = true;
    _emit('ble.cameraOff');
  }

  /// Turns an off camera on over BLE.
  Future<void> _wake(GrBleClient client) async {
    _set(GrSessionPhase.waking, 'power.on', {'mode': options.powerOnMode.name});
    await _step(
      GrSessionPhase.waking,
      'operation mode write',
      () => client.setOperationMode(options.powerOnMode),
    );
    _cameraOff = false;
  }

  /// Wakes the camera on an established BT-only link. The link goes silent
  /// while the main firmware starts and then drops (GR IV: ~5.5 s); like
  /// GR WORLD, reconnect straight away rather than after the background
  /// reconnect's backoff.
  Future<void> _wakeAndRelink(GrBleClient client) async {
    _relinking = true;
    try {
      await _wake(client);
      await _step(
        GrSessionPhase.waking,
        'waiting for the camera to restart',
        () => client.connection.disconnected.timeout(options.bleConnectTimeout),
      );
      _ble = null;
      _emit('power.restarted');
      await _connectBle(initial: false);
    } finally {
      _relinking = false;
    }
  }

  void _onBleDisconnected(BleDisconnect d) {
    if (_closing || _relinking) return;
    _ble = null;
    _emit('ble.lost', {
      'requested': d.requested,
      'reason': d.reason,
      if (d.bondRejected) 'bondRejected': true,
    });
    if (d.bondRejected) {
      _emit('ble.needsPairing');
      return;
    }
    _bleReconnect ??= _reconnectBle().whenComplete(() => _bleReconnect = null);
  }

  /// Reconnects BLE only; Wi-Fi state is untouched (no WLAN writes). Stops
  /// for good when the bond is gone.
  Future<void> _reconnectBle() async {
    for (
      var attempt = 0;
      attempt < options.maxBleReconnectAttempts;
      attempt++
    ) {
      await Future<void>.delayed(_delay(options.bleReconnectDelays, attempt));
      if (_closing) return;
      _emit('ble.reconnect', {'attempt': attempt + 1});
      try {
        await _connectBle(initial: false);
        _emit('ble.restored', {'attempt': attempt + 1});
        return;
      } catch (e) {
        _emit('ble.reconnectFailed', {'attempt': attempt + 1, 'error': '$e'});
        if (e is! GrSessionException) continue;
        if (e.needsPairing) {
          _emit('ble.needsPairing');
          return;
        }
      }
    }
    _emit('ble.gaveUp', {'attempts': options.maxBleReconnectAttempts});
  }

  // ---------------------------------------------------------------- Wi-Fi

  Future<void> _joinAndVerify() async {
    final c = _credentials!;
    // One security type per camera: Android approves a camera network per
    // app and security type, so alternating WPA3 and WPA2 asks the user
    // twice. Transition-mode APs accept WPA2, which is what GR WORLD's
    // approval on a test phone records (GR IV HDF, 2026-11-08).
    final security = c.wifiSecurity == WifiSecurity.wpa3
        ? WifiSecurity.wpa3
        : WifiSecurity.wpa2;
    _set(
      _phase == GrSessionPhase.recovering ? _phase : GrSessionPhase.joining,
      'wifi.join',
      {'ssid': c.ssid, 'security': security.name},
    );
    // The AP comes up several seconds after WLAN-on (GR IV HDF: a join at
    // 0 s found no network, one at 16 s succeeded), so retry within
    // joinTimeout.
    final deadline = DateTime.now().add(options.joinTimeout);
    var attempt = 0;
    while (true) {
      // close() or stopWifi() during the hand-off must not leave the phone
      // retrying, and possibly joining, the camera's network afterwards.
      _checkWifiStopped(GrSessionPhase.joining);
      attempt++;
      final left = deadline.difference(DateTime.now());
      try {
        await wifi.join(
          ssid: c.ssid,
          passphrase: c.passphrase,
          security: security,
          timeout: left,
        );
        break;
      } on WifiJoinDeclined catch (e) {
        _emit('wifi.declined');
        throw GrSessionException(GrSessionPhase.joining, 'declined', e);
      } catch (e) {
        final remaining = deadline.difference(DateTime.now());
        _emit('wifi.joinRetry', {
          'attempt': attempt,
          'remainingMs': remaining.inMilliseconds,
          'error': '$e',
        });
        if (remaining <= options.joinRetryDelay) {
          throw GrSessionException(GrSessionPhase.joining, 'join failed', e);
        }
        await Future<void>.delayed(options.joinRetryDelay);
      }
    }
    _emit('wifi.joined');
    await _verify();
  }

  Future<void> _verify() async {
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
        _props = props;
        _emit('verify.ok', {
          'probes': probes,
          'model': props.model,
          'serialNo': props.serialNo,
          'firmwareVersion': props.firmwareVersion,
        });
        return;
      } on GrSessionException {
        rethrow;
      } catch (e) {
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

  Future<void> _startWifiServices() async {
    final http = _http!;
    final changes = _changes ??= http.changesSocket();
    try {
      await changes.connect();
      _emit('changes.open');
    } catch (e) {
      // The WebSocket is an extra signal; liveness polling still runs.
      _emit('changes.failed', {'error': '$e'});
    }
    final monitor = LivenessMonitor(
      http,
      interval: options.livenessInterval,
      failureThreshold: options.livenessFailureThreshold,
      lossAfter: options.livenessLossAfter,
      expectedIdentity: _props?.identity,
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
    monitor.start();
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
  /// said so, or `check`): emits `wifi.lost`, then recovers.
  void _wifiLost(String reason, [Map<String, Object?> fields = const {}]) {
    if (_closing || _monitor == null || _wifiRecovery != null) return;
    _emit('wifi.lost', {'reason': reason, ...fields});
    _wifiRecovery = _recoverWifi().whenComplete(() => _wifiRecovery = null);
  }

  Future<void> _stopWifiServices() async {
    await _lostSub?.cancel();
    _lostSub = null;
    final monitor = _monitor;
    _monitor = null;
    await monitor?.stop();
    final changes = _changes;
    _changes = null;
    await changes?.close();
  }

  /// Re-issues WLAN-on over BLE (when linked), rejoins and re-verifies with
  /// backoff; ends in [GrSessionPhase.connected] or [GrSessionPhase.lost].
  Future<void> _recoverWifi() async {
    _set(GrSessionPhase.recovering, 'recovery.start');
    await _stopWifiServices();
    var declined = false;
    var attempts = 0;
    while (attempts < options.maxWifiRecoveryAttempts) {
      final attempt = attempts++;
      await Future<void>.delayed(_delay(options.wifiRecoveryDelays, attempt));
      if (_closing || _wifiStopped) return;
      if (_cameraOff) {
        // Turned off over BLE by the user: rejoining cannot work.
        _set(GrSessionPhase.lost, 'recovery.gaveUp', {
          'attempts': attempts,
          'cameraOff': true,
        });
        return;
      }
      _emit('recovery.attempt', {'attempt': attempt + 1});
      try {
        if (await _cameraAnswers()) {
          _emit('recovery.cameraReachable');
        } else {
          final ble = _ble;
          if (ble != null) {
            await ble.setWlan(true);
            _emit('recovery.wlanOn');
          } else {
            _emit('recovery.noBle');
          }
          await _joinAndVerify();
        }
        await _startWifiServices();
        _set(GrSessionPhase.connected, 'recovery.done', {
          'attempt': attempt + 1,
        });
        return;
      } catch (e) {
        _emit('recovery.failed', {'attempt': attempt + 1, 'error': '$e'});
        if (e is GrSessionException && e.wifiDeclined) {
          declined = true;
          break;
        }
      }
    }
    _set(GrSessionPhase.lost, 'recovery.gaveUp', {
      'attempts': attempts,
      if (declined) 'declined': true,
    });
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
      _props = props;
      return true;
    } catch (_) {
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
