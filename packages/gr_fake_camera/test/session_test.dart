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

    test('leaving with powerOffIfWoken turns a camera the start woke back off; '
        'the link drop that follows is expected', () async {
      camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
      final events = <GrSessionEvent>[];
      final s = session = sessionFor(camera);
      s.events.listen(events.add);
      await s.connectBluetooth(deviceId: camera.config.deviceId);
      await s.startWifi();
      expect(s.wokeCamera, isTrue);

      final restored = s.events.firstWhere((e) => e.kind == 'ble.restored');
      await s.stopWifi(powerOffIfWoken: true);
      expect(s.wokeCamera, isFalse);
      expect(s.phase, GrSessionPhase.bluetooth);
      await restored.timeout(const Duration(seconds: 5));
      expect(camera.poweredOn, isFalse);
      expect(s.cameraOff, isTrue);
      final drop = events.lastWhere((e) => e.kind == 'ble.lost');
      expect(drop.fields['afterPowerOff'], isTrue);
      expect(events.map((e) => e.kind), contains('power.off'));
      expect(events.map((e) => e.kind), isNot(contains('wlan.off')));
    });

    test('a camera that was on is left on: leaving only turns its Wi-Fi '
        'off', () async {
      camera = await startCamera(fastConfig(bonded: true));
      final s = await linkBluetooth([]);
      await s.startWifi();
      expect(s.wokeCamera, isFalse);
      await s.stopWifi(powerOffIfWoken: true);
      expect(camera.poweredOn, isTrue);
      expect(camera.wlanOn, isFalse);
    });

    test('switched off while its Wi-Fi is in use, the camera is turned on '
        'again over Bluetooth and rejoined', () async {
      camera = await startCamera(fastConfig(bonded: true));
      final kinds = <String>[];
      final s = await linkBluetooth(kinds);
      await s.startWifi();
      expect(s.wokeCamera, isFalse);

      final recovered = s.events.firstWhere((e) => e.kind == 'recovery.done');
      camera.poweredOn = false;
      await recovered.timeout(const Duration(seconds: 5));
      expect(s.phase, GrSessionPhase.connected);
      expect(camera.poweredOn, isTrue);
      expect(camera.wifiJoined, isTrue);
      expect(s.wokeCamera, isTrue);
      expect(
        kinds,
        containsAllInOrder(['wifi.lost', 'recovery.start', 'power.on']),
      );
    });

    test('switched off with its Bluetooth too, recovery gives up once the '
        'link has not come back', () async {
      camera = await startCamera(fastConfig(bonded: true));
      final s = await linkBluetooth([]);
      await s.startWifi();

      final gaveUp = s.events.firstWhere((e) => e.kind == 'recovery.gaveUp');
      camera.powerOffFully();
      final e = await gaveUp.timeout(const Duration(seconds: 5));
      expect(e.fields['noBle'], isTrue);
      expect(s.phase, GrSessionPhase.lost);
      expect(camera.poweredOn, isFalse);
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

    group('wake for remote shooting', () {
      test('an off camera is woken in capture mode; the link drops while it '
          'boots and is linked again, and the shutter works', () async {
        camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
        final kinds = <String>[];
        final s = await linkBluetooth(kinds);

        await s.wake(BleOperationMode.capture);
        await Future<void>.delayed(Duration.zero);
        expect(s.phase, GrSessionPhase.bluetooth);
        expect(s.cameraOff, isFalse);
        expect(s.wokeCamera, isTrue);
        expect(camera.poweredOn, isTrue);
        expect(camera.operationMode, BleOperationMode.capture);
        expect(
          kinds,
          containsAllInOrder([
            'power.on',
            'power.relink',
            'ble.ready',
            'wake.done',
          ]),
        );
        expect(kinds, isNot(contains('ble.lost')));
        expect(kinds, isNot(contains('mode.set')));

        final before = camera.photos.length;
        await s.ble!.shutter();
        await until(() => camera.photos.length == before + 1);
      });

      test('a camera that keeps the link: power.onLinked, no relink', () async {
        camera = await startCamera(
          fastConfig(poweredOn: false, bonded: true, wakeKeepsLink: true),
        );
        final kinds = <String>[];
        final s = await linkBluetooth(kinds);
        await s.wake(BleOperationMode.capture);
        await Future<void>.delayed(Duration.zero);
        expect(camera.operationMode, BleOperationMode.capture);
        expect(kinds, containsAllInOrder(['power.on', 'power.onLinked']));
        expect(kinds, isNot(contains('power.relink')));
        expect(kinds.where((k) => k == 'ble.ready'), hasLength(1));
      });

      test('a camera that keeps the link and reports being on ends the wake '
          'long before wakeSettle', () async {
        camera = await startCamera(
          fastConfig(poweredOn: false, bonded: true, wakeKeepsLink: true),
        );
        final events = <GrSessionEvent>[];
        final s = session = sessionFor(
          camera,
          options: const GrSessionOptions(wakeSettle: Duration(seconds: 30)),
        );
        s.events.listen(events.add);
        await s.connectBluetooth(deviceId: camera.config.deviceId);

        await s
            .wake(BleOperationMode.capture)
            .timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        expect(s.cameraOff, isFalse);
        final linked = events.singleWhere((e) => e.kind == 'power.onLinked');
        expect(linked.fields['reportedOn'], isTrue);
      });

      test('a camera that is on in playback is switched to capture, and is '
          'not counted as woken', () async {
        camera = await startCamera(fastConfig(bonded: true));
        final kinds = <String>[];
        final s = await linkBluetooth(kinds);
        expect(camera.operationMode, BleOperationMode.playback);
        await s.wake(BleOperationMode.capture);
        await Future<void>.delayed(Duration.zero);
        expect(camera.operationMode, BleOperationMode.capture);
        expect(kinds, contains('mode.set'));
        expect(s.wokeCamera, isFalse);
        await s.powerOffIfWoken();
        expect(camera.poweredOn, isTrue);
      });

      test('powerOffIfWoken turns a woken camera off; the drop that follows '
          'is expected', () async {
        camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
        final events = <GrSessionEvent>[];
        final s = session = sessionFor(camera);
        s.events.listen(events.add);
        await s.connectBluetooth(deviceId: camera.config.deviceId);
        await s.wake(BleOperationMode.capture);

        final restored = s.events.firstWhere((e) => e.kind == 'ble.restored');
        await s.powerOffIfWoken();
        await restored.timeout(const Duration(seconds: 5));
        expect(camera.poweredOn, isFalse);
        expect(s.cameraOff, isTrue);
        expect(s.wokeCamera, isFalse);
        final drop = events.lastWhere((e) => e.kind == 'ble.lost');
        expect(drop.fields['afterPowerOff'], isTrue);
      });

      test('a camera the Wi-Fi start woke stays woken after stopWifi, and '
          'remote shooting can turn it off later', () async {
        camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
        final s = await linkBluetooth([]);
        await s.startWifi();
        await s.stopWifi();
        expect(s.wokeCamera, isTrue);
        expect(camera.poweredOn, isTrue);
        expect(camera.wlanOn, isFalse);

        await s.wake(BleOperationMode.capture);
        expect(camera.operationMode, BleOperationMode.capture);
        await s.powerOffIfWoken();
        expect(s.wokeCamera, isFalse);
        await until(() => !camera.poweredOn);
      });
    });

    group('turning the camera off', () {
      // Room for the guard and a link that drops before the reconnect
      // counts the camera as gone.
      const options = GrSessionOptions(
        bleConnectTimeout: Duration(seconds: 1),
        powerOffGuard: Duration(milliseconds: 150),
        bleReconnectDelays: [Duration(milliseconds: 20)],
        bleLostAfter: Duration(seconds: 3),
      );

      test('turningOff lasts until the camera is linked again in its off '
          'state: the guard is waited out, the first link to the off camera '
          'drops before it answers and is tried again, and no drop counts '
          'as a loss', () async {
        camera = await startCamera(
          fastConfig(bonded: true, firstOffLinkDrop: ms(80)),
        );
        final events = <GrSessionEvent>[];
        var reconnecting = false;
        final s = session = sessionFor(camera, options: options);
        s.events.listen((e) {
          events.add(e);
          reconnecting = reconnecting || s.bleReconnecting;
        });
        await s.connectBluetooth(deviceId: camera.config.deviceId);
        expect(s.turningOff, isFalse);

        final settled = s.events.firstWhere(
          (e) => e.kind == 'power.offSettled',
        );
        expect(await s.powerOff(), isTrue);
        expect(s.turningOff, isTrue);
        await settled.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);

        expect(s.turningOff, isFalse);
        expect(s.cameraOff, isTrue);
        expect(s.ble, isNotNull);
        expect(
          events.map((e) => e.kind),
          containsAllInOrder([
            'power.off',
            'ble.lost',
            'ble.powerOffGuard',
            'ble.connectRetry',
            'ble.ready',
            'power.offSettled',
          ]),
        );
        final drops = events.where((e) => e.kind == 'ble.lost');
        expect(drops.map((e) => e.fields['afterPowerOff']), everyElement(true));
        expect(reconnecting, isFalse);
      });

      test('a camera that is on again when it is linked keeps turningOff '
          'until the time for it runs out; its link dropping meanwhile is '
          'no loss either', () async {
        camera = await startCamera(fastConfig(bonded: true));
        final s = session = sessionFor(
          camera,
          options: const GrSessionOptions(
            bleConnectTimeout: Duration(seconds: 1),
            powerOffGuard: Duration(milliseconds: 150),
            bleReconnectDelays: [Duration(milliseconds: 20)],
            bleLostAfter: Duration(milliseconds: 600),
          ),
        );
        await s.connectBluetooth(deviceId: camera.config.deviceId);

        final lost = s.events.firstWhere((e) => e.kind == 'ble.lost');
        final restored = s.events.firstWhere((e) => e.kind == 'ble.restored');
        final unsettled = s.events.firstWhere(
          (e) => e.kind == 'power.offUnsettled',
        );
        expect(await s.powerOff(), isTrue);
        await lost.timeout(const Duration(seconds: 5));
        // Switched back on at the camera before the session links again.
        camera.poweredOn = true;
        await restored.timeout(const Duration(seconds: 5));
        expect(s.cameraOff, isFalse);
        expect(s.turningOff, isTrue);

        final again = s.events.firstWhere((e) => e.kind == 'ble.lost');
        final back = s.events.firstWhere((e) => e.kind == 'ble.restored');
        camera.dropBluetooth();
        final drop = await again.timeout(const Duration(seconds: 5));
        expect(drop.fields['afterPowerOff'], isTrue);
        expect(s.bleReconnecting, isFalse);
        await back.timeout(const Duration(seconds: 5));

        final event = await unsettled.timeout(const Duration(seconds: 5));
        expect(event.fields, {'linked': true, 'cameraOff': false});
        expect(s.turningOff, isFalse);
      });

      test('turning the camera on again ends turningOff', () async {
        camera = await startCamera(fastConfig(bonded: true));
        final s = session = sessionFor(camera, options: options);
        await s.connectBluetooth(deviceId: camera.config.deviceId);
        expect(await s.powerOff(), isTrue);
        expect(s.turningOff, isTrue);

        await until(() => s.ble == null);
        expect(s.turningOff, isTrue);
        final waking = s.powerOn();
        expect(s.turningOff, isFalse);
        await waking.timeout(const Duration(seconds: 5));
        expect(camera.poweredOn, isTrue);
      });

      test('a link to an off camera that drops is linked again without '
          'counting as a loss; one to a camera that is on counts', () async {
        camera = await startCamera(fastConfig(poweredOn: false, bonded: true));
        final events = <GrSessionEvent>[];
        final s = session = sessionFor(camera, options: options);
        s.events.listen(events.add);
        await s.connectBluetooth(deviceId: camera.config.deviceId);
        expect(s.cameraOff, isTrue);

        var restored = s.events.firstWhere((e) => e.kind == 'ble.restored');
        camera.dropBluetooth();
        await until(() => s.ble == null);
        expect(s.bleReconnecting, isFalse);
        await restored.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        final off = events.lastWhere((e) => e.kind == 'ble.lost');
        expect(off.fields['cameraOff'], isTrue);
        expect(off.fields, isNot(contains('afterPowerOff')));

        await s.powerOn();
        restored = s.events.firstWhere((e) => e.kind == 'ble.restored');
        camera.dropBluetooth();
        await until(() => s.ble == null);
        expect(s.bleReconnecting, isTrue);
        await restored.timeout(const Duration(seconds: 5));
        expect(s.bleReconnecting, isFalse);
      });
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
    camera = await startCamera(fastConfig(bonded: true))
      ..forgetPairing();
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

  test('closing the session turns the camera Wi-Fi off and leaves the camera '
      'on', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final s = await connect();
    expect(camera.wlanOn, isTrue);
    await s.close();
    expect(camera.wlanOn, isFalse);
    expect(camera.poweredOn, isTrue);
    expect(await camera.wifi.currentSsid(), isNull);
  });

  test('liveness probes /v1/ping and leaves /v1/props alone until the camera '
      'announces a battery or storage change', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final s = await connect();
    final reads = <GrProps>[];
    s.propsUpdates.listen(reads.add);
    final polls = await s.liveness!.polls.take(3).toList();
    expect(polls.map((p) => (p.ok, p.props)), everyElement((true, null)));
    expect(reads, isEmpty);

    camera.battery = 40;
    await until(() => reads.isNotEmpty);
    expect(reads.last.battery, 40);

    final before = reads.length;
    camera.addPhoto(
      FakePhoto('101RICOH', 'R0000999.JPG', DateTime(2026, 11, 6)),
    );
    await until(() => reads.length > before);
  });

  test('a camera that refuses /v1/ping is probed with /v1/props', () async {
    camera = await startCamera(fastConfig(bonded: true, answersPing: false));
    final s = await connect();
    final polls = await s.liveness!.polls.take(3).toList();
    expect(polls.map((p) => p.ok), everyElement(isTrue));
    expect(
      polls.map((p) => p.props?.serialNo),
      everyElement(camera.config.serial),
    );
    expect(s.phase, GrSessionPhase.connected);
  });

  test('a battery change after a Wi-Fi recovery is read, though a /v1/props '
      'read from before the loss is still unanswered', () async {
    camera = await startCamera(fastConfig(bonded: true));
    final s = await connect();
    final reads = <GrProps>[];
    s.propsUpdates.listen(reads.add);

    // The camera goes quiet on the read for this change, then its Wi-Fi
    // drops.
    final unanswered = camera.propsGate = Completer<void>();
    camera.battery = 40;
    await Future<void>.delayed(ms(100));
    camera.propsGate = null;
    final recovered = s.events.firstWhere((e) => e.kind == 'recovery.done');
    camera.dropWifi();
    await recovered.timeout(const Duration(seconds: 5));
    expect(reads.map((p) => p.battery), isNot(contains(55)));

    camera.battery = 55;
    await until(() => reads.any((p) => p.battery == 55));
    unanswered.complete();
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

  test(
    'a change made from another zone, as a widget test makes it in fake '
    "time, is sent without the camera's sockets entering that zone",
    () async {
      camera = await startCamera(fastConfig(bonded: true));
      final s = await connect();
      final changes = s.changes!;
      Future<GrBatteryChange?> batteryChange() =>
          changes.waitFor<GrBatteryChange>(
            (_) => true,
            timeout: const Duration(seconds: 2),
          );

      var entered = 0;
      R count<R>(R Function() body) {
        entered++;
        return body();
      }

      final callers = Zone.current.fork(
        specification: ZoneSpecification(
          run: <R>(_, parent, zone, f) => count(() => parent.run(zone, f)),
          runUnary: <R, T>(_, parent, zone, f, arg) =>
              count(() => parent.runUnary(zone, f, arg)),
          runBinary: <R, T1, T2>(_, parent, zone, f, a, b) =>
              count(() => parent.runBinary(zone, f, a, b)),
        ),
      );
      final first = batteryChange();
      callers.run(() => camera.battery = 40);
      expect(await first, isNotNull);

      entered = 0;
      final second = batteryChange();
      camera.battery = 30;
      expect(await second, isNotNull);
      await camera.close();
      expect(entered, 0);
    },
  );

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
