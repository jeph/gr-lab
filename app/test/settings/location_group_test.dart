import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/settings/settings_screen.dart';

import '../support/test_app.dart';

const _row = Key('setting-background-geotag');
const _switch = Key('setting-background-geotag-switch');
const _explain = Key('background-geotag-explain');
const _continue = Key('background-geotag-continue');
const _need = Key('setting-background-geotag-need');
const _openSettings = Key('setting-background-geotag-settings');
const _delete = Key('setting-location-history-delete');

const _offLine = 'Adds a location to photos when you download them';
const _onLine = 'On. This phone keeps a history of where it has been.';
const _needsAlways = 'Location has to be allowed all the time';

const _denied = LocationAccess(
  permission: LocationPermission.denied,
  precise: false,
  serviceOn: true,
);

/// Settings on a phone-sized screen, scrolled to the Location section.
Future<TestApp> _start(WidgetTester tester, FakePhoneLocation location) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(() => createTestApp(location: location)))!;
  await app.pumpWithin(tester, const SettingsScreen());
  await tester.scrollUntilVisible(find.byKey(_delete), 200);
  return app;
}

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

/// Waits for [future], which runs on files and so on real time, while
/// pumping.
Future<T> _pumped<T>(WidgetTester tester, Future<T> future) async {
  late T result;
  var done = false;
  unawaited(
    future.then((value) {
      result = value;
      done = true;
    }),
  );
  await pumpUntil(tester, () => done, reason: 'the location history');
  return result;
}

Finder _inRow(String text) =>
    find.descendant(of: find.byKey(_row), matching: find.text(text));

Switch _switchOf(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_switch));

void main() {
  testWidgets('Background geotagging explains the two ways before the '
      'phone asks, turns on with location allowed all the time, and '
      'shows as paused when that is taken away', (tester) async {
    final location = FakePhoneLocation(access: _denied)
      ..whileInUseAnswer = FakePhoneLocation.whileInUse
      ..alwaysAnswer = FakePhoneLocation.always;
    final app = await _start(tester, location);
    final settings = app.models.settings;

    expect(find.text('LOCATION'), findsOneWidget);
    expect(_inRow('Background geotagging'), findsOneWidget);
    expect(_inRow(_offLine), findsOneWidget);
    expect(_switchOf(tester).value, isFalse);
    // What it cannot do is said without opening anything.
    final note = tester.widget<Text>(
      find.byKey(const Key('setting-background-geotag-note')),
    );
    expect(
      note.data,
      contains(
        'Photos downloaded more than 90 days after they were taken get no '
        'location from background geotagging.',
      ),
    );
    expect(note.data, contains('live geotagging wins'));

    // Not now: nothing was asked of the phone.
    await _tap(tester, _switch);
    await pumpUntilFound(tester, find.byKey(_explain));
    Finder said(String text) => find.descendant(
      of: find.byKey(_explain),
      matching: find.textContaining(text),
    );
    expect(said('Live geotagging is the accurate way'), findsOneWidget);
    expect(said('connected over Bluetooth and switched on'), findsOneWidget);
    expect(said('Background geotagging is the hands-free way'), findsOneWidget);
    expect(said('history of where it has been for 90 days'), findsOneWidget);
    expect(said('It is less accurate'), findsOneWidget);
    expect(said('live geotagging wins'), findsOneWidget);
    expect(said('more than 90 days after they were taken'), findsOneWidget);
    expect(said('allow location all the time'), findsOneWidget);
    expect(location.whileInUseRequests, 0);
    await _tap(tester, const Key('background-geotag-later'));
    await pumpUntil(
      tester,
      () => find.byKey(_explain).evaluate().isEmpty,
      reason: 'the explanation closed',
    );
    expect(settings.backgroundGeotagging, isFalse);
    expect(location.whileInUseRequests, 0);
    expect(location.alwaysRequests, 0);

    await _tap(tester, _switch);
    await _tap(tester, _continue);
    await pumpUntil(
      tester,
      () => settings.backgroundGeotagging,
      reason: 'background geotagging on',
    );
    expect(location.whileInUseRequests, 1);
    expect(location.alwaysRequests, 1);
    expect(location.historyEnabled, isTrue);
    await pumpUntilFound(tester, _inRow(_onLine));
    expect(_switchOf(tester).value, isTrue);
    expect(find.byKey(_need), findsNothing);

    // Reduced in the phone's settings: still on, and paused.
    location.setAccess(FakePhoneLocation.whileInUse);
    await pumpUntilFound(tester, _inRow('Paused'));
    expect(settings.backgroundGeotagging, isTrue);
    expect(_switchOf(tester).value, isTrue);
    expect(
      find.descendant(of: find.byKey(_need), matching: find.text(_needsAlways)),
      findsOneWidget,
    );
    await _tap(tester, _openSettings);
    expect(location.settingsOpened, [LocationSettingsPage.app]);

    // Allowed again: it carries on by itself.
    location.setAccess(FakePhoneLocation.always);
    await pumpUntilFound(tester, _inRow(_onLine));
    expect(find.byKey(_need), findsNothing);

    // Off needs no explanation.
    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => !settings.backgroundGeotagging,
      reason: 'background geotagging off',
    );
    expect(find.byKey(_explain), findsNothing);
    expect(location.historyEnabled, isFalse);
    await pumpUntilFound(tester, _inRow(_offLine));

    await app.dispose();
  });

  testWidgets('without location allowed all the time it stays off and '
      'says what is needed', (tester) async {
    final location = FakePhoneLocation();
    final app = await _start(tester, location);

    await _tap(tester, _switch);
    await _tap(tester, _continue);
    await pumpUntilFound(tester, find.byKey(_need));
    expect(location.alwaysRequests, 1);
    expect(app.models.settings.backgroundGeotagging, isFalse);
    expect(location.historyEnabled, isFalse);
    expect(_switchOf(tester).value, isFalse);
    expect(
      find.descendant(of: find.byKey(_need), matching: find.text(_needsAlways)),
      findsOneWidget,
    );
    await _tap(tester, _openSettings);
    expect(location.settingsOpened, [LocationSettingsPage.app]);

    await app.dispose();
  });

  testWidgets('Delete location history asks first, then deletes what was '
      'recorded', (tester) async {
    final location = FakePhoneLocation(access: FakePhoneLocation.always);
    final app = await _start(tester, location);
    final history = app.models.geotag.history;
    await _pumped(
      tester,
      history.add([
        LocationFix(
          latitude: 35,
          longitude: 139,
          accuracy: 20,
          time: clock.now().toUtc(),
        ),
      ]),
    );
    expect(await _pumped(tester, history.isEmpty), isFalse);

    await _tap(tester, _delete);
    await pumpUntilFound(tester, find.text('Delete location history?'));
    await tapWhenReady(tester, find.text('Cancel'));
    await pumpUntil(
      tester,
      () => find.text('Delete location history?').evaluate().isEmpty,
      reason: 'the question closed',
    );
    expect(await _pumped(tester, history.isEmpty), isFalse);

    await _tap(tester, _delete);
    await _tap(tester, const Key('location-history-delete-confirm'));
    await pumpUntilFound(tester, find.text('Location history deleted'));
    expect(await _pumped(tester, history.isEmpty), isTrue);

    await app.dispose();
  });
}
