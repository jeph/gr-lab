import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

enum ShotFormat { jpeg, raw, rawJpeg, video }

/// What the grid shows as one item: a JPEG, a DNG, a JPEG+DNG pair with the
/// same base name in the same folder and storage, or a movie.
@immutable
final class Shot {
  const new({this.jpeg, this.raw, this.movie})
    : assert(
        (movie == null) != (jpeg == null && raw == null),
        'a shot is a movie or a still',
      );

  final CameraFile? jpeg;
  final CameraFile? raw;
  final CameraFile? movie;

  /// The file the grid and viewer show: the JPEG of a pair.
  CameraFile get primary => movie ?? jpeg ?? raw!;

  String? get storage => primary.storage;
  String get dir => primary.dir;
  String get base => primary.base;

  List<CameraFile> get files => [?jpeg, ?raw, ?movie];

  ShotFormat get format => movie != null
      ? ShotFormat.video
      : jpeg != null && raw != null
      ? ShotFormat.rawJpeg
      : raw != null
      ? ShotFormat.raw
      : ShotFormat.jpeg;

  bool get isPair => format == ShotFormat.rawJpeg;
  bool get isVideo => movie != null;
  bool get hasJpeg => jpeg != null;
  bool get hasRaw => raw != null;

  /// The image a grid cell shows, and the Cameras card reuses. One size
  /// only, so a cell never swaps pictures: a photo's `view` (a `thumb` is
  /// smaller than a phone's cell), a movie's `thumb`.
  GrImageSize get gridSize => isVideo ? GrImageSize.thumb : GrImageSize.view;

  /// Identifies the shot within one camera. Movies get their own key so a
  /// movie never merges with a still of the same base name.
  String get key =>
      '${storage ?? ''}|$dir/$base${movie != null ? '.${movie!.extension}' : ''}';

  /// The shot's files of [kind]: a pair has one JPEG and one RAW.
  List<CameraFile> filesOf(FileKind kind) => switch (kind) {
    FileKind.jpeg => [?jpeg],
    FileKind.raw => [?raw],
    FileKind.movie => [?movie],
  };

  @override
  bool operator ==(Object other) =>
      other is Shot &&
      other.jpeg == jpeg &&
      other.raw == raw &&
      other.movie == movie;

  @override
  int get hashCode => Object.hash(jpeg, raw, movie);

  @override
  String toString() => 'Shot($key ${format.name})';
}

/// What a camera file holds, by its extension; what the selection
/// downloads per action.
enum FileKind { jpeg, raw, movie }

/// The kind of a file with [extension]; null for files the app cannot
/// show.
FileKind? fileKind(String extension) => switch (extension) {
  'JPG' || 'JPEG' => FileKind.jpeg,
  'DNG' => FileKind.raw,
  'MOV' || 'MP4' => FileKind.movie,
  _ => null,
};

/// Groups camera files into shots, newest first. Files the app cannot show
/// (other extensions) are left out.
///
/// The listing carries no dates, so order follows the camera's numbering:
/// later folders first, then higher file numbers. Both storages are merged
/// by that numbering.
List<Shot> groupShots(Iterable<CameraFile> files) {
  final stills = <String, ({CameraFile? jpeg, CameraFile? raw})>{};
  final shots = <Shot>[];
  for (final f in files) {
    switch (fileKind(f.extension)) {
      case null:
        break;
      case FileKind.movie:
        shots.add(Shot(movie: f));
      case FileKind.jpeg:
        final key = '${f.storage ?? ''}|${f.dir}/${f.base}';
        final e = stills[key];
        stills[key] = (jpeg: e?.jpeg ?? f, raw: e?.raw);
      case FileKind.raw:
        final key = '${f.storage ?? ''}|${f.dir}/${f.base}';
        final e = stills[key];
        stills[key] = (jpeg: e?.jpeg, raw: e?.raw ?? f);
    }
  }
  for (final s in stills.values) {
    shots.add(Shot(jpeg: s.jpeg, raw: s.raw));
  }
  return shots..sort(compareShots);
}

/// Newest first by folder, then file number, then storage.
int compareShots(Shot a, Shot b) {
  final byDir = _compareNatural(b.dir, a.dir);
  if (byDir != 0) return byDir;
  final byBase = _compareNatural(b.base, a.base);
  if (byBase != 0) return byBase;
  final byStorage = (a.storage ?? '').compareTo(b.storage ?? '');
  if (byStorage != 0) return byStorage;
  return a.primary.name.compareTo(b.primary.name);
}

final _digits = RegExp(r'\d+');

/// Compares the first number in each name (`100RICOH`, `R0001234`), then the
/// whole text, so numbering that outgrows its width still sorts.
int _compareNatural(String a, String b) {
  final na = _digits.firstMatch(a)?.group(0);
  final nb = _digits.firstMatch(b)?.group(0);
  if (na != null && nb != null) {
    final c = BigInt.parse(na).compareTo(BigInt.parse(nb));
    if (c != 0) return c;
  }
  return a.compareTo(b);
}
