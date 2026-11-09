import 'package:universal_ble/universal_ble.dart';

/// Makes sure the app may scan for and connect to the camera: Android 12+
/// asks for Nearby devices (BLUETOOTH_SCAN/CONNECT, declared
/// neverForLocation, so no location prompt); iOS shows its Bluetooth prompt
/// the first time. Returns false when the user denied it or Bluetooth is
/// unsupported, never throws.
Future<bool> ensureBluetoothPermission() async {
  try {
    if (await UniversalBle.hasPermissions()) return true;
    await UniversalBle.requestPermissions();
    return true;
  } on Object {
    // universal_ble reports a denial (and a missing adapter) by throwing.
    return false;
  }
}
