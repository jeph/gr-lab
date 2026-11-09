import 'dart:io';

import 'package:flutter/services.dart';

import 'package:grlab/src/services.dart';

/// [MediaSaver] over the `io.jeph.grlab/media` method channel.
///
/// The shot is sent as `{album, files: [{path, name, kind, mimeType}]}`
/// with the JPEG before the DNG, because iOS makes the first file of a pair
/// the primary photo and the second its RAW alternate. Android writes each
/// file as its own MediaStore entry under `Pictures/<album>` or
/// `Movies/<album>`; iOS asks only for add-only Photos access, which cannot
/// create or look up albums, so the album is ignored there.
final class PlatformMediaSaver implements MediaSaver {
  new({this._channel = const MethodChannel('io.jeph.grlab/media')});

  final MethodChannel _channel;

  @override
  Future<void> saveShot(List<File> files, {required String album}) async {
    final entries = [for (final f in files) _entry(f)]
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    final kinds = [for (final e in entries) e.kind];
    final supported = switch (kinds) {
      [_] => true,
      [_MediaKind.jpeg, _MediaKind.dng] => true,
      _ => false,
    };
    if (!supported) {
      throw MediaSaveException(
        MediaSaveFailure.unsupported,
        'not one shot: ${files.map((f) => _name(f.path)).join(', ')}',
      );
    }
    try {
      await _channel.invokeMethod<void>('saveShot', {
        'album': album,
        'files': [
          for (final e in entries)
            {
              'path': e.file.path,
              'name': _name(e.file.path),
              'kind': e.kind.name,
              'mimeType': e.kind.mimeType,
            },
        ],
      });
    } on PlatformException catch (e) {
      final failure = switch (e.code) {
        'permissionDenied' => MediaSaveFailure.permissionDenied,
        'unsupported' => MediaSaveFailure.unsupported,
        _ => MediaSaveFailure.failed,
      };
      throw MediaSaveException(failure, [e.code, ?e.message].join(': '));
    } on MissingPluginException {
      throw const MediaSaveException(
        MediaSaveFailure.unsupported,
        'no media channel on this platform',
      );
    }
  }

  static ({File file, _MediaKind kind}) _entry(File file) {
    final name = _name(file.path);
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final kind = switch (ext) {
      'jpg' || 'jpeg' => _MediaKind.jpeg,
      'dng' => _MediaKind.dng,
      'mov' => _MediaKind.movie,
      _ => throw MediaSaveException(
        MediaSaveFailure.unsupported,
        'not a JPEG, DNG or MOV file: $name',
      ),
    };
    return (file: file, kind: kind);
  }

  static String _name(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// Declaration order is the order files are sent in.
enum _MediaKind {
  jpeg('image/jpeg'),
  dng('image/x-adobe-dng'),
  movie('video/quicktime');

  new(this.mimeType);

  final String mimeType;
}
