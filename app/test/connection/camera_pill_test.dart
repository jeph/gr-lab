import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/connection/camera_pill.dart';
import 'package:grlab/src/connection/connection_controller.dart';

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
  unawaited(app.models.connection.openCamera(CameraTab.library));
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
  testWidgets('the pill shows the Bluetooth link, then joining Wi-Fi and '
      'the battery', (tester) async {
    final app = await _start(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    final connection = app.models.connection;
    expect(find.text('GR IV'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    final seen = <PillLinkLabel>[];
    void record() {
      final label = PillLinkState.of(connection).label;
      if (seen.isEmpty || seen.last != label) seen.add(label);
    }

    connection.addListener(record);
    unawaited(connection.connect());
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);
    await pumpUntilFound(tester, find.text('Bluetooth'));

    unawaited(connection.openCamera(CameraTab.library));
    await pumpUntilFound(tester, find.byKey(const Key('camera-pill-battery')));
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(seen, [
      PillLinkLabel.connecting,
      PillLinkLabel.bluetooth,
      PillLinkLabel.connectingWifi,
      PillLinkLabel.wifi,
    ]);
    connection.removeListener(record);

    await app.dispose();
  });

  testWidgets('the connected sheet shows the camera; Disconnect Wi-Fi keeps '
      'Bluetooth', (tester) async {
    final app = await _start(tester);
    await _connect(tester, app);
    await _openSheet(tester);

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
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.bluetooth,
      reason: 'back on Bluetooth',
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
}
