import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:grlab/src/data/json_file.dart';
import 'package:grlab/src/theme/tokens.dart';

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
      final debugLogging = json['debugLogging'];
      c._debugLogging = debugLogging is bool ? debugLogging : null;
    }
    return c;
  }

  final JsonFile _file;

  /// Named from when the choices were Flutter's `ThemeMode`; its values are
  /// the [AppTheme] names, so a choice saved then still loads.
  static const _themeKey = 'themeMode';

  AppTheme _theme = AppTheme.system;
  AutoDisconnect _autoDisconnect = AutoDisconnect.fiveMinutes;
  ShootMode _shootMode = ShootMode.remote;
  bool? _debugLogging;

  AppTheme get theme => _theme;

  /// Leave the camera's Wi-Fi after this long without use.
  AutoDisconnect get autoDisconnect => _autoDisconnect;

  /// Shoot opens in the mode used last; the first time in Remote, which
  /// needs no Wi-Fi.
  ShootMode get shootMode => _shootMode;

  /// Whether the app keeps debug logs (Settings, "Enable debug logging");
  /// null until the user chooses, so the build's default (on in dev, off in
  /// prod) applies.
  bool? get debugLogging => _debugLogging;

  set theme(AppTheme v) => _update(() => _theme = v);
  set autoDisconnect(AutoDisconnect v) => _update(() => _autoDisconnect = v);
  set shootMode(ShootMode v) => _update(() => _shootMode = v);
  set debugLogging(bool? v) => _update(() => _debugLogging = v);

  /// Applies [change] at once and saves every setting; a failed write goes
  /// to the debug log, and the next change writes every setting again.
  void _update(void Function() change) {
    change();
    notifyListeners();
    final snapshot = {
      _themeKey: _theme.name,
      'autoDisconnect': _autoDisconnect.name,
      'shootMode': _shootMode.name,
      'debugLogging': ?_debugLogging,
    };
    unawaited(_file.save(() => snapshot));
  }

  /// Completes when every change so far is on disk; fails when the latest
  /// write did.
  Future<void> flush() => _file.flush();
}
