import 'package:flutter/widgets.dart';
import 'package:grlab/l10n/app_localizations.dart';

export 'package:grlab/l10n/app_localizations.dart';

/// The app's localized messages (AGENTS.md, "Text the user sees").
extension L10n on BuildContext {
  /// Messages for the locale in effect at this point of the tree.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
