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

/// Geotagging as the app runs it, with no widget involved: Android can
/// start the app with no screen when a camera is switched on, so everything
/// here is driven by listeners and streams.
///
/// **Live mode**, per camera (`SavedCamera.liveGeotagging`): the camera
/// layer sends the phone's location to a camera that is on
/// ([CameraGeotagging]). This controller gives each session its settings,
/// saves that the camera took the Store Location Info value it was owed,
/// and has the phone watch for cameras being switched on
/// ([PowerOnWatch]). A sighting links the camera: a session that let go of
/// it while it was off is told ([CameraSession.cameraSeenOn]), and with no
/// session, or one for another camera that is not on, the sighted camera
/// becomes the current one and is connected. A sighting while another
/// camera is on and linked is ignored: one camera at a time. \[design\]
///
/// **Background mode** (`SettingsController.backgroundGeotagging`): the
/// phone records where it is by itself ([PhoneLocation.setHistory]), this
/// controller moves those positions into the [history], and [geotagger]
/// gives downloaded photos the nearest one. While background mode is on,
/// the positions live mode takes are kept in the history too. A permission
/// reduced later leaves the setting on: [backgroundPausedBy] says what is
/// missing, and recording resumes by itself when it is back.
final class GeotagController extends ChangeNotifier {
  new _({
    required this.connection,
    required this.cameras,
    required this.settings,
    required this.history,
    required this._location,
    required this._watch,
  });

  /// Opens the location history under [AppServices.dataDir] and follows
  /// the connection, the paired cameras, the settings and the phone from
  /// now on. [start] then puts the phone in line with the settings.
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
    watch: services.camera.powerOnWatch,
  ).._listen();

  /// How long a recorded position is kept: a photo downloaded later than
  /// this after it was taken gets no location from the history. \[design\]
  static const historyKept = Duration(days: 90);

  /// The session whose geotagging this controller configures.
  final ConnectionController connection;

  /// The paired cameras, with each one's geotagging settings.
  final CameraStore cameras;

  /// Holds whether background mode is on, and the app's language.
  final SettingsController settings;

  /// Where the phone has been, for background mode.
  final LocationHistory history;

  final PhoneLocation _location;
  final PowerOnWatch _watch;

  /// Gives downloaded photos a location from the [history] while background
  /// mode is on; the download engine runs [DownloadGeotagger.tag] before it
  /// saves a shot. Positions the phone recorded meanwhile are taken over
  /// first.
  late final DownloadGeotagger geotagger = DownloadGeotagger(
    history: history,
    enabled: () => settings.backgroundGeotagging,
    beforeMatch: drainHistory,
    log: (line) => debugPrint(line),
  );

  final List<StreamSubscription<void>> _phone = [];
  LocationAccess _access = LocationAccess.none;
  bool _autoStartSupported = false;

  /// Device ids of the paired cameras the phone's own link exists for
  /// ([PowerOnWatch.associated]).
  final Set<String> _associated = {};

  CameraSession? _session;
  CameraGeotagging? _geotagging;

  /// Serial number of [_session]'s camera.
  String? _sessionSerial;
  StreamSubscription<LocationFix>? _fixes;
  StreamSubscription<bool>? _written;

  /// What [_geotagging] was configured with last, so that it is told again
  /// only when something changed.
  Object? _configured;

  /// The watched cameras as last handed to the phone.
  String? _watched;

  /// Whether there is a session, whether its camera is on and linked, and
  /// whether it let go of a camera that is off, as last seen.
  ({bool session, bool on, bool parked}) _power = (
    session: false,
    on: false,
    parked: false,
  );

  /// Every history job so far; the next one runs after them.
  Future<void> _historyJobs = Future.value();

  /// Set after a camera the phone saw on could not be reached: the phone
  /// is told to watch afresh when it fires, so it reports the camera again
  /// if it is still on.
  Timer? _watchAgain;

  /// Such attempts in a row; a camera that gets linked while on clears it.
  int _unreached = 0;
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

  /// The phone can notice a camera being switched on while GR Photo is not
  /// running, and start it.
  bool get autoStartSupported => _autoStartSupported;

  /// The phone has its own link between GR Photo and [camera]
  /// ([PowerOnWatch.associated]); always true where none is needed.
  bool linkedToPhone(SavedCamera camera) =>
      _associated.contains(camera.paired.deviceId);

  /// Location is allowed at all times, which starting with GR Photo closed
  /// takes.
  bool get locationAlways => _access.permission == LocationPermission.always;

  /// Live geotagging starts by itself when [camera] is switched on, with
  /// GR Photo closed too: location is allowed at all times and the phone
  /// links the app to the camera.
  bool autoStartReady(SavedCamera camera) =>
      _autoStartSupported && locationAlways && linkedToPhone(camera);

  /// What keeps background mode from recording while it is on; null while
  /// it records, and while it is off.
  GeotagNeed? get backgroundPausedBy =>
      settings.backgroundGeotagging ? _alwaysNeed(_access) : null;

  // -------------------------------------------------------------- actions

  /// Turns live geotagging on for [serial]'s camera, asking for the phone's
  /// location first where the phone still asks. Returns null when it is
  /// on: the camera's Store Location Info is turned on as soon as the
  /// camera is on and linked. Otherwise it stays off, and the result says
  /// what the phone lacks.
  Future<GeotagNeed?> turnLiveOn(String serial) async {
    final need = _liveNeed(await _ask(_location.requestWhileInUse));
    if (need != null) return need;
    await _saved(cameras.setLiveGeotagging(serial, on: true));
    return null;
  }

  /// Turns live geotagging off for [serial]'s camera. Its Store Location
  /// Info is turned off as soon as the camera is on and linked, which
  /// clears the location it holds.
  Future<void> turnLiveOff(String serial) =>
      _saved(cameras.setLiveGeotagging(serial, on: false));

  /// Turns keeping [serial]'s clock on the phone's time on or off. Live
  /// geotagging keeps it there whatever this says.
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

  /// Starts live geotagging again after the user stopped it from the
  /// phone's notice ([GeotagStatus.stopped]).
  void resume() => _geotagging?.resume();

  /// Sets up live geotagging starting whenever [serial]'s camera is
  /// switched on: asks for location at all times, then for the phone's own
  /// link to the camera where one is needed. Returns null when both are in
  /// place.
  Future<GeotagNeed?> setUpAutoStart(String serial) async {
    final camera = _camera(serial);
    if (camera == null) return GeotagNeed.cameraLink;
    final need = _liveNeed(await _ask(_location.access));
    if (need != null) return need;
    if (!locationAlways) await _ask(_location.requestAlways);
    if (!locationAlways) return GeotagNeed.always;
    final id = camera.paired.deviceId;
    final linked = await _guard(
      'linking the camera to the phone',
      () async =>
          await _watch.associated(id) ||
          await _watch.associate(
            WatchedCamera(deviceId: id, name: camera.name),
          ),
      false,
    );
    if (_disposed) return null;
    if (!linked) {
      _associated.remove(id);
      notifyListeners();
      return GeotagNeed.cameraLink;
    }
    _associated.add(id);
    notifyListeners();
    // The phone may start the app for this camera from now on.
    _armWatch();
    return null;
  }

  /// Turns background mode on: asks for the phone's location while GR
  /// Photo is in use, which the phone wants granted first, then for
  /// location at all times. Only that turns it on; otherwise it stays off
  /// and the result says what the phone lacks.
  Future<GeotagNeed?> turnBackgroundOn() async {
    final need = _liveNeed(await _ask(_location.requestWhileInUse));
    if (need != null) return need;
    if (!locationAlways) await _ask(_location.requestAlways);
    if (!locationAlways) return GeotagNeed.always;
    settings.backgroundGeotagging = true;
    await _setHistory();
    return null;
  }

  /// Turns background mode off: the phone stops recording where it is.
  /// What it recorded stays in the [history] until it is 90 days old or
  /// deleted ([deleteHistory]).
  Future<void> turnBackgroundOff() async {
    settings.backgroundGeotagging = false;
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
    final page = need.settingsPage;
    if (page == null) return;
    await _guard<void>(
      'opening the settings',
      () => _location.openSettings(page),
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
      ..add(_location.historyPending.listen((_) => unawaited(drainHistory())))
      ..add(_watch.sightings.listen(_onSighting));
  }

  /// Reads where the phone stands, puts its recording and its watch in
  /// line with the settings, and acts on the sightings that started the
  /// app (a camera was switched on while GR Photo was not running). Called
  /// once, when the app's other models exist.
  Future<void> start() async {
    _access = await _guard('reading the access', _location.access, _access);
    _autoStartSupported = await _guard(
      'asking for the power-on watch',
      _watch.supported,
      false,
    );
    await _readLinks();
    // The settings file decides, also after a restore that kept only one
    // of the two.
    await _setHistory();
    unawaited(drainHistory());
    _onConnection();
    _armWatch();
    final launched = await _guard(
      'taking the launch sightings',
      _watch.takeLaunchSightings,
      const <String>[],
    );
    launched.forEach(_onSighting);
  }

  void _onConnection() {
    if (_disposed) return;
    final session = connection.cameraSession;
    if (!identical(session, _session)) _attach(session);
    final power = (
      session: session != null,
      on: _cameraOn,
      parked: connection.parked,
    );
    final wentOff = _power.on && !power.on;
    final nowParked = power.parked && !_power.parked;
    _power = power;
    if (power.on) _unreached = 0;
    // The phone reports a camera once per watch, so it is told to watch
    // afresh each time a camera that was on and linked no longer is, and
    // when the session lets go of one that is off.
    if (wentOff || nowParked) _armWatch(again: true);
    notifyListeners();
  }

  void _onCameras() {
    if (_disposed) return;
    _configure();
    _armWatch();
    unawaited(_readLinks());
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
    // The user may have been in the phone's settings.
    unawaited(_readLinks());
    if (!regained || !settings.backgroundGeotagging) return;
    unawaited(_setHistory());
    unawaited(drainHistory());
  }

  /// The phone saw the camera at [deviceId] advertising that it is on.
  void _onSighting(String deviceId) {
    if (_disposed) return;
    final camera = cameras.cameras
        .where((c) => c.paired.deviceId == deviceId)
        .firstOrNull;
    if (camera == null || !camera.liveGeotagging) return;
    final session = connection.cameraSession;
    if (session != null && connection.camera?.serial == camera.serial) {
      // Links at once when the session had let go of the camera.
      session.cameraSeenOn();
      return;
    }
    if (session != null && _cameraOn) {
      debugPrint(
        'Geotagging: ${camera.serial} was switched on while another '
        'camera is on and linked; left alone',
      );
      return;
    }
    debugPrint('Geotagging: ${camera.serial} was switched on; connecting');
    unawaited(_connectSeen(camera.serial));
  }

  /// Makes [serial]'s camera, which the phone saw on, the current one and
  /// links it. When it cannot be reached, the phone is asked to watch
  /// afresh a little later, three times at most: a camera that is on a
  /// moment too short, or just out of reach, is tried again without a
  /// camera that never answers being dialled for good. A failure only the
  /// user can clear (pairing, Bluetooth off) is left to them.
  Future<void> _connectSeen(String serial) async {
    await connection.connectTo(serial);
    if (_disposed || connection.status != ConnectionStatus.failed) return;
    if (connection.failure?.kind != ConnectFailureKind.unreachable) return;
    if (_unreached >= _reachAttempts) return;
    _unreached++;
    _watchAgain?.cancel();
    _watchAgain = Timer(_watchAgainAfter, () => _armWatch(again: true));
  }

  /// The least time between two of live mode's positions kept in the
  /// history.
  static const _liveHistoryEvery = Duration(seconds: 15);

  /// When the last of live mode's positions kept in the history was taken.
  DateTime? _liveHistoryAt;

  static const _reachAttempts = 3;
  static const _watchAgainAfter = Duration(seconds: 30);

  /// The session's camera is on and within reach: linked over Bluetooth,
  /// or carrying on over its Wi-Fi without it.
  bool get _cameraOn =>
      !connection.cameraOff && (connection.bleLinked || connection.inSession);

  void _attach(CameraSession? session) {
    _geotagging?.removeListener(_onGeotagging);
    unawaited(_fixes?.cancel());
    unawaited(_written?.cancel());
    _fixes = null;
    _written = null;
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
      syncClock: camera.syncClock,
      pending: camera.storeLocationInfoPending,
      name: camera.name,
      language: _l10n.localeName,
    );
    if (configured == _configured) return;
    _configured = configured;
    geotagging.configure(
      GeotagSettings(
        live: camera.liveGeotagging,
        syncClock: camera.syncClock,
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

  void _onStoreLocationInfoWritten(bool written) {
    final serial = _sessionSerial;
    if (serial == null) return;
    unawaited(
      _saved(cameras.storeLocationInfoWritten(serial, written: written)),
    );
  }

  /// A position live mode took for the camera: kept for the photos the
  /// camera does not tag, while background mode is on. The phone takes
  /// about one a second while the camera is on, so only one every
  /// [_liveHistoryEvery] is kept: a photo is matched by its capture time,
  /// which that resolves well, and the history stays small.
  void _onFix(LocationFix fix) {
    if (!settings.backgroundGeotagging) return;
    final last = _liveHistoryAt;
    if (last != null && fix.time.difference(last).abs() < _liveHistoryEvery) {
      return;
    }
    _liveHistoryAt = fix.time;
    unawaited(_historyJob(() => history.add([fix])));
  }

  /// Has the phone watch for every camera with live geotagging on, when
  /// those changed or [again] asks for a fresh watch.
  void _armWatch({bool again = false}) {
    if (!_autoStartSupported) return;
    final watched = [
      for (final camera in cameras.cameras)
        if (camera.liveGeotagging && camera.supportsGeotagging)
          WatchedCamera(deviceId: camera.paired.deviceId, name: camera.name),
    ];
    final key = [for (final w in watched) '${w.deviceId}\n${w.name}']
        .join('\n');
    if (!again && key == _watched) return;
    // Nothing to stop when no camera was watched before either.
    if (watched.isEmpty && key == _watched) return;
    _watched = key;
    unawaited(
      _guard<void>('watching for cameras', () => _watch.watch(watched), null),
    );
  }

  /// Reads which paired cameras the phone links GR Photo to.
  Future<void> _readLinks() async {
    if (!_autoStartSupported) return;
    final linked = <String>{};
    for (final camera in cameras.cameras) {
      final id = camera.paired.deviceId;
      final has = await _guard(
        'reading the camera link',
        () => _watch.associated(id),
        false,
      );
      if (has) linked.add(id);
    }
    if (_disposed || setEquals(linked, _associated)) return;
    _associated
      ..clear()
      ..addAll(linked);
    notifyListeners();
  }

  /// Puts the phone's own recording in line with the setting. Without
  /// location at all times it records nothing; it is asked again when that
  /// comes back ([_onAccess]).
  Future<void> _setHistory() => _guard<void>(
    'switching the location history',
    () => _location.setHistory(enabled: settings.backgroundGeotagging),
    null,
  );

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
    _watchAgain?.cancel();
    connection.removeListener(_onConnection);
    cameras.removeListener(_onCameras);
    settings.removeListener(_onSettings);
    _geotagging?.removeListener(_onGeotagging);
    unawaited(_fixes?.cancel());
    unawaited(_written?.cancel());
    for (final subscription in _phone) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
