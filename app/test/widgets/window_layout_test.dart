import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/dock.dart';
import 'package:grphoto/src/widgets/toast.dart';
import 'package:grphoto/src/widgets/window_layout.dart';

import '../support/duo_window.dart';

/// [home] in an app whose window has [pose].
Future<void> _pump(
  WidgetTester tester,
  ValueNotifier<WindowPose> pose,
  Widget home,
) => tester.pumpWidget(
  MaterialApp(
    theme: grTheme(GrColors.dark),
    builder: (context, child) => WindowPoseScope(
      pose: pose,
      child: ToastHost(child: child!),
    ),
    home: home,
  ),
);

/// Builds [builder] with a context under the window's pose.
Widget _probe(void Function(BuildContext context) builder) => Builder(
  builder: (context) {
    builder(context);
    return const SizedBox.expand();
  },
);

class _Counter extends StatefulWidget {
  const new();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late ValueNotifier<WindowPose> pose;

  setUp(() => pose = ValueNotifier(WindowPose.none));
  tearDown(() => pose.dispose());

  group('VerticalBar', () {
    testWidgets('is the strip iOS keeps on an iPhone Duo, under its status', (
      tester,
    ) async {
      VerticalBar? bar;
      setDuoWindow(tester, pose, DuoWindow.closed);
      await _pump(tester, pose, _probe((c) => bar = VerticalBar.of(c)));
      expect(bar?.side, BarSide.right);
      expect(bar?.width, 84);
      expect(bar?.top, greaterThan(174), reason: 'under the status');
      expect(bar?.top, lessThan(200));

      setDuoWindow(tester, pose, DuoWindow.open);
      await tester.pump();
      expect(bar?.width, 84);
      expect(bar?.top, greaterThan(124));
      expect(bar?.top, lessThan(150));

      setDuoWindow(tester, pose, DuoWindow.upright);
      await tester.pump();
      expect(bar, isNull, reason: 'bars lie across an upright window');
    });

    testWidgets('is absent on every other phone', (tester) async {
      VerticalBar? bar;
      // A phone on its side: insets at both ends, and nothing from iOS.
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(956, 440) * 3
        ..padding = const FakeViewPadding(left: 186, right: 186, bottom: 63)
        ..viewPadding = const FakeViewPadding(
          left: 186,
          right: 186,
          bottom: 63,
        );
      addTearDown(tester.view.reset);
      await _pump(tester, pose, _probe((c) => bar = VerticalBar.of(c)));
      expect(bar, isNull);

      // iOS names the edge it prefers whether or not a bar shows.
      pose.value = const WindowPose(barSide: BarSide.left);
      tester.view
        ..padding = FakeViewPadding.zero
        ..viewPadding = FakeViewPadding.zero;
      await tester.pump();
      expect(bar, isNull, reason: 'no inset, so no bar');

      // Without the scope, as in a test that pumps a screen by itself.
      await tester.pumpWidget(
        MaterialApp(home: _probe((c) => bar = VerticalBar.of(c))),
      );
      expect(bar, isNull);
    });
  });

  group('BarColumn', () {
    testWidgets('stands its buttons in the bar and keeps the page as it '
        'comes and goes', (tester) async {
      setDuoWindow(tester, pose, DuoWindow.closed);
      await _pump(
        tester,
        pose,
        const BarColumn(
          buttons: [
            SizedBox.square(key: Key('one'), dimension: 36),
            SizedBox.square(key: Key('two'), dimension: 36),
          ],
          child: _Counter(),
        ),
      );
      tester.state<_CounterState>(find.byType(_Counter)).count = 7;
      const strip = Rect.fromLTRB(382, 174, 466, 678);
      final one = tester.getRect(find.byKey(const Key('one')));
      final two = tester.getRect(find.byKey(const Key('two')));
      expect(strip.contains(one.topLeft), isTrue, reason: '$one');
      expect(strip.contains(two.bottomRight), isTrue, reason: '$two');
      expect(one.center.dx, strip.center.dx);
      expect(two.top, greaterThan(one.bottom));
      expect(tester.getSize(find.byType(_Counter)), const Size(466, 678));

      setDuoWindow(tester, pose, DuoWindow.upright);
      await tester.pump();
      expect(find.byKey(const Key('one')), findsNothing);
      expect(tester.getSize(find.byType(_Counter)), const Size(669, 951));
      expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    });
  });

  group('StatusBand', () {
    testWidgets('is the top inset an upright iPhone Duo leaves beside its '
        'status', (tester) async {
      StatusBand? band;
      setDuoWindow(tester, pose, DuoWindow.upright);
      await _pump(tester, pose, _probe((c) => band = StatusBand.of(c)));
      expect(band?.height, 82);
      expect(band?.left, 0);
      expect(band?.right, 144);

      setDuoWindow(tester, pose, DuoWindow.closed);
      await tester.pump();
      expect(band, isNull, reason: 'the status stands in the bar');
    });

    testWidgets('is absent where the status is not at one end of the top', (
      tester,
    ) async {
      StatusBand? band;
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(402, 874) * 3
        ..padding = const FakeViewPadding(top: 186, bottom: 102)
        ..viewPadding = const FakeViewPadding(top: 186, bottom: 102);
      addTearDown(tester.view.reset);
      // A camera island in the middle, and a status the width of the top.
      pose.value = const WindowPose(
        occlusions: [
          Rect.fromLTRB(138, 14, 264, 51),
          Rect.fromLTRB(0, 0, 402, 62),
        ],
      );
      await _pump(tester, pose, _probe((c) => band = StatusBand.of(c)));
      expect(band, isNull);
    });

    testWidgets('holds a top bar beside the status, and under the top '
        'inset elsewhere', (tester) async {
      const bar = StatusBandBar(
        barHeight: 42,
        child: SizedBox(key: Key('bar'), width: double.infinity, height: 42),
      );
      const page = Align(alignment: Alignment.topCenter, child: bar);
      setDuoWindow(tester, pose, DuoWindow.upright);
      await _pump(tester, pose, page);
      var rect = tester.getRect(find.byKey(const Key('bar')));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(82), reason: 'in the band');
      expect(rect.right, lessThanOrEqualTo(525), reason: 'beside the status');
      expect(rect.center.dy, 41);

      // A phone: under the status bar.
      pose.value = WindowPose.none;
      tester.view
        ..physicalSize = const Size(402, 874) * 3
        ..padding = const FakeViewPadding(top: 186)
        ..viewPadding = const FakeViewPadding(top: 186);
      await tester.pump();
      rect = tester.getRect(find.byKey(const Key('bar')));
      expect(rect, const Rect.fromLTWH(0, 62, 402, 42));

      // A vertical bar leaves the top without an inset: clear of the
      // rounded corner.
      setDuoWindow(tester, pose, DuoWindow.closed);
      await tester.pump();
      rect = tester.getRect(find.byKey(const Key('bar')));
      expect(rect.top, StatusBandBar.cornerMargin);
      expect(rect.right, 382, reason: 'clear of the bar');
    });
  });

  group('the fold', () {
    testWidgets('of an iPhone Duo is a display feature, as on Android', (
      tester,
    ) async {
      List<DisplayFeature>? features;
      BookFold? book;
      Rect? table;
      final probe = _probe((c) {
        features = MediaQuery.displayFeaturesOf(c);
        book = WindowFold.book(c, leastPage: 300);
        table = WindowFold.table(c);
      });
      setDuoWindow(tester, pose, DuoWindow.open);
      await _pump(tester, pose, probe);
      expect(features, hasLength(1));
      expect(features!.single.type, DisplayFeatureType.fold);
      expect(features!.single.state, DisplayFeatureState.postureFlat);
      expect(
        features!.single.bounds,
        const Rect.fromLTRB(475.5, 0, 475.5, 669),
        reason: 'flat, there is nothing to keep clear of',
      );
      expect(book?.first, 475.5);
      expect(book?.gap, 0);
      expect(book?.second, 951 - 84 - 475.5);
      expect(table, isNull);

      setDuoWindow(tester, pose, DuoWindow.book);
      await tester.pump();
      expect(features!.single.state, DisplayFeatureState.postureHalfOpened);
      expect(
        features!.single.bounds,
        const Rect.fromLTRB(455.5, 0, 495.5, 669),
      );
      expect(book?.first, 455.5);
      expect(book?.gap, 40);
      expect(book?.second, 951 - 84 - 495.5);
      expect(table, isNull, reason: 'the fold stands upright');

      setDuoWindow(tester, pose, DuoWindow.tabletop);
      await tester.pump();
      expect(book, isNull, reason: 'the fold lies across the window');
      expect(table, const Rect.fromLTRB(0, 455.5, 669, 495.5));

      setDuoWindow(tester, pose, DuoWindow.upright);
      await tester.pump();
      expect(table, isNull, reason: 'flat');

      setDuoWindow(tester, pose, DuoWindow.closed);
      await tester.pump();
      expect(features, isEmpty);
      expect(book, isNull);
    });

    testWidgets('is left to Flutter once it reports one itself', (
      tester,
    ) async {
      List<DisplayFeature>? features;
      setDuoWindow(tester, pose, DuoWindow.book);
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTRB(1366.5, 0, 1486.5, 2007),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      await _pump(
        tester,
        pose,
        _probe((c) => features = MediaQuery.displayFeaturesOf(c)),
      );
      expect(features, hasLength(1));
    });

    testWidgets('gives no pages to a window too narrow for two', (
      tester,
    ) async {
      BookFold? book;
      setDuoWindow(tester, pose, DuoWindow.open);
      await _pump(
        tester,
        pose,
        _probe((c) => book = WindowFold.book(c, leastPage: 400)),
      );
      expect(book, isNull, reason: 'the bar leaves the second page 391.5');
    });
  });

  group('Dock', () {
    Widget pages() => DockLayout(
      dock: Dock<int>(
        key: const Key('dock'),
        items: const [
          DockItem(0, icon: Icons.photo_library_outlined, label: 'Library'),
          DockItem(1, icon: Icons.photo_camera_outlined, label: 'Shoot'),
          DockItem(2, icon: Icons.palette_outlined, label: 'Looks'),
        ],
        selected: 0,
        onSelect: (_) {},
      ),
      child: Builder(
        builder: (context) => SizedBox.expand(
          key: ValueKey(MediaQuery.paddingOf(context).bottom),
        ),
      ),
    );

    testWidgets('stands in the vertical bar, icons only, beside the pages', (
      tester,
    ) async {
      setDuoWindow(tester, pose, DuoWindow.open);
      await _pump(tester, pose, pages());
      final dock = tester.getRect(find.byKey(const Key('dock')));
      expect(dock.left, greaterThanOrEqualTo(867));
      expect(dock.right, lessThanOrEqualTo(951));
      expect(dock.height, greaterThan(dock.width), reason: 'upright');
      expect(dock.top, greaterThan(124), reason: 'under the status');
      expect(dock.bottom, lessThan(669));
      expect(find.text('Library'), findsNothing);
      expect(find.bySemanticsLabel('Library'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<double>(34)),
        findsOneWidget,
        reason: 'the pages reach the bottom of the window',
      );
    });

    testWidgets('lies under the pages where the window has no vertical bar', (
      tester,
    ) async {
      setDuoWindow(tester, pose, DuoWindow.upright);
      await _pump(tester, pose, pages());
      await tester.pump(const Duration(seconds: 1));
      final dock = tester.getRect(find.byKey(const Key('dock')));
      expect(dock.width, greaterThan(dock.height));
      expect(dock.center.dx, closeTo(669 / 2, 1));
      expect(find.text('Library'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<double>(34 + Dock.height + 8)),
        findsOneWidget,
        reason: 'the pages keep clear of the dock',
      );
    });
  });
}
