import 'package:flutter/material.dart';

/// A button that draws itself: while a finger is on it, [child] dims and
/// shrinks a little under a highlight in the button's [shape], so a touch
/// shows before its action does. For buttons Material's ink cannot mark,
/// because their own picture or background would cover it; the others use
/// an `InkWell` on a `Material`.
///
/// A quick tap still plays the whole change. The whole of [child]'s box
/// takes the touch. Without [onTap] and [onLongPress] it is disabled and
/// does not react.
class Pressable extends StatefulWidget {
  const new({
    required this.onTap,
    required this.child,
    super.key,
    this.onLongPress,
    this.shape = const RoundedRectangleBorder(),
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The outline of the highlight; [child]'s box unless given.
  final ShapeBorder shape;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 70),
    reverseDuration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 1,
    end: .5,
  ).animate(_press);
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: .96,
  ).animate(_press);
  bool _held = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    _press.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _hold() {
    _held = true;
    _press.forward();
  }

  void _release() {
    _held = false;
    // A finger lifted mid-way lets the dimming finish first: see [_onStatus].
    if (_press.isCompleted) _press.reverse();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_held) _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _hold() : null,
      onTapUp: _enabled ? (_) => _release() : null,
      onTapCancel: _enabled ? _release : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        // No shrinking when the platform asks for less motion.
        scale: MediaQuery.disableAnimationsOf(context)
            ? const AlwaysStoppedAnimation(1)
            : _scale,
        child: DecoratedBoxTransition(
          position: DecorationPosition.foreground,
          decoration: DecorationTween(
            begin: ShapeDecoration(
              color: highlight.withValues(alpha: 0),
              shape: widget.shape,
            ),
            end: ShapeDecoration(
              color: highlight.withValues(alpha: .12),
              shape: widget.shape,
            ),
          ).animate(_press),
          child: FadeTransition(opacity: _opacity, child: widget.child),
        ),
      ),
    );
  }
}
