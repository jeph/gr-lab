import 'package:meta/meta.dart';

/// One position of the phone, as its location service reported it.
final class LocationFix {
  /// A fix at [latitude], [longitude] taken at [time].
  const new({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.time,
    this.altitude,
  });

  /// Reads the record [toJson] writes; null when a field is missing or of
  /// the wrong type.
  static LocationFix? fromJson(Map<Object?, Object?> json) {
    final latitude = json['lat'];
    final longitude = json['lon'];
    final accuracy = json['acc'];
    final time = json['t'];
    final altitude = json['alt'];
    if (latitude is! num || longitude is! num || time is! int) return null;
    return LocationFix(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      accuracy: accuracy is num ? accuracy.toDouble() : double.infinity,
      time: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
      altitude: altitude is num ? altitude.toDouble() : null,
    );
  }

  /// Degrees north of the equator, WGS 84.
  final double latitude;

  /// Degrees east of Greenwich, WGS 84.
  final double longitude;

  /// Metres above the WGS 84 ellipsoid (Android) or mean sea level (iOS);
  /// null when the phone gave none.
  final double? altitude;

  /// Radius in metres the phone gives for the position (about 68 %
  /// confidence); infinite when it gave none.
  final double accuracy;

  /// When the phone took the fix, UTC.
  final DateTime time;

  /// `lat`, `lon`, `acc` (metres), `t` (milliseconds since the epoch, UTC)
  /// and `alt` when known: the record the native code sends too.
  Map<String, Object?> toJson() => {
    'lat': latitude,
    'lon': longitude,
    if (accuracy.isFinite) 'acc': accuracy,
    't': time.millisecondsSinceEpoch,
    'alt': ?altitude,
  };

  @override
  String toString() =>
      'LocationFix($latitude, $longitude ±$accuracy m at '
      '${time.toIso8601String()})';
}

/// How far the user lets the app locate the phone.
enum LocationPermission {
  /// Not allowed: never asked, or refused.
  denied,

  /// Allowed while the app is in use: on screen, or carrying on from there
  /// with what the platform shows for it (Android's foreground service
  /// notification, the iOS location indicator).
  whileInUse,

  /// Allowed at all times ("Allow all the time" on Android, "Always" on
  /// iOS): the only level at which the app may start locating the phone
  /// while it is not on screen.
  always,
}

/// What the app may do with the phone's location right now.
@immutable
final class LocationAccess {
  /// Access with [permission], [precise] and [serviceOn] as the platform
  /// reports them.
  const new({
    required this.permission,
    required this.precise,
    required this.serviceOn,
  });

  /// Reads the map the native code sends (`permission`, `precise`,
  /// `service`); anything missing counts as not allowed.
  factory fromJson(Map<Object?, Object?> json) => LocationAccess(
    permission: LocationPermission.values.firstWhere(
      (p) => p.name == json['permission'],
      orElse: () => LocationPermission.denied,
    ),
    precise: json['precise'] == true,
    serviceOn: json['service'] == true,
  );

  /// No access at all.
  static const none = LocationAccess(
    permission: LocationPermission.denied,
    precise: false,
    serviceOn: false,
  );

  /// What the user allowed the app.
  final LocationPermission permission;

  /// The app gets precise positions. False when the user allowed only an
  /// approximate location, which is kilometres off.
  final bool precise;

  /// Location is switched on for the whole phone.
  final bool serviceOn;

  /// Positions good enough to send to a camera can be had now, at least
  /// while the app is in use.
  bool get usable =>
      serviceOn && precise && permission != LocationPermission.denied;

  /// `permission`, `precise` and `service`, as [LocationAccess.fromJson]
  /// reads them.
  Map<String, Object?> toJson() => {
    'permission': permission.name,
    'precise': precise,
    'service': serviceOn,
  };

  @override
  bool operator ==(Object other) =>
      other is LocationAccess &&
      other.permission == permission &&
      other.precise == precise &&
      other.serviceOn == serviceOn;

  @override
  int get hashCode => Object.hash(permission, precise, serviceOn);

  @override
  String toString() =>
      'LocationAccess(${permission.name}, precise: $precise, '
      'serviceOn: $serviceOn)';
}

/// A page of the phone's settings that [PhoneLocation.openSettings] opens.
enum LocationSettingsPage {
  /// The app's own permissions.
  app,

  /// The switch that turns location on for the whole phone. iOS cannot
  /// open it and opens the app's page instead.
  phone,
}

/// What the platform shows while a [PhoneLocation.holdRun] is held; the
/// texts are the app's, already in the user's language.
final class LocationRunNotice {
  /// A notice titled [title] with [text] under it and a [stopLabel] button,
  /// in the notification category named [channel].
  const new({
    required this.title,
    required this.text,
    required this.stopLabel,
    required this.channel,
  });

  /// First line, e.g. the camera the location goes to.
  final String title;

  /// Second line: what is happening now.
  final String text;

  /// Label of the button that ends the run.
  final String stopLabel;

  /// Name of the category the platform lists the notice under in its own
  /// notification settings (Android's notification channel).
  final String channel;

  /// `title`, `text`, `stopLabel` and `channel`.
  Map<String, Object?> toJson() => {
    'title': title,
    'text': text,
    'stopLabel': stopLabel,
    'channel': channel,
  };
}

/// Why [PhoneLocation.holdRun] could not hold a run.
enum LocationRunRefusal {
  /// The app is not on screen and the platform lets it start a run from
  /// there only with [LocationPermission.always].
  background,

  /// Location is not allowed, or is off for the whole phone.
  noAccess,

  /// The platform has no way to keep a run going, or failed to start it.
  unsupported,
}

/// Thrown by [PhoneLocation.holdRun].
final class LocationRunException implements Exception {
  /// A run refused for [refusal], with the platform's [message].
  const new(this.refusal, [this.message]);

  /// Why the run was refused.
  final LocationRunRefusal refusal;

  /// What the platform said, for the log.
  final String? message;

  @override
  String toString() =>
      'LocationRunException(${refusal.name})'
      '${message == null ? '' : ': $message'}';
}

/// The phone's location service, implemented outside this package (native
/// code in the Flutter app, a simulated phone in tests and the demo).
///
/// Three uses, independent of each other:
///
/// - [updates] and [current] give precise positions for a camera that is on
///   (live geotagging).
/// - [holdRun] keeps the app going with its screen off while live
///   geotagging runs or waits for the camera.
/// - [setHistory] has the platform record where the phone is in the cheapest
///   way it has, with the app closed too, and [takeHistory] hands those
///   positions over.
abstract interface class PhoneLocation {
  /// What the app may do now. Never prompts.
  Future<LocationAccess> access();

  /// Emits the access whenever it may have changed: after a prompt, when the
  /// app comes back on screen, when the platform reports a change.
  Stream<LocationAccess> get accessChanges;

  /// Asks the user for precise location while the app is in use, when the
  /// platform still shows its prompt; returns the access afterwards. A
  /// platform that no longer asks returns the unchanged access at once.
  Future<LocationAccess> requestWhileInUse();

  /// Asks the user for location at all times. Call it only once
  /// [LocationPermission.whileInUse] is held: both platforms refuse it
  /// before. Android shows the app's location settings page for it; iOS
  /// shows a prompt once and nothing after that. Returns the access when
  /// the user is back in the app.
  Future<LocationAccess> requestAlways();

  /// Opens [page] of the phone's settings.
  Future<void> openSettings(LocationSettingsPage page);

  /// Precise positions, as often as the phone has them, for as long as the
  /// stream has a listener; the phone is located for nothing else. Emits
  /// nothing while access is missing: watch [accessChanges] for that.
  Stream<LocationFix> get updates;

  /// One newly taken position, or null when the phone got none within
  /// [timeout]. Never a stored one.
  Future<LocationFix?> current({required Duration timeout});

  /// Keeps the app running off screen for live geotagging, showing
  /// [notice] where the platform shows one (Android's foreground service
  /// notification), or replaces the notice of a run already held. With
  /// [awake] the processor is kept on with the screen off (a camera is on
  /// and being written to); without it the run only waits. Throws
  /// [LocationRunException].
  Future<void> holdRun(LocationRunNotice notice, {required bool awake});

  /// Ends what [holdRun] started; nothing happens when no run is held.
  Future<void> releaseRun();

  /// Emits when the user ended the run from the platform's notice (its Stop
  /// button). The run is released already.
  Stream<void> get runStops;

  /// Turns the platform's own recording of the phone's position on or off.
  /// It goes on with the app closed and after the phone restarts, and
  /// needs [LocationPermission.always]; without that it records nothing
  /// until the permission is back.
  Future<void> setHistory({required bool enabled});

  /// The positions recorded since the last call, oldest first; the
  /// platform forgets them once they are handed over.
  Future<List<LocationFix>> takeHistory();

  /// Emits when the platform recorded a position while the app runs, so
  /// [takeHistory] has something to hand over.
  Stream<void> get historyPending;
}
