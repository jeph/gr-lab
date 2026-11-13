import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'rig.dart';

/// The notice text and `awake` of every run hold the phone took, in order.
List<(String, bool)> _holds(GeotagRig rig) => [
  for (final hold in rig.phone.runHolds) (hold.notice.text, hold.awake),
];

/// The run that keeps live geotagging going with the app off screen
/// (`PhoneLocation.holdRun`).
void main() {
  testWidgets("the run is held with the status's notice, and keeps the "
      'processor on only while the camera is on', (tester) async {
    final rig = await GeotagRig.start(tester, config: cameraOff);
    await rig.configure();
    expect(rig.phone.runHeld, isTrue);
    expect(rig.phone.runAwake, isFalse);
    final notice = rig.phone.runNotice!;
    expect(notice.title, 'GR IV');
    expect(notice.text, 'waitingForCamera');
    expect(notice.stopLabel, 'Stop');
    expect(notice.channel, 'Geotagging');

    rig.camera.powerOnKeepingLinks();
    await rig.advance(const Duration(seconds: 1));
    expect(rig.phone.runAwake, isTrue);
    expect(rig.phone.runNotice!.text, 'waitingForLocation');

    await rig.emit(rig.fix());
    expect(rig.phone.runNotice!.text, 'sending');

    rig.camera.storeLocationInfo = false;
    await rig.advance(const Duration(seconds: 1));
    expect(rig.phone.runNotice!.text, 'offOnCamera');

    // Updated at each change of status, never let go of in between.
    expect(_holds(rig), [
      ('waitingForCamera', false),
      ('waitingForLocation', true),
      ('sending', true),
      ('offOnCamera', true),
    ]);
    expect(rig.phone.runReleases, 0);
    expect(rig.phone.runHeld, isTrue);
    await rig.close();
  });

  testWidgets('the run is released when live geotagging is turned off', (
    tester,
  ) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    expect(rig.phone.runHeld, isTrue);

    await rig.configure(live: false, pending: false);
    expect(rig.phone.runHeld, isFalse);
    expect(rig.phone.runReleases, 1);
    expect(rig.steps, contains('geotag.run.release'));
    await rig.close();
  });

  testWidgets('the run is released when the session closes', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    expect(rig.phone.runHeld, isTrue);
    expect(rig.phone.locating, isTrue);

    await rig.close();
    expect(rig.phone.runHeld, isFalse);
    expect(rig.phone.runReleases, 1);
    expect(rig.phone.locating, isFalse);
  });

  testWidgets('Stop on the notice ends it and tells the app: nothing is '
      'located or written until the app has turned the setting off and the '
      'user turns it on again', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    final holds = rig.phone.runHolds.length;
    var stops = 0;
    final stopped = rig.geotagging.stoppedByUser.listen((_) => stops++);

    rig.phone.pressStop();
    await rig.advance(const Duration(seconds: 1));
    expect(stops, 1);
    expect(rig.status, GeotagStatus.off);
    expect(rig.steps, contains('geotag.stopped'));
    expect(rig.phone.locating, isFalse);

    // Settings that still say on, as the app had them before it heard of
    // the Stop, start nothing.
    await rig.configure(syncClock: false);
    rig.phone.currentFix = rig.fix(north: 100);
    await rig.emit(rig.fix(north: 100));
    await rig.advance(
      const Duration(seconds: 200),
      step: const Duration(seconds: 1),
    );
    expect(rig.writes, hasLength(1));
    expect(rig.phone.currentRequests, 0);
    // The platform released the run itself; it is not taken again.
    expect(rig.phone.runHeld, isFalse);
    expect(rig.phone.runHolds, hasLength(holds));
    expect(rig.phone.runReleases, 0);
    expect(rig.status, GeotagStatus.off);

    // The app turns the setting off, which turns the camera's off too.
    await rig.configure(live: false, pending: false);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.status, GeotagStatus.off);
    expect(rig.phone.runHeld, isFalse);

    await rig.configure(pending: true);
    await rig.until(
      () => rig.status == GeotagStatus.waitingForLocation,
      reason: 'live geotagging to start again',
    );
    expect(rig.phone.runHeld, isTrue);
    await rig.advance(const Duration(seconds: 1));
    expect(rig.phone.locating, isTrue);
    await rig.emit(rig.fix(north: 100));
    expect(rig.writes, hasLength(2));
    expect(stops, 1);
    unawaited(stopped.cancel());
    await rig.close();
  });

  testWidgets('after Stop it stays off when the link comes back and when '
      'the camera is switched off and on again', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    rig.phone.pressStop();
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.off);

    rig.camera.dropBluetooth();
    await rig.until(() => rig.links == 2, reason: 'the link to come back');
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.off);

    rig.camera.poweredOn = false;
    await rig.until(() => rig.session.cameraOff, reason: 'the camera off');
    await rig.advance(const Duration(seconds: 5));
    rig.camera.poweredOn = true;
    await rig.until(() => !rig.session.cameraOff, reason: 'the camera on');
    await rig.advance(const Duration(seconds: 5));

    expect(rig.status, GeotagStatus.off);
    expect(rig.phone.runHeld, isFalse);
    expect(rig.phone.locating, isFalse);
    await rig.emit(rig.fix());
    expect(rig.writes, isEmpty);
    await rig.close();
  });

  testWidgets('a camera that is not on for 60 minutes: the run is released, '
      'and held again when the camera comes on', (tester) async {
    final rig = await GeotagRig.start(tester, config: cameraOff);
    await rig.configure();
    expect(rig.phone.runHeld, isTrue);

    await rig.advance(
      const Duration(minutes: 58),
      step: const Duration(seconds: 5),
    );
    expect(rig.phone.runHeld, isTrue);
    expect(rig.phone.runReleases, 0);

    await rig.advance(
      const Duration(minutes: 2),
      step: const Duration(seconds: 1),
    );
    expect(rig.steps, contains('geotag.waitedOut'));
    expect(rig.phone.runHeld, isFalse);
    expect(rig.phone.runReleases, 1);
    // The camera is still waited for: it is seen coming on all the same.
    expect(rig.status, GeotagStatus.waitingForCamera);

    rig.camera.powerOnKeepingLinks();
    await rig.until(
      () => rig.status == GeotagStatus.waitingForLocation,
      reason: 'live geotagging to start',
    );
    expect(rig.phone.runHeld, isTrue);
    expect(rig.phone.runAwake, isTrue);
    expect(rig.phone.locating, isTrue);
    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    await rig.close();
  });

  testWidgets('the 60 minutes start over each time the camera goes off', (
    tester,
  ) async {
    final rig = await GeotagRig.start(tester, config: cameraOff);
    await rig.configure();
    await rig.advance(
      const Duration(minutes: 50),
      step: const Duration(seconds: 5),
    );

    rig.camera.powerOnKeepingLinks();
    await rig.advance(const Duration(minutes: 1));
    expect(rig.status, GeotagStatus.waitingForLocation);
    rig.camera.poweredOn = false;
    await rig.until(
      () => rig.status == GeotagStatus.waitingForCamera,
      reason: 'the camera to be seen off',
    );

    await rig.advance(
      const Duration(minutes: 50),
      step: const Duration(seconds: 5),
    );
    expect(rig.phone.runHeld, isTrue);
    expect(rig.phone.runAwake, isFalse);
    expect(rig.phone.runReleases, 0);

    await rig.advance(
      const Duration(minutes: 11),
      step: const Duration(seconds: 5),
    );
    expect(rig.phone.runHeld, isFalse);
    expect(rig.phone.runReleases, 1);
    await rig.close();
  });

  testWidgets('a run the phone refuses from the background: the app is '
      'needed, until it is on screen again', (tester) async {
    final rig = await GeotagRig.start(tester, config: cameraOff);
    rig.phone.runRefusal = LocationRunRefusal.background;
    await rig.configure();
    // A camera that is off is waited for, with or without the run.
    expect(rig.status, GeotagStatus.waitingForCamera);
    expect(rig.phone.runHeld, isFalse);
    expect(rig.decisions('geotag.run.hold'), hasLength(1));

    rig.camera.powerOnKeepingLinks();
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.needsApp);
    expect(rig.decisions('geotag.run.refused').last, {'refusal': 'background'});
    expect(rig.phone.locating, isFalse);
    await rig.emit(rig.fix());
    await rig.advance(
      const Duration(seconds: 200),
      step: const Duration(seconds: 1),
    );
    expect(rig.writes, isEmpty);
    expect(rig.phone.currentRequests, 0);
    // Asked once when the camera came on, not again and again.
    expect(rig.decisions('geotag.run.hold'), hasLength(2));

    // The app comes on screen: the platform reports the access again.
    rig.phone
      ..runRefusal = null
      ..setAccess(FakePhoneLocation.whileInUse);
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.phone.runHeld, isTrue);
    expect(rig.phone.runAwake, isTrue);
    expect(rig.phone.locating, isTrue);
    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    await rig.close();
  });

  testWidgets('still refused when the access is reported again, the app is '
      'still needed', (tester) async {
    final rig = await GeotagRig.start(tester);
    rig.phone.runRefusal = LocationRunRefusal.background;
    await rig.configure();
    expect(rig.status, GeotagStatus.needsApp);

    rig.phone.setAccess(FakePhoneLocation.whileInUse);
    await rig.advance(const Duration(seconds: 1));
    expect(rig.status, GeotagStatus.needsApp);
    expect(rig.phone.locating, isFalse);
    expect(rig.decisions('geotag.run.hold'), hasLength(2));
    await rig.close();
  });

  for (final refusal in [
    LocationRunRefusal.unsupported,
    LocationRunRefusal.noAccess,
  ]) {
    testWidgets('a run the phone cannot hold (${refusal.name}) is asked for '
        'once; live geotagging goes on without it', (tester) async {
      final rig = await GeotagRig.start(tester);
      rig.phone.runRefusal = refusal;
      await rig.configure();
      expect(rig.status, GeotagStatus.waitingForLocation);
      expect(rig.phone.locating, isTrue);

      await rig.emit(rig.fix());
      expect(rig.writes, hasLength(1));
      expect(rig.status, GeotagStatus.sending);
      expect(rig.decisions('geotag.run.hold'), hasLength(1));
      expect(rig.decisions('geotag.run.refused'), [
        {'refusal': refusal.name},
      ]);

      // Asked for again when the phone reports its access.
      rig.phone
        ..runRefusal = null
        ..setAccess(FakePhoneLocation.whileInUse);
      await rig.advance(const Duration(seconds: 1));
      expect(rig.phone.runHeld, isTrue);
      expect(rig.phone.runNotice!.text, 'sending');
      await rig.close();
    });
  }
}
