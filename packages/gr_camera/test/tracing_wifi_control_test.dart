import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/src/platform/tracing_wifi_control.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Answers each call from the queue in [results] (a value, or an error to
/// throw).
final class _ScriptedWifi implements WifiNetworkControl {
  final results = <Object?>[];
  final lostController = StreamController<void>.broadcast();

  Future<void> close() => lostController.close();

  Future<T> _next<T>() async {
    final r = results.removeAt(0);
    if (r is Exception) throw r;
    return r as T;
  }

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) => _next<void>();

  @override
  Future<String?> currentSsid() => _next<String?>();

  @override
  Future<void> leave() => _next<void>();

  @override
  Stream<void> get lost => lostController.stream;
}

void main() {
  late _ScriptedWifi inner;
  late List<TraceEvent> trace;
  late TracingWifiControl wifi;

  setUp(() {
    inner = _ScriptedWifi();
    trace = [];
    wifi = TracingWifiControl(inner, trace.add);
  });

  tearDown(() => inner.close());

  List<(TraceDirection, String)> kinds() => [
    for (final e in trace) (e.direction, e.kind),
  ];

  test('a join records every argument and its outcome', () async {
    inner.results.add(null);
    await wifi.join(
      ssid: 'GR_1234567',
      passphrase: 'abcd1234',
      security: WifiSecurity.wpa3,
      timeout: const Duration(seconds: 30),
      approved: true,
    );

    expect(trace.every((e) => e.channel == TraceChannel.wifi), isTrue);
    expect(kinds(), [
      (TraceDirection.outbound, 'join'),
      (TraceDirection.inbound, 'join.done'),
    ]);
    expect(trace.first.fields, {
      'ssid': 'GR_1234567',
      'passphrase': 'abcd1234',
      'security': 'wpa3',
      'timeoutMs': 30000,
      'approved': true,
    });
  });

  test('a failed join is recorded and still thrown', () async {
    inner.results.add(const WifiJoinDeclined('the user declined'));

    await expectLater(
      wifi.join(
        ssid: 'GR_1234567',
        passphrase: 'abcd1234',
        security: WifiSecurity.wpa2,
        timeout: const Duration(seconds: 30),
      ),
      throwsA(isA<WifiJoinDeclined>()),
    );
    expect(kinds().last, (TraceDirection.inbound, 'join.error'));
    expect(trace.last.fields['type'], 'WifiJoinDeclined');
    expect(trace.last.fields['error'], contains('the user declined'));
  });

  test('currentSsid and leave record their answers', () async {
    inner.results.addAll(['GR_1234567', null]);
    expect(await wifi.currentSsid(), 'GR_1234567');
    await wifi.leave();

    expect(kinds(), [
      (TraceDirection.outbound, 'currentSsid'),
      (TraceDirection.inbound, 'currentSsid.done'),
      (TraceDirection.outbound, 'leave'),
      (TraceDirection.inbound, 'leave.done'),
    ]);
    expect(trace[1].fields['ssid'], 'GR_1234567');
  });

  test('a loss reaches every listener and is recorded once', () async {
    final first = wifi.lost.first;
    final second = wifi.lost.first;
    inner.lostController.add(null);
    await Future.wait([first, second]);

    expect(kinds(), [(TraceDirection.inbound, 'lost')]);
  });
}
