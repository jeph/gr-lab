import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

/// A [CameraSession] linked over Bluetooth to a simulated GR IV, with every
/// trace event the layer recorded.
final class ShootRig {
  new _(this.camera, this.session, this.trace);

  /// Links [config]'s camera over Bluetooth; with [wifi], turns it on in
  /// shooting mode, as Shoot does before live view, and joins its Wi-Fi.
  static Future<ShootRig> start({
    FakeCameraConfig config = const FakeCameraConfig(bonded: true),
    bool wifi = false,
  }) async {
    // flutter_test blocks real HTTP; the simulated camera serves it on
    // loopback.
    HttpOverrides.global = null;
    final camera = FakeGrCamera(config: config, media: syntheticMedia());
    await camera.startHttp();
    final trace = <TraceEvent>[];
    final session = CameraSession(
      GrCameraEnvironment(
        ble: camera.transport,
        wifi: camera.wifi,
        trace: trace.add,
        httpFactory: camera.httpClient,
        // Liveness probes would otherwise run every 500 ms.
        sessionOptions: const GrSessionOptions(
          livenessInterval: Duration(hours: 1),
          livenessLossAfter: Duration(hours: 2),
        ),
      ),
      consent: WifiConsent(
        ask: (_) async => true,
        askAgain: (_) async => false,
        cameraApproved: () => true,
        joined: () async {},
      ),
    );
    await session.connectBluetooth(
      deviceId: config.deviceId,
      serial: config.serial,
    );
    final rig = ShootRig._(camera, session, trace);
    if (wifi) {
      await session.remote.wake();
      await session.startWifi();
    }
    return rig;
  }

  final FakeGrCamera camera;
  final CameraSession session;
  final List<TraceEvent> trace;

  CameraRemote get remote => session.remote;
  CameraLiveView get liveView => session.liveView;

  /// Session-channel decisions of [kind] recorded so far.
  List<Map<String, Object?>> events(String kind) => [
    for (final e in trace)
      if (e.channel == TraceChannel.session && e.kind == kind) e.fields,
  ];

  /// Joins the Wi-Fi if needed and starts live view until frames come.
  Future<void> startLiveView() async {
    if (session.phase != GrSessionPhase.connected) await session.startWifi();
    liveView.start();
    await until(() => liveView.streaming, reason: 'frames');
  }

  Future<void> close() async {
    await session.close();
    await camera.close();
  }
}

/// Waits for [condition], failing after [timeout].
Future<void> until(
  bool Function() condition, {
  String reason = 'condition',
  Duration timeout = const Duration(seconds: 10),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('Timed out waiting for $reason');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
