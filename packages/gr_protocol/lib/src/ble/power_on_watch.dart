/// A paired camera the platform watches for ([PowerOnWatch]).
final class WatchedCamera {
  /// The camera reached at [deviceId], which the user calls [name].
  const new({required this.deviceId, required this.name});

  /// Platform peripheral id (Android MAC, CoreBluetooth UUID).
  final String deviceId;

  /// The user's name for the camera, for the platform's own prompts.
  final String name;

  /// `deviceId` and `name`.
  Map<String, Object?> toJson() => {'deviceId': deviceId, 'name': name};
}

/// Noticing a camera being switched on while the app is not on screen, or
/// not running, implemented outside this package (native code in the
/// Flutter app, a simulated phone in tests).
///
/// A camera that is on advertises the Camera Information service in its
/// primary advertising packet, and one that is off advertises Client
/// Registration instead (research/camera-models.md §4.1), so the platform
/// can watch for the first with a filter and no connection.
abstract interface class PowerOnWatch {
  /// The platform can watch for a camera with the app not running.
  Future<bool> supported();

  /// The platform's own link between the app and the camera at [deviceId]
  /// exists (Android: a companion device association, which lets the app
  /// start from the background). Always true where none is needed (iOS).
  Future<bool> associated(String deviceId);

  /// Asks the user for that link (Android's companion device prompt);
  /// true when it exists afterwards.
  Future<bool> associate(WatchedCamera camera);

  /// Replaces the set of watched cameras; an empty list stops watching.
  /// Calling it again with the same list starts the watch afresh, so a
  /// camera that went off and comes on again is reported again.
  Future<void> watch(List<WatchedCamera> cameras);

  /// Device ids of watched cameras seen advertising in their on state.
  Stream<String> get sightings;

  /// The sightings that started the app while it was not running; handed
  /// over once.
  Future<List<String>> takeLaunchSightings();
}
