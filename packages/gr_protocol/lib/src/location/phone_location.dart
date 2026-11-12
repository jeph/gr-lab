import 'package:meta/meta.dart';

/// What the phone lets the app know about where it is.
enum LocationAccess {
  /// Precise location is allowed and the phone's location is on.
  precise,

  /// Only approximate location is allowed: fixes are too rough to send to
  /// a camera.
  approximate,

  /// Not allowed yet, and the system can still be asked
  /// ([PhoneLocation.requestAccess]).
  undetermined,

  /// Refused, and the system will not ask again: only its settings change
  /// it ([PhoneLocation.openSettings]).
  blocked,

  /// The phone's location is turned off for every app.
  off,

  /// The platform has no location code (desktop, tests without a fake).
  unsupported,
}

/// How hard the phone looks for its position during a run
/// ([PhoneLocation.start]).
enum LocationMode {
  /// A camera is on and linked: precise fixes, one every interval.
  precise,

  /// Waiting for the camera: nothing the camera layer uses. Android stops
  /// locating; iOS keeps the coarsest updates it has, because those are
  /// what keeps the app running with its screen off \[design\].
  idle,
}

/// One position of the phone.
@immutable
final class PhoneFix {
  /// A fix at [time] (UTC).
  const new({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.time,
    this.altitude,
    this.speed,
  });

  /// Degrees, north positive.
  final double latitude;

  /// Degrees, east positive.
  final double longitude;

  /// Metres above sea level where the phone gives that (iOS, Android 14
  /// and later), otherwise above the WGS 84 ellipsoid; null when the phone
  /// did not say.
  final double? altitude;

  /// Horizontal accuracy in metres: the radius the phone gives the fix.
  final double accuracy;

  /// When the phone fixed the position, in UTC.
  final DateTime time;

  /// Metres per second; null when the phone did not say.
  final double? speed;

  /// For the trace.
  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'accuracy': accuracy,
    'time': time.toIso8601String(),
    'speed': speed,
  };

  @override
  String toString() => 'PhoneFix(${toJson()})';
}

/// The texts of what the platform shows while a run goes on with the app
/// not in front (Android's notification), in the app's language.
@immutable
final class LocationNotice {
  /// The notification's texts.
  const new({
    required this.title,
    required this.text,
    required this.stopLabel,
    required this.channelName,
  });

  /// First line, such as `Sending location to MY GR IV`.
  final String title;

  /// Second line.
  final String text;

  /// The button that ends the run.
  final String stopLabel;

  /// What Android's notification settings call these notifications.
  final String channelName;

  /// For the platform channel and the trace.
  Map<String, Object?> toJson() => {
    'title': title,
    'text': text,
    'stopLabel': stopLabel,
    'channelName': channelName,
  };

  @override
  bool operator ==(Object other) =>
      other is LocationNotice &&
      other.title == title &&
      other.text == text &&
      other.stopLabel == stopLabel &&
      other.channelName == channelName;

  @override
  int get hashCode => Object.hash(title, text, stopLabel, channelName);
}

/// Why a run could not begin ([PhoneLocation.start]).
enum LocationStartFailure {
  /// The app is not in front: the system only lets a run begin there.
  background,

  /// Location is not allowed, or is off.
  denied,

  /// The platform has no location code, or it failed.
  failed,
}

/// Thrown by [PhoneLocation.start] and [PhoneLocation.setMode].
final class LocationStartException implements Exception {
  /// A run that could not begin, or a mode set outside a run.
  const new(this.failure, [this.message = '']);

  /// What stood in the way.
  final LocationStartFailure failure;

  /// What the platform said, for the log.
  final String message;

  @override
  String toString() => 'LocationStartException(${failure.name}): $message';
}

/// The phone's own position, read to geotag a camera's pictures;
/// implemented outside this package.
///
/// A run ([start] to [stop]) is what keeps fixes coming with the app not in
/// front: Android holds a foreground service of the location type with
/// [LocationNotice] as its notification, iOS keeps location updates going
/// in the background and shows its own indicator. Both need the run to
/// begin while the app is in front. During a run [setMode] says whether a
/// camera wants fixes now.
abstract interface class PhoneLocation {
  /// What the phone allows now, without asking.
  Future<LocationAccess> access();

  /// Asks the system for location while the app is in use, when it can
  /// still be asked, and returns what the phone allows afterwards.
  Future<LocationAccess> requestAccess();

  /// Opens the system settings where the user can change the answer: the
  /// app's own page, or the phone's location switch when [access] is
  /// [LocationAccess.off].
  Future<void> openSettings();

  /// Begins a run in [LocationMode.idle], or changes the [notice] and
  /// [interval] of the one under way. [interval] is the time between fixes
  /// in [LocationMode.precise]. Throws [LocationStartException].
  Future<void> start({
    required LocationNotice notice,
    required Duration interval,
  });

  /// Whether a camera wants fixes now. Only during a run: throws
  /// [LocationStartException] outside one.
  Future<void> setMode(LocationMode mode);

  /// Ends the run: no more fixes, and nothing left running or showing.
  /// Does nothing when no run is under way.
  Future<void> stop();

  /// Every fix of the run, as the phone delivers it. Fixes in
  /// [LocationMode.idle] (iOS) come through too.
  Stream<PhoneFix> get fixes;

  /// The user ended the run from outside the app (the notification's
  /// button). The platform has stopped it already; [stop] is still safe to
  /// call.
  Stream<void> get stopRequests;

  /// The phone's answer changed during a run: location turned off, or the
  /// permission changed in the system settings.
  Stream<LocationAccess> get accessChanges;
}
