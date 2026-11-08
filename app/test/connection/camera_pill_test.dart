import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/connection/camera_pill.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/pairing/pairing_flow.dart';

import '../support/test_app.dart';

const _pill = Key('camera-pill');
const _bonded = FakeCameraConfig(bonded: true);

/// A phone-sized screen with the pill at the top, without the Library.
Future<TestApp> _start(
  WidgetTester tester, {
  FakeCameraConfig config = _bonded,
  GrSessionOptions sessionOptions = const GrSessionOptions(),
  Brightness brightness = Brightness.light,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: config,
      saveCamera: true,
      sessionOptions: sessionOptions,
    ),
  ))!;
  await app.pumpWithin(
    tester,
    const Scaffold(
      body: SafeArea(
        child: Align(alignment: Alignment.topLeft, child: CameraPill()),
      ),
    ),
    brightness: brightness,
  );
  return app;
}

Future<void> _connect(WidgetTester tester, TestApp app) async {
  unawaited(app.models.connection.connect());
  await pumpUntil(
    tester,
    () => app.models.connection.status == ConnectionStatus.connected,
    reason: 'connected',
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tapWhenReady(tester, find.byKey(_pill));
  await pumpUntilFound(tester, find.byKey(const Key('camera-sheet')));
}

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

void main() {
  testWidgets('the pill follows waking and joining to Wi-Fi with battery', (
    tester,
  ) async {
    final app = await _start(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    final connection = app.models.connection;
    expect(find.text('GR IV'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    final seen = <String>[];
    void record() {
      final label = PillLinkState.of(connection).label;
      if (seen.isEmpty || seen.last != label) seen.add(label);
    }

    connection.addListener(record);
    unawaited(connection.connect());
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);

    await pumpUntilFound(tester, find.text('Waking…'));
    await pumpUntilFound(tester, find.byKey(const Key('camera-pill-battery')));
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(
      seen,
      containsAllInOrder([
        'Connecting…',
        'Waking…',
        'Wi-Fi on…',
        'Joining Wi-Fi…',
        'Wi-Fi',
      ]),
    );
    connection.removeListener(record);

    await app.dispose();
  });

  testWidgets('the sheet shows the steps, then the camera, then Connect', (
    tester,
  ) async {
    final app = await _start(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    unawaited(app.models.connection.connect());
    await _openSheet(tester);

    expect(find.byKey(const Key('camera-sheet-connecting')), findsOneWidget);
    expect(find.text('Connecting to GR IV'), findsOneWidget);
    await pumpUntilFound(tester, find.text('Waking the camera'));
    expect(find.textContaining('The first link drops'), findsOneWidget);

    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-sheet-connected')),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('camera-sheet-battery'))).data,
      '82%',
    );
    // The camera has a card and internal memory: both show, SD first.
    final sd = find.byKey(const Key('camera-sheet-storage-sd1'));
    final internal = find.byKey(const Key('camera-sheet-storage-in'));
    expect(sd, findsOneWidget);
    expect(internal, findsOneWidget);
    expect(tester.getTopLeft(sd).dy, lessThan(tester.getTopLeft(internal).dy));
    expect(find.text('No. 1234567 · fw 1.20'), findsOneWidget);

    await _tap(tester, const Key('camera-sheet-disconnect'));
    expect(app.models.connection.status, ConnectionStatus.offline);
    expect(find.byKey(const Key('camera-sheet-offline')), findsOneWidget);

    await _tap(tester, const Key('camera-sheet-connect'));
    expect(app.models.connection.status, ConnectionStatus.connecting);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-sheet-connected')),
    );

    await app.dispose();
  });

  testWidgets('the connected sheet fits a phone at large text sizes', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await _start(tester);
    await _connect(tester, app);
    await _openSheet(tester);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-sheet-storage-in')).hitTestable(),
    );
    // Layout overflows are reported as test failures; check the lines are
    // drawn inside their tile as well.
    final tile = tester.getRect(find.byKey(const Key('camera-sheet-storage')));
    for (final id in ['sd1', 'in']) {
      final line = tester.getRect(find.byKey(Key('camera-sheet-storage-$id')));
      expect(line.right, lessThanOrEqualTo(tile.right + .5));
    }

    await app.dispose();
  });

  testWidgets('forgetting the camera disconnects and removes it', (
    tester,
  ) async {
    final app = await _start(tester, brightness: Brightness.dark);
    await _connect(tester, app);
    await _openSheet(tester);

    await _tap(tester, const Key('camera-sheet-forget'));
    await pumpUntilFound(tester, find.text('Forget GR IV?'));
    await _tap(tester, const Key('camera-forget-confirm'));
    await pumpUntil(
      tester,
      () => app.models.cameras.current == null,
      reason: 'camera removed',
    );
    expect(app.models.cameras.cameras, isEmpty);
    expect(app.models.connection.status, ConnectionStatus.offline);
    expect(find.byKey(_pill), findsNothing);

    await app.dispose();
  });

  testWidgets('renaming from the sheet updates the pill', (tester) async {
    final app = await _start(tester);
    await _openSheet(tester);

    await _tap(tester, const Key('camera-sheet-rename'));
    await pumpUntilFound(tester, find.byKey(const Key('camera-rename-field')));
    await tester.enterText(
      find.byKey(const Key('camera-rename-field')),
      '  Street GR  ',
    );
    await _tap(tester, const Key('camera-rename-save'));
    await pumpUntil(
      tester,
      () => app.models.cameras.current?.name == 'Street GR',
      reason: 'renamed',
    );
    expect(find.text('Street GR'), findsWidgets);

    await app.dispose();
  });

  testWidgets('a camera that dropped the pairing leads to Pair again', (
    tester,
  ) async {
    final app = await _start(tester, config: const FakeCameraConfig());
    unawaited(app.models.connection.connect());
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.failed,
      reason: 'failed',
    );
    expect(
      app.models.connection.failure?.kind,
      ConnectFailureKind.needsPairing,
    );
    expect(find.text('Not connected'), findsOneWidget);

    await _openSheet(tester);
    expect(
      find.byKey(const Key('camera-sheet-failed-needsPairing')),
      findsOneWidget,
    );
    expect(find.text('Pair GR IV again'), findsOneWidget);

    await _tap(tester, const Key('camera-sheet-pair-again'));
    await pumpUntilFound(tester, find.byKey(const Key('pairing-find')));
    // The sheet closes before the flow opens; its exit animation ends.
    await pumpUntil(
      tester,
      () => find.byKey(const Key('camera-sheet')).evaluate().isEmpty,
      reason: 'sheet closed',
    );
    expect(find.byKey(const Key('pairing-close')), findsOneWidget);

    await _tap(tester, const Key('pairing-close'));
    await pumpUntil(tester, () => find.byType(PairingFlow).evaluate().isEmpty);
    expect(find.byKey(_pill), findsOneWidget);

    await app.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('an unreachable camera offers Try again (text ×$scale)', (
      tester,
    ) async {
      // Layout overflows at large text fail the test.
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await _start(
        tester,
        config: const FakeCameraConfig(bonded: true, unreachable: true),
        sessionOptions: const GrSessionOptions(
          scanTimeout: Duration(seconds: 1),
          bleConnectTimeout: Duration(seconds: 1),
          bleConnectAttempts: 1,
        ),
      );
      unawaited(app.models.connection.connect());
      await pumpUntil(
        tester,
        () => app.models.connection.status == ConnectionStatus.failed,
        reason: 'failed',
      );
      expect(
        app.models.connection.failure?.kind,
        ConnectFailureKind.unreachable,
      );

      await _openSheet(tester);
      expect(
        find.byKey(const Key('camera-sheet-failed-unreachable')),
        findsOneWidget,
      );
      expect(find.text("Can't reach GR IV"), findsOneWidget);

      await _tap(tester, const Key('camera-sheet-retry'));
      expect(app.models.connection.status, ConnectionStatus.connecting);
      expect(find.byKey(const Key('camera-sheet-connecting')), findsOneWidget);
      await pumpUntil(
        tester,
        () => app.models.connection.status == ConnectionStatus.failed,
        reason: 'failed again',
      );

      await app.dispose();
    });
  }
}
