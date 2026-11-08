import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../data/settings.dart';

/// One file on the camera. [storage] is `in` or `sd1` on cameras with two
/// storages and null on cameras that are listed without `storage=`; the
/// same `dir/file` may exist on both storages of a GR IV.
@immutable
final class CameraFile {
  const CameraFile(this.storage, this.path);

  final String? storage;
  final GrPhotoPath path;

  String get dir => path.dir;
  String get name => path.file;

  /// `JPG`, `DNG`, `MOV`.
  String get extension => path.extension;

  /// Name without the extension (`R0001234`).
  String get base {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }

  /// Identifies the file within one camera.
  String get key => '${storage ?? ''}|$dir/$name';

  /// [key] made safe for a file name.
  String get fileStem => '${storage ?? 'x'}_${dir}_$name';

  @override
  bool operator ==(Object other) =>
      other is CameraFile && other.storage == storage && other.path == path;

  @override
  int get hashCode => Object.hash(storage, path);

  @override
  String toString() => storage == null ? '$path' : '$storage:$path';
}

enum ShotFormat { jpeg, raw, rawJpeg, video }

/// What the grid shows as one item: a JPEG, a DNG, a JPEG+DNG pair with the
/// same base name in the same folder and storage, or a movie.
@immutable
final class Shot {
  const Shot({this.jpeg, this.raw, this.movie})
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

  /// Identifies the shot within one camera. Movies get their own key so a
  /// movie never merges with a still of the same base name.
  String get key =>
      '${storage ?? ''}|$dir/$base${movie != null ? '.${movie!.extension}' : ''}';

  /// The files a download brings: a pair follows [choice], a single file
  /// always comes.
  List<CameraFile> filesFor(RawJpegChoice choice) {
    if (!isPair) return files;
    return switch (choice) {
      RawJpegChoice.jpeg => [jpeg!],
      RawJpegChoice.raw => [raw!],
      RawJpegChoice.both => [jpeg!, raw!],
    };
  }

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

enum _Kind { jpeg, raw, movie }

_Kind? _kindOf(String extension) => switch (extension) {
  'JPG' || 'JPEG' => _Kind.jpeg,
  'DNG' => _Kind.raw,
  'MOV' || 'MP4' => _Kind.movie,
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
    switch (_kindOf(f.extension)) {
      case null:
        break;
      case _Kind.movie:
        shots.add(Shot(movie: f));
      case _Kind.jpeg:
        final key = '${f.storage ?? ''}|${f.dir}/${f.base}';
        final e = stills[key];
        stills[key] = (jpeg: e?.jpeg ?? f, raw: e?.raw);
      case _Kind.raw:
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

/// `in` → Internal, `sd1` → SD.
String? storageLabel(String? storage) => switch (storage) {
  null => null,
  GrStorageId.internal => 'Internal',
  GrStorageId.sd => 'SD',
  final s => s.toUpperCase(),
};

String formatLabel(ShotFormat f) => switch (f) {
  ShotFormat.jpeg => 'JPEG',
  ShotFormat.raw => 'RAW',
  ShotFormat.rawJpeg => 'RAW+JPEG',
  ShotFormat.video => 'Video',
};
