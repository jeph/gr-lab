import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

/// [BleTransport] over `universal_ble` (BSD-3-Clause; Android, iOS, macOS,
/// Windows, Linux). `universal_ble` is a process-wide singleton, so create
/// one transport per app.
final class UniversalBleTransport implements BleTransport {
  /// GR WORLD requests a 512-byte MTU right after connecting (ble.md
  /// §Connection, pairing and reconnect).
  static const requestedMtu = 512;

  final Map<String, _UniversalBleConnection> _connections = {};

  /// The scan stream that owns the platform scan. Only its cancellation
  /// stops the scan; a rejected concurrent scan must not.
  StreamController<BleAdvertisement>? _scanOwner;

  /// The platform stop of the previous owner. A cancelled scan releases
  /// ownership at once, so a scan asked for straight afterwards (the Cameras
  /// screen's nearby scan ending as a connection starts its own) is accepted
  /// and starts once this completes.
  Future<void> _stopping = Future.value();

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

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    late final StreamController<BleAdvertisement> controller;
    StreamSubscription<BleDevice>? sub;
    var started = false;
    controller = StreamController<BleAdvertisement>(
      onListen: () async {
        if (_scanOwner != null) {
          controller.addError(
            const BleException(BleErrorCode.transport, 'a scan is running'),
          );
          await controller.close();
          return;
        }
        _scanOwner = controller;
        await _stopping;
        // Cancelled while the previous scan was stopping.
        if (!identical(_scanOwner, controller)) return;
        sub = UniversalBle.scanStream.listen(
          (d) => controller.add(_advertisement(d)),
          onError: controller.addError,
        );
        try {
          started = true;
          await _guard(
            () => UniversalBle.startScan(
              scanFilter: serviceUuids.isEmpty
                  ? null
                  : ScanFilter(withServices: serviceUuids),
              // Android's default low-power mode listens ~0.5 s every 5 s
              // and misses cameras; the app scans only while a screen
              // shows the results or a connection looks for its camera.
              platformConfig: PlatformConfig(
                android: AndroidOptions(scanMode: AndroidScanMode.lowLatency),
              ),
            ),
          );
        } catch (e, s) {
          started = false;
          controller.addError(e, s);
          await sub?.cancel();
          if (identical(_scanOwner, controller)) _scanOwner = null;
          await controller.close();
        }
      },
      onCancel: () {
        if (!identical(_scanOwner, controller)) return sub?.cancel();
        _scanOwner = null;
        final listening = sub;
        final stop = started;
        final stopping = () async {
          await listening?.cancel();
          if (stop) await _guard(UniversalBle.stopScan);
        }();
        // The next scan only waits; the error is the canceller's.
        _stopping = stopping.catchError((Object _) {});
        return stopping;
      },
    );
    return controller.stream;
  }

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    final existing = _connections[deviceId];
    if (existing != null && !existing.isClosed) return existing;
    final connection = _UniversalBleConnection(deviceId, () {
      _connections.remove(deviceId);
    });
    try {
      await _guard(() => UniversalBle.connect(deviceId, timeout: timeout));
    } catch (e) {
      final bondRejected = connection.bondRejected;
      connection.dispose();
      // CoreBluetooth and Android keep a connect request pending after the
      // Dart-side timeout; cancel it so it cannot complete later or block
      // the next attempt.
      try {
        await UniversalBle.disconnect(
          deviceId,
          timeout: const Duration(seconds: 2),
        );
      } catch (_) {
        // Nothing pending; the original failure is what matters.
      }
      if (bondRejected) {
        throw BleException(BleErrorCode.bondRejected, '$e');
      }
      rethrow;
    }
    _connections[deviceId] = connection;
    await connection.negotiateMtu(timeout);
    return connection;
  }

  @override
  Future<void> close() async {
    if (_scanOwner != null) {
      _scanOwner = null;
      await _guard(UniversalBle.stopScan);
    }
    await _stopping;
    for (final c in _connections.values.toList()) {
      await c.disconnect();
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

final class _UniversalBleConnection implements BleConnection {
  _UniversalBleConnection(this.deviceId, this._onClosed) {
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

  @override
  final String deviceId;
  final void Function() _onClosed;
  late final StreamSubscription<BleConnectionChange> _connectionSub;
  final Completer<BleDisconnect> _disconnected = Completer();
  final Map<String, Set<BleCharacteristicProperty>> _properties = {};
  bool _requested = false;
  int? _maximumWriteLength;

  bool get isClosed => _disconnected.isCompleted;

  @override
  int? get maximumWriteLength => _maximumWriteLength;

  @override
  Future<BleDisconnect> get disconnected => _disconnected.future;

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
    } catch (_) {
      _maximumWriteLength = null;
    }
  }

  @override
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

  @override
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

  @override
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

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) {
    late final StreamController<Uint8List> controller;
    StreamSubscription<Uint8List>? sub;
    controller = StreamController<Uint8List>(
      onListen: () async {
        sub = UniversalBle.characteristicValueStream(
          deviceId,
          characteristicUuid,
        ).listen(controller.add, onError: controller.addError);
        final props = _properties[_canonicalOrSelf(characteristicUuid)];
        final indicateOnly =
            props != null &&
            props.contains(BleCharacteristicProperty.indicate) &&
            !props.contains(BleCharacteristicProperty.notify);
        try {
          await _guard(
            () => indicateOnly
                ? UniversalBle.subscribeIndications(
                    deviceId,
                    serviceUuid,
                    characteristicUuid,
                  )
                : UniversalBle.subscribeNotifications(
                    deviceId,
                    serviceUuid,
                    characteristicUuid,
                  ),
          );
        } catch (e, s) {
          controller.addError(e, s);
          await sub?.cancel();
          await controller.close();
        }
      },
      onCancel: () async {
        await sub?.cancel();
        if (isClosed) return;
        try {
          await UniversalBle.unsubscribe(
            deviceId,
            serviceUuid,
            characteristicUuid,
          );
        } catch (_) {
          // The link may have dropped meanwhile; nothing left to disable.
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> disconnect() async {
    if (isClosed) return;
    _requested = true;
    try {
      await _guard(() => UniversalBle.disconnect(deviceId));
    } finally {
      _finish(null);
    }
  }

  @override
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
