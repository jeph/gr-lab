import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:gr_fake_camera/src/config.dart';
import 'package:gr_fake_camera/src/media.dart';
import 'package:gr_protocol/gr_protocol.dart';

part 'ble_side.dart';
part 'http_side.dart';
part 'location_side.dart';
part 'shoot_side.dart';
part 'wifi_side.dart';

/// Thrown by [FakeGrCamera.wifi] when a join fails.
final class FakeWifiException implements Exception {
  /// Wraps [message], the reason the join failed.
  const new(this.message);

  /// Why the join failed.
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
///   point is up, with the SSID and passphrase the camera reports;
/// * in capture mode it takes pictures on a BLE Operation Request or an
///   HTTP shoot, after the drive mode's self-timer, streams live view and
///   takes exposure settings from the lists `/v1/props` offers
///   (remote-shooting.md);
/// * it takes a phone's position only while Store Location Info is on,
///   keeps it for 600 s, across a power cycle too, and clears it when the
///   setting goes off or, on a GR IV, a second after its clock changes, as
///   the firmware does (geotagging.md §1).
///
/// The HTTP server stands in for the camera's network: it answers while
/// the camera is on and its access point has not gone down, so HTTP-only
/// tests can use it without a BLE session.
final class FakeGrCamera {
  /// A camera serving [media] as its file bytes, set up by [config].
  ///
  /// Throws [ArgumentError] when [FakeCameraConfig.model] is not a GR model
  /// string.
  new({required this.media, this.config = const FakeCameraConfig()})
    : model =
          GrModel.fromModelString(config.model) ??
          (throw ArgumentError.value(
            config.model,
            'config.model',
            'not a GR model string',
          )),
      executePairingOpen = config.executePairingOpen,
      _poweredOn = config.poweredOn,
      _hostAsleep = !config.poweredOn,
      _apGone = !config.poweredOn,
      _bonded = config.bonded,
      _battery = config.battery,
      _exposureMode = config.exposureMode,
      _remaining = config.remainingPictures,
      _clockOffset = config.clockOffset,
      _photos = List.of(config.photos ?? FakePhoto.defaultCard()) {
    _initValues();
  }

  /// Identity, timing and failure injection this camera was built with.
  final FakeCameraConfig config;

  /// Bytes served for each photo and size.
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

  /// While set, `/v1/photos/<dir>/<file>/info` answers only once it
  /// completes: a camera slow to describe a file.
  Completer<void>? infoGate;

  /// While set, `/v1/props` answers only once it completes: a camera that
  /// has gone quiet on a request. A request already waiting keeps waiting
  /// after this is cleared.
  Completer<void>? propsGate;

  bool _poweredOn;

  /// Off, and no link has been opened since: the next one wakes the
  /// camera's host ([FakeCameraConfig.firstOffLinkDrop]).
  bool _hostAsleep;
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
  bool _bluetoothOff = false;

  // Remote shooting (shoot_side.dart).
  int _driveMode = BleDriveMode.single.wire;
  BleExposureMode _exposureMode;
  BleUserMode _userMode = BleUserMode.none;
  int _remaining;
  bool _capturing = false;
  BleCountdown _countdown = BleCountdown.none;
  Timer? _releaseTimer;
  int _captureIds = 0;
  GrCameraOrientation _orientation = GrCameraOrientation.positive;

  /// Ends when the running focus does (see `_focus`).
  Future<void> _focusEnd = Future.value();
  final _focusPoints = <(int, int)>[];

  // Location and clock (location_side.dart).
  Duration _clockOffset;
  FakeCameraLocation? _location;

  /// When the camera's timer for [_location] runs out, in the phone's
  /// time (`clock.now()`): it counts time that passes, not the camera's
  /// clock.
  DateTime? _locationUntil;
  final _locationWrites = <FakeCameraLocation>[];
  int _refusedLocationWrites = 0;
  final _clockWrites = <DateTime>[];

  /// Current values of the writable `/v1/props` settings.
  final Map<String, String> _settings = {
    'av': '2.8',
    'tv': '1.250',
    'sv': '200',
    'xv': '0.0',
    'meteringMode': 'multi',
    'effect': 'off',
  };

  /// Captured photos and the card photo whose bytes they serve.
  final Map<FakePhoto, FakePhoto> _captureSources = Map.identity();

  /// Open live-view streams, ended with the access point.
  final Set<Socket> _liveViews = {};

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

  /// The zone [startHttp] was called in, where the server's sockets run.
  Zone _httpZone = Zone.current;
  final Set<WebSocket> _sockets = {};
  final Map<FakePhoto, int> _fullSizes = Map.identity();

  /// Thumbnail/preview requests per `<photo>|<size>`, for
  /// [FakeCameraConfig.previewFailures].
  final Map<String, int> _previewRequests = {};

  // ------------------------------------------------------------- scenario

  /// On (main firmware) or off (BT-only: still advertises and accepts a
  /// bonded link). Turning it off drops every link and the access point;
  /// turning it on starts in capture mode with Wi-Fi off, and with
  /// Bluetooth back after [powerOffFully].
  bool get poweredOn => _poweredOn;
  set poweredOn(bool on) {
    if (on) _bluetoothOff = false;
    _setPower(on, mode: BleOperationMode.capture.wire);
  }

  /// Switched off with Bluetooth off as well (the camera's Bluetooth is not
  /// kept on while it is off): links drop, and it neither advertises nor
  /// accepts a link until [poweredOn] turns it on again.
  void powerOffFully() {
    _bluetoothOff = true;
    _setPower(false, mode: _mode);
    // Already off, [_setPower] keeps the BT-only firmware's links.
    for (final link in _links.toList()) {
      link._drop('camera powered off');
    }
  }

  /// The user switches the camera on and it keeps its open Bluetooth
  /// links, reporting Camera Power on over them, instead of dropping them
  /// as [poweredOn] does. What a link that is up sees when the power
  /// button is pressed is \[unknown\]
  /// (research/protocol/power-on-grworld.md §8), so a client has to
  /// handle both.
  void powerOnKeepingLinks() {
    _bluetoothOff = false;
    _setPower(true, mode: BleOperationMode.capture.wire, keepLinks: true);
  }

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

  /// Open live-view streams.
  int get liveViewStreams => _liveViews.length;

  /// Battery charge in percent; setting it notifies BLE Battery Level and
  /// pushes a `battery` change over the WebSocket.
  int get battery => _battery;
  set battery(int percent) {
    _battery = percent;
    _notify(GrBleCatalog.batteryLevel, [percent & 0xff]);
    _push({'errCode': 200, 'changed': 'battery'});
  }

  /// BLE Drive Mode, also `/v1/props` `shootMode`.
  BleDriveMode get driveMode =>
      BleDriveMode.values.firstWhere((m) => m.wire == _driveMode);

  /// Mode-dial position (BLE Shooting Mode byte 0).
  BleExposureMode get exposureMode => _exposureMode;

  /// Pictures the storage this camera saves to still has room for.
  int get remainingPictures => _remaining;

  /// The user turns the mode dial: BLE Shooting Mode notifies and
  /// `/v1/props` `exposureMode` follows, with a `camera` change.
  void setExposureMode(
    BleExposureMode mode, {
    BleUserMode userMode = BleUserMode.none,
  }) {
    _exposureMode = mode;
    _userMode = userMode;
    _notify(GrBleCatalog.shootingMode, [mode.wire, userMode.wire]);
    if (config.announcesDialChanges) {
      _push({'errCode': 200, 'changed': 'camera'});
    }
  }

  /// The camera changes an exposure setting itself, as the shutter speed
  /// it picks in Av. No change is pushed: a GR IV HDF sent none for mode
  /// dial changes either (2026-11-08); whether it pushes one for its own
  /// exposure is \[unknown\].
  void cameraSets(String key, String value) => _settings[key] = value;

  /// How the camera is held: `/v1/props` `cameraOrientation`. Turning it
  /// pushes a `cameraDirect` change, as GR IV webapid sends one whenever
  /// the orientation changes (remote-shooting.md §1.5).
  GrCameraOrientation get orientation => _orientation;

  set orientation(GrCameraOrientation value) {
    if (value == _orientation) return;
    _orientation = value;
    _pushCameraDirect();
  }

  /// The card, in insertion order.
  List<FakePhoto> get photos => List.unmodifiable(_photos);

  /// The `pos` of every focus the camera ran, in percent, in order.
  List<(int, int)> get focusPoints => List.unmodifiable(_focusPoints);

  /// What Custom slot [number] (1–3) holds: its name and look. The slot
  /// only ever holds blobs it accepted, so they decode.
  FakeLook lookSlot(int number) {
    final slot = GrBleCatalog.imageControlSlots[number - 1];
    final data = _values[slot.data.uuid]!;
    return FakeLook(
      utf8.decode(_values[slot.name.uuid]!),
      slot.data.codec.decode(data).value!,
    );
  }

  /// The camera's Store Location Info setting (BLE GEO Tag). Setting it
  /// here is the user changing it in the camera's menu: GEO Tag notifies,
  /// and turning it off clears the location the camera holds
  /// (research/protocol/geotagging.md §1.3).
  bool get storeLocationInfo => _values[GrBleCatalog.geoTag.uuid]!.first == 1;
  set storeLocationInfo(bool on) => _setStoreLocationInfo(on, notify: true);

  /// While set, the camera refuses every position although Store Location
  /// Info is on. The firmware takes one only while the property is
  /// settable and a lock byte is 0 (geotagging.md §1.2); what sets either
  /// is \[unknown\].
  bool locationLocked = false;

  /// The position the camera holds now, which it would save in a picture;
  /// null when it has none or the one it took has run out.
  FakeCameraLocation? get location => _heldLocation;

  /// Every position the camera accepted, oldest first.
  List<FakeCameraLocation> get locationWrites =>
      List.unmodifiable(_locationWrites);

  /// How many GPS Information writes the camera refused.
  int get refusedLocationWrites => _refusedLocationWrites;

  /// The camera's clock now: local time, as its Date Time reads, running
  /// [clockOffset] ahead of the phone's (`clock.now()`).
  DateTime get clockTime => _clockNow;

  /// How far the camera's clock runs ahead of the phone's (negative:
  /// behind). Setting it here is the user setting the clock in the
  /// camera's menu, or the clock having drifted: like every change of the
  /// clock, on a GR IV it clears the location a second later
  /// (geotagging.md §1.3).
  Duration get clockOffset => _clockOffset;
  set clockOffset(Duration offset) => _setClock(offset);

  /// The time each Date Time write set the clock to, oldest first.
  List<DateTime> get clockWrites => List.unmodifiable(_clockWrites);

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

  /// Storages whose listing answers `errCode` 500, as GR IV webapid does
  /// for a storage it cannot read at that moment
  /// (research/protocol/http-api.md "Storage values"); `/v1/props` still
  /// reports them as equipped and available.
  final Set<String> failingListings = {};

  /// The `/v1/changes` sockets drop while HTTP keeps answering. The
  /// camera keeps no changes for a socket that is not open, so changes
  /// until a client reopens one reach nobody.
  void dropChangeSockets() {
    _onChangeSockets((ws) => unawaited(ws.close(WebSocketStatus.goingAway)));
    _sockets.clear();
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
    dropChangeSockets();
    _endLiveViews();
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
    byte(GrBleCatalog.geoTag, config.storeLocationInfo ? 1 : 0);
    final looks = config.lookSlots ?? FakeLook.presets.sublist(0, 3);
    for (var i = 0; i < GrBleCatalog.imageControlSlots.length; i++) {
      final slot = GrBleCatalog.imageControlSlots[i];
      text(slot.name, looks[i].name);
      _values[slot.data.uuid] = Uint8List.fromList(looks[i].data);
    }
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
    _hostAsleep = !on;
    if (on) {
      _mode = mode;
      _restoreLocation();
    } else {
      executePairingOpen = false;
      rejectPairing();
      _abortRelease();
      _apDown();
    }
    _notify(GrBleCatalog.cameraPower, [
      if (on) BleCameraPower.on.wire else BleCameraPower.off.wire,
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
    dropChangeSockets();
    _endLiveViews();
    if (wasOn) _notify(GrBleCatalog.networkType, [BleNetworkType.off.wire]);
  }

  FakePhoto? _find(String storage, String dir, String file) {
    for (final p in _photos) {
      if (p.storage == storage && p.dir == dir && p.file == file) return p;
    }
    return null;
  }

  void _pushStorage(String action, FakePhoto photo, {String captureId = '0'}) =>
      _push({
        'errCode': 200,
        'changed': 'storage',
        'action': action,
        'filepath': '${photo.dir}/${photo.file}',
        'storage': photo.storage,
        'captureId': captureId,
      });

  /// What [media] serves for [photo]; a captured photo serves the bytes of
  /// the card photo it was made from.
  Future<Uint8List> _media(FakePhoto photo, GrImageSize size) =>
      media(_captureSources[photo] ?? photo, size);

  void _endLiveViews() {
    for (final socket in _liveViews) {
      socket.destroy();
    }
    _liveViews.clear();
  }

  void _push(Map<String, Object?> message) {
    final text = jsonEncode(message);
    _onChangeSockets((ws) => ws.add(text));
  }

  /// Runs [action] on every change socket in [_httpZone]. A WebSocket's
  /// sending side belongs to the zone of its first send or close, and
  /// changes come from other zones: a widget test sets camera state in its
  /// fake-time zone, where a failed write to a socket the client has left
  /// is reported only on the test's next pump, by which time the socket is
  /// closed (`Cannot add event after closing`).
  void _onChangeSockets(void Function(WebSocket ws) action) {
    _httpZone.run(() => _sockets.toList().forEach(action));
  }
}
