import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/src/platform/permissions.dart';
import 'package:universal_ble/universal_ble.dart';

/// Answers the permission calls; every other platform call is unexpected.
final class _PermissionPlatform extends UniversalBlePlatform {
  new({required this.granted, this.denyRequest = false});

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
}
