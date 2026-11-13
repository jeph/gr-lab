import 'dart:async';

import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

LocationFix _fix([double latitude = 35]) => LocationFix(
  latitude: latitude,
  longitude: 139,
  accuracy: 8,
  time: DateTime.utc(2026, 11, 12, 1, 2, 3),
);

const _notice = LocationRunNotice(
  title: 'GR IV',
  text: 'Sending location',
  stopLabel: 'Stop',
  channel: 'Geotagging',
);

const _denied = LocationAccess(
  permission: LocationPermission.denied,
  precise: true,
  serviceOn: true,
);

/// Lets stream events reach their listeners.
Future<void> _delivered() => Future<void>.delayed(Duration.zero);

void main() {
  group('FakePhoneLocation', () {
    late FakePhoneLocation phone;

    setUp(() => phone = FakePhoneLocation());
    tearDown(() => phone.close());

    test('has the access it is given and reports every change', () async {
      expect(await phone.access(), FakePhoneLocation.whileInUse);
      final changes = <LocationAccess>[];
      final sub = phone.accessChanges.listen(changes.add);

      phone.setAccess(LocationAccess.none);
      await _delivered();
      expect(await phone.access(), LocationAccess.none);
      expect(phone.currentAccess, LocationAccess.none);
      // The app coming back on screen reports the access unchanged.
      phone.setAccess(LocationAccess.none);
      await _delivered();
      expect(changes, [LocationAccess.none, LocationAccess.none]);
      await sub.cancel();
    });

    test('a permission request is answered as scripted', () async {
      phone.setAccess(_denied);
      final changes = <LocationAccess>[];
      final sub = phone.accessChanges.listen(changes.add);

      // No prompt shown: the access stays as it is.
      expect(await phone.requestWhileInUse(), _denied);
      phone.whileInUseAnswer = FakePhoneLocation.whileInUse;
      expect(await phone.requestWhileInUse(), FakePhoneLocation.whileInUse);
      phone.alwaysAnswer = FakePhoneLocation.always;
      expect(await phone.requestAlways(), FakePhoneLocation.always);
      expect(await phone.access(), FakePhoneLocation.always);
      await _delivered();

      expect(phone.whileInUseRequests, 2);
      expect(phone.alwaysRequests, 1);
      expect(changes, [
        _denied,
        FakePhoneLocation.whileInUse,
        FakePhoneLocation.always,
      ]);
      await sub.cancel();
    });

    test('records the settings pages opened', () async {
      await phone.openSettings(LocationSettingsPage.phone);
      await phone.openSettings(LocationSettingsPage.app);
      expect(phone.settingsOpened, [
        LocationSettingsPage.phone,
        LocationSettingsPage.app,
      ]);
    });

    test('positions come only while the phone is being located', () async {
      expect(phone.locating, isFalse);
      phone.emitFix(_fix());

      final fixes = <LocationFix>[];
      final sub = phone.updates.listen(fixes.add);
      expect(phone.locating, isTrue);
      final first = _fix();
      phone.emitFix(first);
      await _delivered();
      expect(fixes, [first]);

      await sub.cancel();
      expect(phone.locating, isFalse);
      phone.emitFix(_fix(36));
      await _delivered();
      expect(fixes, [first]);
    });

    test('no position comes while access is missing', () async {
      final fixes = <LocationFix>[];
      final sub = phone.updates.listen(fixes.add);
      phone
        ..setAccess(_denied)
        ..emitFix(_fix())
        ..currentFix = _fix();
      await _delivered();
      expect(fixes, isEmpty);
      expect(
        await phone.current(timeout: const Duration(milliseconds: 5)),
        isNull,
      );
      await sub.cancel();
    });

    test('current answers with the scripted position, or runs out its '
        'timeout', () async {
      final watch = Stopwatch()..start();
      expect(
        await phone.current(timeout: const Duration(milliseconds: 30)),
        isNull,
      );
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(25));

      final fix = _fix();
      phone.currentFix = fix;
      expect(await phone.current(timeout: const Duration(seconds: 5)), fix);

      final other = _fix(36);
      Duration? asked;
      phone.onCurrent = (timeout) async {
        asked = timeout;
        return other;
      };
      expect(await phone.current(timeout: const Duration(seconds: 7)), other);
      expect(asked, const Duration(seconds: 7));
      expect(phone.currentRequests, 3);
    });

    test('closing answers a waiting current with null', () async {
      final waiting = phone.current(timeout: const Duration(minutes: 1));
      await phone.close();
      expect(await waiting, isNull);
    });

    test('a run is held, updated and released', () async {
      expect(phone.runHeld, isFalse);
      expect(phone.runNotice, isNull);
      expect(phone.runAwake, isNull);

      await phone.holdRun(_notice, awake: false);
      expect(phone.runHeld, isTrue);
      expect(phone.runNotice, same(_notice));
      expect(phone.runAwake, isFalse);

      const next = LocationRunNotice(
        title: 'GR IV',
        text: 'Waiting for the camera',
        stopLabel: 'Stop',
        channel: 'Geotagging',
      );
      await phone.holdRun(next, awake: true);
      expect(phone.runNotice, same(next));
      expect(phone.runAwake, isTrue);
      expect(phone.runHolds, [
        (notice: _notice, awake: false),
        (notice: next, awake: true),
      ]);

      await phone.releaseRun();
      expect(phone.runHeld, isFalse);
      expect(phone.runNotice, isNull);
      await phone.releaseRun();
      expect(phone.runReleases, 1, reason: 'nothing was held the second time');
    });

    test('a run is refused as scripted, and without access', () async {
      Matcher refusedAs(LocationRunRefusal refusal) => throwsA(
        isA<LocationRunException>().having(
          (e) => e.refusal,
          'refusal',
          refusal,
        ),
      );

      phone.runRefusal = LocationRunRefusal.background;
      await expectLater(
        phone.holdRun(_notice, awake: true),
        refusedAs(LocationRunRefusal.background),
      );
      expect(phone.runHeld, isFalse);
      expect(phone.runHolds, isEmpty);

      phone
        ..runRefusal = null
        ..setAccess(_denied);
      await expectLater(
        phone.holdRun(_notice, awake: true),
        refusedAs(LocationRunRefusal.noAccess),
      );

      phone.setAccess(FakePhoneLocation.whileInUse);
      await phone.holdRun(_notice, awake: true);
      expect(phone.runHeld, isTrue);
    });

    test('Stop takes the notice away and is reported once; the run stays '
        'held until it is released', () async {
      var stops = 0;
      final sub = phone.runStops.listen((_) => stops++);
      phone.pressStop();
      await _delivered();
      expect(stops, 0, reason: 'no run, no notice to press Stop on');

      await phone.holdRun(_notice, awake: true);
      var releasedHeld = true;
      phone
        ..onRunReleased = (() => releasedHeld = phone.runHeld)
        ..pressStop()
        ..pressStop();
      await _delivered();
      expect(stops, 1);
      expect(phone.runNotice, isNull);
      expect(phone.runHeld, isTrue);
      expect(phone.runReleases, 0, reason: 'the app did not release it');

      await phone.releaseRun();
      expect(phone.runHeld, isFalse);
      expect(phone.runReleases, 1);
      expect(releasedHeld, isFalse);
      await sub.cancel();
    });

    test('the history is recorded, announced and handed over once', () async {
      expect(phone.historyEnabled, isFalse);
      await phone.setHistory(enabled: true);
      expect(phone.historyEnabled, isTrue);

      var pending = 0;
      final sub = phone.historyPending.listen((_) => pending++);
      final a = _fix();
      final b = _fix(36);
      phone
        ..recordHistory(a)
        ..recordHistory(b);
      await _delivered();
      expect(pending, 2);
      expect(phone.pendingHistory, [a, b]);

      expect(await phone.takeHistory(), [a, b]);
      expect(await phone.takeHistory(), isEmpty);
      expect(phone.pendingHistory, isEmpty);
      await sub.cancel();
    });
  });
}
