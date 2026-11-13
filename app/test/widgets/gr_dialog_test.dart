import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';

const _no = Key('no');
const _yes = Key('yes');

/// Pumps a dialog with the buttons [no] and [yes] on a phone-sized screen.
/// The test font draws every character as wide as the font size, so a
/// label's width is its length times 15.
Future<void> _pump(
  WidgetTester tester, {
  required String no,
  required String yes,
  String? message,
  Size screen = const Size(393, 812),
  double textScale = 1,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: grTheme(GrColors.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: GrDialog(
          title: 'Title',
          message: message,
          actions: [
            GrDialogAction(key: _no, label: no, onPressed: () {}),
            GrDialogAction.answer(key: _yes, label: yes, onPressed: () {}),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('labels that fit share the row equally, the answer trailing', (
    tester,
  ) async {
    await _pump(tester, no: 'Cancel', yes: 'Save');

    final no = tester.getRect(find.byKey(_no));
    final yes = tester.getRect(find.byKey(_yes));
    expect(no.top, yes.top);
    expect(no.width, yes.width);
    expect(no.right, lessThan(yes.left));
  });

  testWidgets('a label wider than its share of the row stacks the buttons, '
      'the answer on top', (tester) async {
    await _pump(tester, no: 'Cancel', yes: 'Load into C1');

    final no = tester.getRect(find.byKey(_no));
    final yes = tester.getRect(find.byKey(_yes));
    expect(yes.bottom, lessThan(no.top));
    expect(yes.left, no.left);
    expect(yes.width, no.width);
    // Each has the whole row: the screen less the dialog's margin and
    // padding.
    expect(yes.width, 393 - 2 * 16 - 2 * 20);
  });

  testWidgets('labels that fit stack once the phone enlarges its text', (
    tester,
  ) async {
    await _pump(tester, no: 'Cancel', yes: 'Delete', textScale: 1.5);

    final no = tester.getRect(find.byKey(_no));
    final yes = tester.getRect(find.byKey(_yes));
    expect(yes.bottom, lessThan(no.top));
  });

  testWidgets('a message too long for the screen scrolls, and the buttons '
      'stay on it', (tester) async {
    const screen = Size(393, 420);
    await _pump(
      tester,
      no: 'Cancel',
      yes: 'Save',
      message: 'word ' * 400,
      screen: screen,
    );

    expect(tester.takeException(), isNull);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.getRect(find.byKey(_yes)).bottom, lessThan(screen.height));
    expect(tester.getRect(find.text('Title')).top, greaterThan(0));
  });
}
