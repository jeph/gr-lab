import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/cameras/cameras_screen.dart';
import 'package:grphoto/src/theme/tokens.dart';

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

  test('the thumb of a switch that is on stands out from its track in every '
      'theme at least as much as in Dark', () {
    double thumbContrast(GrColors colors) {
      final switches = grTheme(colors).switchTheme;
      const on = {WidgetState.selected};
      final thumb = switches.thumbColor!.resolve(on)!.computeLuminance();
      final track = switches.trackColor!.resolve(on)!.computeLuminance();
      return (math.max(thumb, track) + .05) / (math.min(thumb, track) + .05);
    }

    final dark = thumbContrast(GrColors.dark);
    for (final colors in AppTheme.values.map((theme) => theme.colors)) {
      if (colors == null) continue;
      expect(
        thumbContrast(colors),
        greaterThanOrEqualTo(dark),
        reason: '${colors.accent}',
      );
    }
  });
}
