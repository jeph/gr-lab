import 'package:flutter/foundation.dart';

/// When GR Photo sets a camera's clock and sends it the phone's location.
///
/// Every value is GR Photo's choice \[design\], made from what the camera
/// firmware does with a location (research/protocol/geotagging.md §1): it
/// keeps one for 600 s after each write and cannot tell an old position
/// from a new one, so how fresh a position is has to be judged here. None
/// has been tuned on hardware yet.
@immutable
final class GeotagOptions {
  /// The defaults; tests shorten them.
  const new({
    this.fixInterval = const Duration(seconds: 5),
    this.minimumGap = const Duration(seconds: 5),
    this.minimumMove = 5,
    this.keepAlive = const Duration(seconds: 180),
    this.maximumFixAge = const Duration(seconds: 60),
    this.maximumAccuracy = 100,
    this.idleLimit = const Duration(hours: 1),
    this.clockClearDelay = const Duration(milliseconds: 1500),
    this.clockTolerance = const Duration(seconds: 2),
    this.clockRecheck = const Duration(hours: 1),
    this.clockWatch = const Duration(minutes: 1),
  });

  /// How often the phone is asked for a fix while a camera is on.
  final Duration fixInterval;

  /// The shortest time between two writes to the camera.
  final Duration minimumGap;

  /// A fix is written when the phone moved more than this many metres from
  /// the last one written, or more than the fix's own accuracy when that
  /// is larger: closer than its accuracy, a move cannot be told from
  /// noise.
  final double minimumMove;

  /// A phone that has not moved writes again after this long, so the
  /// camera's 600 s never run out while fixes still come: GR WORLD's
  /// slowest interval, which leaves three tries.
  final Duration keepAlive;

  /// A fix older than this is not written: the camera would record it as
  /// where the picture was taken.
  final Duration maximumFixAge;

  /// A fix whose accuracy is worse than this many metres is not written.
  final double maximumAccuracy;

  /// How long a run goes on with the camera off or out of reach before it
  /// ends, so a forgotten phone stops by itself.
  final Duration idleLimit;

  /// How long after a clock write the location is written again: a GR IV
  /// clears its location 1 s after its clock changes.
  final Duration clockClearDelay;

  /// The camera's clock is set when it is at least this far from the
  /// phone's. It reads in whole seconds, so less cannot be told.
  final Duration clockTolerance;

  /// How often the clock of a camera that stays linked is compared again.
  final Duration clockRecheck;

  /// How often the phone's own time zone is looked at, which costs no
  /// exchange with the camera: a change (travel, daylight saving) sets the
  /// camera's clock at once.
  final Duration clockWatch;
}
