import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/gr_text_field.dart';

Future<TextEditingController> _pump(WidgetTester tester) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: grTheme(GrColors.dark),
      home: Scaffold(body: GrTextField(controller: controller, maxLength: 5)),
    ),
  );
  return controller;
}

void main() {
  testWidgets('the field shows how much of its limit is used and takes no '
      'more', (tester) async {
    final controller = await _pump(tester);
    expect(find.text('0/5'), findsOneWidget);

    await tester.enterText(find.byType(GrTextField), 'abc');
    await tester.pump();
    expect(find.text('3/5'), findsOneWidget);

    await tester.enterText(find.byType(GrTextField), 'abcdefgh');
    await tester.pump();
    expect(controller.text, 'abcde');
    expect(find.text('5/5'), findsOneWidget);
  });

  testWidgets('the count is in characters as the user sees them', (
    tester,
  ) async {
    await _pump(tester);
    // One emoji with a skin tone is four UTF-16 code units.
    await tester.enterText(find.byType(GrTextField), '👍🏽a');
    await tester.pump();
    expect(find.text('2/5'), findsOneWidget);
  });
}
