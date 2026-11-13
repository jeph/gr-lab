import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_camera/src/library/camera_library.dart';

void main() {
  group('parseCameraTime', () {
    test('accepts ISO and EXIF forms as local wall time', () {
      expect(
        parseCameraTime('2026-11-05T14:03:22'),
        DateTime(2026, 11, 5, 14, 3, 22),
      );
      expect(
        parseCameraTime('2026:11:05 14:03:22'),
        DateTime(2026, 11, 5, 14, 3, 22),
      );
      expect(parseCameraTime(''), isNull);
      expect(parseCameraTime('soon'), isNull);
    });
  });

  group('listedStorages', () {
    GrProps props(List<Map<String, Object?>> storages) =>
        GrProps({'errCode': 200, 'storages': storages});

    test('lists each equipped and available storage of a two-storage '
        'camera', () {
      expect(
        listedStorages(
          props([
            {'name': 'in', 'equipped': true},
            {'name': 'sd1', 'equipped': true},
          ]),
        ),
        ['in', 'sd1'],
      );
      expect(
        listedStorages(
          props([
            {'name': 'in', 'equipped': true},
            {'name': 'sd1', 'equipped': false},
          ]),
        ),
        ['in'],
      );
      expect(
        listedStorages(
          props([
            {'name': 'in', 'equipped': true, 'available': true},
            {'name': 'sd1', 'equipped': true, 'available': false},
          ]),
        ),
        ['in'],
      );
    });

    test('a one-storage camera is listed without storage=', () {
      expect(
        listedStorages(
          props([
            {'name': 'sd1', 'equipped': true},
          ]),
        ),
        [null],
      );
      expect(listedStorages(null), [null]);
    });
  });

  group('cached listing', () {
    const serial = '1234567';
    late Directory cache;
    final jpeg = CameraFile(
      GrStorageId.sd,
      GrPhotoPath('100RICOH', 'R0000001.JPG'),
    );
    final movie = CameraFile(null, GrPhotoPath('100RICOH', 'R0000002.MOV'));
    final listedAt = DateTime(2026, 11, 5, 18, 2, 7);

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('gr_camera_listing_');
    });

    tearDown(() => cache.delete(recursive: true));

    test('none without a file, or with one that is not JSON', () async {
      expect(await readCachedListing(cache, serial), isNull);
      final file = File('${cache.path}/$serial/library.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('{not json');
      expect(await readCachedListing(cache, serial), isNull);
    });

    test('reads back what was written, per camera', () async {
      await writeCachedListing(cache, serial, (
        files: [jpeg, movie],
        info: {
          jpeg.key: FileInfo(
            taken: listedAt,
            size: 4096,
            orientation: 6,
            location: const GrPhotoLocation(35.681236, -139.767125),
          ),
          movie.key: const FileInfo(duration: Duration(seconds: 14)),
        },
        listedAt: listedAt,
      ));
      final read = (await readCachedListing(cache, serial))!;
      expect(read.files, [jpeg, movie]);
      expect(read.listedAt, listedAt);
      expect(read.info[jpeg.key]?.taken, listedAt);
      expect(read.info[jpeg.key]?.size, 4096);
      expect(read.info[jpeg.key]?.orientation, 6);
      expect(
        read.info[jpeg.key]?.location,
        const GrPhotoLocation(35.681236, -139.767125),
      );
      expect(read.info[movie.key]?.duration, const Duration(seconds: 14));
      expect(read.info[movie.key]?.location, isNull);
      expect(await readCachedListing(cache, 'another'), isNull);
      expect(Directory('${cache.path}/$serial').listSync().map((e) => e.path), [
        '${cache.path}/$serial/library.json',
      ], reason: 'no temporary file left behind');
    });

    test('info of another version is dropped; the listing stays', () async {
      await writeCachedListing(cache, serial, (
        files: [jpeg],
        info: {jpeg.key: const FileInfo(size: 4096)},
        listedAt: null,
      ));
      final file = File('${cache.path}/$serial/library.json');
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      await file.writeAsString(jsonEncode({...json, 'version': 1}));
      final read = (await readCachedListing(cache, serial))!;
      expect(read.files, [jpeg]);
      expect(read.info, isEmpty);
      expect(read.listedAt, isNull);
    });
  });
}
