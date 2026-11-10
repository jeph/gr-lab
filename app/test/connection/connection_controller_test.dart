import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show
        BleAdapterState,
        BleAdvertisement,
        BleConnection,
        BleDisconnect,
        BleServiceInfo,
        BleTransport,
        WifiJoinDeclined,
        WifiJoinVpnSuspected,
        WifiNetworkControl,
        WifiSecurity;
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/connection/link_state.dart';
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
      expect(connection.cameraSession?.library, isNull);
      expect(app.camera.wlanOn, isFalse);
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    test('opening the Library joins Wi-Fi over the existing link; closing '
        'the pages keeps it, and disconnectWifi leaves it with Bluetooth '
        'kept', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      await connection.connect();

      await connection.openCamera(CameraTab.library);
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.inSession, isTrue);
      expect(app.ble.connects, 1);
      final library = connection.cameraSession!.library;

      await connection.closeCamera();
      expect(connection.tab, isNull);
      expect(connection.status, ConnectionStatus.connected);
      expect(await app.camera.wifi.currentSsid(), app.camera.config.ssid);
      expect(app.camera.wlanOn, isTrue);

      // The Library opens again on the join it left: one library per join.
      await connection.openCamera(CameraTab.library);
      expect(connection.cameraSession!.library, same(library));

      await connection.disconnectWifi();
      expect(connection.tab, isNull);
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.inSession, isFalse);
      expect(await app.camera.wifi.currentSsid(), isNull);
      expect(app.camera.wlanOn, isFalse);

      await connection.openCamera(CameraTab.library);
      expect(connection.status, ConnectionStatus.connected);
      expect(app.ble.connects, 1);
    });

    test('a join still under way stops when the pages close, and when live '
        'view goes back to Remote', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;
      Future<void> untilJoining() =>
          _until(() => connection.step == ConnectStep.wifi);
      Future<void> expectLeft() async {
        expect(connection.status, ConnectionStatus.bluetooth);
        expect(connection.failure, isNull);
        expect(await app.camera.wifi.currentSsid(), isNull);
        expect(app.camera.wlanOn, isFalse);
      }

      final opening = connection.openCamera(CameraTab.library);
      await untilJoining();
      await connection.closeCamera();
      await opening;
      expect(connection.tab, isNull);
      await expectLeft();

      await connection.openCamera(CameraTab.shoot);
      final joining = connection.joinWifi();
      await untilJoining();
      await connection.cancelWifiJoin();
      await joining;
      expect(connection.tab, CameraTab.shoot);
      await expectLeft();
    });

    test('opening the Library while offline links Bluetooth first', () async {
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      );
      addTearDown(app.dispose);
      final connection = app.models.connection;

      await connection.openCamera(CameraTab.library);
      expect(connection.status, ConnectionStatus.connected);
    });
  });

  group('Wi-Fi asked for while Bluetooth links', () {
    /// A paired camera that is off, behind a transport whose connect waits
    /// for the test.
    Future<(TestApp, _GatedTransport)> gated() async {
      late _GatedTransport ble;
      final app = await createTestApp(
        config: const FakeCameraConfig(bonded: true, poweredOn: false),
        saveCamera: true,
        transport: (camera) => ble = _GatedTransport(camera),
      );
      addTearDown(app.dispose);
      ble.linkGate = Completer<void>();
      return (app, ble);
    }

    /// Records whether a Wi-Fi start ever began.
    bool Function() watchWifiStart(ConnectionController connection) {
      var started = false;
      void listener() => started |= connection.step == ConnectStep.wifi;
      connection.addListener(listener);
      addTearDown(() => connection.removeListener(listener));
      return () => started;
    }

    test('closing the pages before the link is up cancels the Library '
        'join', () async {
      final (app, ble) = await gated();
      final connection = app.models.connection;
      final wifiStarted = watchWifiStart(connection);

      final opening = connection.openCamera(CameraTab.library);
      await ble.connectCalled.future;
      await connection.closeCamera();
      ble.linkGate!.complete();
      await opening;

      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.tab, isNull);
      expect(wifiStarted(), isFalse);
      expect(app.camera.poweredOn, isFalse);
      expect(app.camera.wlanOn, isFalse);
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    test('opening the Library again after closing it still joins', () async {
      final (app, ble) = await gated();
      final connection = app.models.connection;

      final first = connection.openCamera(CameraTab.library);
      await ble.connectCalled.future;
      await connection.closeCamera();
      final again = connection.openCamera(CameraTab.library);
      ble.linkGate!.complete();
      await Future.wait([first, again]);

      expect(connection.status, ConnectionStatus.connected);
      expect(connection.tab, CameraTab.library);
    });

    test('switching to the Library joins once the link is up', () async {
      final (app, ble) = await gated();
      final connection = app.models.connection;

      final opening = connection.openCamera(CameraTab.shoot);
      await ble.connectCalled.future;
      connection.selectTab(CameraTab.library);
      final up = connection.wifiUp.first;
      ble.linkGate!.complete();
      await opening;
      expect(connection.status, ConnectionStatus.connecting);
      expect(connection.step, ConnectStep.wifi);

      await up;
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.tab, CameraTab.library);
    });

    test('switching away again before the link is up cancels that '
        'join', () async {
      final (app, ble) = await gated();
      final connection = app.models.connection;
      final wifiStarted = watchWifiStart(connection);

      final opening = connection.openCamera(CameraTab.shoot);
      await ble.connectCalled.future;
      connection
        ..selectTab(CameraTab.library)
        ..selectTab(CameraTab.shoot);
      ble.linkGate!.complete();
      await opening;

      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.tab, CameraTab.shoot);
      expect(wifiStarted(), isFalse);
      expect(app.camera.wlanOn, isFalse);
    });
  });

  test('a new link waits for a close still releasing the last one, '
      'through a second disconnect', () async {
    late _GatedTransport ble;
    final app = await createTestApp(
      config: const FakeCameraConfig(bonded: true),
      saveCamera: true,
      transport: (camera) => ble = _GatedTransport(camera),
    );
    addTearDown(app.dispose);
    final connection = app.models.connection;
    await connection.connect();
    expect(connection.status, ConnectionStatus.bluetooth);

    // Switching away while the camera's link is slow to close, then
    // cancelling the attempt that waits for it and linking again.
    final closeGate = ble.closeGate = Completer<void>();
    final closed = connection.disconnect();
    await ble.disconnectCalled.future;
    unawaited(connection.connect());
    unawaited(connection.disconnect());
    final again = connection.connect();
    final checks = ble.adapterChecks;
    await pumpEventQueue();
    expect(ble.adapterChecks, checks, reason: 'linked before the close');
    expect(app.ble.connects, 1);

    closeGate.complete();
    await closed;
    await again;
    expect(connection.status, ConnectionStatus.bluetooth);
    expect(app.ble.connects, 2);
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

    await connection.openCamera(CameraTab.library);
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
    // By default liveness takes far longer than any test waits, so a loss
    // can only come from the phone's report or an explicit check.
    GrSessionOptions options({
      Duration livenessInterval = const Duration(seconds: 30),
      Duration livenessLossAfter = const Duration(seconds: 30),
    }) => GrSessionOptions(
      livenessInterval: livenessInterval,
      livenessLossAfter: livenessLossAfter,
      wifiRecoveryDelays: const [Duration(milliseconds: 50)],
      maxWifiRecoveryAttempts: 2,
      bleReconnectDelays: const [Duration(milliseconds: 50)],
      maxBleReconnectAttempts: 2,
      bleLostAfter: const Duration(milliseconds: 500),
      bleConnectTimeout: const Duration(seconds: 1),
      // Longer than the simulated camera's drop after a wake (1 s).
      wakeSettle: const Duration(seconds: 2),
    );

    Future<TestApp> connected(
      FakeCameraConfig config, [
      GrSessionOptions? sessionOptions,
    ]) async {
      final app = await createTestApp(
        config: config,
        saveCamera: true,
        sessionOptions: sessionOptions ?? options(),
      );
      addTearDown(app.dispose);
      await app.models.connection.openCamera(CameraTab.library);
      expect(app.models.connection.status, ConnectionStatus.connected);
      return app;
    }

    /// The Library stays while the session gets the Wi-Fi back, shown as
    /// reconnecting, and is usable again afterwards.
    Future<void> expectRecoveredInPlace(TestApp app) async {
      final connection = app.models.connection;
      final seen = <bool>[];
      void record() => seen.add(connection.reconnecting);
      connection.addListener(record);
      addTearDown(() => connection.removeListener(record));
      await _until(() => seen.contains(true));
      expect(connection.inSession, isTrue);
      await _until(
        () => !connection.reconnecting && app.camera.wifiJoined,
        timeout: const Duration(seconds: 5),
      );
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.failure, isNull);
      expect(await connection.checkWifi(), isTrue);
    }

    test('the phone reporting the network gone rejoins with the Library '
        'kept', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      app.camera.dropWifi();
      await expectRecoveredInPlace(app);
    });

    test('without that report, liveness finds the loss the same way', () async {
      final app = await connected(
        const FakeCameraConfig(bonded: true, reportsWifiLoss: false),
        options(
          livenessInterval: const Duration(milliseconds: 100),
          livenessLossAfter: const Duration(milliseconds: 400),
        ),
      );
      app.camera.dropWifi();
      await expectRecoveredInPlace(app);
    });

    test('checkWifi keeps the Wi-Fi while the camera answers and rejoins '
        'when it does not', () async {
      final app = await connected(
        const FakeCameraConfig(bonded: true, reportsWifiLoss: false),
      );
      final connection = app.models.connection;
      expect(await connection.checkWifi(), isTrue);
      expect(connection.reconnecting, isFalse);

      app.camera.dropWifi();
      expect(await connection.checkWifi(), isFalse);
      await expectRecoveredInPlace(app);
    });

    test('a Bluetooth drop on Wi-Fi shows Bluetooth down with the Library '
        'kept', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final connection = app.models.connection;
      expect(LinkState.of(connection).bluetooth, isTrue);

      app.camera
        ..adapterState = BleAdapterState.poweredOff
        ..dropBluetooth();
      await _until(() => !connection.bleLinked);
      final link = LinkState.of(connection);
      expect(link.bluetooth, isFalse);
      expect(link.label, LinkLabel.wifi);
      expect(connection.inSession, isTrue);
    });

    test('a camera switched off shows as off, is turned back on and '
        'rejoined', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final connection = app.models.connection;
      final off = <bool>[];
      // The camera pill turns red while the Library stays.
      void record() {
        final pill = LinkState.of(connection);
        off.add(connection.inSession && pill.label == LinkLabel.cameraOff);
      }

      connection.addListener(record);
      addTearDown(() => connection.removeListener(record));

      app.camera.poweredOn = false;
      await _until(() => off.contains(true));
      await _until(
        () => !connection.reconnecting && app.camera.wifiJoined,
        timeout: const Duration(seconds: 5),
      );
      expect(app.camera.poweredOn, isTrue);
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.cameraOff, isFalse);
    });

    test('a Wi-Fi that does not come back returns to Cameras on Bluetooth '
        'with a note', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final connection = app.models.connection;
      app.camera.dropWifi(recoverable: false);
      await _until(
        () => connection.status == ConnectionStatus.bluetooth,
        timeout: const Duration(seconds: 5),
      );
      expect(connection.inSession, isFalse);
      expect(connection.failure?.kind, ConnectFailureKind.wifi);
      expect(connection.failure?.loss, ConnectLoss.wifi);
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    test('a camera gone with its Bluetooth ends the session with a lost '
        'connection', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final connection = app.models.connection;
      app.camera.powerOffFully();
      await _until(
        () => connection.status == ConnectionStatus.failed,
        timeout: const Duration(seconds: 5),
      );
      expect(connection.inSession, isFalse);
      expect(connection.failure?.kind, ConnectFailureKind.unreachable);
      expect(connection.failure?.loss, ConnectLoss.camera);
    });

    test(
      'leaving the Wi-Fi turns a camera the app turned on back off',
      () async {
        final app = await connected(
          const FakeCameraConfig(bonded: true, poweredOn: false),
        );
        final connection = app.models.connection;
        expect(app.camera.poweredOn, isTrue);
        await connection.disconnectWifi();
        await _until(() => !app.camera.poweredOn);
        expect(connection.status, ConnectionStatus.bluetooth);
        // The drop after turning it off is expected, not a reconnect.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(connection.reconnecting, isFalse);
      },
    );

    test(
      'leaving the Wi-Fi of a camera that was already on leaves it on',
      () async {
        final app = await connected(const FakeCameraConfig(bonded: true));
        await app.models.connection.disconnectWifi();
        expect(app.models.connection.status, ConnectionStatus.bluetooth);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(app.camera.poweredOn, isTrue);
      },
    );

    test('closing the pages keeps a camera the app turned on on, until '
        'the unused Wi-Fi is left from the Cameras screen', () async {
      final app = await connected(
        const FakeCameraConfig(bonded: true, poweredOn: false),
      );
      final connection = app.models.connection;
      await connection.closeCamera();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(app.camera.poweredOn, isTrue);
      expect(connection.status, ConnectionStatus.connected);

      await connection.leaveUnusedWifi(const Duration(minutes: 5));
      await _until(() => !app.camera.poweredOn);
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.idleClosedAfter, const Duration(minutes: 5));
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    test('leaving the unused Wi-Fi keeps a page that does not need it, '
        'with the camera on, and closes one that does', () async {
      final app = await connected(
        const FakeCameraConfig(bonded: true, poweredOn: false),
      );
      final connection = app.models.connection..selectTab(CameraTab.shoot);
      await connection.leaveUnusedWifi(const Duration(minutes: 5));
      expect(connection.tab, CameraTab.shoot);
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.idleClosedAfter, isNull);
      expect(app.camera.wlanOn, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(app.camera.poweredOn, isTrue);

      // Live view needs the Wi-Fi as the Library does.
      connection.liveViewWanted = true;
      await connection.joinWifi();
      expect(connection.status, ConnectionStatus.connected);
      await connection.leaveUnusedWifi(const Duration(minutes: 1));
      expect(connection.tab, isNull);
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.idleClosedAfter, const Duration(minutes: 1));
      await _until(() => !app.camera.poweredOn);
    });

    test('a camera switched off while its Wi-Fi was only kept stays off, '
        'and the Wi-Fi is let go without a failure', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final connection = app.models.connection;
      await connection.closeCamera();

      app.camera.poweredOn = false;
      await _until(() => connection.status == ConnectionStatus.bluetooth);
      expect(connection.failure, isNull);
      // The camera drops its link when it turns off and the session links
      // it again in its off state: a recovery would wake it over that link.
      await _until(() => !connection.bleLinked);
      await _until(() => connection.bleLinked);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(app.camera.poweredOn, isFalse);
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    test('a network gone on a page that does not need it is not rejoined, '
        'and the page stays', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final connection = app.models.connection..selectTab(CameraTab.shoot);

      app.camera.dropWifi();
      await _until(() => connection.status == ConnectionStatus.bluetooth);
      expect(connection.tab, CameraTab.shoot);
      expect(connection.failure, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(app.camera.wifiJoined, isFalse);
      expect(app.camera.wlanOn, isFalse);
      expect(connection.status, ConnectionStatus.bluetooth);
    });

    test('a network gone on such a page while work over the Wi-Fi runs is '
        'got back', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final release = app.models.idle.hold();
      addTearDown(release);
      app.models.connection.selectTab(CameraTab.shoot);

      app.camera.dropWifi();
      await expectRecoveredInPlace(app);
      expect(app.models.connection.tab, CameraTab.shoot);
    });

    test('Bluetooth gone for good while the Wi-Fi was only kept ends the '
        'session, so the camera can be linked again', () async {
      final app = await connected(const FakeCameraConfig(bonded: true));
      final connection = app.models.connection;
      await connection.closeCamera();

      app.camera
        ..adapterState = BleAdapterState.poweredOff
        ..dropBluetooth();
      await _until(
        () => connection.status == ConnectionStatus.failed,
        timeout: const Duration(seconds: 5),
      );
      expect(connection.failure?.kind, ConnectFailureKind.unreachable);
      expect(connection.failure?.loss, ConnectLoss.bluetooth);
      expect(await app.camera.wifi.currentSsid(), isNull);
    });

    /// The camera behind [_RefusableWifi], with joins giving up after
    /// 300 ms and recovery after one attempt that fails. (A second attempt
    /// would find the simulated camera answering without a join.)
    Future<(TestApp, _RefusableWifi)> refusable() async {
      late _RefusableWifi wifi;
      final app = await createTestApp(
        config: const FakeCameraConfig(
          bonded: true,
          wlanOnDelay: Duration.zero,
          joinDelay: Duration.zero,
        ),
        saveCamera: true,
        sessionOptions: const GrSessionOptions(
          livenessInterval: Duration(seconds: 30),
          livenessLossAfter: Duration(seconds: 30),
          joinTimeout: Duration(milliseconds: 300),
          joinRetryDelay: Duration(milliseconds: 50),
          wifiRecoveryDelays: [Duration(milliseconds: 50)],
          maxWifiRecoveryAttempts: 1,
        ),
        wifi: (camera) => wifi = _RefusableWifi(camera),
      );
      addTearDown(app.dispose);
      return (app, wifi);
    }

    /// The Library on Wi-Fi joined through [_RefusableWifi].
    Future<(TestApp, _RefusableWifi)> connectedRefusable() async {
      final (app, wifi) = await refusable();
      await app.models.connection.openCamera(CameraTab.library);
      expect(app.models.connection.status, ConnectionStatus.connected);
      return (app, wifi);
    }

    /// Completes when the session gives up getting the Wi-Fi back.
    Future<void> recoveryGaveUp(ConnectionController connection) => connection
        .cameraSession!
        .events
        .firstWhere((e) => e.kind == 'recovery.gaveUp')
        .timeout(const Duration(seconds: 10));

    test('a Wi-Fi that could not be got back in the background is joined '
        'again on return, with the Library kept', () async {
      final (app, wifi) = await connectedRefusable();
      final connection = app.models.connection;

      final gaveUp = recoveryGaveUp(connection);
      connection.foreground = false;
      wifi.background = true;
      app.camera.dropWifi();
      await gaveUp;
      expect(connection.tab, CameraTab.library);
      expect(connection.failure, isNull);
      expect(connection.reconnecting, isTrue);

      final up = connection.wifiUp.first;
      wifi.background = false;
      connection.foreground = true;
      await up.timeout(const Duration(seconds: 10));
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.tab, CameraTab.library);
      expect(await connection.checkWifi(), isTrue);
    });

    test('a Wi-Fi the user declined to rejoin in the background is not '
        'joined again on return', () async {
      final (app, wifi) = await connectedRefusable();
      final connection = app.models.connection;

      final gaveUp = recoveryGaveUp(connection);
      connection.foreground = false;
      wifi.decline = true;
      app.camera.dropWifi();
      await gaveUp;
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.failure?.kind, ConnectFailureKind.wifiDeclined);

      final joins = wifi.joins;
      connection.foreground = true;
      await pumpEventQueue();
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(wifi.joins, joins);
    });

    test('a join a VPN may be blocking is retried, and its hint shows when '
        'every try fails on it', () async {
      final (app, wifi) = await refusable();
      final connection = app.models.connection;

      wifi.vpnBlocks = 1000;
      await connection.openCamera(CameraTab.library);
      expect(wifi.joins, greaterThan(1));
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.failure?.kind, ConnectFailureKind.wifiVpn);
    });

    test(
      'a Wi-Fi a VPN keeps blocking after a loss shows the VPN hint',
      () async {
        final (app, wifi) = await connectedRefusable();
        final connection = app.models.connection;

        final gaveUp = recoveryGaveUp(connection);
        wifi.vpnBlocks = 1000;
        app.camera.dropWifi();
        await gaveUp;
        expect(connection.status, ConnectionStatus.bluetooth);
        expect(connection.failure?.kind, ConnectFailureKind.wifiVpn);
      },
    );

    test('a VPN suspicion that clears on a retry rejoins without a '
        'failure', () async {
      final (app, wifi) = await connectedRefusable();
      final connection = app.models.connection;

      final up = connection.wifiUp.first;
      wifi.vpnBlocks = 1;
      final joins = wifi.joins;
      app.camera.dropWifi();
      await up.timeout(const Duration(seconds: 10));
      expect(wifi.joins, joins + 2);
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.failure, isNull);
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

      final attempt = connection.openCamera(CameraTab.library);
      await _until(() => connection.wifiConsent != null);
      expect(connection.wifiConsent!.ssid, app.camera.config.ssid);
      connection.answerWifiConsent(join: false);
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

      final attempt = connection.openCamera(CameraTab.library);
      await _until(() => connection.wifiConsent != null);
      connection.answerWifiConsent(join: true);
      await attempt;
      expect(connection.status, ConnectionStatus.connected);
      expect(app.models.cameras.current!.wifiApproved, isTrue);

      await connection.disconnect();
      var asked = false;
      void listener() => asked |= connection.wifiConsent != null;
      connection.addListener(listener);
      await connection.openCamera(CameraTab.library);
      connection.removeListener(listener);

      expect(connection.status, ConnectionStatus.connected);
      expect(asked, isFalse);
    });

    test('cancelling while asked withdraws the question', () async {
      final app = await create();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      unawaited(connection.openCamera(CameraTab.library));
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
      final first = connection.openCamera(CameraTab.library);
      await _until(() => connection.wifiConsent != null);
      connection.answerWifiConsent(join: true);
      await first;
      expect(connection.status, ConnectionStatus.connected);
      await connection.disconnectWifi();
      expect(connection.status, ConnectionStatus.bluetooth);
      wifi.backOutOfList = 1;
      return (app, wifi);
    }

    test('explains it and Try again joins', () async {
      final (app, wifi) = await approvedThenListed();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.openCamera(CameraTab.library);
      await _until(() => connection.wifiConsent != null);
      expect(connection.wifiConsent!.again, isTrue);
      expect(connection.wifiConsent!.ssid, app.camera.config.ssid);
      final joinsBefore = wifi.joins;
      connection.answerWifiConsent(join: true);
      await attempt;

      expect(connection.status, ConnectionStatus.connected);
      expect(wifi.joins, joinsBefore + 1);
    });

    test('Not now keeps Bluetooth and reports the decline', () async {
      final (app, _) = await approvedThenListed();
      addTearDown(app.dispose);
      final connection = app.models.connection;

      final attempt = connection.openCamera(CameraTab.library);
      await _until(() => connection.wifiConsent != null);
      connection.answerWifiConsent(join: false);
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

      final attempt = connection.openCamera(CameraTab.library);
      await _until(() => connection.wifiConsent != null);
      expect(connection.wifiConsent!.again, isFalse);
      connection.answerWifiConsent(join: true);
      await attempt;

      expect(connection.wifiConsent, isNull);
      expect(connection.failure?.kind, ConnectFailureKind.wifiDeclined);
    });
  });
}

/// The camera's Wi-Fi, with Android's network list shown during the next
/// [backOutOfList] joins and the user backing out of it each time.
final class _ListWifi implements WifiNetworkControl {
  new(this._camera, this._shown);

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

/// The camera's transport, with gates the test opens: [connect] waits for
/// [linkGate], and a link's disconnect for [closeGate].
final class _GatedTransport implements BleTransport {
  new(this._camera);

  final BleTransport _camera;
  Completer<void>? linkGate;
  Completer<void>? closeGate;
  final connectCalled = Completer<void>();
  final disconnectCalled = Completer<void>();

  /// Adapter state reads: each Bluetooth attempt starts with one.
  int adapterChecks = 0;

  @override
  Future<BleAdapterState> adapterState() {
    adapterChecks++;
    return _camera.adapterState();
  }

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) =>
      _camera.scan(serviceUuids: serviceUuids);

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    if (!connectCalled.isCompleted) connectCalled.complete();
    await linkGate?.future;
    return _GatedLink(await _camera.connect(deviceId, timeout: timeout), this);
  }

  @override
  Future<void> close() => _camera.close();
}

final class _GatedLink implements BleConnection {
  new(this._link, this._transport);

  final BleConnection _link;
  final _GatedTransport _transport;

  @override
  String get deviceId => _link.deviceId;

  @override
  int? get maximumWriteLength => _link.maximumWriteLength;

  @override
  Future<List<BleServiceInfo>> discover() => _link.discover();

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) => _link.read(serviceUuid, characteristicUuid, timeout: timeout);

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) => _link.write(
    serviceUuid,
    characteristicUuid,
    value,
    withResponse: withResponse,
    timeout: timeout,
  );

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) =>
      _link.subscribe(serviceUuid, characteristicUuid);

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) => _link.pair(
    probeServiceUuid: probeServiceUuid,
    probeCharacteristicUuid: probeCharacteristicUuid,
    timeout: timeout,
  );

  @override
  Future<BleDisconnect> get disconnected => _link.disconnected;

  @override
  Future<void> disconnect() async {
    final called = _transport.disconnectCalled;
    if (!called.isCompleted) called.complete();
    await _transport.closeGate?.future;
    await _link.disconnect();
  }
}

/// The camera's Wi-Fi, which the OS does not join while [background] (as
/// Android and iOS refuse joins for an app that is not in front), which
/// the user declines while [decline], and whose next [vpnBlocks] joins
/// Android refuses to route over while a VPN carries the app's traffic.
final class _RefusableWifi implements WifiNetworkControl {
  new(this._camera);

  final WifiNetworkControl _camera;
  bool background = false;
  bool decline = false;
  int vpnBlocks = 0;
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
    if (decline) throw const WifiJoinDeclined();
    if (background) throw const _JoinInBackground();
    if (vpnBlocks > 0) {
      vpnBlocks--;
      throw const WifiJoinVpnSuspected('a VPN carries the app');
    }
    await _camera.join(
      ssid: ssid,
      passphrase: passphrase,
      security: security,
      timeout: timeout,
      approved: approved,
    );
  }

  @override
  Future<String?> currentSsid() => _camera.currentSsid();

  @override
  Future<void> leave() => _camera.leave();

  @override
  Stream<void> get lost => _camera.lost;
}

final class _JoinInBackground implements Exception {
  const new();

  @override
  String toString() => 'the OS joins networks only for the app in front';
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
