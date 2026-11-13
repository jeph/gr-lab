import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The licenses of what GR Photo ships besides its Dart and Flutter packages,
/// which Flutter lists by itself: the fonts, the sample photos, the map's
/// style with the credits of the map data it is drawn from, and the
/// libraries MapLibre Native brings into the Android app. Each is the names
/// Settings › About › Licenses shows and the bundled file that holds their
/// text.
const _licenseFiles = [
  (['Inter'], 'assets/fonts/Inter-OFL.txt'),
  (['JetBrains Mono'], 'assets/fonts/JetBrainsMono-OFL.txt'),
  (
    ['Gson', 'MapLibre Gestures', 'MapLibre Java', 'OkHttp', 'Okio', 'Timber'],
    'assets/map/android-libraries.txt',
  ),
  (['OpenFreeMap'], 'assets/map/map-credits.txt'),
  (['Unsplash'], 'assets/photo-credits.txt'),
];

/// The entries of [_licenseFiles], for `LicenseRegistry.addLicense`.
Stream<LicenseEntry> bundledLicenses() async* {
  for (final (names, file) in _licenseFiles) {
    yield LicenseEntryWithLineBreaks(names, await rootBundle.loadString(file));
  }
}
