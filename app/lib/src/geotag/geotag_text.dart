import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';

/// What live geotagging is doing, in words: the line under its switch on
/// the camera's card and the text of the phone's notice while it runs.
/// While it is off, the line says what the switch does.
String geotagStatusText(AppLocalizations l10n, GeotagStatus status) =>
    switch (status) {
      GeotagStatus.off => l10n.geotagLiveSubtitle,
      GeotagStatus.unsupported => l10n.geotagStatusUnsupported,
      GeotagStatus.permissionDenied => l10n.geotagStatusPermissionDenied,
      GeotagStatus.preciseNeeded => l10n.geotagStatusPreciseNeeded,
      GeotagStatus.locationOff => l10n.geotagStatusLocationOff,
      GeotagStatus.stopped => l10n.geotagStatusStopped,
      GeotagStatus.needsApp => l10n.geotagStatusNeedsApp,
      GeotagStatus.waitingForCamera => l10n.geotagStatusWaitingForCamera,
      GeotagStatus.offOnCamera => l10n.geotagStatusOffOnCamera,
      GeotagStatus.waitingForLocation => l10n.geotagStatusWaitingForLocation,
      GeotagStatus.sending => l10n.geotagStatusSending,
    };

/// What the phone still has to allow, in words: shown where a location
/// mode was refused or is paused, beside a button to the phone's settings.
String geotagNeedText(AppLocalizations l10n, GeotagNeed need) => switch (need) {
  GeotagNeed.phoneLocation => l10n.geotagStatusLocationOff,
  GeotagNeed.permission => l10n.geotagStatusPermissionDenied,
  GeotagNeed.precise => l10n.geotagStatusPreciseNeeded,
  GeotagNeed.always => l10n.geotagNeedAlways,
};
