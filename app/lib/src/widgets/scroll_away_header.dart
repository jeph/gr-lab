import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A header that is the first sliver of a page scrolling down the screen.
/// It leaves with the page as the page scrolls down, and comes back over
/// the page as soon as it scrolls up again, however far down the page is.
/// A header left partly in view when the scrolling stops slides the rest
/// of the way: into view when most of it shows, out of it otherwise.
///
/// Flutter's [SliverFloatingHeader] does much the same, but goes by
/// [ScrollPosition.userScrollDirection], the direction of the last pointer
/// movement, which can be against the scroll it ends. On the Android 16
/// emulator with Flutter 3.47.9 (2026-11-10), that header slid back in
/// over the Library after three of five `adb shell input swipe`s that
/// flung it down; the one that was logged ended as
/// [ScrollDirection.forward]. This one goes by where the page moves, so a
/// movement too small to see changes nothing.
class SliverScrollAwayHeader extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<SliverScrollAwayHeader> createState() => _SliverScrollAwayHeaderState();
}

class _SliverScrollAwayHeaderState extends State<SliverScrollAwayHeader>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(_onSlide);
  final _slideRange = Tween<double>();
  ScrollPosition? _position;

  _RenderScrollAwayHeader get _header =>
      context.findRenderObject()! as _RenderScrollAwayHeader;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.of(context).position;
    if (position == _position) return;
    _position?.isScrollingNotifier.removeListener(_onScrollingChanged);
    _position = position..isScrollingNotifier.addListener(_onScrollingChanged);
  }

  @override
  void dispose() {
    _position?.isScrollingNotifier.removeListener(_onScrollingChanged);
    _slide.dispose();
    super.dispose();
  }

  void _onScrollingChanged() {
    if (_position!.isScrollingNotifier.value) {
      _slide.stop();
      return;
    }
    // The page's last movement only reaches the header at the next layout.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _slideToRest())
      ..ensureVisualUpdate();
  }

  void _slideToRest() {
    if (!mounted || _position!.isScrollingNotifier.value) return;
    final header = _header;
    final rest = header.restingHidden;
    if (rest == null) return;
    _slideRange
      ..begin = header.hidden
      ..end = rest;
    _slide.forward(from: 0);
  }

  void _onSlide() => _header.hidden = _slideRange.transform(
    Curves.easeOut.transform(_slide.value),
  );

  @override
  Widget build(BuildContext context) =>
      _ScrollAwayHeader(position: _position!, child: widget.child);
}

class _ScrollAwayHeader extends SingleChildRenderObjectWidget {
  const new({required this.position, required Widget super.child});

  final ScrollPosition position;

  @override
  _RenderScrollAwayHeader createRenderObject(BuildContext context) =>
      _RenderScrollAwayHeader(position);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollAwayHeader renderObject,
  ) => renderObject.position = position;
}

class _RenderScrollAwayHeader extends RenderSliverSingleBoxAdapter {
  new(this.position);

  /// The page's scroll position, for where the page ends.
  ScrollPosition position;

  /// How much of the header is above the start of the viewport: 0 with all
  /// of it in view, [_extent] with none.
  double get hidden => _hidden;
  double _hidden = 0;
  set hidden(double value) {
    if (value == _hidden) return;
    _hidden = value;
    markNeedsLayout();
  }

  /// The scroll offset at the last layout, null before the first.
  double? _pageOffset;

  double get _extent => child?.size.height ?? 0;

  /// The most of the header that can be out of view: near its start the
  /// page has not scrolled far enough to take all of it along.
  double get _mostHidden => math.min(_extent, _pageOffset ?? 0);

  /// The [hidden] a header that is partly in view slides to, or null when
  /// it is where it rests.
  double? get restingHidden {
    final most = _mostHidden;
    if (_hidden <= 0 || _hidden >= most) return null;
    return _hidden < _extent / 2 ? 0 : most;
  }

  @override
  void performLayout() {
    assert(
      constraints.axisDirection == AxisDirection.down &&
          constraints.growthDirection == GrowthDirection.forward,
      'for the start of a page that scrolls down the screen',
    );
    child?.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = _extent;
    // A page springing back from past its end, as on iOS, is not scrolling
    // up: it counts as resting at its end.
    final pageOffset = position.hasContentDimensions
        ? math.min(
            constraints.scrollOffset,
            math.max<double>(position.maxScrollExtent, 0),
          )
        : constraints.scrollOffset;
    _hidden += pageOffset - (_pageOffset ?? 0);
    _pageOffset = pageOffset;
    _hidden = clampDouble(_hidden, 0, _mostHidden);
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: clampDouble(
        extent - _hidden,
        0,
        constraints.remainingPaintExtent,
      ),
      layoutExtent: clampDouble(
        extent - constraints.scrollOffset,
        0,
        constraints.remainingPaintExtent,
      ),
      maxPaintExtent: extent,
      // Drawn over the slivers after it.
      hasVisualOverflow: true,
    );
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      math.min(0, (geometry?.paintExtent ?? _extent) - _extent);

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) =>
      applyPaintTransformForBoxChild(child as RenderBox, transform);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || !geometry!.visible) return;
    context.paintChild(child, offset + Offset(0, childMainAxisPosition(child)));
  }
}
