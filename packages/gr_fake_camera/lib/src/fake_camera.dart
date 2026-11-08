import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';

import 'config.dart';

part 'ble_side.dart';
part 'http_side.dart';
part 'wifi_side.dart';

/// Thrown by [FakeGrCamera.wifi] when a join fails.
final class FakeWifiException implements Exception {
  const FakeWifiException(this.message);
  final String message;

  @override
  String toString() => 'FakeWifiException: $message';
}

/// A simulated Ricoh GR: BLE advertising and GATT ([transport]), the camera
/// access point ([wifi]) and the Wi-Fi HTTP API with the change WebSocket
/// ([startHttp]), sharing one camera state.
///
/// It follows the protocol as gr_protocol speaks it and as a GR IV was
/// observed to behave:
/// * adverts carry the Ricoh manufacturer payload with the power tag and
///   the Camera Information (on) or Client Registration (off) service;
/// * DIS reads work on any link, every other characteristic needs the bond
///   made by [BleConnection.pair] while Execute Pairing is open (one-shot);
/// * an off camera reads Operation Mode `02`; writing capture/playback
///   wakes it, and the link stops answering and drops after
///   [FakeCameraConfig.wakeDelay] while it restarts;
/// * Wi-Fi can be joined only after WLAN-on over BLE, once the access
///   point is up, with the SSID and passphrase the camera reports.
///
/// The HTTP server stands in for the camera's network: it answers while
/// the camera is on and its access point has not gone down, so HTTP-only
/// tests can use it without a BLE session.
final class FakeGrCamera {
  FakeGrCamera({this.config = const FakeCameraConfig(), required this.media})
    : model =
          GrModel.fromModelString(config.model) ??
          (throw ArgumentError.value(
            config.model,
            'config.model',
            'not a GR model string',
          )),
      executePairingOpen = config.executePairingOpen,
      _poweredOn = config.poweredOn,
      _apGone = !config.poweredOn,
      _bonded = config.bonded,
      _battery = config.battery,
      _photos = List.of(config.photos ?? FakePhoto.defaultCard()) {
    _initValues();
  }

  final FakeCameraConfig config;
  final FakeMediaSource media;

  /// Model selected by [FakeCameraConfig.model].
  final GrModel model;

  /// BLE central backed by this camera; the only peripheral it sees.
  late final BleTransport transport = _FakeTransport(this);

  /// Joins this camera's access point.
  late final WifiNetworkControl wifi = _FakeWifi(this);

  /// What [BleTransport.adapterState] reports; anything but poweredOn makes
  /// scans fail and connects throw.
  BleAdapterState adapterState = BleAdapterState.poweredOn;

  /// The camera shows Execute Pairing. Closed again by every pairing
  /// attempt, successful or not.
  bool executePairingOpen;

  /// Last name written to Client Registration by a bonded client.
  String? registeredClientName;

  bool _poweredOn;
  int _mode = BleOperationMode.playback.wire;
  bool _bonded;
  int _battery;
  final List<FakePhoto> _photos;
  final Map<String, Uint8List> _values = {};
  final Set<_FakeLink> _links = {};
  final Set<Timer> _timers = {};
  final Set<StreamController<BleAdvertisement>> _scans = {};
  Completer<bool>? _pairing;
  bool _closed = false;

  // Access point state. [_apGone] is what the HTTP server checks: set when
  // the AP shuts down (power off, WLAN off, drop), cleared when it is up.
  bool _wlanEnabled = false;
  bool _apReady = false;
  bool _apGone;
  bool _wlanBroken = false;
  bool _joined = false;
  bool _dropArmed = false;
  int _wlanGeneration = 0;
  Completer<bool>? _apUp;
  final _wifiLost = StreamController<void>.broadcast();

  HttpServer? _server;
  final Set<WebSocket> _sockets = {};
  final Map<FakePhoto, int> _fullSizes = Map.identity();

  /// Thumbnail/preview requests per `<photo>|<size>`, for
  /// [FakeCameraConfig.previewFailures].
  final Map<String, int> _previewRequests = {};

  // ------------------------------------------------------------- scenario

  /// On (main firmware) or off (BT-only: still advertises and accepts a
  /// bonded link). Turning it off drops every link and the access point;
  /// turning it on starts in capture mode with Wi-Fi off.
  bool get poweredOn => _poweredOn;
  set poweredOn(bool on) => _setPower(on, mode: BleOperationMode.capture.wire);

  /// Operation Mode as BLE reports it.
  BleOperationMode get operationMode => _poweredOn
      ? BleOperationMode.values.firstWhere(
          (m) => m.wire == _mode,
          orElse: () => BleOperationMode.other,
        )
      : BleOperationMode.bleStartup;

  /// The camera holds this phone's bond.
  bool get bonded => _bonded;

  /// The camera shows the code and waits for OK: [confirmPairing] and
  /// [rejectPairing] only act while this is true.
  bool get pairingPending => _pairing?.isCompleted == false;

  /// WLAN has been turned on over BLE (the AP may still be starting).
  bool get wlanOn => _wlanEnabled;

  /// The phone is associated with the camera's access point.
  bool get wifiJoined => _joined;

  /// Open BLE links.
  int get linkCount => _links.length;

  int get battery => _battery;
  set battery(int percent) {
    _battery = percent;
    _notify(GrBleCatalog.batteryLevel, [percent & 0xff]);
    _push({'errCode': 200, 'changed': 'battery'});
  }

  /// The card, in insertion order.
  List<FakePhoto> get photos => List.unmodifiable(_photos);

  /// The user turns the camera on and opens MENU → Wireless Connection →
  /// Pairing → Execute Pairing.
  void openExecutePairing() {
    poweredOn = true;
    executePairingOpen = true;
  }

  /// The user presses OK on the camera for the pending pairing.
  void confirmPairing() {
    final p = _pairing;
    if (p != null && !p.isCompleted) p.complete(true);
  }

  /// The user cancels the pending pairing on the camera.
  void rejectPairing() {
    final p = _pairing;
    if (p != null && !p.isCompleted) p.complete(false);
  }

  /// The user deletes this phone from the camera's Paired Devices list:
  /// encrypted access now fails as unauthorized (needs pairing).
  void forgetPairing() => _bonded = false;

  /// The access point goes down (HTTP and the WebSocket stop answering).
  /// With [recoverable] a WLAN-on write brings it back; without, WLAN-on
  /// writes fail from now on.
  void dropWifi({bool recoverable = true}) {
    if (!recoverable) _wlanBroken = true;
    _apDown();
  }

  /// Every open BLE link drops from the camera side (out of range, blip).
  void dropBluetooth() {
    for (final link in _links.toList()) {
      link._drop('link supervision timeout');
    }
  }

  /// Serves the camera HTTP API and `/v1/changes` on 127.0.0.1; returns
  /// the port. Calling it again returns the same port.
  Future<int> startHttp() => _startHttp();

  /// Port of the running HTTP server, if [startHttp] has completed.
  int? get httpPort => _server?.port;

  /// A client for the loopback server, whatever [host] the caller meant
  /// (the session passes the camera's 192.168.0.1). Shaped for
  /// `GrSession.httpFactory` / `AppServices.httpFactory`.
  GrHttpClient httpClient(String host, TraceSink? trace) {
    final server = _server;
    if (server == null) throw StateError('call startHttp() first');
    return GrHttpClient(
      InternetAddress.loopbackIPv4.address,
      port: server.port,
      trace: trace,
    );
  }

  /// Adds [photo] to the card and pushes a `storage` `add` change, as the
  /// camera does after a capture.
  void addPhoto(FakePhoto photo) {
    if (_find(photo.storage, photo.dir, photo.file) != null) {
      throw ArgumentError.value(photo, 'photo', 'already on the card');
    }
    _photos.add(photo);
    _pushStorage('add', photo);
  }

  /// Removes the file at [path] on [storage] and pushes a `storage`
  /// `delete` change. Returns false when it was not on the card.
  bool removePhoto(GrPhotoPath path, {String storage = GrStorageId.sd}) {
    final photo = _find(storage, path.dir, path.file);
    if (photo == null) return false;
    _photos.remove(photo);
    _fullSizes.remove(photo);
    _pushStorage('delete', photo);
    return true;
  }

  /// Stops timers, drops every link and socket and closes the HTTP server.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final link in _links.toList()) {
      link._drop('camera closed');
    }
    // Listeners see the scan end; the periodic timers went with _timers.
    for (final scan in _scans.toList()) {
      unawaited(scan.close());
    }
    _scans.clear();
    for (final ws in _sockets.toList()) {
      unawaited(ws.close(WebSocketStatus.goingAway));
    }
    _sockets.clear();
    unawaited(_wifiLost.close());
    await _server?.close(force: true);
  }

  // ---------------------------------------------------------------- state

  String get _ssid => utf8.decode(_values[GrBleCatalog.ssid.uuid]!);
  String get _passphrase => utf8.decode(_values[GrBleCatalog.passphrase.uuid]!);

  bool get _httpReachable =>
      !_closed && !config.unreachable && _poweredOn && !_apGone;

  static const _manufacturer = 'RICOH IMAGING COMPANY, LTD.';
  static const _bluetoothMac = '00:00:5E:00:53:A9';
  static const _wifiMac = '00:00:5E:00:53:A8';

  void _initValues() {
    void text(GrBleCharacteristic<Object> c, String v) =>
        _values[c.uuid] = Uint8List.fromList(utf8.encode(v));
    void byte(GrBleCharacteristic<Object> c, int v) =>
        _values[c.uuid] = Uint8List.fromList([v]);
    text(GrBleCatalog.disManufacturerName, _manufacturer);
    text(GrBleCatalog.disModelNumber, config.model);
    text(GrBleCatalog.disSerialNumber, config.serial);
    text(GrBleCatalog.disFirmwareRevision, config.firmware);
    text(GrBleCatalog.disSoftwareRevision, config.firmware);
    text(GrBleCatalog.manufacturerName, _manufacturer);
    text(GrBleCatalog.modelName, config.model);
    text(GrBleCatalog.serialNumber, config.serial);
    text(GrBleCatalog.firmwareRevision, config.firmware);
    text(GrBleCatalog.bluetoothDeviceName, config.bluetoothName);
    text(GrBleCatalog.bluetoothMacAddress, _bluetoothMac);
    text(GrBleCatalog.ssid, config.ssid);
    text(GrBleCatalog.passphrase, config.passphrase);
    text(GrBleCatalog.cameraName, 'MY ${model.shortName}');
    byte(GrBleCatalog.wlanSecurity, BleWlanSecurity.wpa2.wire);
    byte(GrBleCatalog.wlanFrequency, BleWlanFrequency.band24GHz.wire);
    byte(GrBleCatalog.wlanChannel, BleWlanChannel.auto.wire);
    byte(GrBleCatalog.available5GHz, 1);
    byte(
      GrBleCatalog.bleEnableCondition,
      BleEnableCondition.enableAnytime.wire,
    );
    byte(GrBleCatalog.geoTag, 0);
  }

  /// Runs [action] after [delay] unless the camera has been closed.
  Timer _after(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (!_closed) action();
    });
    _timers.add(timer);
    return timer;
  }

  void _cancel(Timer? timer) {
    if (timer == null) return;
    timer.cancel();
    _timers.remove(timer);
  }

  void _setPower(bool on, {required int mode, bool keepLinks = false}) {
    if (on == _poweredOn) return;
    _poweredOn = on;
    if (on) {
      _mode = mode;
    } else {
      executePairingOpen = false;
      rejectPairing();
      _apDown();
    }
    _notify(GrBleCatalog.cameraPower, [
      on ? BleCameraPower.on.wire : BleCameraPower.off.wire,
    ]);
    // The main firmware's links end when it shuts down; a link opened to
    // the BT-only firmware ends when the main firmware takes over, unless
    // the camera keeps it ([FakeCameraConfig.wakeKeepsLink]).
    if (keepLinks) return;
    for (final link in _links.toList()) {
      link._drop(on ? 'camera restarted' : 'camera powered off');
    }
  }

  void _enableWlan() {
    if (_wlanEnabled) return;
    _wlanEnabled = true;
    final generation = ++_wlanGeneration;
    _notify(GrBleCatalog.networkType, [BleNetworkType.ap.wire]);
    _after(config.wlanOnDelay, () {
      if (generation != _wlanGeneration) return;
      _apReady = true;
      _apGone = false;
      final waiting = _apUp;
      _apUp = null;
      if (waiting != null && !waiting.isCompleted) waiting.complete(true);
    });
  }

  void _apDown() {
    _wlanGeneration++;
    final wasOn = _wlanEnabled;
    _wlanEnabled = false;
    _apReady = false;
    if (_joined && config.reportsWifiLoss) _wifiLost.add(null);
    _joined = false;
    _apGone = true;
    final waiting = _apUp;
    _apUp = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete(false);
    for (final ws in _sockets.toList()) {
      unawaited(ws.close(WebSocketStatus.goingAway));
    }
    _sockets.clear();
    if (wasOn) _notify(GrBleCatalog.networkType, [BleNetworkType.off.wire]);
  }

  FakePhoto? _find(String storage, String dir, String file) {
    for (final p in _photos) {
      if (p.storage == storage && p.dir == dir && p.file == file) return p;
    }
    return null;
  }

  void _pushStorage(String action, FakePhoto photo) => _push({
    'errCode': 200,
    'changed': 'storage',
    'action': action,
    'filepath': '${photo.dir}/${photo.file}',
    'storage': photo.storage,
    'captureId': '0',
  });

  void _push(Map<String, Object?> message) {
    final text = jsonEncode(message);
    for (final ws in _sockets) {
      ws.add(text);
    }
  }
}
