part of 'fake_camera.dart';

/// A position the simulated camera accepted over Bluetooth (GPS
/// Information).
final class FakeCameraLocation {
  /// The position at [latitude], [longitude] and [altitude] with
  /// [fixTime], which the camera took at [receivedAt] by its own clock.
  const new({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.fixTime,
    required this.receivedAt,
  });

  /// Degrees north of the equator, as written.
  final double latitude;

  /// Degrees east of Greenwich, as written.
  final double longitude;

  /// Metres, as written.
  final double altitude;

  /// The record's own time, read as UTC, which is what both of Ricoh's
  /// apps send; the camera checks only that it is a real date and time
  /// (research/protocol/geotagging.md §1.2, §1.3).
  final DateTime fixTime;

  /// The camera's clock when it took the record; the position is valid for
  /// 600 s from then, and the camera compares this with its clock again
  /// when it starts up.
  final DateTime receivedAt;

  @override
  String toString() =>
      'FakeCameraLocation($latitude, $longitude, $altitude m, fix '
      '${fixTime.toIso8601String()}, received '
      '${receivedAt.toIso8601String()})';
}

/// How long the camera keeps a position it accepted (found in the GR IV
/// 1.20 and GR III 2.20 firmware; geotagging.md §1.3).
const _locationValidity = Duration(seconds: 600);

/// How long after a change of its clock a GR IV clears its location (found
/// in the GR IV 1.20 firmware; geotagging.md §1.3).
const _clearAfterClockChange = Duration(seconds: 1);

/// The location and clock rules of the main firmware
/// (research/protocol/geotagging.md §1).
extension on FakeGrCamera {
  /// The camera's clock: the phone's, moved by the offset.
  DateTime get _clockNow => clock.now().toLocal().add(_clockOffset);

  /// The position the camera holds, unless its 600 s have passed. The
  /// firmware arms a one-shot timer for them at receipt, which a later
  /// change of the clock does not move, and keeps the time of receipt for
  /// its next start-up ([_restoreLocation]) (geotagging.md §1.3).
  FakeCameraLocation? get _heldLocation {
    final until = _locationUntil;
    if (until == null || !clock.now().isBefore(until)) return null;
    return _location;
  }

  /// The camera starts up: the 600 s check runs again, against the stored
  /// time of receipt and the camera's clock, so a position outlives a
  /// power cycle inside that time (geotagging.md §1.3).
  void _restoreLocation() {
    final held = _location;
    if (held == null) return;
    final left = _locationValidity - _clockNow.difference(held.receivedAt);
    _locationUntil = clock.now().add(left);
  }

  /// A write to GPS Information. The camera takes it only while it is on
  /// and Store Location Info is on, and only when it is in range:
  /// latitude within ±90, longitude within ±180, altitude within ±9999 and
  /// a real calendar date and time (geotagging.md §1.2). The firmware also
  /// wants the year within 49 of a base year that is \[unknown\], which is
  /// not checked here. That a camera in its off state refuses is
  /// \[design\]: what it does is \[unknown\] (geotagging.md §7, test 7).
  void _writeLocation(GrBleCharacteristic<Object> c, Uint8List v) {
    final record = GrBleCatalog.gpsInformation.codec.decode(v).value;
    final refusal = _locationRefusal(record);
    if (refusal != null || record == null) {
      _refusedLocationWrites++;
      throw BleException(BleErrorCode.gatt, '${c.key}: $refusal');
    }
    final location = FakeCameraLocation(
      latitude: record.latitude,
      longitude: record.longitude,
      altitude: record.altitude,
      fixTime: DateTime.utc(
        record.year,
        record.month,
        record.day,
        record.hour,
        record.minute,
        record.second,
      ),
      receivedAt: _clockNow,
    );
    // A clear still due after a clock change takes this position too: the
    // firmware's event clears whatever is held when it fires.
    _location = location;
    _locationUntil = clock.now().add(_locationValidity);
    _locationWrites.add(location);
    _values[c.uuid] = v;
  }

  /// Why the camera does not take [record] now; null when it does.
  String? _locationRefusal(BleGpsInformation? record) {
    if (!_poweredOn) return 'camera is off';
    if (!storeLocationInfo) return 'Store Location Info is off';
    if (locationLocked) return 'not settable now';
    if (record == null || !_inRange(record)) return 'invalid value';
    return null;
  }

  static bool _inRange(BleGpsInformation record) {
    final date = DateTime.utc(record.year, record.month, record.day);
    return record.latitude.abs() <= 90 &&
        record.longitude.abs() <= 180 &&
        record.altitude.abs() <= 9999 &&
        date.year == record.year &&
        date.month == record.month &&
        date.day == record.day &&
        record.hour <= 23 &&
        record.minute <= 59 &&
        record.second <= 59;
  }

  /// Store Location Info becomes [on]; off clears the location the camera
  /// holds. With [notify] (a change in the camera's menu) GEO Tag notifies.
  /// Whether the camera also notifies a value written over Bluetooth is
  /// \[unknown\], so that write does not \[design\].
  void _setStoreLocationInfo(bool on, {required bool notify}) {
    if (on == storeLocationInfo) return;
    final value = [if (on) 1 else 0];
    _values[GrBleCatalog.geoTag.uuid] = Uint8List.fromList(value);
    if (!on) _location = null;
    if (notify) _notify(GrBleCatalog.geoTag, value);
  }

  /// A write to GEO Tag: `bled` takes only `00` or `01` (geotagging.md
  /// §1.1).
  void _writeStoreLocationInfo(GrBleCharacteristic<Object> c, Uint8List v) {
    if (v.length != 1 || v.first > 1) {
      throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
    }
    _setStoreLocationInfo(v.first == 1, notify: false);
  }

  /// Date Time as the camera reports it: its clock in whole seconds, local
  /// time without a zone.
  Uint8List _readClock() =>
      GrBleCatalog.dateTime.codec.encode(BleDateTime.fromDateTime(_clockNow));

  /// A write to Date Time sets the clock to the time written, which
  /// starts that second.
  void _writeClock(GrBleCharacteristic<Object> c, Uint8List v) {
    final written = GrBleCatalog.dateTime.codec.decode(v).value;
    final time = written?.toLocalDateTime();
    if (time == null) {
      throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
    }
    _clockWrites.add(time);
    _setClock(time.difference(clock.now()));
  }

  /// Moves the clock to [offset] from the phone's. A clock that then shows
  /// another second than before has changed, and a GR IV clears its
  /// location a second after that; no such clear was found in the GR III
  /// firmware (geotagging.md §1.3, §1.5).
  void _setClock(Duration offset) {
    final before = BleDateTime.fromDateTime(_clockNow).iso;
    _clockOffset = offset;
    if (BleDateTime.fromDateTime(_clockNow).iso == before) return;
    if (model.family != GrModelFamily.gr4) return;
    _after(_clearAfterClockChange, () => _location = null);
  }
}
