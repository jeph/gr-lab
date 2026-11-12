import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/library/library_screen.dart';

import '../support/test_app.dart';

/// Liveness probes would otherwise run every 5 s of the minutes these
/// tests skip in fake time, against a camera answering in real time.
const _quietLiveness = GrSessionOptions(
  livenessInterval: Duration(hours: 1),
  livenessLossAfter: Duration(hours: 2),
);

/// The whole app with the fake GR IV paired and its Library open.
Future<TestApp> _inLibrary(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      sessionOptions: _quietLiveness,
    ),
  ))!;
  await app.pumpApp(tester);
  await tapWhenReady(tester, find.byKey(const Key('camera-card-library')));
  await pumpUntilFound(tester, find.byType(LibraryScreen));
  await pumpUntil(
    tester,
    () => app.models.connection.status == ConnectionStatus.connected,
    reason: 'Wi-Fi joined',
  );
  return app;
}

/// Waits for the Library's listing. A request still in flight when a test
/// skips minutes of fake time times out, which reads as a lost Wi-Fi.
Future<void> _untilListed(WidgetTester tester, TestApp app) => pumpUntil(
  tester,
  () => app.models.library.model.shots != null,
  reason: 'listing',
);

/// The Wi-Fi was left after [minutes] without use: the camera card's chip
/// says so, on Bluetooth.
Future<void> _expectLeft(
  WidgetTester tester,
  TestApp app, {
  int minutes = 5,
}) async {
  await pumpUntilFound(tester, find.byKey(const Key('camera-card-link-idle')));
  expect(app.models.connection.status, ConnectionStatus.bluetooth);
  expect(find.text('Left Wi-Fi after $minutes min'), findsOneWidget);
  await pumpUntil(tester, () => !app.camera.wlanOn, reason: 'WLAN off');
}

void main() {
  testWidgets("leaves the camera's Wi-Fi after 5 minutes without use, "
      'keeping Bluetooth', (tester) async {
    final app = await _inLibrary(tester);
    expect(app.models.settings.autoDisconnect, AutoDisconnect.fiveMinutes);

    await tester.pump(const Duration(minutes: 4));
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(app.models.connection.status, ConnectionStatus.connected);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await _expectLeft(tester, app);

    // The note goes once the Library is opened again.
    await tapWhenReady(tester, find.byKey(const Key('camera-card-library')));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    expect(app.models.connection.idleClosedAfter, isNull);

    await app.dispose();
  });

  testWidgets('a touch starts the wait again', (tester) async {
    final app = await _inLibrary(tester);

    await tester.pump(const Duration(minutes: 4));
    // A corner of the status bar: nothing there reacts, but it is a touch.
    await tester.tapAt(const Offset(2, 2));
    await tester.pump(const Duration(minutes: 4));
    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await _expectLeft(tester, app);

    await app.dispose();
  });

  testWidgets('a hold (download or playback) keeps the Wi-Fi until it ends', (
    tester,
  ) async {
    final app = await _inLibrary(tester);

    final release = app.models.idle.hold();
    await tester.pump(const Duration(minutes: 20));
    expect(find.byType(LibraryScreen), findsOneWidget);

    release();
    await tester.pump(const Duration(minutes: 4));
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await _expectLeft(tester, app);

    await app.dispose();
  });

  testWidgets('back on the Cameras screen the Wi-Fi stays until the app was '
      'not used for 5 minutes', (tester) async {
    final app = await _inLibrary(tester);
    await _untilListed(tester, app);

    await tapWhenReady(tester, find.byKey(const Key('camera-back')));
    await pumpUntil(
      tester,
      () => find.byType(LibraryScreen).evaluate().isEmpty,
      reason: 'camera pages closed',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-wifi')),
    );
    await tester.pump(const Duration(minutes: 4));
    expect(app.models.connection.status, ConnectionStatus.connected);
    expect(app.camera.wlanOn, isTrue);
    expect(find.byKey(const Key('camera-card-link-idle')), findsNothing);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await _expectLeft(tester, app);

    await app.dispose();
  });

  testWidgets('on a page that does not need the Wi-Fi, it is left after 5 '
      'minutes without use and the page stays', (tester) async {
    final app = await _inLibrary(tester);
    await _untilListed(tester, app);

    await tapWhenReady(tester, find.byKey(const Key('camera-tab-shoot')));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('shoot-remote')).hitTestable(),
    );
    await tester.pump(const Duration(minutes: 4));
    expect(app.models.connection.status, ConnectionStatus.connected);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await pumpUntil(tester, () => !app.camera.wlanOn, reason: 'WLAN off');
    expect(app.models.connection.status, ConnectionStatus.bluetooth);
    expect(app.models.connection.idleClosedAfter, isNull);
    expect(find.byKey(const Key('shoot-remote')).hitTestable(), findsOneWidget);

    await app.dispose();
  });

  testWidgets('Never keeps the Wi-Fi; a shorter choice applies at once', (
    tester,
  ) async {
    final app = await _inLibrary(tester);
    final settings = app.models.settings..autoDisconnect = AutoDisconnect.never;
    await tester.pump(const Duration(minutes: 30));
    expect(find.byType(LibraryScreen), findsOneWidget);

    // 30 minutes without use already passed.
    settings.autoDisconnect = AutoDisconnect.oneMinute;
    await tester.pump();
    await _expectLeft(tester, app, minutes: 1);

    await app.dispose();
  });
}
