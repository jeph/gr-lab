import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show WifiNetworkControl, WifiSecurity;
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/library/library_screen.dart';

import '../support/test_app.dart';

/// Liveness probes would otherwise run every 5 s of the time these tests
/// skip in fake time, against a camera answering in real time.
const _quietLiveness = GrSessionOptions(
  livenessInterval: Duration(hours: 1),
  livenessLossAfter: Duration(hours: 2),
);

/// The whole app with the fake GR IV paired and its Library open and
/// listed, on a phone where the camera network outlives the app (an
/// iPhone) unless [outlivesApp] is false.
Future<TestApp> _inLibrary(
  WidgetTester tester, {
  bool outlivesApp = true,
  Duration? backgroundTime = const Duration(seconds: 30),
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      sessionOptions: _quietLiveness,
      wifiOutlivesApp: outlivesApp,
      backgroundTime: backgroundTime,
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
  // A request still in flight when a test skips time times out, which
  // reads as a lost Wi-Fi.
  await pumpUntil(
    tester,
    () => app.models.library.model.shots != null,
    reason: 'listing',
  );
  return app;
}

Future<void> _expectLeft(WidgetTester tester, TestApp app) async {
  await pumpUntil(tester, () => !app.camera.wlanOn, reason: 'WLAN off');
  expect(app.models.connection.status, ConnectionStatus.bluetooth);
  await pumpUntil(
    tester,
    () => app.phone.held == 0,
    reason: 'background time given back',
  );
}

/// The camera's Wi-Fi control, with joins that never complete until the
/// network is left: as on iOS when the configuration is installed but the
/// phone has not associated yet.
final class _StalledJoins implements WifiNetworkControl {
  new(this._inner);

  final WifiNetworkControl _inner;
  Completer<void>? _join;
  bool joining = false;
  int leaves = 0;

  @override
  Stream<void> get lost => _inner.lost;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) {
    joining = true;
    return (_join = Completer<void>()).future;
  }

  @override
  Future<String?> currentSsid() => _inner.currentSsid();

  @override
  Future<void> leave() async {
    leaves++;
    joining = false;
    final join = _join;
    _join = null;
    if (join != null && !join.isCompleted) {
      join.completeError(TimeoutException('left during the join'));
    }
    await _inner.leave();
  }
}

void main() {
  testWidgets("on an iPhone, the camera's Wi-Fi is left 20 s after the app "
      'goes off screen, in background time, and the camera card says so', (
    tester,
  ) async {
    final app = await _inLibrary(tester);

    goOffScreen(tester);
    await tester.pump(const Duration(seconds: 19));
    expect(app.models.connection.status, ConnectionStatus.connected);
    expect(app.camera.wlanOn, isTrue);
    expect(app.phone.held, 1);

    await tester.pump(const Duration(seconds: 2));
    await _expectLeft(tester, app);
    expect(app.phone.granted, 1);

    comeBackOnScreen(tester);
    await pumpUntil(
      tester,
      () => find.byType(LibraryScreen).evaluate().isEmpty,
      reason: 'Library closed',
    );
    expect(find.text('Left Wi-Fi in the background'), findsOneWidget);
    expect(app.models.connection.unusedWifiLeft, const UnusedInBackground());

    await app.dispose();
  });

  testWidgets('coming back within the 20 s keeps the Wi-Fi and gives the '
      'background time back', (tester) async {
    final app = await _inLibrary(tester);

    goOffScreen(tester);
    await tester.pump(const Duration(seconds: 10));
    comeBackOnScreen(tester);
    await tester.pump(const Duration(seconds: 30));

    expect(app.models.connection.status, ConnectionStatus.connected);
    expect(app.camera.wlanOn, isTrue);
    expect(find.byType(LibraryScreen), findsOneWidget);
    await pumpUntil(
      tester,
      () => app.phone.held == 0,
      reason: 'background time given back',
    );

    await app.dispose();
  });

  testWidgets('less background time than 28 s brings the leave forward, '
      'leaving 8 s for it', (tester) async {
    final app = await _inLibrary(
      tester,
      backgroundTime: const Duration(seconds: 12),
    );

    goOffScreen(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(app.models.connection.status, ConnectionStatus.connected);

    await tester.pump(const Duration(seconds: 2));
    await _expectLeft(tester, app);

    await app.dispose();
  });

  testWidgets('work keeps the Wi-Fi off screen only while iOS keeps the app '
      'running for the download queue', (tester) async {
    final app = await _inLibrary(tester);
    final release = app.models.idle.hold();
    addTearDown(release);
    app.background.continuedTask.value = true;

    goOffScreen(tester);
    await tester.pump(const Duration(minutes: 2));
    expect(app.models.connection.status, ConnectionStatus.connected);
    // The continued processing task keeps the app running meanwhile.
    expect(app.phone.held, 0);

    app.background.continuedTask.value = false;
    await tester.pump();
    await _expectLeft(tester, app);

    await app.dispose();
  });

  testWidgets('without the continued processing task, work does not keep the '
      'Wi-Fi past the 20 s', (tester) async {
    final app = await _inLibrary(tester);
    final release = app.models.idle.hold();
    addTearDown(release);

    goOffScreen(tester);
    await tester.pump(const Duration(seconds: 19));
    expect(app.models.connection.status, ConnectionStatus.connected);

    await tester.pump(const Duration(seconds: 2));
    await _expectLeft(tester, app);

    await app.dispose();
  });

  testWidgets('where the camera network ends with the app (Android), going '
      'off screen leaves nothing early', (tester) async {
    final app = await _inLibrary(tester, outlivesApp: false);

    goOffScreen(tester);
    await tester.pump(const Duration(minutes: 1));

    expect(app.models.connection.status, ConnectionStatus.connected);
    expect(app.camera.wlanOn, isTrue);
    expect(app.phone.granted, 0);

    await app.dispose();
  });

  test('camera networks an earlier run left joined are removed at start-up '
      'where they outlive the app, and only there', () async {
    final iphone = await createTestApp(wifiOutlivesApp: true);
    expect(iphone.phone.leftoverRemovals, 1);
    await iphone.dispose();

    final android = await createTestApp();
    expect(android.phone.leftoverRemovals, 0);
    await android.dispose();
  });

  testWidgets('a join still under way when the app goes off screen is '
      'stopped 20 s later, in background time', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late _StalledJoins wifi;
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
        sessionOptions: _quietLiveness,
        wifiOutlivesApp: true,
        wifi: (camera) => wifi = _StalledJoins(camera),
      ),
    ))!;
    await app.pumpApp(tester);
    await tapWhenReady(tester, find.byKey(const Key('camera-card-library')));
    await pumpUntil(tester, () => wifi.joining, reason: 'join under way');
    final connection = app.models.connection;

    goOffScreen(tester);
    await tester.pump(const Duration(seconds: 19));
    expect(connection.status, ConnectionStatus.connecting);
    expect(connection.step, ConnectStep.wifi);
    expect(app.phone.held, 1);
    expect(wifi.leaves, 0);

    await tester.pump(const Duration(seconds: 2));
    await pumpUntil(
      tester,
      () => connection.status == ConnectionStatus.bluetooth,
      reason: 'join stopped',
    );
    expect(wifi.leaves, greaterThan(0));
    await pumpUntil(
      tester,
      () => app.phone.held == 0,
      reason: 'background time given back',
    );

    await app.dispose();
  });
}
