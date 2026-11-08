import 'dart:io';

import 'package:flutter/material.dart';

import 'json_file.dart';

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
      c._powerOnWhenConnecting =
          json['powerOnWhenConnecting'] as bool? ?? c._powerOnWhenConnecting;
    }
    return c;
  }

  final JsonFile _file;
  Future<void> _pending = Future.value();

  ThemeMode _themeMode = ThemeMode.system;
  bool _powerOnWhenConnecting = true;

  ThemeMode get themeMode => _themeMode;

  /// Turn the camera on over Bluetooth when it is off and the app connects.
  bool get powerOnWhenConnecting => _powerOnWhenConnecting;

  set themeMode(ThemeMode v) => _update(() => _themeMode = v);
  set powerOnWhenConnecting(bool v) =>
      _update(() => _powerOnWhenConnecting = v);

  void _update(void Function() change) {
    change();
    notifyListeners();
    final snapshot = {
      'themeMode': _themeMode.name,
      'powerOnWhenConnecting': _powerOnWhenConnecting,
    };
    _pending = _pending.then((_) => _file.write(snapshot));
  }

  /// Completes when every change so far is on disk.
  Future<void> flush() => _pending;
}
