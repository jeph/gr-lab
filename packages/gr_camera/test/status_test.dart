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
      () => status.battery == 82 && status.shotsLeft == 1234,
      reason: 'first readings',
    );
    expect(status.storages.map((s) => s.kind), contains(CameraStorageKind.sd1));

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
