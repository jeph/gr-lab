import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The licenses of what GR Lab ships besides its Dart and Flutter packages,
/// which Flutter lists by itself: the fonts and the sample photos. Each is
/// the name Settings › About › Licenses shows and the bundled file that
/// holds the text.
const _licenseFiles = [
  ('Inter', 'assets/fonts/Inter-OFL.txt'),
  ('JetBrains Mono', 'assets/fonts/JetBrainsMono-OFL.txt'),
  ('Unsplash', 'assets/photo-credits.txt'),
];

/// The entries of [_licenseFiles], for `LicenseRegistry.addLicense`.
Stream<LicenseEntry> bundledLicenses() async* {
  for (final (name, file) in _licenseFiles) {
    yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString(file));
  }
}
