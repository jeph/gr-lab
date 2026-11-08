import 'dart:async';

import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeGrCamera camera;
  GrSession? session;

  tearDown(() async {
    await session?.close();
    session = null;
    await camera.close();
  });

  Future<GrSession> connect({bool powerOn = true, List<String>? kinds}) async {
    final s = session = sessionFor(camera);
    if (kinds != null) s.events.listen((e) => kinds.add(e.kind));
    await s.connect(deviceId: camera.config.deviceId, powerOn: powerOn);
    // Session events are delivered asynchronously.
    await Future<void>.delayed(Duration.zero);
    return s;
  }

  test('pairing, then a session on the paired device id', () async {
    camera = await startCamera(
      fastConfig(executePairingOpen: true, autoConfirmPairing: ms(10)),
    );
    final pairing = await pairCamera(
      camera.transport,
      clientName: 'GR Lab Test',
      scanTimeout: ms(300),
    );
    await pairing.client.connection.disconnect();

    final s = session = sessionFor(camera);
    await s.connect(deviceId: pairing.camera.deviceId);
    expect(s.phase, GrSessionPhase.connected);
    expect(s.props!.serialNo, pairing.camera.serialNumber);
  });

  test(
    'from off: power-on write, the first link drops while the camera '
    'wakes, the retry connects, Wi-Fi joins and /v1/props verifies',
    () async {
      camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
      final kinds = <String>[];
      final s = await connect(kinds: kinds);

      expect(s.phase, GrSessionPhase.connected);
      expect(
        kinds,
        containsAllInOrder([
          'ble.connect',
          'power.on',
          'power.onWritten',
          'ble.connectRetry',
          'ble.ready',
          'wlan.on',
          'wifi.join',
          'wifi.joined',
          'verify.ok',
          'changes.open',
          'connected',
        ]),
      );
      expect(kinds.where((k) => k == 'power.on'), hasLength(1));
      expect(camera.poweredOn, isTrue);
      expect(camera.operationMode, BleOperationMode.playback);
      expect(camera.wlanOn, isTrue);
      expect(camera.wifiJoined, isTrue);
      expect(await camera.wifi.currentSsid(), camera.config.ssid);
      expect(s.props!.model, 'RICOH GR IV');
      expect(s.props!.ssid, camera.config.ssid);
      expect(s.identity!.serialNumber, '1234567');
      expect(s.credentials!.passphrase, camera.config.passphrase);
    },
  );

  test('powerOn false: an off camera stays off and the connect fails '
      'without needsPairing', () async {
    camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
    await expectLater(
      connect(powerOn: false),
      throwsA(
        isA<GrSessionException>()
            .having((e) => e.phase, 'phase', GrSessionPhase.bleConnecting)
            .having((e) => e.needsPairing, 'needsPairing', isFalse),
      ),
    );
    expect(camera.poweredOn, isFalse);
  });

  test('camera already on: no power-on write', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final kinds = <String>[];
    final s = await connect(kinds: kinds);
    expect(s.phase, GrSessionPhase.connected);
    expect(kinds, isNot(contains('power.on')));
    expect(kinds, isNot(contains('ble.connectRetry')));
  });

  test('without a bond the session reports needsPairing', () async {
    camera = await startCamera(fastConfig());
    await expectLater(
      connect(),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.needsPairing,
          'needsPairing',
          isTrue,
        ),
      ),
    );
  });

  test('forgotten on the camera: needsPairing on the next connect', () async {
    camera = await startCamera(fastConfig(bonded: true));
    camera.forgetPairing();
    await expectLater(
      connect(),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.needsPairing,
          'needsPairing',
          isTrue,
        ),
      ),
    );
  });

  test('change WebSocket delivers storage and battery changes', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final s = await connect();
    final changes = s.changes!;
    final added = changes.waitFor<GrStorageChange>(
      (e) => e.action == 'add',
      timeout: const Duration(seconds: 2),
    );
    final battery = changes.waitFor<GrBatteryChange>(
      (_) => true,
      timeout: const Duration(seconds: 2),
    );
    camera
      ..addPhoto(FakePhoto('101RICOH', 'R0000999.JPG', DateTime(2026, 11, 6)))
      ..battery = 40;

    final event = await added;
    expect(event, isNotNull);
    expect(event!.path, GrPhotoPath('101RICOH', 'R0000999.JPG'));
    expect(event.storage, GrStorageId.sd);
    expect(await battery, isNotNull);
    expect((await s.http!.props()).battery, 40);
  });

  test('dropWifiAfter: liveness reports the loss, then WLAN-on over BLE '
      'and a rejoin recover the session', () async {
    camera = await startCamera(fastConfig(bonded: true, dropWifiAfter: ms(80)));
    final kinds = <String>[];
    final recovered = Completer<void>();
    final s = session = sessionFor(camera);
    s.events.listen((e) {
      kinds.add(e.kind);
      if (e.kind == 'recovery.done' && !recovered.isCompleted) {
        recovered.complete();
      }
    });
    await s.connect(deviceId: camera.config.deviceId);

    await recovered.future.timeout(const Duration(seconds: 5));
    expect(
      kinds,
      containsAllInOrder([
        'connected',
        'liveness.lost',
        'recovery.start',
        'recovery.wlanOn',
        'wifi.join',
        'verify.ok',
        'recovery.done',
      ]),
    );
    expect(s.phase, GrSessionPhase.connected);
    expect(camera.wifiJoined, isTrue);
  });

  test('unrecoverable Wi-Fi loss ends the session in lost', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final s = await connect();
    final lost = s.events.firstWhere((e) => e.phase == GrSessionPhase.lost);
    camera.dropWifi(recoverable: false);
    await lost.timeout(const Duration(seconds: 5));
    expect(s.phase, GrSessionPhase.lost);
  });

  test('a BLE blip reconnects BLE without touching Wi-Fi', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final kinds = <String>[];
    final s = await connect(kinds: kinds);
    final restored = s.events.firstWhere((e) => e.kind == 'ble.restored');
    camera.dropBluetooth();
    await restored.timeout(const Duration(seconds: 2));
    expect(kinds, containsAllInOrder(['ble.lost', 'ble.reconnect']));
    expect(s.phase, GrSessionPhase.connected);
    expect(camera.wifiJoined, isTrue);
  });

  test(
    'close(powerOff) turns the camera off and its HTTP stops answering',
    () async {
      camera = await startCamera(fastConfig(bonded: true));
      final s = await connect();
      final http = camera.httpClient('192.168.0.1', null);
      addTearDown(() => http.close(force: true));
      await s.close(powerOff: true);
      session = null;
      await Future<void>.delayed(ms(20));
      expect(camera.poweredOn, isFalse);
      expect(camera.linkCount, 0);
      await expectLater(http.props(), throwsA(anything));
    },
  );

  test('out of range: BLE connect fails as unreachable', () async {
    camera = await startCamera(fastConfig(bonded: true, unreachable: true));
    await expectLater(
      connect(),
      throwsA(
        isA<GrSessionException>()
            .having((e) => e.phase, 'phase', GrSessionPhase.bleConnecting)
            .having((e) => e.needsPairing, 'needsPairing', isFalse),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));
}
