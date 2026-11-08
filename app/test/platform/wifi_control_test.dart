import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/platform/wifi_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.jeph.grlab/wifi');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) reply;

  setUp(() {
    calls = [];
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
    final wifi = PlatformWifiControl();
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
          },
      ],
    );
  });

  test('an exhausted join window still makes one native attempt', () async {
    await join(PlatformWifiControl(), timeout: const Duration(seconds: -3));
    expect((calls.single.arguments as Map<Object?, Object?>)['timeoutMs'], 1);
  });

  test('a native timeout becomes a TimeoutException', () async {
    reply = (_) async => throw PlatformException(
      code: 'timeout',
      message: '"GR_1234567" did not connect within 5000 ms',
    );
    await expectLater(
      join(PlatformWifiControl(), timeout: const Duration(seconds: 5)),
      throwsA(
        isA<TimeoutException>()
            .having((e) => e.duration, 'duration', const Duration(seconds: 5))
            .having((e) => e.message, 'message', contains('5000 ms')),
      ),
    );
  });

  test('a declined system prompt is a WifiJoinException', () async {
    reply = (_) async =>
        throw PlatformException(code: 'declined', message: 'declined');
    await expectLater(
      join(PlatformWifiControl()),
      throwsA(
        isA<WifiJoinException>()
            .having((e) => e.declined, 'declined', isTrue)
            .having((e) => e.code, 'code', 'declined'),
      ),
    );
  });

  test('other native errors keep their code', () async {
    for (final code in ['invalid', 'superseded', 'cancelled', 'failed']) {
      reply = (_) async => throw PlatformException(code: code);
      await expectLater(
        join(PlatformWifiControl()),
        throwsA(
          isA<WifiJoinException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.declined, 'declined', isFalse)
              .having((e) => e.message, 'message', contains('GR_1234567')),
        ),
      );
    }
  });

  test('a missing native side is reported as unsupported', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final wifi = PlatformWifiControl();
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
    final wifi = PlatformWifiControl();
    reply = (_) async => 'GR_1234567';
    expect(await wifi.currentSsid(), 'GR_1234567');
    reply = (_) async => null;
    expect(await wifi.currentSsid(), isNull);
    reply = (_) async => throw PlatformException(code: 'failed');
    expect(await wifi.currentSsid(), isNull);
    expect(calls.map((c) => c.method), everyElement('currentSsid'));
  });
}
