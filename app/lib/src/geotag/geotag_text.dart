import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';

/// What live geotagging is doing, in words: the text of the phone's notice
/// while it runs.
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

/// What holds live geotagging up that the user can put right, in words:
/// shown under its switch on the camera's card, below the line that says
/// what the switch does. Null while it runs or only waits (for the camera
/// to be on and in reach, or for a position).
String? geotagProblemText(AppLocalizations l10n, GeotagStatus status) =>
    switch (status) {
      GeotagStatus.permissionDenied ||
      GeotagStatus.preciseNeeded ||
      GeotagStatus.locationOff ||
      GeotagStatus.stopped ||
      GeotagStatus.needsApp ||
      GeotagStatus.offOnCamera => geotagStatusText(l10n, status),
      GeotagStatus.off ||
      GeotagStatus.unsupported ||
      GeotagStatus.waitingForCamera ||
      GeotagStatus.waitingForLocation ||
      GeotagStatus.sending => null,
    };

/// What the phone still has to allow, in words: shown where a location
/// mode was refused or is paused, beside a button to the phone's settings.
String geotagNeedText(AppLocalizations l10n, GeotagNeed need) => switch (need) {
  GeotagNeed.phoneLocation => l10n.geotagStatusLocationOff,
  GeotagNeed.permission => l10n.geotagStatusPermissionDenied,
  GeotagNeed.precise => l10n.geotagStatusPreciseNeeded,
  GeotagNeed.always => l10n.geotagNeedAlways,
};
