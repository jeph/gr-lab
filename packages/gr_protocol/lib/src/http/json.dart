import 'dart:convert';

final RegExp _uint32Max = RegExp('(?<![0-9.])4294967295(?![0-9.])');

/// Applies Image Sync's textual fix-up before JSON parsing: every
/// `4294967295` (an unsigned 32-bit -1 the firmware serialises for "unset"
/// fields) becomes `-2147483648` so it fits a signed 32-bit int
/// (docs/protocol/remote-shooting.md §0 item 3, `RestCameraClient.java:110`).
///
/// Image Sync replaces the substring blindly; this version only replaces it
/// where it is not part of a longer number, which is the same for every
/// well-formed numeric token.
String applyUint32Quirk(String text) => text.contains('4294967295')
    ? text.replaceAll(_uint32Max, '-2147483648')
    : text;

/// Outcome of decoding a camera JSON body. Decoding never throws: a body that
/// is not JSON yields [value] `null` and a human-readable [issue].
final class CameraJson {
  const new _(this.text, this.value, this.issue);

  /// Body text after UTF-8 decoding (malformed sequences replaced) and the
  /// `4294967295` quirk.
  final String text;

  /// Parsed JSON value, or `null` when [issue] is set.
  final Object? value;

  /// Why the body could not be parsed, or `null` on success.
  final String? issue;

  /// The parsed value when it is a JSON object.
  Map<String, Object?>? get object =>
      value is Map<String, Object?> ? value! as Map<String, Object?> : null;
}

/// Decodes a camera response body (bytes) as JSON with the Image Sync quirk.
CameraJson decodeCameraJsonBytes(List<int> body) =>
    decodeCameraJson(utf8.decode(body, allowMalformed: true));

/// Decodes camera JSON [text] with the Image Sync quirk. Never throws.
CameraJson decodeCameraJson(String text) {
  final fixed = applyUint32Quirk(text);
  if (fixed.trim().isEmpty) return CameraJson._(fixed, null, 'empty body');
  try {
    return CameraJson._(fixed, jsonDecode(fixed), null);
  } on FormatException catch (e) {
    return CameraJson._(fixed, null, 'not JSON: ${e.message}');
  }
}

/// Lenient typed access to a camera JSON object. The apps' parsers disagree
/// on field types (GR WORLD reads storage `remain` as a number, Image Sync as
/// a string), so getters coerce between number, string and bool and return
/// `null` for anything else instead of throwing.
extension type const JsonFields(Map<String, Object?> map) {
  /// Strings as-is; numbers via [numberText]; bools as `true`/`false`.
  String? string(String key) => stringValue(map[key]);

  /// Integer via [intValue]: whole doubles and numeric strings coerce.
  int? integer(String key) => intValue(map[key]);

  /// Bool via [boolValue]: `"true"`/`"false"` strings coerce.
  bool? boolean(String key) => boolValue(map[key]);

  /// Nested JSON object, or `null` when absent or not an object.
  Map<String, Object?>? object(String key) => objectValue(map[key]);

  /// Elements coerced with [stringValue]; elements that are not scalars are
  /// skipped. `null` when the key is absent or not a list.
  List<String>? strings(String key) {
    final v = map[key];
    if (v is! List<Object?>) return null;
    return [for (final e in v) ?stringValue(e)];
  }

  /// Elements coerced with [intValue]; elements that do not coerce are
  /// skipped. `null` when the key is absent or not a list.
  List<int>? ints(String key) {
    final v = map[key];
    if (v is! List<Object?>) return null;
    return [for (final e in v) ?intValue(e)];
  }

  /// Elements that are JSON objects; others are skipped. `null` when the key
  /// is absent or not a list.
  List<Map<String, Object?>>? objects(String key) {
    final v = map[key];
    if (v is! List<Object?>) return null;
    return [for (final e in v) ?objectValue(e)];
  }
}

/// Text form of a JSON number. Doubles lose their original lexeme in
/// `dart:convert` (`1.250` parses to `1.25`); the camera is expected to send
/// setting values such as `tv` as strings (Image Sync models them as
/// `String`, docs/protocol/remote-shooting.md §4.1), so this only matters for
/// a firmware that sends bare numbers.
String numberText(num n) => n.toString();

/// Strings as-is, numbers via [numberText], bools as `true`/`false`; `null`
/// for anything else.
String? stringValue(Object? v) => switch (v) {
  final String s => s,
  final num n => numberText(n),
  final bool b => b.toString(),
  _ => null,
};

/// Ints as-is, whole finite doubles truncated, numeric strings parsed after
/// trimming; `null` for anything else.
int? intValue(Object? v) => switch (v) {
  final int i => i,
  final double d when d.isFinite && d == d.truncateToDouble() => d.toInt(),
  final String s => int.tryParse(s.trim()),
  _ => null,
};

/// Bools as-is and the exact strings `true`/`false`; `null` otherwise.
bool? boolValue(Object? v) => switch (v) {
  final bool b => b,
  'true' => true,
  'false' => false,
  _ => null,
};

/// [v] when it is a JSON object, else `null`.
Map<String, Object?>? objectValue(Object? v) =>
    v is Map<String, Object?> ? v : null;
