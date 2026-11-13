import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The viewer's column: the shot, its details and what is below them
/// (the `shot`, `details` and `below` children). It is as tall as the
/// viewer ([height]) when `below` is no taller than [belowShown]; of a
/// taller one, [belowShown] is in view and the rest follows below the
/// viewer's bottom edge, for its scroll view to bring up. The `shot` gets
/// the room the other two leave of [height].
class ShotOverDetails extends MultiChildRenderObjectWidget {
  new({
    required this.height,
    required this.belowShown,
    required Widget shot,
    required Widget details,
    required Widget below,
    super.key,
  }) : super(children: [shot, details, below]);

  final double height;
  final double belowShown;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderShotOverDetails(height: height, belowShown: belowShown);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderShotOverDetails renderObject,
  ) {
    renderObject
      ..height = height
      ..belowShown = belowShown;
  }
}

class _ColumnSlot extends ContainerBoxParentData<RenderBox>;

/// Lays out [ShotOverDetails].
class RenderShotOverDetails extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ColumnSlot>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ColumnSlot> {
  new({required this._height, required this._belowShown});

  double _height;
  double get height => _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  double _belowShown;
  double get belowShown => _belowShown;
  set belowShown(double value) {
    if (value == _belowShown) return;
    _belowShown = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ColumnSlot) child.parentData = _ColumnSlot();
  }

  @override
  void performLayout() {
    final shot = firstChild!;
    final details = childAfter(shot)!;
    final below = childAfter(details)!;
    final width = constraints.maxWidth;
    final asTallAsItIs = BoxConstraints.tightFor(width: width);
    details.layout(asTallAsItIs, parentUsesSize: true);
    below.layout(asTallAsItIs, parentUsesSize: true);
    final shotHeight = max(
      0,
      height - details.size.height - min(below.size.height, belowShown),
    ).toDouble();
    shot.layout(BoxConstraints.tight(Size(width, shotHeight)));
    (details.parentData! as _ColumnSlot).offset = Offset(0, shotHeight);
    (below.parentData! as _ColumnSlot).offset = Offset(
      0,
      shotHeight + details.size.height,
    );
    size = Size(width, shotHeight + details.size.height + below.size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
