import 'dart:typed_data';

import 'package:gr_protocol/src/ble/bytes.dart';
import 'package:gr_protocol/src/ble/catalog.dart';
import 'package:gr_protocol/src/ble/codecs.dart';
import 'package:gr_protocol/src/ble/enums.dart';

/// How the 16 UUID bytes inside an aggregate notification were ordered.
/// Which order the camera actually uses is an open hardware question
/// (research/protocol/ble-imagesync.md §4.2), so the decoder tries all three
/// and records the one that matched.
enum BleUuidByteOrder {
  /// Image Sync's parser (`c.java:597-612`): wire = node(6) | clock_seq(2)
  /// | time_hi(2) | time_mid(2) | time_low(4), each group big-endian.
  imageSyncGroups,

  /// Canonical big-endian order, as the UUID string reads.
  canonical,

  /// Fully byte-reversed (usual little-endian BLE attribute order).
  reversed;

  /// Canonical dashed UUID for [bytes] read in this order.
  String uuidOf(Uint8List bytes) {
    if (bytes.length != 16) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must be 16 bytes');
    }
    final ordered = switch (this) {
      BleUuidByteOrder.imageSyncGroups => Uint8List.fromList([
        ...bytes.sublist(12, 16),
        ...bytes.sublist(10, 12),
        ...bytes.sublist(8, 10),
        ...bytes.sublist(6, 8),
        ...bytes.sublist(0, 6),
      ]),
      BleUuidByteOrder.canonical => bytes,
      BleUuidByteOrder.reversed => Uint8List.fromList(bytes.reversed.toList()),
    };
    final h = BleBytes.toHex(ordered).toUpperCase();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Wire bytes of canonical [uuid] in this order.
  Uint8List bytesOf(String uuid) {
    final c = BleBytes.fromHex(uuid.replaceAll('-', ''));
    if (c.length != 16) {
      throw FormatException('Expected a 128-bit UUID', uuid);
    }
    return switch (this) {
      BleUuidByteOrder.imageSyncGroups => Uint8List.fromList([
        ...c.sublist(10, 16),
        ...c.sublist(8, 10),
        ...c.sublist(6, 8),
        ...c.sublist(4, 6),
        ...c.sublist(0, 4),
      ]),
      BleUuidByteOrder.canonical => c,
      BleUuidByteOrder.reversed => Uint8List.fromList(c.reversed.toList()),
    };
  }
}

/// Image Sync's aggregate notification (Shooting Service Notification,
/// High Frequency Shooting Service Notification, Camera Service
/// Notification): `[count sint8][include sint8][16-byte UUID][changed
/// value]`. Image Sync processes only the first entry (ble-imagesync.md
/// §4.2); the value of a multi-entry notification cannot be delimited
/// because entries carry no length.
final class BleAggregateNotification {
  /// Creates a notification; the decoder fills [characteristic],
  /// [byteOrder] and [decoded] when the embedded UUID matches the catalog.
  const new({
    required this.count,
    required this.include,
    required this.uuidBytes,
    required this.changedValue,
    this.characteristic,
    this.byteOrder,
    this.decoded,
  });

  /// Number of entries the camera says the notification carries; only 1
  /// can be delimited.
  final int count;

  /// "Include Changed Value" byte: whether [changedValue] is present.
  final BleEnumValue<BleAggregateInclude> include;

  /// The 16 embedded UUID bytes, in wire order.
  final Uint8List uuidBytes;

  /// Bytes after the UUID: the changed characteristic's new value when
  /// [include] says so; normally empty otherwise.
  final Uint8List changedValue;

  /// Catalog characteristic the embedded UUID matched, if any.
  final GrBleCharacteristic<Object>? characteristic;

  /// Byte order that produced the match.
  final BleUuidByteOrder? byteOrder;

  /// [changedValue] decoded as [characteristic], when included.
  final BleDecoded<Object>? decoded;

  /// Diagnostic JSON with the raw bytes, the match and the decoded value.
  Map<String, Object?> toJson() => {
    'count': count,
    'include': include.toJson(),
    'uuidHex': BleBytes.toHex(uuidBytes),
    'characteristic': characteristic?.key,
    'uuid': characteristic?.uuid,
    'byteOrder': byteOrder?.name,
    'changedValueHex': BleBytes.toHex(changedValue),
    'decoded': decoded?.toJson(),
  };
}

/// Matches 16 embedded UUID bytes against the catalog, trying
/// [BleUuidByteOrder.values] in declaration order (Image Sync's group order
/// first).
({GrBleCharacteristic<Object> characteristic, BleUuidByteOrder order})?
matchAggregateUuid(Uint8List uuidBytes) {
  for (final order in BleUuidByteOrder.values) {
    final c = GrBleCatalog.byUuid(order.uuidOf(uuidBytes));
    if (c != null) return (characteristic: c, order: order);
  }
  return null;
}

/// Codec for [BleAggregateNotification]: decodes the header, matches the
/// embedded UUID and decodes the changed value with the matched
/// characteristic's codec.
final class BleAggregateNotificationCodec
    extends BleCodec<BleAggregateNotification> {
  /// Stateless; one shared instance is enough.
  const new();

  @override
  BleDecoded<BleAggregateNotification> decode(Uint8List bytes) {
    if (bytes.length < 18) {
      const expected =
          'expected at least 18 bytes (count, include, 16-byte UUID)';
      return result(bytes, null, ['$expected, got ${bytes.length}']);
    }
    final issues = <String>[];
    final count = BleIntFormat.sint8.read(bytes, 0);
    final include = BleEnumValue.decode(
      BleIntFormat.sint8.read(bytes, 1),
      BleAggregateInclude.values,
    );
    final uuidBytes = Uint8List.fromList(bytes.sublist(2, 18));
    final value = Uint8List.fromList(bytes.sublist(18));
    if (count != 1) {
      issues.add(
        'count $count: only a single entry can be delimited; the value is '
        'decoded as the first entry',
      );
    }
    final match = matchAggregateUuid(uuidBytes);
    if (match == null) {
      issues.add(
        'embedded UUID matches no catalog characteristic in any byte order',
      );
    }
    BleDecoded<Object>? decoded;
    if (include.known == BleAggregateInclude.included) {
      if (match != null) {
        decoded = match.characteristic.codec.decode(value);
        for (final issue in decoded.issues) {
          issues.add('changed value: $issue');
        }
      }
    } else if (value.isNotEmpty) {
      issues.add(
        '${value.length} value byte(s) although include = ${include.raw}',
      );
    }
    return result(
      bytes,
      BleAggregateNotification(
        count: count,
        include: include,
        uuidBytes: uuidBytes,
        changedValue: value,
        characteristic: match?.characteristic,
        byteOrder: match?.order,
        decoded: decoded,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleAggregateNotification value) {
    if (value.uuidBytes.length != 16) {
      throw ArgumentError.value(
        value.uuidBytes,
        'uuidBytes',
        'must be 16 bytes',
      );
    }
    final head = Uint8List(2);
    BleIntFormat.sint8.write(head, 0, value.count, 'count');
    BleIntFormat.sint8.write(head, 1, value.include.raw, 'include');
    return Uint8List.fromList([
      ...head,
      ...value.uuidBytes,
      ...value.changedValue,
    ]);
  }

  @override
  BleAggregateNotification parse(String text) => parseHex(text);

  @override
  Object? valueToJson(BleAggregateNotification value) => value.toJson();

  @override
  String describeValue(BleAggregateNotification value) {
    final c = value.characteristic;
    if (c == null) {
      return 'unmatched UUID ${BleBytes.toHex(value.uuidBytes)} '
          'value ${BleBytes.toHex(value.changedValue)}';
    }
    final d = value.decoded;
    return '${c.key} [${value.byteOrder?.name}] = '
        '${d == null ? '(not included)' : d.describe()}';
  }

  @override
  String get syntax => 'hex bytes';
}
