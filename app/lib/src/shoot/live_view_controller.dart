import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/connection/connection_controller.dart';

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

/// Why [LiveViewController.setSetting] did not change a setting.
sealed class SettingRefusal {
  const new();
}

/// The phone is not on the camera's Wi-Fi, so settings cannot change.
final class SettingRefusalNotOnWifi extends SettingRefusal {
  const new();
}

/// The camera did not take the new value.
final class SettingRefusalByCamera extends SettingRefusal {
  const new(this.detail);

  /// The error, as technical detail; not translated.
  final String detail;
}

/// Live view on the Shoot tab (mock `b-shoot`): wanting it joins the
/// camera's Wi-Fi, and the session's [CameraLiveView] runs while the Wi-Fi
/// is up. A focus result shows for 2 s.
///
/// Not wanting it stops live view and leaves the Wi-Fi up for the Library
/// ([ConnectionController.closeCamera] leaves it). \[design\]
final class LiveViewController extends ChangeNotifier {
  new({required this.connection}) {
    connection.addListener(_sync);
    _wifiUp = connection.wifiUp.listen((_) => _sync());
  }

  final ConnectionController connection;

  /// The newest frame; changes many times a second, so it is separate from
  /// this notifier.
  final frame = ValueNotifier<LiveViewFrame?>(null);

  late final StreamSubscription<void> _wifiUp;
  CameraLiveView? _live;
  bool _wanted = false;
  bool _askedToJoin = false;
  bool _disposed = false;

  /// The focus result [_focusClear] hides, and one it has hidden.
  FocusMark? _timedFocus;
  FocusMark? _hiddenFocus;
  Timer? _focusClear;

  LiveViewPhase get phase {
    if (!_wanted) return LiveViewPhase.off;
    if (connection.status != ConnectionStatus.connected) {
      return LiveViewPhase.joining;
    }
    return _live?.streaming ?? false
        ? LiveViewPhase.streaming
        : LiveViewPhase.starting;
  }

  /// Why the last stream ended; cleared by the next frame.
  String? get streamError => _live?.streamError;

  /// `/v1/props` with the exposure settings and their lists, and changes
  /// not answered yet.
  GrProps? get props => _live?.props;

  /// The focus mark to show: a result goes 2 s after it came.
  FocusMark? get focus {
    final f = _live?.focus;
    return identical(f, _hiddenFocus) ? null : f;
  }

  /// Thumbnail of the newest picture taken while live view is on.
  Uint8List? get lastShot => _live?.lastShot;

  /// Whether [CameraLiveView.modeSettings] are as the camera reported them
  /// for the current mode dial position.
  bool get modeSettled => _live?.modeSettled ?? false;

  /// Whether live view is wanted; see the class comment.
  bool get wanted => _wanted;

  set wanted(bool value) {
    if (_wanted == value) return;
    _wanted = value;
    _askedToJoin = false;
    if (!value) _live?.stop();
    _sync();
  }

  /// Joins again after a failed join.
  void retryJoin() {
    if (!_wanted) return;
    unawaited(connection.joinWifi());
  }

  /// Focuses on [at] (0..1 of the picture); see [CameraLiveView.focusAt].
  Future<void> focusAt(Offset at) async {
    await _live?.focusAt(at);
  }

  /// Sets an exposure setting to one of the values its list offers. The
  /// readouts show [value] at once and go back if the camera refuses it;
  /// returns why then.
  Future<SettingRefusal?> setSetting(String key, String value) async {
    final live = _live;
    if (live == null || !live.canChangeSettings) {
      return const SettingRefusalNotOnWifi();
    }
    try {
      await live.setSetting(key, value);
      return null;
    } on Object catch (e) {
      if (_disposed) return null;
      return SettingRefusalByCamera('$e');
    }
  }

  void _sync() {
    if (_disposed) return;
    _attach(connection.cameraSession?.liveView);
    final live = _live;
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
        live?.start();
      case ConnectionStatus.offline ||
          ConnectionStatus.connecting ||
          ConnectionStatus.bluetooth ||
          ConnectionStatus.failed:
        live?.stop();
    }
    notifyListeners();
  }

  void _attach(CameraLiveView? live) {
    final old = _live;
    if (identical(old, live)) return;
    if (old != null) {
      old
        ..removeListener(_onLive)
        ..stop();
      old.frame.removeListener(_onFrame);
    }
    _live = live;
    live?.addListener(_onLive);
    live?.frame.addListener(_onFrame);
    _onFrame();
    _onLive();
  }

  void _onFrame() => frame.value = _live?.frame.value;

  void _onLive() {
    if (_disposed) return;
    final f = _live?.focus;
    if (!identical(f, _timedFocus)) {
      _focusClear?.cancel();
      _focusClear = null;
      _timedFocus = null;
      if (f != null && f.state != FocusState.focusing) {
        _timedFocus = f;
        _focusClear = Timer(const Duration(seconds: 2), () {
          _hiddenFocus = f;
          notifyListeners();
        });
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_sync);
    _focusClear?.cancel();
    final live = _live;
    if (live != null) {
      live
        ..removeListener(_onLive)
        ..stop();
      live.frame.removeListener(_onFrame);
    }
    unawaited(_wifiUp.cancel());
    frame.dispose();
    super.dispose();
  }
}
