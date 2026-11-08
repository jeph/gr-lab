import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/library/library_screen.dart';

import '../support/test_app.dart';

const _cameras = Key('cameras');
const _dialog = Key('wifi-consent');

/// The whole app with a paired camera nearby: the Cameras screen connects
/// to it and asks before the first join of its Wi-Fi.
Future<TestApp> _asked(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      askBeforeWifiJoin: true,
    ),
  ))!;
  await app.pumpApp(tester);
  await pumpUntilFound(tester, find.byKey(_dialog));
  return app;
}

Future<void> _answer(WidgetTester tester, Key button) async {
  await tester.tap(find.byKey(button));
  // Frame by frame, as on a device: the question rebuilds while it
  // animates out.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await pumpUntil(
    tester,
    () => find.byKey(_dialog).evaluate().isEmpty,
    reason: 'the question to close',
  );
  await _pastAnimations(tester);
}

/// Lets route transitions finish; the connecting spinner never settles.
Future<void> _pastAnimations(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Continue joins and hands over to the Library', (tester) async {
    final app = await _asked(tester);
    await _answer(tester, const Key('wifi-consent-join'));

    expect(find.byKey(_cameras), findsOneWidget);
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    expect(app.models.connection.status, ConnectionStatus.connected);
    expect(app.models.cameras.current?.wifiApproved, isTrue);
    await app.dispose();
  });

  testWidgets('Not now leaves the camera card showing the decline', (
    tester,
  ) async {
    final app = await _asked(tester);
    await _answer(tester, const Key('wifi-consent-later'));

    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.failed,
      reason: 'failed',
    );
    expect(
      app.models.connection.failure?.kind,
      ConnectFailureKind.wifiDeclined,
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-failed-wifiDeclined')),
    );
    expect(find.byKey(_cameras), findsOneWidget);
    await app.dispose();
  });

  testWidgets('Join Wi-Fi after Not now asks again', (tester) async {
    final app = await _asked(tester);
    await _answer(tester, const Key('wifi-consent-later'));
    await tapWhenReady(tester, find.byKey(const Key('camera-card-retry')));
    await pumpUntilFound(tester, find.byKey(_dialog));
    await _answer(tester, const Key('wifi-consent-join'));

    await pumpUntilFound(tester, find.byType(LibraryScreen));
    expect(app.models.connection.status, ConnectionStatus.connected);
    await app.dispose();
  });

  testWidgets('a cancelled attempt withdraws the question', (tester) async {
    final app = await _asked(tester);
    await tester.runAsync(app.models.connection.disconnect);
    await pumpUntil(
      tester,
      () => find.byKey(_dialog).evaluate().isEmpty,
      reason: 'the question to close',
    );
    await _pastAnimations(tester);

    expect(find.byKey(_cameras), findsOneWidget);
    expect(app.models.connection.status, ConnectionStatus.offline);
    await app.dispose();
  });
}
