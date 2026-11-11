import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';

import 'shoot/rig.dart';

void main() {
  late ShootRig rig;

  tearDown(() => rig.close());

  test('battery and storages follow Bluetooth for the whole session, '
      'without the remote watching', () async {
    rig = await ShootRig.start();
    final status = rig.session.status;
    expect(rig.remote.watching, isFalse);
    await until(
      () => status.battery == 82 && status.storages.length == 2,
      reason: 'first readings',
    );
    // Both storages in the camera's order, each with its own count and
    // neither marked as the one pictures go to.
    expect(
      [
        for (final s in status.storages)
          (s.kind, s.remainingPictures, s.active),
      ],
      [
        (CameraStorageKind.internal, 500, null),
        (CameraStorageKind.sd1, 1234, null),
      ],
    );

    rig.camera.battery = 40;
    await until(() => status.battery == 40, reason: 'battery notification');
  });

  test('with Bluetooth down, a Wi-Fi reading keeps the battery '
      'current', () async {
    rig = await ShootRig.start(wifi: true);
    final status = rig.session.status;
    await until(() => status.battery == 82, reason: 'first reading');

    rig.camera
      ..adapterState = BleAdapterState.poweredOff
      ..dropBluetooth();
    await until(() => !rig.session.bleLinked, reason: 'Bluetooth down');
    rig.camera.battery = 40;
    expect(await rig.session.checkWifi(), isTrue);

    await until(() => status.battery == 40, reason: 'Wi-Fi reading');
    expect(rig.events('status.changed').last['source'], 'props');
  });
}
