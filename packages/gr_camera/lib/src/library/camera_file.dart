import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// One file on the camera. [storage] is `in` or `sd1` on cameras with two
/// storages and null on cameras that are listed without `storage=`; the
/// same `dir/file` may exist on both storages of a GR IV.
@immutable
final class CameraFile {
  /// The file at [path] on [storage].
  const new(this.storage, this.path);

  /// `in`, `sd1`, or null when the camera was listed without `storage=`.
  final String? storage;

  /// Folder and file name as the camera lists them.
  final GrPhotoPath path;

  /// Folder on the camera, e.g. `100RICOH`.
  String get dir => path.dir;

  /// File name with extension, e.g. `R0001234.JPG`.
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

/// What `/v1/photos/<dir>/<file>/info` told us about one file.
@immutable
final class FileInfo {
  /// Facts the camera reported; each is null when it left it out.
  const new({this.taken, this.size, this.duration, this.orientation});

  /// Reads the form [toJson] writes (the on-device cache).
  factory fromJson(Map<String, Object?> json) => FileInfo(
    taken: switch (json['t']) {
      final String t => DateTime.tryParse(t),
      _ => null,
    },
    size: (json['z'] as num?)?.toInt(),
    duration: switch (json['v']) {
      final num v => Duration(seconds: v.toInt()),
      _ => null,
    },
    orientation: (json['o'] as num?)?.toInt(),
  );

  /// Capture time in the camera's clock (local, no zone).
  final DateTime? taken;

  /// Bytes of the full file.
  final int? size;

  /// Movie length, whole seconds as `/info` `duration` reports it.
  final Duration? duration;

  /// EXIF orientation (1–8) the camera reports for the shot; its
  /// thumbnails and previews are stored unrotated.
  final int? orientation;

  /// \[design\] Whether this and [other], read for one camera path at
  /// different times, describe the same file. The listing gives names only
  /// (http-api.md §2.1), so a path that comes back with different content
  /// (another card, a file deleted and shot again) shows only in `/info`:
  /// the size and capture time are what it reports per file that tell two
  /// shots apart. Two shots at one path with the same size, taken in the
  /// same second, count as one.
  bool sameContent(FileInfo other) =>
      size == other.size && taken == other.taken;

  /// Compact form for the on-device cache, read back by [FileInfo.fromJson].
  Map<String, Object?> toJson() => {
    if (taken != null) 't': taken!.toIso8601String(),
    'z': ?size,
    if (duration != null) 'v': duration!.inSeconds,
    'o': ?orientation,
  };

  @override
  bool operator ==(Object other) =>
      other is FileInfo &&
      other.taken == taken &&
      other.size == size &&
      other.duration == duration &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(taken, size, duration, orientation);
}

/// [FileInfo] of the camera's `/info` answer.
FileInfo fileInfoOf(GrPhotoInfo info) => FileInfo(
  taken: parseCameraTime(info.datetime ?? info.recordedTime),
  size: info.size,
  duration: info.duration == null ? null : Duration(seconds: info.duration!),
  orientation: info.orientation,
);

/// Parses the camera's `datetime`. Its format is untested on hardware
/// (burst-grouping.md), so ISO 8601 and the EXIF `YYYY:MM:DD HH:MM:SS`
/// form are both accepted, always as the camera's local wall clock.
DateTime? parseCameraTime(String? text) {
  if (text == null || text.isEmpty) return null;
  final exif = RegExp(
    r'^(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(text);
  if (exif != null) {
    final p = [for (var i = 1; i <= 6; i++) int.parse(exif.group(i)!)];
    return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}
