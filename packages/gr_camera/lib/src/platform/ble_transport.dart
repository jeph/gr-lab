import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

/// [BleTransport] over `universal_ble` (BSD-3-Clause; Android, iOS, macOS,
/// Windows, Linux). `universal_ble` is a process-wide singleton, so create
/// one transport per app.
///
/// The phone holds one link per camera, which `universal_ble` addresses by
/// device id, so owners asking for the same camera share it. Each
/// [connect] hands out its own [BleConnection]; the link is only closed by
/// the newest one, so a run that was cancelled while connecting cannot
/// drop the link a newer session or pairing run has been given. Connects
/// and disconnects of one device run one after another, so a connect never
/// gets a link that is still being set up or closed.
final class UniversalBleTransport implements BleTransport {
  /// GR WORLD requests a 512-byte MTU right after connecting (ble.md
  /// §Connection, pairing and reconnect).
  static const requestedMtu = 512;

  final Map<String, _UniversalBleLink> _links = {};

  /// Connects and disconnects, one device at a time.
  final _deviceOps = _Serial();

  /// Everyone scanning now; one platform scan serves them all.
  final List<_Scanner> _scanners = [];

  /// What the running platform scan was started for; null while none runs.
  _ScanNeed? _scanning;
  StreamSubscription<BleDevice>? _results;

  /// Starts and stops of the platform scan, one after another: a scan
  /// asked for while the previous one is stopping (the Cameras screen's
  /// nearby scan ending as a connection starts its own) starts once that
  /// has completed.
  Future<void> _scanOp = Future.value();

  @override
  Future<BleAdapterState> adapterState() async {
    final state = await _guard(UniversalBle.getBluetoothAvailabilityState);
    return switch (state) {
      AvailabilityState.unknown => BleAdapterState.unknown,
      AvailabilityState.resetting => BleAdapterState.resetting,
      AvailabilityState.unsupported => BleAdapterState.unsupported,
      AvailabilityState.unauthorized => BleAdapterState.unauthorized,
      AvailabilityState.poweredOff => BleAdapterState.poweredOff,
      AvailabilityState.poweredOn => BleAdapterState.poweredOn,
    };
  }

  /// Asks for the runtime Bluetooth permissions the platform needs before
  /// scanning (Android 12+ nearby-devices); a no-op elsewhere.
  Future<void> requestPermissions() => _guard(UniversalBle.requestPermissions);

  /// Scans share the one platform scan `universal_ble` has: a session
  /// that reads the advertisements of a camera it let go of scans for as
  /// long as it lasts, next to the Cameras screen's scan or a pairing
  /// run's. Each listener gets the advertisements its [serviceUuids] ask
  /// for; the platform filters only while every listener has a filter, and
  /// listens as much of the time as the listener that asks for most.
  ///
  /// Without a [rate], a search (no filter: a screen shows the results, or
  /// a connection looks for its camera) listens all the time, because
  /// Android's low-power mode misses cameras, and a filtered scan is a
  /// watch at low power.
  @override
  Stream<BleAdvertisement> scan({
    List<String> serviceUuids = const [],
    BleScanRate? rate,
  }) {
    late final _Scanner scanner;
    final controller = StreamController<BleAdvertisement>(
      onListen: () {
        _scanners.add(scanner);
        // A stop of the scan before that failed: the listeners hear of it.
        unawaited(_syncScan().catchError(_fail));
      },
      onCancel: () {
        if (!_scanners.remove(scanner)) return null;
        return _syncScan();
      },
    );
    scanner = _Scanner(controller, {
      for (final uuid in serviceUuids) _canonicalOrSelf(uuid),
    }, rate ?? (serviceUuids.isEmpty ? BleScanRate.full : BleScanRate.low));
    return controller.stream;
  }

  /// Brings the platform scan in line with [_scanners], after every start
  /// and stop asked for before. A start that fails ends every scan
  /// listening then with its error; a stop that fails is the error of the
  /// call that asked for it.
  Future<void> _syncScan() {
    final op = _scanOp.then((_) async {
      final need = _ScanNeed.of(_scanners);
      if (need == _scanning) return;
      if (_scanning != null) {
        _scanning = null;
        await _results?.cancel();
        _results = null;
        await _guard(UniversalBle.stopScan);
      }
      if (need == null) return;
      _results = UniversalBle.scanStream.listen(_deliver, onError: _fail);
      _scanning = need;
      try {
        await _guard(
          () => UniversalBle.startScan(
            scanFilter: need.services.isEmpty
                ? null
                : ScanFilter(withServices: need.services.toList()),
            platformConfig: PlatformConfig(
              android: AndroidOptions(
                // How much each mode listens, and what Android makes of
                // it with the screen off:
                // research/protocol/power-on-grworld.md §8.1.
                scanMode: switch (need.rate) {
                  BleScanRate.full => AndroidScanMode.lowLatency,
                  BleScanRate.balanced => AndroidScanMode.balanced,
                  BleScanRate.low => AndroidScanMode.lowPower,
                },
              ),
            ),
          ),
        );
      } on Object catch (e, s) {
        _scanning = null;
        await _results?.cancel();
        _results = null;
        _fail(e, s);
        for (final scanner in _scanners.toList()) {
          _scanners.remove(scanner);
          unawaited(scanner.controller.close());
        }
      }
    });
    // The next start or stop only waits; the error is this caller's.
    _scanOp = op.catchError((Object _) {});
    return op;
  }

  void _deliver(BleDevice device) {
    final advertisement = _advertisement(device);
    for (final scanner in _scanners.toList()) {
      if (scanner.wants(advertisement)) scanner.controller.add(advertisement);
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    for (final scanner in _scanners.toList()) {
      scanner.controller.addError(error, stack);
    }
  }

  @override
  Future<BleConnection> connect(String deviceId, {required Duration timeout}) =>
      _deviceOps.run(deviceId, () => _connect(deviceId, timeout));

  Future<BleConnection> _connect(String deviceId, Duration timeout) async {
    final existing = _links[deviceId];
    if (existing != null && !existing.isClosed) return existing.handOut();
    late final _UniversalBleLink link;
    link = _UniversalBleLink(
      deviceId,
      onClosed: () {
        if (identical(_links[deviceId], link)) _links.remove(deviceId);
      },
      serialize: (op) => _deviceOps.run(deviceId, op),
    );
    try {
      await _guard(() => UniversalBle.connect(deviceId, timeout: timeout));
    } on Object catch (e) {
      final bondRejected = link.bondRejected;
      link.dispose();
      // CoreBluetooth and Android keep a connect request pending after the
      // Dart-side timeout; cancel it so it cannot complete later or block
      // the next attempt.
      try {
        await UniversalBle.disconnect(
          deviceId,
          timeout: const Duration(seconds: 2),
        );
      } on Object {
        // Nothing pending; the original failure is what matters.
      }
      if (bondRejected) {
        throw BleException(BleErrorCode.bondRejected, '$e');
      }
      rethrow;
    }
    _links[deviceId] = link;
    await link.negotiateMtu(timeout);
    return link.handOut();
  }

  @override
  Future<void> close() async {
    // Their streams stay open, as a cancelled scan's would; nothing more
    // is delivered.
    _scanners.clear();
    await _syncScan();
    for (final link in _links.values.toList()) {
      await link.disconnect();
    }
  }

  static BleAdvertisement _advertisement(BleDevice d) => BleAdvertisement(
    deviceId: d.deviceId,
    name: d.name,
    rssi: d.rssi ?? 0,
    manufacturerData: {
      for (final m in d.manufacturerDataList) m.companyId: m.payload,
    },
    serviceUuids: [for (final u in d.services) _canonicalOrSelf(u)],
    connectable: d.connectable,
  );
}

/// One listener of [UniversalBleTransport.scan].
final class _Scanner {
  new(this.controller, this.services, this.rate);

  final StreamController<BleAdvertisement> controller;

  /// The services it asked for, canonical; empty for every advertisement.
  final Set<String> services;

  /// How much of the time it wants the scan to listen.
  final BleScanRate rate;

  bool wants(BleAdvertisement advertisement) =>
      services.isEmpty || advertisement.serviceUuids.any(services.contains);
}

/// What the platform scan has to deliver for a set of listeners.
@immutable
final class _ScanNeed {
  const new(this.services, this.rate);

  /// Null without listeners. One listener without a filter makes the whole
  /// scan unfiltered; otherwise the platform filters to every service
  /// asked for. It listens as much as the listener that asks for most.
  static _ScanNeed? of(List<_Scanner> scanners) {
    if (scanners.isEmpty) return null;
    final rate = scanners
        .map((s) => s.rate)
        .reduce((a, b) => a.index < b.index ? a : b);
    final services = scanners.any((s) => s.services.isEmpty)
        ? const <String>{}
        : {for (final s in scanners) ...s.services};
    return _ScanNeed(services, rate);
  }

  /// The services the platform filters to; empty for no filter.
  final Set<String> services;

  /// How much of the time the platform scan listens.
  final BleScanRate rate;

  @override
  bool operator ==(Object other) =>
      other is _ScanNeed &&
      other.rate == rate &&
      other.services.length == services.length &&
      other.services.containsAll(services);

  @override
  int get hashCode => Object.hash(rate, Object.hashAllUnordered(services));
}

/// One owner's use of a [_UniversalBleLink], handed out by
/// [UniversalBleTransport.connect].
final class _UniversalBleConnection implements BleConnection {
  new(this._link);

  final _UniversalBleLink _link;

  /// Completed when this owner let go of a link a newer connection uses.
  final Completer<BleDisconnect> _released = Completer();

  @override
  String get deviceId => _link.deviceId;

  @override
  int? get maximumWriteLength => _link.maximumWriteLength;

  @override
  late final Future<BleDisconnect> disconnected = Future.any([
    _link.disconnected,
    _released.future,
  ]);

  @override
  Future<List<BleServiceInfo>> discover() async {
    _checkHeld();
    return await _link.discover();
  }

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    _checkHeld();
    return await _link.read(serviceUuid, characteristicUuid, timeout: timeout);
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    _checkHeld();
    await _link.write(
      serviceUuid,
      characteristicUuid,
      value,
      withResponse: withResponse,
      timeout: timeout,
    );
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) {
    if (_released.isCompleted) return Stream.error(_releasedError);
    return _link.subscribe(serviceUuid, characteristicUuid);
  }

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {
    _checkHeld();
    await _link.pair(
      probeServiceUuid: probeServiceUuid,
      probeCharacteristicUuid: probeCharacteristicUuid,
      timeout: timeout,
    );
  }

  /// Closes the link, unless a newer connection has been handed it: then
  /// only this one ends, and the link stays up for its new owner.
  @override
  Future<void> disconnect() => _link.release(this);

  void _letGo() {
    if (_released.isCompleted) return;
    _released.complete(
      const BleDisconnect(
        requested: true,
        reason: 'the link stays up for a newer connection',
      ),
    );
  }

  static const _releasedError = BleException(
    BleErrorCode.notConnected,
    'disconnected; a newer connection uses the link',
  );

  void _checkHeld() {
    if (_released.isCompleted) throw _releasedError;
  }
}

/// The phone's link to one peripheral, shared by every connection handed
/// out for it.
final class _UniversalBleLink {
  new(this.deviceId, {required this._onClosed, required this._serialize}) {
    _connectionSub = UniversalBle.connectionChangeStream(deviceId).listen((c) {
      if (c.isConnected) return;
      if (_isBondRejection(c.nativeErrorCode)) bondRejected = true;
      _finish(c.error ?? c.errorCode?.name);
    });
  }

  /// Native disconnect codes meaning the peer refused our stored keys:
  /// CoreBluetooth `CBError.peerRemovedPairingInformation` (14, observed
  /// on the GR IV after its entry was deleted); Android reports the HCI
  /// disconnect reason, where 0x06 is "PIN or Key Missing" (Bluetooth Core
  /// spec Vol 1 Part F).
  static bool _isBondRejection(int? code) {
    if (code == null) return false;
    if (Platform.isMacOS || Platform.isIOS) return code == 14;
    if (Platform.isAndroid) return code == 0x06;
    return false;
  }

  /// Set when a disconnect carried a [_isBondRejection] code.
  bool bondRejected = false;

  final String deviceId;
  final void Function() _onClosed;

  /// Runs an operation in turn with the transport's connects and
  /// disconnects of this device.
  final Future<void> Function(Future<void> Function() op) _serialize;
  late final StreamSubscription<BleConnectionChange> _connectionSub;
  final Completer<BleDisconnect> _disconnected = Completer();
  final Map<String, Set<BleCharacteristicProperty>> _properties = {};
  bool _requested = false;
  int? _maximumWriteLength;

  /// The connection handed out last; only it closes the link.
  _UniversalBleConnection? _newest;

  /// Listened [subscribe] streams per characteristic. The platform enables
  /// notifications per characteristic, not per listener.
  final Map<String, int> _subscribers = {};

  /// Enables and disables, one characteristic at a time.
  final _notifyOps = _Serial();

  bool get isClosed => _disconnected.isCompleted;

  int? get maximumWriteLength => _maximumWriteLength;

  Future<BleDisconnect> get disconnected => _disconnected.future;

  /// A new connection for a new owner; older ones can no longer close the
  /// link.
  _UniversalBleConnection handOut() => _newest = _UniversalBleConnection(this);

  /// [connection]'s owner is done with the link: the newest connection
  /// closes it, an older one only lets go. Decided in turn with connects,
  /// so a connect that has just handed the link to someone else counts.
  Future<void> release(_UniversalBleConnection connection) async {
    if (isClosed) return;
    await _serialize(() async {
      if (isClosed) return;
      if (!identical(connection, _newest)) return connection._letGo();
      await disconnect();
    });
  }

  /// Best effort: CoreBluetooth negotiates the MTU itself and Windows may
  /// refuse; the camera works at the default MTU for every documented
  /// characteristic except long Image Control blobs.
  Future<void> negotiateMtu(Duration timeout) async {
    try {
      final mtu = await UniversalBle.requestMtu(
        deviceId,
        UniversalBleTransport.requestedMtu,
        timeout: timeout,
      );
      _maximumWriteLength = mtu - 3;
    } on Object {
      _maximumWriteLength = null;
    }
  }

  Future<List<BleServiceInfo>> discover() async {
    final services = await _guard(
      () => UniversalBle.discoverServices(deviceId),
    );
    return [
      for (final s in services)
        BleServiceInfo(
          uuid: _canonicalOrSelf(s.uuid),
          characteristics: [
            for (final c in s.characteristics)
              BleCharacteristicInfo(
                uuid: _canonicalOrSelf(c.uuid),
                properties: _properties[_canonicalOrSelf(c.uuid)] = {
                  for (final p in c.properties) ?_property(p),
                },
              ),
          ],
        ),
    ];
  }

  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) => _guard(
    () => UniversalBle.read(
      deviceId,
      serviceUuid,
      characteristicUuid,
      timeout: timeout,
    ),
  );

  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) => _guard(
    () => UniversalBle.write(
      deviceId,
      serviceUuid,
      characteristicUuid,
      value,
      withoutResponse: !withResponse,
      timeout: timeout,
    ),
  );

  /// Notifications (or indications) of one characteristic, enabled while at
  /// least one returned stream is listened to. The platform switches them
  /// per characteristic, so enables and disables run in turn and go by the
  /// listeners left when they run: a stream cancelled as its replacement
  /// starts cannot switch the replacement's notifications off.
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) {
    final key = _canonicalOrSelf(characteristicUuid);
    late final StreamController<Uint8List> controller;
    StreamSubscription<Uint8List>? values;
    var counted = false;
    // True when this stream was still counted as a listener.
    bool stopCounting() {
      if (!counted) return false;
      counted = false;
      final left = _subscribers[key]! - 1;
      if (left == 0) {
        _subscribers.remove(key);
      } else {
        _subscribers[key] = left;
      }
      return true;
    }

    controller = StreamController<Uint8List>(
      onListen: () async {
        counted = true;
        _subscribers.update(key, (n) => n + 1, ifAbsent: () => 1);
        values = UniversalBle.characteristicValueStream(
          deviceId,
          characteristicUuid,
        ).listen(controller.add, onError: controller.addError);
        try {
          await _notifyOps.run(key, () async {
            // Cancelled before its turn, and nobody else listens.
            if (!_subscribers.containsKey(key)) return;
            await _guard(() => _enable(serviceUuid, characteristicUuid));
          });
        } on Object catch (e, s) {
          stopCounting();
          controller.addError(e, s);
          await values?.cancel();
          await controller.close();
        }
      },
      onCancel: () async {
        final wasCounted = stopCounting();
        await values?.cancel();
        if (!wasCounted || isClosed) return;
        await _notifyOps.run(key, () async {
          // A newer listener (a watcher's replacement) still needs them.
          if (_subscribers.containsKey(key) || isClosed) return;
          try {
            await UniversalBle.unsubscribe(
              deviceId,
              serviceUuid,
              characteristicUuid,
            );
          } on Object {
            // The link may have dropped meanwhile; nothing left to disable.
          }
        });
      },
    );
    return controller.stream;
  }

  Future<void> _enable(String serviceUuid, String characteristicUuid) {
    final props = _properties[_canonicalOrSelf(characteristicUuid)];
    final indicateOnly =
        props != null &&
        props.contains(BleCharacteristicProperty.indicate) &&
        !props.contains(BleCharacteristicProperty.notify);
    return indicateOnly
        ? UniversalBle.subscribeIndications(
            deviceId,
            serviceUuid,
            characteristicUuid,
          )
        : UniversalBle.subscribeNotifications(
            deviceId,
            serviceUuid,
            characteristicUuid,
          );
  }

  /// Closes the link for every connection handed out for it.
  Future<void> disconnect() async {
    if (isClosed) return;
    _requested = true;
    try {
      await _guard(() => UniversalBle.disconnect(deviceId));
    } finally {
      _finish(null);
    }
  }

  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) => _guard(
    () => UniversalBle.pair(
      deviceId,
      pairingCommand: BleCommand(
        service: probeServiceUuid,
        characteristic: probeCharacteristicUuid,
      ),
      timeout: timeout,
    ),
  );

  void dispose() {
    unawaited(_connectionSub.cancel());
  }

  void _finish(String? reason) {
    if (_disconnected.isCompleted) return;
    _disconnected.complete(
      BleDisconnect(
        requested: _requested,
        reason: reason,
        bondRejected: bondRejected,
      ),
    );
    dispose();
    _onClosed();
  }

  static BleCharacteristicProperty? _property(CharacteristicProperty p) =>
      switch (p) {
        CharacteristicProperty.read => BleCharacteristicProperty.read,
        CharacteristicProperty.write => BleCharacteristicProperty.write,
        CharacteristicProperty.writeWithoutResponse =>
          BleCharacteristicProperty.writeWithoutResponse,
        CharacteristicProperty.notify => BleCharacteristicProperty.notify,
        CharacteristicProperty.indicate => BleCharacteristicProperty.indicate,
        _ => null,
      };
}

/// Runs operations that share a key one after another, in call order.
/// Keys are device ids and characteristic UUIDs, so the map stays small.
final class _Serial {
  final Map<String, Future<void>> _tails = {};

  Future<T> run<T>(String key, Future<T> Function() op) {
    final result = (_tails[key] ?? Future<void>.value()).then((_) => op());
    _tails[key] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

String _canonicalOrSelf(String uuid) {
  try {
    return canonicalUuid(uuid);
  } on FormatException {
    return uuid;
  }
}

/// Runs a `universal_ble` call, translating its errors into [BleException].
Future<T> _guard<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on UniversalBleException catch (e) {
    throw BleException(bleErrorCodeFor(e.code), e.message);
  } on TimeoutException catch (e) {
    throw BleException(BleErrorCode.timeout, e.message ?? 'timed out');
  }
}

/// Maps `universal_ble` error codes onto the protocol's coarser set.
BleErrorCode bleErrorCodeFor(UniversalBleErrorCode code) => switch (code) {
  UniversalBleErrorCode.connectionTimeout ||
  UniversalBleErrorCode.operationTimeout ||
  UniversalBleErrorCode.pairingTimeout => BleErrorCode.timeout,
  UniversalBleErrorCode.deviceDisconnected ||
  UniversalBleErrorCode.connectionTerminated => BleErrorCode.notConnected,
  UniversalBleErrorCode.deviceNotFound ||
  UniversalBleErrorCode.serviceNotFound ||
  UniversalBleErrorCode.characteristicNotFound => BleErrorCode.notFound,
  UniversalBleErrorCode.bluetoothNotAllowed ||
  UniversalBleErrorCode.bluetoothUnauthorized ||
  UniversalBleErrorCode.insufficientAuthentication ||
  UniversalBleErrorCode.insufficientAuthorization ||
  UniversalBleErrorCode.insufficientEncryption ||
  UniversalBleErrorCode.authenticationFailure ||
  UniversalBleErrorCode.accessDenied => BleErrorCode.unauthorized,
  UniversalBleErrorCode.bluetoothNotEnabled => BleErrorCode.poweredOff,
  UniversalBleErrorCode.readFailed ||
  UniversalBleErrorCode.readNotPermitted ||
  UniversalBleErrorCode.writeFailed ||
  UniversalBleErrorCode.writeNotPermitted ||
  UniversalBleErrorCode.invalidAttributeLength ||
  UniversalBleErrorCode.invalidHandle ||
  UniversalBleErrorCode.invalidOffset ||
  UniversalBleErrorCode.invalidPdu => BleErrorCode.gatt,
  _ => BleErrorCode.transport,
};
