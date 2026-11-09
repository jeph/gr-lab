import 'dart:convert';
import 'dart:io';

import 'package:gr_camera/src/library/camera_file.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// `library.json` format; info cached under another version is dropped.
const _cacheVersion = 2;

File _cacheFile(Directory cacheDir, String serial) =>
    File('${cacheDir.path}/$serial/library.json');

/// What `library.json` keeps for one camera: its files as last listed, the
/// `/info` known for them, and when the listing was read.
typedef CachedListing = ({
  List<CameraFile> files,
  Map<String, FileInfo> info,
  DateTime? listedAt,
});

/// Reads [serial]'s `<cacheDir>/<serial>/library.json`; null when there is
/// none or it cannot be read.
Future<CachedListing?> readCachedListing(
  Directory cacheDir,
  String serial,
) async {
  final Map<String, Object?> json;
  try {
    final decoded = jsonDecode(
      await _cacheFile(cacheDir, serial).readAsString(),
    );
    if (decoded is! Map<String, Object?>) return null;
    json = decoded;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  final files = <CameraFile>[];
  for (final e in json['files'] as List<Object?>? ?? const []) {
    if (e is! Map<String, Object?>) continue;
    final dir = e['d'];
    final file = e['f'];
    final storage = e['s'];
    if (dir is! String || file is! String) continue;
    try {
      files.add(CameraFile(storage as String?, GrPhotoPath(dir, file)));
    } on Object {
      continue;
    }
  }
  final info = <String, FileInfo>{};
  // Version 1 info lacks the orientation; it is fetched again.
  final cachedInfo = json['version'] == _cacheVersion ? json['info'] : null;
  if (cachedInfo is Map<String, Object?>) {
    for (final MapEntry(:key, :value) in cachedInfo.entries) {
      if (value is Map<String, Object?>) info[key] = FileInfo.fromJson(value);
    }
  }
  return (
    files: files,
    info: info,
    listedAt: switch (json['listedAt']) {
      final String t => DateTime.tryParse(t),
      _ => null,
    },
  );
}

/// Replaces [serial]'s `library.json` with [listing], atomically (a
/// temporary file renamed over it), so a crash mid-write never leaves a
/// torn file. The listing is read before the first await, so later changes
/// to its collections do not reach this write.
Future<void> writeCachedListing(
  Directory cacheDir,
  String serial,
  CachedListing listing,
) async {
  final text = jsonEncode({
    'version': _cacheVersion,
    'listedAt': listing.listedAt?.toIso8601String(),
    'files': [
      for (final f in listing.files) {'s': f.storage, 'd': f.dir, 'f': f.name},
    ],
    'info': {
      for (final MapEntry(:key, :value) in listing.info.entries)
        key: value.toJson(),
    },
  });
  final file = _cacheFile(cacheDir, serial);
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(text, flush: true);
  await tmp.rename(file.path);
}
