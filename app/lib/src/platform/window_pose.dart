import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The side of the window the system's vertical bar is on.
enum BarSide { left, right }

/// What a foldable iPhone says about the app's window that Flutter does not
/// report itself (flutter/flutter #193038 and #193062, open as of Flutter
/// 3.47): where iOS puts its vertical bar and where the display folds.
/// Android reports a fold through `MediaQuery.displayFeatures` and has no
/// vertical bar, so there, and on every other iPhone and iPad, this is
/// [none].
@immutable
final class WindowPose {
  const new({
    this.barSide,
    this.fold,
    this.halfOpen = false,
    this.occlusions = const [],
  });

  /// [pose] as `io.jeph.grphoto/window` sends it: `bar` (`left` or `right`),
  /// `fold` and each of `occlusions` as `[left, top, width, height]` in the
  /// window's points, and `foldActive`. Anything missing or malformed is
  /// left out.
  factory fromChannel(Map<Object?, Object?> pose) {
    final occlusions = pose['occlusions'];
    return WindowPose(
      barSide: switch (pose['bar']) {
        'left' => BarSide.left,
        'right' => BarSide.right,
        _ => null,
      },
      fold: _rect(pose['fold']),
      halfOpen: pose['foldActive'] == true,
      occlusions: [
        if (occlusions is List)
          for (final occlusion in occlusions) ?_rect(occlusion),
      ],
    );
  }

  /// A window with no vertical bar and no fold.
  static const none = WindowPose();

  /// Where iOS puts bars that stand upright in this window
  /// (`UITraitCollection.verticalBarEdge`), null where it uses none. iOS
  /// names the edge it prefers whether or not a bar shows, so a bar is
  /// only there when the window also has a safe-area inset on that side.
  final BarSide? barSide;

  /// The band the display folds along, in the window's logical pixels
  /// (the `division` reserved region of the Flutter view); null in a
  /// window with no fold.
  final Rect? fold;

  /// Whether the display is folded part of the way, so that nothing
  /// should lie across [fold] (the region is active).
  final bool halfOpen;

  /// What the system draws over the window (the `occlusion` reserved
  /// regions): the time and status at the top of the vertical bar, and the
  /// camera.
  final List<Rect> occlusions;

  static Rect? _rect(Object? value) {
    if (value is! List || value.length != 4) return null;
    final [left, top, width, height] = value;
    if (left is! num || top is! num || width is! num || height is! num) {
      return null;
    }
    return Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WindowPose &&
      other.barSide == barSide &&
      other.fold == fold &&
      other.halfOpen == halfOpen &&
      listEquals(other.occlusions, occlusions);

  @override
  int get hashCode =>
      Object.hash(barSide, fold, halfOpen, Object.hashAll(occlusions));

  @override
  String toString() =>
      'WindowPose(bar: ${barSide?.name}, fold: $fold, halfOpen: $halfOpen, '
      'occlusions: $occlusions)';
}

/// The [WindowPose] of the app's window, kept up to date by the iOS runner
/// (`WindowPosePlugin`). Stays [WindowPose.none] on Android and on an iOS
/// older than 27.1, which have no such channel or nothing to say on it.
final class PlatformWindowPose extends ValueNotifier<WindowPose> {
  new({this._channel = const MethodChannel('io.jeph.grphoto/window')})
    : super(WindowPose.none) {
    _channel.setMethodCallHandler(_onCall);
    unawaited(_read());
  }

  final MethodChannel _channel;

  Future<void> _read() async {
    try {
      _take(await _channel.invokeMapMethod<Object?, Object?>('get'));
    } on PlatformException catch (e) {
      debugPrint('window pose: not read: $e');
    } on MissingPluginException {
      // Android, and tests.
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'changed') throw MissingPluginException();
    final pose = call.arguments;
    _take(pose is Map ? pose : null);
  }

  void _take(Map<Object?, Object?>? pose) {
    final next = pose == null ? WindowPose.none : WindowPose.fromChannel(pose);
    if (next == value) return;
    debugPrint('window pose: $next (${pose?['hinge']})');
    value = next;
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
