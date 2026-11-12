import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/connection/camera_pill.dart';
import 'package:grphoto/src/connection/connection_controller.dart';

import '../support/test_app.dart';

const _serial = '1234567';
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

const _section = Key('camera-sheet-location');
const _switch = Key('camera-sheet-geotag-switch');
const _clockSwitch = Key('camera-sheet-clock-switch');
const _settings = Key('camera-sheet-geotag-settings');
const _store = Key('camera-sheet-geotag-store');
const _resume = Key('camera-sheet-geotag-resume');
const _setUp = Key('camera-sheet-autostart-setup');
const _offer = Key('geotag-offer');

const _off = 'Off';
const _waitingForCamera = 'Starts when the camera is switched on and in reach';
const _waitingForLocation = "Waiting for this phone's location";
const _sending = "Sending this phone's location to the camera";
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

/// A phone-sized screen with the camera pill, which opens the camera
/// sheet; nothing connects by itself.
Future<TestApp> _start(
  WidgetTester tester, {
  FakeCameraConfig config = _bonded,
  FakePhoneLocation? location,
  FakePowerOnWatch? watch,
  bool live = false,
  bool offered = true,
  bool saveModel = true,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: config,
      saveCamera: true,
      saveModel: saveModel,
      location: location,
      powerOnWatch: watch,
      liveGeotagging: live,
      geotagOffered: offered,
    ),
  ))!;
  await app.pumpWithin(
    tester,
    const Scaffold(
      body: SafeArea(
        child: Align(alignment: Alignment.topLeft, child: CameraPill()),
      ),
    ),
  );
  return app;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tapWhenReady(tester, find.byKey(const Key('camera-pill')));
  await pumpUntilFound(tester, find.byKey(const Key('camera-sheet')));
}

Future<void> _linkBluetooth(WidgetTester tester, TestApp app) async {
  unawaited(app.models.connection.connect());
  await pumpUntil(
    tester,
    () => app.models.connection.status == ConnectionStatus.bluetooth,
    reason: 'linked over Bluetooth',
  );
}

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

/// [text] in the section's row named [row] (`geotag`, `autostart` or
/// `clock`).
Finder _inRow(String row, String text) => find.descendant(
  of: find.byKey(Key('camera-sheet-$row')),
  matching: find.textContaining(text),
);

Switch _switchOf(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key));

void main() {
  testWidgets('a camera that cannot be sent a location has no location '
      'section', (tester) async {
    // Saved without its model, and not linked, so nothing says what it
    // can do.
    final app = await _start(tester, saveModel: false);
    await _openSheet(tester);
    expect(find.byKey(const Key('camera-sheet-bluetooth')), findsOneWidget);
    expect(find.byKey(_section), findsNothing);

    await app.dispose();
  });

  testWidgets('the Geotagging switch turns live geotagging on, its line '
      'says what it is doing, and the clock is kept in sync while it is '
      'on', (tester) async {
    final location = FakePhoneLocation();
    final app = await _start(tester, location: location);
    final cameras = app.models.cameras;
    await _openSheet(tester);

    expect(find.byKey(_section), findsOneWidget);
    expect(_inRow('geotag', 'Geotagging'), findsOneWidget);
    expect(_inRow('geotag', _off), findsOneWidget);
    expect(_switchOf(tester, _switch).value, isFalse);
    expect(_inRow('clock', 'Sync camera clock'), findsOneWidget);
    expect(_inRow('clock', 'Keeps the camera'), findsOneWidget);
    expect(_switchOf(tester, _clockSwitch).value, isTrue);
    expect(_switchOf(tester, _clockSwitch).onChanged, isNotNull);
    // Nothing to set up while it is off.
    expect(find.byKey(const Key('camera-sheet-autostart')), findsNothing);

    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging,
      reason: 'live geotagging on',
    );
    // Offered before, so the phone is asked without the explanation.
    expect(find.byKey(_offer), findsNothing);
    expect(location.whileInUseRequests, 1);
    await pumpUntilFound(tester, _inRow('geotag', _waitingForCamera));
    expect(_switchOf(tester, _switch).value, isTrue);
    // Forced on, and saying why.
    expect(_inRow('clock', 'On while geotagging is on'), findsOneWidget);
    expect(_switchOf(tester, _clockSwitch).value, isTrue);
    expect(_switchOf(tester, _clockSwitch).onChanged, isNull);

    await _linkBluetooth(tester, app);
    await pumpUntil(
      tester,
      () => app.camera.storeLocationInfo,
      reason: 'Store Location Info on',
    );
    await pumpUntilFound(tester, _inRow('geotag', _waitingForLocation));
    await pumpUntil(tester, () {
      location.emitFix(_fix());
      return _inRow('geotag', _sending).evaluate().isNotEmpty;
    }, reason: 'sending');
    expect(app.camera.location, isNotNull);

    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => !cameras.current!.liveGeotagging,
      reason: 'live geotagging off',
    );
    await pumpUntilFound(tester, _inRow('geotag', _off));
    await pumpUntil(
      tester,
      () => !app.camera.storeLocationInfo,
      reason: 'Store Location Info off',
    );
    expect(app.camera.location, isNull);

    // The clock is the user's to choose again.
    expect(_switchOf(tester, _clockSwitch).onChanged, isNotNull);
    await _tap(tester, _clockSwitch);
    await pumpUntil(
      tester,
      () => !cameras.current!.syncClock,
      reason: 'clock sync off',
    );
    expect(_switchOf(tester, _clockSwitch).value, isFalse);

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
    await _linkBluetooth(tester, app);
    await _openSheet(tester);
    await pumpUntilFound(tester, _inRow('geotag', _waitingForLocation));
    expect(find.byKey(_settings), findsNothing);

    for (final (access, text, page) in [
      (_denied, _notAllowed, LocationSettingsPage.app),
      (_approximate, 'Precise location is needed', LocationSettingsPage.app),
      (_phoneOff, _phoneLocationOff, LocationSettingsPage.phone),
    ]) {
      location.setAccess(access);
      await pumpUntilFound(tester, _inRow('geotag', text));
      await _tap(tester, _settings);
      expect(location.settingsOpened.last, page);
      // It stays on: only the phone holds it up.
      expect(_switchOf(tester, _switch).value, isTrue);
    }

    // Allowed again in the phone's settings.
    location.setAccess(FakePhoneLocation.whileInUse);
    await pumpUntilFound(tester, _inRow('geotag', _waitingForLocation));
    expect(find.byKey(_settings), findsNothing);

    await app.dispose();
  });

  testWidgets('a refusal when turning it on leaves the switch off and '
      'says what is needed, until the phone allows it', (tester) async {
    final location = FakePhoneLocation(access: _denied);
    final app = await _start(tester, location: location);
    await _openSheet(tester);

    await _tap(tester, _switch);
    await pumpUntilFound(tester, _inRow('geotag', _notAllowed));
    expect(location.whileInUseRequests, 1);
    expect(app.models.cameras.current!.liveGeotagging, isFalse);
    expect(_switchOf(tester, _switch).value, isFalse);
    await _tap(tester, _settings);
    expect(location.settingsOpened, [LocationSettingsPage.app]);

    location.setAccess(FakePhoneLocation.whileInUse);
    await pumpUntilFound(tester, _inRow('geotag', _off));
    expect(find.byKey(_settings), findsNothing);

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
    await _linkBluetooth(tester, app);
    await _openSheet(tester);
    await pumpUntilFound(tester, _inRow('geotag', _waitingForLocation));
    expect(find.byKey(_store), findsNothing);

    // In the camera's menu.
    app.camera.storeLocationInfo = false;
    await pumpUntilFound(tester, _inRow('geotag', _offOnCamera));
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
    await pumpUntilFound(tester, _inRow('geotag', _waitingForLocation));
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
    await _linkBluetooth(tester, app);
    await _openSheet(tester);
    await pumpUntil(tester, () => location.runHeld, reason: 'the run');
    expect(find.byKey(_resume), findsNothing);

    location.pressStop();
    await pumpUntilFound(tester, _inRow('geotag', 'Stopped.'));
    expect(
      find.descendant(of: find.byKey(_resume), matching: find.text('Resume')),
      findsOneWidget,
    );
    expect(_switchOf(tester, _switch).value, isTrue);

    await _tap(tester, _resume);
    await pumpUntilFound(tester, _inRow('geotag', _waitingForLocation));
    expect(find.byKey(_resume), findsNothing);
    await pumpUntil(tester, () => location.runHeld, reason: 'the run again');

    await app.dispose();
  });

  testWidgets('a camera switched on while the phone would not start '
      'geotagging off screen: the line says it starts when GR Photo is '
      'open', (tester) async {
    final location = FakePhoneLocation()
      ..runRefusal = LocationRunRefusal.background;
    final app = await _start(
      tester,
      config: _storing,
      location: location,
      live: true,
    );
    await _linkBluetooth(tester, app);
    await _openSheet(tester);
    await pumpUntilFound(
      tester,
      _inRow('geotag', 'Geotagging starts when GR Photo is open'),
    );
    expect(find.byKey(_settings), findsNothing);
    expect(find.byKey(_resume), findsNothing);

    // GR Photo is on screen again, where the phone lets it start.
    location
      ..runRefusal = null
      ..setAccess(FakePhoneLocation.whileInUse);
    await pumpUntilFound(tester, _inRow('geotag', _waitingForLocation));

    await app.dispose();
  });

  testWidgets('automatic start is offered while live geotagging is on, '
      'asks for location all the time and the link to the phone, and '
      'then says it is set up', (tester) async {
    final location = FakePhoneLocation()
      ..alwaysAnswer = FakePhoneLocation.always;
    final watch = FakePowerOnWatch(needsAssociation: true);
    final app = await _start(
      tester,
      location: location,
      watch: watch,
      live: true,
    );
    await _openSheet(tester);

    expect(_inRow('autostart', 'Automatic start'), findsOneWidget);
    expect(
      _inRow('autostart', 'Starts when GR Photo is open.'),
      findsOneWidget,
    );
    expect(
      _inRow('autostart', 'allow location all the time and link the camera'),
      findsOneWidget,
    );

    await _tap(tester, _setUp);
    await pumpUntilFound(
      tester,
      _inRow('autostart', 'Starts whenever the camera is switched on, also'),
    );
    expect(location.alwaysRequests, 1);
    expect(watch.associateRequests.single.deviceId, _bonded.deviceId);
    expect(find.byKey(_setUp), findsNothing);
    expect(
      app.models.geotag.autoStartReady(app.models.cameras.current!),
      isTrue,
    );

    await app.dispose();
  });

  testWidgets('automatic start refused: the row says what is missing, '
      "with the phone's settings for the location and Set up again for "
      'the link', (tester) async {
    final location = FakePhoneLocation();
    final watch = FakePowerOnWatch(needsAssociation: true)
      ..associateAnswer = false;
    final app = await _start(
      tester,
      location: location,
      watch: watch,
      live: true,
    );
    await _openSheet(tester);

    // The phone leaves location as it is: allowed while in use.
    await _tap(tester, _setUp);
    await pumpUntilFound(
      tester,
      _inRow('autostart', 'Location has to be allowed all the time'),
    );
    expect(watch.associateRequests, isEmpty);
    await _tap(tester, const Key('camera-sheet-autostart-settings'));
    expect(location.settingsOpened, [LocationSettingsPage.app]);

    // Allowed there; the link is what is left, and it is refused.
    location.setAccess(FakePhoneLocation.always);
    await pumpUntilFound(
      tester,
      _inRow('autostart', 'link the camera to this phone when the phone'),
    );
    await _tap(tester, _setUp);
    await pumpUntilFound(
      tester,
      _inRow('autostart', "The camera wasn't linked to this phone"),
    );
    expect(watch.associateRequests, hasLength(1));
    expect(find.byKey(_setUp), findsOneWidget);

    await app.dispose();
  });

  testWidgets('a phone that cannot start GR Photo for a camera shows no '
      'automatic start', (tester) async {
    final app = await _start(
      tester,
      watch: FakePowerOnWatch(supported: false),
      live: true,
    );
    await _openSheet(tester);
    expect(_inRow('geotag', _waitingForCamera), findsOneWidget);
    expect(find.byKey(const Key('camera-sheet-autostart')), findsNothing);

    await app.dispose();
  });

  testWidgets('the switch explains geotagging first for a camera that was '
      'not offered it, before the phone asks anything', (tester) async {
    final location = FakePhoneLocation(access: _denied)
      ..whileInUseAnswer = FakePhoneLocation.whileInUse;
    final app = await _start(tester, location: location, offered: false);
    final cameras = app.models.cameras;
    await _openSheet(tester);

    await _tap(tester, _switch);
    await pumpUntilFound(tester, find.byKey(_offer));
    expect(location.whileInUseRequests, 0);
    await _tap(tester, const Key('geotag-offer-later'));
    await pumpUntil(
      tester,
      () => cameras.current!.geotagOffered,
      reason: 'offered',
    );
    await pumpUntil(
      tester,
      () => find.byKey(_offer).evaluate().isEmpty,
      reason: 'the offer closed',
    );
    expect(cameras.current!.liveGeotagging, isFalse);
    expect(location.whileInUseRequests, 0);

    // Explained once: the switch asks the phone from now on. It is
    // disabled until the answer has been saved.
    await pumpUntil(
      tester,
      () => _switchOf(tester, _switch).onChanged != null,
      reason: 'the switch enabled again',
    );
    await _tap(tester, _switch);
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging,
      reason: 'live geotagging on',
    );
    expect(find.byKey(_offer), findsNothing);
    expect(location.whileInUseRequests, 1);
    expect(cameras.current!.serial, _serial);

    await app.dispose();
  });
}
