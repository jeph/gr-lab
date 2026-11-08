import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:test/test.dart';

import 'wake_test.dart' show advert, ms;

/// A camera on Execute Pairing. Camera Information reads fail with
/// insufficient authentication until [BleConnection.pair] succeeds.
final class PairingCamera implements BleTransport {
  PairingCamera({
    this.power = 1,
    this.pairError,
    this.failDiscover = false,
    this.failRegistration = false,
  });

  final int power;
  final BleException? pairError;
  final bool failDiscover;
  final bool failRegistration;

  /// Every GATT/pairing operation in order.
  final ops = <String>[];
  var connects = 0;
  var bonded = false;
  final registered = <String>[];
  final connections = <PairingConnection>[];

  @override
  Future<BleAdapterState> adapterState() async => BleAdapterState.poweredOn;

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) =>
      Stream.value(advert('cam', serial: 1234567, power: power));

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    connects++;
    final c = PairingConnection(this, deviceId);
    connections.add(c);
    return c;
  }

  @override
  Future<void> close() async {}
}

final class PairingConnection implements BleConnection {
  PairingConnection(this.camera, this.deviceId);

  final PairingCamera camera;
  @override
  final String deviceId;
  var disconnects = 0;

  @override
  int? get maximumWriteLength => null;

  @override
  Future<BleDisconnect> get disconnected => Completer<BleDisconnect>().future;

  @override
  Future<void> disconnect() async => disconnects++;

  @override
  Future<List<BleServiceInfo>> discover() async {
    camera.ops.add('discover');
    if (camera.failDiscover) {
      throw const BleException(BleErrorCode.gatt, 'discovery failed');
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
  }) async {
    camera.ops.add('pair');
    final e = camera.pairError;
    if (e != null) throw e;
    camera.bonded = true;
  }

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    final uuid = canonicalUuid(characteristicUuid);
    final dis =
        uuid == GrBleCatalog.disModelNumber.uuid ||
        uuid == GrBleCatalog.disFirmwareRevision.uuid;
    camera.ops.add(dis ? 'read dis' : 'read');
    if (!dis && !camera.bonded) {
      throw const BleException(
        BleErrorCode.unauthorized,
        'Authentication is insufficient.',
      );
    }
    final values = {
      GrBleCatalog.serialNumber.uuid: '1234567',
      GrBleCatalog.modelName.uuid: 'RICOH GR IV HDF',
      GrBleCatalog.firmwareRevision.uuid: '1.20',
      GrBleCatalog.disModelNumber.uuid: 'RICOH GR IV HDF',
      GrBleCatalog.disFirmwareRevision.uuid: '1.20',
    };
    return Uint8List.fromList(utf8.encode(values[uuid] ?? 'x'));
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    if (canonicalUuid(characteristicUuid) !=
        GrBleCatalog.pairedDeviceName.uuid) {
      camera.ops.add('write');
      return;
    }
    camera.ops.add('register');
    if (camera.failRegistration) {
      throw const BleException(BleErrorCode.gatt, 'cannot set name');
    }
    camera.registered.add(utf8.decode(value));
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) =>
      const Stream.empty();
}

Future<GrPairing> pair(PairingCamera camera, {List<GrPairingStage>? stages}) =>
    pairCamera(
      camera,
      clientName: 'GR Lab Mac',
      scanTimeout: ms(200),
      onStage: stages?.add,
    );

Matcher failsWith(GrPairingFailure f) =>
    throwsA(isA<GrPairingException>().having((e) => e.failure, 'failure', f));

void main() {
  test('GR WORLD order on one link: DIS, pair, Camera Information, '
      'register last; link left open', () async {
    final camera = PairingCamera();
    final stages = <GrPairingStage>[];
    final result = await pair(camera, stages: stages);

    expect(result.camera.deviceId, 'cam');
    expect(result.camera.serialNumber, '1234567');
    expect(result.camera.model, GrModel.gr4Hdf);
    expect(camera.registered, ['GR Lab Mac']);
    expect(camera.connects, 1);
    expect(camera.connections.single.disconnects, 0);
    expect(
      identical(result.client.connection, camera.connections.single),
      isTrue,
    );
    expect(stages, [
      GrPairingStage.scanning,
      GrPairingStage.awaitingConfirmation,
      GrPairingStage.registering,
    ]);
    final firstPair = camera.ops.indexOf('pair');
    expect(camera.ops.sublist(0, firstPair), [
      'discover',
      'read dis',
      'read dis',
    ]);
    expect(camera.ops.where((o) => o == 'pair'), hasLength(1));
    expect(camera.ops.last, 'register');
  });

  test('pairing refused: one attempt, no reconnect, link dropped', () async {
    final camera = PairingCamera(
      pairError: const BleException(BleErrorCode.unauthorized, 'refused'),
    );
    await expectLater(pair(camera), failsWith(GrPairingFailure.notConfirmed));
    expect(camera.connects, 1);
    expect(camera.ops.where((o) => o == 'pair'), hasLength(1));
    expect(camera.ops, isNot(contains('register')));
    expect(camera.connections.single.disconnects, 1);
  });

  test('camera off: refused without connecting', () async {
    final camera = PairingCamera(power: 0);
    await expectLater(pair(camera), failsWith(GrPairingFailure.cameraOff));
    expect(camera.connects, 0);
  });

  test('discovery failure is connectFailed and drops the link', () async {
    final camera = PairingCamera(failDiscover: true);
    await expectLater(pair(camera), failsWith(GrPairingFailure.connectFailed));
    expect(camera.ops, isNot(contains('pair')));
    expect(camera.connections.single.disconnects, 1);
  });

  test('registration rejected after bonding: registrationFailed', () async {
    final camera = PairingCamera(failRegistration: true);
    await expectLater(
      pair(camera),
      failsWith(GrPairingFailure.registrationFailed),
    );
    expect(camera.connections.single.disconnects, 1);
  });
}
