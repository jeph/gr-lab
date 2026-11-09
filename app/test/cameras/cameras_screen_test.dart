import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/pairing/pairing_flow.dart';

import '../support/test_app.dart';

const _cameras = Key('cameras');

/// The GR IIIx paired earlier, which is not around.
const _other = GrPairedCamera(
  deviceId: 'AA:BB:CC:DD:EE:FF',
  serialNumber: '1111111',
  modelName: 'RICOH GR IIIx',
);

/// The whole app on a phone-sized screen with the fake GR IV paired.
/// [bluetoothPermission] is what the permission request answers.
Future<TestApp> _start(
  WidgetTester tester, {
  FakeCameraConfig config = const FakeCameraConfig(bonded: true),
  GrSessionOptions sessionOptions = const GrSessionOptions(),
  List<Duration> redialDelays = const [Duration(milliseconds: 20)],
  bool withOther = false,
  bool bluetoothPermission = true,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(() async {
    final app = await createTestApp(
      config: config,
      saveCamera: true,
      sessionOptions: sessionOptions,
      redialDelays: redialDelays,
    );
    if (withOther) {
      final cameras = app.models.cameras;
      await cameras.add(
        SavedCamera(paired: _other, name: 'Street', pairedAt: DateTime(2026)),
      );
      await cameras.select(config.serial);
    }
    app.bluetoothPermission = bluetoothPermission;
    return app;
  }))!;
  await app.pumpApp(tester);
  return app;
}

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

Future<void> _untilStatus(
  WidgetTester tester,
  TestApp app,
  ConnectionStatus status,
) => pumpUntil(
  tester,
  () => app.models.connection.status == status,
  reason: status.name,
);

/// A camera that does not advertise and never answers, failing fast.
const _unreachable = FakeCameraConfig(bonded: true, unreachable: true);
const _failFast = GrSessionOptions(
  scanTimeout: Duration(seconds: 1),
  bleConnectTimeout: Duration(seconds: 1),
  bleConnectAttempts: 1,
);

/// Ends the session the way switching or forgetting the camera does, and
/// waits for the close (it runs on the fake camera's pumped timers).
Future<void> _disconnect(
  WidgetTester tester,
  ConnectionController connection,
) async {
  var closed = false;
  unawaited(connection.disconnect().whenComplete(() => closed = true));
  await pumpUntil(tester, () => closed, reason: 'session closed');
}

void main() {
  testWidgets('opens on Welcome before any camera is paired', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(createTestApp))!;
    await app.pumpApp(tester);

    expect(find.byKey(const Key('cameras-welcome')), findsOneWidget);
    // Nothing is paired, so nothing scans.
    await pumpRounds(tester, 20);
    expect(app.ble.scans, 0);

    await _tap(tester, const Key('cameras-add'));
    await pumpUntilFound(tester, find.byType(PairingFlow));
    await _tap(tester, const Key('pairing-close'));
    await pumpUntil(tester, () => find.byType(PairingFlow).evaluate().isEmpty);
    expect(find.byKey(const Key('cameras-welcome')), findsOneWidget);

    await app.dispose();
  });

  testWidgets('scans only while the app is visible', (tester) async {
    final app = await _start(tester, config: _unreachable);
    await pumpUntil(tester, () => app.ble.scanning == 1, reason: 'scanning');

    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await pumpUntil(tester, () => app.ble.scanning == 0, reason: 'stopped');

    [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await pumpUntil(tester, () => app.ble.scanning == 1, reason: 'resumed');

    await app.dispose();
  });

  group('a Bluetooth permission denied at first', () {
    Future<TestApp> denied(WidgetTester tester) async {
      final app = await _start(
        tester,
        withOther: true,
        bluetoothPermission: false,
      );
      await pumpRounds(tester, 20);
      expect(app.ble.scans, 0);
      expect(app.models.connection.status, ConnectionStatus.offline);
      return app;
    }

    /// The scan starts, and the camera nearby is linked by itself as on
    /// launch.
    Future<void> expectScanAndLink(WidgetTester tester, TestApp app) async {
      await pumpUntil(tester, () => app.ble.scanning == 1, reason: 'scan');
      await _untilStatus(tester, app, ConnectionStatus.bluetooth);
      expect(app.ble.connects, 1);
    }

    testWidgets('and granted in the system settings is used on return', (
      tester,
    ) async {
      final app = await denied(tester);

      [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpRounds(tester, 2);
      app.bluetoothPermission = true;
      [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await expectScanAndLink(tester, app);

      await app.dispose();
    });

    testWidgets('and granted on another screen is used on return', (
      tester,
    ) async {
      final app = await denied(tester);

      await _tap(tester, const Key('camera-row-1111111'));
      final details = find.byKey(const Key('camera-details'));
      await pumpUntilFound(tester, details);
      app.bluetoothPermission = true;
      Navigator.of(tester.element(details)).pop();
      await expectScanAndLink(tester, app);

      await app.dispose();
    });
  });

  testWidgets('links the nearby camera over Bluetooth by itself; Wi-Fi '
      'only for the Library, and leaving it keeps Bluetooth', (tester) async {
    final app = await _start(
      tester,
      sessionOptions: _failFast,
      withOther: true,
    );

    // The card lists the steps while it links, then offers the Library.
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-connecting')),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-bluetooth')),
    );
    expect(app.models.connection.status, ConnectionStatus.bluetooth);
    await pumpRounds(tester, 30);
    expect(app.camera.wlanOn, isFalse);
    expect(find.byType(LibraryScreen), findsNothing);

    await _tap(tester, const Key('camera-card-library'));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.connected,
      reason: 'Wi-Fi joined',
    );
    expect(app.ble.connects, 1);

    await _tap(tester, const Key('camera-pill'));
    await _tap(tester, const Key('camera-sheet-disconnect'));
    await pumpUntilFound(tester, find.byKey(_cameras));
    await pumpUntil(
      tester,
      () => find.byKey(const Key('camera-sheet')).evaluate().isEmpty,
      reason: 'sheet closed',
    );
    await pumpRounds(tester, 50);
    expect(app.models.connection.status, ConnectionStatus.bluetooth);
    expect(app.camera.wlanOn, isFalse);
    expect(app.ble.connects, 1);
    expect(find.byKey(const Key('camera-card-library')), findsOneWidget);

    await _tap(tester, const Key('camera-row-connect-1111111'));
    await pumpUntil(
      tester,
      () => app.models.cameras.current?.serial == '1111111',
      reason: 'Street current',
    );
    await _untilStatus(tester, app, ConnectionStatus.failed);
    expect(app.models.connection.failure?.kind, ConnectFailureKind.unreachable);
    expect(find.text("Can't reach Street"), findsOneWidget);
    // The GR IV moved to the other cameras.
    expect(app.models.cameras.cameras.map((c) => c.serial), [
      '1111111',
      '1234567',
    ]);

    await app.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('an unreachable camera shows the checks and Try again '
        '(text ×$scale)', (tester) async {
      // Layout overflows at large text fail the test.
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await _start(
        tester,
        config: _unreachable,
        sessionOptions: _failFast,
      );

      // Not advertising, so not nearby and not connected by itself; the
      // power button links it.
      await pumpRounds(tester, 20);
      expect(app.ble.connects, 0);
      expect(find.byKey(const Key('camera-card-link-away')), findsOneWidget);
      await _tap(tester, const Key('camera-card-power'));
      await _untilStatus(tester, app, ConnectionStatus.failed);
      await pumpUntilFound(
        tester,
        find.byKey(const Key('connect-failed-unreachable')),
      );
      expect(find.text("Can't reach GR IV"), findsOneWidget);
      expect(find.text('Action Mode is On'), findsOneWidget);
      // What the session reported, as technical detail under the checks.
      final detail = app.models.connection.failure?.detail;
      expect(detail, isNotNull);
      expect(find.text('Error: $detail'), findsOneWidget);

      await _tap(tester, const Key('connect-retry'));
      expect(app.models.connection.status, ConnectionStatus.connecting);
      expect(find.byKey(const Key('camera-card-connecting')), findsOneWidget);
      await _untilStatus(tester, app, ConnectionStatus.failed);

      await app.dispose();
    });
  }

  testWidgets('a camera that dropped the pairing leads to Pair again', (
    tester,
  ) async {
    final app = await _start(tester, config: const FakeCameraConfig());
    await _untilStatus(tester, app, ConnectionStatus.failed);
    expect(
      app.models.connection.failure?.kind,
      ConnectFailureKind.needsPairing,
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('connect-failed-needsPairing')),
    );
    expect(find.text('Pair GR IV again'), findsOneWidget);

    await _tap(tester, const Key('connect-pair-again'));
    await pumpUntilFound(tester, find.byKey(const Key('pairing-find')));
    await _tap(tester, const Key('pairing-close'));
    await pumpUntil(tester, () => find.byType(PairingFlow).evaluate().isEmpty);
    expect(find.byKey(_cameras), findsOneWidget);
    // Pairing is never retried by itself.
    expect(app.ble.connects, 1);

    await app.dispose();
  });

  testWidgets('Wi-Fi lost for good keeps the Library on Bluetooth, saying '
      'so', (tester) async {
    final app = await _start(
      tester,
      sessionOptions: const GrSessionOptions(
        livenessInterval: Duration(milliseconds: 100),
        livenessLossAfter: Duration(milliseconds: 400),
        maxWifiRecoveryAttempts: 0,
      ),
    );
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-library')));
    await _tap(tester, const Key('camera-card-library'));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.connected,
      reason: 'Wi-Fi joined',
    );

    app.camera.dropWifi(recoverable: false);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('connect-failed-wifi')).hitTestable(),
    );
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(app.models.connection.status, ConnectionStatus.bluetooth);
    expect(find.text("Lost the camera's Wi-Fi"), findsOneWidget);

    await app.dispose();
  });

  testWidgets('back from the Library returns to Cameras and leaves the '
      "camera's Wi-Fi, keeping Bluetooth", (tester) async {
    final app = await _start(tester);
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-library')));
    await _tap(tester, const Key('camera-card-library'));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.connected,
      reason: 'Wi-Fi joined',
    );

    await _tap(tester, const Key('camera-back'));
    await pumpUntil(
      tester,
      () => find.byType(LibraryScreen).evaluate().isEmpty,
    );
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-library')));
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.bluetooth,
    );
    expect(await app.camera.wifi.currentSsid(), isNull);
    expect(find.byKey(const Key('cameras-lost')), findsNothing);

    await app.dispose();
  });

  testWidgets('a camera says whether the scan sees it, and its details show '
      'its identity and pairing date', (tester) async {
    final app = await _start(tester, config: _unreachable, withOther: true);
    // The GR IIIx in the list with its model; the card's icon alone.
    await pumpUntilFound(tester, find.text('GR IIIx · looking…'));
    expect(find.byKey(const Key('camera-card-link-away')), findsOneWidget);

    await _tap(tester, const Key('camera-row-1111111'));
    await pumpUntilFound(tester, find.byKey(const Key('camera-details')));
    expect(find.text('GR IIIx · No. 1111111'), findsOneWidget);
    expect(find.text('Jan 1, 2026'), findsOneWidget);

    await app.dispose();
  });

  testWidgets('forgetting the camera while connecting ends the attempt', (
    tester,
  ) async {
    final app = await _start(
      tester,
      config: _unreachable,
      sessionOptions: const GrSessionOptions(scanTimeout: Duration(minutes: 1)),
    );
    await _tap(tester, const Key('camera-card-power'));
    await _untilStatus(tester, app, ConnectionStatus.connecting);

    await _tap(tester, const Key('camera-card-more'));
    await _tap(tester, const Key('camera-forget'));
    await pumpUntilFound(tester, find.text('Forget GR IV?'));
    await _tap(tester, const Key('camera-forget-confirm'));

    await pumpUntilFound(tester, find.byKey(const Key('cameras-welcome')));
    expect(app.models.cameras.cameras, isEmpty);
    expect(app.models.connection.status, ConnectionStatus.offline);

    await app.dispose();
  });

  testWidgets('the power button turns the camera off and on, keeping the '
      'link, and a camera turned on this way stays on', (tester) async {
    final app = await _start(tester);
    final connection = app.models.connection;
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-bluetooth')),
    );
    expect(find.byKey(const Key('camera-card-power-on')), findsOneWidget);

    await _tap(tester, const Key('camera-card-power'));
    await pumpUntil(tester, () => !app.camera.poweredOn, reason: 'off');
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-power-off')),
    );
    // The session links the camera again in its off state.
    await pumpUntil(tester, () => connection.bleLinked, reason: 'relinked');
    expect(connection.status, ConnectionStatus.bluetooth);
    expect(connection.cameraOff, isTrue);
    expect(app.camera.poweredOn, isFalse);

    await _tap(tester, const Key('camera-card-power'));
    await pumpUntil(tester, () => app.camera.poweredOn, reason: 'on');
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-power-on')));
    await pumpUntil(
      tester,
      () => connection.powerChange == null,
      reason: 'power on done',
    );
    expect(connection.cameraOff, isFalse);

    // Ending the session turns off only cameras the app woke for itself.
    await _disconnect(tester, connection);
    expect(app.camera.poweredOn, isTrue);

    await app.dispose();
  });

  testWidgets('the power button links an unlinked camera that is off and '
      'turns it on', (tester) async {
    final app = await _start(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    final connection = app.models.connection;
    await _untilStatus(tester, app, ConnectionStatus.bluetooth);
    await _disconnect(tester, connection);
    // The scan sees it nearby and switched off.
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-nearby')),
    );
    expect(find.byKey(const Key('camera-card-power-off')), findsOneWidget);

    await _tap(tester, const Key('camera-card-power'));
    await pumpUntil(tester, () => app.camera.poweredOn, reason: 'on');
    await pumpUntil(
      tester,
      () => connection.powerChange == null,
      reason: 'power on done',
    );
    expect(connection.status, ConnectionStatus.bluetooth);
    expect(find.byKey(const Key('camera-card-power-on')), findsOneWidget);

    await app.dispose();
  });
}
