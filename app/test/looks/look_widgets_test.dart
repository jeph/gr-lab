import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/looks/look_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';

void main() {
  testWidgets('the name dialog answers with the name typed, and is still '
      'built while it leaves, as when the keyboard closes under it', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    String? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: grTheme(GrColors.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                answer = await askLookName(context, initial: 'Standard'),
            child: const Text('ask'),
          ),
        ),
      ),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('looks-name-field')),
      ' Faded Film ',
    );

    await tester.tap(find.byKey(const Key('looks-name-ok')));
    // The answer is in, the dialog is on its way out, and the keyboard
    // closing rebuilds it.
    await tester.pump();
    expect(answer, 'Faded Film');
    expect(find.byKey(const Key('looks-name-field')), findsOneWidget);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('looks-name-field')), findsNothing);
  });
}
