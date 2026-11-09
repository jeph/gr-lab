import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show BleOperationMode, GrBleCatalog, TraceDirection;

import 'rig.dart';

void main() {
  late ShootRig rig;

  tearDown(() => rig.close());

  test('wake turns an off camera on in shooting mode; watching reads the '
      'mode, shots left and battery; the shutter takes a picture', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    final remote = rig.remote;
    await remote.wake();
    expect(rig.camera.poweredOn, isTrue);
    expect(rig.camera.operationMode, BleOperationMode.capture);
    expect(rig.camera.wlanOn, isFalse, reason: 'the remote needs no Wi-Fi');
    expect(remote.linked, isTrue);

    remote.watching = true;
    await until(
      () => remote.shotsLeft == 1234 && remote.battery == 82,
      reason: 'readouts',
    );
    expect(remote.exposure!.mode.known, BleExposureMode.av);

    final before = rig.camera.photos.length;
    await remote.shutter();
    await until(
      () => rig.camera.photos.length == before + 1,
      reason: 'picture taken',
    );
    await until(() => remote.shotsLeft == 1233, reason: 'shots left after');
  });

  test('the readouts follow the camera only while watched', () async {
    rig = await ShootRig.start();
    final remote = rig.remote;
    await remote.wake();
    remote.watching = true;
    await until(
      () => remote.exposure != null && remote.battery == 82,
      reason: 'readouts',
    );
    rig.camera.setExposureMode(BleExposureMode.m);
    await until(
      () => remote.exposure!.mode.known == BleExposureMode.m,
      reason: 'mode dial notification',
    );
    remote.watching = false;
    rig.camera.battery = 40;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(remote.battery, 82);
    remote.watching = true;
    await until(() => remote.battery == 40, reason: 'read when watching');
  });

  test("a running self-timer is cancelled with GR WORLD's 1-byte write, "
      'without a picture', () async {
    rig = await ShootRig.start();
    final remote = rig.remote;
    await remote.wake();
    remote.watching = true;
    await until(() => remote.drive != null, reason: 'drive');
    await remote.setDriveMode(BleDriveMode.selfTimer10s);
    expect(rig.camera.driveMode, BleDriveMode.selfTimer10s);

    final before = rig.camera.photos.length;
    await remote.shutter();
    await until(() => remote.countdownEnds != null, reason: 'countdown');
    expect(remote.countdown, const Duration(seconds: 10));

    await remote.shutter();
    await until(() => remote.countdownEnds == null, reason: 'cancelled');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(rig.camera.photos, hasLength(before));
    final cancels = [
      for (final e in rig.trace)
        if (e.kind == 'transport.write' &&
            e.direction == TraceDirection.outbound &&
            '${e.fields['characteristic']}'.toUpperCase() ==
                GrBleCatalog.selfTimer.uuid.toUpperCase())
          e.bytes,
    ];
    expect(cancels, [
      [1],
    ]);
    expect(rig.events('shoot.remote.cancelSelfTimer'), hasLength(1));
  });

  test('the countdown length is the self-timer the drive mode has', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(bonded: true, selfTimerScale: 5),
    );
    final remote = rig.remote;
    await remote.wake();
    remote.watching = true;
    await until(() => remote.drive != null, reason: 'drive');
    await remote.setDriveMode(BleDriveMode.bracketSelfTimer2s);
    await remote.shutter();
    await until(() => remote.countdownEnds != null, reason: 'countdown');
    expect(remote.countdown, const Duration(seconds: 2));
    await remote.shutter();
    await until(() => remote.countdownEnds == null, reason: 'cancelled');
  });

  test('a drive mode shows at once', () async {
    rig = await ShootRig.start();
    final remote = rig.remote;
    await remote.wake();
    final set = remote.setDriveMode(BleDriveMode.continuous);
    expect(remote.drive!.known, BleDriveMode.continuous);
    await set;
    expect(rig.camera.driveMode, BleDriveMode.continuous);
  });

  test(
    'a camera switched off forgets the capture but keeps the readouts',
    () async {
      rig = await ShootRig.start();
      final remote = rig.remote;
      await remote.wake();
      remote.watching = true;
      await until(() => remote.drive != null, reason: 'drive');
      await remote.setDriveMode(BleDriveMode.selfTimer10s);
      await remote.shutter();
      await until(() => remote.countdownEnds != null, reason: 'countdown');
      remote
        ..watching = false
        ..cameraSwitchedOff();
      expect(remote.countdownEnds, isNull);
      expect(remote.countdown, isNull);
      expect(remote.capturing, isFalse);
      expect(remote.battery, 82);
    },
  );
}
