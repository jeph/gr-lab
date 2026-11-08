import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

/// A bonded camera reached by device id. [operationMode] is what Operation
/// Mode reads (`02` = off, BT-only); writes to it are recorded.
final class BondedCamera implements BleTransport {
  BondedCamera({
    this.operationMode = 1,
    this.connectError,
    this.bonded = true,
    this.dropLinks = 0,
  });

  int operationMode;
  final BleException? connectError;
  final bool bonded;

  /// Links whose discovery fails as if the camera dropped them (waking).
  int dropLinks;
  var scans = 0;
  final ops = <String>[];

  @override
  Future<BleAdapterState> adapterState() async => BleAdapterState.poweredOn;

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    scans++;
    return const Stream.empty();
  }

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    ops.add('connect $deviceId');
    final e = connectError;
    if (e != null) throw e;
    return _Link(this, deviceId);
  }

  @override
  Future<void> close() async {}
}

final class _Link implements BleConnection {
  _Link(this.camera, this.deviceId);

  final BondedCamera camera;
  @override
  final String deviceId;
  final _drop = Completer<BleDisconnect>();

  @override
  int? get maximumWriteLength => null;

  @override
  Future<BleDisconnect> get disconnected => _drop.future;

  @override
  Future<void> disconnect() async {
    camera.ops.add('disconnect');
    if (!_drop.isCompleted) {
      _drop.complete(const BleDisconnect(requested: true));
    }
  }

  @override
  Future<List<BleServiceInfo>> discover() async {
    if (camera.dropLinks > 0) {
      camera.dropLinks--;
      camera.ops.add('dropped');
      throw const BleException(BleErrorCode.notFound, 'Unknown deviceId');
    }
    final byService = <String, List<BleCharacteristicInfo>>{};
    for (final c in GrBleCatalog.all) {
      (byService[c.service.uuid] ??= []).add(
        BleCharacteristicInfo(uuid: c.uuid, properties: c.properties),
      );
    }
    return [
      for (final e in byService.entries)
        BleServiceInfo(uuid: e.key, characteristics: e.value),
    ];
  }

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {}

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    final uuid = canonicalUuid(characteristicUuid);
    if (uuid == GrBleCatalog.operationMode.uuid) {
      camera.ops.add('read mode');
      return Uint8List.fromList([camera.operationMode]);
    }
    if (uuid == GrBleCatalog.serialNumber.uuid) camera.ops.add('read serial');
    if (!camera.bonded) {
      throw const BleException(
        BleErrorCode.unauthorized,
        'Authentication is insufficient.',
      );
    }
    final values = {
      GrBleCatalog.serialNumber.uuid: '1234567',
      GrBleCatalog.modelName.uuid: 'RICOH GR IV HDF',
      GrBleCatalog.ssid.uuid: 'GR_H0053A8',
      GrBleCatalog.passphrase.uuid: 'abcdefgh',
    };
    return Uint8List.fromList(utf8.encode(values[uuid] ?? '1'));
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    if (canonicalUuid(characteristicUuid) == GrBleCatalog.operationMode.uuid) {
      camera.ops.add('write mode ${value.single}');
      camera.operationMode = value.single;
    }
    if (canonicalUuid(characteristicUuid) == GrBleCatalog.networkType.uuid) {
      camera.ops.add('write wlan ${value.single}');
    }
    if (canonicalUuid(characteristicUuid) == GrBleCatalog.cameraPower.uuid) {
      camera.ops.add('write power ${value.single}');
    }
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) =>
      const Stream.empty();
}

/// Ends every session at the join, after the BLE part under test.
final class FailingWifi implements WifiNetworkControl {
  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
  }) async => throw StateError('no Wi-Fi in this test');

  @override
  Future<String?> currentSsid() async => null;

  @override
  Future<void> leave() async {}
}

GrSession session(BondedCamera camera) => GrSession(
  transport: camera,
  wifi: FailingWifi(),
  options: const GrSessionOptions(
    joinTimeout: Duration(milliseconds: 10),
    joinRetryDelay: Duration(milliseconds: 1),
  ),
);

void main() {
  test('off camera: direct connect, operation mode 02 -> playback written '
      'before any encrypted read', () async {
    final camera = BondedCamera(operationMode: 2);
    final s = session(camera);
    final kinds = <String>[];
    s.events.listen((e) => kinds.add(e.kind));

    await expectLater(
      s.connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.phase,
          'phase',
          GrSessionPhase.joining,
        ),
      ),
    );
    expect(camera.scans, 0);
    expect(camera.ops.take(4), [
      'connect cam',
      'read mode',
      'write mode 1',
      'read serial',
    ]);
    expect(kinds, containsAllInOrder(['power.on', 'power.onWritten']));
  });

  test('camera already on: no operation mode write', () async {
    final camera = BondedCamera();
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(isA<GrSessionException>()),
    );
    expect(camera.ops.where((o) => o.startsWith('write mode')), isEmpty);
  });

  test('powerOn false: an off camera is left off', () async {
    final camera = BondedCamera(operationMode: 2);
    await expectLater(
      session(camera).connect(deviceId: 'cam', powerOn: false),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.needsPairing,
          'needsPairing',
          isFalse,
        ),
      ),
    );
    expect(camera.ops.where((o) => o.startsWith('write mode')), isEmpty);
    expect(camera.ops.last, 'disconnect');
  });

  test('bond rejected at connect: needsPairing', () async {
    final camera = BondedCamera(
      connectError: const BleException(
        BleErrorCode.bondRejected,
        'Peer removed pairing information',
      ),
    );
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.needsPairing,
          'needsPairing',
          isTrue,
        ),
      ),
    );
  });

  test('encrypted read refused on a bonded link: needsPairing, and the '
      'link is disconnected', () async {
    final camera = BondedCamera(bonded: false);
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.needsPairing,
          'needsPairing',
          isTrue,
        ),
      ),
    );
    expect(camera.ops.last, 'disconnect');
  });

  test('close(powerOff) writes Camera Power 00 before disconnecting, '
      'without WLAN-off', () async {
    final camera = BondedCamera();
    final s = session(camera);
    await expectLater(
      s.connect(deviceId: 'cam'),
      throwsA(isA<GrSessionException>()),
    );
    await s.close(wlanOff: true, powerOff: true);
    expect(camera.ops.where((o) => o == 'write wlan 0'), isEmpty);
    expect(camera.ops.skipWhile((o) => !o.startsWith('write power')), [
      'write power 0',
      'disconnect',
    ]);
  });

  test('first link drops while the off camera wakes: reconnects and '
      'powers on, as GR WORLD', () async {
    final camera = BondedCamera(operationMode: 2, dropLinks: 1);
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.phase,
          'phase',
          GrSessionPhase.joining,
        ),
      ),
    );
    expect(camera.ops.take(5), [
      'connect cam',
      'dropped',
      'disconnect',
      'connect cam',
      'read mode',
    ]);
    expect(camera.ops, contains('write mode 1'));
  });

  test('gives up after three dropped links', () async {
    final camera = BondedCamera(dropLinks: 5);
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.phase,
          'phase',
          GrSessionPhase.bleConnecting,
        ),
      ),
    );
    expect(camera.ops.where((o) => o == 'connect cam'), hasLength(3));
  });
}
