import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/window_layout.dart';

/// The app's toasts, as a screen shows them: a short message that
/// something worked ([done]) or did not ([failed]), in a capsule of the
/// dock's material as wide as its words, with a tick or a mark in front
/// (mock `notifications.html`, direction A). It floats above what the
/// screen in front keeps along its bottom edge ([ToastFloor]), stays a
/// moment and leaves; a tap or a swipe down sends it away sooner. A toast
/// shown while another is up takes its place in the same capsule.
///
/// Taken from a screen's context before its work starts, it still shows
/// the outcome when the screen has closed meanwhile.
final class Toasts {
  new _(this._host, this._colors);

  /// The toasts of the app around [context], in the colours of the theme
  /// there: live view keeps a dark one under a light app.
  factory of(BuildContext context) => Toasts._(
    context.getInheritedWidgetOfExactType<_ToastScope>()!.host,
    GrColors.of(context),
  );

  final _ToastHostState _host;
  final GrColors _colors;

  /// Says that something worked.
  void done(String text) => _host._show(text, failed: false, colors: _colors);

  /// Says that something did not work.
  void failed(String text) => _host._show(text, failed: true, colors: _colors);
}

/// Shows the [Toasts] of everything in [child] over it.
class ToastHost extends StatefulWidget {
  const new({required this.child, super.key});

  /// A toast that something worked stays this long, one that it failed
  /// [failedStay]: a failure takes longer to read and matters more
  /// \[design\].
  static const doneStay = Duration(milliseconds: 2500);
  static const failedStay = Duration(seconds: 5);

  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost>
    with SingleTickerProviderStateMixin {
  /// How far the toast has come in: it rises as it appears and sinks as
  /// it goes.
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    reverseDuration: const Duration(milliseconds: 180),
  )..addStatusListener(_onShown);

  final Set<_ToastFloorState> _floors = {};
  _Toast? _toast;
  Timer? _stay;

  /// How far above the window's bottom edge [_toast] floats.
  double _bottom = 0;
  bool _following = false;

  @override
  void dispose() {
    _stay?.cancel();
    _shown.dispose();
    super.dispose();
  }

  void _show(String text, {required bool failed, required GrColors colors}) {
    if (!mounted) return;
    _stay?.cancel();
    _stay = Timer(failed ? ToastHost.failedStay : ToastHost.doneStay, _leave);
    setState(() {
      _toast = _Toast(text: text, failed: failed, colors: colors);
      _bottom = _clearBottom();
    });
    _shown.forward();
    _follow();
  }

  /// Keeps the toast clear of the screen's bottom edge as that moves under
  /// it, after every frame while it shows: the keyboard closes behind a
  /// name that was typed, a dock comes or goes.
  void _follow() {
    if (_following) return;
    _following = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _following = false;
      if (!mounted || _toast == null) return;
      final bottom = _clearBottom();
      if (bottom != _bottom) setState(() => _bottom = bottom);
      _follow();
    });
  }

  /// Sends the toast away as it came.
  void _leave() {
    _stay?.cancel();
    _shown.reverse();
  }

  /// Takes away a toast that was swiped off, at once.
  void _remove() {
    _stay?.cancel();
    _shown.value = 0;
    setState(() => _toast = null);
  }

  void _onShown(AnimationStatus status) {
    if (status.isDismissed && _toast != null) setState(() => _toast = null);
  }

  /// How far above the window's bottom edge a toast floats: 8 above the
  /// highest [ToastFloor] of the screen in front and above the keyboard,
  /// and where the dock is on a screen with neither.
  double _clearBottom() {
    final media = MediaQuery.of(context);
    final window = context.findRenderObject()! as RenderBox;
    var bottom = math.max(
      media.viewPadding.bottom + 12,
      media.viewInsets.bottom + 8,
    );
    for (final floor in _floors) {
      final top = floor._topIn(window);
      if (top != null) bottom = math.max(bottom, window.size.height - top + 8);
    }
    return bottom;
  }

  @override
  Widget build(BuildContext context) {
    final toast = _toast;
    final bar = VerticalBar.of(context);
    return _ToastScope(
      host: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (toast != null)
            // Centred over the pages, not over a vertical bar beside them.
            Positioned(
              left: 16 + (bar?.side == BarSide.left ? bar!.width : 0),
              right: 16 + (bar?.side == BarSide.right ? bar!.width : 0),
              bottom: _bottom,
              child: Center(
                child: AnimatedBuilder(
                  animation: _shown,
                  builder: (context, child) {
                    final t = _shown.isForwardOrCompleted
                        ? Curves.easeOutCubic.transform(_shown.value)
                        : Curves.easeIn.transform(_shown.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - t)),
                        child: child,
                      ),
                    );
                  },
                  child: Dismissible(
                    key: const ValueKey('toast-swipe'),
                    direction: DismissDirection.down,
                    resizeDuration: null,
                    onDismissed: (_) => _remove(),
                    child: _Capsule(toast: toast, onDismiss: _leave),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToastScope extends InheritedWidget {
  const new({required this.host, required super.child});

  final _ToastHostState host;

  @override
  bool updateShouldNotify(_ToastScope old) => false;
}

/// What a toast says, and in which colours.
@immutable
final class _Toast {
  const new({required this.text, required this.failed, required this.colors});

  final String text;
  final bool failed;
  final GrColors colors;
}

class _Capsule extends StatelessWidget {
  const new({required this.toast, required this.onDismiss});

  final _Toast toast;
  final VoidCallback onDismiss;

  static const _height = 44.0;

  @override
  Widget build(BuildContext context) {
    final c = toast.colors;
    final tone = toast.failed ? c.danger : c.ok;
    return Semantics(
      container: true,
      liveRegion: true,
      onDismiss: onDismiss,
      child: GestureDetector(
        onTap: onDismiss,
        child: Container(
          key: const Key('toast'),
          constraints: const BoxConstraints(minHeight: _height, maxWidth: 480),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 16, 8),
          decoration: c.floating(radius: _height / 2),
          // The host is above the app's pages, with no Material of theirs
          // to give the words a text style.
          child: Material(
            type: MaterialType.transparency,
            // A toast that takes another's place changes the words in the
            // capsule, which grows or shrinks to them.
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Row(
                  key: ValueKey(toast),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: .16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        toast.failed
                            ? Icons.priority_high_rounded
                            : Icons.check_rounded,
                        key: Key(toast.failed ? 'toast-failed' : 'toast-done'),
                        size: 14,
                        color: tone,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        toast.text,
                        style: TextStyle(
                          fontFamily: GrFonts.ui,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: c.t1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Something a screen keeps along its bottom edge, such as the dock or a
/// row of buttons: [child], which toasts float above instead of lying on
/// it. It counts while its screen is the one in front and it takes up
/// room.
class ToastFloor extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<ToastFloor> createState() => _ToastFloorState();
}

class _ToastFloorState extends State<ToastFloor> {
  late final _ToastHostState _host = context
      .getInheritedWidgetOfExactType<_ToastScope>()!
      .host;

  /// Whether its screen is in front: a page of a dock that is not the
  /// chosen one, and a screen under another, have their tickers off.
  bool _inFront = true;

  @override
  void initState() {
    super.initState();
    _host._floors.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inFront = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    _host._floors.remove(this);
    super.dispose();
  }

  /// How far its top edge is below the top of [window], or null while it
  /// is not in front or takes up no room.
  double? _topIn(RenderBox window) {
    if (!_inFront) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero, ancestor: window).dy;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
