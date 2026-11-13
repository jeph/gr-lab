import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/cameras/camera_details.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/widgets/group.dart';

import '../support/test_app.dart';

const _serial = '1234567';
const _otherSerial = '7654321';
const _bonded = FakeCameraConfig(bonded: true);

const _denied = LocationAccess(
  permission: LocationPermission.denied,
  precise: false,
  serviceOn: true,
);

const _section = Key('camera-details-location');
const _row = Key('camera-details-background');
const _switch = Key('camera-details-background-switch');
const _need = Key('camera-details-background-need');
const _openSettings = Key('camera-details-background-settings');
const _learnMore = Key('camera-details-geotag-learn-more');
const _explain = Key('background-geotag-explain');
const _clockRow = Key('camera-details-clock');
const _clockSwitch = Key('camera-details-clock-switch');

const _subtitle =
    "Records this phone's location in the background and geotags photos "
    "when they're downloaded";
const _needsAlways = 'Location has to be allowed all the time';
const _clockSubtitle =
    "Keeps the camera's clock in sync with this phone. Stays on while "
    'background geotagging is on.';

/// A phone-sized screen with the details of the saved camera [serial]
/// (the current one by default); nothing connects by itself. With [other],
/// a second camera is paired as well and the first stays the current one.
Future<TestApp> _start(
  WidgetTester tester, {
  FakePhoneLocation? location,
  bool live = false,
  bool saveModel = true,
  bool other = false,
  String serial = _serial,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(() async {
    final app = await createTestApp(
      config: _bonded,
      saveCamera: true,
      saveModel: saveModel,
      location: location,
      liveGeotagging: live,
    );
    if (other) {
      const paired = GrPairedCamera(
        deviceId: '00:00:5E:00:53:B7',
        serialNumber: _otherSerial,
        modelName: 'RICOH GR IV',
        firmwareRevision: '1.20',
        bluetoothDeviceName: 'GR_H0053B7',
      );
      await app.models.cameras.add(
        SavedCamera(
          paired: paired,
          name: 'Street',
          pairedAt: DateTime(2026, 11, 8, 9, 41),
        ),
      );
      await app.models.cameras.select(_serial);
    }
    return app;
  }))!;
  await app.pumpWithin(tester, CameraDetailsScreen(serial: serial));
  await pumpUntilFound(tester, find.byKey(const Key('camera-details')));
  return app;
}

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

Finder _in(Key row, String text) =>
    find.descendant(of: find.byKey(row), matching: find.text(text));

Switch _switchOf(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key));

SavedCamera _saved(TestApp app, [String serial = _serial]) =>
    app.models.cameras.cameras.singleWhere((c) => c.serial == serial);

void main() {
  testWidgets('Learn more opens a screen that explains background '
      'geotagging, and Back returns to the details with nothing asked of '
      'the phone', (tester) async {
    final location = FakePhoneLocation(access: _denied);
    final app = await _start(tester, location: location);

    // The section itself carries no explanation.
    expect(find.byKey(_section), findsOneWidget);
    expect(find.textContaining('90 days'), findsNothing);

    await _tap(tester, _learnMore);
    await pumpUntilFound(tester, find.byKey(_explain));
    expect(find.byType(AlertDialog), findsNothing);
    Finder said(String text) => find.descendant(
      of: find.byKey(_explain),
      matching: find.textContaining(text),
    );
    expect(
      find.descendant(
        of: find.byKey(_explain),
        matching: find.text('Background geotagging'),
      ),
      findsOneWidget,
    );
    expect(
      said("keeps a history of this phone's location for 90 days"),
      findsOneWidget,
    );
    expect(said('Unlike live geotagging'), findsOneWidget);
    expect(said('slightly less accurate'), findsOneWidget);
    expect(said('allow access to your location all the time'), findsOneWidget);
    expect(said('only ever stored locally on this phone'), findsOneWidget);
    expect(said('past 90 days of location data'), findsOneWidget);
    expect(said('more than 90 days after they were taken'), findsOneWidget);

    // Once the screen has slid in.
    await tapWhenReady(tester, find.byType(BackButton).last);
    await pumpUntil(
      tester,
      () => find.byKey(_explain).evaluate().isEmpty,
      reason: 'the explanation closed',
    );
    expect(find.byKey(_switch), findsOneWidget);
    expect(_saved(app).backgroundGeotagging, isFalse);
    expect(location.whileInUseRequests, 0);
    expect(location.alwaysRequests, 0);

    await app.dispose();
  });

  testWidgets('Background geotagging turns on for the camera with location '
      'allowed all the time, holds Sync camera clock on while it is on, '
      'and shows as paused when the permission is taken away', (tester) async {
    final location = FakePhoneLocation(access: _denied)
      ..whileInUseAnswer = FakePhoneLocation.whileInUse
      ..alwaysAnswer = FakePhoneLocation.always;
    final app = await _start(tester, location: location);

    expect(find.text('LOCATION'), findsOneWidget);
    expect(_in(_row, 'Background geotagging'), findsOneWidget);
    expect(_in(_row, _subtitle), findsOneWidget);
    expect(_switchOf(tester, _switch).value, isFalse);
    expect(_in(_clockRow, 'Sync camera clock'), findsOneWidget);
    // In a section of its own, not with the location rows.
    expect(find.text('CLOCK'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.byKey(_row),
          matching: find.byType(GroupBox),
        ),
        matching: find.byKey(_clockRow),
      ),
      findsNothing,
    );
    expect(_in(_clockRow, _clockSubtitle), findsOneWidget);
    expect(_switchOf(tester, _clockSwitch).value, isTrue);
    expect(_switchOf(tester, _clockSwitch).onChanged, isNotNull);

    // The clock is the user's to choose while background geotagging is
    // off.
    await _tap(tester, _clockSwitch);
    await pumpUntil(
      tester,
      () => !_saved(app).syncClock,
      reason: 'clock sync off',
    );
    await pumpUntil(
      tester,
      () => !_switchOf(tester, _clockSwitch).value,
      reason: 'the clock switch off',
    );
    expect(_in(_clockRow, _clockSubtitle), findsOneWidget);

    // The phone's own prompt comes straight away.
    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => _saved(app).backgroundGeotagging,
      reason: 'background geotagging on',
    );
    expect(find.byKey(_explain), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(location.whileInUseRequests, 1);
    expect(location.alwaysRequests, 1);
    expect(location.historyEnabled, isTrue);
    await pumpUntil(
      tester,
      () => _switchOf(tester, _switch).value,
      reason: 'the switch on',
    );
    expect(_in(_row, _subtitle), findsOneWidget);
    expect(find.byKey(_need), findsNothing);
    // Live geotagging is not turned on with it.
    expect(_saved(app).liveGeotagging, isFalse);

    // The clock is on and cannot be changed, whatever the user chose.
    expect(_saved(app).syncClock, isFalse);
    expect(_switchOf(tester, _clockSwitch).value, isTrue);
    expect(_switchOf(tester, _clockSwitch).onChanged, isNull);
    expect(_in(_clockRow, _clockSubtitle), findsOneWidget);
    await tester.tap(find.byKey(_clockRow), warnIfMissed: false);
    await pumpRounds(tester, 5);
    expect(_switchOf(tester, _clockSwitch).value, isTrue);

    // Reduced in the phone's settings: still on, and paused.
    location.setAccess(FakePhoneLocation.whileInUse);
    await pumpUntilFound(tester, _in(_need, 'Paused'));
    expect(_saved(app).backgroundGeotagging, isTrue);
    expect(_switchOf(tester, _switch).value, isTrue);
    expect(_in(_row, _subtitle), findsOneWidget);
    expect(_in(_need, _needsAlways), findsOneWidget);
    await _tap(tester, _openSettings);
    expect(location.settingsOpened, [LocationSettingsPage.app]);

    // Allowed again: it carries on by itself.
    location.setAccess(FakePhoneLocation.always);
    await pumpUntil(
      tester,
      () => find.byKey(_need).evaluate().isEmpty,
      reason: 'no longer paused',
    );
    expect(_switchOf(tester, _switch).value, isTrue);

    // The switch waits while the phone is being asked and set up.
    await pumpUntil(
      tester,
      () => _switchOf(tester, _switch).onChanged != null,
      reason: 'the switch enabled again',
    );
    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => !_saved(app).backgroundGeotagging,
      reason: 'background geotagging off',
    );
    expect(location.historyEnabled, isFalse);
    await pumpUntil(
      tester,
      () => !_switchOf(tester, _switch).value,
      reason: 'the switch off',
    );
    expect(_in(_row, _subtitle), findsOneWidget);
    // The clock is back to what the user chose.
    expect(_switchOf(tester, _clockSwitch).value, isFalse);
    expect(_switchOf(tester, _clockSwitch).onChanged, isNotNull);
    expect(_in(_clockRow, _clockSubtitle), findsOneWidget);

    await app.dispose();
  });

  testWidgets('without location allowed all the time it stays off and '
      'says what is needed', (tester) async {
    final location = FakePhoneLocation();
    final app = await _start(tester, location: location);

    await _tap(tester, _switch);
    await pumpUntilFound(tester, find.byKey(_need));
    expect(location.alwaysRequests, 1);
    expect(_saved(app).backgroundGeotagging, isFalse);
    expect(location.historyEnabled, isFalse);
    expect(_switchOf(tester, _switch).value, isFalse);
    expect(_in(_need, _needsAlways), findsOneWidget);
    expect(_in(_need, 'Paused'), findsNothing);
    // Not on, so the clock is not held either.
    expect(_switchOf(tester, _clockSwitch).onChanged, isNotNull);
    await _tap(tester, _openSettings);
    expect(location.settingsOpened, [LocationSettingsPage.app]);

    await app.dispose();
  });

  testWidgets('Sync camera clock does not follow live geotagging: with '
      'live geotagging on it can still be turned off', (tester) async {
    final app = await _start(tester, live: true);
    expect(_saved(app).liveGeotagging, isTrue);
    expect(_switchOf(tester, _clockSwitch).value, isTrue);
    expect(_switchOf(tester, _clockSwitch).onChanged, isNotNull);
    expect(_in(_clockRow, _clockSubtitle), findsOneWidget);

    await _tap(tester, _clockSwitch);
    await pumpUntil(
      tester,
      () => !_saved(app).syncClock,
      reason: 'clock sync off',
    );
    expect(_saved(app).keepsClock, isFalse);
    expect(_saved(app).liveGeotagging, isTrue);

    await app.dispose();
  });

  testWidgets('the details of a camera that is not the current one turn '
      "background geotagging on for that camera, not the current one's, "
      'also for a camera saved without its model', (tester) async {
    final location = FakePhoneLocation(access: FakePhoneLocation.always);
    final app = await _start(
      tester,
      location: location,
      saveModel: false,
      other: true,
      serial: _otherSerial,
    );
    expect(app.models.cameras.current!.serial, _serial);
    expect(_switchOf(tester, _switch).value, isFalse);

    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => _saved(app, _otherSerial).backgroundGeotagging,
      reason: 'background geotagging on for the other camera',
    );
    expect(_saved(app).backgroundGeotagging, isFalse);
    expect(location.historyEnabled, isTrue);
    expect(_in(_clockRow, _clockSubtitle), findsOneWidget);

    // The current camera's details, saved without its model: the section
    // is there, with its own switches.
    await app.pumpWithin(tester, const CameraDetailsScreen(serial: _serial));
    await pumpUntilFound(tester, find.byKey(_section));
    expect(_switchOf(tester, _switch).value, isFalse);
    expect(_switchOf(tester, _clockSwitch).onChanged, isNotNull);
    expect(_in(_clockRow, _clockSubtitle), findsOneWidget);

    await app.dispose();
  });
}
