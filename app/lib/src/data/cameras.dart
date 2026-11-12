import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grphoto/src/data/json_file.dart';

/// A paired camera as the app keeps it.
@immutable
final class SavedCamera {
  const new({
    required this.paired,
    required this.name,
    required this.pairedAt,
    this.wifiApproved = false,
    this.liveGeotagging,
    this.syncTime = true,
  });

  factory fromJson(Map<String, Object?> json) => SavedCamera(
    paired: GrPairedCamera.fromJson(json['paired']! as Map<String, Object?>),
    name: json['name']! as String,
    pairedAt: DateTime.parse(json['pairedAt']! as String),
    wifiApproved: json['wifiApproved'] == true,
    liveGeotagging: switch (json['liveGeotagging']) {
      final bool on => on,
      _ => null,
    },
    syncTime: json['syncTime'] != false,
  );

  final GrPairedCamera paired;

  /// Shown in the camera pill; defaults to the model without "RICOH".
  final String name;
  final DateTime pairedAt;

  /// The phone has joined this camera's Wi-Fi through GR Photo, so the OS
  /// approval is in place and joins need no explanation first.
  final bool wifiApproved;

  /// Sending the phone's location to this camera while it is on. Null
  /// until the user has been asked: it is offered once, the first time the
  /// camera is linked, and is on from then if the phone's location is
  /// allowed.
  final bool? liveGeotagging;

  /// Keeping this camera's clock on the phone's time. On unless the user
  /// turned it off; live geotagging keeps the clock in step either way.
  final bool syncTime;

  String get serial => paired.serialNumber;

  /// The model name to show: without "RICOH", as the camera reported it at
  /// pairing. The identity check over Wi-Fi refuses a camera whose
  /// `/v1/props` model differs, so this is the connected camera's model too.
  String? get modelName => _modelOf(paired);

  /// The camera's model and firmware as last recorded, for what it
  /// supports ([CameraFeature]).
  CameraBody get body =>
      CameraBody(model: paired.model, firmware: paired.firmwareRevision);

  /// Firmware version as the camera last reported it over Bluetooth.
  String? get firmware => paired.firmwareRevision;

  /// Default display name for a newly paired camera.
  static String defaultName(GrPairedCamera paired) =>
      _modelOf(paired) ?? 'GR camera';

  static String? _modelOf(GrPairedCamera paired) =>
      stripRicohPrefix(paired.modelName)?.nonEmpty;

  SavedCamera copyWith({
    String? name,
    bool? wifiApproved,
    GrPairedCamera? paired,
    bool? liveGeotagging,
    bool? syncTime,
  }) => SavedCamera(
    paired: paired ?? this.paired,
    name: name ?? this.name,
    pairedAt: pairedAt,
    wifiApproved: wifiApproved ?? this.wifiApproved,
    liveGeotagging: liveGeotagging ?? this.liveGeotagging,
    syncTime: syncTime ?? this.syncTime,
  );

  Map<String, Object?> toJson() => {
    'paired': paired.toJson(),
    'name': name,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    if (wifiApproved) 'wifiApproved': true,
    'liveGeotagging': ?liveGeotagging,
    if (!syncTime) 'syncTime': false,
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

  /// Records the user's choice about sending the phone's location to
  /// [serial].
  Future<void> setLiveGeotagging(String serial, {required bool on}) {
    final i = _cameras.indexWhere((c) => c.serial == serial);
    if (i < 0 || _cameras[i].liveGeotagging == on) return Future.value();
    _cameras[i] = _cameras[i].copyWith(liveGeotagging: on);
    return _save();
  }

  /// Records whether [serial]'s clock is kept on the phone's time.
  Future<void> setSyncTime(String serial, {required bool on}) {
    final i = _cameras.indexWhere((c) => c.serial == serial);
    if (i < 0 || _cameras[i].syncTime == on) return Future.value();
    _cameras[i] = _cameras[i].copyWith(syncTime: on);
    return _save();
  }

  /// Keeps [serial]'s firmware version as the camera reported it on
  /// linking, so a firmware update shows everywhere the camera's
  /// identity does.
  Future<void> recordFirmware(String serial, String firmware) {
    final i = _cameras.indexWhere((c) => c.serial == serial);
    if (i < 0 || _cameras[i].firmware == firmware) return Future.value();
    _cameras[i] = _cameras[i].copyWith(
      paired: _cameras[i].paired.withFirmwareRevision(firmware),
    );
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
