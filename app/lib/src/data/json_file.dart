import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One JSON document on disk, replaced atomically (write to a temporary
/// file, then rename) so a crash mid-write never leaves a torn file.
final class JsonFile {
  new(this.file);

  final File file;

  /// Numbers each write's temporary file, so two writers of one document
  /// never write into the same temporary file.
  static int _writes = 0;

  /// The latest [save]; fails when it did.
  Future<void> _lastSave = Future.value();

  /// [_lastSave] with its failure reported, for the next save to follow.
  Future<void> _saves = Future.value();

  /// The stored object, or null when the file is missing or unreadable.
  Future<Map<String, Object?>?> read() async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Replaces the file with [value]. A failed write leaves the file as it
  /// was.
  Future<void> write(Map<String, Object?> value) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.${_writes++}.tmp');
    try {
      await tmp.writeAsString(jsonEncode(value), flush: true);
      await tmp.rename(file.path);
    } on FileSystemException {
      await tmp.delete().catchError((Object _) => tmp);
      rethrow;
    }
  }

  /// Writes the document [snapshot] returns once every earlier save of this
  /// file has finished; [snapshot] runs when the write starts, so the file
  /// gets the state as it is then. The returned future fails when this
  /// write does, and the failure goes to the debug log; later saves still
  /// run.
  Future<void> save(FutureOr<Map<String, Object?>> Function() snapshot) {
    final done = _saves.then((_) async {
      await write(await snapshot());
    });
    _lastSave = done;
    _saves = done.catchError((Object e) {
      debugPrint('Saving ${file.uri.pathSegments.last} failed: $e');
    });
    return done;
  }

  /// Completes when every save so far has finished. Each save writes the
  /// whole document, so this fails when the latest one did: the file does
  /// not hold the latest state then.
  Future<void> flush() => _lastSave;
}
