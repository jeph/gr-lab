import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

void main() {
  testWidgets("a pressed row's ink draws on its card, not under it", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: grTheme(GrColors.dark),
        home: Scaffold(
          body: GroupBox(
            children: [GroupRow(title: 'Row', onTap: () {})],
          ),
        ),
      ),
    );
    // The ink of a row is painted by the nearest Material above it. One
    // outside the card would paint it beneath the card's background, where
    // it cannot be seen.
    final ink = Material.of(tester.element(find.text('Row'))) as RenderObject;
    final card = tester.renderObject(find.byType(GroupBox));
    var inCard = false;
    for (RenderObject? o = ink; o != null; o = o.parent) {
      if (o == card) inCard = true;
    }
    expect(inCard, isTrue);
  });
}
