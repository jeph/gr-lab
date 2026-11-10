import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/camera/camera_top_bar.dart';
import 'package:grlab/src/connection/camera_pill.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/looks/looks_screen.dart';
import 'package:grlab/src/pairing/pairing_flow.dart';
import 'package:grlab/src/shoot/shoot_screen.dart';

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

/// A camera whose lost Bluetooth link counts as gone after 1.5 s; only
/// that time ends the reconnect.
const _goneSoon = GrSessionOptions(
  bleReconnectDelays: [Duration(milliseconds: 100)],
  maxBleReconnectAttempts: 1000,
  bleLostAfter: Duration(milliseconds: 1500),
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

/// The opacity the card's link icon is drawn at while it shows [link].
double _iconOpacity(WidgetTester tester, String link) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byKey(Key('camera-card-link-$link')),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

/// The lowest opacity the card's link icon is drawn at over the next
/// 400 ms while it shows [link]: below 1 while it pulses.
Future<double> _dimmestIcon(WidgetTester tester, String link) async {
  var dimmest = _iconOpacity(tester, link);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    dimmest = math.min(dimmest, _iconOpacity(tester, link));
  }
  return dimmest;
}

/// The opacity the card's foot draws [key] at: below 1 while it comes in.
double _footOpacity(WidgetTester tester, Key key) => tester
    .widget<FadeTransition>(
      find
          .ancestor(of: find.byKey(key), matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;

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

  testWidgets('stops scanning while the home dock shows the saved looks', (
    tester,
  ) async {
    final app = await _start(tester, config: _unreachable);
    await pumpUntil(tester, () => app.ble.scanning == 1, reason: 'scanning');

    await _tap(tester, const Key('home-tab-looks'));
    await pumpUntil(tester, () => app.ble.scanning == 0, reason: 'stopped');

    await _tap(tester, const Key('home-tab-cameras'));
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

    // While it links, the card's icon stands for the steps and Cancel for
    // the buttons to the camera's pages.
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-bluetoothConnecting')),
    );
    expect(find.byKey(const Key('camera-card-cancel')), findsOneWidget);
    expect(find.textContaining('Connecting'), findsNothing);

    // Once linked, the buttons fade in rather than replace it at once.
    const library = Key('camera-card-library');
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-bluetooth')),
    );
    expect(_footOpacity(tester, library), lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_footOpacity(tester, library), 1);
    expect(find.byKey(const Key('camera-card-cancel')), findsNothing);
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
      // The card shrinks to Cancel, and the list scrolls back to it; the
      // icon pulses for as long as the attempt runs.
      await pumpUntilFound(
        tester,
        find.byKey(const Key('camera-card-link-bluetoothConnecting')),
      );
      expect(find.byKey(const Key('camera-card-cancel')), findsOneWidget);
      expect(await _dimmestIcon(tester, 'bluetoothConnecting'), lessThan(1));
      await _untilStatus(tester, app, ConnectionStatus.failed);

      await app.dispose();
    });
  }

  testWidgets('with less motion asked for, the linking icon is still and the '
      "card's buttons change at once", (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final app = await _start(
      tester,
      config: _unreachable,
      sessionOptions: _failFast,
    );
    await pumpRounds(tester, 20);
    expect(find.byKey(const Key('camera-card-library')), findsOneWidget);

    await _tap(tester, const Key('camera-card-power'));
    expect(
      find.byKey(const Key('camera-card-link-bluetoothConnecting')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('camera-card-cancel')), findsOneWidget);
    expect(find.byKey(const Key('camera-card-library')), findsNothing);
    expect(await _dimmestIcon(tester, 'bluetoothConnecting'), 1);
    await _untilStatus(tester, app, ConnectionStatus.failed);

    await app.dispose();
  });

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

  testWidgets('back from the Library returns to Cameras with the '
      "camera's Wi-Fi still up", (tester) async {
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
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-wifi')),
    );
    expect(_iconOpacity(tester, 'wifi'), 1);
    await pumpRounds(tester, 30);
    expect(app.models.connection.status, ConnectionStatus.connected);
    expect(await app.camera.wifi.currentSsid(), app.camera.config.ssid);
    expect(find.byKey(const Key('cameras-lost')), findsNothing);

    await app.dispose();
  });

  testWidgets('Settings sits on the title row of Cameras and the Library', (
    tester,
  ) async {
    void expectOnTitleRow(String title, Key settings) {
      final titleRect = tester.getRect(
        find.descendant(of: find.byType(PageTitle), matching: find.text(title)),
      );
      final button = tester.getRect(find.byKey(settings));
      expect(
        button.center.dy,
        moreOrLessEquals(titleRect.center.dy, epsilon: 1),
      );
      expect(button.left, greaterThan(titleRect.right));
    }

    final app = await _start(tester);
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-library')));
    expectOnTitleRow('Cameras', const Key('cameras-settings'));

    await _tap(tester, const Key('camera-card-library'));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    expectOnTitleRow('Library', const Key('camera-settings'));

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

  testWidgets('forgetting the only camera returns to Welcome and deletes its '
      'cached listing, images and download records', (tester) async {
    final app = await _start(tester);
    final serial = app.models.cameras.current!.serial;
    final folder = Directory('${app.models.services.cacheDir.path}/$serial');
    final downloads = app.models.downloads;
    await _tap(tester, const Key('camera-card-library'));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    final library = app.models.library.model;
    await pumpUntil(
      tester,
      () => library.shots?.isNotEmpty ?? false,
      reason: 'listing',
    );
    final shot = library.shots!.first;
    unawaited(downloads.enqueue(serial, [shot]));
    await pumpUntil(
      tester,
      () => downloads.isShotDownloaded(serial, shot),
      reason: 'downloaded',
    );
    await pumpUntil(
      tester,
      () =>
          File('${folder.path}/library.json').existsSync() &&
          folder.listSync(recursive: true).any((e) => e.path.endsWith('.jpg')),
      reason: 'listing and images cached',
    );

    await _tap(tester, const Key('camera-back'));
    await _tap(tester, const Key('camera-card-more'));
    await _tap(tester, const Key('camera-forget'));
    await _tap(tester, const Key('camera-forget-confirm'));

    await pumpUntilFound(tester, find.byKey(const Key('cameras-welcome')));
    expect(find.byKey(const Key('cameras-add')), findsOneWidget);
    await pumpUntil(tester, () => !folder.existsSync(), reason: 'deleted');
    expect(downloads.isShotDownloaded(serial, shot), isFalse);
    expect(library.shots, isNull);

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

  testWidgets('a screen reader can press the power button, which is disabled '
      'while it works', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await _start(tester);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-bluetooth')),
    );
    final button = find.byKey(const Key('camera-card-power'));
    expect(
      tester.getSemantics(button),
      isSemantics(
        label: 'Turn GR IV off',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );

    tester.semantics.tap(find.semantics.byLabel('Turn GR IV off'));
    await tester.pump();
    expect(
      tester.getSemantics(button),
      isSemantics(
        label: 'Turn GR IV off',
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    await pumpUntil(tester, () => !app.camera.poweredOn, reason: 'off');

    await app.dispose();
    semantics.dispose();
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

  testWidgets('while the Wi-Fi is joined the card shows the Wi-Fi alone, '
      'pulsing, also when the wake drops the Bluetooth link under it', (
    tester,
  ) async {
    final app = await _start(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    final connection = app.models.connection;
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-bluetooth')),
    );

    // With the camera's pages closed, as for work that goes on without
    // them.
    unawaited(connection.joinWifi());
    final joining = find.byKey(const Key('camera-card-link-wifiConnecting'));
    await pumpUntilFound(tester, joining);
    await pumpUntil(
      tester,
      () => connection.cameraSession?.bleLinked == false,
      reason: 'the wake dropped the link',
    );
    expect(connection.status, ConnectionStatus.connecting);
    expect(joining, findsOneWidget);
    expect(await _dimmestIcon(tester, 'wifiConnecting'), lessThan(1));

    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-wifi')),
    );
    expect(_iconOpacity(tester, 'wifi'), 1);

    await app.dispose();
  });

  testWidgets('a camera gone while only Bluetooth links it shows as '
      'reconnecting on its pages, then the app returns to Cameras and says '
      'it was lost', (tester) async {
    final app = await _start(tester, sessionOptions: _goneSoon);
    final connection = app.models.connection;
    await _tap(tester, const Key('camera-card-shoot'));
    await pumpUntilFound(tester, find.byType(ShootScreen));
    await pumpUntil(tester, () => connection.bleLinked, reason: 'linked');

    app.camera.powerOffFully();
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(CameraPill),
        matching: find.text('Reconnecting…'),
      ),
    );

    await _untilStatus(tester, app, ConnectionStatus.failed);
    await pumpUntil(
      tester,
      () => find.byType(ShootScreen).evaluate().isEmpty,
      reason: "the camera's pages closed",
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('cameras-lost')).hitTestable(),
    );
    expect(connection.failure?.loss, ConnectLoss.bluetooth);

    await app.dispose();
  });

  testWidgets('a camera gone while the home dock shows the saved looks '
      'leaves them in front', (tester) async {
    final app = await _start(tester, sessionOptions: _goneSoon);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('camera-card-link-bluetooth')),
    );
    await _tap(tester, const Key('home-tab-looks'));

    app.camera.powerOffFully();
    await _untilStatus(tester, app, ConnectionStatus.failed);
    await pumpRounds(tester, 20);
    expect(find.byType(LooksScreen).hitTestable(), findsOneWidget);

    await app.dispose();
  });
}
