import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import 'package:grphoto/l10n/app_localizations.dart';
import 'package:grphoto/src/data/json_file.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// How long the camera's Wi-Fi stays connected without use before the app
/// leaves it.
enum AutoDisconnect {
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  tenMinutes(Duration(minutes: 10)),
  fifteenMinutes(Duration(minutes: 15)),
  never(null);

  new(this.after);

  /// Null for [never].
  final Duration? after;
}

/// The Shoot tab's two modes (mock `b-remote`, `b-shoot`).
enum ShootMode {
  /// Shutter, self-timer and drive over Bluetooth alone.
  remote,

  /// The camera's picture over its Wi-Fi.
  liveView,
}

/// User settings, persisted as `settings.json` in the app data directory.
final class SettingsController extends ChangeNotifier {
  new _(this._file);

  static Future<SettingsController> load(Directory dataDir) async {
    final c = SettingsController._(
      JsonFile(File('${dataDir.path}/settings.json')),
    );
    final json = await c._file.read();
    if (json != null) {
      c._theme = AppTheme.values.asNameMap()[json[_themeKey]] ?? c._theme;
      c._autoDisconnect =
          AutoDisconnect.values.asNameMap()[json['autoDisconnect']] ??
          c._autoDisconnect;
      c._shootMode =
          ShootMode.values.asNameMap()[json['shootMode']] ?? c._shootMode;
      final connectWhenNearby = json['connectWhenNearby'];
      if (connectWhenNearby is bool) c._connectWhenNearby = connectWhenNearby;
      final backgroundGeotagging = json['backgroundGeotagging'];
      if (backgroundGeotagging is bool) {
        c._backgroundGeotagging = backgroundGeotagging;
      }
      final debugLogging = json['debugLogging'];
      c
        .._debugLogging = debugLogging is bool ? debugLogging : null
        // A language GR Photo is no longer translated into follows the phone.
        .._language = AppLocalizations.supportedLocales
            .where((locale) => locale.toLanguageTag() == json[_languageKey])
            .firstOrNull;
    }
    return c;
  }

  final JsonFile _file;

  /// Named from when the choices were Flutter's `ThemeMode`; its values are
  /// the [AppTheme] names, so a choice saved then still loads.
  static const _themeKey = 'themeMode';

  /// Holds the language's BCP 47 tag (`de`, `zh-Hant`).
  static const _languageKey = 'language';

  AppTheme _theme = AppTheme.system;
  AutoDisconnect _autoDisconnect = AutoDisconnect.fiveMinutes;
  bool _connectWhenNearby = true;
  ShootMode _shootMode = ShootMode.remote;
  bool _backgroundGeotagging = false;
  bool? _debugLogging;
  Locale? _language;

  AppTheme get theme => _theme;

  /// Leave the camera's Wi-Fi after this long without use.
  AutoDisconnect get autoDisconnect => _autoDisconnect;

  /// Connect to the camera used last when the app opens and the Cameras
  /// screen sees it nearby (`CamerasScreen.autoConnect`). Off, the user
  /// connects it: from the camera card, its sheet or its pages.
  bool get connectWhenNearby => _connectWhenNearby;

  /// Shoot opens in the mode used last; the first time in Remote, which
  /// needs no Wi-Fi.
  ShootMode get shootMode => _shootMode;

  /// Background geotagging: the phone keeps a history of where it has been
  /// and GR Photo gives downloaded photos the nearest recorded place
  /// (`GeotagController`). Off until the user turns it on in Settings; it
  /// stays on here when the permission it needs is taken away later, and is
  /// shown as paused then.
  bool get backgroundGeotagging => _backgroundGeotagging;

  /// Whether the app keeps debug logs (Settings, "Enable debug logging");
  /// null until the user chooses, so the build's default (on in dev, off in
  /// prod) applies.
  bool? get debugLogging => _debugLogging;

  /// The language the user chose in Settings, one of
  /// [AppLocalizations.supportedLocales]; null follows the phone's
  /// languages.
  Locale? get language => _language;

  set theme(AppTheme v) => _update(() => _theme = v);
  set autoDisconnect(AutoDisconnect v) => _update(() => _autoDisconnect = v);
  set connectWhenNearby(bool v) => _update(() => _connectWhenNearby = v);
  set shootMode(ShootMode v) => _update(() => _shootMode = v);
  set backgroundGeotagging(bool v) => _update(() => _backgroundGeotagging = v);
  set debugLogging(bool? v) => _update(() => _debugLogging = v);
  set language(Locale? v) => _update(() => _language = v);

  /// Applies [change] at once and saves every setting; a failed write goes
  /// to the debug log, and the next change writes every setting again.
  void _update(void Function() change) {
    change();
    notifyListeners();
    final snapshot = {
      _themeKey: _theme.name,
      'autoDisconnect': _autoDisconnect.name,
      'connectWhenNearby': _connectWhenNearby,
      'shootMode': _shootMode.name,
      'backgroundGeotagging': _backgroundGeotagging,
      'debugLogging': ?_debugLogging,
      _languageKey: ?_language?.toLanguageTag(),
    };
    unawaited(_file.save(() => snapshot));
  }

  /// Completes when every change so far is on disk; fails when the latest
  /// write did.
  Future<void> flush() => _file.flush();
}
