import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/settings/settings_screen.dart';

import '../support/test_app.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('settings change and persist on a phone screen '
        '(${brightness.name})', (tester) async {
      tester.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final app = (await tester.runAsync(createTestApp))!;
      final settings = app.models.settings;
      await app.pumpWithin(
        tester,
        const SettingsScreen(),
        brightness: brightness,
      );

      await tester.tap(find.byKey(const ValueKey('theme:dark')));
      await tester.pump();
      expect(settings.themeMode, ThemeMode.dark);

      final powerOn = settings.powerOnWhenConnecting;
      await tester.tap(find.byKey(const ValueKey('setting-power-on')));
      await tester.pump();
      expect(settings.powerOnWhenConnecting, !powerOn);

      expect(find.text('Licenses'), findsOneWidget);

      // The writes started in fake time, so they finish by pumping, not
      // inside runAsync.
      var flushed = false;
      unawaited(settings.flush().whenComplete(() => flushed = true));
      await pumpUntil(tester, () => flushed, reason: 'settings write');
      final reloaded = (await tester.runAsync(
        () => SettingsController.load(app.models.services.dataDir),
      ))!;
      expect(reloaded.themeMode, ThemeMode.dark);
      expect(reloaded.powerOnWhenConnecting, !powerOn);

      await app.dispose();
    });
  }
}
