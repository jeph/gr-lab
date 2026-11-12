import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';

import 'rig.dart';

/// When live geotagging writes a position to the camera, and when it does
/// not.
void main() {
  testWidgets('the first good position of a time on is written at once, with '
      'its fix time in UTC', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.geotagging.lastSentAt, isNull);
    expect(rig.writes, isEmpty);

    final fix = rig.fix(altitude: 40.5);
    final emittedAt = clock.now();
    await rig.emit(fix);

    final held = rig.camera.location!;
    expect(rig.writes, [held]);
    expect(held.latitude, fix.latitude);
    expect(held.longitude, fix.longitude);
    expect(held.altitude, 40.5);
    final time = fix.time.toUtc();
    expect(
      held.fixTime,
      DateTime.utc(
        time.year,
        time.month,
        time.day,
        time.hour,
        time.minute,
        time.second,
      ),
    );
    expect(rig.status, GeotagStatus.sending);
    expect(
      rig.geotagging.lastSentAt!.difference(emittedAt),
      lessThan(const Duration(milliseconds: 300)),
    );
    expect(rig.decisions('geotag.written'), [
      {'reason': 'first'},
    ]);
    await rig.close();
  });

  testWidgets('an unknown altitude is written as 0, and one outside ±9999 m '
      "as the camera's limit", (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();

    await rig.emit(rig.fix());
    await rig.advance(const Duration(seconds: 6));
    await rig.emit(rig.fix(north: 100, altitude: 12000));
    await rig.advance(const Duration(seconds: 6));
    await rig.emit(rig.fix(north: 200, altitude: -12000));

    expect([for (final write in rig.writes) write.altitude], [0, 9999, -9999]);
    expect(rig.camera.refusedLocationWrites, 0);
    await rig.close();
  });

  testWidgets('a position is written again only once the phone moved more '
      'than 5 m from the last one written', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix(accuracy: 3));
    await rig.advance(const Duration(seconds: 6));

    await rig.emit(rig.fix(north: 4, accuracy: 3));
    expect(rig.writes, hasLength(1));
    expect(rig.skips, ['notMoved']);

    await rig.emit(rig.fix(north: 6, accuracy: 3));
    expect(rig.writes, hasLength(2));
    expect(rig.decisions('geotag.written').last, {'reason': 'moved'});

    // Measured from the position written, not from the last one seen.
    await rig.advance(const Duration(seconds: 6));
    await rig.emit(rig.fix(north: 9, accuracy: 3));
    expect(rig.writes, hasLength(2));
    await rig.emit(rig.fix(north: 12, accuracy: 3));
    expect(rig.writes, hasLength(3));
    await rig.close();
  });

  testWidgets('a position less accurate than 5 m has to move by its own '
      'accuracy', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    await rig.advance(const Duration(seconds: 6));

    await rig.emit(rig.fix(north: 40, accuracy: 50));
    expect(rig.writes, hasLength(1));
    final skipped = rig.decisions('geotag.skipped').single;
    expect(skipped['reason'], 'notMoved');
    expect(skipped['movedMetres'], closeTo(40, 0.01));
    expect(skipped['neededMetres'], 50);

    await rig.emit(rig.fix(north: 60, accuracy: 50));
    expect(rig.writes, hasLength(2));
    await rig.close();
  });

  testWidgets('positions are written at least 5 s apart: the newest one, '
      'once the 5 s have passed', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    final firstAt = rig.writes.single.receivedAt;

    await rig.advance(const Duration(seconds: 1));
    await rig.emit(rig.fix(north: 100));
    await rig.emit(rig.fix(north: 200));
    await rig.advanceTo(firstAt.add(const Duration(milliseconds: 4800)));
    expect(rig.writes, hasLength(1));
    expect(rig.skips, ['tooSoon', 'tooSoon']);

    await rig.advanceTo(firstAt.add(const Duration(milliseconds: 5500)));
    expect(rig.writes, hasLength(2));
    expect(rig.writes.last.latitude, closeTo(35 + 200 / metresPerDegree, 1e-9));
    expect(
      rig.writes.last.receivedAt.difference(firstAt),
      greaterThan(const Duration(milliseconds: 4900)),
    );

    await rig.advance(const Duration(seconds: 6));
    expect(rig.writes, hasLength(2), reason: 'the replaced one is dropped');
    await rig.close();
  });

  testWidgets('after 180 s without a write a newly taken position is '
      'written, moved or not', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    final first = rig.writes.single;
    rig.phone.onCurrent = (_) async => rig.fix(north: 1);

    await rig.advanceTo(first.receivedAt.add(const Duration(seconds: 179)));
    expect(rig.writes, hasLength(1));
    expect(rig.phone.currentRequests, 0);

    await rig.advanceTo(first.receivedAt.add(const Duration(seconds: 181)));
    expect(rig.phone.currentRequests, 1);
    expect(rig.writes, hasLength(2));
    final second = rig.writes.last;
    expect(second.latitude, closeTo(35 + 1 / metresPerDegree, 1e-9));
    expect(
      second.fixTime.difference(first.fixTime),
      greaterThanOrEqualTo(const Duration(seconds: 179)),
      reason: 'the position taken now, not the one written before',
    );
    expect(rig.decisions('geotag.written').last, {'reason': 'keepAlive'});

    // Counted from the last write, each time.
    await rig.advanceTo(second.receivedAt.add(const Duration(seconds: 179)));
    expect(rig.writes, hasLength(2));
    await rig.advanceTo(second.receivedAt.add(const Duration(seconds: 181)));
    expect(rig.writes, hasLength(3));
    expect(rig.phone.currentRequests, 2);
    await rig.close();
  });

  testWidgets('a position that comes by itself after 180 s is written, moved '
      'or not', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    final firstAt = rig.writes.single.receivedAt;

    await rig.advanceTo(firstAt.add(const Duration(seconds: 170)));
    await rig.emit(rig.fix(north: 1));
    expect(rig.writes, hasLength(1));
    await rig.advanceTo(firstAt.add(const Duration(seconds: 200)));
    await rig.emit(rig.fix(north: 1));
    expect(rig.writes, hasLength(2));
    await rig.close();
  });

  testWidgets('a position written before is never sent again: with no new '
      "one the camera's runs out after 600 s", (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    final firstAt = rig.writes.single.receivedAt;

    // The phone has no new position: every request for one times out.
    await rig.advanceTo(firstAt.add(const Duration(seconds: 599)));
    expect(rig.phone.currentRequests, greaterThanOrEqualTo(2));
    expect(rig.skips, everyElement('noFix'));
    expect(rig.writes, hasLength(1));
    expect(rig.camera.location, isNotNull);
    expect(rig.status, GeotagStatus.sending);

    await rig.advanceTo(firstAt.add(const Duration(seconds: 601)));
    expect(rig.camera.location, isNull);
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.writes, hasLength(1));
    expect(rig.gattWrites.where((key) => key == 'gps'), hasLength(1));
    await rig.close();
  });

  testWidgets('a newly taken position has to pass the age and accuracy '
      'limits too', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();
    await rig.emit(rig.fix());
    final firstAt = rig.writes.single.receivedAt;

    rig.phone.onCurrent = (_) async => rig.fix(north: 50, accuracy: 500);
    await rig.advanceTo(firstAt.add(const Duration(seconds: 181)));
    expect(rig.phone.currentRequests, 1);
    expect(rig.writes, hasLength(1));
    expect(rig.skips, ['accuracy']);

    rig.phone.onCurrent = (_) async =>
        rig.fix(north: 50, age: const Duration(seconds: 90));
    await rig.advanceTo(firstAt.add(const Duration(seconds: 362)));
    expect(rig.phone.currentRequests, 2);
    expect(rig.writes, hasLength(1));
    expect(rig.skips, ['accuracy', 'age']);
    await rig.close();
  });

  testWidgets('a position older than 60 s or less accurate than 100 m is not '
      'written, not even as the first', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();

    await rig.emit(rig.fix(age: const Duration(seconds: 61)));
    await rig.emit(rig.fix(accuracy: 101));
    // A fix the phone gave no accuracy for.
    await rig.emit(rig.fix(accuracy: double.infinity));
    expect(rig.writes, isEmpty);
    expect(rig.skips, ['age', 'accuracy', 'accuracy']);
    expect(rig.status, GeotagStatus.waitingForLocation);
    expect(rig.geotagging.lastSentAt, isNull);

    await rig.emit(rig.fix(age: const Duration(seconds: 59), accuracy: 100));
    expect(rig.writes, hasLength(1));

    // The same after a write, however far the phone moved.
    await rig.advance(const Duration(seconds: 6));
    await rig.emit(rig.fix(north: 500, age: const Duration(seconds: 61)));
    await rig.emit(rig.fix(north: 500, accuracy: 150));
    expect(rig.writes, hasLength(1));
    expect(rig.skips, ['age', 'accuracy', 'accuracy', 'age', 'accuracy']);
    expect(rig.camera.refusedLocationWrites, 0);
    await rig.close();
  });

  testWidgets('every position taken for the camera reaches fixes, written or '
      'not', (tester) async {
    final rig = await GeotagRig.start(tester);
    await rig.configure();

    final written = rig.fix();
    await rig.emit(written);
    final notMoved = rig.fix(north: 1);
    await rig.emit(notMoved);
    final inaccurate = rig.fix(north: 300, accuracy: 400);
    await rig.emit(inaccurate);
    expect(rig.writes, hasLength(1));
    expect(rig.fixes, [written, notMoved, inaccurate]);

    // One the phone was asked for, too.
    final asked = rig.fix(north: 2);
    rig.phone.onCurrent = (_) async => asked;
    await rig.advanceTo(
      rig.writes.single.receivedAt.add(const Duration(seconds: 181)),
    );
    expect(rig.fixes, [written, notMoved, inaccurate, asked]);
    await rig.close();
  });
}
