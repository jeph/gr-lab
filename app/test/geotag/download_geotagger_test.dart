import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/geotag/download_geotagger.dart';
import 'package:grphoto/src/geotag/location_history.dart';

import 'photo_files.dart';

/// When the synthetic photos were taken ([testTiff]'s capture time), by
/// the camera's clock: a local time.
final _captured = DateTime(2026, 11, 5, 10, 15, 30);

const _minute = Duration(minutes: 1);

/// Serial number of the camera the files were downloaded from.
const _serial = '1234567';

/// A made-up position, 12° 15' N 34° 30' E, taken at [time].
LocationFix _at(DateTime time) => LocationFix(
  latitude: 12.25,
  longitude: 34.5,
  accuracy: 10,
  altitude: 100,
  time: time,
);

const _movie = [0, 0, 0, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74, 0x20, 0x20];

void main() {
  late Directory temp;
  late LocationHistory history;
  late List<String> lines;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('download_geotagger_test');
    await Directory('${temp.path}/shot').create();
    lines = [];
  });

  tearDown(() => temp.delete(recursive: true));

  // A test a day after the photos were taken, with an empty history.
  void geotagTest(String description, Future<void> Function() body) {
    final dayAfter = Clock.fixed(_captured.add(const Duration(days: 1)));
    test(
      description,
      () => withClock(dayAfter, () async {
        history = await LocationHistory.open(Directory('${temp.path}/history'));
        await body();
      }),
    );
  }

  Future<File> put(String name, List<int> bytes) =>
      File('${temp.path}/shot/$name').writeAsBytes(bytes, flush: true);

  DownloadGeotagger geotagger({
    bool Function(String serial)? enabled,
    Future<void> Function()? beforeMatch,
    void Function(String line)? log,
  }) => DownloadGeotagger(
    history: history,
    enabled: enabled ?? (serial) => serial == _serial,
    beforeMatch: beforeMatch,
    log: log ?? lines.add,
  );

  // The GPS directory of `tiff`.
  ReadDirectory gpsOf(Uint8List tiff) =>
      readDirectory(tiff, firstDirectory(tiff)[tagGps].number);

  // Checks that `gps` holds the position `_at` gives for `time`.
  void expectPosition(ReadDirectory gps, DateTime time) {
    final utc = time.toUtc();
    String two(int value) => '$value'.padLeft(2, '0');
    expect(gps.values, {
      0x00: [2, 3, 0, 0],
      0x01: 'N',
      0x02: [
        [12, 1],
        [15, 1],
        [0, 10000],
      ],
      0x03: 'E',
      0x04: [
        [34, 1],
        [30, 1],
        [0, 10000],
      ],
      0x05: [0],
      0x06: [
        [10000, 100],
      ],
      0x07: [
        [utc.hour, 1],
        [utc.minute, 1],
        [utc.second, 1],
      ],
      0x12: 'WGS-84',
      0x1D: '${utc.year}:${two(utc.month)}:${two(utc.day)}',
    });
  }

  geotagTest('gives the JPEG and DNG of a shot the nearest position and '
      'leaves every other file as it is', () async {
    final before = _captured.subtract(_minute * 2);
    await history.add([
      _at(_captured.subtract(_minute * 30)),
      _at(before),
      _at(_captured.add(_minute * 5)),
    ]);
    final located = testJpeg(
      exif: testTiff(gps: TestGps.located, imageBytes: 64),
    );
    final plain = testJpeg();
    final files = [
      await put('R0000001.JPG', testJpeg(exif: testTiff(imageBytes: 64))),
      await put('R0000001.DNG', testTiff(endian: Endian.big)),
      await put('R0000002.JPG', located),
      await put('R0000003.MOV', _movie),
      await put('R0000004.JPG', plain),
    ];

    await geotagger().tag(_serial, files);

    expect(lines, [
      'Geotag R0000001.JPG: written',
      'Geotag R0000001.DNG: written',
      'Geotag R0000002.JPG: alreadyLocated',
      'Geotag R0000003.MOV: no capture time',
      'Geotag R0000004.JPG: no capture time',
    ]);
    // The capture time is the camera's local time; the position's time
    // is written as the phone took it.
    expectPosition(gpsOf(exifTiff(await files[0].readAsBytes())), before);
    expectPosition(gpsOf(await files[1].readAsBytes()), before);
    expect(await files[2].readAsBytes(), located);
    expect(await files[3].readAsBytes(), _movie);
    expect(await files[4].readAsBytes(), plain);
    expect(namesIn(Directory('${temp.path}/shot')), [
      'R0000001.DNG',
      'R0000001.JPG',
      'R0000002.JPG',
      'R0000003.MOV',
      'R0000004.JPG',
    ]);
    // What happened is logged, never where.
    expect(lines.join('\n'), isNot(contains('12.25')));
    expect(lines.join('\n'), isNot(contains('34.5')));
  });

  geotagTest('does nothing while it is off', () async {
    await history.add([_at(_captured)]);
    final bytes = testTiff();
    final file = await put('R0000001.DNG', bytes);
    var prepared = 0;

    await geotagger(
      enabled: (_) => false,
      beforeMatch: () async => prepared++,
    ).tag(_serial, [file]);

    expect(await file.readAsBytes(), bytes);
    expect(prepared, 0);
    expect(lines, isEmpty);
  });

  geotagTest('asks whether it is on for the camera the files came from, '
      'and leaves the files of a camera that has it off', () async {
    await history.add([_at(_captured)]);
    final bytes = testTiff();
    final file = await put('R0000001.DNG', bytes);
    final asked = <String>[];
    final tagger = geotagger(
      enabled: (serial) {
        asked.add(serial);
        return serial == _serial;
      },
    );

    await tagger.tag('7654321', [file]);
    expect(asked, ['7654321']);
    expect(await file.readAsBytes(), bytes);
    expect(lines, isEmpty);

    await tagger.tag(_serial, [file]);
    expect(asked, ['7654321', _serial]);
    expect(lines, ['Geotag R0000001.DNG: written']);
  });

  geotagTest('asks whether it is on at each call', () async {
    await history.add([_at(_captured)]);
    final file = await put('R0000001.DNG', testTiff());
    var on = false;
    final tagger = geotagger(enabled: (_) => on);

    await tagger.tag(_serial, [file]);
    expect(lines, isEmpty);
    on = true;
    await tagger.tag(_serial, [file]);
    expect(lines, ['Geotag R0000001.DNG: written']);
  });

  geotagTest('runs beforeMatch once per call that has a photo to match, '
      'before the history is asked', () async {
    var prepared = 0;
    final tagger = geotagger(
      beforeMatch: () async {
        prepared++;
        // What the phone recorded and had not handed over yet.
        await history.add([_at(_captured.add(_minute))]);
      },
    );
    final raw = await put('R0000001.DNG', testTiff());
    final jpeg = await put(
      'R0000001.JPG',
      testJpeg(exif: testTiff(imageBytes: 64)),
    );
    final movie = await put('R0000002.MOV', _movie);

    await tagger.tag(_serial, [jpeg, raw]);
    expect(prepared, 1);
    expect(lines, [
      'Geotag R0000001.JPG: written',
      'Geotag R0000001.DNG: written',
    ]);

    await tagger.tag(_serial, [movie]);
    expect(prepared, 1);

    await tagger.tag(_serial, [movie, raw]);
    expect(prepared, 2);
    expect(lines.last, 'Geotag R0000001.DNG: alreadyLocated');
  });

  geotagTest('a photo the history has no position for stays as it '
      'is', () async {
    // Nothing from before the photo, and the next more than 10 minutes on.
    await history.add([_at(_captured.add(_minute * 11))]);
    final bytes = testTiff();
    final file = await put('R0000001.DNG', bytes);

    await geotagger().tag(_serial, [file]);

    expect(lines, ['Geotag R0000001.DNG: no position in the history']);
    expect(await file.readAsBytes(), bytes);
  });

  geotagTest('a file that cannot be written does not stop the '
      'others', () async {
    await history.add([_at(_captured)]);
    final tiff = testTiff();
    final broken = withLong(
      tiff,
      firstDirectory(tiff)[tagGps].fieldAt,
      0x7FFFFFF0,
    );
    final cut = tiff.sublist(0, 20);
    final files = [
      await put('R0000001.DNG', broken),
      await put('R0000002.DNG', cut),
      File('${temp.path}/shot/R0000003.DNG'),
      await put('R0000004.DNG', tiff),
    ];

    await geotagger().tag(_serial, files);

    expect(lines, [
      'Geotag R0000001.DNG: failed',
      'Geotag R0000002.DNG: no capture time',
      'Geotag R0000003.DNG: no capture time',
      'Geotag R0000004.DNG: written',
    ]);
    expect(await files[0].readAsBytes(), broken);
    expect(await files[1].readAsBytes(), cut);
    expect(files[2].existsSync(), isFalse);
  });

  geotagTest('never throws', () async {
    await history.add([_at(_captured)]);
    final file = await put('R0000001.DNG', testTiff());

    // What prepares the history fails: the photo is matched against what
    // the history has.
    await geotagger(beforeMatch: () async => throw StateError('no phone'))
        .tag(_serial, [file]);
    expect(lines, [
      'Geotag: preparing the history failed (StateError)',
      'Geotag R0000001.DNG: written',
    ]);

    await geotagger(enabled: (_) => throw StateError('no settings'))
        .tag(_serial, [file]);
    await geotagger(log: (line) => throw StateError('no log'))
        .tag(_serial, [file]);
    await geotagger().tag(_serial, const []);
  });
}
