import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:grphoto/src/platform/window_pose.dart';

/// Gives the pages under it the window's [WindowPose]: the vertical bar
/// ([VerticalBar.of]) and, as a display feature of the [MediaQuery], the
/// fold of a foldable iPhone, so that [WindowFold] and Flutter's own
/// dialogs see it as they see an Android foldable's.
class WindowPoseScope extends StatelessWidget {
  const new({required this.pose, required this.child, super.key});

  final ValueListenable<WindowPose> pose;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: pose,
    builder: (context, pose, child) {
      final media = MediaQuery.of(context);
      final fold = _foldOf(pose, media);
      return _PoseScope(
        // Of the window: a page's own `SafeArea` takes the insets away
        // from what is under it.
        bar: VerticalBar._of(pose, media),
        band: StatusBand._of(pose, media),
        child: MediaQuery(
          data: fold == null
              ? media
              : media.copyWith(
                  displayFeatures: [...media.displayFeatures, fold],
                ),
          child: child!,
        ),
      );
    },
    child: child,
  );

  /// The fold of [pose] as a display feature; null without one, and once
  /// Flutter reports a fold of this window itself.
  static ui.DisplayFeature? _foldOf(WindowPose pose, MediaQueryData media) {
    final band = pose.fold;
    if (band == null || media.displayFeatures.any(WindowFold.isFold)) {
      return null;
    }
    // A display that lies flat has nothing to keep clear of: as on
    // Android, its fold is then a line, down the middle of the band.
    final upright = band.height > band.width;
    final line = upright
        ? Rect.fromLTRB(band.center.dx, band.top, band.center.dx, band.bottom)
        : Rect.fromLTRB(band.left, band.center.dy, band.right, band.center.dy);
    return ui.DisplayFeature(
      bounds: pose.halfOpen ? band : line,
      type: ui.DisplayFeatureType.fold,
      state: pose.halfOpen
          ? ui.DisplayFeatureState.postureHalfOpened
          : ui.DisplayFeatureState.postureFlat,
    );
  }
}

class _PoseScope extends InheritedWidget {
  const new({required this.bar, required this.band, required super.child});

  final VerticalBar? bar;
  final StatusBand? band;

  @override
  bool updateShouldNotify(_PoseScope old) => old.bar != bar || old.band != band;
}

/// The strip down one side of the window that iOS keeps for bars that
/// stand upright (iPhone Duo: closed, and open and held wide). iOS draws
/// the time and the status at its top and leaves the rest to the app, as a
/// safe-area inset: the pages put their buttons there ([BarColumn]) and
/// the dock stands in it.
@immutable
final class VerticalBar {
  const new({required this.side, required this.width, required this.top});

  final BarSide side;

  /// The strip's width: the window's safe-area inset on [side].
  final double width;

  /// Where the app's part of the strip starts, under what the system
  /// draws at its top.
  final double top;

  /// A narrower inset than this is not a bar: a camera cutout, or the
  /// room beside the rounded corners \[design\].
  static const _leastWidth = 56.0;

  /// Between the system's status and the first button \[design\].
  static const _statusGap = 10.0;

  /// The vertical bar of the window [context] is in; null in a window
  /// without one, which is every window but a foldable iPhone's.
  static VerticalBar? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PoseScope>()?.bar;

  /// The vertical bar of a window with [pose] and [media].
  static VerticalBar? _of(WindowPose pose, MediaQueryData media) {
    final side = pose.barSide;
    if (side == null) return null;
    final insets = media.viewPadding;
    final width = side == BarSide.left ? insets.left : insets.right;
    if (width < _leastWidth) return null;
    final window = media.size;
    final strip = side == BarSide.left
        ? Rect.fromLTWH(0, 0, width, window.height)
        : Rect.fromLTWH(window.width - width, 0, width, window.height);
    var top = insets.top;
    for (final occlusion in pose.occlusions) {
      // The status, not something further down the strip.
      if (occlusion.overlaps(strip) && occlusion.top < window.height / 2) {
        top = math.max(top, occlusion.bottom);
      }
    }
    return VerticalBar(side: side, width: width, top: top + _statusGap);
  }

  @override
  bool operator ==(Object other) =>
      other is VerticalBar &&
      other.side == side &&
      other.width == width &&
      other.top == top;

  @override
  int get hashCode => Object.hash(side, width, top);
}

/// The band across the top of the window that iOS keeps for its status
/// where the status takes one end of it only (iPhone Duo, open and held
/// upright: a band of 82 pt with the time and the status in its last
/// 144 pt). A page's top bar goes in the band, beside the status, instead
/// of under it ([StatusBandBar]).
@immutable
final class StatusBand {
  const new({required this.height, required this.left, required this.right});

  /// The band's height: the window's safe-area inset at the top.
  final double height;

  /// What the status takes of the band at either end.
  final double left;
  final double right;

  /// A lower inset than this has no room for a bar \[design\].
  static const _leastHeight = 56.0;

  /// The status band of the window [context] is in; null in a window
  /// whose status runs the width of its top, or stands in a
  /// [VerticalBar], which is every window but a foldable iPhone's.
  static StatusBand? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PoseScope>()?.band;

  /// The status band of a window with [pose] and [media].
  static StatusBand? _of(WindowPose pose, MediaQueryData media) {
    final height = media.viewPadding.top;
    if (height < _leastHeight) return null;
    final window = media.size;
    for (final occlusion in pose.occlusions) {
      // The status: in the band, from one corner of the window.
      final atLeft = occlusion.left <= 0;
      final atRight = occlusion.right >= window.width;
      if (occlusion.top > 0 ||
          occlusion.bottom > height ||
          atLeft == atRight ||
          occlusion.width > window.width / 2) {
        continue;
      }
      return StatusBand(
        height: height,
        left: atLeft ? occlusion.right : 0,
        right: atRight ? window.width - occlusion.left : 0,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is StatusBand &&
      other.height == height &&
      other.left == left &&
      other.right == right;

  @override
  int get hashCode => Object.hash(height, left, right);
}

/// [child], the bar at the top of a page, clear of the system's status:
/// under the window's top inset, or in it beside the status where the
/// window has a [StatusBand]. [child] is no taller than [barHeight]. In a
/// window with a [VerticalBar], whose top has no inset, it keeps
/// [cornerMargin] above it.
class StatusBandBar extends StatelessWidget {
  const new({required this.barHeight, required this.child, super.key});

  /// Above the first thing on a page in a window with a [VerticalBar]: the
  /// status stands in the bar there, so the window has no inset at the
  /// top, and the display's corners are rounded \[design\].
  static const cornerMargin = 14.0;

  final double barHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final band = StatusBand.of(context);
    if (band == null) {
      return SafeArea(
        bottom: false,
        minimum: VerticalBar.of(context) == null
            ? EdgeInsets.zero
            : const EdgeInsets.only(top: cornerMargin),
        child: child,
      );
    }
    final insets = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        top: math.max(0, (band.height - barHeight) / 2),
        left: math.max(insets.left, band.left),
        right: math.max(insets.right, band.right),
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeLeft: true,
        removeRight: true,
        child: child,
      ),
    );
  }
}

/// [child], a whole page, with [buttons] down the window's [VerticalBar]
/// under the system's status, where iOS puts a page's bar buttons. In a
/// window without a vertical bar it is [child] alone, and the page shows
/// the buttons in a bar of its own.
///
/// [child] keeps its place in the tree either way, so a page keeps its
/// state when the bar comes and goes (the open phone turned upright).
class BarColumn extends StatelessWidget {
  const new({
    required this.buttons,
    required this.child,
    super.key,
    this.buttonsCovered = false,
  });

  /// Between two buttons \[design\].
  static const gap = 10.0;

  final List<Widget> buttons;
  final Widget child;

  /// Whether something over the page covers the [buttons], so that a
  /// screen reader does not reach them either: they are painted after
  /// [child], where a block in it leaves them.
  final bool buttonsCovered;

  @override
  Widget build(BuildContext context) {
    final bar = VerticalBar.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (bar != null && buttons.isNotEmpty)
          Positioned(
            top: bar.top,
            left: bar.side == BarSide.left ? 0 : null,
            right: bar.side == BarSide.right ? 0 : null,
            width: bar.width,
            child: ExcludeSemantics(
              excluding: buttonsCovered,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: gap,
                children: buttons,
              ),
            ),
          ),
      ],
    );
  }
}

/// The fold or hinge of a foldable where it crosses the window, and the
/// room either side of it.
abstract final class WindowFold {
  static bool isFold(ui.DisplayFeature feature) =>
      feature.type == ui.DisplayFeatureType.fold ||
      feature.type == ui.DisplayFeatureType.hinge;

  /// The fold or hinge the window lies across; null on a device without
  /// one, on a foldable's cover screen and in a window to one side of it.
  static ui.DisplayFeature? of(BuildContext context) =>
      MediaQuery.displayFeaturesOf(context).where(isFold).firstOrNull;

  /// The fold where it stands upright in the window, flat or half-open
  /// like a book, with a page of at least [leastPage] on either side of
  /// it; null otherwise. The pages are what the window's insets leave of
  /// its two sides. [context] is one whose insets are the window's.
  static BookFold? book(BuildContext context, {required double leastPage}) {
    final fold = of(context)?.bounds;
    if (fold == null || fold.height <= fold.width) return null;
    final insets = MediaQuery.paddingOf(context);
    final left = fold.left - insets.left;
    final right = MediaQuery.sizeOf(context).width - insets.right - fold.right;
    if (math.min(left, right) < leastPage) return null;
    final leftFirst = Directionality.of(context) == TextDirection.ltr;
    return BookFold(
      first: leftFirst ? left : right,
      gap: fold.width,
      second: leftFirst ? right : left,
    );
  }

  /// The fold of a foldable that is half-open on a table, lying across the
  /// window: its bounds in the window; null otherwise.
  static Rect? table(BuildContext context) {
    final feature = of(context);
    if (feature == null ||
        feature.state != ui.DisplayFeatureState.postureHalfOpened) {
      return null;
    }
    final fold = feature.bounds;
    return fold.width > fold.height ? fold : null;
  }
}

/// The two pages of a window whose fold stands upright ([WindowFold.book]):
/// the widths of the page the text direction starts on, of the fold, and
/// of the other page.
@immutable
final class BookFold {
  const new({required this.first, required this.gap, required this.second});

  final double first;
  final double gap;
  final double second;
}
