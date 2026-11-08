/// Security requested when joining the camera access point; chosen from the
/// camera's BLE `security` characteristic where present (0 WPA2, 1 WPA3,
/// 2 WPA2/WPA3 transition).
enum WifiSecurity { wpa2, wpa3, transition }

/// Thrown by [WifiNetworkControl.join] when the user declined joining the
/// camera network (an app or OS prompt). Sessions never retry it: asking
/// again is the user's call.
final class WifiJoinDeclined implements Exception {
  const WifiJoinDeclined([
    this.message = 'joining the camera Wi-Fi was declined',
  ]);

  final String message;

  @override
  String toString() => 'WifiJoinDeclined: $message';
}

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

  /// Emits when the OS reports that the joined camera network is gone.
  /// Platforms without that signal never emit; the session's liveness
  /// polling still notices the loss there, only later.
  Stream<void> get lost;
}
