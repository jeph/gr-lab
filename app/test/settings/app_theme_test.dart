import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/cameras/cameras_screen.dart';
import 'package:grlab/src/theme/tokens.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('Auto follows the phone between Light and Dark; every other '
      'theme keeps its colours whatever the phone is set to', (tester) async {
    final phone = tester.platformDispatcher;
    addTearDown(phone.clearPlatformBrightnessTestValue);
    final app = (await tester.runAsync(createTestApp))!;
    final settings = app.models.settings;
    await app.pumpApp(tester);
    await pumpUntilFound(tester, find.byType(CamerasScreen));

    Future<GrColors> shown() async {
      // A change of theme is animated.
      await tester.pump();
      await tester.pump(kThemeAnimationDuration);
      return GrColors.of(tester.element(find.byType(CamerasScreen)));
    }

    for (final brightness in Brightness.values) {
      phone.platformBrightnessTestValue = brightness;
      for (final theme in AppTheme.values) {
        settings.theme = theme;
        final expected =
            theme.colors ??
            (brightness == Brightness.dark ? GrColors.dark : GrColors.light);
        expect(
          await shown(),
          expected,
          reason: '${theme.name} on a ${brightness.name} phone',
        );
      }
    }

    await app.dispose();
  });
}
