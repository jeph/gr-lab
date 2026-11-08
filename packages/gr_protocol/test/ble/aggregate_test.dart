import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:test/test.dart';

Uint8List b(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  const shutterUuid = 'D3CE2AED-10FA-4648-833D-CD74C6F35905';
  final codec = GrBleCatalog.shootingNotification.codec;

  group('BleUuidByteOrder', () {
    test('Image Sync group order matches the documented example', () {
      // ble-imagesync.md §4.2: `CD74C6F35905 833D 4648 10FA D3CE2AED`.
      final wire = BleBytes.fromHex('CD74C6F35905833D464810FAD3CE2AED');
      expect(BleUuidByteOrder.imageSyncGroups.uuidOf(wire), shutterUuid);
      expect(BleUuidByteOrder.imageSyncGroups.bytesOf(shutterUuid), wire);
    });

    test('canonical and reversed round-trip', () {
      for (final order in BleUuidByteOrder.values) {
        expect(order.uuidOf(order.bytesOf(shutterUuid)), shutterUuid);
      }
      expect(
        BleBytes.toHex(BleUuidByteOrder.reversed.bytesOf(shutterUuid)),
        '0559f3c674cd3d834846fa10ed2aced3',
      );
    });

    test('rejects wrong sizes', () {
      expect(
        () => BleUuidByteOrder.canonical.uuidOf(Uint8List(15)),
        throwsArgumentError,
      );
      expect(
        () => BleUuidByteOrder.canonical.bytesOf('1234'),
        throwsFormatException,
      );
    });
  });

  group('aggregate notification', () {
    Uint8List notification(
      BleUuidByteOrder order, {
      int count = 1,
      int include = 1,
      List<int> value = const [24],
      String uuid = shutterUuid,
    }) => b([count, include, ...order.bytesOf(uuid), ...value]);

    test('decodes the first entry in Image Sync order', () {
      final d = codec.decode(notification(BleUuidByteOrder.imageSyncGroups));
      expect(d.issues, isEmpty);
      final v = d.value!;
      expect(v.characteristic, same(GrBleCatalog.shutterSpeed));
      expect(v.byteOrder, BleUuidByteOrder.imageSyncGroups);
      expect(v.include.known, BleAggregateInclude.included);
      final shutter = v.decoded!.value! as BleIndexedValue;
      expect(shutter.label, '1/125');
    });

    test('falls back to canonical and fully reversed orders', () {
      for (final order in [
        BleUuidByteOrder.canonical,
        BleUuidByteOrder.reversed,
      ]) {
        final v = codec.decode(notification(order)).value!;
        expect(v.characteristic, same(GrBleCatalog.shutterSpeed));
        expect(v.byteOrder, order);
      }
    });

    test('multi-byte values decode with the matched codec', () {
      final d = GrBleCatalog.cameraServiceNotification.codec.decode(
        notification(
          BleUuidByteOrder.imageSyncGroups,
          uuid: GrBleCatalog.captureStatus.uuid,
          value: [1, 0],
        ),
      );
      final status = d.value!.decoded!.value! as BleCaptureStatus;
      expect(status.capturing.known, BleCapturing.capturing);
      expect(d.issues, isEmpty);
    });

    test('value issues are surfaced', () {
      final d = codec.decode(
        notification(BleUuidByteOrder.imageSyncGroups, value: []),
      );
      expect(d.value!.decoded!.value, isNull);
      expect(d.issues.single, startsWith('changed value:'));
    });

    test('not-included entry has no decoded value', () {
      final d = codec.decode(
        notification(BleUuidByteOrder.canonical, include: 0, value: []),
      );
      expect(d.issues, isEmpty);
      expect(d.value!.decoded, isNull);
      expect(d.value!.characteristic, same(GrBleCatalog.shutterSpeed));
      final extra = codec.decode(
        notification(BleUuidByteOrder.canonical, include: 0),
      );
      expect(extra.issues.single, contains('include = 0'));
    });

    test('count other than 1 is reported', () {
      final d = codec.decode(
        notification(BleUuidByteOrder.imageSyncGroups, count: 2),
      );
      expect(d.value!.count, 2);
      expect(d.issues.single, contains('count 2'));
    });

    test('unknown UUID keeps raw bytes', () {
      final d = codec.decode(b([1, 1, ...List.filled(16, 0xab), 0x05]));
      expect(d.value!.characteristic, isNull);
      expect(d.value!.byteOrder, isNull);
      expect(d.value!.changedValue, [5]);
      expect(d.issues.single, contains('matches no catalog'));
    });

    test('short payload has no value', () {
      final d = codec.decode(b([1, 1, 0, 0]));
      expect(d.value, isNull);
      expect(d.issues, hasLength(1));
    });

    test('encode round-trips', () {
      final bytes = notification(BleUuidByteOrder.imageSyncGroups);
      expect(codec.encode(codec.decode(bytes).value!), bytes);
    });
  });
}
