import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/services.dart';

/// The texts of the notification Android shows while live geotagging runs
/// with the app not in front, in the app's language.
@immutable
final class GeotagTexts {
  const new({
    required this.sendingTitle,
    required this.sendingText,
    required this.waitingTitle,
    required this.waitingText,
    required this.stopLabel,
    required this.channelName,
  });

  /// The first line while the phone is located, for a camera's name.
  final String Function(String cameraName) sendingTitle;

  /// The second line while the phone is located.
  final String sendingText;

  /// The first line while the camera is off or away, for a camera's name.
  final String Function(String cameraName) waitingTitle;

  /// The second line while the camera is off or away.
  final String waitingText;

  /// The button that stops it.
  final String stopLabel;

  /// What Android's notification settings call these notifications.
  final String channelName;
}

/// How turning live geotagging on ended ([GeotagModel.turnOnLive]).
enum GeotagTurnOn {
  /// It is on.
  on,

  /// The phone only allows approximate location: it is on, and sends
  /// nothing until precise location is allowed in the system settings.
  needsPreciseLocation,

  /// The phone's location is off for every app: it is on, and sends
  /// nothing until that is turned on.
  locationOff,

  /// The user refused location, so it stays off.
  refused,

  /// The phone has no location GR Photo can read, so it stays off.
  unavailable,
}

/// Live geotagging and the clock of the current camera, as the app keeps
/// and shows them: the user's choices are saved with the camera
/// ([SavedCamera.liveGeotagging], [SavedCamera.syncTime]) and handed to the
/// camera layer (`CameraGeotagging`, `CameraClock`), which does the work.
final class GeotagModel extends ChangeNotifier {
  new({
    required this.services,
    required this.cameras,
    required this.connection,
  }) {
    _foreground = connection.foreground;
    cameras.addListener(_apply);
    connection.addListener(_onConnection);
    _geotagging.addListener(notifyListeners);
  }

  final AppServices services;
  final CameraStore cameras;
  final ConnectionController connection;
  late bool _foreground;
  GeotagTexts? _texts;
  String? _refusedSerial;

  CameraGeotagging get _geotagging => services.camera.geotagging;

  /// The app's language changed, or was first known.
  void setTexts(GeotagTexts texts) {
    _texts = texts;
    _apply();
  }

  /// The current camera can take a location from a phone.
  bool get supported => connection.body.supports(CameraFeature.geotagging);

  /// Live geotagging is turned on for the current camera.
  bool get live => cameras.current?.liveGeotagging ?? false;

  /// The current camera's clock is kept on the phone's time. Live
  /// geotagging keeps it in step whatever this says.
  bool get syncTime => cameras.current?.syncTime ?? true;

  /// The user turned live geotagging on for the current camera and
  /// refused the phone's location, so it is off: the camera sheet says
  /// what is missing. Allowing location in the system settings and coming
  /// back turns it on.
  bool get refused {
    final serial = cameras.current?.serial;
    return !live && serial != null && serial == _refusedSerial;
  }

  /// Where live geotagging stands.
  GeotagStatus get status => _geotagging.status;

  /// When the camera last took a location from this phone.
  DateTime? get lastSentAt => _geotagging.lastSentAt;

  /// The current camera is linked, can be geotagged, and its user has not
  /// been asked about it yet: the app offers it once.
  bool get offerDue {
    final camera = cameras.current;
    if (camera == null || camera.liveGeotagging != null || !supported) {
      return false;
    }
    return connection.cameraSession?.bleLinked ?? false;
  }

  /// The user turned live geotagging on (the offer, or the camera sheet's
  /// switch): asks the system for the phone's location when it can still
  /// be asked. Refused, the choice is saved as off, so the offer does not
  /// come back; the switch asks again.
  Future<GeotagTurnOn> turnOnLive() async {
    final camera = cameras.current;
    if (camera == null) return GeotagTurnOn.unavailable;
    final access = await services.camera.requestLocationAccess();
    final outcome = switch (access) {
      LocationAccess.precise => GeotagTurnOn.on,
      LocationAccess.approximate => GeotagTurnOn.needsPreciseLocation,
      LocationAccess.off => GeotagTurnOn.locationOff,
      LocationAccess.undetermined ||
      LocationAccess.blocked => GeotagTurnOn.refused,
      LocationAccess.unsupported => GeotagTurnOn.unavailable,
    };
    final on =
        outcome != GeotagTurnOn.refused && outcome != GeotagTurnOn.unavailable;
    _refusedSerial = outcome == GeotagTurnOn.refused ? camera.serial : null;
    await cameras.setLiveGeotagging(camera.serial, on: on);
    notifyListeners();
    if (on && cameras.current?.serial == camera.serial) {
      await _geotagging.setEnabled(enabled: true);
    }
    return outcome;
  }

  /// The user turned live geotagging off, or declined the offer.
  Future<void> turnOffLive() async {
    final camera = cameras.current;
    if (camera == null) return;
    final wasOn = camera.liveGeotagging ?? false;
    await cameras.setLiveGeotagging(camera.serial, on: false);
    if (wasOn) await _geotagging.setEnabled(enabled: false);
  }

  /// The user changed whether the camera's clock follows the phone's.
  Future<void> setSyncTime({required bool on}) async {
    final camera = cameras.current;
    if (camera == null) return;
    await cameras.setSyncTime(camera.serial, on: on);
  }

  /// Opens the system settings where location is allowed.
  Future<void> openLocationSettings() => services.camera.openLocationSettings();

  void _onConnection() {
    final foreground = connection.foreground;
    final resumed = foreground && !_foreground;
    _foreground = foreground;
    if (resumed) {
      unawaited(_geotagging.appResumed());
      if (refused) unawaited(_turnOnIfAllowedSince());
    }
    _apply();
  }

  /// Back in the app after a refusal: the user may have allowed location
  /// in the system settings, which is what they were turning on.
  Future<void> _turnOnIfAllowedSince() async {
    final access = await services.camera.locationAccess();
    if (!refused) return;
    switch (access) {
      case LocationAccess.precise ||
          LocationAccess.approximate ||
          LocationAccess.off:
        await turnOnLive();
      case LocationAccess.undetermined ||
          LocationAccess.blocked ||
          LocationAccess.unsupported:
    }
  }

  /// Hands the current camera's choices to the camera layer.
  void _apply() {
    final camera = cameras.current;
    connection.cameraSession?.clock.enabled = camera?.syncTime ?? false;
    final texts = _texts;
    if (texts == null) return;
    final name = camera?.name ?? '';
    _geotagging.configure(
      enabled: camera?.liveGeotagging ?? false,
      waitingNotice: LocationNotice(
        title: texts.waitingTitle(name),
        text: texts.waitingText,
        stopLabel: texts.stopLabel,
        channelName: texts.channelName,
      ),
      sendingNotice: LocationNotice(
        title: texts.sendingTitle(name),
        text: texts.sendingText,
        stopLabel: texts.stopLabel,
        channelName: texts.channelName,
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    cameras.removeListener(_apply);
    connection.removeListener(_onConnection);
    _geotagging.removeListener(notifyListeners);
    super.dispose();
  }
}
