import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/src/library/library_model.dart';
import 'package:grlab/src/library/shot.dart';

CameraFile f(String path, {String? storage = 'sd1'}) =>
    CameraFile(storage, GrPhotoPath.parse(path));

void main() {
  group('groupShots', () {
    test('pairs a JPG and DNG with the same base name in one folder', () {
      final shots = groupShots([
        f('100RICOH/R0000001.JPG'),
        f('100RICOH/R0000001.DNG'),
        f('100RICOH/R0000002.JPG'),
        f('100RICOH/R0000003.DNG'),
      ]);
      expect(shots.map((s) => (s.base, s.format)), [
        ('R0000003', ShotFormat.raw),
        ('R0000002', ShotFormat.jpeg),
        ('R0000001', ShotFormat.rawJpeg),
      ]);
      final pair = shots.last;
      expect(pair.primary, f('100RICOH/R0000001.JPG'));
      expect(pair.files, [
        f('100RICOH/R0000001.JPG'),
        f('100RICOH/R0000001.DNG'),
      ]);
    });

    test('pairs regardless of listing order', () {
      final shots = groupShots([
        f('100RICOH/R0000001.DNG'),
        f('100RICOH/R0000001.JPG'),
      ]);
      expect(shots.single.format, ShotFormat.rawJpeg);
    });

    test('keeps the same name on two storages apart', () {
      final shots = groupShots([
        f('100RICOH/R0000001.JPG', storage: 'in'),
        f('100RICOH/R0000001.JPG'),
        f('100RICOH/R0000001.DNG'),
      ]);
      expect(shots, hasLength(2));
      final byStorage = {for (final s in shots) s.storage: s};
      expect(byStorage['in']!.format, ShotFormat.jpeg);
      expect(byStorage['sd1']!.format, ShotFormat.rawJpeg);
      expect(byStorage['in']!.key, isNot(byStorage['sd1']!.key));
      expect(
        byStorage['in']!.primary.key,
        isNot(byStorage['sd1']!.primary.key),
      );
    });

    test('does not pair halves from different folders', () {
      final shots = groupShots([
        f('100RICOH/R0000001.JPG'),
        f('101RICOH/R0000001.DNG'),
      ]);
      expect(shots.map((s) => s.format), [ShotFormat.raw, ShotFormat.jpeg]);
    });

    test('a movie is its own shot and never pairs with a still', () {
      final shots = groupShots([
        f('100RICOH/R0000005.MOV'),
        f('100RICOH/R0000005.JPG'),
      ]);
      expect(shots, hasLength(2));
      final movie = shots.firstWhere((s) => s.isVideo);
      expect(movie.format, ShotFormat.video);
      expect(movie.files, [f('100RICOH/R0000005.MOV')]);
      expect(movie.key, isNot(shots.firstWhere((s) => !s.isVideo).key));
    });

    test('leaves out files it cannot show', () {
      expect(groupShots([f('100RICOH/R0000001.WAV')]), isEmpty);
    });

    test('sorts newest first by folder then file number', () {
      final shots = groupShots([
        f('100RICOH/R0000099.JPG'),
        f('101RICOH/R0000100.JPG'),
        f('99RICOH_/R0000001.JPG'),
        f('100RICOH/R0000098.JPG'),
      ]);
      expect(shots.map((s) => '${s.dir}/${s.base}'), [
        '101RICOH/R0000100',
        '100RICOH/R0000099',
        '100RICOH/R0000098',
        '99RICOH_/R0000001',
      ]);
    });
  });

  group('Shot.filesOf', () {
    final pair = groupShots([
      f('100RICOH/R0000001.JPG'),
      f('100RICOH/R0000001.DNG'),
    ]).single;

    test('a pair has one file of each still kind', () {
      expect(pair.filesOf(FileKind.jpeg), [pair.jpeg]);
      expect(pair.filesOf(FileKind.raw), [pair.raw]);
      expect(pair.filesOf(FileKind.movie), isEmpty);
    });

    test('a single file is only its own kind', () {
      for (final (path, kind) in [
        ('100RICOH/R0000002.JPG', FileKind.jpeg),
        ('100RICOH/R0000003.DNG', FileKind.raw),
        ('100RICOH/R0000004.MOV', FileKind.movie),
      ]) {
        final shot = groupShots([f(path)]).single;
        for (final k in FileKind.values) {
          expect(
            shot.filesOf(k),
            k == kind ? [f(path)] : isEmpty,
            reason: '$path $k',
          );
        }
      }
    });
  });

  group('daySections', () {
    final shots = groupShots([
      for (var i = 1; i <= 6; i++) f('100RICOH/R000000$i.JPG'),
    ]);
    // Newest first: 6, 5, 4, 3, 2, 1.

    test('splits by capture day', () {
      final dates = {
        'R0000006': DateTime(2026, 11, 7, 14),
        'R0000005': DateTime(2026, 11, 7, 9),
        'R0000004': DateTime(2026, 11, 6, 20),
        'R0000003': DateTime(2026, 11, 6, 8),
        'R0000002': DateTime(2026, 11, 3, 8),
        'R0000001': DateTime(2026, 11, 3, 7),
      };
      final sections = daySections(shots, (s) => dates[s.base]);
      expect(sections.map((s) => (s.day, s.shots.length)), [
        (DateTime(2026, 11, 7), 2),
        (DateTime(2026, 11, 6), 2),
        (DateTime(2026, 11, 3), 2),
      ]);
    });

    test('undated shots stay with the shot before them', () {
      final dates = {
        'R0000005': DateTime(2026, 11, 7, 9),
        'R0000002': DateTime(2026, 11, 3, 8),
      };
      final sections = daySections(shots, (s) => dates[s.base]);
      // Records compare their List fields by identity, so compare text.
      expect(
        sections.map(
          (s) => '${s.day} ${[for (final x in s.shots) x.base].join(',')}',
        ),
        [
          'null R0000006',
          '${DateTime(2026, 11, 7)} R0000005,R0000004,R0000003',
          '${DateTime(2026, 11, 3)} R0000002,R0000001',
        ],
      );
    });

    test('no dates at all is one undated section', () {
      final sections = daySections(shots, (_) => null);
      expect(sections.single.day, isNull);
      expect(sections.single.shots, hasLength(6));
    });
  });

  test('FilteredShots counts every chip', () {
    final shots = groupShots([
      f('100RICOH/R0000001.JPG'),
      f('100RICOH/R0000001.DNG'),
      f('100RICOH/R0000002.JPG'),
      f('100RICOH/R0000003.DNG'),
      f('100RICOH/R0000004.MOV'),
    ]);
    final downloaded = {shots.last.key};
    final filtered = FilteredShots.of(
      shots,
      LibraryFilter.raw,
      (s) => downloaded.contains(s.key),
    );
    expect(filtered.counts, {
      LibraryFilter.all: 4,
      LibraryFilter.jpeg: 2,
      LibraryFilter.raw: 2,
      LibraryFilter.video: 1,
      LibraryFilter.notDownloaded: 3,
    });
    expect(filtered.shots.map((s) => s.base), ['R0000003', 'R0000001']);
  });
}
