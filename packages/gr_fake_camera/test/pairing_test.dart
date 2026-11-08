import 'dart:async';

import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

Future<GrPairing> pair(
  FakeGrCamera camera, {
  void Function(GrPairingStage stage)? onStage,
  Duration confirmationTimeout = const Duration(seconds: 2),
}) => pairCamera(
  camera.transport,
  clientName: 'GR Lab Test',
  scanTimeout: ms(300),
  confirmationTimeout: confirmationTimeout,
  onStage: onStage,
);

Matcher failsWith(GrPairingFailure f) =>
    throwsA(isA<GrPairingException>().having((e) => e.failure, 'failure', f));

void main() {
  late FakeGrCamera camera;

  tearDown(() => camera.close());

  test('auto-confirm: bonds, reads identity, registers the client name; '
      'Execute Pairing closes', () async {
    camera = FakeGrCamera(
      config: fastConfig(executePairingOpen: true, autoConfirmPairing: ms(30)),
      media: syntheticMedia(),
    );
    final stages = <GrPairingStage>[];
    final result = await pair(camera, onStage: stages.add);

    expect(result.camera.deviceId, camera.config.deviceId);
    expect(result.camera.serialNumber, '1234567');
    expect(result.camera.model, GrModel.gr4);
    expect(result.camera.firmwareRevision, '1.20');
    expect(result.camera.bluetoothDeviceName, camera.config.bluetoothName);
    expect(stages, GrPairingStage.values);
    expect(camera.bonded, isTrue);
    expect(camera.registeredClientName, 'GR Lab Test');
    expect(camera.executePairingOpen, isFalse);
    expect(camera.linkCount, 1, reason: 'the pairing link stays open');
    await result.client.connection.disconnect();
    expect(camera.linkCount, 0);
  });

  test('manual confirm: nothing is bonded until OK is pressed', () async {
    camera = FakeGrCamera(
      config: fastConfig(executePairingOpen: true),
      media: syntheticMedia(),
    );
    final waiting = Completer<void>();
    final pairing = pair(
      camera,
      onStage: (s) {
        if (s == GrPairingStage.awaitingConfirmation) waiting.complete();
      },
    );
    await waiting.future;
    await Future<void>.delayed(ms(50));
    expect(camera.bonded, isFalse);
    expect(camera.registeredClientName, isNull);

    camera.confirmPairing();
    final result = await pairing;
    expect(result.camera.serialNumber, '1234567');
    expect(camera.bonded, isTrue);
    expect(camera.registeredClientName, 'GR Lab Test');
  });

  test('cancelled on the camera: notConfirmed, no bond', () async {
    camera = FakeGrCamera(
      config: fastConfig(executePairingOpen: true),
      media: syntheticMedia(),
    );
    final pairing = pair(
      camera,
      onStage: (s) {
        if (s == GrPairingStage.awaitingConfirmation) {
          Timer(ms(20), camera.rejectPairing);
        }
      },
    );
    await expectLater(pairing, failsWith(GrPairingFailure.notConfirmed));
    expect(camera.bonded, isFalse);
    expect(camera.registeredClientName, isNull);
    expect(camera.executePairingOpen, isFalse);
  });

  test(
    'never confirmed: notConfirmed after the confirmation timeout',
    () async {
      camera = FakeGrCamera(
        config: fastConfig(executePairingOpen: true),
        media: syntheticMedia(),
      );
      await expectLater(
        pair(camera, confirmationTimeout: ms(80)),
        failsWith(GrPairingFailure.notConfirmed),
      );
      expect(camera.bonded, isFalse);
    },
  );

  test(
    'refusePairing: notConfirmed even on Execute Pairing; link dropped',
    () async {
      camera = FakeGrCamera(
        config: fastConfig(
          executePairingOpen: true,
          autoConfirmPairing: ms(10),
          refusePairing: true,
        ),
        media: syntheticMedia(),
      );
      await expectLater(pair(camera), failsWith(GrPairingFailure.notConfirmed));
      expect(camera.bonded, isFalse);
      expect(camera.registeredClientName, isNull);
      expect(camera.linkCount, 0);
    },
  );

  test('Execute Pairing closed: notConfirmed, and it stays one-shot', () async {
    camera = FakeGrCamera(
      config: fastConfig(autoConfirmPairing: ms(10)),
      media: syntheticMedia(),
    );
    await expectLater(pair(camera), failsWith(GrPairingFailure.notConfirmed));
    expect(camera.bonded, isFalse);

    camera.openExecutePairing();
    final first = await pair(camera);
    await first.client.connection.disconnect();
    expect(camera.bonded, isTrue);

    // A second request without reopening Execute Pairing is refused, and
    // the camera drops the entry it had (firmware-bonding.md §2).
    await expectLater(pair(camera), failsWith(GrPairingFailure.notConfirmed));
    expect(camera.bonded, isFalse);
  });

  test('camera off: cameraOff without connecting', () async {
    camera = FakeGrCamera(
      config: fastConfig(poweredOn: false, executePairingOpen: true),
      media: syntheticMedia(),
    );
    await expectLater(pair(camera), failsWith(GrPairingFailure.cameraOff));
    expect(camera.linkCount, 0);
  });

  test('out of range: notFound', () async {
    camera = FakeGrCamera(
      config: fastConfig(executePairingOpen: true, unreachable: true),
      media: syntheticMedia(),
    );
    await expectLater(pair(camera), failsWith(GrPairingFailure.notFound));
  });

  test('openExecutePairingOnScan (demo): an off camera is turned on and '
      'pairs', () async {
    camera = FakeGrCamera(
      config: fastConfig(
        poweredOn: false,
        openExecutePairingOnScan: true,
        autoConfirmPairing: ms(20),
      ),
      media: syntheticMedia(),
    );
    final result = await pair(camera);
    expect(camera.poweredOn, isTrue);
    expect(camera.bonded, isTrue);
    expect(result.camera.serialNumber, '1234567');
  });

  test('adverts decode as the GR model, serial and power state', () async {
    camera = FakeGrCamera(
      config: fastConfig(poweredOn: false),
      media: syntheticMedia(),
    );
    Future<GrAdvertisement> next() async =>
        GrAdvertisement(await camera.transport.scan().first);

    final off = await next();
    expect(off.model, GrModel.gr4);
    expect(off.serialText, '1234567');
    expect(off.powerOn, isFalse);
    expect(off.powerOnFromServices, isFalse);
    expect(off.ricoh!.issues, isEmpty);

    camera.poweredOn = true;
    final on = await next();
    expect(on.powerOn, isTrue);
    expect(on.powerOnFromServices, isTrue);
  });

  test('close() ends an active scan and stops advertising', () async {
    camera = FakeGrCamera(config: fastConfig(), media: syntheticMedia());
    final received = <BleAdvertisement>[];
    final done = Completer<void>();
    final sub = camera.transport.scan().listen(
      received.add,
      onDone: done.complete,
    );
    addTearDown(sub.cancel);
    await Future<void>.delayed(ms(30));
    expect(received, isNotEmpty);

    await camera.close();
    await done.future.timeout(const Duration(seconds: 1));
    final count = received.length;
    await Future<void>.delayed(ms(30));
    expect(received, hasLength(count));

    // A scan started after close ends at once without adverts.
    expect(await camera.transport.scan().toList(), isEmpty);
  });

  test('Bluetooth off: scan errors and connect throws poweredOff', () async {
    camera = FakeGrCamera(config: fastConfig(), media: syntheticMedia())
      ..adapterState = BleAdapterState.poweredOff;
    expect(await camera.transport.adapterState(), BleAdapterState.poweredOff);
    await expectLater(
      camera.transport.scan().first,
      throwsA(isA<BleException>()),
    );
    await expectLater(
      camera.transport.connect(camera.config.deviceId, timeout: ms(100)),
      throwsA(
        isA<BleException>().having(
          (e) => e.code,
          'code',
          BleErrorCode.poweredOff,
        ),
      ),
    );
  });
}
