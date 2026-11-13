import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_camera/src/library/camera_library.dart';
import 'package:gr_camera/src/shoot/setting_writes.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Focus at a point of the picture.
enum FocusState {
  /// The focus request is out; no `lens` change has answered yet.
  focusing,

  /// The camera reported the point in focus.
  focused,

  /// The camera could not focus there, or no result came in time.
  missed,
}

/// Where a focus was asked for and how it went, for drawing on the picture.
@immutable
final class FocusMark {
  /// A mark at [at] in [state].
  const new(this.at, this.state);

  /// 0..1 of the frame as the camera sends it (before any turn for
  /// [CameraLiveView.orientation]), origin top-left.
  final Offset at;

  /// How the focus at [at] went.
  final FocusState state;
}

/// Live view over the camera's Wi-Fi for one session (mock `b-shoot`,
/// remote-shooting.md): the MJPEG picture from `GET /v1/liveview`, tap to
/// focus (`POST /v1/lens/focus pos=X,Y`), the exposure settings from
/// `/v1/props` and their lists, changed with `PUT /v1/params/camera`, and
/// the pictures taken meanwhile, from the change WebSocket.
///
/// It runs between [start] and [stop]: the app starts it while live view
/// is wanted and the camera's Wi-Fi is up, and stops it otherwise.
final class CameraLiveView extends ChangeNotifier {
  new _(this._session, this._camera, this.settingsPoll);

  final GrSession _session;
  final GrCameraEnvironment _camera;

  /// The newest frame; changes many times a second, so it is separate from
  /// this notifier.
  ValueListenable<LiveViewFrame?> get frame => _frame;
  final _frame = ValueNotifier<LiveViewFrame?>(null);

  bool _started = false;
  bool _closed = false;
  GrChangesSocket? _socket;
  StreamSubscription<GrChangeEvent>? _changes;
  LiveViewStream? _stream;
  bool _opening = false;
  int _run = 0;
  Timer? _retry;

  /// The focus the camera is running: its point, and the `captureId` of
  /// its answer once that came. One at a time; see [focusAt].
  (Offset, String?)? _focusing;

  /// The newest tap made while [_focusing]; sent when that ends.
  Offset? _nextFocus;

  /// Ends [_focusing] if no `lens` change comes.
  Timer? _focusWait;

  /// `lens` changes that came while [_focusing] waited for its answer:
  /// they travel on the WebSocket, the answer on another connection, so
  /// either may come first. Matched by `captureId` once the answer is in.
  final _earlyLens = <(String?, bool)>[];

  /// Bumped by [stop], so a focus answer from before it is dropped.
  int _focusRun = 0;

  final _settings = SettingWrites();
  FocusMark? _focus;

  /// See [shots]; replaced when it changes, never changed in place.
  List<CameraFile> _shots = const [];
  String? _streamError;

  /// Whether [start] was called and [stop] not since.
  bool get started => _started;

  /// Frames are coming in.
  bool get streaming => _frame.value != null && _stream != null;

  /// Why the last stream ended; cleared by the next frame.
  String? get streamError => _streamError;

  /// `/v1/props` with the exposure settings and their lists, and changes
  /// not answered yet.
  GrProps? get props => _settings.props;

  /// The focus running or waiting ([FocusState.focusing], at the newest
  /// tap), else the result of the last one; null when the last one ended
  /// without a result, and after [stop].
  FocusMark? get focus => _focus;

  /// The files the camera reported as added while live view ran (pictures
  /// taken from the app or on the camera), oldest first, without those it
  /// reported deleted since. A RAW+JPEG picture is two of them. Each is
  /// named as the library lists it, so its image and info come from there.
  /// They stay through [stop] and the next [start]; [forgetShots] empties
  /// them. Another list each time it changes.
  List<CameraFile> get shots => _shots;

  /// Empties [shots].
  void forgetShots() {
    if (_shots.isEmpty) return;
    _log('shots.forgotten', {'files': _shots.length});
    _shots = const [];
    if (!_closed) notifyListeners();
  }

  /// How the camera is held, from `/v1/props` and the `cameraDirect`
  /// change (remote-shooting.md §1.5); null until the settings are read,
  /// and when the camera does not say. [frame]s come as the sensor sees
  /// them; turned by [GrCameraOrientation.quarterTurns] they show upright.
  GrCameraOrientation? get orientation => _orientation;
  GrCameraOrientation? _orientation;

  /// Counts `cameraDirect` orientations, so that a settings read started
  /// before one does not put the older orientation back.
  int _orientationChanges = 0;

  /// Whether [setSetting] can send a change now: live view runs and has
  /// read the settings.
  bool get canChangeSettings => _http != null && _settings.props != null;

  /// The camera's HTTP client while live view runs.
  GrHttpClient? get _http => _started && !_closed ? _session.http : null;

  /// Live view is wanted and the camera's Wi-Fi is up: opens the stream
  /// (and opens it again 2 s after it ends), reads the settings, polls them
  /// every [settingsPoll] and follows the change WebSocket. Call again
  /// after the Wi-Fi comes back; calls while running change nothing.
  void start() {
    if (_closed) return;
    if (!_started) _camera.event('shoot.liveview.start');
    _started = true;
    if (_stream == null && !_opening && _retry == null) unawaited(_open());
    // Each Wi-Fi join opens a new socket.
    if (_changes == null || !identical(_socket, _session.changes)) {
      _watchChanges();
    }
  }

  /// Stops the stream, the polls and every focus, and forgets the
  /// settings: they are read again on the next [start] (the mode dial or
  /// another session may change them meanwhile).
  void stop() {
    if (!_started) return;
    _camera.event('shoot.liveview.stop');
    _started = false;
    _stop();
    if (!_closed) notifyListeners();
  }

  /// Focuses on [at] (0..1 of the frame as sent, see [FocusMark.at]: Image
  /// Sync sends the point in the frame's own layout, remote-shooting.md
  /// §3.2), one focus at a time. The GR IV holds a focus sent while one
  /// runs until that one ends, and live view
  /// stalls through all of them (GR IV HDF, 2026-11-08: a 0.9-2 s gap per
  /// focus, 8.8 s after a quick series of taps). A tap meanwhile moves the
  /// mark and is sent when the running focus ends; only the newest one.
  Future<void> focusAt(Offset at) async {
    final http = _http;
    if (http == null) return;
    _focus = FocusMark(at, FocusState.focusing);
    notifyListeners();
    if (_focusing != null) {
      _log('focus.queued', {'x': at.dx, 'y': at.dy});
      _nextFocus = at;
      return;
    }
    _focusing = (at, null);
    final run = _focusRun;
    final watch = Stopwatch()..start();
    final pos = GrFocusPoint.normalized(
      at.dx.clamp(0.0, 1.0),
      at.dy.clamp(0.0, 1.0),
    );
    try {
      final r = await http.focus(pos: pos);
      _log('focus', {
        'pos': pos.wire,
        'ms': watch.elapsedMilliseconds,
        'captureId': r.captureId,
        'focused': r.focused,
        'running': r.focusRunning,
      });
      if (run != _focusRun || _closed) return;
      if (r.focused case final focused? when r.focusRunning != true) {
        _focusEnded(focused ? FocusState.focused : FocusState.missed);
        return;
      }
      // The GR IV answers with a `captureId` only (`ShootResponse`,
      // remote-shooting.md §3.1); the result is a `lens` change, which may
      // already be here.
      final id = r.captureId;
      _focusing = (at, id);
      for (final (lensId, focused) in _earlyLens.reversed) {
        if (_sameFocus(id, lensId)) {
          _log('focus.earlyLens', {'captureId': lensId, 'focused': focused});
          _focusEnded(focused ? FocusState.focused : FocusState.missed);
          return;
        }
      }
      _earlyLens.clear();
      _focusWait = Timer(_lensWait, () {
        _log('focus.noLens', {'captureId': id});
        _focusEnded(null);
      });
    } on Object catch (e) {
      _log('focus', {'ms': watch.elapsedMilliseconds, 'error': '$e'});
      if (run != _focusRun || _closed) return;
      _focusEnded(FocusState.missed);
    }
  }

  /// Without a `lens` change by then, the focus counts as ended with no
  /// result. Longer than the 2 s longest single-focus stall seen. \[design\]
  static const _lensWait = Duration(seconds: 3);

  /// Whether a `lens` change with [lensId] is the focus answered with
  /// [answerId]; either may lack one.
  static bool _sameFocus(String? answerId, String? lensId) =>
      answerId == null || lensId == null || answerId == lensId;

  /// The running focus ended with [result] (null: unknown). Sends the
  /// tap that waited, if any.
  void _focusEnded(FocusState? result) {
    final at = _focusing?.$1;
    _focusWait?.cancel();
    _focusWait = null;
    _focusing = null;
    _earlyLens.clear();
    final next = _nextFocus;
    _nextFocus = null;
    if (_closed) return;
    if (next != null) {
      unawaited(focusAt(next));
    } else if (result == null || at == null) {
      _focus = null;
      notifyListeners();
    } else {
      _focus = FocusMark(at, result);
      notifyListeners();
    }
  }

  /// Sets an exposure setting to one of the values its list offers. [props]
  /// show [value] at once and go back if the camera refuses it; this throws
  /// then. Does nothing unless [canChangeSettings].
  Future<void> setSetting(String key, String value) async {
    final http = _http;
    if (http == null || _settings.props == null) return;
    final change = _settings.begin(key, value);
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      // The answer is props-shaped (remote-shooting.md §4.2).
      var answer = await http.setCameraParams({key: value});
      _log('setting', {
        'key': key,
        'value': value,
        'ms': watch.elapsedMilliseconds,
        'current': answer.raw[key],
        'listLength': switch (answer.raw['${key}List']) {
          final List<Object?> l => l.length,
          _ => null,
        },
      });
      if (answer.setting(key) == null) {
        answer = await http.props();
        _session.recordProps(answer);
      }
      if (_closed) return;
      _settings.succeeded(change, key, answer);
      notifyListeners();
    } on Object catch (e) {
      _log('setting', {
        'key': key,
        'value': value,
        'ms': watch.elapsedMilliseconds,
        'error': '$e',
      });
      if (_closed) rethrow;
      _settings.failed(change, key);
      notifyListeners();
      // A refusal can mean the lists are out of date (the mode dial moved).
      unawaited(_refreshProps(http, 'refused'));
      rethrow;
    }
  }

  void _log(String kind, Map<String, Object?> fields) =>
      _camera.event('shoot.$kind', fields);

  Future<void> _open() async {
    final http = _http;
    if (http == null) return;
    final run = ++_run;
    _opening = true;
    try {
      // Settings first: the readouts and chips need them, and a camera
      // that answers props is up for the stream too.
      if (_settings.props == null) {
        final since = _settings.startRead();
        final changes = _orientationChanges;
        final props = await http.props();
        _session.recordProps(props);
        if (changes == _orientationChanges) {
          _setOrientation(props.cameraOrientation, 'props');
        }
        // Image Sync honours a tap only in AF and inside
        // `focusEffectiveArea` (remote-shooting.md §3.1-3.2).
        _log('props.focus', {
          for (final MapEntry(:key, :value) in props.raw.entries)
            if (key.toLowerCase().contains('focus')) key: value,
        });
        _settings.read(props, since: since);
      }
      if (!_current(run)) return;
      notifyListeners();
      final stream = await http.openLiveView();
      if (!_current(run)) {
        unawaited(stream.close());
        return;
      }
      _stream = stream;
      unawaited(_pollSettings(run));
      var last = DateTime.now();
      stream.frames.listen(
        (f) {
          if (!_current(run)) return;
          final now = DateTime.now();
          final gap = now.difference(last).inMilliseconds;
          last = now;
          // Pauses show up on hardware only (focus, settings).
          if (gap > 300) _log('liveview.gap', {'ms': gap});
          _streamError = null;
          final first = _frame.value == null;
          _frame.value = f;
          if (first) notifyListeners();
        },
        onError: (Object e) {
          if (_current(run)) _streamError = '$e';
        },
        onDone: () => _ended(run),
      );
    } on Object catch (e) {
      if (!_current(run)) return;
      _streamError = '$e';
      _ended(run);
    } finally {
      if (run == _run) _opening = false;
    }
  }

  bool _current(int run) => !_closed && _started && run == _run;

  /// How often the settings are read while the stream runs \[design\]. A
  /// GR IV HDF pushed no `camera` change for mode dial moves (2026-11-08),
  /// so the values the camera picks itself (shutter speed in Av, auto
  /// ISO) and lists it reported mid-switch are only seen by reading again.
  final Duration settingsPoll;

  Future<void> _pollSettings(int run) async {
    while (true) {
      await Future<void>.delayed(settingsPoll);
      final http = _http;
      if (!_current(run) || http == null) return;
      await _refreshProps(http, 'poll');
    }
  }

  /// The stream ended (the camera stopped it, or Wi-Fi went): open it
  /// again after a pause while live view still runs. \[design\]
  void _ended(int run) {
    if (!_current(run)) return;
    _log('liveview.ended', {'error': _streamError});
    _stream = null;
    _frame.value = null;
    notifyListeners();
    _retry ??= Timer(const Duration(seconds: 2), () {
      _retry = null;
      if (!_closed && _started) start();
    });
  }

  void _stop() {
    _run++;
    _retry?.cancel();
    _retry = null;
    _opening = false;
    final stream = _stream;
    _stream = null;
    if (stream != null) unawaited(stream.close());
    _frame.value = null;
    // Read again on the next start: the settings may change meanwhile
    // (mode dial, or another session).
    _settings.clear();
    _focus = null;
    _orientation = null;
    _focusRun++;
    _focusWait?.cancel();
    _focusWait = null;
    _focusing = null;
    _earlyLens.clear();
    _nextFocus = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _socket = null;
  }

  void _watchChanges() {
    unawaited(_changes?.cancel());
    _changes = null;
    final socket = _session.changes;
    _socket = socket;
    if (socket == null || !_started) return;
    _changes = socket.events.listen(_onChange);
  }

  void _onChange(GrChangeEvent e) {
    final http = _http;
    if (http == null) return;
    switch (e) {
      case GrCameraChange():
        _log('change', {'changed': 'camera'});
        unawaited(_refreshProps(http, 'cameraChange'));
      case GrCameraDirectChange(:final cameraOrientation?):
        _orientationChanges++;
        if (_setOrientation(cameraOrientation, 'cameraDirect')) {
          notifyListeners();
        }
      case GrLensChange(:final focused?, :final captureId):
        _log('lens', {'captureId': captureId, 'focused': focused});
        // `"0"` is not a client's focus (Image Sync ignores it,
        // remote-shooting.md §2.3).
        final running = _focusing;
        if (running == null || captureId == '0') return;
        if (_focusWait == null) {
          _earlyLens.add((captureId, focused));
          return;
        }
        if (!_sameFocus(running.$2, captureId)) return;
        _focusEnded(focused ? FocusState.focused : FocusState.missed);
      case GrStorageChange(:final path?, action: 'delete'):
        _shotDeleted(_listed(path, e.storage));
      case GrStorageChange(:final path?):
        _shotAdded(_listed(path, e.storage));
      default:
    }
  }

  /// Exposure settings whose lists the mode dial decides: they cannot be
  /// changed from when the dial moves until the camera has reported them
  /// for the new mode.
  static const modeSettings = {'av', 'tv', 'sv', 'xv'};

  /// Whether [modeSettings] are as the camera reported them for the
  /// current mode dial position.
  bool get modeSettled => _settings.modeSettled;

  bool _settling = false;

  /// The last settings read, as logged.
  String? _lastProps;

  /// The mode dial moved (BLE Shooting Mode): locks [modeSettings] at once
  /// and reads the settings until a read started after the move is in.
  /// Does nothing until live view has read them once.
  void _modeChanged() {
    if (!_started || _closed || _settings.props == null) return;
    _log('modeDial.lock', {'keys': modeSettings.toList()});
    _settings.modeChanged();
    notifyListeners();
    unawaited(_settleMode());
  }

  Future<void> _settleMode() async {
    if (_settling) return;
    _settling = true;
    try {
      // A read can be dropped (a change was answered meanwhile) or fail;
      // either way the lock stays until one for this mode is used.
      while (!_closed && _started && !_settings.modeSettled) {
        final http = _http;
        if (http == null) return;
        if (!await _refreshProps(http, 'modeDial')) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (_started && _settings.modeSettled) _log('modeDial.settled', {});
    } finally {
      _settling = false;
    }
  }

  /// Reads the settings; false when the camera did not answer.
  Future<bool> _refreshProps(GrHttpClient http, String reason) async {
    final since = _settings.startRead();
    final changes = _orientationChanges;
    try {
      final props = await http.props();
      if (_closed) return true;
      _session.recordProps(props);
      if (changes == _orientationChanges) {
        _setOrientation(props.cameraOrientation, reason);
      }
      final summary = {
        'exposureMode': props.exposureMode,
        for (final key in const ['av', 'tv', 'sv', 'xv']) ...{
          key: props.setting(key)?.current,
          '${key}List': props.setting(key)?.options?.length,
        },
      };
      // Polls are logged only when something changed.
      final text = jsonEncode(summary);
      if (reason != 'poll' || text != _lastProps) {
        _log('props', {'reason': reason, ...summary});
      }
      _lastProps = text;
      _settings.read(props, since: since);
      notifyListeners();
      return true;
    } on Object catch (e) {
      _log('props.failed', {'reason': reason, 'error': '$e'});
      // The next change or setting tries again.
      return false;
    }
  }

  /// Takes [value] as how the camera is held; true when that changed it.
  bool _setOrientation(GrCameraOrientation? value, String reason) {
    if (value == _orientation) return false;
    _log('orientation', {
      'from': _orientation?.wire,
      'to': value?.wire,
      'reason': reason,
    });
    _orientation = value;
    return true;
  }

  /// [path] on [storage], as a `storage` change names them, as the library
  /// lists it: a camera listed without `storage=` ([listedStorages]) has
  /// its files without one.
  CameraFile _listed(GrPhotoPath path, String? storage) => CameraFile(
    listedStorages(_session.props).contains(null) ? null : storage,
    path,
  );

  void _shotAdded(CameraFile file) {
    if (_shots.contains(file)) return;
    _shots = List.unmodifiable([..._shots, file]);
    _log('shot.added', {'file': '$file', 'shots': _shots.length});
    notifyListeners();
  }

  /// The camera deleted [file] (on the body, or by another app).
  void _shotDeleted(CameraFile file) {
    if (!_shots.contains(file)) return;
    _shots = List.unmodifiable([
      for (final shot in _shots)
        if (shot != file) shot,
    ]);
    _log('shot.deleted', {'file': '$file', 'shots': _shots.length});
    notifyListeners();
  }

  void _close() {
    _started = false;
    _stop();
    _closed = true;
  }
}

/// Creates the live view of [session]. Used by `CameraSession` only.
CameraLiveView createCameraLiveView(
  GrSession session,
  GrCameraEnvironment camera, {
  Duration settingsPoll = const Duration(seconds: 1),
}) => CameraLiveView._(session, camera, settingsPoll);

/// What `CameraSession` does to its live view. Not exported.
extension CameraLiveViewInternals on CameraLiveView {
  /// The mode dial moved (BLE Shooting Mode).
  void modeChanged() => _modeChanged();

  /// The session ended: stops everything and notifies no more.
  void close() => _close();
}
