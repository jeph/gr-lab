import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/connection/connection_controller.dart';

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
const _resume = Key('camera-card-geotag-resume');
const _problem = Key('camera-card-geotag-problem');

const _whatItDoes =
    "Geotags photos on the camera while it's connected to GR Photo";
const _notAllowed = "GR Photo isn't allowed to use this phone's location";
const _phoneLocationOff = 'Location is turned off on this phone';
const _offOnCamera = 'Store Location Info is off on the camera';

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
    expect(find.byType(AlertDialog), findsNothing);
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
    expect(find.byType(AlertDialog), findsNothing);
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

  testWidgets("after Stop on the phone's notice the line says so and "
      'offers Resume', (tester) async {
    final location = FakePhoneLocation();
    final app = await _start(
      tester,
      config: _storing,
      location: location,
      live: true,
    );
    await pumpUntil(tester, () => location.runHeld, reason: 'the run');
    expect(find.byKey(_resume), findsNothing);

    location.pressStop();
    await pumpUntilFound(tester, _said('Stopped.'));
    expect(
      find.descendant(of: find.byKey(_resume), matching: find.text('Resume')),
      findsOneWidget,
    );
    expect(_switchOf(tester).value, isTrue);

    await _tap(tester, _resume);
    await _untilStatus(tester, app, GeotagStatus.waitingForLocation);
    await _untilNoProblem(tester);
    expect(find.byKey(_resume), findsNothing);
    await pumpUntil(tester, () => location.runHeld, reason: 'the run again');

    await app.dispose();
  });
}
