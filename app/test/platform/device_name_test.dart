import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/platform/device_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deviceClientName', () {
    const channel = MethodChannel('io.jeph.grphoto/device');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<String> nameFor(Object? Function() answer) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'name');
        return answer();
      });
      return deviceClientName();
    }

    test('uses the device name, cleaned like GR WORLD', () async {
      expect(await nameFor(() => 'Pixel 9 Pro'), 'Pixel 9 Pro');
      expect(await nameFor(() => 'Jeph’s Pixel'), 'Jeph?s Pixel');
      expect(
        await nameFor(() => 'A' * 40),
        'A' * 32,
        reason: 'the camera stores at most 32 characters',
      );
    });

    test('falls back to GR Photo when there is nothing usable', () async {
      expect(await nameFor(() => null), 'GR Photo');
      expect(await nameFor(() => '   '), 'GR Photo');
      expect(
        await nameFor(() => throw PlatformException(code: 'failed')),
        'GR Photo',
      );
      messenger.setMockMethodCallHandler(channel, null);
      expect(await deviceClientName(), 'GR Photo');
    });
  });
}
