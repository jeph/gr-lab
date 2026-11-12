import 'package:gr_camera/gr_camera.dart';

/// Something the phone still has to allow before a location mode can run.
/// The view words it (AGENTS.md, "Text the user sees") and offers
/// [settingsPage].
enum GeotagNeed {
  /// Location is off for the whole phone.
  phoneLocation,

  /// GR Photo may not locate the phone.
  permission,

  /// Only approximate location is allowed, which is kilometres off.
  precise,

  /// Location is allowed while GR Photo is in use, not at all times.
  always,

  /// The phone's own link between GR Photo and the camera, which lets the
  /// app start when the camera is switched on, was not made (Android's
  /// companion device prompt was refused).
  cameraLink;

  /// The page of the phone's settings where the user allows it; null when
  /// none does (the camera link is asked for again instead).
  LocationSettingsPage? get settingsPage => switch (this) {
    phoneLocation => LocationSettingsPage.phone,
    permission || precise || always => LocationSettingsPage.app,
    cameraLink => null,
  };
}
