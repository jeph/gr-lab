import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart' show GrBleClient;

import 'rig.dart';

/// A paired GR IV that is on, with Store Location Info off, as it ships.
const _settingOff = FakeCameraConfig(bonded: true);

List<Object?> _settingWrites(GeotagRig rig) => [
  for (final key in rig.gattWrites)
    if (key == 'geotag') key,
];

/// The camera's Store Location Info setting (GEO Tag): written when the
/// app has a value pending, followed otherwise.
void main() {
  testWidgets('a pending value is written as soon as the camera is on and '
      'linked, then reported', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    await rig.configure(pending: true);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.settingWritten, isEmpty);
    expect(rig.asked, isEmpty);

    rig.camera.powerOnKeepingLinks();
    await rig.advance(const Duration(seconds: 1));

    expect(rig.camera.storeLocationInfo, isTrue);
    expect(rig.settingWritten, [true]);
    // Before anything else is asked of the camera.
    expect(rig.asked, ['write geotag', 'read geotag', 'read date-time']);
    expect(rig.decisions('geotag.storeLocationInfo.write'), [
      {'value': true, 'why': 'pending'},
    ]);
    expect(rig.status, GeotagStatus.waitingForLocation);
    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    await rig.close();
  });

  testWidgets('a pending value is written once: while the app still passes '
      "it, the camera's own setting is followed", (tester) async {
    final rig = await GeotagRig.start(tester, config: _settingOff);
    await rig.configure(pending: true);
    expect(rig.settingWritten, [true]);
    expect(_settingWrites(rig), hasLength(1));

    // Turned off in the camera's menu before the app cleared its value.
    rig.camera.storeLocationInfo = false;
    await rig.advance(const Duration(seconds: 1));
    await rig.configure(pending: true);
    expect(rig.status, GeotagStatus.offOnCamera);

    // Not on the next link either.
    rig.camera.dropBluetooth();
    await rig.until(() => rig.links == 2, reason: 'the link to come back');
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.offOnCamera);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(_settingWrites(rig), hasLength(1));
    expect(rig.settingWritten, [true]);

    // A new value of the app's is written again.
    await rig.configure();
    await rig.configure(pending: true);
    expect(rig.camera.storeLocationInfo, isTrue);
    expect(rig.settingWritten, [true, true]);
    await rig.close();
  });

  testWidgets('turning live geotagging off writes the setting off, which '
      "clears the camera's location", (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    expect(rig.camera.location, isNotNull);

    await rig.configure(live: false, pending: false);

    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.camera.location, isNull);
    expect(rig.settingWritten, [false]);
    expect(rig.status, GeotagStatus.off);
    expect(rig.phone.locating, isFalse);
    await rig.emit(rig.fix(north: 100));
    expect(rig.writes, hasLength(1));
    expect(rig.camera.refusedLocationWrites, 0);
    await rig.close();
  });

  testWidgets('turned off without a pending value, live geotagging turns '
      'the setting off all the same', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());

    await rig.configure(live: false);

    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.camera.location, isNull);
    expect(rig.decisions('geotag.storeLocationInfo.write'), [
      {'value': false, 'why': 'liveOff'},
    ]);
    // Nothing the app persisted was written.
    expect(rig.settingWritten, isEmpty);
    await rig.close();
  });

  testWidgets('turned off while the camera is off, the setting is turned '
      'off when the camera is next on', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    rig.camera.poweredOn = false;
    await rig.until(
      () => rig.status == GeotagStatus.waitingForCamera,
      reason: 'the camera to be seen off',
    );

    await rig.configure(live: false);
    await rig.advance(const Duration(seconds: 30));
    expect(_settingWrites(rig), isEmpty);
    expect(rig.camera.storeLocationInfo, isTrue);

    // Inside its 600 s the camera still holds the position.
    rig.camera.poweredOn = true;
    await rig.until(
      () => !rig.camera.storeLocationInfo,
      reason: 'Store Location Info to be turned off',
    );
    expect(rig.camera.location, isNull);
    expect(_settingWrites(rig), isNotEmpty);
    expect(rig.status, GeotagStatus.off);
    await rig.close();
  });

  testWidgets('found off at the link, the setting is left as it is: the '
      'status says so and the phone is not located', (tester) async {
    final rig = await GeotagRig.start(tester, config: _settingOff);
    await rig.configure();

    expect(rig.status, GeotagStatus.offOnCamera);
    expect(rig.phone.locating, isFalse);
    await rig.emit(rig.fix());
    await rig.advance(
      const Duration(minutes: 5),
      step: const Duration(seconds: 1),
    );
    expect(rig.asked, ['read geotag', 'read date-time']);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.camera.refusedLocationWrites, 0);
    expect(rig.phone.currentRequests, 0);
    expect(rig.fixes, isEmpty);
    await rig.close();
  });

  testWidgets("turned off in the camera's menu: the phone is no longer "
      'located and the app does not turn it back on by itself', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    expect(rig.status, GeotagStatus.sending);

    rig.camera.storeLocationInfo = false;
    await rig.advance(const Duration(seconds: 1));

    expect(rig.status, GeotagStatus.offOnCamera);
    expect(rig.phone.locating, isFalse);
    expect(rig.decisions('geotag.storeLocationInfo').last, {
      'value': false,
      'source': 'notified',
    });
    await rig.emit(rig.fix(north: 100));
    await rig.advance(
      const Duration(minutes: 5),
      step: const Duration(seconds: 1),
    );
    expect(rig.writes, hasLength(1));
    expect(rig.camera.refusedLocationWrites, 0);
    expect(rig.phone.currentRequests, 0);
    expect(_settingWrites(rig), isEmpty);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.status, GeotagStatus.offOnCamera);
    await rig.close();
  });

  testWidgets('the user turns it on again in the app: the next good '
      'position is written as the first', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    rig.camera.storeLocationInfo = false;
    await rig.advance(const Duration(seconds: 10));
    expect(rig.status, GeotagStatus.offOnCamera);

    await rig.wait(rig.geotagging.turnOnStoreLocationInfo());

    expect(rig.camera.storeLocationInfo, isTrue);
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.phone.locating, isTrue);
    expect(rig.decisions('geotag.storeLocationInfo.write'), [
      {'value': true, 'why': 'user'},
    ]);
    // It was not a value the app had pending.
    expect(rig.settingWritten, isEmpty);

    // The camera cleared its location with the setting: not moved, and
    // written all the same.
    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(2));
    expect(rig.decisions('geotag.written').last, {'reason': 'first'});
    expect(rig.status, GeotagStatus.sending);
    await rig.close();
  });

  testWidgets("turned on again in the camera's menu, live geotagging goes "
      'on', (tester) async {
    final rig = await GeotagRig.start(tester, config: _settingOff);
    await rig.configure();
    expect(rig.status, GeotagStatus.offOnCamera);

    rig.camera.storeLocationInfo = true;
    await rig.advance(const Duration(seconds: 1));

    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.phone.locating, isTrue);
    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    expect(_settingWrites(rig), isEmpty);
    await rig.close();
  });

  testWidgets('Store Location Info cannot be turned on while the camera is '
      'off', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    await rig.configure();

    await expectLater(
      rig.wait(rig.geotagging.turnOnStoreLocationInfo()),
      throwsA(isA<BleException>()),
    );
    expect(rig.asked, isEmpty);
    expect(rig.camera.storeLocationInfo, isFalse);
    await rig.close();
  });

  testWidgets('a position the camera refuses has the setting read again: '
      'off, the status says so, and the link is kept', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    // Another phone turns the setting off: no notification says so.
    final other = GrBleClient(
      await rig.wait(
        rig.camera.transport.connect(
          rig.camera.config.deviceId,
          timeout: const Duration(seconds: 5),
        ),
      ),
    );
    await rig.wait(other.setGeoTag(enabled: false));
    expect(rig.status, GeotagStatus.waitingForLocation);
    final asked = rig.asked.length;

    await rig.emit(rig.fix());

    expect(rig.camera.refusedLocationWrites, 1);
    expect(rig.writes, isEmpty);
    expect(rig.asked.sublist(asked), ['write gps', 'read geotag']);
    expect(rig.decisions('geotag.refused'), hasLength(1));
    expect(rig.status, GeotagStatus.offOnCamera);
    expect(rig.geotagging.lastSentAt, isNull);
    expect(rig.phone.locating, isFalse);
    // A refusal is the camera's answer, not a lost link.
    expect(rig.session.bleLinked, isTrue);
    expect(rig.links, 1);
    expect(rig.sessionEvents, isNot(contains('ble.lost')));
    await rig.close();
  });

  testWidgets('a position refused although the setting is on is not '
      'counted as written, and the next one is tried 5 s later', (
    tester,
  ) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    rig.camera.locationLocked = true;

    await rig.emit(rig.fix());
    expect(rig.camera.refusedLocationWrites, 1);
    expect(rig.decisions('geotag.refused'), hasLength(1));
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.geotagging.lastSentAt, isNull);
    expect(rig.phone.locating, isTrue);
    expect(rig.session.bleLinked, isTrue);
    expect(rig.sessionEvents, isNot(contains('ble.lost')));

    rig.camera.locationLocked = false;
    await rig.emit(rig.fix());
    expect(rig.skips, ['tooSoon']);
    expect(rig.writes, isEmpty);
    await rig.advance(const Duration(seconds: 5));
    expect(rig.writes, hasLength(1));
    expect(rig.decisions('geotag.written').single, {'reason': 'first'});
    expect(rig.status, GeotagStatus.sending);
    await rig.close();
  });

  testWidgets('a setting that cannot be read is read again every 10 s; '
      'until then the phone is not located', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: const FakeCameraConfig(
        bonded: true,
        storeLocationInfo: true,
        unreadable: {'geotag'},
      ),
    );
    await rig.configure();
    await rig.advance(const Duration(seconds: 24));

    expect(rig.asked.where((ask) => ask == 'read geotag'), hasLength(3));
    expect(rig.decisions('geotag.storeLocationInfo.readFailed'), hasLength(3));
    expect(rig.phone.locating, isFalse);
    expect(rig.writes, isEmpty);

    // What the camera notifies is followed all the same.
    rig.camera.storeLocationInfo = false;
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.offOnCamera);
    rig.camera.storeLocationInfo = true;
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.phone.locating, isTrue);
    await rig.close();
  });
}
