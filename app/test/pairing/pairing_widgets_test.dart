import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';

void main() {
  for (final scale in [1.0, 1.3, 2.0, 3.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'camera screen drawings fit at text scale $scale (${brightness.name})',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: grTheme(brightness),
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
        },
      );
    }
  }
}
