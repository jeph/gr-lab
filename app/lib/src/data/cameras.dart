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
    this.liveGeotagging = false,
    this.backgroundGeotagging = false,
    this.syncClock = true,
    this.storeLocationInfoPending,
  });

  /// Reads what [toJson] writes. The geotagging fields are missing from
  /// files written before GR Photo had geotagging, and take their defaults
  /// then.
  factory fromJson(Map<String, Object?> json) {
    final pending = json['storeLocationInfoPending'];
    return SavedCamera(
      paired: GrPairedCamera.fromJson(json['paired']! as Map<String, Object?>),
      name: json['name']! as String,
      pairedAt: DateTime.parse(json['pairedAt']! as String),
      wifiApproved: json['wifiApproved'] == true,
      liveGeotagging: json['liveGeotagging'] == true,
      backgroundGeotagging: json['backgroundGeotagging'] == true,
      syncClock: json['syncClock'] != false,
      storeLocationInfoPending: pending is bool ? pending : null,
    );
  }

  final GrPairedCamera paired;

  /// Shown in the camera pill; defaults to the model without "RICOH".
  final String name;
  final DateTime pairedAt;

  /// The phone has joined this camera's Wi-Fi through GR Photo, so the OS
  /// approval is in place and joins need no explanation first.
  final bool wifiApproved;

  /// Live geotagging is on for this camera: while it is on and linked, the
  /// phone's location is sent to it. Off until the user flips the switch
  /// on the camera's card.
  final bool liveGeotagging;

  /// Background geotagging is on for this camera: the photos downloaded
  /// from it get the nearest place of the phone's location history. Off
  /// until the user flips the switch in the camera's details; it stays on
  /// when the permission it needs is taken away later, and is shown as
  /// paused then.
  final bool backgroundGeotagging;

  /// Keep the camera's clock on the phone's time, as the user chose it.
  /// [keepsClock] is what GR Photo does.
  final bool syncClock;

  /// Whether GR Photo keeps the camera's clock on the phone's time: the
  /// user's choice ([syncClock]), and always with [backgroundGeotagging],
  /// which matches a photo to the history by the time the camera wrote
  /// into it.
  bool get keepsClock => syncClock || backgroundGeotagging;

  /// The value of the camera's Store Location Info that GR Photo still has
  /// to write, because the switch was flipped while the camera was off or
  /// away; null when nothing is waiting.
  final bool? storeLocationInfoPending;

  /// Whether this camera can be sent a location at all
  /// ([CameraFeature.geotagging]), by its model and firmware as last
  /// recorded.
  bool get supportsGeotagging => body.supports(CameraFeature.geotagging);

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

  /// This camera with the given fields replaced. [storeLocationInfoPending]
  /// is a function so that it can set the value to null.
  SavedCamera copyWith({
    String? name,
    bool? wifiApproved,
    GrPairedCamera? paired,
    bool? liveGeotagging,
    bool? backgroundGeotagging,
    bool? syncClock,
    bool? Function()? storeLocationInfoPending,
  }) => SavedCamera(
    paired: paired ?? this.paired,
    name: name ?? this.name,
    pairedAt: pairedAt,
    wifiApproved: wifiApproved ?? this.wifiApproved,
    liveGeotagging: liveGeotagging ?? this.liveGeotagging,
    backgroundGeotagging: backgroundGeotagging ?? this.backgroundGeotagging,
    syncClock: syncClock ?? this.syncClock,
    storeLocationInfoPending: storeLocationInfoPending == null
        ? this.storeLocationInfoPending
        : storeLocationInfoPending(),
  );

  Map<String, Object?> toJson() => {
    'paired': paired.toJson(),
    'name': name,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    if (wifiApproved) 'wifiApproved': true,
    if (liveGeotagging) 'liveGeotagging': true,
    if (backgroundGeotagging) 'backgroundGeotagging': true,
    if (!syncClock) 'syncClock': false,
    'storeLocationInfoPending': ?storeLocationInfoPending,
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

  /// Turns live geotagging on or off for [serial]. Either way the camera's
  /// Store Location Info is to follow
  /// ([SavedCamera.storeLocationInfoPending]).
  Future<void> setLiveGeotagging(String serial, {required bool on}) => _change(
    serial,
    (camera) =>
        camera.copyWith(liveGeotagging: on, storeLocationInfoPending: () => on),
  );

  /// Turns background geotagging on or off for [serial].
  Future<void> setBackgroundGeotagging(String serial, {required bool on}) =>
      _change(
        serial,
        (camera) => camera.backgroundGeotagging == on
            ? camera
            : camera.copyWith(backgroundGeotagging: on),
      );

  /// Turns keeping [serial]'s clock on the phone's time on or off.
  Future<void> setSyncClock(String serial, {required bool on}) => _change(
    serial,
    (camera) =>
        camera.syncClock == on ? camera : camera.copyWith(syncClock: on),
  );

  /// The camera took the Store Location Info value [written]: nothing is
  /// waiting to be written any more, unless the user has flipped the
  /// switch the other way since.
  Future<void> storeLocationInfoWritten(
    String serial, {
    required bool written,
  }) => _change(
    serial,
    (camera) => camera.storeLocationInfoPending == written
        ? camera.copyWith(storeLocationInfoPending: () => null)
        : camera,
  );

  /// Saves [serial]'s camera as [change] makes it. Nothing is saved when
  /// the camera is not paired, or [change] returns it as it is.
  Future<void> _change(
    String serial,
    SavedCamera Function(SavedCamera camera) change,
  ) {
    final i = _cameras.indexWhere((c) => c.serial == serial);
    if (i < 0) return Future.value();
    final changed = change(_cameras[i]);
    if (identical(changed, _cameras[i])) return Future.value();
    _cameras[i] = changed;
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
