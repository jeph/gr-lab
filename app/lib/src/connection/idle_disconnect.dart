import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/settings.dart';

/// Leaves the camera's Wi-Fi ([ConnectionController.closeCamera]) after
/// [SettingsController.autoDisconnect] without use, returning to the
/// Cameras screen with Bluetooth still linked.
///
/// Use is a touch, scroll or key press anywhere in the app (reported by
/// [IdleInput]; while the Wi-Fi is up every screen sits over the Library),
/// navigation ([observer]), and a download, movie copy or playback
/// ([hold]), whose end counts as use too. Counting starts when the Wi-Fi
/// comes up and measures wall-clock time ([clock]), so time in the
/// background counts.
final class IdleDisconnect {
  new({required this.connection, required this.settings})
    : _last = clock.now() {
    connection.addListener(_update);
    settings.addListener(_schedule);
    _update();
  }

  final ConnectionController connection;
  final SettingsController settings;

  /// Counts every route change as use. Add to `navigatorObservers`.
  late final NavigatorObserver observer = _NavigationUse(this);

  DateTime _last;
  Timer? _timer;
  int _holds = 0;
  bool _connected = false;

  /// Records use now.
  void touch() => _last = clock.now();

  /// Keeps the Wi-Fi up until the returned callback runs (more than once
  /// is fine); that moment counts as use.
  VoidCallback hold() {
    _holds++;
    _schedule();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _holds--;
      touch();
      _schedule();
    };
  }

  void _update() {
    final connected = connection.status == ConnectionStatus.connected;
    if (connected && !_connected) touch();
    final changed = connected != _connected;
    _connected = connected;
    if (changed) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final after = settings.autoDisconnect.after;
    if (!_connected || after == null || _holds > 0) return;
    final left = _last.add(after).difference(clock.now());
    _timer = Timer(left.isNegative ? Duration.zero : left, _expired);
  }

  void _expired() {
    _timer = null;
    final after = settings.autoDisconnect.after;
    if (!_connected || after == null || _holds > 0) return;
    if (clock.now().difference(_last) < after) {
      _schedule();
      return;
    }
    unawaited(connection.closeCamera(idleFor: after));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    connection.removeListener(_update);
    settings.removeListener(_schedule);
  }
}

final class _NavigationUse extends NavigatorObserver {
  new(this._idle);

  final IdleDisconnect _idle;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _idle.touch();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _idle.touch();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _idle.touch();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _idle.touch();
}

/// Reports touches, scrolls and key presses under [child] to [idle].
class IdleInput extends StatefulWidget {
  const new({required this.idle, required this.child, super.key});

  final IdleDisconnect idle;
  final Widget child;

  @override
  State<IdleInput> createState() => _IdleInputState();
}

class _IdleInputState extends State<IdleInput> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    widget.idle.touch();
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => widget.idle.touch(),
    onPointerSignal: (_) => widget.idle.touch(),
    onPointerPanZoomStart: (_) => widget.idle.touch(),
    child: widget.child,
  );
}
