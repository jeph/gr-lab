import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/library/library_screen.dart';

import '../support/test_app.dart';

/// Liveness probes would otherwise run every 500 ms of the minutes these
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
  return app;
}

Future<void> _expectLeft(WidgetTester tester, TestApp app) async {
  await pumpUntilFound(tester, find.byKey(const Key('cameras-idle')));
  expect(app.models.connection.status, ConnectionStatus.bluetooth);
  expect(
    find.text(
      "GR Lab wasn't used for 5 minutes. Tap Library to join "
      'again.',
    ),
    findsOneWidget,
  );
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

  testWidgets('Never keeps the Wi-Fi; a shorter choice applies at once', (
    tester,
  ) async {
    final app = await _inLibrary(tester);
    final settings = app.models.settings;

    settings.autoDisconnect = AutoDisconnect.never;
    await tester.pump(const Duration(minutes: 30));
    expect(find.byType(LibraryScreen), findsOneWidget);

    // 30 minutes without use already passed.
    settings.autoDisconnect = AutoDisconnect.oneMinute;
    await tester.pump();
    await pumpUntilFound(tester, find.byKey(const Key('cameras-idle')));
    expect(
      find.text(
        "GR Lab wasn't used for 1 minute. Tap Library to join "
        'again.',
      ),
      findsOneWidget,
    );

    await app.dispose();
  });
}
