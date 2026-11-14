import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

void main() {
  late FakeGrCamera camera;
  late List<TraceEvent> trace;

  setUp(() {
    camera = FakeGrCamera(
      config: const FakeCameraConfig(bonded: true),
      media: syntheticMedia(),
    );
    trace = [];
  });

  tearDown(() => camera.close());

  GrCameraEnvironment environment({
    required bool outlivesApp,
    Future<BackgroundTime> Function()? backgroundTime,
    Future<List<String>> Function()? forgetLeftovers,
  }) => GrCameraEnvironment(
    ble: camera.transport,
    wifi: camera.wifi,
    trace: trace.add,
    wifiOutlivesApp: outlivesApp,
    beginBackgroundTime: backgroundTime,
    forgetLeftoverWifi: forgetLeftovers,
  );

  List<(TraceDirection, String)> wifiTrace() => [
    for (final e in trace)
      if (e.channel == TraceChannel.wifi) (e.direction, e.kind),
  ];

  test('background time is traced when asked for, granted and given back, '
      'and given back once', () async {
    var ended = 0;
    final env = environment(
      outlivesApp: true,
      backgroundTime: () async => BackgroundTime(
        remaining: const Duration(seconds: 30),
        end: () async => ended++,
      ),
    );

    final time = await env.backgroundTime('leave camera Wi-Fi');
    expect(time.remaining, const Duration(seconds: 30));
    await time.end();
    await time.end();

    expect(ended, 1);
    expect(wifiTrace(), [
      (TraceDirection.outbound, 'backgroundTime'),
      (TraceDirection.inbound, 'backgroundTime.done'),
      (TraceDirection.outbound, 'backgroundTime.end'),
    ]);
    expect(trace[1].fields, {
      'why': 'leave camera Wi-Fi',
      'remainingMs': 30000,
    });
  });

  test('without a way to ask, background time is unlimited', () async {
    final env = environment(outlivesApp: false);
    expect((await env.backgroundTime('leave camera Wi-Fi')).remaining, isNull);
    expect(wifiTrace(), isEmpty);
  });

  test('leftover camera networks are removed only where they outlive the '
      'app', () async {
    var removals = 0;
    Future<List<String>> forget() async {
      removals++;
      return ['GR_000001'];
    }

    await environment(
      outlivesApp: false,
      forgetLeftovers: forget,
    ).forgetLeftoverWifi();
    expect(removals, 0);

    await environment(
      outlivesApp: true,
      forgetLeftovers: forget,
    ).forgetLeftoverWifi();
    expect(removals, 1);
    expect(wifiTrace(), [
      (TraceDirection.outbound, 'forgetLeftovers'),
      (TraceDirection.inbound, 'forgetLeftovers.done'),
    ]);
    expect(trace.last.fields, {
      'ssids': ['GR_000001'],
    });
  });
}
