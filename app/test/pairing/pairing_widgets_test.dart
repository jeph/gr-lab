import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/pairing/pairing_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';

void main() {
  for (final scale in [1.0, 1.3, 2.0, 3.0]) {
    for (final colors in [GrColors.light, GrColors.dark]) {
      testWidgets('camera screen drawings fit at text scale $scale '
          '(${colors.brightness.name})', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: grTheme(colors),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: Column(
                  children: [
                    CameraScreenHero.pairingMenu(),
                    CameraScreenHero.authenticationCode(),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Execute Pairing'), findsOneWidget);
        expect(find.text('OK'), findsOneWidget);
      });
    }
  }

  testWidgets('headline draws <b> parts of the body bold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: grTheme(GrColors.dark),
        home: const Scaffold(
          body: PairingHeadline(
            title: 'Title',
            body: 'Tap <b>Pair</b>, then <b>OK</b>.',
          ),
        ),
      ),
    );
    final body = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'Tap Pair, then OK.',
      ),
    );
    final bold = <String>[];
    body.text.visitChildren((span) {
      if (span case TextSpan(:final text?, :final style?)
          when style.fontWeight == FontWeight.w700) {
        bold.add(text);
      }
      return true;
    });
    expect(bold, ['Pair', 'OK']);
  });
}
