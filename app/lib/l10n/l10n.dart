import 'package:flutter/widgets.dart';
import 'package:grphoto/l10n/app_localizations.dart';

export 'package:grphoto/l10n/app_localizations.dart';

/// The app's localized messages (AGENTS.md, "Text the user sees").
extension L10n on BuildContext {
  /// Messages for the locale in effect at this point of the tree.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The language GR Photo is shown in while the user has not chosen one in
/// Settings: the first of the phone's languages ([preferred], the most
/// wanted first) that GR Photo is translated into. When none is, the first
/// of [supported], which `l10n.yaml` keeps English.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) =>
    basicLocaleListResolution(
      preferred?.map(_asTranslated).toList(),
      supported,
    );

/// Chinese under the locale of its translation: `zh` is Simplified and
/// `zh_Hant` Traditional. A phone names the script (`zh-Hans-CN`), which
/// `zh` alone would match only loosely, behind a later Traditional entry,
/// or just the region (`zh-TW`), which tells the script by where it is
/// written. Other languages pass through.
Locale _asTranslated(Locale locale) {
  if (locale.languageCode != 'zh') return locale;
  const traditionalRegions = {'TW', 'HK', 'MO'};
  final traditional =
      locale.scriptCode == 'Hant' ||
      (locale.scriptCode == null &&
          traditionalRegions.contains(locale.countryCode));
  return traditional
      ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
      : const Locale('zh');
}

/// [locale]'s language under its own name (`Deutsch`, `日本語`), as a list
/// of languages shows it whatever language the app is in.
String languageName(Locale locale) =>
    lookupAppLocalizations(locale).settingsLanguageName;

/// Capitals for the labels the design sets in capitals.
extension L10nCapitals on AppLocalizations {
  /// [text] in capitals as this language writes them. Dart's `toUpperCase`
  /// applies one rule to every language, which is wrong for Turkish (the
  /// capital of `i` is `İ`) and Greek (capitals carry no accent, and a
  /// vowel that loses its accent before `ι` or `υ` passes a diaeresis on
  /// to it: `Μάιος` is `ΜΑΪΟΣ`).
  String upperCase(String text) => switch (localeName) {
    'tr' => text.replaceAll('i', 'İ').toUpperCase(),
    'el' =>
      text
          .replaceAllMapped(
            _greekAccentBeforeIotaOrUpsilon,
            (m) => '${m[1]}${m[2] == 'ι' ? 'ϊ' : 'ϋ'}',
          )
          .toUpperCase()
          .replaceAllMapped(
            _greekAccentedCapital,
            (m) => _greekPlainCapitals[m[0]]!,
          ),
    _ => text.toUpperCase(),
  };

  /// [spacing] for the letters of a label set in capitals, or none in
  /// Thai, which has no capitals and whose vowel and tone marks the
  /// spacing sets apart from the letter after them (seen on Android 16,
  /// 2026-11-10).
  double capitalSpacing(double spacing) => localeName == 'th' ? 0 : spacing;
}

final _greekAccentBeforeIotaOrUpsilon = RegExp('([άέήόώ])([ιυ])');
final _greekAccentedCapital = RegExp('[ΆΈΉΊΌΎΏ]');
const _greekPlainCapitals = {
  'Ά': 'Α',
  'Έ': 'Ε',
  'Ή': 'Η',
  'Ί': 'Ι',
  'Ό': 'Ο',
  'Ύ': 'Υ',
  'Ώ': 'Ω',
};
