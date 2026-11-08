import 'dart:io';

import 'package:flutter/material.dart';

import 'json_file.dart';

/// How long the camera's Wi-Fi stays connected without use before the app
/// leaves it.
enum AutoDisconnect {
  oneMinute(Duration(minutes: 1), '1 min'),
  fiveMinutes(Duration(minutes: 5), '5 min'),
  tenMinutes(Duration(minutes: 10), '10 min'),
  fifteenMinutes(Duration(minutes: 15), '15 min'),
  never(null, 'Never');

  const AutoDisconnect(this.after, this.label);

  /// Null for [never].
  final Duration? after;
  final String label;
}

/// User settings, persisted as `settings.json` in the app data directory.
final class SettingsController extends ChangeNotifier {
  SettingsController._(this._file);

  static Future<SettingsController> load(Directory dataDir) async {
    final c = SettingsController._(
      JsonFile(File('${dataDir.path}/settings.json')),
    );
    final json = await c._file.read();
    if (json != null) {
      c._themeMode =
          ThemeMode.values.asNameMap()[json['themeMode']] ?? c._themeMode;
      c._autoDisconnect =
          AutoDisconnect.values.asNameMap()[json['autoDisconnect']] ??
          c._autoDisconnect;
    }
    return c;
  }

  final JsonFile _file;
  Future<void> _pending = Future.value();

  ThemeMode _themeMode = ThemeMode.system;
  AutoDisconnect _autoDisconnect = AutoDisconnect.fiveMinutes;

  ThemeMode get themeMode => _themeMode;

  /// Leave the camera's Wi-Fi after this long without use.
  AutoDisconnect get autoDisconnect => _autoDisconnect;

  set themeMode(ThemeMode v) => _update(() => _themeMode = v);
  set autoDisconnect(AutoDisconnect v) => _update(() => _autoDisconnect = v);

  void _update(void Function() change) {
    change();
    notifyListeners();
    final snapshot = {
      'themeMode': _themeMode.name,
      'autoDisconnect': _autoDisconnect.name,
    };
    _pending = _pending.then((_) => _file.write(snapshot));
  }

  /// Completes when every change so far is on disk.
  Future<void> flush() => _pending;
}
