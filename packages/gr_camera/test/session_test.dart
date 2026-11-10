import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show WifiNetworkControl, WifiSecurity;

/// The camera's Wi-Fi control, counting the joins that reach it.
final class _CountingWifi implements WifiNetworkControl {
  new(this._inner);

  final WifiNetworkControl _inner;
  int joins = 0;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) {
    joins++;
    return _inner.join(
      ssid: ssid,
      passphrase: passphrase,
      security: security,
      timeout: timeout,
      approved: approved,
    );
  }

  @override
  Future<String?> currentSsid() => _inner.currentSsid();

  @override
  Future<void> leave() => _inner.leave();

  @override
  Stream<void> get lost => _inner.lost;
}

void main() {
  late FakeGrCamera camera;
  late _CountingWifi wifi;
  late Completer<String> asked;
  late Completer<bool> answer;
  late CameraSession session;

  setUp(() async {
    HttpOverrides.global = null;
    camera = FakeGrCamera(
      config: const FakeCameraConfig(bonded: true, httpLatency: Duration.zero),
      media: syntheticMedia(),
    );
    await camera.startHttp();
    wifi = _CountingWifi(camera.wifi);
    asked = Completer();
    answer = Completer();
    session = CameraSession(
      GrCameraEnvironment(
        ble: camera.transport,
        wifi: wifi,
        trace: (_) {},
        httpFactory: camera.httpClient,
        sessionOptions: const GrSessionOptions(joinRetryDelay: Duration.zero),
      ),
      consent: WifiConsent(
        ask: (ssid) {
          asked.complete(ssid);
          return answer.future;
        },
        askAgain: (_) async => true,
        cameraApproved: () => false,
        joined: () async {},
      ),
    );
    await session.connectBluetooth(
      deviceId: camera.config.deviceId,
      serial: camera.config.serial,
    );
  });

  tearDown(() async {
    await session.close();
    await camera.close();
  });

  test(
    'a Wi-Fi consent given after the join was stopped joins nothing',
    () async {
      final start = session.startWifi();
      final startFailed = expectLater(
        start,
        throwsA(isA<GrSessionException>()),
      );
      await asked.future;

      // Disconnect while the question is still open; the answer comes late.
      final stopped = session.stopWifi(reason: WifiStopReason.user);
      answer.complete(true);
      await stopped;
      await startFailed;

      expect(wifi.joins, 0);
      expect(session.phase, GrSessionPhase.bluetooth);
    },
  );

  test(
    'a Wi-Fi consent given after the session closed joins nothing',
    () async {
      final start = session.startWifi();
      final startFailed = expectLater(
        start,
        throwsA(isA<GrSessionException>()),
      );
      await asked.future;

      final closed = session.close();
      answer.complete(true);
      await closed;
      await startFailed;

      expect(wifi.joins, 0);
    },
  );
}
