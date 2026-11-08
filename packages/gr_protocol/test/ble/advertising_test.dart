import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:test/test.dart';

Uint8List b(List<int> bytes) => Uint8List.fromList(bytes);

/// `DA 01 <model> 02 <serial u32 LE> 03 <power>` (camera-models.md §4.1).
Uint8List payload(int model, int serial, int power) => b([
  0xda,
  0x01,
  model,
  0x02,
  serial & 0xff,
  (serial >> 8) & 0xff,
  (serial >> 16) & 0xff,
  (serial >> 24) & 0xff,
  0x03,
  power,
]);

void main() {
  group('GrManufacturerData.parse', () {
    test('full GR IV HDF payload', () {
      final d = GrManufacturerData.parse(payload(8, 1234567, 1));
      expect(d.issues, isEmpty);
      expect(d.model!.model, GrModel.gr4Hdf);
      expect(d.serialNumber, 1234567);
      expect(d.serialText, '1234567');
      expect(d.powerOn, isTrue);
    });

    test('serial is little-endian and padded to 7 digits', () {
      final d = GrManufacturerData.parse(
        b([0xda, 0x01, 0x01, 0x02, 0x39, 0x30, 0x00, 0x00, 0x03, 0x00]),
      );
      expect(d.serialNumber, 12345);
      expect(d.serialText, '0012345');
      expect(d.powerOn, isFalse);
      expect(d.model!.model, GrModel.gr3);
    });

    test('unknown model code is kept raw', () {
      final d = GrManufacturerData.parse(payload(2, 1, 1));
      expect(d.model!.raw, 2);
      expect(d.model!.model, isNull);
      expect(d.issues, isEmpty);
    });

    test('undocumented power value is raw with null powerOn', () {
      final d = GrManufacturerData.parse(payload(7, 1, 2));
      expect(d.powerRaw, 2);
      expect(d.powerOn, isNull);
    });

    test('stops at the first unexpected tag, keeping earlier fields', () {
      final d = GrManufacturerData.parse(
        b([0xda, 0x01, 0x07, 0x04, 0x02, 0x01, 0x00, 0x00, 0x00, 0x03, 0x01]),
      );
      expect(d.model!.model, GrModel.gr4);
      expect(d.serialNumber, isNull);
      expect(d.powerRaw, isNull);
      expect(d.issues.single, contains('unexpected tag 0x04'));
    });

    test('short payloads keep what decoded', () {
      final truncatedSerial = GrManufacturerData.parse(
        b([0xda, 0x01, 0x07, 0x02, 0x01, 0x02]),
      );
      expect(truncatedSerial.model!.model, GrModel.gr4);
      expect(truncatedSerial.serialNumber, isNull);
      expect(truncatedSerial.issues.single, contains('truncated'));

      final noPower = GrManufacturerData.parse(
        b([0xda, 0x01, 0x07, 0x02, 0x01, 0x00, 0x00, 0x00]),
      );
      expect(noPower.serialNumber, 1);
      expect(noPower.powerRaw, isNull);
      expect(noPower.issues.single, contains('ends before tag 0x03'));
    });

    test('wrong marker and empty payload decode nothing', () {
      expect(GrManufacturerData.parse(b([])).issues.single, 'empty payload');
      final wrong = GrManufacturerData.parse(b([0xdb, 0x01, 0x07]));
      expect(wrong.model, isNull);
      expect(wrong.issues.single, contains('marker'));
    });

    test('trailing bytes are reported, not reinterpreted', () {
      final d = GrManufacturerData.parse(b([...payload(7, 5, 1), 0x04, 0x09]));
      expect(d.powerOn, isTrue);
      expect(d.issues.single, contains('2 byte(s) after tag 03'));
    });
  });

  group('GrAdvertisement', () {
    test('decodes company 0x065F only', () {
      final ad = GrAdvertisement(
        BleAdvertisement(
          deviceId: 'dev',
          rssi: -60,
          name: 'GR_123456',
          manufacturerData: {
            0x004c: b([1, 2]),
            0x065f: payload(8, 42, 0),
          },
        ),
      );
      expect(ad.isGrCamera, isTrue);
      expect(ad.model, GrModel.gr4Hdf);
      expect(ad.serialNumber, 42);
      expect(ad.powerOn, isFalse);
      expect(ad.toJson()['ricoh'], isA<Map<String, Object?>>());
    });

    test('no Ricoh data', () {
      final ad = GrAdvertisement(
        const BleAdvertisement(deviceId: 'x', rssi: -70),
      );
      expect(ad.ricoh, isNull);
      expect(ad.isGrCamera, isFalse);
      expect(ad.powerOn, isNull);
    });

    test('GR WORLD service-UUID power inference', () {
      GrAdvertisement withServices(List<String> uuids) => GrAdvertisement(
        BleAdvertisement(deviceId: 'x', rssi: 0, serviceUuids: uuids),
      );
      final reg = GrBleServices.clientRegistration.uuid;
      final info = GrBleServices.cameraInformation.uuid;
      expect(withServices([info]).powerOnFromServices, isTrue);
      expect(withServices([reg, info]).powerOnFromServices, isFalse);
      expect(withServices([info.toLowerCase()]).powerOnFromServices, isTrue);
      expect(withServices(['not-a-uuid']).powerOnFromServices, isNull);
    });
  });

  group('GrModel', () {
    test('codes, families and firmware strings', () {
      expect(GrModel.fromCode(1), GrModel.gr3);
      expect(GrModel.fromCode(3), GrModel.gr3x);
      expect(GrModel.fromCode(5), GrModel.gr3Hdf);
      expect(GrModel.fromCode(6), GrModel.gr3xHdf);
      expect(GrModel.fromCode(7), GrModel.gr4);
      expect(GrModel.fromCode(8)!.modelString, 'RICOH GR IV HDF');
      expect(GrModel.fromCode(9), GrModel.gr4Monochrome);
      expect(GrModel.fromCode(10), GrModel.gr4x);
      for (final unknown in [0, 2, 4, 11, 255]) {
        expect(GrModel.fromCode(unknown), isNull);
      }
      expect(GrModel.gr3xHdf.family, GrModelFamily.gr3);
      expect(GrModel.gr4Hdf.family, GrModelFamily.gr4);
      expect(GrModel.gr4x.acceptedByGrWorld, isFalse);
    });

    test('model strings match exactly, with or without RICOH prefix', () {
      expect(GrModel.fromModelString('RICOH GR IV HDF'), GrModel.gr4Hdf);
      expect(GrModel.fromModelString('GR IV HDF'), GrModel.gr4Hdf);
      expect(GrModel.fromModelString('RICOH GR IV\u0000\u0000'), GrModel.gr4);
      expect(GrModel.fromModelString('GR IIIx'), GrModel.gr3x);
      expect(GrModel.fromModelString('gr iv'), isNull);
      expect(GrModel.fromModelString('RICOH GR II'), isNull);
    });

    test('GrModelCode keeps raw', () {
      expect(GrModelCode(8).toJson(), {
        'raw': 8,
        'name': 'gr4Hdf',
        'modelString': 'RICOH GR IV HDF',
        'family': 'gr4',
      });
      expect(GrModelCode(42).model, isNull);
      expect('${GrModelCode(42)}', 'unknown model code 42');
    });
  });
}
