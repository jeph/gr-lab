import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';

import '../support/test_app.dart';

void main() {
  group('Bluetooth first', () {
    test('connect links Bluetooth only; the camera Wi-Fi stays off', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;

      await connection.connect();
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.inSession, isFalse);
      expect(connection.http, isNull);
      expect(app.camera.wlanOn, isFalse);
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    test('openLibrary joins Wi-Fi over the existing link; closeLibrary '
        'leaves it and keeps Bluetooth', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      await connection.connect();

      await connection.openLibrary();
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.inSession, isTrue);
      expect(app.ble.connects, 1);

      await connection.closeLibrary();
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.inSession, isFalse);
      expect(await app.camera.wifi.currentSsid(), isNull);
      expect(app.camera.wlanOn, isFalse);

      await connection.openLibrary();
      expect(connection.status, ConnectionStatus.connected);
      expect(app.ble.connects, 1);
    });

    test('openLibrary while offline links Bluetooth first', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;

      await connection.openLibrary();
      expect(connection.status, ConnectionStatus.connected);
    });
  });

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

    await connection.openLibrary();
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
    // Liveness would take far longer than any test waits, so a loss can
    // only come from the phone's report or an explicit check.
    const slowLiveness = GrSessionOptions(
      livenessInterval: Duration(seconds: 30),
      livenessLossAfter: Duration(seconds: 30),
    );

    Future<void> expectBackOnBluetooth(TestApp app) async {
      final connection = app.models.connection;
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.inSession, isFalse);
      expect(connection.failure?.kind, ConnectFailureKind.wifi);
      expect(connection.failure?.lost, isTrue);
      // Nothing rejoins by itself, and the Bluetooth link is kept.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(await app.camera.wifi.currentSsid(), isNull);
      expect(app.ble.connects, 1);
    }

    test(
      'the phone reporting the network gone ends the Wi-Fi at once',
      () async {
        final app = await createTestApp(
          config: const FakeCameraConfig(bonded: true),
          saveCamera: true,
          sessionOptions: slowLiveness,
        );
        addTearDown(app.dispose);
        final connection = app.models.connection;
        await connection.openLibrary();
        expect(connection.status, ConnectionStatus.connected);

        app.camera.dropWifi();
        await _until(
          () => connection.status == ConnectionStatus.bluetooth,
          timeout: const Duration(seconds: 2),
        );
        await expectBackOnBluetooth(app);
      },
    );

    test('without that report, liveness ends it the same way', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true, reportsWifiLoss: false),
        saveCamera: true,
        sessionOptions: const GrSessionOptions(
          livenessInterval: Duration(milliseconds: 100),
          livenessLossAfter: Duration(milliseconds: 400),
        ),
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      await connection.openLibrary();

      app.camera.dropWifi();
      await _until(() => connection.status == ConnectionStatus.bluetooth);
      await expectBackOnBluetooth(app);
    });

    test('checkWifi keeps the Wi-Fi while the camera answers and ends it '
        'when it does not', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true, reportsWifiLoss: false),
        saveCamera: true,
        sessionOptions: slowLiveness,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      await connection.openLibrary();

      expect(await connection.checkWifi(), isTrue);
      expect(connection.status, ConnectionStatus.connected);

      app.camera.dropWifi();
      expect(await connection.checkWifi(), isFalse);
      await _until(() => connection.status == ConnectionStatus.bluetooth);
      await expectBackOnBluetooth(app);
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

      final attempt = connection.openLibrary();
      await _until(() => connection.wifiConsent != null);
      expect(connection.wifiConsent!.ssid, app.camera.config.ssid);
      connection.answerWifiConsent(false);
      await attempt;

      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.failure?.kind, ConnectFailureKind.wifiDeclined);
      expect(await app.camera.wifi.currentSsid(), isNull);
      expect(app.models.cameras.current!.wifiApproved, isFalse);
    });

    test('is asked once per camera', () async {
      final app = await create();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.openLibrary();
      await _until(() => connection.wifiConsent != null);
      connection.answerWifiConsent(true);
      await attempt;
      expect(connection.status, ConnectionStatus.connected);
      expect(app.models.cameras.current!.wifiApproved, isTrue);

      await connection.disconnect();
      var asked = false;
      void listener() => asked |= connection.wifiConsent != null;
      connection.addListener(listener);
      await connection.openLibrary();
      connection.removeListener(listener);

      expect(connection.status, ConnectionStatus.connected);
      expect(asked, isFalse);
    });

    test('cancelling while asked withdraws the question', () async {
      final app = await create();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      unawaited(connection.openLibrary());
      await _until(() => connection.wifiConsent != null);
      await connection.disconnect();

      expect(connection.wifiConsent, isNull);
      expect(connection.status, ConnectionStatus.offline);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(connection.status, ConnectionStatus.offline);
    });
  });

  group("Android's network list for an approved camera", () {
    // The camera has been joined once (approved), then Android shows its
    // list again and the user backs out of it, as after the network was
    // disconnected in Wi-Fi settings.
    Future<(TestApp, _ListWifi)> approvedThenListed() async {
      late _ListWifi wifi;
      final shown = StreamController<void>.broadcast(sync: true);
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
        askBeforeWifiJoin: true,
        wifi: (camera) => wifi = _ListWifi(camera, shown),
        wifiApprovalShown: shown.stream,
      );
      addTearDown(shown.close);
      final connection = app.models.connection;
      final first = connection.openLibrary();
      await _until(() => connection.wifiConsent != null);
      connection.answerWifiConsent(true);
      await first;
      expect(connection.status, ConnectionStatus.connected);
      await connection.closeLibrary();
      expect(connection.status, ConnectionStatus.bluetooth);
      wifi.backOutOfList = 1;
      return (app, wifi);
    }

    test('explains it and Try again joins', () async {
      final (app, wifi) = await approvedThenListed();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.openLibrary();
      await _until(() => connection.wifiConsent != null);
      expect(connection.wifiConsent!.again, isTrue);
      expect(connection.wifiConsent!.ssid, app.camera.config.ssid);
      final joinsBefore = wifi.joins;
      connection.answerWifiConsent(true);
      await attempt;

      expect(connection.status, ConnectionStatus.connected);
      expect(wifi.joins, joinsBefore + 1);
    });

    test('Not now keeps Bluetooth and reports the decline', () async {
      final (app, _) = await approvedThenListed();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.openLibrary();
      await _until(() => connection.wifiConsent != null);
      connection.answerWifiConsent(false);
      await attempt;

      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.failure?.kind, ConnectFailureKind.wifiDeclined);
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    test('is not asked about on a first join', () async {
      final shown = StreamController<void>.broadcast(sync: true);
      addTearDown(shown.close);
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
        askBeforeWifiJoin: true,
        wifi: (camera) => _ListWifi(camera, shown)..backOutOfList = 1,
        wifiApprovalShown: shown.stream,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.openLibrary();
      await _until(() => connection.wifiConsent != null);
      expect(connection.wifiConsent!.again, isFalse);
      connection.answerWifiConsent(true);
      await attempt;

      expect(connection.wifiConsent, isNull);
      expect(connection.failure?.kind, ConnectFailureKind.wifiDeclined);
    });
  });
}

/// The camera's Wi-Fi, with Android's network list shown during the next
/// [backOutOfList] joins and the user backing out of it each time.
final class _ListWifi implements WifiNetworkControl {
  _ListWifi(this._camera, this._shown);

  final WifiNetworkControl _camera;
  final StreamController<void> _shown;
  int backOutOfList = 0;
  int joins = 0;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    joins++;
    if (backOutOfList > 0) {
      backOutOfList--;
      _shown.add(null);
      throw const WifiJoinDeclined('the system dialog was declined');
    }
    await _camera.join(
      ssid: ssid,
      passphrase: passphrase,
      security: security,
      timeout: timeout,
    );
  }

  @override
  Future<String?> currentSsid() => _camera.currentSsid();

  @override
  Future<void> leave() => _camera.leave();

  @override
  Stream<void> get lost => _camera.lost;
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
