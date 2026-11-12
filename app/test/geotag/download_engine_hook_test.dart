import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart' show GrHttpClient;
import 'package:grphoto/src/downloads/download_engine.dart';
import 'package:grphoto/src/geotag/download_geotagger.dart';
import 'package:grphoto/src/geotag/location_history.dart';
import 'package:grphoto/src/library/shot.dart';
import 'package:grphoto/src/services.dart';

import '../support/test_app.dart';
import 'photo_files.dart';

const _serial = '1234567';

/// When the synthetic photos were taken ([testTiff]'s capture time).
final _captured = DateTime(2026, 11, 5, 10, 15, 30);

/// A RAW+JPEG pair and a movie on the SD card.
List<FakePhoto> _card() => [
  FakePhoto('100RICOH', 'R0000001.JPG', _captured),
  FakePhoto('100RICOH', 'R0000001.DNG', _captured),
  FakePhoto(
    '100RICOH',
    'R0000002.MOV',
    _captured,
    videoLength: const Duration(seconds: 12),
  ),
];

/// Polls [condition] in real time.
Future<void> _until(bool Function() condition, {required String reason}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      fail('Timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Keeps the bytes of every saved file instead of writing to the photo
/// library.
final class _KeepingSaver implements MediaSaver {
  final Map<String, Uint8List> saved = {};

  @override
  Future<void> saveShot(List<File> files, {required String album}) async {
    for (final file in files) {
      saved[file.uri.pathSegments.last] = await file.readAsBytes();
    }
  }
}

/// A simulated camera whose photos are [testJpeg] and [testTiff] files,
/// and what a [DownloadEngine] needs around it.
final class _Harness {
  new _(this.camera, this.http, this.root, this.link);

  static Future<_Harness> start() async {
    HttpOverrides.global = null;
    final other = syntheticMedia(movieBytes: 8 * 1024);
    final camera = FakeGrCamera(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: _card()),
      media: (photo, size) async {
        if (size != GrImageSize.full) return await other(photo, size);
        return switch (photo.extension) {
          'JPG' => testJpeg(exif: testTiff(imageBytes: 64)),
          'DNG' => testTiff(imageBytes: 4001),
          _ => await other(photo, size),
        };
      },
    );
    await camera.startHttp();
    final http = camera.httpClient('127.0.0.1', null);
    final root = await Directory.systemTemp.createTemp('grphoto_hook_');
    final link = ValueNotifier<CameraLibrary?>(
      CameraLibrary.overHttp(
        http,
        serial: _serial,
        storages: const [GrStorageId.internal, GrStorageId.sd],
      ),
    );
    return _Harness._(camera, http, root, link);
  }

  final FakeGrCamera camera;
  final GrHttpClient http;
  final Directory root;
  final ValueNotifier<CameraLibrary?> link;
  final List<DownloadEngine> _engines = [];

  DownloadEngine engine(
    MediaSaver media, {
    Future<void> Function(String serial, List<File> files)? beforeSave,
  }) {
    final engine = DownloadEngine(
      dataDir: Directory('${root.path}/data'),
      cacheDir: Directory('${root.path}/cache'),
      media: media,
      link: link,
      album: 'GR Photo',
      beforeSave: beforeSave,
      transportGrace: Duration.zero,
      progressInterval: Duration.zero,
    );
    _engines.add(engine);
    return engine;
  }

  Shot shot(String base) =>
      groupShots([for (final p in camera.photos) CameraFile(p.storage, p.path)])
          .firstWhere((s) => s.base == base);

  Future<void> close() async {
    for (final engine in _engines) {
      engine.dispose();
      // A job in its last steps still deletes its copies and writes the
      // queue, into the folders deleted below.
      await engine.whenIdle();
      await engine.flush();
    }
    link.dispose();
    http.close(force: true);
    await camera.close();
    await root.delete(recursive: true);
  }
}

void main() {
  late _Harness h;

  setUp(() async => h = await _Harness.start());

  tearDown(() => h.close());

  test('beforeSave gets the copies of a shot once all are on the phone, '
      'and what it makes of them is what the photo library gets', () async {
    final media = RecordingMediaSaver();
    final seen = <(String, int)>[];
    final cameras = <String>[];
    var calls = 0;
    var savedBefore = 0;
    final engine = h.engine(
      media,
      beforeSave: (serial, files) async {
        calls++;
        cameras.add(serial);
        savedBefore += media.shots.length;
        for (final file in files) {
          seen.add((file.uri.pathSegments.last, file.lengthSync()));
          await file.writeAsBytes([1], mode: FileMode.append, flush: true);
        }
      },
    );

    await engine.enqueue(_serial, [h.shot('R0000001')]);
    await engine.whenIdle();

    final tiff = testTiff(imageBytes: 4001);
    final jpeg = testJpeg(exif: testTiff(imageBytes: 64));
    expect(calls, 1);
    expect(cameras, [_serial]);
    expect(savedBefore, 0, reason: 'nothing was saved yet');
    expect(seen, [
      ('R0000001.JPG', jpeg.length),
      ('R0000001.DNG', tiff.length),
    ]);
    final saved = media.shots.single;
    expect(saved.names, ['R0000001.JPG', 'R0000001.DNG']);
    expect(saved.sizes, [jpeg.length + 1, tiff.length + 1]);
    expect(engine.jobs, isEmpty);
    expect(engine.isShotDownloaded(_serial, h.shot('R0000001')), isTrue);
  });

  test('saving waits for beforeSave, and a cancel meanwhile stops the '
      'shot before it is saved', () async {
    final media = RecordingMediaSaver();
    final gate = Completer<void>();
    var waiting = 0;
    final engine = h.engine(
      media,
      beforeSave: (serial, files) async {
        waiting++;
        await gate.future;
      },
    );

    await engine.enqueue(_serial, [h.shot('R0000001'), h.shot('R0000002')]);
    await _until(() => waiting == 1, reason: 'beforeSave');
    // Long enough for a save that did not wait to have happened.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(media.shots, isEmpty);
    expect(engine.current?.shot.base, 'R0000001');

    engine.cancel(engine.current!);
    gate.complete();
    await engine.whenIdle();

    expect(waiting, 2);
    expect(
      [for (final shot in media.shots) shot.names],
      [
        ['R0000002.MOV'],
      ],
    );
    expect(engine.jobs, isEmpty);
    expect(engine.isShotDownloaded(_serial, h.shot('R0000001')), isFalse);
  });

  test('a beforeSave that fails does not fail the download', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);
    final media = RecordingMediaSaver();
    final engine = h.engine(
      media,
      beforeSave: (serial, files) async => throw StateError('no location'),
    );

    await engine.enqueue(_serial, [h.shot('R0000001'), h.shot('R0000002')]);
    await engine.whenIdle();

    expect(
      [for (final shot in media.shots) shot.names],
      [
        ['R0000001.JPG', 'R0000001.DNG'],
        ['R0000002.MOV'],
      ],
    );
    expect(engine.jobs, isEmpty);
    expect(engine.failedCount, 0);
    expect(
      printed.where((line) => line.contains('for saving failed')),
      hasLength(2),
    );
  });

  test('a beforeSave that throws at once does not fail the download '
      'either', () async {
    final media = RecordingMediaSaver();
    final engine = h.engine(
      media,
      beforeSave: (serial, files) => throw StateError('no location'),
    );

    await engine.enqueue(_serial, [h.shot('R0000001')]);
    await engine.whenIdle();

    expect(media.shots, hasLength(1));
    expect(engine.jobs, isEmpty);
  });

  test('without beforeSave a shot is saved as the camera sent it', () async {
    final media = _KeepingSaver();
    final engine = h.engine(media);

    await engine.enqueue(_serial, [h.shot('R0000001')]);
    await engine.whenIdle();

    expect(media.saved, {
      'R0000001.JPG': testJpeg(exif: testTiff(imageBytes: 64)),
      'R0000001.DNG': testTiff(imageBytes: 4001),
    });
  });

  test('with the geotagger as beforeSave, a downloaded pair reaches the '
      'photo library with its location and a movie as it was', () {
    final dayAfter = Clock.fixed(_captured.add(const Duration(days: 1)));
    return withClock(dayAfter, () async {
      final history = await LocationHistory.open(
        Directory('${h.root.path}/data/location-history'),
      );
      await history.add([
        LocationFix(
          latitude: 12.25,
          longitude: 34.5,
          accuracy: 10,
          time: _captured.subtract(const Duration(minutes: 3)),
        ),
      ]);
      final lines = <String>[];
      final media = _KeepingSaver();
      final engine = h.engine(
        media,
        beforeSave: DownloadGeotagger(
          history: history,
          enabled: (serial) => serial == _serial,
          log: lines.add,
        ).tag,
      );

      await engine.enqueue(_serial, [h.shot('R0000001'), h.shot('R0000002')]);
      await engine.whenIdle();

      expect(lines, [
        'Geotag R0000001.JPG: written',
        'Geotag R0000001.DNG: written',
        'Geotag R0000002.MOV: no capture time',
      ]);
      expect(engine.jobs, isEmpty);
      for (final tiff in [
        exifTiff(media.saved['R0000001.JPG']!),
        media.saved['R0000001.DNG']!,
      ]) {
        final gps = readDirectory(tiff, firstDirectory(tiff)[tagGps].number);
        expect(gps[0x01].text, 'N');
        expect(gps[0x02].rationals, [
          [12, 1],
          [15, 1],
          [0, 10000],
        ]);
        expect(gps[0x03].text, 'E');
        expect(gps[0x04].rationals, [
          [34, 1],
          [30, 1],
          [0, 10000],
        ]);
      }
      // The image data of the raw file is where it was, byte for byte.
      final sent = testTiff(imageBytes: 4001);
      final raw = media.saved['R0000001.DNG']!;
      final pointerAt = firstDirectory(sent)[tagGps].fieldAt;
      expect(
        changedBytes(sent, raw),
        everyElement(inInclusiveRange(pointerAt, pointerAt + 3)),
      );
      expect(media.saved['R0000002.MOV'], hasLength(greaterThan(8 * 1024 - 1)));
    });
  });
}
