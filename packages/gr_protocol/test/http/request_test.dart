import 'dart:convert';

import 'package:gr_protocol/src/http/http.dart';
import 'package:gr_protocol/src/http/sha256.dart';
import 'package:test/test.dart';

void main() {
  group('encodeKeyValueBody', () {
    test('keeps order and literal characters, no URL-encoding', () {
      expect(encodeKeyValueBody({'xv': '+0.3'}), 'xv=+0.3');
      expect(
        encodeKeyValueBody({
          'tv': '1.250',
          'WBMode': 'daylight',
          'pos': '50,50',
        }),
        'tv=1.250&WBMode=daylight&pos=50,50',
      );
      expect(
        encodeKeyValueBody({'ssid': 'GR cam', 'key': 'p@ss=w%rd'}),
        'ssid=GR cam&key=p@ss=w%rd',
      );
      expect(encodeKeyValueBody({}), '');
      expect(encodeKeyValueBodyBytes({'k': 'é'}), utf8.encode('k=é'));
    });

    test('rejects what cannot be represented unescaped', () {
      expect(() => encodeKeyValueBody({'a=b': 'c'}), throwsArgumentError);
      expect(() => encodeKeyValueBody({'': 'c'}), throwsArgumentError);
      expect(() => encodeKeyValueBody({'a': 'b&c'}), throwsArgumentError);
      expect(() => encodeKeyValueBody({'a': 'b\nc'}), throwsArgumentError);
    });
  });

  group('shootBody', () {
    test('matches Image Sync and GR II forms', () {
      expect(shootBody(), '');
      expect(shootBody(af: GrShootAf.on), 'af=on');
      expect(
        shootBody(af: GrShootAf.on, pos: GrFocusPoint(50, 50)),
        'af=on&pos=50,50',
      );
      expect(shootBody(af: GrShootAf.camera), 'af=camera');
      expect(shootBody(pos: GrFocusPoint(0, 100)), 'pos=0,100');
    });
  });

  group('GrFocusPoint', () {
    test('parses X,Y percent and rounds normalized input', () {
      expect(GrFocusPoint.parse('50,50').wire, '50,50');
      expect(GrFocusPoint.parse(' 7 , 93 ').wire, '7,93');
      expect(GrFocusPoint.normalized(0.125, 0.875).wire, '13,88');
    });

    test('rejects malformed and out-of-range input', () {
      for (final bad in [
        '50',
        '50;50',
        '-1,5',
        '101,5',
        '5,101',
        'a,b',
        '1.5,2',
      ]) {
        expect(
          () => GrFocusPoint.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
      expect(() => GrFocusPoint(0, 101), throwsRangeError);
    });

    test('effective area is centered; default matches Image Sync', () {
      expect(GrFocusPoint(50, 50).withinEffectiveArea([20, 20]), isTrue);
      expect(GrFocusPoint(60, 50).withinEffectiveArea([20, 20]), isTrue);
      expect(GrFocusPoint(61, 50).withinEffectiveArea([20, 20]), isFalse);
      expect(GrFocusPoint(12, 13).withinEffectiveArea(null), isTrue);
      expect(GrFocusPoint(11, 50).withinEffectiveArea(null), isFalse);
      expect(GrFocusPoint(50, 88).withinEffectiveArea(null), isFalse);
    });
  });

  group('GrPhotoPath', () {
    test('parses dir/file and extension', () {
      final p = GrPhotoPath.parse('100RICOH/R0000001.jpg');
      expect((p.dir, p.file, p.extension), ('100RICOH', 'R0000001.jpg', 'JPG'));
    });

    test('rejects malformed user input', () {
      for (final bad in [
        'R0000001.JPG',
        'a/b/c',
        '/b',
        'a/',
        'a/b?x',
        'a b/c',
      ]) {
        expect(
          () => GrPhotoPath.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('camera filepaths strip ?xs and a leading slash, never throw', () {
      expect(
        GrPhotoPath.tryParseCamera('100RICOH/R1.JPG?xs'),
        GrPhotoPath('100RICOH', 'R1.JPG'),
      );
      expect(
        GrPhotoPath.tryParseCamera('/100RICOH/R1.JPG'),
        GrPhotoPath('100RICOH', 'R1.JPG'),
      );
      expect(GrPhotoPath.tryParseCamera('nonsense'), isNull);
    });
  });

  test('storage ids are validated', () {
    expect(GrStorageId.validate('sd1'), 'sd1');
    expect(() => GrStorageId.validate('sd1&x=1'), throwsFormatException);
    expect(() => GrStorageId.validate(''), throwsFormatException);
  });

  test('query values keep / , : literal like the apps', () {
    expect(encodeQuery({}), isNull);
    expect(
      encodeQuery({
        'storage': 'sd1',
        'after': '100RICOH/R0000001.JPG',
        'pos': '1,2',
      }),
      'storage=sd1&after=100RICOH/R0000001.JPG&pos=1,2',
    );
    expect(encodeQuery({'reso': 'a b&c'}), 'reso=a+b%26c');
  });

  group('sha256', () {
    test('FIPS 180-4 vectors', () {
      expect(
        hexLower(sha256(const [])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        hexLower(sha256(ascii.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        hexLower(
          sha256(
            ascii.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
            ),
          ),
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      expect(
        hexLower(sha256(List.filled(1000000, 0x61))),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });
}
