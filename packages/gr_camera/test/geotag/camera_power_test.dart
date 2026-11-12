import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'rig.dart';

/// Live geotagging follows the camera's power, not the Bluetooth link.
void main() {
  testWidgets('while the camera is off nothing is located, read or written, '
      'whatever is wanted', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      // Off, linked, and with something to write: its setting is off.
      config: const FakeCameraConfig(
        bonded: true,
        poweredOn: false,
        clockOffset: Duration(hours: 1),
      ),
    );
    await rig.configure(pending: true);
    expect(rig.session.bleLinked, isTrue);
    expect(rig.session.cameraOff, isTrue);
    expect(rig.status, GeotagStatus.waitingForCamera);
    expect(rig.phone.locating, isFalse);

    rig.phone.currentFix = rig.fix();
    await rig.emit(rig.fix());
    await rig.advance(
      const Duration(minutes: 10),
      step: const Duration(seconds: 1),
    );

    expect(rig.asked, isEmpty);
    expect(rig.phone.locating, isFalse);
    expect(rig.phone.currentRequests, 0);
    expect(rig.fixes, isEmpty);
    expect(rig.writes, isEmpty);
    expect(rig.camera.refusedLocationWrites, 0);
    expect(rig.camera.clockWrites, isEmpty);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.settingWritten, isEmpty);
    expect(rig.status, GeotagStatus.waitingForCamera);
    await rig.close();
  });

  testWidgets('it starts when the camera comes on over the link it has', (
    tester,
  ) async {
    final rig = await GeotagRig.start(tester, config: cameraOff);
    await rig.configure();
    expect(rig.status, GeotagStatus.waitingForCamera);
    expect(rig.asked, isEmpty);

    // The link was there all along; only the camera's power changes.
    rig.camera.powerOnKeepingLinks();
    await rig.advance(const Duration(seconds: 1));

    expect(rig.sessionEvents, contains('ble.cameraOn'));
    expect(rig.links, 1);
    expect(rig.session.cameraOff, isFalse);
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.phone.locating, isTrue);
    expect(rig.asked, ['read geotag', 'read date-time']);
    expect(rig.steps, contains('geotag.cameraOn'));

    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    expect(rig.status, GeotagStatus.sending);
    await rig.close();
  });

  testWidgets('it starts when a camera that was let go of advertises that it '
      'is on, over a new link', (tester) async {
    final rig = await GeotagRig.start(tester, config: cameraOff);
    await rig.configure();
    // The link to the camera that is off drops: the session lets go.
    rig.camera.dropBluetooth();
    await rig.until(() => rig.session.parked, reason: 'the session to park');
    await rig.advance(const Duration(seconds: 30));
    expect(rig.session.parked, isTrue);
    expect(rig.links, 1);
    expect(rig.status, GeotagStatus.waitingForCamera);
    expect(rig.phone.locating, isFalse);
    expect(rig.asked, isEmpty);

    rig.camera.poweredOn = true;
    await rig.until(
      () => rig.status == GeotagStatus.waitingForLocation,
      reason: 'live geotagging to start',
    );
    // The setting is read and the clock checked before the phone is
    // located.
    await rig.advance(const Duration(seconds: 1));
    expect(rig.session.parked, isFalse);
    expect(rig.links, 2);
    expect(rig.sessionEvents, contains('ble.seenOn'));
    expect(rig.phone.locating, isTrue);

    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    expect(rig.status, GeotagStatus.sending);
    await rig.close();
  });

  testWidgets('configured before the first link, it starts when the link '
      'finds the camera on', (tester) async {
    final rig = await GeotagRig.start(tester, link: false);
    await rig.configure();
    expect(rig.status, GeotagStatus.waitingForCamera);
    expect(rig.phone.locating, isFalse);

    await rig.link();
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.phone.locating, isTrue);
    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    await rig.close();
  });

  testWidgets('a camera that turns off is no longer written to, and the '
      'phone no longer located', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    expect(rig.status, GeotagStatus.sending);
    expect(rig.phone.locating, isTrue);

    rig.camera.poweredOn = false;
    await rig.until(
      () => rig.status == GeotagStatus.waitingForCamera,
      reason: 'the camera to be seen off',
    );
    expect(rig.phone.locating, isFalse);
    expect(rig.steps, contains('geotag.cameraAway'));

    rig.phone.currentFix = rig.fix(north: 200);
    await rig.emit(rig.fix(north: 100));
    await rig.advance(
      const Duration(minutes: 10),
      step: const Duration(seconds: 1),
    );
    expect(rig.writes, hasLength(1));
    // The simulated camera counts what reaches it while it is off.
    expect(rig.camera.refusedLocationWrites, 0);
    expect(rig.gattWrites.where((key) => key == 'gps'), hasLength(1));
    expect(rig.phone.currentRequests, 0);
    expect(rig.phone.locating, isFalse);
    expect(rig.status, GeotagStatus.waitingForCamera);
    await rig.close();
  });

  testWidgets('a camera the session turned off is left alone too', (
    tester,
  ) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());

    await rig.wait(rig.session.powerOff());
    await rig.until(
      () => rig.status == GeotagStatus.waitingForCamera,
      reason: 'the camera to be seen off',
    );
    await rig.emit(rig.fix(north: 100));
    await rig.advance(
      const Duration(minutes: 5),
      step: const Duration(seconds: 1),
    );
    expect(rig.camera.poweredOn, isFalse);
    expect(rig.writes, hasLength(1));
    expect(rig.camera.refusedLocationWrites, 0);
    expect(rig.phone.locating, isFalse);
    expect(rig.phone.currentRequests, 0);
    await rig.close();
  });

  testWidgets('switched on again, the camera gets the next good position as '
      'the first, moved or not', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    final sentAt = rig.geotagging.lastSentAt;

    rig.camera.poweredOn = false;
    await rig.until(
      () => rig.status == GeotagStatus.waitingForCamera,
      reason: 'the camera to be seen off',
    );
    rig.camera.poweredOn = true;
    await rig.until(
      () => rig.status == GeotagStatus.waitingForLocation,
      reason: 'live geotagging to start again',
    );
    // The setting is read and the clock checked before the phone is
    // located.
    await rig.advance(const Duration(seconds: 1));
    // What was written before the camera went off does not count as
    // sending now, although it is under 600 s old.
    expect(rig.geotagging.lastSentAt, sentAt);
    // The setting is read and the clock checked on the new link too.
    expect(
      rig.asked.where((ask) => ask == 'read geotag').length,
      greaterThanOrEqualTo(2),
    );
    expect(
      rig.asked.where((ask) => ask == 'read date-time').length,
      greaterThanOrEqualTo(2),
    );

    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(2));
    expect(rig.decisions('geotag.written').last, {'reason': 'first'});
    expect(rig.status, GeotagStatus.sending);
    await rig.close();
  });

  testWidgets('a link that drops and comes back starts over: the setting is '
      'read, the clock checked and the next position written as the '
      'first', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    expect(rig.asked, ['read geotag', 'read date-time', 'write gps']);

    rig.camera.dropBluetooth();
    await rig.until(
      () => rig.status == GeotagStatus.waitingForCamera,
      reason: 'the link to be seen down',
    );
    expect(rig.phone.locating, isFalse);
    await rig.until(
      () => rig.status == GeotagStatus.waitingForLocation,
      reason: 'the link to come back',
    );
    // The setting is read and the clock checked before the phone is
    // located.
    await rig.advance(const Duration(seconds: 1));
    expect(rig.links, 2);
    expect(rig.asked, [
      'read geotag',
      'read date-time',
      'write gps',
      'read geotag',
      'read date-time',
    ]);

    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(2));
    expect(rig.decisions('geotag.written').last, {'reason': 'first'});
    await rig.close();
  });
}
