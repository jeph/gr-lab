import 'dart:typed_data';

import 'bytes.dart';
import 'catalog.dart';
import 'model.dart';
import 'transport.dart';

/// Bluetooth SIG company ID of Ricoh Company Ltd, carried in the camera's
/// scan response (docs/camera-models.md §4.1).
const grRicohCompanyId = 0x065F;

/// Marker byte that starts the Ricoh payload (`def_adv.yaml` format value).
const grAdvertisingMarker = 0xDA;

/// Decoded Ricoh manufacturer payload: `DA 01 [model] 02 [serial u32 LE]
/// 03 [power]` with fixed, tag-implied widths and no length bytes.
///
/// Follows the parsing rule of docs/camera-models.md §4.1: tags are read
/// only in that order, parsing stops at the first unexpected tag or short
/// payload, already-decoded fields are kept, and later bytes are never
/// reinterpreted. [raw] keeps the payload for diagnostics.
final class GrManufacturerData {
  const GrManufacturerData._({
    required this.raw,
    required this.model,
    required this.serialNumber,
    required this.powerRaw,
    required this.issues,
  });

  /// Payload without the 2-byte company ID.
  factory GrManufacturerData.parse(Uint8List payload) {
    final issues = <String>[];
    GrModelCode? model;
    int? serial;
    int? power;

    // Returns false (and records why) when parsing must stop at [offset].
    bool expectTag(int offset, int tag, int width, String what) {
      if (payload.length <= offset) {
        issues.add('payload ends before tag ${_hex2(tag)} ($what)');
        return false;
      }
      if (payload[offset] != tag) {
        issues.add(
          'unexpected tag ${_hex2(payload[offset])} at offset $offset '
          '(expected ${_hex2(tag)}, $what); parsing stopped',
        );
        return false;
      }
      if (payload.length < offset + 1 + width) {
        issues.add('tag ${_hex2(tag)} ($what) value is truncated');
        return false;
      }
      return true;
    }

    if (payload.isEmpty) {
      issues.add('empty payload');
    } else if (payload[0] != grAdvertisingMarker) {
      issues.add(
        'first byte ${_hex2(payload[0])} is not the marker '
        '${_hex2(grAdvertisingMarker)}',
      );
    } else if (expectTag(1, 0x01, 1, 'model code')) {
      model = GrModelCode(payload[2]);
      if (expectTag(3, 0x02, 4, 'serial number')) {
        serial =
            payload[4] |
            (payload[5] << 8) |
            (payload[6] << 16) |
            (payload[7] << 24);
        if (expectTag(8, 0x03, 1, 'camera power')) {
          power = payload[9];
          if (payload.length > 10) {
            issues.add(
              '${payload.length - 10} byte(s) after tag 03 not parsed',
            );
          }
        }
      }
    }
    return GrManufacturerData._(
      raw: payload,
      model: model,
      serialNumber: serial,
      powerRaw: power,
      issues: List.unmodifiable(issues),
    );
  }

  final Uint8List raw;
  final GrModelCode? model;

  /// Tag `02`: digits of the camera serial number as uint32 LE.
  final int? serialNumber;

  /// Tag `03`: 1 = on (main firmware), 0 = off (BT-only firmware).
  final int? powerRaw;
  final List<String> issues;

  /// Serial rendered like Image Sync (`%07d`).
  String? get serialText => serialNumber?.toString().padLeft(7, '0');

  /// Null when tag 03 is absent or holds an undocumented value.
  bool? get powerOn => switch (powerRaw) {
    1 => true,
    0 => false,
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'hex': BleBytes.toHex(raw),
    'model': model?.toJson(),
    'serial': serialText,
    'powerRaw': powerRaw,
    'powerOn': powerOn,
    if (issues.isNotEmpty) 'issues': issues,
  };
}

String _hex2(int b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';

/// A scanned advertisement with the camera-specific parts decoded.
final class GrAdvertisement {
  GrAdvertisement(this.advertisement)
    : ricoh = switch (advertisement.manufacturerData[grRicohCompanyId]) {
        final Uint8List payload => GrManufacturerData.parse(payload),
        null => null,
      };

  final BleAdvertisement advertisement;

  /// Null when the advertisement carries no company-0x065F data (for
  /// example a primary packet whose scan response has not arrived yet).
  final GrManufacturerData? ricoh;

  String get deviceId => advertisement.deviceId;
  String? get name => advertisement.name;
  int get rssi => advertisement.rssi;

  GrModel? get model => ricoh?.model?.model;
  int? get serialNumber => ricoh?.serialNumber;
  String? get serialText => ricoh?.serialText;

  /// True when the Ricoh payload decoded a GR model code.
  bool get isGrCamera => model != null;

  /// Power state from tag `03` (Image Sync's source, preferred).
  bool? get powerOn => ricoh?.powerOn;

  /// Power state inferred the way GR WORLD does, from the advertised
  /// service UUID: Client Registration `0F291746` means off (and takes
  /// precedence), Camera Information `9A5ED1C5` means on (ble.md
  /// §Identifying a camera in the scan).
  bool? get powerOnFromServices {
    final uuids = advertisement.serviceUuids.map(_canonicalOrSelf).toSet();
    if (uuids.contains(GrBleServices.clientRegistration.uuid)) return false;
    if (uuids.contains(GrBleServices.cameraInformation.uuid)) return true;
    return null;
  }

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'name': name,
    'rssi': rssi,
    'connectable': advertisement.connectable,
    'serviceUuids': advertisement.serviceUuids,
    'ricoh': ricoh?.toJson(),
    'powerOnFromServices': powerOnFromServices,
  };
}

String _canonicalOrSelf(String uuid) {
  try {
    return canonicalUuid(uuid);
  } on FormatException {
    return uuid;
  }
}
