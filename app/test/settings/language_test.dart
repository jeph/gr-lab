import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/looks/looks_screen.dart';
import 'package:grlab/src/settings/settings_screen.dart';
import 'package:grlab/src/shoot/shoot_screen.dart';

import '../support/test_app.dart';

void main() {
  testWidgets("GR Lab starts in the phone's language, changes to the one "
      'chosen in Settings and keeps it, and System default returns to the '
      "phone's", (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final phone = tester.platformDispatcher;
    addTearDown(phone.clearLocalesTestValue);
    phone.localesTestValue = const [Locale('fr', 'FR')];
    final french = lookupAppLocalizations(const Locale('fr'));
    final german = lookupAppLocalizations(const Locale('de'));
    final app = (await tester.runAsync(createTestApp))!;
    final settings = app.models.settings;

    Future<Locale?> savedLanguage() async {
      // The write started in fake time, so it finishes by pumping.
      var flushed = false;
      unawaited(settings.flush().whenComplete(() => flushed = true));
      await pumpUntil(tester, () => flushed, reason: 'settings write');
      final reloaded = (await tester.runAsync(
        () => SettingsController.load(app.models.services.dataDir),
      ))!;
      return reloaded.language;
    }

    Future<void> choose(String language) async {
      await tapWhenReady(tester, find.byKey(const Key('setting-language')));
      await tapWhenReady(tester, find.byKey(ValueKey('language:$language')));
      await tester.pumpAndSettle();
    }

    await app.pumpApp(tester);
    // No camera is paired, so the Cameras screen has no Settings button:
    // open Settings the way that button does.
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()))
        .ignore();
    await pumpUntilFound(tester, find.byKey(const Key('setting-language')));
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(title).data, french.settingsTitle);
    expect(find.text(french.settingsLanguageSystem), findsOneWidget);

    await choose('de');
    expect(tester.widget<Text>(title).data, german.settingsTitle);
    // The row names the language as that language does.
    expect(find.text(languageName(const Locale('de'))), findsOneWidget);
    expect(await savedLanguage(), const Locale('de'));

    await choose('system');
    expect(tester.widget<Text>(title).data, french.settingsTitle);
    expect(await savedLanguage(), isNull);

    // A phone that names Chinese by region alone gets that region's script.
    phone.localesTestValue = const [Locale('zh', 'TW')];
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(title).data,
      lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ).settingsTitle,
    );

    await app.dispose();
  });

  testWidgets('the welcome screen, Settings and the list of languages fit a '
      'small phone in every language', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(createTestApp))!;
    final settings = app.models.settings;
    await app.pumpApp(tester);
    await pumpUntilFound(tester, find.byKey(const Key('cameras-welcome')));
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    for (final language in AppLocalizations.supportedLocales) {
      final reason = language.toLanguageTag();
      settings.language = language;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$reason welcome');

      navigator
          .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()))
          .ignore();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$reason Settings');

      await tapWhenReady(tester, find.byKey(const Key('setting-language')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$reason languages');

      navigator.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
    }

    await app.dispose();
  });

  testWidgets("the Cameras screen and the camera's pages fit a narrow phone "
      'in every language', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    final settings = app.models.settings;

    // Every language is tried on every screen, so one run names them all.
    // The test font's glyphs are as wide as they are tall, about twice
    // Inter's, so a text that fits here fits a phone with room to spare.
    final misfits = <String>[];
    Future<void> tryEveryLanguage(String screen) async {
      for (final language in AppLocalizations.supportedLocales) {
        settings.language = language;
        await pumpRounds(tester, 5);
        final error = tester.takeException();
        if (error == null) continue;
        misfits.add('${language.toLanguageTag()} $screen: $error');
      }
    }

    await app.pumpApp(tester);
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-library')));
    await tryEveryLanguage('Cameras');

    await tapWhenReady(tester, find.byKey(const Key('camera-card-library')));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    await tryEveryLanguage('Library');

    await tapWhenReady(tester, find.byKey(const Key('camera-tab-shoot')));
    await pumpUntilFound(tester, find.byType(ShootScreen));
    await tryEveryLanguage('Shoot');

    await tapWhenReady(tester, find.byKey(const Key('camera-tab-looks')));
    await pumpUntilFound(tester, find.byType(LooksScreen));
    await tryEveryLanguage('Looks');
    expect(misfits, isEmpty);

    await app.dispose();
  });
}
