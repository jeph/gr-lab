/// Security requested when joining the camera access point; chosen from the
/// camera's BLE `security` characteristic where present (0 WPA2, 1 WPA3,
/// 2 WPA2/WPA3 transition).
enum WifiSecurity { wpa2, wpa3, transition }

/// Platform control of the phone/computer Wi-Fi link to the camera AP,
/// implemented outside this package.
abstract interface class WifiNetworkControl {
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
  });

  /// SSID of the current association, or null when unknown or not associated.
  Future<String?> currentSsid();

  Future<void> leave();
}
