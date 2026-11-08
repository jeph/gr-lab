import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/connection/connection_controller.dart';

import '../support/test_app.dart';

const _sheet = Key('camera-sheet');
const _dialog = Key('wifi-consent');

/// The whole app with a paired camera, the camera sheet open and the
/// question about the camera's Wi-Fi on top of it.
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
  await tapWhenReady(tester, find.byKey(const Key('camera-pill')));
  await pumpUntilFound(tester, find.byKey(_sheet));
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
  testWidgets('Continue closes only the question', (tester) async {
    final app = await _asked(tester);
    await _answer(tester, const Key('wifi-consent-join'));

    expect(find.byKey(_sheet), findsOneWidget);
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.connected,
      reason: 'connected',
    );
    expect(find.byKey(_sheet), findsOneWidget);
    await app.dispose();
  });

  testWidgets('Not now closes only the question', (tester) async {
    final app = await _asked(tester);
    await _answer(tester, const Key('wifi-consent-later'));

    expect(find.byKey(_sheet), findsOneWidget);
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.failed,
      reason: 'failed',
    );
    expect(find.byKey(_sheet), findsOneWidget);
    expect(
      app.models.connection.failure?.kind,
      ConnectFailureKind.wifiDeclined,
    );
    await app.dispose();
  });

  testWidgets('Join Wi-Fi after Not now asks again over the sheet', (
    tester,
  ) async {
    final app = await _asked(tester);
    await _answer(tester, const Key('wifi-consent-later'));
    await tapWhenReady(tester, find.byKey(const Key('camera-sheet-retry')));
    await pumpUntilFound(tester, find.byKey(_dialog));
    await _answer(tester, const Key('wifi-consent-join'));

    expect(find.byKey(_sheet), findsOneWidget);
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.connected,
      reason: 'connected',
    );
    expect(find.byKey(_sheet), findsOneWidget);
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

    expect(find.byKey(_sheet), findsOneWidget);
    await app.dispose();
  });
}
