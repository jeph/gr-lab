import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/data/json_file.dart';

/// A paired camera as the app keeps it.
@immutable
final class SavedCamera {
  const new({
    required this.paired,
    required this.name,
    required this.pairedAt,
    this.wifiApproved = false,
  });

  factory fromJson(Map<String, Object?> json) => SavedCamera(
    paired: GrPairedCamera.fromJson(json['paired']! as Map<String, Object?>),
    name: json['name']! as String,
    pairedAt: DateTime.parse(json['pairedAt']! as String),
    wifiApproved: json['wifiApproved'] == true,
  );

  final GrPairedCamera paired;

  /// Shown in the camera pill; defaults to the model without "RICOH".
  final String name;
  final DateTime pairedAt;

  /// The phone has joined this camera's Wi-Fi through GR Lab, so the OS
  /// approval is in place and joins need no explanation first.
  final bool wifiApproved;

  String get serial => paired.serialNumber;

  /// Model without "RICOH", from [props] when connected.
  String? model([GrProps? props]) =>
      stripRicohPrefix(props?.model)?.nonEmpty ??
      stripRicohPrefix(paired.modelName)?.nonEmpty;

  /// Default display name for a newly paired camera.
  static String defaultName(GrPairedCamera paired) =>
      stripRicohPrefix(paired.modelName)?.nonEmpty ?? 'GR camera';

  SavedCamera copyWith({String? name, bool? wifiApproved}) => SavedCamera(
    paired: paired,
    name: name ?? this.name,
    pairedAt: pairedAt,
    wifiApproved: wifiApproved ?? this.wifiApproved,
  );

  Map<String, Object?> toJson() => {
    'paired': paired.toJson(),
    'name': name,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    if (wifiApproved) 'wifiApproved': true,
  };
}

extension on String {
  String? get nonEmpty => isEmpty ? null : this;
}

/// Paired cameras, the one used last first, persisted as `cameras.json`.
/// The first one is the camera the app connects to.
final class CameraStore extends ChangeNotifier {
  new _(this._file);

  static Future<CameraStore> load(Directory dataDir) async {
    final s = CameraStore._(JsonFile(File('${dataDir.path}/cameras.json')));
    final json = await s._file.read();
    final list = json?['cameras'];
    if (list is List<Object?>) {
      for (final e in list) {
        if (e is! Map<String, Object?>) continue;
        try {
          s._cameras.add(SavedCamera.fromJson(e));
        } on Object {
          // Skip entries written by an incompatible build.
        }
      }
    }
    return s;
  }

  final JsonFile _file;
  final List<SavedCamera> _cameras = [];

  List<SavedCamera> get cameras => List.unmodifiable(_cameras);
  SavedCamera? get current => _cameras.isEmpty ? null : _cameras.first;

  /// Adds [camera], replacing any entry with the same serial number (a
  /// re-pairing gives the camera a new bond and possibly a new device id).
  Future<void> add(SavedCamera camera) {
    _cameras
      ..removeWhere((c) => c.serial == camera.serial)
      ..insert(0, camera);
    return _save();
  }

  /// Makes [serial] the current camera by moving it to the front.
  Future<void> select(String serial) {
    final i = _cameras.indexWhere((c) => c.serial == serial);
    if (i <= 0) return Future.value();
    _cameras.insert(0, _cameras.removeAt(i));
    return _save();
  }

  Future<void> rename(String serial, String name) {
    final i = _cameras.indexWhere((c) => c.serial == serial);
    if (i < 0) return Future.value();
    _cameras[i] = _cameras[i].copyWith(name: name);
    return _save();
  }

  Future<void> markWifiApproved(String serial) {
    final i = _cameras.indexWhere((c) => c.serial == serial);
    if (i < 0 || _cameras[i].wifiApproved) return Future.value();
    _cameras[i] = _cameras[i].copyWith(wifiApproved: true);
    return _save();
  }

  Future<void> remove(String serial) {
    _cameras.removeWhere((c) => c.serial == serial);
    return _save();
  }

  /// Saves every camera after the writes already queued. The returned
  /// future fails when this write does (the failure also goes to the debug
  /// log); the next change writes every camera again.
  Future<void> _save() {
    notifyListeners();
    final snapshot = {
      'cameras': [for (final c in _cameras) c.toJson()],
    };
    return _file.save(() => snapshot);
  }
}
