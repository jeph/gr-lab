import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';
import 'package:grphoto/src/widgets/gr_text_field.dart';

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

  testWidgets('a text dialog above the keyboard of a phone on its side '
      'keeps the field being typed in and the buttons in reach', (
    tester,
  ) async {
    // 193 pt are left above the keyboard, less than the card's own height.
    tester.view.physicalSize = const Size(812, 393);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.reset);
    final name = TextEditingController(text: 'Faded Film');
    addTearDown(name.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: grTheme(GrColors.dark),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => GrDialog(
                title: 'Name the look',
                content: GrTextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 32,
                ),
                actions: [
                  GrDialogAction(key: _no, label: 'Cancel', onPressed: () {}),
                  GrDialogAction.answer(
                    key: _yes,
                    label: 'Save',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    const aboveKeyboard = 393 - 200;
    final save = tester.getRect(find.byKey(_yes));
    expect(save.bottom, lessThan(aboveKeyboard));
    expect(find.byKey(_yes).hitTestable(), findsOneWidget);
    // The field has scrolled into what is left above the buttons.
    final shown = tester.getRect(find.byType(SingleChildScrollView));
    final field = tester.getRect(find.byType(GrTextField));
    expect(shown.top, greaterThan(0));
    expect(field.top, greaterThanOrEqualTo(shown.top));
    expect(field.bottom, lessThanOrEqualTo(shown.bottom));
    expect(shown.bottom, lessThanOrEqualTo(save.top));
  });
}
