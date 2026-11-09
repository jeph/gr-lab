/// Security requested when joining the camera access point; chosen from the
/// camera's BLE `security` characteristic where present (0 WPA2, 1 WPA3,
/// 2 WPA2/WPA3 transition).
enum WifiSecurity {
  /// WPA2-Personal (wire value 0).
  wpa2,

  /// WPA3-Personal (wire value 1).
  wpa3,

  /// WPA2/WPA3 transition mode (wire value 2).
  transition,
}

/// Thrown by [WifiNetworkControl.join] when the user declined joining the
/// camera network (an app or OS prompt). Sessions never retry it: asking
/// again is the user's call.
final class WifiJoinDeclined implements Exception {
  /// Declined join, with a human-readable [message].
  const new([this.message = 'joining the camera Wi-Fi was declined']);

  /// Why the join was declined.
  final String message;

  @override
  String toString() => 'WifiJoinDeclined: $message';
}

/// Platform control of the phone/computer Wi-Fi link to the camera AP,
/// implemented outside this package.
abstract interface class WifiNetworkControl {
  /// Joins the camera network within [timeout].
  ///
  /// [approved]: the user already approved this network for the app (the
  /// app knows; the session does not), so the platform may look for it
  /// harder without asking again. Android then repeats its request while
  /// the network has not been found (see the app's `WifiChannel`).
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  });

  /// SSID of the current association, or null when unknown or not associated.
  Future<String?> currentSsid();

  /// Leaves the camera network.
  Future<void> leave();

  /// Emits when the OS reports that the joined camera network is gone.
  /// Platforms without that signal never emit; the session's liveness
  /// polling still notices the loss there, only later.
  Stream<void> get lost;
}
