import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/pressable.dart';

const _button = Key('button');

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback? onTap,
  bool reduceMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: grTheme(GrColors.dark),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: Pressable(
            key: _button,
            onTap: onTap,
            child: const SizedBox.square(dimension: 80),
          ),
        ),
      ),
    ),
  ),
);

T _inButton<T extends Widget>(WidgetTester tester) => tester.widget<T>(
  find.descendant(of: find.byKey(_button), matching: find.byType(T)),
);

double _opacity(WidgetTester tester) =>
    _inButton<FadeTransition>(tester).opacity.value;

double _scale(WidgetTester tester) =>
    _inButton<ScaleTransition>(tester).scale.value;

double _highlight(WidgetTester tester) {
  final decoration =
      _inButton<DecoratedBoxTransition>(tester).decoration.value
          as ShapeDecoration;
  return decoration.color!.a;
}

void main() {
  testWidgets('dims, shrinks and highlights while held, then recovers', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);
    expect(_opacity(tester), 1);
    expect(_scale(tester), 1);
    expect(_highlight(tester), 0);

    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_button)),
    );
    await tester.pumpAndSettle();
    expect(_opacity(tester), lessThan(.7));
    expect(_scale(tester), lessThan(1));
    expect(_highlight(tester), greaterThan(0));
    expect(taps, 0);

    await finger.up();
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(_scale(tester), 1);
    expect(_highlight(tester), 0);
    expect(taps, 1);
  });

  testWidgets('a quick tap still dims all the way before recovering', (
    tester,
  ) async {
    await _pump(tester, onTap: () {});
    await tester.tap(find.byKey(_button));
    await tester.pump();
    var dimmest = 1.0;
    for (var i = 0; i < 40 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (_opacity(tester) < dimmest) dimmest = _opacity(tester);
    }
    expect(dimmest, lessThan(.7));
    expect(_opacity(tester), 1);
  });

  testWidgets('does not react when disabled', (tester) async {
    await _pump(tester, onTap: null);
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_button)),
    );
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(_highlight(tester), 0);
    await finger.up();
  });

  testWidgets('recovers when disabled under the finger', (tester) async {
    await _pump(tester, onTap: () {});
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_button)),
    );
    await tester.pumpAndSettle();
    expect(_opacity(tester), lessThan(.7));

    await _pump(tester, onTap: null);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    await finger.up();
  });

  testWidgets('dims without shrinking when the platform reduces motion', (
    tester,
  ) async {
    await _pump(tester, onTap: () {}, reduceMotion: true);
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_button)),
    );
    await tester.pumpAndSettle();
    expect(_opacity(tester), lessThan(.7));
    expect(_scale(tester), 1);
    await finger.up();
    await tester.pumpAndSettle();
  });
}
