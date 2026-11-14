import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/src/platform/wifi_control.dart';
import 'package:gr_protocol/gr_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.jeph.grphoto/wifi');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) reply;
  late List<TraceEvent> trace;

  setUp(() {
    calls = [];
    trace = [];
    reply = (_) async => null;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return reply(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> join(
    PlatformWifiControl wifi, {
    WifiSecurity security = WifiSecurity.wpa2,
    Duration timeout = const Duration(seconds: 60),
  }) => wifi.join(
    ssid: 'GR_1234567',
    passphrase: 'abcd1234',
    security: security,
    timeout: timeout,
  );

  test('join sends credentials, security name and timeout in ms', () async {
    final wifi = PlatformWifiControl(trace: trace.add);
    for (final security in WifiSecurity.values) {
      await join(
        wifi,
        security: security,
        timeout: const Duration(seconds: 42),
      );
    }
    expect(calls.map((c) => c.method), everyElement('join'));
    expect(
      [for (final c in calls) c.arguments],
      [
        for (final name in ['wpa2', 'wpa3', 'transition'])
          {
            'ssid': 'GR_1234567',
            'passphrase': 'abcd1234',
            'security': name,
            'timeoutMs': 42000,
            'approved': false,
          },
      ],
    );
  });

  test('an exhausted join window still makes one native attempt', () async {
    await join(
      PlatformWifiControl(trace: trace.add),
      timeout: const Duration(seconds: -3),
    );
    expect((calls.single.arguments as Map<Object?, Object?>)['timeoutMs'], 1);
  });

  test('a native timeout becomes a TimeoutException', () async {
    reply = (_) async => throw PlatformException(
      code: 'timeout',
      message: '"GR_1234567" did not connect within 5000 ms',
    );
    await expectLater(
      join(
        PlatformWifiControl(trace: trace.add),
        timeout: const Duration(seconds: 5),
      ),
      throwsA(
        isA<TimeoutException>()
            .having((e) => e.duration, 'duration', const Duration(seconds: 5))
            .having((e) => e.message, 'message', contains('5000 ms')),
      ),
    );
  });

  test('a declined system prompt is WifiJoinDeclined, which sessions never '
      'retry', () async {
    reply = (_) async =>
        throw PlatformException(code: 'declined', message: 'declined');
    await expectLater(
      join(PlatformWifiControl(trace: trace.add)),
      throwsA(isA<WifiJoinDeclined>()),
    );
  });

  test('a suspected VPN block is WifiJoinVpnSuspected, with the native '
      'message', () async {
    reply = (_) async => throw PlatformException(
      code: 'vpnSuspected',
      message: 'a VPN carries this app',
    );
    await expectLater(
      join(PlatformWifiControl(trace: trace.add)),
      throwsA(
        isA<WifiJoinVpnSuspected>().having(
          (e) => e.message,
          'message',
          'a VPN carries this app',
        ),
      ),
    );
  });

  test('other native errors keep their code', () async {
    for (final code in ['invalid', 'superseded', 'cancelled', 'failed']) {
      reply = (_) async => throw PlatformException(code: code);
      await expectLater(
        join(PlatformWifiControl(trace: trace.add)),
        throwsA(
          isA<WifiJoinException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.message, 'message', contains('GR_1234567')),
        ),
      );
    }
  });

  test('a missing native side is reported as unsupported', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final wifi = PlatformWifiControl(trace: trace.add);
    await expectLater(
      join(wifi),
      throwsA(
        isA<WifiJoinException>().having((e) => e.code, 'code', 'unsupported'),
      ),
    );
    expect(await wifi.currentSsid(), isNull);
    await wifi.leave();
  });

  test('currentSsid passes the native answer through', () async {
    final wifi = PlatformWifiControl(trace: trace.add);
    reply = (_) async => 'GR_1234567';
    expect(await wifi.currentSsid(), 'GR_1234567');
    reply = (_) async => null;
    expect(await wifi.currentSsid(), isNull);
    reply = (_) async => throw PlatformException(code: 'failed');
    expect(await wifi.currentSsid(), isNull);
    expect(calls.map((c) => c.method), everyElement('currentSsid'));
  });

  test(
    'native log lines and events are recorded on the wifi channel',
    () async {
      final wifi = PlatformWifiControl(trace: trace.add);
      final shown = wifi.approvalShown.first;
      Future<void> fromNative(String method, [Object? arguments]) =>
          messenger.handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method, arguments)),
            (_) {},
          );

      await fromNative('log', '"GR_1234567" not found yet; request 2');
      await fromNative('approvalShown');
      await shown;

      expect(
        [for (final e in trace) (e.channel, e.direction, e.kind)],
        [
          (TraceChannel.wifi, TraceDirection.internal, 'native'),
          (TraceChannel.wifi, TraceDirection.inbound, 'approvalShown'),
        ],
      );
      expect(trace.first.fields, {
        'message': '"GR_1234567" not found yet; request 2',
      });
    },
  );

  test('background time carries what iOS said is left, and ending it sends '
      'its id back once', () async {
    final wifi = PlatformWifiControl(trace: trace.add);
    reply = (call) async => call.method == 'beginBackgroundTime'
        ? {'id': 7, 'remainingMs': 29500}
        : null;
    final time = await wifi.beginBackgroundTime();
    expect(time.remaining, const Duration(milliseconds: 29500));

    await time.end();
    await time.end();
    expect(
      [for (final c in calls) (c.method, c.arguments)],
      [('beginBackgroundTime', null), ('endBackgroundTime', 7)],
    );
  });

  test('background time without a limit has none; a refused one has none '
      'left and nothing to end', () async {
    final wifi = PlatformWifiControl(trace: trace.add);
    reply = (_) async => {'id': 3, 'remainingMs': null};
    expect((await wifi.beginBackgroundTime()).remaining, isNull);

    reply = (_) async => {'id': null, 'remainingMs': 0};
    final refused = await wifi.beginBackgroundTime();
    expect(refused.remaining, Duration.zero);
    calls.clear();
    await refused.end();
    expect(calls, isEmpty);
  });

  test('without the native methods (Android), background time is unlimited '
      'and no leftover network is removed', () async {
    final wifi = PlatformWifiControl(trace: trace.add);
    messenger.setMockMethodCallHandler(channel, null);
    expect((await wifi.beginBackgroundTime()).remaining, isNull);
    expect(await wifi.forgetLeftovers(), isEmpty);
  });

  test('forgetLeftovers passes the removed SSIDs through and traces a native '
      'failure', () async {
    final wifi = PlatformWifiControl(trace: trace.add);
    reply = (_) async => ['GR_000001'];
    expect(await wifi.forgetLeftovers(), ['GR_000001']);

    reply = (_) async => throw PlatformException(code: 'failed');
    expect(await wifi.forgetLeftovers(), isEmpty);
    expect(trace.single.kind, 'native.forgetLeftovers.error');
  });

  test('background time iOS takes back is traced', () async {
    PlatformWifiControl(trace: trace.add);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('backgroundTimeExpired', 7),
      ),
      (_) {},
    );
    final event = trace.single;
    expect(event.direction, TraceDirection.inbound);
    expect(event.kind, 'backgroundTime.expired');
    expect(event.fields, {'id': 7});
  });
}
