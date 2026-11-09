import 'dart:io';

import 'package:flutter/material.dart';

import 'package:grlab/src/data/json_file.dart';

/// How long the camera's Wi-Fi stays connected without use before the app
/// leaves it.
enum AutoDisconnect {
  oneMinute(Duration(minutes: 1), '1 min'),
  fiveMinutes(Duration(minutes: 5), '5 min'),
  tenMinutes(Duration(minutes: 10), '10 min'),
  fifteenMinutes(Duration(minutes: 15), '15 min'),
  never(null, 'Never');

  new(this.after, this.label);

  /// Null for [never].
  final Duration? after;
  final String label;
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
      c._themeMode =
          ThemeMode.values.asNameMap()[json['themeMode']] ?? c._themeMode;
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
  Future<void> _pending = Future.value();

  ThemeMode _themeMode = ThemeMode.system;
  AutoDisconnect _autoDisconnect = AutoDisconnect.fiveMinutes;
  ShootMode _shootMode = ShootMode.remote;
  bool? _debugLogging;

  ThemeMode get themeMode => _themeMode;

  /// Leave the camera's Wi-Fi after this long without use.
  AutoDisconnect get autoDisconnect => _autoDisconnect;

  /// Shoot opens in the mode used last; the first time in Remote, which
  /// needs no Wi-Fi.
  ShootMode get shootMode => _shootMode;

  /// Whether the app keeps debug logs (Settings, "Enable debug logging");
  /// null until the user chooses, so the build's default (on in dev, off in
  /// prod) applies.
  bool? get debugLogging => _debugLogging;

  set themeMode(ThemeMode v) => _update(() => _themeMode = v);
  set autoDisconnect(AutoDisconnect v) => _update(() => _autoDisconnect = v);
  set shootMode(ShootMode v) => _update(() => _shootMode = v);
  set debugLogging(bool? v) => _update(() => _debugLogging = v);

  void _update(void Function() change) {
    change();
    notifyListeners();
    final snapshot = {
      'themeMode': _themeMode.name,
      'autoDisconnect': _autoDisconnect.name,
      'shootMode': _shootMode.name,
      'debugLogging': ?_debugLogging,
    };
    _pending = _pending.then((_) => _file.write(snapshot));
  }

  /// Completes when every change so far is on disk.
  Future<void> flush() => _pending;
}
