import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/toast.dart';

const _page = Key('page');
const _toast = Key('toast');
const _screen = Size(393, 812);

/// The system's bar along the bottom edge of the screen.
const _systemBar = 24.0;

/// Pumps [home] under a [ToastHost] on a phone-sized screen.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  GrColors colors = GrColors.light,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: _systemBar);
  tester.view.viewPadding = const FakeViewPadding(bottom: _systemBar);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: grTheme(colors),
      builder: (context, child) => ToastHost(child: child!),
      home: home,
    ),
  );
}

/// The toasts as the screen with [key] shows them.
Toasts _toasts(WidgetTester tester, [Key key = _page]) =>
    Toasts.of(tester.element(find.byKey(key)));

void main() {
  testWidgets('a toast that something worked leaves sooner than one that it '
      'failed', (tester) async {
    await _pump(tester, const Scaffold(key: _page));

    _toasts(tester).done('Saved');
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byKey(const Key('toast-done')), findsOneWidget);
    await tester.pump(ToastHost.doneStay);
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);

    _toasts(tester).failed('Not saved');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('toast-failed')), findsOneWidget);
    await tester.pump(ToastHost.doneStay);
    await tester.pumpAndSettle();
    expect(find.text('Not saved'), findsOneWidget);
    await tester.pump(ToastHost.failedStay - ToastHost.doneStay);
    await tester.pumpAndSettle();
    expect(find.text('Not saved'), findsNothing);
  });

  testWidgets('floats where the dock would be on a screen with nothing at '
      'its bottom edge', (tester) async {
    await _pump(tester, const Scaffold(key: _page));

    _toasts(tester).done('Saved');
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(_toast)).bottom,
      _screen.height - _systemBar - 12,
    );
  });

  testWidgets('floats above what the screen in front keeps at its bottom '
      'edge', (tester) async {
    const bar = Key('bar');
    await _pump(
      tester,
      const Scaffold(
        key: _page,
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: ToastFloor(child: SizedBox(key: bar, height: 56)),
            ),
            // On a page of a dock that is not the chosen one.
            Positioned(
              left: 0,
              right: 0,
              bottom: 300,
              child: TickerMode(
                enabled: false,
                child: ToastFloor(child: SizedBox(height: 56)),
              ),
            ),
            // A bar with nothing to show.
            Positioned(
              bottom: 500,
              child: ToastFloor(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );

    _toasts(tester).done('Saved');
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(_toast)).bottom,
      tester.getRect(find.byKey(bar)).top - 8,
    );
  });

  testWidgets('follows what it floats above when that moves', (tester) async {
    const bar = Key('bar');
    // As far above the bottom edge as a keyboard that then closes.
    final raised = ValueNotifier<double>(300);
    addTearDown(raised.dispose);
    await _pump(
      tester,
      Scaffold(
        key: _page,
        body: ValueListenableBuilder(
          valueListenable: raised,
          builder: (context, bottom, _) => Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: bottom,
                child: const ToastFloor(child: SizedBox(key: bar, height: 56)),
              ),
            ],
          ),
        ),
      ),
    );
    _toasts(tester).done('Saved');
    await tester.pumpAndSettle();

    raised.value = 40;
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(_toast)).bottom,
      tester.getRect(find.byKey(bar)).top - 8,
    );
  });

  testWidgets('a second toast takes the place of the first and stays its '
      'own time', (tester) async {
    await _pump(tester, const Scaffold(key: _page));

    _toasts(tester).failed('First');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    _toasts(tester).done('Second');
    await tester.pumpAndSettle();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.byKey(_toast), findsOneWidget);

    // Past the time the first would have left at.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('a tap or a swipe down sends it away', (tester) async {
    await _pump(tester, const Scaffold(key: _page));

    _toasts(tester).failed('Not saved');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not saved'));
    await tester.pumpAndSettle();
    expect(find.text('Not saved'), findsNothing);

    _toasts(tester).failed('Not saved');
    await tester.pumpAndSettle();
    await tester.drag(find.text('Not saved'), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.text('Not saved'), findsNothing);

    // It comes back for the next message.
    _toasts(tester).done('Saved');
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a screen that has closed still gets its toast', (tester) async {
    const other = Key('other');
    await _pump(tester, const Scaffold(key: _page));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final closed = navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(key: other)),
    );
    await tester.pumpAndSettle();
    final toasts = _toasts(tester, other);

    navigator.pop();
    await closed;
    await tester.pumpAndSettle();
    toasts.done('Saved');
    await tester.pumpAndSettle();

    expect(find.byKey(other), findsNothing);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('wears the colours of the screen that shows it', (tester) async {
    // Live view keeps a dark theme under a light app.
    await _pump(
      tester,
      Theme(
        data: grTheme(GrColors.dark),
        child: const Scaffold(key: _page),
      ),
    );

    _toasts(tester).done('Saved');
    await tester.pumpAndSettle();

    final capsule = tester.widget<Container>(find.byKey(_toast));
    expect((capsule.decoration! as BoxDecoration).color, GrColors.dark.float);
  });
}
