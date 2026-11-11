import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/widgets/scroll_away_header.dart';

const _headerHeight = 50.0;
const _header = Key('header');

/// A page 2000 high under a header [_headerHeight] high, in a window 600
/// high.
Future<ScrollController> _pumpPage(
  WidgetTester tester, {
  ScrollPhysics physics = const ClampingScrollPhysics(),
}) async {
  tester.view
    ..physicalSize = const Size(400, 600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(
        controller: controller,
        physics: physics,
        slivers: const [
          SliverScrollAwayHeader(
            child: SizedBox(key: _header, height: _headerHeight),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 2000)),
        ],
      ),
    ),
  );
  return controller;
}

/// How far the header's top edge is above the window's: 0 with all of it
/// in view, [_headerHeight] or more with none.
double _hidden(WidgetTester tester) =>
    -tester.getTopLeft(find.byKey(_header)).dy;

bool _inView(WidgetTester tester) => find.byKey(_header).evaluate().isNotEmpty;

/// Drags the page by [dy] in one movement and lifts.
Future<void> _drag(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
  await tester.pump();
}

/// Lets a slide that started when the scrolling stopped end.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('leaves with the page as it scrolls down, and comes back over '
      'the page when it scrolls up', (tester) async {
    final page = await _pumpPage(tester);
    expect(_hidden(tester), 0);

    await _drag(tester, -400);
    await _settle(tester);
    expect(_inView(tester), isFalse);
    final scrolledTo = page.offset;
    expect(scrolledTo, greaterThan(300));

    // Most of it shows when the finger lifts: the rest slides in.
    await _drag(tester, 30);
    expect(_hidden(tester), _headerHeight - 30);
    await _settle(tester);
    expect(_hidden(tester), 0);
    expect(page.offset, scrolledTo - 30);

    await _drag(tester, -30);
    expect(_hidden(tester), 30);
    await _settle(tester);
    expect(_inView(tester), isFalse);
  });

  testWidgets('slides back out when less than half of it shows as the '
      'scrolling stops', (tester) async {
    await _pumpPage(tester);
    await _drag(tester, -400);
    await _settle(tester);

    await _drag(tester, 20);
    expect(_hidden(tester), _headerHeight - 20);
    await _settle(tester);
    expect(_inView(tester), isFalse);
  });

  testWidgets('stays away when the finger moves back a little as it lifts '
      'from a scroll down', (tester) async {
    await _pumpPage(tester);
    final finger = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await finger.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(_inView(tester), isFalse);
    await finger.moveBy(const Offset(0, 2));
    await finger.up();
    await tester.pump();
    await _settle(tester);
    expect(_inView(tester), isFalse);
  });

  testWidgets('stays in view when the finger moves back a little as it '
      'lifts from a scroll up', (tester) async {
    await _pumpPage(tester);
    await _drag(tester, -400);
    await _settle(tester);

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await finger.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(_hidden(tester), 0);
    await finger.moveBy(const Offset(0, -2));
    await finger.up();
    await tester.pump();
    await _settle(tester);
    expect(_hidden(tester), 0);
  });

  testWidgets('comes back when the page is flung up', (tester) async {
    final page = await _pumpPage(tester);
    await _drag(tester, -1000);
    await _settle(tester);
    expect(_inView(tester), isFalse);

    // The finger moves less than half the header; the fling does the rest.
    final finger = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    for (var ms = 4; ms <= 16; ms += 4) {
      await finger.moveBy(
        const Offset(0, 5),
        timeStamp: Duration(milliseconds: ms),
      );
    }
    await finger.up(timeStamp: const Duration(milliseconds: 16));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(_hidden(tester), 0);
    expect(page.offset, inExclusiveRange(_headerHeight, 900));
  });

  testWidgets('rests where the page holds it near the start of the page', (
    tester,
  ) async {
    final page = await _pumpPage(tester);
    await _drag(tester, -40);
    expect(page.offset, 40);
    expect(_hidden(tester), 40);
    await _settle(tester);
    expect(_hidden(tester), 40);
  });

  testWidgets('stays away while the page springs back from past its end', (
    tester,
  ) async {
    final page = await _pumpPage(
      tester,
      physics: const BouncingScrollPhysics(),
    );
    page.jumpTo(page.position.maxScrollExtent);
    await tester.pump();
    expect(_inView(tester), isFalse);

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await finger.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(page.offset, greaterThan(page.position.maxScrollExtent));
    await finger.up();
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_inView(tester), isFalse, reason: 'frame $frame');
    }
    expect(page.offset, moreOrLessEquals(page.position.maxScrollExtent));
  });

  testWidgets('moves with a page pulled down past its start', (tester) async {
    await _pumpPage(tester, physics: const BouncingScrollPhysics());
    final finger = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await finger.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(_hidden(tester), lessThan(0));
    await finger.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_hidden(tester), 0);
  });
}
