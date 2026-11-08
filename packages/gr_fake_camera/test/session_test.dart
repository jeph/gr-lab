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

  Future<GrSession> connect({List<String>? kinds}) async {
    final s = session = sessionFor(camera);
    if (kinds != null) s.events.listen((e) => kinds.add(e.kind));
    await s.connect(deviceId: camera.config.deviceId);
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
    'from off: linked first, the Wi-Fi start wakes the camera, the link '
    'drops while it boots, it links again, joins and /v1/props verifies',
    () async {
      camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
      final kinds = <String>[];
      final s = await connect(kinds: kinds);

      expect(s.phase, GrSessionPhase.connected);
      expect(
        kinds,
        containsAllInOrder([
          'ble.connect',
          'ble.cameraOff',
          'bluetooth',
          'power.on',
          'power.relink',
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

  group('Bluetooth first', () {
    Future<GrSession> linkBluetooth(List<String> kinds) async {
      final s = session = sessionFor(camera);
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: camera.config.deviceId);
      await Future<void>.delayed(Duration.zero);
      return s;
    }

    test('an off camera is linked and left off until Wi-Fi starts, which '
        'wakes it, links again and joins', () async {
      camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
      final kinds = <String>[];
      final s = await linkBluetooth(kinds);
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(s.cameraOff, isTrue);
      expect(camera.poweredOn, isFalse);
      expect(camera.wlanOn, isFalse);

      await s.startWifi();
      await Future<void>.delayed(Duration.zero);
      expect(s.phase, GrSessionPhase.connected);
      expect(camera.poweredOn, isTrue);
      expect(camera.wifiJoined, isTrue);
      expect(
        kinds,
        containsAllInOrder([
          'bluetooth',
          'power.on',
          'power.relink',
          'ble.ready',
          'wlan.on',
          'connected',
        ]),
      );
      expect(kinds, isNot(contains('ble.lost')));
    });

    test('a camera that turns on and keeps the link: the Wi-Fi start '
        'carries on over it without waiting for a drop', () async {
      camera = await startCamera(
        fastConfig(poweredOn: false, bonded: true, wakeKeepsLink: true),
      );
      final kinds = <String>[];
      final s = await linkBluetooth(kinds);
      expect(s.cameraOff, isTrue);

      await s.startWifi();
      expect(s.phase, GrSessionPhase.connected);
      expect(camera.poweredOn, isTrue);
      expect(camera.wifiJoined, isTrue);
      expect(
        kinds,
        containsAllInOrder(['power.on', 'power.onLinked', 'wlan.on']),
      );
      expect(kinds, isNot(contains('power.relink')));
      expect(kinds.where((k) => k == 'ble.ready'), hasLength(1));
    });

    test('stopping Wi-Fi turns the camera Wi-Fi off and keeps Bluetooth; '
        'it can start again', () async {
      camera = await startCamera(fastConfig(bonded: true));
      final s = await linkBluetooth([]);
      await s.startWifi();
      expect(camera.wlanOn, isTrue);

      await s.stopWifi();
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(s.http, isNull);
      expect(s.ble, isNotNull);
      expect(camera.wlanOn, isFalse);
      expect(await camera.wifi.currentSsid(), isNull);

      await s.startWifi();
      expect(s.phase, GrSessionPhase.connected);
      expect(camera.wifiJoined, isTrue);
    });

    test('stopping Wi-Fi during the join ends the attempt and leaves the '
        'phone off the camera network', () async {
      camera = await startCamera(fastConfig(bonded: true, joinDelay: ms(500)));
      final s = await linkBluetooth([]);
      final ended = expectLater(
        s.startWifi(),
        throwsA(isA<GrSessionException>()),
      );
      await Future<void>.delayed(ms(200));
      await s.stopWifi();
      await ended;
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(s.http, isNull);
      expect(await camera.wifi.currentSsid(), isNull);
      expect(camera.wlanOn, isFalse);
    });
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
    camera = await startCamera(
      fastConfig(bonded: true, dropWifiAfter: ms(80), reportsWifiLoss: false),
    );
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
        'wifi.lost',
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

  test('the phone reporting the network gone counts as lost at once, '
      'long before liveness would', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final s = session = sessionFor(
      camera,
      options: const GrSessionOptions(
        livenessInterval: Duration(milliseconds: 20),
        livenessLossAfter: Duration(seconds: 30),
        wifiRecoveryDelays: [Duration(seconds: 30)],
      ),
    );
    await s.connect(deviceId: camera.config.deviceId);
    final lost = s.events.firstWhere((e) => e.kind == 'wifi.lost');
    camera.dropWifi();
    final e = await lost.timeout(const Duration(seconds: 2));
    expect(e.fields['reason'], 'network');
    expect(s.phase, GrSessionPhase.recovering);
  });

  test('checkWifi: true while the camera answers; once it does not, the '
      'link counts as lost', () async {
    camera = await startCamera(
      fastConfig(bonded: true, reportsWifiLoss: false),
    );
    final s = session = sessionFor(
      camera,
      options: const GrSessionOptions(
        verifyProbeTimeout: Duration(seconds: 1),
        livenessInterval: Duration(seconds: 30),
        livenessLossAfter: Duration(seconds: 30),
        wifiRecoveryDelays: [Duration(seconds: 30)],
      ),
    );
    await s.connect(deviceId: camera.config.deviceId);
    expect(await s.checkWifi(), isTrue);
    expect(s.phase, GrSessionPhase.connected);

    final lost = s.events.firstWhere((e) => e.kind == 'wifi.lost');
    camera.dropWifi();
    expect(await s.checkWifi(), isFalse);
    expect(
      (await lost.timeout(const Duration(seconds: 2))).fields['reason'],
      'check',
    );
    expect(s.phase, GrSessionPhase.recovering);
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
