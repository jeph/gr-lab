import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/geotag/download_geotagger.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';
import 'package:grphoto/src/geotag/geotag_text.dart';
import 'package:grphoto/src/geotag/location_history.dart';
import 'package:grphoto/src/services.dart';

/// Geotagging as the app runs it, with no widget involved: live geotagging
/// carries on with the app not on screen, so everything here is driven by
/// listeners and streams.
///
/// **Live geotagging**, per camera (`SavedCamera.liveGeotagging`): the
/// camera layer sends the phone's location to a camera that is on
/// ([CameraGeotagging]), from when GR Photo is opened and has linked the
/// camera. This controller gives each session its settings, saves that
/// the camera took the Store Location Info value it was owed, and turns
/// the setting off when the user presses Stop on the phone's notice. Nothing
/// starts GR Photo for a camera that is switched on while the app is not
/// running \[design\]: that was tried and did not start it
/// (research/protocol/geotagging.md §6.3).
///
/// **Background geotagging**, per camera
/// (`SavedCamera.backgroundGeotagging`): while it is on for any paired
/// camera the phone records where it is by itself
/// ([PhoneLocation.setHistory]), this controller moves those positions
/// into the [history], and [geotagger] gives the photos downloaded from a
/// camera that has it on the nearest one. The positions live geotagging
/// takes are kept in the history too then. A permission reduced later
/// leaves the setting on: [backgroundPausedBy] says what is missing, and
/// recording resumes by itself when it is back.
///
/// **The camera's clock**, per camera (`SavedCamera.keepsClock`): kept on
/// the phone's time while the user wants it, and always with background
/// geotagging, which matches photos by the time the camera wrote.
final class GeotagController extends ChangeNotifier {
  new _({
    required this.connection,
    required this.cameras,
    required this.settings,
    required this.history,
    required this._location,
  });

  /// Opens the location history under [AppServices.dataDir] and follows
  /// the connection, the paired cameras, the settings and the phone from
  /// now on. [start] then puts the phone in line with the cameras'
  /// settings.
  static Future<GeotagController> open({
    required AppServices services,
    required ConnectionController connection,
    required CameraStore cameras,
    required SettingsController settings,
  }) async => GeotagController._(
    connection: connection,
    cameras: cameras,
    settings: settings,
    history: await LocationHistory.open(
      Directory('${services.dataDir.path}/location-history'),
    ),
    location: services.camera.location,
  ).._listen();

  /// How long a recorded position is kept: a photo downloaded later than
  /// this after it was taken gets no location from the history. \[design\]
  static const historyKept = Duration(days: 90);

  /// The session whose geotagging this controller configures.
  final ConnectionController connection;

  /// The paired cameras, with each one's geotagging settings.
  final CameraStore cameras;

  /// Holds the app's language, for the phone's notice.
  final SettingsController settings;

  /// Where the phone has been, for background geotagging.
  final LocationHistory history;

  final PhoneLocation _location;

  /// Gives the photos downloaded from a camera with background geotagging
  /// on a location from the [history]; the download engine runs
  /// [DownloadGeotagger.tag] before it saves a shot. Positions the phone
  /// recorded meanwhile are taken over first.
  late final DownloadGeotagger geotagger = DownloadGeotagger(
    history: history,
    enabled: (serial) => _camera(serial)?.backgroundGeotagging ?? false,
    beforeMatch: drainHistory,
    log: (line) => debugPrint(line),
  );

  final List<StreamSubscription<void>> _phone = [];
  LocationAccess _access = LocationAccess.none;

  /// The phone leaves GR Photo alone while it runs off screen, as it
  /// answered last ([PhoneLocation.backgroundUnrestricted]).
  bool _unrestricted = true;

  CameraSession? _session;
  CameraGeotagging? _geotagging;

  /// Serial number of [_session]'s camera.
  String? _sessionSerial;
  StreamSubscription<LocationFix>? _fixes;
  StreamSubscription<bool>? _written;
  StreamSubscription<void>? _stops;

  /// What [_geotagging] was configured with last, so that it is told again
  /// only when something changed.
  Object? _configured;

  /// Whether the phone was last told to record its location history, and
  /// that call.
  bool? _recording;
  Future<void> _historySet = Future.value();

  /// Every history job so far; the next one runs after them.
  Future<void> _historyJobs = Future.value();

  bool _disposed = false;

  // ---------------------------------------------------------------- state

  /// What GR Photo may do with the phone's location, as the phone reported
  /// it last.
  LocationAccess get access => _access;

  /// Whether the current camera can be sent a location at all
  /// ([CameraFeature.geotagging]).
  bool get supported => connection.body.supports(CameraFeature.geotagging);

  /// Whether [camera] can be sent a location at all: for the current
  /// camera by what its link read too ([supported]), for another by its
  /// model and firmware as saved.
  bool supports(SavedCamera camera) =>
      _isCurrent(camera) ? supported : camera.supportsGeotagging;

  /// What live geotagging is doing for the current camera
  /// ([GeotagStatus.unsupported] without one).
  GeotagStatus get status {
    final camera = connection.camera;
    return camera == null ? GeotagStatus.unsupported : statusOf(camera);
  }

  /// What live geotagging is doing for [camera]: the session's own word
  /// for the current camera while there is one, otherwise what the setting
  /// and the phone's access make of it.
  GeotagStatus statusOf(SavedCamera camera) {
    if (!supports(camera)) return GeotagStatus.unsupported;
    if (!camera.liveGeotagging) return GeotagStatus.off;
    final status = _isCurrent(camera) ? _geotagging?.status : null;
    // No session, or one that has not taken the setting in yet.
    if (status == null || status == GeotagStatus.off) {
      return switch (_liveNeed(_access)) {
        GeotagNeed.phoneLocation => GeotagStatus.locationOff,
        GeotagNeed.permission => GeotagStatus.permissionDenied,
        GeotagNeed.precise => GeotagStatus.preciseNeeded,
        _ => GeotagStatus.waitingForCamera,
      };
    }
    final needsCameraOn = switch (status) {
      GeotagStatus.offOnCamera ||
      GeotagStatus.waitingForLocation ||
      GeotagStatus.sending => true,
      _ => false,
    };
    // A session that let go of a camera that is off holds no link to send
    // over, whatever the camera still holds.
    return needsCameraOn && connection.parked
        ? GeotagStatus.waitingForCamera
        : status;
  }

  bool _isCurrent(SavedCamera camera) =>
      camera.serial == connection.camera?.serial;

  /// What the phone has to allow before [status] can move on; null for a
  /// status that waits for something else.
  static GeotagNeed? needOf(GeotagStatus status) => switch (status) {
    GeotagStatus.permissionDenied => GeotagNeed.permission,
    GeotagStatus.preciseNeeded => GeotagNeed.precise,
    GeotagStatus.locationOff => GeotagNeed.phoneLocation,
    _ => null,
  };

  /// The phone may stop GR Photo while the screen is off, a camera with
  /// live geotagging on or not: a camera switched on then is linked only
  /// once the screen is on again (observed on an Android phone whose maker
  /// freezes apps, research/protocol/geotagging.md §6.5). [allowBackground]
  /// asks the user to exempt GR Photo. Never true on iOS.
  bool get backgroundRestricted => !_unrestricted;

  /// Location is allowed at all times, which recording the location
  /// history takes.
  bool get locationAlways => _access.permission == LocationPermission.always;

  /// What keeps background geotagging from recording while it is on for
  /// [camera]; null while it records, and while it is off.
  GeotagNeed? backgroundPausedBy(SavedCamera camera) =>
      camera.backgroundGeotagging ? _alwaysNeed(_access) : null;

  /// Background geotagging is on for a paired camera, so the phone is to
  /// record where it is.
  bool get _backgroundWanted =>
      cameras.cameras.any((camera) => camera.backgroundGeotagging);

  // -------------------------------------------------------------- actions

  /// Turns live geotagging on for [serial]'s camera, asking for the phone's
  /// location first where the phone still asks. Returns null when it is
  /// on: the camera's Store Location Info is turned on as soon as the
  /// camera is on and linked. Otherwise it stays off, and the result says
  /// what the phone lacks.
  ///
  /// A phone that may stop GR Photo with the screen off
  /// ([backgroundRestricted]) then asks whether it may leave it alone; live
  /// geotagging is on whatever the answer.
  Future<GeotagNeed?> turnLiveOn(String serial) async {
    final need = _liveNeed(await _ask(_location.requestWhileInUse));
    if (need != null) return need;
    await _saved(cameras.setLiveGeotagging(serial, on: true));
    await allowBackground();
    return null;
  }

  /// Asks the user to let GR Photo run with the screen off, where the phone
  /// may stop it ([backgroundRestricted]).
  Future<void> allowBackground() =>
      _readUnrestricted(_location.requestBackgroundUnrestricted);

  /// Turns live geotagging off for [serial]'s camera. Its Store Location
  /// Info is turned off as soon as the camera is on and linked, which
  /// clears the location it holds.
  Future<void> turnLiveOff(String serial) =>
      _saved(cameras.setLiveGeotagging(serial, on: false));

  /// Turns keeping [serial]'s clock on the phone's time on or off.
  /// Background geotagging keeps it there whatever this says
  /// ([SavedCamera.keepsClock]).
  Future<void> setSyncClock(String serial, {required bool on}) =>
      _saved(cameras.setSyncClock(serial, on: on));

  /// Writes Store Location Info on, after the user turned it off in the
  /// camera's menu ([GeotagStatus.offOnCamera]).
  Future<void> turnOnStoreLocationInfo() async {
    final geotagging = _geotagging;
    if (geotagging == null) return;
    await _guard<void>(
      'turning on Store Location Info',
      geotagging.turnOnStoreLocationInfo,
      null,
    );
  }

  /// Turns background geotagging on for [serial]'s camera: asks for the
  /// phone's location while GR Photo is in use, which the phone wants
  /// granted first, then for location at all times. Only that turns it on;
  /// otherwise it stays off and the result says what the phone lacks.
  Future<GeotagNeed?> turnBackgroundOn(String serial) async {
    final need = _liveNeed(await _ask(_location.requestWhileInUse));
    if (need != null) return need;
    if (!locationAlways) await _ask(_location.requestAlways);
    if (!locationAlways) return GeotagNeed.always;
    await _saved(cameras.setBackgroundGeotagging(serial, on: true));
    await _setHistory();
    return null;
  }

  /// Turns background geotagging off for [serial]'s camera. The phone
  /// stops recording where it is once no camera has it on; what it
  /// recorded stays in the [history] until it is 90 days old or deleted
  /// ([deleteHistory]).
  Future<void> turnBackgroundOff(String serial) async {
    await _saved(cameras.setBackgroundGeotagging(serial, on: false));
    await _setHistory();
  }

  /// Deletes every recorded position: the [history], and what the phone
  /// recorded and has not handed over yet. False when some of it could
  /// not be deleted.
  Future<bool> deleteHistory() async {
    var deleted = false;
    await _historyJob(() async {
      await _location.takeHistory();
      await history.clear();
      deleted = true;
    });
    return deleted;
  }

  /// Moves the positions the phone recorded by itself into the [history].
  /// Never fails: a failure goes to the debug log.
  Future<void> drainHistory() => _historyJob(() async {
    final fixes = await _location.takeHistory();
    if (fixes.isEmpty) return;
    await history.add(fixes);
  });

  /// Opens the page of the phone's settings where [need] is allowed.
  Future<void> openSettings(GeotagNeed need) async {
    await _guard<void>(
      'opening the settings',
      () => _location.openSettings(need.settingsPage),
      null,
    );
  }

  // ------------------------------------------------------------ following

  void _listen() {
    connection.addListener(_onConnection);
    cameras.addListener(_onCameras);
    settings.addListener(_onSettings);
    _phone
      ..add(_location.accessChanges.listen(_onAccess))
      ..add(_location.historyPending.listen((_) => unawaited(drainHistory())));
  }

  /// Reads where the phone stands and puts its recording in line with the
  /// cameras' settings. Called once, when the app's other models exist.
  Future<void> start() async {
    _access = await _guard('reading the access', _location.access, _access);
    await _readUnrestricted(_location.backgroundUnrestricted);
    // The cameras file decides, also after a restore that kept only one
    // of the two.
    await _setHistory(again: true);
    unawaited(drainHistory());
    _onConnection();
  }

  void _onConnection() {
    if (_disposed) return;
    final session = connection.cameraSession;
    if (!identical(session, _session)) _attach(session);
    notifyListeners();
  }

  void _onCameras() {
    if (_disposed) return;
    _configure();
    // Background geotagging was switched, or a camera that had it on was
    // forgotten.
    unawaited(_setHistory());
    notifyListeners();
  }

  void _onSettings() {
    if (_disposed) return;
    // A change of language changes the notice.
    _configure();
    notifyListeners();
  }

  void _onAccess(LocationAccess access) {
    if (_disposed) return;
    final regained =
        access.permission == LocationPermission.always && !locationAlways;
    _access = access;
    notifyListeners();
    // Back from the phone's settings, where this is allowed too.
    unawaited(_readUnrestricted(_location.backgroundUnrestricted));
    if (!regained || !_backgroundWanted) return;
    unawaited(_setHistory(again: true));
    unawaited(drainHistory());
  }

  /// The least time between two of live geotagging's positions kept in the
  /// history.
  static const _liveHistoryEvery = Duration(seconds: 15);

  /// When the last of live geotagging's positions kept in the history was
  /// taken.
  DateTime? _liveHistoryAt;

  void _attach(CameraSession? session) {
    _geotagging?.removeListener(_onGeotagging);
    unawaited(_fixes?.cancel());
    unawaited(_written?.cancel());
    unawaited(_stops?.cancel());
    _fixes = null;
    _written = null;
    _stops = null;
    _configured = null;
    _session = session;
    _sessionSerial = session == null ? null : connection.camera?.serial;
    final geotagging = _geotagging = session?.geotagging;
    if (geotagging == null) return;
    geotagging.addListener(_onGeotagging);
    _fixes = geotagging.fixes.listen(_onFix);
    _written = geotagging.storeLocationInfoWritten.listen(
      _onStoreLocationInfoWritten,
    );
    _stops = geotagging.stoppedByUser.listen((_) => _onStoppedByUser());
    _configure();
  }

  void _onGeotagging() {
    if (!_disposed) notifyListeners();
  }

  /// Hands the session its camera's settings, when they changed.
  void _configure() {
    final geotagging = _geotagging;
    final camera = _camera(_sessionSerial);
    if (geotagging == null || camera == null) return;
    final serial = camera.serial;
    final configured = (
      session: _session,
      live: camera.liveGeotagging,
      syncClock: camera.keepsClock,
      pending: camera.storeLocationInfoPending,
      name: camera.name,
      language: _l10n.localeName,
    );
    if (configured == _configured) return;
    _configured = configured;
    geotagging.configure(
      GeotagSettings(
        live: camera.liveGeotagging,
        syncClock: camera.keepsClock,
        storeLocationInfoPending: camera.storeLocationInfoPending,
      ),
      // Asked for each time the notice changes, so it follows a new name.
      notice: (status) => _notice(_camera(serial)?.name ?? camera.name, status),
    );
  }

  /// What the phone shows while live geotagging runs with GR Photo not on
  /// screen, in the app's language.
  LocationRunNotice _notice(String cameraName, GeotagStatus status) {
    final l10n = _l10n;
    return LocationRunNotice(
      title: l10n.geotagNoticeTitle(cameraName),
      text: geotagStatusText(l10n, status),
      stopLabel: l10n.geotagNoticeStop,
      channel: l10n.geotagNoticeChannel,
    );
  }

  /// The app's messages in the language chosen in Settings, or else the
  /// phone's: what `MaterialApp` resolves, without a widget to ask.
  AppLocalizations get _l10n => lookupAppLocalizations(
    settings.language ??
        resolveAppLocale(
          PlatformDispatcher.instance.locales,
          AppLocalizations.supportedLocales,
        ),
  );

  /// The user pressed Stop on the phone's notice: live geotagging is
  /// turned off for the session's camera, as its switch does, until the
  /// user turns it on again.
  void _onStoppedByUser() {
    final serial = _sessionSerial;
    if (serial == null) return;
    unawaited(turnLiveOff(serial));
  }

  void _onStoreLocationInfoWritten(bool written) {
    final serial = _sessionSerial;
    if (serial == null) return;
    unawaited(
      _saved(cameras.storeLocationInfoWritten(serial, written: written)),
    );
  }

  /// A position live geotagging took for the camera: kept for the photos
  /// the camera does not tag, while the phone records its history (so
  /// while background geotagging is on for any camera). The phone takes
  /// about one a second while the camera is on, so only one every
  /// [_liveHistoryEvery] is kept: a photo is matched by its capture time,
  /// which that resolves well, and the history stays small.
  void _onFix(LocationFix fix) {
    if (!_backgroundWanted) return;
    final last = _liveHistoryAt;
    if (last != null && fix.time.difference(last).abs() < _liveHistoryEvery) {
      return;
    }
    _liveHistoryAt = fix.time;
    unawaited(_historyJob(() => history.add([fix])));
  }

  /// Puts the phone's own recording in line with the cameras' settings:
  /// on while background geotagging is on for any of them. Without
  /// location at all times it records nothing; it is asked again when that
  /// comes back ([_onAccess]). The phone is told when that changed, or
  /// [again].
  Future<void> _setHistory({bool again = false}) {
    final enabled = _backgroundWanted;
    if (!again && enabled == _recording) return _historySet;
    _recording = enabled;
    return _historySet = _guard<void>(
      'switching the location history',
      () => _location.setHistory(enabled: enabled),
      null,
    );
  }

  /// Runs [job] after every history job before it, so the phone's
  /// positions are taken over in order and a deletion misses none. The
  /// returned future never fails.
  Future<void> _historyJob(Future<void> Function() job) =>
      _historyJobs = _historyJobs.then((_) => job()).catchError((Object e) {
        debugPrint('Geotagging: location history: $e');
      });

  /// Asks the phone with [request] and keeps what it answers.
  Future<LocationAccess> _ask(Future<LocationAccess> Function() request) async {
    final access = await _guard('asking for location', request, _access);
    if (_disposed || access == _access) return access;
    _access = access;
    notifyListeners();
    return access;
  }

  /// Keeps what the phone answers [read] with.
  Future<void> _readUnrestricted(Future<bool> Function() read) async {
    final unrestricted = await _guard(
      'reading the background restriction',
      read,
      _unrestricted,
    );
    if (_disposed || unrestricted == _unrestricted) return;
    _unrestricted = unrestricted;
    notifyListeners();
  }

  /// [call]'s result, or [fallback] when the platform fails it (also a
  /// platform without the channel): geotagging then stays as it is, and
  /// the failure goes to the debug log.
  Future<T> _guard<T>(
    String what,
    Future<T> Function() call,
    T fallback,
  ) async {
    try {
      return await call();
    } on Object catch (e) {
      debugPrint('Geotagging: $what failed: $e');
      return fallback;
    }
  }

  /// Waits for a change of the paired cameras to be on disk. A failed
  /// write is reported by the store and made up for by its next one.
  Future<void> _saved(Future<void> write) async {
    try {
      await write;
    } on FileSystemException {
      return;
    }
  }

  SavedCamera? _camera(String? serial) => serial == null
      ? null
      : cameras.cameras.where((c) => c.serial == serial).firstOrNull;

  static GeotagNeed? _liveNeed(LocationAccess access) {
    // iOS reports no permission at all while location is off for the
    // phone, so that comes first.
    if (!access.serviceOn) return GeotagNeed.phoneLocation;
    if (access.permission == LocationPermission.denied) {
      return GeotagNeed.permission;
    }
    return access.precise ? null : GeotagNeed.precise;
  }

  static GeotagNeed? _alwaysNeed(LocationAccess access) =>
      _liveNeed(access) ??
      (access.permission == LocationPermission.always
          ? null
          : GeotagNeed.always);

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_onConnection);
    cameras.removeListener(_onCameras);
    settings.removeListener(_onSettings);
    _geotagging?.removeListener(_onGeotagging);
    unawaited(_fixes?.cancel());
    unawaited(_written?.cancel());
    unawaited(_stops?.cancel());
    for (final subscription in _phone) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
