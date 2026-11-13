import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/platform/window_pose.dart';

/// The windows GR Photo gets on an iPhone Duo, as the iOS 27.1 simulator
/// reports them (`research/app/iphone-duo.md` §2): sizes and safe-area
/// insets in points, and what `WindowPosePlugin` sends.
enum DuoWindow {
  /// Closed, on the outer display: the vertical bar on the right.
  closed(
    size: Size(466, 678),
    insets: EdgeInsets.only(right: 84, bottom: 34),
    pose: WindowPose(
      barSide: BarSide.right,
      occlusions: [
        Rect.fromLTRB(399.7, 29.3, 436.7, 66.3),
        Rect.fromLTRB(382, 0, 466, 174),
      ],
    ),
  ),

  /// Open and held wide, flat: the vertical bar on the right and the fold
  /// down the middle, inactive.
  open(
    size: Size(951, 669),
    insets: EdgeInsets.only(right: 84, bottom: 34),
    pose: WindowPose(
      barSide: BarSide.right,
      fold: Rect.fromLTRB(455.5, 0, 495.5, 669),
      occlusions: [Rect.fromLTRB(867, 0, 951, 124)],
    ),
  ),

  /// Held wide and half-open, like a book: as [open], the fold active.
  book(
    size: Size(951, 669),
    insets: EdgeInsets.only(right: 84, bottom: 34),
    pose: WindowPose(
      barSide: BarSide.right,
      fold: Rect.fromLTRB(455.5, 0, 495.5, 669),
      halfOpen: true,
      occlusions: [Rect.fromLTRB(867, 0, 951, 124)],
    ),
  ),

  /// Open and held upright, flat: no vertical bar, the status in the last
  /// 144 pt of an 82 pt band across the top, the fold across the middle.
  upright(
    size: Size(669, 951),
    insets: EdgeInsets.only(top: 82, bottom: 34),
    pose: WindowPose(
      fold: Rect.fromLTRB(0, 455.5, 669, 495.5),
      occlusions: [Rect.fromLTRB(525, 0, 669, 82)],
    ),
  ),

  /// Held upright and half-open, standing on its lower half: as
  /// [upright], the fold active.
  tabletop(
    size: Size(669, 951),
    insets: EdgeInsets.only(top: 82, bottom: 34),
    pose: WindowPose(
      fold: Rect.fromLTRB(0, 455.5, 669, 495.5),
      halfOpen: true,
      occlusions: [Rect.fromLTRB(525, 0, 669, 82)],
    ),
  );

  new({required this.size, required this.insets, required this.pose});

  final Size size;
  final EdgeInsets insets;
  final WindowPose pose;
}

/// Gives the test's view the size and insets of [window] and [pose] its
/// pose, as unfolding or turning an iPhone Duo does; the view is reset
/// when the test ends. [pose] is `TestApp.windowPose`.
void setDuoWindow(
  WidgetTester tester,
  ValueNotifier<WindowPose> pose,
  DuoWindow window,
) {
  const scale = 3.0;
  final insets = FakeViewPadding(
    left: window.insets.left * scale,
    top: window.insets.top * scale,
    right: window.insets.right * scale,
    bottom: window.insets.bottom * scale,
  );
  tester.view
    ..devicePixelRatio = scale
    ..physicalSize = window.size * scale
    ..padding = insets
    ..viewPadding = insets;
  addTearDown(tester.view.reset);
  pose.value = window.pose;
}
