import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/platform/device_services.dart';
import 'package:grlab/src/platform/permissions.dart';
import 'package:universal_ble/universal_ble.dart';

/// Answers the permission calls; every other platform call is unexpected.
final class _PermissionPlatform extends UniversalBlePlatform {
  _PermissionPlatform({required this.granted, this.denyRequest = false});

  bool granted;
  final bool denyRequest;
  int requests = 0;

  @override
  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) async =>
      granted;

  @override
  Future<void> requestPermissions({
    bool withAndroidFineLocation = false,
  }) async {
    requests++;
    if (denyRequest) {
      throw UniversalBleException(
        code: UniversalBleErrorCode.bluetoothUnauthorized,
        message: 'Not authorized to access Bluetooth',
      );
    }
    granted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ensureBluetoothPermission', () {
    test('already granted does not prompt', () async {
      final platform = _PermissionPlatform(granted: true);
      UniversalBle.setInstance(platform);
      expect(await ensureBluetoothPermission(), isTrue);
      expect(platform.requests, 0);
    });

    test('prompts once and reports a grant', () async {
      final platform = _PermissionPlatform(granted: false);
      UniversalBle.setInstance(platform);
      expect(await ensureBluetoothPermission(), isTrue);
      expect(platform.requests, 1);
    });

    test('a denial is false, not an exception', () async {
      final platform = _PermissionPlatform(granted: false, denyRequest: true);
      UniversalBle.setInstance(platform);
      expect(await ensureBluetoothPermission(), isFalse);
      expect(platform.requests, 1);
    });
  });

  group('deviceClientName', () {
    const channel = MethodChannel('io.jeph.grlab/device');
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

    test('falls back to GR Lab when there is nothing usable', () async {
      expect(await nameFor(() => null), 'GR Lab');
      expect(await nameFor(() => '   '), 'GR Lab');
      expect(
        await nameFor(() => throw PlatformException(code: 'failed')),
        'GR Lab',
      );
      messenger.setMockMethodCallHandler(channel, null);
      expect(await deviceClientName(), 'GR Lab');
    });
  });
}
