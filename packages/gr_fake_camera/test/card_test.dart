import 'dart:typed_data';

import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('the default card is realistic: ~60 files, pairs, DNG-only, '
      'movies, two folders, several days', () {
    final card = FakePhoto.defaultCard();
    expect(card.length, inInclusiveRange(55, 65));
    final shots = <String, Set<String>>{};
    for (final p in card) {
      (shots['${p.dir}/${p.baseName}'] ??= {}).add(p.extension);
    }
    expect(shots.values, contains(equals({'JPG', 'DNG'})));
    expect(shots.values, contains(equals({'JPG'})));
    expect(shots.values, contains(equals({'DNG'})));
    expect(card.where((p) => p.isVideo), hasLength(3));
    expect(card.where((p) => p.isVideo).map((p) => p.videoLength), [
      const Duration(seconds: 12),
      const Duration(seconds: 31),
      const Duration(seconds: 64),
    ]);
    // Portrait frames are held both ways; everything else is upright.
    expect(card.where((p) => p.portrait).map((p) => p.orientation).toSet(), {
      6,
      8,
    });
    expect(card.where((p) => p.isVideo).every((p) => p.orientation == 1), true);
    expect(card.map((p) => p.dir).toSet(), {'100RICOH', '101RICOH'});
    expect(card.map((p) => p.storage).toSet(), {GrStorageId.sd});
    final days = {
      for (final p in card)
        DateTime(p.dateTime.year, p.dateTime.month, p.dateTime.day),
    };
    expect(days, hasLength(6));
    expect(days.reduce((a, b) => a.isAfter(b) ? a : b), DateTime(2026, 11, 5));
    final paths = card.map((p) => p.path).toList();
    expect(paths.toSet(), hasLength(paths.length));
  });

  test('defaultCard honours lastDay and movie lengths', () {
    final card = FakePhoto.defaultCard(
      lastDay: DateTime(2027, 1, 2),
      videoLengths: const [Duration(seconds: 3)],
    );
    DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
    expect(day(card.first.dateTime), DateTime(2026, 12, 28));
    expect(day(card.last.dateTime), DateTime(2027, 1, 2));
    expect(card.where((p) => p.isVideo).map((p) => p.videoLength).toSet(), {
      const Duration(seconds: 3),
    });
  });

  test('synthetic media: valid JPEG previews, sized full files with the '
      'right magic bytes, deterministic per file', () async {
    final media = syntheticMedia(jpegBytes: 1000, rawBytes: 2000);
    final at = DateTime(2026);
    final jpg = FakePhoto('100RICOH', 'R0000001.JPG', at);
    final dng = FakePhoto('100RICOH', 'R0000001.DNG', at);
    final mov = FakePhoto('100RICOH', 'R0000002.MOV', at);

    final thumb = await media(dng, GrImageSize.thumb);
    expect(thumb.take(2), [0xFF, 0xD8]);
    expect(thumb.sublist(thumb.length - 2), [0xFF, 0xD9]);

    final full = await media(jpg, GrImageSize.full);
    expect(full.take(2), [0xFF, 0xD8]);
    expect(full.length, greaterThanOrEqualTo(1000));
    expect(await media(jpg, GrImageSize.full), full);
    expect((await media(dng, GrImageSize.full)).take(4), [0x49, 0x49, 0x2A, 0]);
    expect(
      String.fromCharCodes((await media(mov, GrImageSize.full)).sublist(4, 8)),
      'ftyp',
    );
  });

  test(
    'synthetic media is oriented as a GR stores it: previews are '
    'unrotated without EXIF, a full JPEG carries the orientation tag',
    () async {
      final media = syntheticMedia(jpegBytes: 1000);
      final at = DateTime(2026);
      final upright = FakePhoto('100RICOH', 'R0000001.JPG', at);
      final held = FakePhoto('100RICOH', 'R0000002.JPG', at, orientation: 8);
      const app1 = [0xFF, 0xD8, 0xFF, 0xE1];

      for (final size in [GrImageSize.thumb, GrImageSize.view]) {
        final preview = await media(held, size);
        expect(preview.take(4), isNot(app1), reason: '$size has no EXIF');
        expect(preview, await media(upright, size));
      }
      expect((await media(upright, GrImageSize.full)).take(4), isNot(app1));

      final full = await media(held, GrImageSize.full);
      expect(full.take(4), app1);
      expect(String.fromCharCodes(full.sublist(6, 12)), 'Exif\x00\x00');
      // TIFF II header, IFD0 at 8, one entry: Orientation (0x0112) SHORT = 8.
      expect(full.sublist(12, 32), [
        0x49, 0x49, 0x2A, 0, 8, 0, 0, 0, 1, 0, //
        0x12, 0x01, 3, 0, 1, 0, 0, 0, 8, 0,
      ]);
    },
  );

  test('withExifOrientation rejects bytes that are not a JPEG', () {
    expect(
      () => withExifOrientation(Uint8List.fromList([0x89, 0x50]), 6),
      throwsArgumentError,
    );
  });
}
