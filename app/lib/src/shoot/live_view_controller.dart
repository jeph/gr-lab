import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../connection/connection_controller.dart';
import 'setting_writes.dart';

/// Where live view is.
enum LiveViewPhase {
  /// Not wanted.
  off,

  /// Waiting for the camera's Wi-Fi (joining, or the join failed:
  /// [ConnectionController.failure]).
  joining,

  /// Wi-Fi is up; opening the stream, or opening it again after it ended.
  starting,

  /// Frames are coming in.
  streaming,
}

/// Focus at a point of the picture.
enum FocusState { focusing, focused, missed }

@immutable
final class FocusMark {
  const FocusMark(this.at, this.state);

  /// 0..1 of the picture, origin top-left.
  final Offset at;
  final FocusState state;
}

/// Live view over the camera's Wi-Fi (mock `b-shoot`, remote-shooting.md):
/// the MJPEG picture from `GET /v1/liveview`, tap to focus
/// (`POST /v1/lens/focus pos=X,Y`), the exposure settings from
/// `/v1/props` and their lists, changed with `PUT /v1/params/camera`, and
/// the newest picture from the change WebSocket.
///
/// Wanting it joins the camera's Wi-Fi; not wanting it stops the stream and
/// leaves the Wi-Fi up for the Library ([ConnectionController.closeCamera]
/// leaves it). [design]
final class LiveViewController extends ChangeNotifier {
  LiveViewController({
    required this.connection,
    this.settingsPoll = const Duration(seconds: 1),
  }) {
    connection.addListener(_sync);
    _onConnected = connection.onConnected.listen((_) => _watchChanges());
  }

  final ConnectionController connection;

  /// The newest frame; changes many times a second, so it is separate from
  /// this notifier.
  final frame = ValueNotifier<LiveViewFrame?>(null);

  late final StreamSubscription<GrHttpClient> _onConnected;
  StreamSubscription<GrChangeEvent>? _changes;
  LiveViewStream? _stream;
  bool _opening = false;
  bool _wanted = false;
  bool _askedToJoin = false;
  bool _disposed = false;
  int _run = 0;
  Timer? _retry;
  Timer? _focusClear;

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

  /// Bumped by [_stop], so a focus answer from before it is dropped.
  int _focusRun = 0;

  final _settings = SettingWrites();
  FocusMark? _focus;
  Uint8List? _lastShot;
  String? _streamError;

  LiveViewPhase get phase {
    if (!_wanted) return LiveViewPhase.off;
    if (connection.status != ConnectionStatus.connected) {
      return LiveViewPhase.joining;
    }
    return frame.value == null || _stream == null
        ? LiveViewPhase.starting
        : LiveViewPhase.streaming;
  }

  /// Why the last stream ended; cleared by the next frame.
  String? get streamError => _streamError;

  /// `/v1/props` with the exposure settings and their lists, and changes
  /// not answered yet.
  GrProps? get props => _settings.props;
  FocusMark? get focus => _focus;

  /// Thumbnail of the newest picture taken while live view is on.
  Uint8List? get lastShot => _lastShot;

  set wanted(bool value) {
    if (_wanted == value) return;
    _wanted = value;
    _askedToJoin = false;
    if (!value) _stop();
    _sync();
  }

  /// Joins again after a failed join.
  void retryJoin() {
    if (!_wanted) return;
    unawaited(connection.joinWifi());
  }

  /// Focuses on [at] (0..1 of the picture), one focus at a time. The GR IV
  /// holds a focus sent while one runs until that one ends, and live view
  /// stalls through all of them (GR IV HDF, 2026-11-08: a 0.9-2 s gap per
  /// focus, 8.8 s after a quick series of taps). A tap meanwhile moves the
  /// mark and is sent when the running focus ends; only the newest one.
  Future<void> focusAt(Offset at) async {
    final http = connection.http;
    if (http == null) return;
    _focusClear?.cancel();
    _focus = FocusMark(at, FocusState.focusing);
    notifyListeners();
    if (_focusing != null) {
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
      if (run != _focusRun || _disposed) return;
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
      if (run != _focusRun || _disposed) return;
      _focusEnded(FocusState.missed);
    }
  }

  /// Without a `lens` change by then, the focus counts as ended with no
  /// result. Longer than the 2 s longest single-focus stall seen. [design]
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
    if (next != null) {
      unawaited(focusAt(next));
    } else if (result == null || at == null) {
      _focus = null;
      notifyListeners();
    } else {
      _showFocus(at, result);
    }
  }

  void _showFocus(Offset at, FocusState state) {
    if (_disposed) return;
    _focus = FocusMark(at, state);
    notifyListeners();
    _focusClear?.cancel();
    _focusClear = Timer(const Duration(seconds: 2), () {
      _focus = null;
      notifyListeners();
    });
  }

  /// Sets an exposure setting to one of the values its list offers. The
  /// readouts show [value] at once and go back if the camera refuses it.
  Future<String?> setSetting(String key, String value) async {
    final http = connection.http;
    if (http == null || _settings.props == null) {
      return 'Not on the camera\'s Wi-Fi';
    }
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
      if (answer.setting(key) == null) answer = await http.props();
      if (_disposed) return null;
      _settings.succeeded(change, key, answer);
      notifyListeners();
      return null;
    } on Object catch (e) {
      _log('setting', {
        'key': key,
        'value': value,
        'ms': watch.elapsedMilliseconds,
        'error': '$e',
      });
      if (_disposed) return null;
      _settings.failed(change, key);
      notifyListeners();
      // A refusal can mean the lists are out of date (the mode dial moved).
      unawaited(_refreshProps(http, 'refused'));
      return "The camera didn't change it ($e)";
    }
  }

  void _log(String kind, Map<String, Object?> fields) =>
      debugPrint('gr.shoot ${jsonEncode({'kind': kind, ...fields})}');

  void _sync() {
    if (_disposed) return;
    if (!_wanted) {
      notifyListeners();
      return;
    }
    switch (connection.status) {
      case ConnectionStatus.bluetooth when !_askedToJoin:
        // A failed join is not repeated by itself; [retryJoin] does.
        _askedToJoin = true;
        if (connection.failure == null) unawaited(connection.joinWifi());
      case ConnectionStatus.connected:
        if (_stream == null && !_opening && _retry == null) {
          unawaited(_open());
        }
        if (_changes == null) _watchChanges();
      default:
        _stop();
    }
    notifyListeners();
  }

  Future<void> _open() async {
    final http = connection.http;
    if (http == null) return;
    final run = ++_run;
    _opening = true;
    try {
      // Settings first: the readouts and chips need them, and a camera
      // that answers props is up for the stream too.
      if (_settings.props == null) {
        final since = _settings.startRead();
        final props = await http.props();
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
          final first = frame.value == null;
          frame.value = f;
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

  bool _current(int run) => !_disposed && _wanted && run == _run;

  /// How often the settings are read while the stream runs [design]. A
  /// GR IV HDF pushed no `camera` change for mode dial moves (2026-11-08),
  /// so the values the camera picks itself (shutter speed in Av, auto
  /// ISO) and lists it reported mid-switch are only seen by reading again.
  final Duration settingsPoll;

  Future<void> _pollSettings(int run) async {
    while (true) {
      await Future<void>.delayed(settingsPoll);
      final http = connection.http;
      if (!_current(run) || http == null) return;
      await _refreshProps(http, 'poll');
    }
  }

  /// The stream ended (the camera stopped it, or Wi-Fi went): open it
  /// again after a pause while live view is still wanted. [design]
  void _ended(int run) {
    if (!_current(run)) return;
    _stream = null;
    frame.value = null;
    notifyListeners();
    _retry ??= Timer(const Duration(seconds: 2), () {
      _retry = null;
      _sync();
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
    frame.value = null;
    // Read again on the next start: the settings may change meanwhile
    // (mode dial, or another session).
    _settings.clear();
    _focusClear?.cancel();
    _focus = null;
    _focusRun++;
    _focusWait?.cancel();
    _focusWait = null;
    _focusing = null;
    _earlyLens.clear();
    _nextFocus = null;
    unawaited(_changes?.cancel());
    _changes = null;
  }

  void _watchChanges() {
    unawaited(_changes?.cancel());
    _changes = null;
    final socket = connection.session?.changes;
    if (socket == null || !_wanted) return;
    _changes = socket.events.listen(_onChange);
  }

  void _onChange(GrChangeEvent e) {
    final http = connection.http;
    if (http == null || !_wanted) return;
    switch (e) {
      case GrCameraChange():
        _log('change', {'changed': 'camera'});
        unawaited(_refreshProps(http, 'cameraChange'));
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
      case GrStorageChange(:final path?) when e.action != 'delete':
        unawaited(_loadThumb(http, path, e.storage));
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
  void modeChanged() {
    if (!_wanted || _settings.props == null) return;
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
      while (!_disposed && _wanted && !_settings.modeSettled) {
        final http = connection.http;
        if (http == null) return;
        if (!await _refreshProps(http, 'modeDial')) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    } finally {
      _settling = false;
    }
  }

  /// Reads the settings; false when the camera did not answer.
  Future<bool> _refreshProps(GrHttpClient http, String reason) async {
    final since = _settings.startRead();
    try {
      final props = await http.props();
      if (_disposed) return true;
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
    } on Object {
      // The next change or setting tries again.
      return false;
    }
  }

  Future<void> _loadThumb(
    GrHttpClient http,
    GrPhotoPath path,
    String? storage,
  ) async {
    final sink = StreamController<List<int>>();
    final bytes = sink.stream.fold(BytesBuilder(copy: false), (b, chunk) {
      b.add(chunk);
      return b;
    });
    try {
      await http.download(
        path,
        sink.sink,
        size: GrImageSize.thumb,
        storage: storage,
      );
      await sink.close();
      final data = (await bytes).takeBytes();
      if (_disposed || data.isEmpty) return;
      _lastShot = data;
      notifyListeners();
    } on Object {
      await sink.close();
      // Only the thumbnail is missing; the picture is on the camera.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_sync);
    _stop();
    unawaited(_onConnected.cancel());
    unawaited(_changes?.cancel());
    frame.dispose();
    super.dispose();
  }
}
