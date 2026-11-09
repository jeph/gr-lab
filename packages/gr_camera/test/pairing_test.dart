import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

/// [PairingRun]s against a simulated camera in the test binding's fake
/// time, which `clock` follows. Some stream cancellations complete in the
/// real event loop, so `advance` lets that run between fake steps.
void main() {
  late FakeGrCamera camera;
  late GrCameraEnvironment environment;
  late NearbyCamera target;

  /// When each bond request left the phone, in fake time.
  late List<DateTime> bondRequests;
  late List<String> events;

  void setUpCamera() {
    camera = FakeGrCamera(
      config: const FakeCameraConfig(
        executePairingOpen: true,
        refusePairing: true,
      ),
      media: syntheticMedia(),
    );
    bondRequests = [];
    events = [];
    environment = GrCameraEnvironment(
      ble: camera.transport,
      wifi: camera.wifi,
      trace: (e) {
        events.add(e.kind);
        if (e.kind == 'pair.bond.start') bondRequests.add(clock.now());
      },
    );
    target = NearbyCamera(
      deviceId: camera.config.deviceId,
      model: GrModel.gr4,
      serial: camera.config.serial,
      bluetoothName: camera.config.bluetoothName,
      powerOn: true,
    );
  }

  /// Lets [duration] of fake time pass, in small steps.
  Future<void> advance(WidgetTester tester, Duration duration) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < duration; t += step) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(step);
    }
  }

  Future<void> tearDownCamera(WidgetTester tester) async {
    await tester.runAsync(camera.close);
    // Lets the camera's timers run out.
    await advance(tester, const Duration(minutes: 2));
  }

  /// Starts a run; its error, once it fails, goes to the returned list.
  List<Object> pair({void Function(PairingRun run)? started}) {
    final errors = <Object>[];
    final run = PairingRun(environment, target: target, clientName: 'GR Lab');
    run.start().then<void>((_) {}, onError: errors.add).ignore();
    started?.call(run);
    return errors;
  }

  testWidgets('a new run waits until 15 s after the last bond attempt', (
    tester,
  ) async {
    setUpCamera();
    final first = pair();
    await advance(tester, const Duration(seconds: 2));
    expect(first.single, isA<GrPairingException>());
    expect(bondRequests, hasLength(1));
    final failedAt = clock.now();
    expect(
      PairingRun.nextAttemptAt(environment, target),
      isA<DateTime>().having(
        (at) => at.difference(failedAt),
        'time left',
        greaterThan(const Duration(seconds: 13)),
      ),
      reason: 'counted from the end of the failed attempt',
    );

    // The user reopens Execute Pairing and taps Pair at once.
    camera.openExecutePairing();
    final second = pair();
    await advance(tester, const Duration(seconds: 10));
    expect(bondRequests, hasLength(1), reason: 'too soon after the first');
    expect(events, contains('pair.bondWait'));

    await advance(tester, const Duration(seconds: 10));
    expect(second.single, isA<GrPairingException>());
    expect(bondRequests, hasLength(2));
    expect(
      bondRequests[1].difference(bondRequests[0]),
      greaterThanOrEqualTo(PairingRun.bondInterval),
    );
    await tearDownCamera(tester);
  });

  testWidgets('a run that never reached bonding does not hold the next one', (
    tester,
  ) async {
    setUpCamera();
    // Cancelled while scanning, before any bond request.
    pair(started: (run) => run.cancel().ignore());
    await advance(tester, const Duration(seconds: 2));
    expect(bondRequests, isEmpty);
    expect(PairingRun.nextAttemptAt(environment, target), isNull);
    await tearDownCamera(tester);
  });

  testWidgets('cancelling a run that waits out the interval ends it at once', (
    tester,
  ) async {
    setUpCamera();
    pair();
    await advance(tester, const Duration(seconds: 2));
    expect(bondRequests, hasLength(1));

    camera.openExecutePairing();
    late PairingRun waiting;
    final errors = pair(started: (run) => waiting = run);
    await advance(tester, const Duration(seconds: 1));
    waiting.cancel().ignore();
    await advance(tester, const Duration(milliseconds: 100));
    expect(errors.single, isA<BleException>());
    await advance(tester, const Duration(seconds: 30));
    expect(bondRequests, hasLength(1));
    await tearDownCamera(tester);
  });
}
