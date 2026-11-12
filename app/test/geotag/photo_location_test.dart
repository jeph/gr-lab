import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/geotag/photo_location.dart';

import 'photo_files.dart';

/// A made-up position whose degrees, minutes and seconds are known:
/// 35° 30' 15.1234" N, 139° 45' 5.5" W, 40.25 m up.
final _fix = LocationFix(
  latitude: 35 + 30 / 60 + 15.1234 / 3600,
  longitude: -(139 + 45 / 60 + 5.5 / 3600),
  accuracy: 12,
  altitude: 40.25,
  time: DateTime.utc(2026, 11, 5, 1, 2, 3, 456),
);

/// The GPS tags [_fix] becomes, by tag.
const _fixValues = <int, Object>{
  0x00: [2, 3, 0, 0],
  0x01: 'N',
  0x02: [
    [35, 1],
    [30, 1],
    [151234, 10000],
  ],
  0x03: 'W',
  0x04: [
    [139, 1],
    [45, 1],
    [55000, 10000],
  ],
  0x05: [0],
  0x06: [
    [4025, 100],
  ],
  0x07: [
    [1, 1],
    [2, 1],
    [3, 1],
  ],
  0x12: 'WGS-84',
  0x1D: '2026:11:05',
};

/// The `[type, count]` of each of them.
const _fixShapes = <int, List<int>>{
  0x00: [typeByte, 4],
  0x01: [typeAscii, 2],
  0x02: [typeRational, 3],
  0x03: [typeAscii, 2],
  0x04: [typeRational, 3],
  0x05: [typeByte, 1],
  0x06: [typeRational, 1],
  0x07: [typeRational, 3],
  0x12: [typeAscii, 7],
  0x1D: [typeAscii, 11],
};

final _captured = DateTime(2026, 11, 5, 10, 15, 30);

String _order(Endian endian) =>
    endian == Endian.little ? 'little-endian' : 'big-endian';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('photo_location_test');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<File> put(String name, List<int> bytes) =>
      File('${temp.path}/$name').writeAsBytes(bytes, flush: true);

  // Checks that `tiff`, made from `before`, has a GPS directory with the
  // fix after everything `before` holds, and returns it.
  ReadDirectory expectLocated(Uint8List before, Uint8List tiff) {
    final gps = readDirectory(tiff, firstDirectory(tiff)[tagGps].number);
    expect(gps.offset, greaterThanOrEqualTo(before.length));
    expect(gps.values, _fixValues);
    expect(gps.shapes, _fixShapes);
    expect(gps.next, 0);
    for (final tag in gps.tags) {
      final valuesAt = gps[tag].valuesAt;
      if (valuesAt != null) expect(valuesAt, greaterThan(gps.offset));
    }
    return gps;
  }

  for (final endian in [Endian.little, Endian.big]) {
    group('${_order(endian)} TIFF', () {
      test('with a GPS directory holding only its version: a new directory '
          'is appended and only the pointer to it changes', () async {
        // An odd length, as a raw file can have.
        final before = testTiff(endian: endian, imageBytes: 2001);
        expect(before.length.isOdd, isTrue);
        final file = await put('R0000001.DNG', before);

        expect(await writeLocation(file, _fix), PhotoLocationOutcome.written);

        final after = await file.readAsBytes();
        final pointerAt = firstDirectory(before)[tagGps].fieldAt;
        final changed = changedBytes(before, after);
        expect(changed, isNotEmpty);
        expect(
          changed,
          everyElement(inInclusiveRange(pointerAt, pointerAt + 3)),
        );
        final gps = expectLocated(before, after);
        // The byte that brings the directory to an even offset.
        expect(gps.offset, before.length + 1);
        expect(after[before.length], 0);
        expect(namesIn(temp), ['R0000001.DNG']);
        expect(await readCaptureTime(file), _captured);
      });

      test('without a GPS tag: a copy of the first directory with the tag '
          'is appended and only the header points elsewhere', () async {
        final before = testTiff(endian: endian, gps: TestGps.none);
        final file = await put('R0000001.DNG', before);

        expect(await writeLocation(file, _fix), PhotoLocationOutcome.written);

        final after = await file.readAsBytes();
        final changed = changedBytes(before, after);
        expect(changed, isNotEmpty);
        expect(changed, everyElement(inInclusiveRange(4, 7)));
        final was = firstDirectory(before);
        final now = firstDirectory(after);
        expect(now.offset, greaterThanOrEqualTo(before.length));
        expect(now.tags, [
          ...was.tags.where((tag) => tag < tagGps),
          tagGps,
          ...was.tags.where((tag) => tag > tagGps),
        ]);
        expect(now.tags.last, greaterThan(tagGps));
        for (final tag in was.tags) {
          expect(now[tag].raw, was[tag].raw, reason: 'tag $tag');
        }
        expect(now.next, was.next);
        expect(now.next, isNot(0));
        expect(now.shapes[tagGps], [typeLong, 1]);
        expectLocated(before, after);
        expect(namesIn(temp), ['R0000001.DNG']);
        expect(await readCaptureTime(file), _captured);
      });

      test('a file that has a location keeps it', () async {
        final before = testTiff(endian: endian, gps: TestGps.located);
        final file = await put('R0000001.DNG', before);

        expect(
          await writeLocation(file, _fix),
          PhotoLocationOutcome.alreadyLocated,
        );
        expect(await file.readAsBytes(), before);
        expect(namesIn(temp), ['R0000001.DNG']);
      });

      test('a JPEG grows only inside its EXIF segment', () async {
        for (final shape in [TestGps.versionOnly, TestGps.none]) {
          // An odd length of TIFF data, so the directory needs the byte
          // that brings it to an even offset.
          final tiff = testTiff(endian: endian, gps: shape, imageBytes: 65);
          final before = testJpeg(exif: tiff);
          final file = await put('R0000001.JPG', before);

          expect(
            await writeLocation(file, _fix),
            PhotoLocationOutcome.written,
            reason: shape.name,
          );

          final after = await file.readAsBytes();
          final was = exifSegment(before);
          final now = exifSegment(after);
          // Everything before the segment's length and everything after
          // the segment are the same bytes.
          expect(now.start, was.start);
          expect(
            after.sublist(0, now.start + 2),
            before.sublist(0, was.start + 2),
          );
          expect(after.sublist(now.end), before.sublist(was.end));
          expect(now.end - now.start, greaterThan(was.end - was.start));
          expect(after.sublist(now.start + 4, now.start + 10), exifId);
          expect(
            [for (final s in jpegSegments(after)) s.marker],
            [for (final s in jpegSegments(before)) s.marker],
          );

          // Inside it, the TIFF data only gained bytes at its end, but
          // for the pointer.
          final data = exifTiff(after);
          final pointerAt = shape == TestGps.none
              ? 4
              : firstDirectory(tiff)[tagGps].fieldAt;
          final changed = changedBytes(tiff, data);
          expect(changed, isNotEmpty);
          expect(
            changed,
            everyElement(inInclusiveRange(pointerAt, pointerAt + 3)),
          );
          expectLocated(tiff, data);
          expect(namesIn(temp), ['R0000001.JPG']);
          expect(await readCaptureTime(file), _captured);

          expect(
            await writeLocation(file, _fix),
            PhotoLocationOutcome.alreadyLocated,
          );
          expect(await file.readAsBytes(), after);
        }
      });
    });
  }

  test('a second write finds the location of the first', () async {
    final file = await put('R0000001.DNG', testTiff(gps: TestGps.none));
    expect(await writeLocation(file, _fix), PhotoLocationOutcome.written);
    final located = await file.readAsBytes();

    expect(
      await writeLocation(file, _fix),
      PhotoLocationOutcome.alreadyLocated,
    );
    expect(await file.readAsBytes(), located);
  });

  test('other tags of a GPS directory without a position are carried '
      'over', () async {
    final before = testTiff(gps: TestGps.direction);
    final file = await put('R0000001.DNG', before);

    expect(await writeLocation(file, _fix), PhotoLocationOutcome.written);

    final after = await file.readAsBytes();
    final was = readDirectory(before, firstDirectory(before)[tagGps].number);
    final now = readDirectory(after, firstDirectory(after)[tagGps].number);
    expect(now.tags, [0, 1, 2, 3, 4, 5, 6, 7, 0x10, 0x11, 0x12, 0x1D]);
    expect(now[0x10].raw, was[0x10].raw);
    expect(now[0x11].raw, was[0x11].raw);
    expect(now.values, {
      ..._fixValues,
      0x10: 'T',
      0x11: [
        [12345, 100],
      ],
    });
  });

  test('a position without an altitude gets no altitude tags', () async {
    final file = await put('R0000001.DNG', testTiff());
    final fix = LocationFix(
      latitude: _fix.latitude,
      longitude: _fix.longitude,
      accuracy: double.infinity,
      time: _fix.time,
    );

    expect(await writeLocation(file, fix), PhotoLocationOutcome.written);

    final after = await file.readAsBytes();
    final gps = readDirectory(after, firstDirectory(after)[tagGps].number);
    expect(
      gps.values,
      {..._fixValues}
        ..remove(0x05)
        ..remove(0x06),
    );
  });

  test('south, east and below sea level are told by the reference tags, '
      'and the time is written in UTC', () async {
    final file = await put('R0000001.DNG', testTiff());
    final fix = LocationFix(
      latitude: -12.5,
      longitude: 77.25,
      accuracy: 5,
      altitude: -3.5,
      // 23:59:58 on the last day of the year in UTC, whatever the zone.
      time: DateTime.utc(2026, 12, 31, 23, 59, 58).toLocal(),
    );

    expect(await writeLocation(file, fix), PhotoLocationOutcome.written);

    final after = await file.readAsBytes();
    final gps = readDirectory(after, firstDirectory(after)[tagGps].number);
    expect(gps.values, {
      0x00: [2, 3, 0, 0],
      0x01: 'S',
      0x02: [
        [12, 1],
        [30, 1],
        [0, 10000],
      ],
      0x03: 'E',
      0x04: [
        [77, 1],
        [15, 1],
        [0, 10000],
      ],
      0x05: [1],
      0x06: [
        [350, 100],
      ],
      0x07: [
        [23, 1],
        [59, 1],
        [58, 1],
      ],
      0x12: 'WGS-84',
      0x1D: '2026:12:31',
    });
  });

  test('seconds that round up carry into the minutes and degrees', () async {
    final file = await put('R0000001.DNG', testTiff());
    final fix = LocationFix(
      latitude: 35.99999999999,
      longitude: 0,
      accuracy: 5,
      time: _fix.time,
    );

    expect(await writeLocation(file, fix), PhotoLocationOutcome.written);

    final after = await file.readAsBytes();
    final gps = readDirectory(after, firstDirectory(after)[tagGps].number);
    expect(gps[0x02].rationals, [
      [36, 1],
      [0, 1],
      [0, 10000],
    ]);
    expect(gps[0x03].text, 'E');
  });

  group('left as it is, unsupported:', () {
    final exifBase = testTiff(imageBytes: 16).length;
    final cases = <String, List<int>>{
      'a movie': [0, 0, 0, 0x14, ...'ftypqt  '.codeUnits, ...noise(400)],
      'a BigTIFF': [0x49, 0x49, 0x2B, 0x00, 8, 0, 0, 0, ...noise(64)],
      'a big-endian BigTIFF': [0x4D, 0x4D, 0x00, 0x2B, 0, 8, ...noise(64)],
      'an empty file': [],
      'a text file': 'not a photo'.codeUnits,
      'a JPEG without EXIF': testJpeg(),
      // A segment holds 65535 bytes with its length; this one is some
      // fifty short of that, which no GPS directory fits into.
      'a JPEG whose EXIF segment is full': testJpeg(
        exif: testTiff(imageBytes: 16, filler: 0xFFFF - 8 - exifBase - 50),
      ),
    };
    for (final MapEntry(key: what, value: bytes) in cases.entries) {
      test(what, () async {
        final file = await put('file', bytes);
        expect(
          await writeLocation(file, _fix),
          PhotoLocationOutcome.unsupported,
        );
        expect(await file.readAsBytes(), bytes);
        expect(namesIn(temp), ['file']);
      });
    }

    test('the full EXIF segment is one a location nearly fits', () {
      final segment = exifSegment(Uint8List.fromList(cases.values.last));
      expect(segment.end - segment.start - 2, inInclusiveRange(65400, 65535));
    });
  });

  group('left as it is, failed:', () {
    final tiff = testTiff();
    final first = firstDirectory(tiff);
    final gpsEntryAt = first[tagGps].fieldAt - 8;
    final data = testTiff(imageBytes: 64);
    final jpeg = testJpeg(exif: data);
    final exif = exifSegment(jpeg);
    final cases = <String, Uint8List>{
      'a TIFF with only its header': tiff.sublist(0, 8),
      'a TIFF cut inside its first directory': tiff.sublist(
        0,
        first.offset + 20,
      ),
      'a TIFF whose first directory is past its end': withLong(
        tiff,
        4,
        tiff.length + 100,
      ),
      'a TIFF whose first directory is in its header': withLong(tiff, 4, 2),
      'a TIFF whose first directory has more entries than fit': withShort(
        tiff,
        first.offset,
        60000,
      ),
      'a TIFF whose GPS directory is past its end': withLong(
        tiff,
        first[tagGps].fieldAt,
        0x7FFFFFF0,
      ),
      'a TIFF whose GPS tag is not an offset': withShort(
        tiff,
        gpsEntryAt + 2,
        typeShort,
      ),
      'a TIFF whose GPS tag has two values': withLong(tiff, gpsEntryAt + 4, 2),
      // Nothing the location needs is wrong in these; the file is still
      // not one to add to.
      'a TIFF cut inside its image data': tiff.sublist(0, tiff.length - 10),
      'a TIFF whose image data is said to be longer than it is': withLong(
        tiff,
        first[0x0117].fieldAt,
        0x100000,
      ),
      'a TIFF whose time is past its end': withLong(
        tiff,
        first[tagDateTime].fieldAt,
        tiff.length - 4,
      ),
      'a TIFF with a value longer than the file': withLong(
        tiff,
        first[0x010F].fieldAt - 4,
        0x7FFFFFFF,
      ),
      'a TIFF whose second directory is past its end': withLong(
        tiff,
        first.offset + 2 + 12 * first.tags.length,
        tiff.length + 100,
      ),
      'a TIFF whose EXIF directory is past its end': withLong(
        tiff,
        first[tagExif].fieldAt,
        0x7FFFFFF0,
      ),
      'a JPEG cut right after its EXIF segment': jpeg.sublist(0, exif.end),
      'a JPEG cut inside a later segment': jpeg.sublist(0, exif.end + 10),
      'a JPEG cut inside its image data': jpeg.sublist(
        0,
        jpeg.length - jpegTrailer.length - 100,
      ),
      'a JPEG without its end marker': jpeg.sublist(
        0,
        jpeg.length - jpegTrailer.length,
      ),
      'a JPEG whose EXIF points past its end': testJpeg(
        exif: withLong(data, firstDirectory(data)[0x0117].fieldAt, 5000),
      ),
      'a JPEG cut inside its EXIF segment': jpeg.sublist(0, exif.start + 40),
      'a JPEG that ends before its image data': jpeg.sublist(0, exif.start),
      'a JPEG with something else where a marker belongs': Uint8List.fromList([
        ...jpeg.sublist(0, exif.start),
        0x00,
        ...jpeg.sublist(exif.start + 1),
      ]),
      'a JPEG whose EXIF data is not TIFF': Uint8List.fromList([
        ...jpeg.sublist(0, exif.start + 10),
        ...List.filled(8, 0),
        ...jpeg.sublist(exif.start + 18),
      ]),
    };
    for (final MapEntry(key: what, value: bytes) in cases.entries) {
      test(what, () async {
        final file = await put('file', bytes);
        expect(await writeLocation(file, _fix), PhotoLocationOutcome.failed);
        expect(await file.readAsBytes(), bytes);
        expect(namesIn(temp), ['file']);
        // Reading the time of such a file gives none at worst.
        await readCaptureTime(file);
      });
    }

    for (final (what, latitude, longitude) in [
      ('north of the pole', 90.5, 10.0),
      ('past the date line', 10.0, -180.5),
      ('not a number', double.nan, 10.0),
    ]) {
      test('a position $what', () async {
        final before = testTiff();
        final file = await put('R0000001.DNG', before);
        final fix = LocationFix(
          latitude: latitude,
          longitude: longitude,
          accuracy: 5,
          time: _fix.time,
        );
        expect(await writeLocation(file, fix), PhotoLocationOutcome.failed);
        expect(await file.readAsBytes(), before);
        expect(namesIn(temp), ['R0000001.DNG']);
      });
    }

    test('a file that is not there', () async {
      final file = File('${temp.path}/R0000009.DNG');
      expect(await writeLocation(file, _fix), PhotoLocationOutcome.failed);
      expect(await readCaptureTime(file), isNull);
      expect(namesIn(temp), isEmpty);
    });
  });

  group('readCaptureTime', () {
    for (final endian in [Endian.little, Endian.big]) {
      test('reads DateTimeOriginal of a ${_order(endian)} TIFF and JPEG as '
          'local time', () async {
        // DateTimeOriginal is 10:15:30 on the 5th.
        final tiff = testTiff(endian: endian, dateTime: '2026:11:06 08:00:00');
        final expected = DateTime(2026, 11, 5, 10, 15, 30);
        expect(expected.isUtc, isFalse);
        expect(await readCaptureTime(await put('a.DNG', tiff)), expected);
        expect(
          await readCaptureTime(await put('a.JPG', testJpeg(exif: tiff))),
          expected,
        );
      });
    }

    test('falls back to DateTime of the first directory', () async {
      final expected = DateTime(2026, 11, 6, 8);
      for (final original in [
        null,
        '0000:00:00 00:00:00',
        '2026:13:05 10:15:30',
        '2026:02:30 10:15:30',
        '2026:11:05 24:00:00',
        '                   ',
      ]) {
        final tiff = testTiff(
          original: original,
          dateTime: '2026:11:06 08:00:00',
        );
        expect(
          await readCaptureTime(await put('a.DNG', tiff)),
          expected,
          reason: '$original',
        );
      }
    });

    test('falls back when the EXIF directory is past the end', () async {
      final tiff = testTiff(dateTime: '2026:11:06 08:00:00');
      final exifAt = firstDirectory(tiff)[tagExif].fieldAt;
      final broken = withLong(tiff, exifAt, 0x7FFFFFF0);
      expect(
        await readCaptureTime(await put('a.DNG', broken)),
        DateTime(2026, 11, 6, 8),
      );
    });

    test('is null for a file without a time or of another kind', () async {
      final none = testTiff(original: null, dateTime: null);
      final zeros = testTiff(
        original: '0000:00:00 00:00:00',
        dateTime: '0000:00:00 00:00:00',
      );
      expect(await readCaptureTime(await put('a.DNG', none)), isNull);
      expect(await readCaptureTime(await put('b.DNG', zeros)), isNull);
      expect(await readCaptureTime(await put('c.JPG', testJpeg())), isNull);
      expect(
        await readCaptureTime(
          await put('d.MOV', [0, 0, 0, 0x14, ...'ftypqt  '.codeUnits]),
        ),
        isNull,
      );
      expect(await readCaptureTime(await put('e.DNG', const [])), isNull);
    });
  });
}
