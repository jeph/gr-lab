import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'rig.dart';

/// A paired GR IV that is on, with Store Location Info on and its clock
/// [offset] ahead of the phone's.
FakeCameraConfig _clockOff(Duration offset) => FakeCameraConfig(
  bonded: true,
  storeLocationInfo: true,
  clockOffset: offset,
);

/// The camera's clock (Date Time) is kept on the phone's time.
void main() {
  // How far the camera's clock is off, and whether that has it set. The
  // clock reads in whole seconds, so it reads up to a second behind what
  // it is: null where the reading may fall on either side of 2 s.
  const cases = <int, bool?>{
    -4000: true,
    -2600: true,
    -1400: null,
    -900: false,
    0: false,
    1500: false,
    2600: null,
    4000: true,
  };
  for (final MapEntry(key: offsetMs, value: expected) in cases.entries) {
    testWidgets('a clock $offsetMs ms off is set only when it reads 2 s or '
        'more off', (tester) async {
      final rig = await GeotagRig.start(
        tester,
        config: _clockOff(Duration(milliseconds: offsetMs)),
      );
      await rig.configure(live: false, syncClock: true);

      final check = rig.decisions('clock.offset').single;
      final read = check['offsetMs']! as int;
      expect(read, inInclusiveRange(offsetMs - 1100, offsetMs + 100));
      final written = read.abs() >= 2000;
      if (expected != null) expect(written, expected);
      expect(check['write'], written);
      expect(rig.asked, ['read date-time', if (written) 'write date-time']);
      expect(rig.camera.clockWrites, hasLength(written ? 1 : 0));
      expect(rig.steps.contains('clock.written'), written);
      if (written) {
        // The nearest whole second of the phone's time.
        expect(
          rig.camera.clockOffset.abs(),
          lessThanOrEqualTo(const Duration(milliseconds: 600)),
        );
      }
      await rig.close();
    });
  }

  testWidgets('the clock is checked before the first position is written; '
      'a position that comes meanwhile is written after it', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      // Slow enough for a position to arrive during the check.
      config: const FakeCameraConfig(
        bonded: true,
        storeLocationInfo: true,
        bleLatency: Duration(seconds: 1),
      ),
    );
    await rig.configure();
    await rig.until(() => rig.phone.locating, reason: 'the phone located');
    expect(rig.steps, isNot(contains('clock.offset')));

    await rig.emit(rig.fix());
    expect(rig.skips, ['clock']);
    expect(rig.writes, isEmpty);

    await rig.until(() => rig.writes.isNotEmpty, reason: 'the position');
    final steps = rig.steps;
    expect(
      steps.indexOf('clock.offset'),
      lessThan(steps.indexOf('geotag.write')),
    );
    expect(rig.asked, ['read geotag', 'read date-time', 'write gps']);
    expect(rig.decisions('geotag.written').single, {'reason': 'first'});
    await rig.close();
  });

  testWidgets('after a clock write a newly taken position is written 2 s '
      'later, once the camera has cleared its location', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: _clockOff(const Duration(hours: -1)),
    );
    rig.phone.onCurrent = (_) async => rig.fix(north: 3);
    await rig.configure();
    expect(rig.camera.clockWrites, hasLength(1));
    expect(rig.status, GeotagStatus.waitingForLocation);

    // A position that comes before the camera has settled is not written.
    await rig.emit(rig.fix());
    expect(rig.skips, ['clock']);
    expect(rig.writes, isEmpty);
    expect(rig.phone.currentRequests, 0);

    await rig.advance(const Duration(seconds: 2));
    expect(rig.phone.currentRequests, 1);
    final written = rig.writes.single;
    // The one taken after the wait, not the one that came during it.
    expect(written.latitude, closeTo(35 + 3 / metresPerDegree, 1e-9));
    expect(rig.decisions('geotag.written').single, {'reason': 'clock'});
    expect(
      written.receivedAt.difference(rig.camera.clockWrites.single),
      greaterThanOrEqualTo(const Duration(seconds: 2)),
    );

    // A GR IV clears its location 1 s after its clock changes: this one
    // came after that.
    await rig.advance(const Duration(seconds: 5));
    expect(rig.camera.location, isNotNull);
    expect(rig.status, GeotagStatus.sending);
    await rig.close();
  });

  testWidgets('while the camera stays on its clock is checked again every '
      '60 minutes', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure(live: false, syncClock: true);
    expect(rig.decisions('clock.offset'), hasLength(1));
    expect(rig.camera.clockWrites, isEmpty);

    // The clock drifts, or is set in the camera's menu.
    rig.camera.clockOffset = const Duration(seconds: 30);
    await rig.advance(
      const Duration(minutes: 58),
      step: const Duration(seconds: 5),
    );
    expect(rig.decisions('clock.offset'), hasLength(1));
    expect(rig.camera.clockWrites, isEmpty);

    await rig.advance(
      const Duration(minutes: 2),
      step: const Duration(seconds: 1),
    );
    expect(rig.decisions('clock.offset'), hasLength(2));
    expect(rig.camera.clockWrites, hasLength(1));
    expect(
      rig.camera.clockOffset.abs(),
      lessThanOrEqualTo(const Duration(milliseconds: 600)),
    );

    // And an hour after that check ended, when it is right.
    await rig.advance(
      const Duration(minutes: 61),
      step: const Duration(seconds: 5),
    );
    expect(rig.decisions('clock.offset'), hasLength(3));
    expect(rig.camera.clockWrites, hasLength(1));

    // Clock sync alone never locates the phone.
    expect(rig.phone.locating, isFalse);
    expect(rig.phone.currentRequests, 0);
    expect(rig.phone.runHolds, isEmpty);
    expect(rig.status, GeotagStatus.off);
    await rig.close();
  });

  testWidgets('a clock set at the hourly check has the position written '
      'again', (tester) async {
    final rig = await GeotagRig.start(tester);
    rig.phone.onCurrent = (_) async => rig.fix();
    await rig.configure();
    await rig.emit(rig.fix());
    expect(rig.status, GeotagStatus.sending);

    await rig.advance(
      const Duration(minutes: 58),
      step: const Duration(seconds: 5),
    );
    rig.camera.clockOffset = const Duration(seconds: 30);
    await rig.advance(
      const Duration(minutes: 3),
      step: const Duration(seconds: 1),
    );

    expect(rig.camera.clockWrites, hasLength(1));
    expect(rig.decisions('geotag.written').last, {'reason': 'clock'});
    expect(
      rig.writes.last.receivedAt.difference(rig.camera.clockWrites.single),
      greaterThanOrEqualTo(const Duration(seconds: 2)),
    );
    expect(rig.camera.location, isNotNull);
    expect(rig.status, GeotagStatus.sending);
    // Between the clock write and that position the camera held none.
    final statuses = rig.statuses;
    expect(statuses.sublist(statuses.length - 3), [
      GeotagStatus.sending,
      GeotagStatus.waitingForLocation,
      GeotagStatus.sending,
    ]);
    await rig.close();
  });

  testWidgets("live geotagging keeps the clock whatever the app's clock "
      'setting says; with neither, the clock is left alone', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: _clockOff(const Duration(minutes: 5)),
    );
    await rig.configure(live: false);
    await rig.advance(const Duration(seconds: 30));
    expect(rig.asked, isEmpty);
    expect(rig.camera.clockWrites, isEmpty);

    await rig.configure();
    expect(rig.camera.clockWrites, hasLength(1));
    await rig.close();
  });

  testWidgets('clock sync that is turned off stops checking', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure(live: false, syncClock: true);
    expect(rig.decisions('clock.offset'), hasLength(1));

    await rig.configure(live: false);
    rig.camera.clockOffset = const Duration(seconds: 30);
    await rig.advance(
      const Duration(minutes: 61),
      step: const Duration(seconds: 5),
    );
    expect(rig.decisions('clock.offset'), hasLength(1));
    expect(rig.camera.clockWrites, isEmpty);
    await rig.close();
  });

  testWidgets('the clock of a camera that is off is left alone until the '
      'camera is on', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: const FakeCameraConfig(
        bonded: true,
        poweredOn: false,
        clockOffset: Duration(minutes: 5),
      ),
    );
    await rig.configure(live: false, syncClock: true);
    await rig.advance(const Duration(seconds: 30));
    expect(rig.asked, isEmpty);

    rig.camera.powerOnKeepingLinks();
    await rig.advance(const Duration(seconds: 1));
    expect(rig.asked, ['read date-time', 'write date-time']);
    expect(rig.camera.clockWrites, hasLength(1));
    await rig.close();
  });

  testWidgets('a camera without Date Time is not asked for it', (tester) async {
    final rig = await GeotagRig.start(
      tester,
      config: const FakeCameraConfig(
        bonded: true,
        storeLocationInfo: true,
        absent: {'date-time'},
      ),
    );
    await rig.configure();
    expect(rig.steps, contains('clock.unsupported'));
    expect(rig.asked, ['read geotag']);

    // Positions are written all the same.
    await rig.emit(rig.fix());
    expect(rig.writes, hasLength(1));
    await rig.close();
  });
}
