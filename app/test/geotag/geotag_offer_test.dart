import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/camera_sheet.dart';
import 'package:grphoto/src/geotag/geotag_offer.dart';
import 'package:grphoto/src/theme/tokens.dart';

import '../support/test_app.dart';

const _offer = Key('geotag-offer');
const _allow = Key('geotag-offer-allow');
const _notNow = Key('geotag-offer-not-now');
const _bonded = FakeCameraConfig(bonded: true);

void _phoneScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Pumps a screen whose Open button shows [GeotagOffer] in a sheet, and
/// returns the answers the sheet closed with, oldest first.
Future<List<bool?>> _pumpOffer(WidgetTester tester) async {
  _phoneScreen(tester);
  final answers = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: grTheme(GrColors.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const GeotagOffer(),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  return answers;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// The whole app with a saved camera linked over Bluetooth: one that has
/// not been asked about geotagging unless [liveGeotagging] says what its
/// user chose. [location] is what the phone allows, and
/// [locationAfterRequest] what it allows once asked.
Future<TestApp> _startLinked(
  WidgetTester tester, {
  FakeCameraConfig config = _bonded,
  bool? liveGeotagging,
  LocationAccess location = LocationAccess.precise,
  LocationAccess? locationAfterRequest,
}) async {
  _phoneScreen(tester);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: config,
      saveCamera: true,
      liveGeotagging: liveGeotagging,
      location: location,
      locationAfterRequest: locationAfterRequest,
    ),
  ))!;
  await app.pumpApp(tester);
  unawaited(app.models.connection.connect());
  await pumpUntil(
    tester,
    () => app.models.connection.cameraSession?.bleLinked ?? false,
    reason: 'linked',
  );
  return app;
}

/// Opens the camera sheet over the whole app's current screen.
Future<void> _openSheet(WidgetTester tester, TestApp app) async {
  unawaited(showCameraSheet(app.models.routes.navigator!.context));
  await pumpUntilFound(tester, find.byKey(const Key('camera-sheet-geotag')));
}

PhoneFix _fix() => PhoneFix(
  latitude: 35,
  longitude: 135,
  altitude: 40,
  accuracy: 8,
  time: DateTime.now().toUtc(),
);

void main() {
  testWidgets('the offer closes with true for Allow location and false for '
      'Not now', (tester) async {
    final answers = await _pumpOffer(tester);
    await _open(tester);
    expect(find.text('Add locations to your photos?'), findsOneWidget);
    await tester.tap(find.byKey(_allow));
    await tester.pumpAndSettle();
    expect(answers, [true]);

    await _open(tester);
    await tester.tap(find.byKey(_notNow));
    await tester.pumpAndSettle();
    expect(answers, [true, false]);

    // Closed by a tap beside it: no answer, which counts as Not now.
    await _open(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(answers, [true, false, null]);
  });

  testWidgets('the offer mentions the notification on Android only', (
    tester,
  ) async {
    final notification = find.textContaining('Android shows a notification');
    await _pumpOffer(tester);
    await _open(tester);
    expect(notification, findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _open(tester);
    expect(find.byKey(_offer), findsOneWidget);
    expect(notification, findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the offer fits at the largest text size', (tester) async {
    await _pumpOffer(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(_notNow));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_notNow));
    await tester.pumpAndSettle();
    expect(find.byKey(_offer), findsNothing);
  });

  testWidgets('the offer keeps its buttons above the system navigation '
      'area', (tester) async {
    await _pumpOffer(tester);
    // 34 logical pixels at the bottom of the 844 high screen.
    tester.view.viewPadding = const FakeViewPadding(bottom: 102);
    tester.view.padding = const FakeViewPadding(bottom: 102);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    await _open(tester);
    // 24 of padding under the button, above the area.
    expect(tester.getRect(find.byKey(_notNow)).bottom, 844 - 34 - 24);
    await tester.tap(find.byKey(_notNow));
    await tester.pumpAndSettle();
  });

  testWidgets('a linked camera that was never asked gets the offer once, '
      'and Not now saves the answer', (tester) async {
    final app = await _startLinked(tester);
    final cameras = app.models.cameras;
    expect(cameras.current!.liveGeotagging, isNull);
    await pumpUntilFound(tester, find.byKey(_offer));
    expect(find.byKey(_offer), findsOneWidget);

    await tapWhenReady(tester, find.byKey(_notNow));
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging == false,
      reason: 'answer saved',
    );
    expect(app.models.geotag.offerDue, isFalse);
    await pumpRounds(tester, 20);
    expect(find.byKey(_offer), findsNothing);
    await app.dispose();
  });

  testWidgets('closing the offer without an answer counts as Not now, and '
      'it does not come back', (tester) async {
    final app = await _startLinked(tester);
    final cameras = app.models.cameras;
    await pumpUntilFound(tester, find.byKey(_offer));
    await pumpRounds(tester, 20);
    await tester.tapAt(const Offset(20, 20));
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging == false,
      reason: 'answer saved',
    );
    await pumpRounds(tester, 20);
    expect(find.byKey(_offer), findsNothing);
    await app.dispose();
  });

  testWidgets('Allow location asks the phone, turns live geotagging on and '
      "the phone's location reaches the camera", (tester) async {
    final app = await _startLinked(
      tester,
      location: LocationAccess.undetermined,
      locationAfterRequest: LocationAccess.precise,
    );
    final cameras = app.models.cameras;
    await tapWhenReady(tester, find.byKey(_allow));
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging ?? false,
      reason: 'answer saved',
    );
    expect(app.phone.requests, 1);
    await pumpUntil(
      tester,
      () => app.models.geotag.status == GeotagStatus.waitingForLocation,
      reason: 'phone located',
    );
    expect(app.camera.storeLocationInfo, isTrue);
    expect(find.byType(SnackBar), findsNothing);

    app.phone.emit(_fix());
    await pumpUntil(
      tester,
      () => app.camera.location != null,
      reason: 'location sent',
    );
    expect(app.models.geotag.status, GeotagStatus.sending);
    await app.dispose();
  });

  testWidgets('a refused location prompt after Allow location leaves it '
      'off and says so, and the offer does not come back', (tester) async {
    final app = await _startLinked(
      tester,
      location: LocationAccess.undetermined,
      locationAfterRequest: LocationAccess.blocked,
    );
    final cameras = app.models.cameras;
    await tapWhenReady(tester, find.byKey(_allow));
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging == false,
      reason: 'answer saved',
    );
    await pumpUntilFound(
      tester,
      find.text("Location wasn't allowed, so Geotagging is off."),
    );
    await pumpRounds(tester, 20);
    expect(find.byKey(_offer), findsNothing);
    expect(app.phone.running, isFalse);
    expect(app.camera.storeLocationInfo, isFalse);
    await app.dispose();
  });

  testWidgets("the camera sheet's switch, refused the phone's location, "
      'says what is missing, opens the settings, and turns on once the user '
      'is back having allowed it', (tester) async {
    final app = await _startLinked(
      tester,
      liveGeotagging: false,
      location: LocationAccess.undetermined,
      locationAfterRequest: LocationAccess.blocked,
    );
    final cameras = app.models.cameras;
    await _openSheet(tester, app);
    expect(find.text('Off'), findsOneWidget);

    await tapWhenReady(
      tester,
      find.byKey(const Key('camera-sheet-geotag-switch')),
    );
    await pumpUntilFound(tester, find.text('Allow location for GR Photo'));
    expect(cameras.current!.liveGeotagging, isFalse);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('camera-sheet-geotag-switch')))
          .value,
      isFalse,
    );

    await tapWhenReady(
      tester,
      find.byKey(const Key('camera-sheet-geotag-settings')),
    );
    await pumpUntil(
      tester,
      () => app.phone.settingsOpened == 1,
      reason: 'settings opened',
    );

    // Allowed in the system settings, then back in the app.
    app.phone
      ..accessAfterRequest = null
      ..currentAccess = LocationAccess.precise;
    app.models.connection.foreground = false;
    await tester.pump();
    app.models.connection.foreground = true;
    await pumpUntil(
      tester,
      () => cameras.current!.liveGeotagging ?? false,
      reason: 'turned on',
    );
    await pumpUntilFound(tester, find.text("Finding this phone's location…"));
    expect(app.camera.storeLocationInfo, isTrue);
    await app.dispose();
  });

  testWidgets('Store Location Info turned off on the camera shows in the '
      'camera sheet, with a button that turns it on again', (tester) async {
    final app = await _startLinked(tester, liveGeotagging: true);
    await _openSheet(tester, app);
    await pumpUntilFound(
      tester,
      find.text('Store Location Info is off on the camera'),
    );

    await tapWhenReady(
      tester,
      find.byKey(const Key('camera-sheet-geotag-turn-on')),
    );
    await pumpUntil(
      tester,
      () => app.camera.storeLocationInfo,
      reason: 'setting written',
    );
    await pumpUntilFound(tester, find.text("Finding this phone's location…"));

    await tapWhenReady(
      tester,
      find.byKey(const Key('camera-sheet-geotag-switch')),
    );
    await pumpUntil(
      tester,
      () => !app.camera.storeLocationInfo,
      reason: 'turned off on the camera',
    );
    expect(app.models.cameras.current!.liveGeotagging, isFalse);
    await pumpUntil(tester, () => !app.phone.running, reason: 'run ended');
    await app.dispose();
  });

  testWidgets('no offer while the app is not in front', (tester) async {
    _phoneScreen(tester);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: _bonded,
        saveCamera: true,
        liveGeotagging: null,
      ),
    ))!;
    await app.pumpApp(tester);
    final connection = app.models.connection..foreground = false;
    unawaited(connection.connect());
    await pumpUntil(
      tester,
      () => app.models.geotag.offerDue,
      reason: 'offer due',
    );
    await pumpRounds(tester, 20);
    expect(find.byKey(_offer), findsNothing);

    connection.foreground = true;
    await pumpUntilFound(tester, find.byKey(_offer));
    await tapWhenReady(tester, find.byKey(_notNow));
    await pumpRounds(tester, 20);
    await app.dispose();
  });

  testWidgets('the camera sheet has the Geotagging and Sync time rows, and '
      'its Sync time switch saves the choice', (tester) async {
    _phoneScreen(tester);
    final app = (await tester.runAsync(
      () => createTestApp(config: _bonded, saveCamera: true),
    ))!;
    await app.pumpWithin(tester, const Scaffold(body: CameraSheet()));
    final cameras = app.models.cameras;
    expect(find.text('LOCATION AND TIME'), findsOneWidget);
    expect(find.byKey(const Key('camera-sheet-geotag')), findsOneWidget);
    expect(find.byKey(const Key('camera-sheet-sync-time')), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(cameras.current!.syncTime, isTrue);

    await tapWhenReady(
      tester,
      find.byKey(const Key('camera-sheet-sync-time-switch')),
    );
    await pumpUntil(
      tester,
      () => !cameras.current!.syncTime,
      reason: 'sync time saved',
    );
    await tester.pump();
    expect(
      tester
          .widget<Switch>(
            find.byKey(const Key('camera-sheet-sync-time-switch')),
          )
          .value,
      isFalse,
    );
    await app.dispose();
  });
}
