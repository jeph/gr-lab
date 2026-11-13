import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';

import '../support/test_app.dart';

const _bonded = FakeCameraConfig(bonded: true);

/// A camera with Store Location Info on already.
const _storing = FakeCameraConfig(bonded: true, storeLocationInfo: true);

const _denied = LocationAccess(
  permission: LocationPermission.denied,
  precise: false,
  serviceOn: true,
);
const _approximate = LocationAccess(
  permission: LocationPermission.whileInUse,
  precise: false,
  serviceOn: true,
);
const _phoneOff = LocationAccess(
  permission: LocationPermission.whileInUse,
  precise: true,
  serviceOn: false,
);

const _card = Key('camera-card-geotag');
const _switch = Key('camera-card-geotag-switch');
const _settings = Key('camera-card-geotag-settings');
const _store = Key('camera-card-geotag-store');
const _problem = Key('camera-card-geotag-problem');
const _background = Key('camera-card-geotag-background');

const _whatItDoes =
    "Geotags photos on the camera while it's connected to GR Photo";
const _notAllowed = "GR Photo isn't allowed to use this phone's location";
const _phoneLocationOff = 'Location is turned off on this phone';
const _offOnCamera =
    'Please enable Store Location Info on the camera to enable geotagging';
const _pausedByPhone = 'This phone can pause GR Photo while its screen is off';

/// A made-up position the phone takes now.
LocationFix _fix() => LocationFix(
  latitude: 35,
  longitude: 139,
  accuracy: 8,
  time: clock.now().toUtc(),
);

/// The whole app on a phone-sized screen with the camera paired: the
/// Cameras screen, which links the camera over Bluetooth by itself unless
/// [link] is false.
Future<TestApp> _start(
  WidgetTester tester, {
  FakeCameraConfig config = _bonded,
  FakePhoneLocation? location,
  bool live = false,
  bool saveModel = true,
  bool link = true,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(() async {
    final app = await createTestApp(
      config: config,
      saveCamera: true,
      saveModel: saveModel,
      location: location,
      liveGeotagging: live,
    );
    if (!link) app.models.settings.connectWhenNearby = false;
    return app;
  }))!;
  await app.pumpApp(tester);
  if (!link) return app;
  await pumpUntil(
    tester,
    () => app.models.connection.status == ConnectionStatus.bluetooth,
    reason: 'linked over Bluetooth',
  );
  return app;
}

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

/// [text] on the card's Live geotagging switch.
Finder _said(String text) =>
    find.descendant(of: find.byKey(_card), matching: find.textContaining(text));

Future<void> _untilStatus(
  WidgetTester tester,
  TestApp app,
  GeotagStatus status,
) => pumpUntil(
  tester,
  () => app.models.geotag.status == status,
  reason: 'live geotagging ${status.name}',
);

/// Until the card says only what the switch does: nothing is in the way.
Future<void> _untilNoProblem(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => find.byKey(_problem).evaluate().isEmpty,
    reason: 'nothing in the way',
  );
  expect(_said(_whatItDoes), findsOneWidget);
}

Switch _switchOf(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_switch));

void main() {
  testWidgets('Live geotagging is a switch on the camera card under '
      'Library, Shoot and Looks, off until the user turns it on: nothing '
      'is asked or offered before, and its line says what it does whether '
      'it is on or off', (tester) async {
    final location = FakePhoneLocation(access: _denied)
      ..whileInUseAnswer = FakePhoneLocation.whileInUse;
    final app = await _start(tester, location: location);
    final cameras = app.models.cameras;

    // Opened and linked, and the phone was asked nothing.
    await pumpRounds(tester, 20);
    expect(find.byType(GrDialog), findsNothing);
    expect(location.whileInUseRequests, 0);
    expect(location.alwaysRequests, 0);
    expect(location.locating, isFalse);
    expect(cameras.current!.liveGeotagging, isFalse);
    expect(app.camera.storeLocationInfo, isFalse);

    expect(_said('Live geotagging'), findsOneWidget);
    expect(_said(_whatItDoes), findsOneWidget);
    expect(_switchOf(tester).value, isFalse);
    for (final tab in ['library', 'shoot', 'looks']) {
      expect(
        tester.getTopLeft(find.byKey(_card)).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byKey(Key('camera-card-$tab'))).dy,
        ),
      );
    }

    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging,
      reason: 'live geotagging on',
    );
    expect(find.byType(GrDialog), findsNothing);
    expect(location.whileInUseRequests, 1);
    expect(location.alwaysRequests, 0);
    await pumpUntil(
      tester,
      () => app.camera.storeLocationInfo,
      reason: 'Store Location Info on',
    );
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);
    await _untilNoProblem(tester);
    expect(_switchOf(tester).value, isTrue);
    await pumpUntil(tester, () {
      location.emitFix(_fix());
      return app.models.geotag.status == GeotagStatus.sending;
    }, reason: 'sending');
    await _untilNoProblem(tester);
    expect(app.camera.location, isNotNull);
    // Background geotagging is another switch, in the camera's details.
    expect(cameras.current!.backgroundGeotagging, isFalse);
    expect(location.historyEnabled, isFalse);

    await pumpUntil(
      tester,
      () => _switchOf(tester).onChanged != null,
      reason: 'the switch enabled again',
    );
    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => !cameras.current!.liveGeotagging,
      reason: 'live geotagging off',
    );
    await pumpUntilFound(tester, _said(_whatItDoes));
    await pumpUntil(
      tester,
      () => !app.camera.storeLocationInfo,
      reason: 'Store Location Info off',
    );
    expect(app.camera.location, isNull);
    expect(location.locating, isFalse);

    await app.dispose();
  });

  testWidgets('a camera that cannot be sent a location has no Live '
      'geotagging switch', (tester) async {
    // Saved without its model, and not linked, so nothing says what it
    // can do.
    final app = await _start(tester, saveModel: false, link: false);
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-library')));
    expect(find.byKey(_card), findsNothing);

    await app.dispose();
  });

  testWidgets('each thing the phone lacks is named, with a button to the '
      'page of its settings that allows it', (tester) async {
    final location = FakePhoneLocation();
    final app = await _start(
      tester,
      config: _storing,
      location: location,
      live: true,
    );
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);
    await _untilNoProblem(tester);
    expect(find.byKey(_settings), findsNothing);

    for (final (access, text, page) in [
      (_denied, _notAllowed, LocationSettingsPage.app),
      (_approximate, 'Precise location is needed', LocationSettingsPage.app),
      (_phoneOff, _phoneLocationOff, LocationSettingsPage.phone),
    ]) {
      location.setAccess(access);
      await pumpUntilFound(tester, _said(text));
      expect(_said(_whatItDoes), findsOneWidget);
      await _tap(tester, _settings);
      expect(location.settingsOpened.last, page);
      // It stays on: only the phone holds it up.
      expect(_switchOf(tester).value, isTrue);
    }

    // Allowed again in the phone's settings.
    location.setAccess(FakePhoneLocation.whileInUse);
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);
    await _untilNoProblem(tester);
    expect(find.byKey(_settings), findsNothing);

    await app.dispose();
  });

  testWidgets('a refusal when turning it on leaves the switch off and '
      'says what is needed, until the phone allows it', (tester) async {
    final location = FakePhoneLocation(access: _denied);
    final app = await _start(tester, location: location);

    await _tap(tester, _switch);
    await pumpUntilFound(tester, _said(_notAllowed));
    expect(_said(_whatItDoes), findsOneWidget);
    expect(location.whileInUseRequests, 1);
    expect(app.models.cameras.current!.liveGeotagging, isFalse);
    expect(_switchOf(tester).value, isFalse);
    await _tap(tester, _settings);
    expect(location.settingsOpened, [LocationSettingsPage.app]);

    location.setAccess(FakePhoneLocation.whileInUse);
    await _untilNoProblem(tester);
    expect(find.byKey(_settings), findsNothing);
    expect(_switchOf(tester).value, isFalse);

    await app.dispose();
  });

  testWidgets('on a phone that may stop GR Photo with the screen off, '
      'turning it on asks to be allowed in the background; refused, it is '
      'on all the same and the card says so with a button that asks again', (
    tester,
  ) async {
    final location = FakePhoneLocation()..unrestricted = false;
    final app = await _start(tester, config: _storing, location: location);
    expect(find.byKey(_background), findsNothing);
    expect(location.unrestrictedRequests, 0);

    await _tap(tester, _switch);
    await pumpUntilFound(tester, _said(_pausedByPhone));
    await pumpUntil(
      tester,
      () => location.unrestrictedRequests == 1,
      reason: 'the phone to be asked',
    );
    expect(app.models.cameras.current!.liveGeotagging, isTrue);
    expect(_switchOf(tester).value, isTrue);
    expect(
      find.descendant(
        of: find.byKey(_background),
        matching: find.text('Allow in the background'),
      ),
      findsOneWidget,
    );
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);

    // What holds geotagging up comes first.
    location.setAccess(_denied);
    await pumpUntilFound(tester, _said(_notAllowed));
    expect(_said(_pausedByPhone), findsNothing);
    expect(find.byKey(_background), findsNothing);
    location.setAccess(FakePhoneLocation.whileInUse);
    await pumpUntilFound(tester, _said(_pausedByPhone));

    location.unrestrictedAnswer = true;
    await _tap(tester, _background);
    await _untilNoProblem(tester);
    expect(location.unrestrictedRequests, 2);
    expect(find.byKey(_background), findsNothing);

    await app.dispose();
  });

  testWidgets("allowed in the background from the phone's settings, the "
      'card no longer says the phone may stop GR Photo; off, it never does', (
    tester,
  ) async {
    final location = FakePhoneLocation()..unrestricted = false;
    final app = await _start(
      tester,
      config: _storing,
      location: location,
      live: true,
    );
    await pumpUntilFound(tester, _said(_pausedByPhone));
    // Nothing asks by itself.
    expect(location.unrestrictedRequests, 0);

    // The user allows it in the phone's settings and comes back.
    location
      ..unrestricted = true
      ..setAccess(FakePhoneLocation.whileInUse);
    await _untilNoProblem(tester);

    location
      ..unrestricted = false
      ..setAccess(FakePhoneLocation.whileInUse);
    await pumpUntilFound(tester, _said(_pausedByPhone));
    await _tap(tester, _switch);
    await _untilNoProblem(tester);
    expect(_switchOf(tester).value, isFalse);

    await app.dispose();
  });

  testWidgets('Store Location Info turned off on the camera is said, and '
      'turned on again only from its button', (tester) async {
    final location = FakePhoneLocation();
    final app = await _start(
      tester,
      config: _storing,
      location: location,
      live: true,
    );
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);
    await _untilNoProblem(tester);
    expect(find.byKey(_store), findsNothing);

    // In the camera's menu.
    app.camera.storeLocationInfo = false;
    await pumpUntilFound(tester, _said(_offOnCamera));
    expect(_said(_whatItDoes), findsOneWidget);
    await pumpRounds(tester, 20);
    expect(app.camera.storeLocationInfo, isFalse);
    expect(
      find.descendant(of: find.byKey(_store), matching: find.text('Turn on')),
      findsOneWidget,
    );

    await _tap(tester, _store);
    await pumpUntil(
      tester,
      () => app.camera.storeLocationInfo,
      reason: 'Store Location Info on',
    );
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);
    await _untilNoProblem(tester);
    expect(find.byKey(_store), findsNothing);

    await app.dispose();
  });

  testWidgets("Stop on the phone's notice turns live geotagging off as the "
      "switch does: the switch is off, the camera's Store Location Info is "
      'turned off, and it starts again only when the user turns it '
      'on', (tester) async {
    final location = FakePhoneLocation();
    final app = await _start(
      tester,
      config: _storing,
      location: location,
      live: true,
    );
    await pumpUntil(tester, () => location.runHeld, reason: 'the run');
    expect(_switchOf(tester).value, isTrue);

    location.pressStop();
    await pumpUntil(
      tester,
      () => !_switchOf(tester).value,
      reason: 'the switch off',
    );
    expect(app.models.cameras.current!.liveGeotagging, isFalse);
    await pumpUntil(
      tester,
      () => !app.camera.storeLocationInfo,
      reason: 'Store Location Info off on the camera',
    );
    expect(find.byKey(_problem), findsNothing);
    expect(_said(_whatItDoes), findsOneWidget);

    // Nothing runs any more.
    await pumpUntil(tester, () => !location.runHeld, reason: 'the run let go');
    await pumpRounds(tester, 20);
    expect(location.runHeld, isFalse);
    expect(location.locating, isFalse);
    expect(app.models.geotag.status, GeotagStatus.off);

    await _tap(tester, _switch);
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);
    await pumpUntil(tester, () => location.runHeld, reason: 'the run again');
    expect(app.camera.storeLocationInfo, isTrue);

    await app.dispose();
  });
}
