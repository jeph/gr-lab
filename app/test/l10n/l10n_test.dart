import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/l10n/l10n.dart';

void main() {
  Locale resolve(List<Locale>? phone) =>
      resolveAppLocale(phone, AppLocalizations.supportedLocales);

  test("the phone's first language that GR Photo is translated into is used, "
      'and English when none is', () {
    expect(resolve(const [Locale('de', 'AT')]), const Locale('de'));
    expect(resolve(const [Locale('pt', 'BR')]), const Locale('pt'));
    expect(resolve(const [Locale('en', 'GB')]), const Locale('en'));
    // Norwegian is not a language of the camera's menus; the phone's
    // second language is.
    expect(
      resolve(const [Locale('nb', 'NO'), Locale('sv', 'SE')]),
      const Locale('sv'),
    );
    expect(resolve(const [Locale('nb', 'NO')]), const Locale('en'));
    expect(
      resolve(const [Locale('ar'), Locale('he', 'IL')]),
      const Locale('en'),
    );
    expect(resolve(const []), const Locale('en'));
    expect(resolve(null), const Locale('en'));
  });

  test('Chinese goes by its script, and by the region when the phone names '
      'no script', () {
    const simplified = Locale('zh');
    const traditional = Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    );
    Locale chinese({String? script, String? region}) => Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: script,
      countryCode: region,
    );

    expect(resolve([chinese()]), simplified);
    expect(resolve([chinese(region: 'CN')]), simplified);
    expect(resolve([chinese(region: 'SG')]), simplified);
    expect(resolve([chinese(script: 'Hans', region: 'CN')]), simplified);
    expect(resolve([chinese(script: 'Hant')]), traditional);
    expect(resolve([chinese(script: 'Hant', region: 'TW')]), traditional);
    for (final region in ['TW', 'HK', 'MO']) {
      expect(resolve([chinese(region: region)]), traditional, reason: region);
    }
    // A script named for a region that usually writes the other one.
    expect(resolve([chinese(script: 'Hans', region: 'HK')]), simplified);
    // The first of two Chinese entries wins, whichever it is.
    expect(
      resolve([
        chinese(script: 'Hans', region: 'CN'),
        chinese(script: 'Hant', region: 'TW'),
      ]),
      simplified,
    );
    expect(
      resolve([chinese(region: 'TW'), chinese(script: 'Hans', region: 'CN')]),
      traditional,
    );
  });

  test('capitals follow the language: Turkish dots the capital of i, Greek '
      'drops the accents', () {
    String upper(String language, String text) =>
        lookupAppLocalizations(Locale(language)).upperCase(text);

    expect(upper('en', 'this camera'), 'THIS CAMERA');
    expect(upper('tr', 'bilgi ışık'), 'BİLGİ IŞIK');
    expect(upper('el', 'Ρυθμίσεις'), 'ΡΥΘΜΙΣΕΙΣ');
    expect(upper('el', 'Μάιος'), 'ΜΑΪΟΣ');
    expect(upper('el', 'άυλος'), 'ΑΫΛΟΣ');
    expect(lookupAppLocalizations(const Locale('th')).capitalSpacing(.8), 0);
    expect(lookupAppLocalizations(const Locale('tr')).capitalSpacing(.8), .8);
  });

  test('every language has its own name for the list in Settings', () {
    final names = AppLocalizations.supportedLocales.map(languageName).toSet();
    expect(names, hasLength(AppLocalizations.supportedLocales.length));
    expect(names, containsAll(['English', 'Deutsch', '日本語']));
  });
}
