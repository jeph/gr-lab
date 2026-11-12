import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/settings/privacy_policy_screen.dart';
import 'package:grphoto/src/settings/settings_screen.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('Settings › About › Privacy policy shows the bundled policy', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(createTestApp))!;
    await app.pumpWithin(tester, const SettingsScreen());

    final row = find.byKey(const Key('setting-privacy-policy'));
    await tester.scrollUntilVisible(row, 200);
    expect(find.text('Privacy policy'), findsOneWidget);
    await tester.tap(row);
    await pumpUntilFound(tester, find.text('GR Photo privacy policy'));
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    // The screen's title, and the policy's headings and dated first lines.
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.textContaining('Last updated: '), findsOneWidget);
    final debugLog = find.text('The debug log');
    await tester.scrollUntilVisible(
      debugLog,
      300,
      scrollable: find
          .descendant(
            of: find.byType(PrivacyPolicyScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(debugLog, findsOneWidget);

    await app.dispose();
  });
}
