import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Which of the camera's storages a [CameraStorage] is.
enum CameraStorageKind {
  /// Built-in memory: BLE type 0, `/v1/props` `in`.
  internal('in'),

  /// SD card slot 1: BLE type 1, `/v1/props` `sd1`.
  sd1('sd1'),

  /// SD card slot 2: BLE type 2; its `/v1/props` name `sd2` is
  /// \[inferred\] from `sd1`.
  sd2('sd2');

  new(this.propsName);

  /// The storage's `name` in `/v1/props` `storages[]`.
  final String propsName;
}

/// One storage as the camera last reported it, over Bluetooth (Storage
/// Information) or Wi-Fi (`/v1/props` `storages[]`).
@immutable
final class CameraStorage {
  /// A storage reading; see the fields for each source's meaning.
  const new({
    required this.id,
    required this.kind,
    required this.present,
    this.available,
    this.active,
    this.remainingPictures,
  });

  /// [kind]'s `/v1/props` name, or the name or BLE type the camera sent
  /// when GR Lab does not know it.
  final String id;

  /// Null for a storage GR Lab does not know.
  final CameraStorageKind? kind;

  /// The medium is there (BLE `exists`, `/v1/props` `equipped`).
  final bool present;

  /// The camera can use it; null when the reading does not say.
  final bool? available;

  /// The camera records to it; null when the reading does not say.
  final bool? active;

  /// Still pictures that fit; null when the reading does not say.
  final int? remainingPictures;

  @override
  bool operator ==(Object other) =>
      other is CameraStorage &&
      other.id == id &&
      other.kind == kind &&
      other.present == present &&
      other.available == available &&
      other.active == active &&
      other.remainingPictures == remainingPictures;

  @override
  int get hashCode =>
      Object.hash(id, kind, present, available, active, remainingPictures);

  Map<String, Object?> _toJson() => {
    'id': id,
    'present': present,
    'available': ?available,
    'active': ?active,
    'remainingPictures': ?remainingPictures,
  };
}

/// The camera's battery and storages for one session, from wherever the
/// camera reports them: the Battery Level and Storage Information
/// notifications, watched on every Bluetooth link for the whole session
/// \[design\] (GR WORLD has a battery level notifier too,
/// research/notes/ble/WfbChars.md), and every `/v1/props` the session
/// reads over Wi-Fi (`GrSession.props`). Every screen reads these values
/// from here.
///
/// While the Bluetooth watch reports a value, readings of it over Wi-Fi
/// are ignored, so the two never take turns \[design\]; when Bluetooth is
/// down, Wi-Fi keeps the values current. The last values stay when both
/// links go.
final class CameraStatus extends ChangeNotifier {
  new _(this._session, this._camera) {
    _events = _session.events.listen((e) {
      // Notifications are per link.
      switch (e.kind) {
        case 'ble.ready':
          _watch();
        case 'ble.lost':
          _stopWatching();
      }
    });
    _propsUpdates = _session.propsUpdates.listen(_onProps);
    final props = _session.props;
    if (props != null) _onProps(props);
    if (_session.ble != null) _watch();
  }

  final GrSession _session;
  final GrCameraEnvironment _camera;
  late final StreamSubscription<GrSessionEvent> _events;
  late final StreamSubscription<GrProps> _propsUpdates;
  StreamSubscription<GrBleNotification<Object>>? _watching;
  bool _closed = false;

  /// The current Bluetooth watch delivered Battery Level / Storage
  /// Information.
  bool _batteryOverBle = false;
  bool _storagesOverBle = false;

  int? _battery;
  List<CameraStorage> _storages = const [];

  /// Battery percent; null until the camera reported it.
  int? get battery => _battery;

  /// Every storage the camera reported, in its order.
  List<CameraStorage> get storages => _storages;

  /// Still pictures that fit on the storage the camera records to: the one
  /// marked active, else the first one present and usable.
  int? get shotsLeft {
    for (final s in _storages) {
      if (s.active ?? false) return s.remainingPictures;
    }
    for (final s in _storages) {
      if (s.present && s.available != false) return s.remainingPictures;
    }
    return null;
  }

  static final _watched = <GrBleCharacteristic<Object>>[
    GrBleCatalog.batteryLevel,
    GrBleCatalog.storageInformation,
  ];

  void _watch() {
    _stopWatching();
    final ble = _session.ble;
    if (_closed || ble == null) return;
    _camera.event('status.watch');
    _watching = ble
        .watchAll(_watched, prime: true)
        .listen(_onNotification, onError: (Object _) {}, onDone: _onWatchEnd);
  }

  void _stopWatching() {
    unawaited(_watching?.cancel());
    _watching = null;
    _onWatchEnd();
  }

  /// The link went: Wi-Fi readings count again.
  void _onWatchEnd() {
    _batteryOverBle = false;
    _storagesOverBle = false;
  }

  void _onNotification(GrBleNotification<Object> n) {
    if (_closed) return;
    switch (n.decoded.value) {
      case BleBatteryLevel(:final level):
        _batteryOverBle = true;
        _update(battery: level < 0 ? null : level, source: 'ble');
      case BleStorageInformation(:final entries):
        _storagesOverBle = true;
        _update(
          storages: [for (final e in entries) _fromBle(e)],
          source: 'ble',
        );
      default:
        return;
    }
  }

  void _onProps(GrProps props) {
    if (_closed) return;
    _update(
      battery: _batteryOverBle ? _battery : props.battery,
      storages: _storagesOverBle
          ? _storages
          : [for (final s in props.storages) _fromProps(s)],
      source: 'props',
    );
  }

  void _update({
    required String source,
    int? battery,
    List<CameraStorage>? storages,
  }) {
    final nextBattery = battery ?? _battery;
    final nextStorages = storages ?? _storages;
    if (nextBattery == _battery && listEquals(nextStorages, _storages)) return;
    _battery = nextBattery;
    _storages = nextStorages;
    _camera.event('status.changed', {
      'source': source,
      'battery': _battery,
      'storages': [for (final s in _storages) s._toJson()],
    });
    notifyListeners();
  }

  static CameraStorage _fromBle(BleStorageEntry e) {
    final kind = switch (e.type.known) {
      BleStorageType.internalMemory => CameraStorageKind.internal,
      BleStorageType.sdSlot1 => CameraStorageKind.sd1,
      BleStorageType.sdSlot2 => CameraStorageKind.sd2,
      null => null,
    };
    return CameraStorage(
      id: kind?.propsName ?? 'type${e.type.raw}',
      kind: kind,
      present: e.exists,
      available: e.available,
      active: e.active,
      remainingPictures: e.remainingPictures,
    );
  }

  static CameraStorage _fromProps(GrStorageInfo s) {
    final name = s.name;
    final kind = CameraStorageKind.values
        .where((k) => k.propsName == name)
        .firstOrNull;
    return CameraStorage(
      id: name ?? '?',
      kind: kind,
      present: s.equipped ?? true,
      available: s.available,
      active: s.active,
      remainingPictures: s.remain,
    );
  }

  void _close() {
    _closed = true;
    unawaited(_events.cancel());
    unawaited(_propsUpdates.cancel());
    _stopWatching();
  }
}

/// Creates the status of [session]. Used by `CameraSession` only.
CameraStatus createCameraStatus(
  GrSession session,
  GrCameraEnvironment camera,
) => CameraStatus._(session, camera);

/// What `CameraSession` does to its status. Not exported.
extension CameraStatusInternals on CameraStatus {
  /// The session ended: stops watching and notifying.
  void close() => _close();
}
