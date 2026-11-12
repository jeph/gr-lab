import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/geotag/geotag_offer.dart';

import '../support/test_app.dart';

const _offer = Key('geotag-offer');
const _turnOn = Key('geotag-offer-on');
const _notNow = Key('geotag-offer-later');

const _denied = LocationAccess(
  permission: LocationPermission.denied,
  precise: false,
  serviceOn: true,
);

/// The whole app on a phone-sized screen, with the fake GR IV paired and
/// not yet offered geotagging; it links the camera by itself.
Future<TestApp> _start(WidgetTester tester, FakePhoneLocation location) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      location: location,
      geotagOffered: false,
    ),
  ))!;
  await app.pumpApp(tester);
  return app;
}

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

Future<void> _untilClosed(WidgetTester tester) => pumpUntil(
  tester,
  () => find.byKey(_offer).evaluate().isEmpty,
  reason: 'the offer closed',
);

void main() {
  testWidgets('a camera linked for the first time is offered geotagging '
      'once, with what it does, before the phone asks anything; Not now '
      'leaves it off', (tester) async {
    final location = FakePhoneLocation(access: _denied);
    final app = await _start(tester, location);
    final cameras = app.models.cameras;
    final connection = app.models.connection;

    await pumpUntilFound(tester, find.byKey(_offer));
    expect(connection.bleLinked, isTrue);
    expect(find.text('Add locations to your photos?'), findsOneWidget);
    final dialog = find.byKey(_offer);
    Finder said(String text) =>
        find.descendant(of: dialog, matching: find.textContaining(text));
    // Whose it is, by the name the user gave the camera.
    expect(
      find.descendant(of: dialog, matching: find.text('GR IV')),
      findsOneWidget,
    );
    expect(said("sends this phone's location to the camera"), findsOneWidget);
    expect(said('only while the camera is on'), findsOneWidget);
    expect(said("keeps the camera's clock on this phone"), findsOneWidget);
    expect(said('your phone asks whether GR Photo may use'), findsOneWidget);
    expect(location.whileInUseRequests, 0);
    expect(cameras.current!.geotagOffered, isFalse);

    await _tap(tester, _notNow);
    await _untilClosed(tester);
    await pumpUntil(
      tester,
      () => cameras.current!.geotagOffered,
      reason: 'offered',
    );
    expect(cameras.current!.liveGeotagging, isFalse);
    expect(location.whileInUseRequests, 0);

    // Linked anew: it is not offered a second time.
    var closed = false;
    unawaited(connection.disconnect().whenComplete(() => closed = true));
    await pumpUntil(tester, () => closed, reason: 'session closed');
    unawaited(connection.connect());
    await pumpUntil(
      tester,
      () => connection.status == ConnectionStatus.bluetooth,
      reason: 'linked again',
    );
    await pumpRounds(tester, 20);
    expect(find.byKey(_offer), findsNothing);

    await app.dispose();
  });

  testWidgets('Turn on asks the phone for its location and turns live '
      "geotagging on, with the camera's Store Location Info", (tester) async {
    final location = FakePhoneLocation(access: _denied)
      ..whileInUseAnswer = FakePhoneLocation.whileInUse;
    final app = await _start(tester, location);
    final cameras = app.models.cameras;

    await _tap(tester, _turnOn);
    await _untilClosed(tester);
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging,
      reason: 'live geotagging on',
    );
    expect(location.whileInUseRequests, 1);
    expect(cameras.current!.geotagOffered, isTrue);
    await pumpUntil(
      tester,
      () => app.camera.storeLocationInfo,
      reason: 'Store Location Info on',
    );
    expect(find.byKey(_offer), findsNothing);

    await app.dispose();
  });

  testWidgets('Turn on with the location refused leaves it off and says '
      "what is needed, with the way to the phone's settings", (tester) async {
    final location = FakePhoneLocation(access: _denied);
    final app = await _start(tester, location);
    final cameras = app.models.cameras;

    await _tap(tester, _turnOn);
    await _untilClosed(tester);
    await pumpUntilFound(
      tester,
      find.text("GR Photo isn't allowed to use this phone's location"),
    );
    expect(location.whileInUseRequests, 1);
    expect(cameras.current!.liveGeotagging, isFalse);
    expect(cameras.current!.geotagOffered, isTrue);

    await tapWhenReady(tester, find.text('Open settings'));
    expect(location.settingsOpened, [LocationSettingsPage.app]);
    await pumpRounds(tester, 20);
    expect(find.byKey(_offer), findsNothing);

    await app.dispose();
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('the offer mentions the notification only where the phone '
        'shows one (${platform.name})', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GeotagOfferDialog(cameraName: 'GR IV'),
        ),
      );
      await tester.pump();
      expect(find.byKey(_turnOn), findsOneWidget);
      expect(
        find.textContaining('Android shows a notification'),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      // Before the test ends: the binding checks that it was put back.
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
