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
    expect(card.where((p) => p.portrait), isNotEmpty);
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
}
