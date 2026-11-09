import 'dart:async';
import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:gr_protocol/src/wifi/network_control.dart';
import 'package:test/test.dart';

/// Connection whose reads stay pending until the test completes them, and
/// which records how many requests were in flight at once.
final class HeldConnection implements BleConnection {
  final pending = <Completer<Uint8List>>[];
  int started = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  String get deviceId => 'held';

  @override
  int? get maximumWriteLength => null;

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) {
    started++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final c = Completer<Uint8List>();
    pending.add(c);
    return c.future.whenComplete(() => inFlight--);
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) {
    started++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final c = Completer<Uint8List>();
    pending.add(c);
    return c.future.whenComplete(() => inFlight--);
  }

  @override
  Future<List<BleServiceInfo>> discover() async => const [];

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) =>
      const Stream.empty();

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {}

  @override
  Future<BleDisconnect> get disconnected => Completer<BleDisconnect>().future;

  @override
  Future<void> disconnect() async {}
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('readWifiCredentials security', () {
    test('absent characteristic: WPA2 assumed', () async {
      final c = await credentials(
        CredentialsConnection(absent: {GrBleCatalog.wlanSecurity.key}),
      );
      expect(c.wifiSecurity, WifiSecurity.wpa2);
      expect(c.securityAssumed, isTrue);
    });

    test('present WPA3 is reported as WPA3', () async {
      final c = await credentials(
        CredentialsConnection(security: [BleWlanSecurity.wpa3.wire]),
      );
      expect(c.wifiSecurity, WifiSecurity.wpa3);
      expect(c.securityAssumed, isFalse);
    });

    test('present but unreadable: unknown, not WPA2', () async {
      final c = await credentials(CredentialsConnection(failSecurity: true));
      expect(c.wifiSecurity, isNull);
      expect(c.securityAssumed, isFalse);
      expect(c.issues, contains(startsWith('wlan-security:')));
    });

    test('present but empty payload: unknown, not WPA2', () async {
      final c = await credentials(CredentialsConnection(security: const []));
      expect(c.wifiSecurity, isNull);
      expect(c.securityAssumed, isFalse);
    });

    test('present with an undocumented value: unknown', () async {
      final c = await credentials(CredentialsConnection(security: const [9]));
      expect(c.wifiSecurity, isNull);
      expect(c.securityAssumed, isFalse);
    });
  });

  final service = GrBleCatalog.batteryLevel.service.uuid;
  final characteristic = GrBleCatalog.batteryLevel.uuid;

  test('one request in flight; a timed-out request keeps the queue', () async {
    final connection = HeldConnection();
    final client = GrBleClient(
      connection,
      operationTimeout: const Duration(milliseconds: 100),
    );

    final first = client.readUuid(service, characteristic);
    final second = client.readUuid(service, characteristic);
    await expectLater(
      first,
      throwsA(
        isA<BleException>().having((e) => e.code, 'code', BleErrorCode.timeout),
      ),
    );

    // The first platform request is still pending: the second must wait.
    await settle();
    expect(connection.started, 1);

    connection.pending.first.complete(Uint8List.fromList([50]));
    await settle();
    expect(connection.started, 2);

    connection.pending.last.complete(Uint8List.fromList([49]));
    expect(await second, [49]);
    expect(connection.maxInFlight, 1);
  });

  test(
    'a late failure of a timed-out request still releases the queue',
    () async {
      final connection = HeldConnection();
      final client = GrBleClient(
        connection,
        operationTimeout: const Duration(milliseconds: 100),
      );

      final first = client.writeUuid(service, characteristic, Uint8List(1));
      final second = client.readUuid(service, characteristic);
      await expectLater(first, throwsA(isA<BleException>()));

      connection.pending.first.completeError(
        const BleException(BleErrorCode.gatt, 'late failure'),
      );
      await settle();
      expect(connection.started, 2);
      connection.pending.last.complete(Uint8List.fromList([7]));
      expect(await second, [7]);
      expect(connection.maxInFlight, 1);
    },
  );
}

/// Camera whose discovery lists every catalog characteristic except
/// [absent], and whose security read returns [security] or fails.
final class CredentialsConnection implements BleConnection {
  new({this.absent = const {}, this.security, this.failSecurity = false});

  final Set<String> absent;
  final List<int>? security;
  final bool failSecurity;

  @override
  String get deviceId => 'credentials';

  @override
  int? get maximumWriteLength => null;

  @override
  Future<List<BleServiceInfo>> discover() async {
    final byService = <String, List<BleCharacteristicInfo>>{};
    for (final c in GrBleCatalog.all) {
      if (absent.contains(c.key)) continue;
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
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    if (canonicalUuid(characteristicUuid) == GrBleCatalog.wlanSecurity.uuid) {
      if (failSecurity) {
        throw const BleException(BleErrorCode.gatt, 'read failed');
      }
      return Uint8List.fromList(security ?? const []);
    }
    return Uint8List.fromList(const [0x41]);
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {}

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) =>
      const Stream.empty();

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {}

  @override
  Future<BleDisconnect> get disconnected => Completer<BleDisconnect>().future;

  @override
  Future<void> disconnect() async {}
}

Future<GrWifiCredentials> credentials(CredentialsConnection c) =>
    GrBleClient(c).readWifiCredentials();
