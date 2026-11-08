import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:test/test.dart';

Uint8List b(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('BleBytes', () {
    test('round-trips with separators and prefix', () {
      expect(BleBytes.fromHex('0x01:ab-CD ef'), [0x01, 0xab, 0xcd, 0xef]);
      expect(BleBytes.toHex([0, 255, 16]), '00ff10');
    });

    test('rejects odd length and non-hex', () {
      expect(() => BleBytes.fromHex('abc'), throwsFormatException);
      expect(() => BleBytes.fromHex('zz'), throwsFormatException);
    });
  });

  group('BleIntFormat', () {
    test('reads little-endian signed and unsigned', () {
      final bytes = b([0xff, 0xff, 0xff, 0x7f]);
      expect(BleIntFormat.sint8.read(bytes, 0), -1);
      expect(BleIntFormat.uint8.read(bytes, 0), 255);
      expect(BleIntFormat.sint16.read(bytes, 0), -1);
      expect(BleIntFormat.uint16.read(bytes, 0), 0xffff);
      expect(BleIntFormat.sint32.read(bytes, 0), 0x7fffffff);
      expect(
        BleIntFormat.sint32.read(b([0x00, 0x00, 0x00, 0x80]), 0),
        -0x80000000,
      );
    });

    test('write enforces range', () {
      final out = Uint8List(2);
      BleIntFormat.sint16.write(out, 0, -2);
      expect(out, [0xfe, 0xff]);
      expect(() => BleIntFormat.sint8.write(out, 0, 128), throwsArgumentError);
      expect(() => BleIntFormat.uint8.write(out, 0, -1), throwsArgumentError);
    });
  });

  group('BleBoolCodec', () {
    const codec = BleBoolCodec();

    test('decodes byte0 == 1', () {
      expect(codec.decode(b([1])).value, isTrue);
      expect(codec.decode(b([0])).value, isFalse);
      expect(codec.decode(b([1])).issues, isEmpty);
    });

    test('flags values other than 0/1 and wrong lengths', () {
      final odd = codec.decode(b([2]));
      expect(odd.value, isFalse);
      expect(odd.issues, hasLength(1));
      expect(codec.decode(b([])).value, isNull);
      final long = codec.decode(b([1, 0]));
      expect(long.value, isTrue);
      expect(long.issues.single, contains('trailing'));
    });

    test('parses user text', () {
      expect(codec.encodeText('on'), [1]);
      expect(codec.encodeText('false'), [0]);
      expect(() => codec.parse('maybe'), throwsFormatException);
    });
  });

  group('BleEnumCodec', () {
    const codec = BleEnumCodec(BleCaptureMode.values);

    test('decodes documented values', () {
      final d = codec.decode(b([2]));
      expect(d.value!.known, BleCaptureMode.movie);
      expect(d.toJson()['value'], {'raw': 2, 'name': 'movie'});
    });

    test('keeps unknown raw values without throwing', () {
      final d = codec.decode(b([1]));
      expect(d.value!.raw, 1);
      expect(d.value!.known, isNull);
      expect(d.value!.label, 'unknown(1)');
    });

    test('parses names case-insensitively and integers', () {
      expect(codec.encodeText('MOVIE'), [2]);
      expect(codec.encodeText('7'), [7]);
      expect(() => codec.parse('video'), throwsFormatException);
    });

    test('drive mode is uint8 so 0x80+ stays positive', () {
      const drive = BleEnumCodec(BleDriveMode.values, BleIntFormat.uint8);
      expect(drive.decode(b([0x80])).value!.raw, 128);
      expect(
        drive.decode(b([65])).value!.known,
        BleDriveMode.starStreamRemote3s,
      );
    });
  });

  group('BleIndexedCodec', () {
    const shutter = BleIndexedCodec(BleIntFormat.uint8, bleShutterSpeedLabels);
    const aperture = BleIndexedCodec(BleIntFormat.sint8, bleApertureLabels);

    test('labels documented indexes', () {
      expect(shutter.decode(b([6])).value!.label, '1/8000');
      expect(shutter.decode(b([24])).value!.label, '1/125');
      expect(shutter.decode(b([0])).value!.label, 'B/T');
      expect(shutter.decode(b([200])).value!.label, isNull);
      expect(aperture.decode(b([10])).value!.label, '2.8');
    });

    test('integer text is the raw index, @ selects a label', () {
      expect(shutter.encodeText('30'), [30]);
      expect(shutter.encodeText('@30'), [60]);
      expect(shutter.encodeText('1/125'), [24]);
      expect(aperture.encodeText('2.8'), [10]);
    });

    test('ambiguous and unknown labels are rejected', () {
      // F13 appears at indexes 23 and 106 in def_ble.yaml.
      expect(() => aperture.parse('@13'), throwsFormatException);
      expect(() => aperture.parse('F2.8'), throwsFormatException);
    });

    test('ISO write range follows the Image Sync 0x00FFFFFF mask', () {
      final iso = GrBleCatalog.iso.codec;
      expect(iso.encodeText('3200'), [0x80, 0x0c, 0x00, 0x00]);
      expect(() => iso.encodeText('16777216'), throwsArgumentError);
      expect(() => iso.encodeText('-1'), throwsArgumentError);
      expect(iso.decode(b([0, 0, 0, 0])).value!.label, 'AUTO');
    });
  });

  group('BleListCodec', () {
    test('ISO list uses 4-byte sint32 elements', () {
      final d = GrBleCatalog.isoList.codec.decode(
        b([0x02, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x00]),
      );
      expect(d.issues, isEmpty);
      expect(d.value!.map((v) => v.raw), [0, 100]);
      expect(d.value!.first.label, 'AUTO');
    });

    test('short list decodes the complete elements and reports', () {
      final d = GrBleCatalog.isoList.codec.decode(
        b([0x02, 0x64, 0x00, 0x00, 0x00, 0xc8]),
      );
      expect(d.value!.map((v) => v.raw), [100]);
      expect(d.issues, hasLength(1));
    });

    test('negative count and empty input yield no value', () {
      expect(GrBleCatalog.driveModeList.codec.decode(b([0xff])).value, isNull);
      expect(GrBleCatalog.driveModeList.codec.decode(b([])).value, isNull);
    });

    test('extra bytes are reported', () {
      final d = GrBleCatalog.whiteBalanceList.codec.decode(b([1, 0, 9]));
      expect(d.value!.single.known, BleWhiteBalance.auto);
      expect(d.issues, hasLength(1));
    });

    test('encodes from text', () {
      expect(
        GrBleCatalog.operationModeList.codec.encodeText('capture,playback'),
        [2, 0, 1],
      );
    });
  });

  group('BleUtf8Codec', () {
    const codec = BleUtf8Codec();

    test('strips NUL padding', () {
      final d = codec.decode(b([0x47, 0x52, 0x00, 0x00]));
      expect(d.value, 'GR');
      expect(d.issues, isEmpty);
    });

    test('reports bytes after the first NUL', () {
      final d = codec.decode(b([0x41, 0x00, 0x42]));
      expect(d.value, 'A');
      expect(d.issues, hasLength(1));
    });

    test('malformed UTF-8 is replaced, not thrown', () {
      final d = codec.decode(b([0xff, 0x41]));
      expect(d.value, '\uFFFDA');
      expect(d.issues, hasLength(1));
    });

    test('encodes raw UTF-8 without terminator', () {
      expect(codec.encode('GR\u3000'), [0x47, 0x52, 0xe3, 0x80, 0x80]);
    });
  });
}
