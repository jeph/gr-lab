import 'dart:convert';
import 'dart:io';

/// One JSON document on disk, replaced atomically (write to a temporary
/// file, then rename) so a crash mid-write never leaves a torn file.
final class JsonFile {
  new(this.file);

  final File file;

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

  Future<void> write(Map<String, Object?> value) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(file.path);
  }
}
