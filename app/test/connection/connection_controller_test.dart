import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';

import '../support/test_app.dart';

void main() {
  test('switching cameras while connected starts a new attempt', () async {
    final app = await createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      sessionOptions: const GrSessionOptions(
        scanTimeout: Duration(milliseconds: 600),
      ),
    );
    addTearDown(app.dispose);
    final connection = app.models.connection;

    await connection.connect();
    expect(connection.status, ConnectionStatus.connected);

    // RootScreen connects in the same tick in which the camera store
    // switches cameras; the controller disconnects from the old one.
    const other = GrPairedCamera(
      deviceId: 'AA:BB:CC:DD:EE:FF',
      serialNumber: '1111111',
      modelName: 'RICOH GR IIIx',
    );
    final added = app.models.cameras.add(
      SavedCamera(paired: other, name: 'GR IIIx', pairedAt: DateTime(2026)),
    );
    final attempt = connection.connect();
    expect(connection.status, ConnectionStatus.connecting);

    await added;
    await attempt;
    // The other camera is not around, so the new attempt fails; it must
    // not be overwritten by the old camera's disconnect.
    expect(connection.status, ConnectionStatus.failed);
    expect(connection.failure?.kind, ConnectFailureKind.unreachable);
  });

  group('lost Wi-Fi', () {
    // The session notices the loss quickly and gives up at once, so every
    // loss reaches the controller.
    const sessionOptions = GrSessionOptions(
      livenessInterval: Duration(milliseconds: 100),
      livenessLossAfter: Duration(milliseconds: 400),
      maxWifiRecoveryAttempts: 0,
    );

    test('reconnects quietly instead of showing a failure', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
        sessionOptions: sessionOptions,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      await connection.connect();
      expect(connection.status, ConnectionStatus.connected);
      final seen = _record(connection);

      app.camera.dropWifi();
      await _until(() => app.ble.connects == 2);
      await _until(() => connection.status == ConnectionStatus.connected);

      expect(seen.map((s) => s.$1), isNot(contains(ConnectionStatus.failed)));
      expect(seen, contains((ConnectionStatus.connecting, true)));
      expect(connection.reconnecting, isFalse);
    });

    test('shows the failure once every quiet reconnect failed', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
        sessionOptions: sessionOptions,
        redialDelays: const [
          Duration(milliseconds: 20),
          Duration(milliseconds: 20),
        ],
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      await connection.connect();

      app.camera.dropWifi(recoverable: false);
      await _until(() => connection.status == ConnectionStatus.failed);

      expect(connection.failure?.kind, ConnectFailureKind.wifi);
      // The first connect plus one per redial.
      expect(app.ble.connects, 3);
    });

    test('waits for the app to come back before reconnecting', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
        sessionOptions: sessionOptions,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      await connection.connect();

      connection.foreground = false;
      app.camera.dropWifi();
      await _until(() => connection.status == ConnectionStatus.connecting);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(app.ble.connects, 1);
      expect(connection.reconnecting, isTrue);

      connection.foreground = true;
      await _until(() => connection.status == ConnectionStatus.connected);
      expect(app.ble.connects, 2);
    });
  });

  group('asking before the first Wi-Fi join', () {
    Future<TestApp> create() => createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      askBeforeWifiJoin: true,
    );

    test('Not now leaves the camera network alone', () async {
      final app = await create();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.connect();
      await _until(() => connection.wifiConsent != null);
      expect(connection.wifiConsent!.ssid, app.camera.config.ssid);
      connection.answerWifiConsent(false);
      await attempt;

      expect(connection.status, ConnectionStatus.failed);
      expect(connection.failure?.kind, ConnectFailureKind.wifiDeclined);
      expect(await app.camera.wifi.currentSsid(), isNull);
      expect(app.models.cameras.current!.wifiApproved, isFalse);
    });

    test('is asked once per camera', () async {
      final app = await create();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.connect();
      await _until(() => connection.wifiConsent != null);
      connection.answerWifiConsent(true);
      await attempt;
      expect(connection.status, ConnectionStatus.connected);
      expect(app.models.cameras.current!.wifiApproved, isTrue);

      await connection.disconnect();
      var asked = false;
      void listener() => asked |= connection.wifiConsent != null;
      connection.addListener(listener);
      await connection.connect();
      connection.removeListener(listener);

      expect(connection.status, ConnectionStatus.connected);
      expect(asked, isFalse);
    });

    test('cancelling while asked withdraws the question', () async {
      final app = await create();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      unawaited(connection.connect());
      await _until(() => connection.wifiConsent != null);
      await connection.disconnect();

      expect(connection.wifiConsent, isNull);
      expect(connection.status, ConnectionStatus.offline);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(connection.status, ConnectionStatus.offline);
    });
  });
}

/// Every (status, reconnecting) pair the controller notifies.
List<(ConnectionStatus, bool)> _record(ConnectionController connection) {
  final seen = <(ConnectionStatus, bool)>[];
  connection.addListener(
    () => seen.add((connection.status, connection.reconnecting)),
  );
  return seen;
}

Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('timed out after $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
