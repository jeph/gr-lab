import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'rig.dart';

/// What live geotagging says it is doing, and when it runs at all.
void main() {
  testWidgets('it is off until the app turns it on: the phone is not asked '
      'for anything, and the camera only for its clock', (tester) async {
    final rig = await GeotagRig.start(tester);
    expect(rig.status, GeotagStatus.off);

    await rig.configure(live: false);
    await rig.emit(rig.fix());
    await rig.advance(const Duration(minutes: 5));

    expect(rig.status, GeotagStatus.off);
    expect(rig.notifications, 0);
    expect(rig.phone.locating, isFalse);
    expect(rig.phone.runHolds, isEmpty);
    expect(rig.phone.currentRequests, 0);
    // Clock sync, which does not depend on live geotagging.
    expect(rig.asked, everyElement('read date-time'));
    expect(rig.trace.where((e) => e.channel == TraceChannel.location), isEmpty);
    await rig.close();
  });

  const unusable = {
    GeotagStatus.permissionDenied: LocationAccess(
      permission: LocationPermission.denied,
      precise: true,
      serviceOn: true,
    ),
    GeotagStatus.locationOff: LocationAccess(
      permission: LocationPermission.whileInUse,
      precise: true,
      serviceOn: false,
    ),
    GeotagStatus.preciseNeeded: LocationAccess(
      permission: LocationPermission.whileInUse,
      precise: false,
      serviceOn: true,
    ),
  };
  for (final MapEntry(key: status, value: access) in unusable.entries) {
    testWidgets('${status.name}: it does not run until the phone may be '
        'located precisely', (tester) async {
      final rig = await GeotagRig.start(tester, access: access);
      await rig.configure();

      expect(rig.status, status);
      expect(rig.phone.locating, isFalse);
      expect(rig.phone.runHolds, isEmpty);
      rig.phone.currentFix = rig.fix();
      await rig.advance(
        const Duration(seconds: 200),
        step: const Duration(seconds: 1),
      );
      expect(rig.phone.currentRequests, 0);
      expect(rig.writes, isEmpty);

      // The user allows it: the platform reports the new access.
      rig.phone.setAccess(FakePhoneLocation.whileInUse);
      await rig.advance(const Duration(seconds: 1));
      expect(rig.status, GeotagStatus.waitingForLocation);
      expect(rig.phone.locating, isTrue);
      expect(rig.phone.runHeld, isTrue);
      await rig.emit(rig.fix());
      expect(rig.writes, hasLength(1));

      // And takes it away again.
      rig.phone.setAccess(access);
      await rig.advance(const Duration(seconds: 1));
      expect(rig.status, status);
      expect(rig.phone.locating, isFalse);
      expect(rig.phone.runHeld, isFalse);
      await rig.emit(rig.fix(north: 100));
      await rig.advance(const Duration(seconds: 10));
      expect(rig.writes, hasLength(1));
      await rig.close();
    });
  }

  testWidgets('no access at all reads as the permission being denied', (
    tester,
  ) async {
    final rig = await GeotagRig.start(tester, access: LocationAccess.none);
    await rig.configure();
    expect(rig.status, GeotagStatus.permissionDenied);
    await rig.close();
  });

  testWidgets('a camera without GPS Information is unsupported: nothing is '
      'located, held or written', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: const FakeCameraConfig(bonded: true, absent: {'gps'}),
    );
    await rig.configure(pending: true);

    expect(rig.status, GeotagStatus.unsupported);
    expect(rig.phone.locating, isFalse);
    expect(rig.phone.runHolds, isEmpty);
    await rig.emit(rig.fix());
    await rig.advance(const Duration(seconds: 30));
    expect(rig.asked.where((ask) => !ask.endsWith('date-time')), isEmpty);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.settingWritten, isEmpty);
    await rig.close();
  });

  testWidgets('the status follows the camera and the positions written, '
      'and every change is notified and traced', (tester) async {
    final rig = await GeotagRig.start(tester);
    expect(rig.notifications, 0);

    await rig.configure();
    expect(rig.statuses, [GeotagStatus.waitingForLocation]);

    await rig.emit(rig.fix());
    expect(rig.statuses, [
      GeotagStatus.waitingForLocation,
      GeotagStatus.sending,
    ]);

    // Another write changes when the last one was sent, not the status.
    final notified = rig.notifications;
    final sentAt = rig.geotagging.lastSentAt!;
    await rig.advance(const Duration(seconds: 6));
    await rig.emit(rig.fix(north: 100));
    expect(rig.geotagging.lastSentAt!.isAfter(sentAt), isTrue);
    expect(rig.notifications, notified + 1);
    expect(rig.statuses, hasLength(2));

    // It is sending while the camera holds the position: 600 s.
    final lastAt = rig.writes.last.receivedAt;
    await rig.advanceTo(
      lastAt.add(const Duration(seconds: 599)),
      step: const Duration(seconds: 1),
    );
    expect(rig.status, GeotagStatus.sending);
    await rig.advanceTo(lastAt.add(const Duration(seconds: 601)));
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.camera.location, isNull);

    rig.camera.poweredOn = false;
    await rig.until(
      () => rig.status == GeotagStatus.waitingForCamera,
      reason: 'the camera to be seen off',
    );
    await rig.configure(live: false);

    expect(rig.statuses, [
      GeotagStatus.waitingForLocation,
      GeotagStatus.sending,
      GeotagStatus.waitingForLocation,
      GeotagStatus.waitingForCamera,
      GeotagStatus.off,
    ]);
    expect(rig.decisions('geotag.status'), [
      {'from': 'off', 'to': 'waitingForLocation'},
      {'from': 'waitingForLocation', 'to': 'sending'},
      {'from': 'sending', 'to': 'waitingForLocation'},
      {'from': 'waitingForLocation', 'to': 'waitingForCamera'},
      {'from': 'waitingForCamera', 'to': 'off'},
    ]);
    await rig.close();
  });

  testWidgets('nothing is done or notified after the session closed', (
    tester,
  ) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    var notified = 0;
    final geotagging = rig.geotagging..addListener(() => notified++);
    final steps = rig.steps.length;
    await rig.close();
    final closedAt = rig.steps.length;
    expect(rig.steps.sublist(steps), ['geotag.run.release']);

    geotagging.configure(
      const GeotagSettings(live: false, syncClock: true),
      notice: (status) => throw StateError('no notice is asked for'),
      onStopped: () => throw StateError('no Stop is handed over'),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(notified, 0);
    expect(rig.steps, hasLength(closedAt));
    expect(geotagging.status, GeotagStatus.sending);
  });

  test('settings with the same values are equal', () {
    const settings = GeotagSettings(
      live: true,
      syncClock: false,
      storeLocationInfoPending: true,
    );
    expect(
      settings,
      const GeotagSettings(
        live: true,
        syncClock: false,
        storeLocationInfoPending: true,
      ),
    );
    expect(
      settings.hashCode,
      const GeotagSettings(
        live: true,
        syncClock: false,
        storeLocationInfoPending: true,
      ).hashCode,
    );
    expect(settings, isNot(const GeotagSettings(live: true, syncClock: false)));
    expect(
      settings,
      isNot(
        const GeotagSettings(
          live: false,
          syncClock: false,
          storeLocationInfoPending: true,
        ),
      ),
    );
    expect(
      settings,
      isNot(
        const GeotagSettings(
          live: true,
          syncClock: true,
          storeLocationInfoPending: true,
        ),
      ),
    );
  });
}
