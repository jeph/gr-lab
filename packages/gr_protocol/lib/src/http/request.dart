import 'dart:convert';

/// Request `Content-Type` values exactly as the apps send them.
enum GrContentType {
  /// Image Sync's OkHttp body type for every POST/PUT
  /// (docs/protocol/remote-shooting.md §0 item 2).
  textPlain('text/plain; charset=utf-8'),

  /// GR WORLD labels its `key=value` bodies for `PUT /v1/params/device` and
  /// `PUT …/transfer` as JSON although they are form-style text
  /// (docs/protocol/http-api.md §1 rows 8 and 12).
  jsonLabelled('application/json'),

  /// Firmware prepare (http-api.md §1 row 15).
  formUrlEncoded('application/x-www-form-urlencoded'),

  /// Firmware upload (http-api.md §1 row 16).
  octetStream('application/octet-stream'),

  /// End-screen upload (http-api.md §4.4).
  imageJpeg('image/jpeg');

  const GrContentType(this.header);
  final String header;
}

/// Encodes `key=value&key=value` exactly as Image Sync and GR WORLD do: no
/// URL-encoding, so `xv=+0.3` keeps its literal `+`
/// (docs/protocol/remote-shooting.md §0 item 2, `ItemCaptureParams.java:267-282`).
///
/// Because nothing is escaped, a key containing `=` or `&` or a value
/// containing `&` cannot be represented; those, empty keys and CR/LF are
/// rejected with [ArgumentError] rather than silently mangled.
String encodeKeyValueBody(Map<String, String> pairs) {
  final parts = <String>[];
  pairs.forEach((key, value) {
    if (key.isEmpty || key.contains(RegExp(r'[=&\r\n]'))) {
      throw ArgumentError.value(
        key,
        'key',
        'must be non-empty without = & CR LF',
      );
    }
    if (value.contains(RegExp(r'[&\r\n]'))) {
      throw ArgumentError.value(
        value,
        key,
        'cannot contain & or line breaks: camera bodies are not escaped',
      );
    }
    parts.add('$key=$value');
  });
  return parts.join('&');
}

/// UTF-8 bytes of [encodeKeyValueBody].
List<int> encodeKeyValueBodyBytes(Map<String, String> pairs) =>
    utf8.encode(encodeKeyValueBody(pairs));

/// Builds a query string `k=v&k=v`, or `null` when [query] is empty. The
/// apps concatenate values without encoding (e.g.
/// `after=100RICOH/R0000001.JPG`, http-api.md §2.1), so `/`, `,` and `:` stay
/// literal; other reserved characters are percent-encoded.
String? encodeQuery(Map<String, String> query) => query.isEmpty
    ? null
    : query.entries.map((e) => '${_q(e.key)}=${_q(e.value)}').join('&');

String _q(String v) =>
    Uri.encodeQueryComponent(v)
        .replaceAll('%2F', '/')
        .replaceAll('%2C', ',')
        .replaceAll('%3A', ':');

/// Storage identifiers the camera uses in `storage=` (http-api.md §1).
abstract final class GrStorageId {
  static const internal = 'in';
  static const sd = 'sd1';

  /// Validates a user-supplied storage id: it is placed in URLs and bodies
  /// unescaped, so only `[A-Za-z0-9_]` is accepted.
  static String validate(String storage) {
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(storage)) {
      throw FormatException('invalid storage id', storage);
    }
    return storage;
  }
}

/// `<dir>/<file>` of an image on the camera, e.g. `100RICOH/R0000001.JPG`.
final class GrPhotoPath {
  GrPhotoPath(this.dir, this.file) {
    for (final (name, v) in [('dir', dir), ('file', file)]) {
      if (v.isEmpty || v.contains(RegExp(r'[/?#\\\s]'))) {
        throw FormatException('invalid photo $name', v);
      }
    }
  }

  /// Parses `dir/file`. Throws [FormatException].
  factory GrPhotoPath.parse(String path) {
    final parts = path.split('/');
    if (parts.length != 2) {
      throw FormatException('expected <dir>/<file>', path);
    }
    return GrPhotoPath(parts[0], parts[1]);
  }

  /// Parses a camera-supplied `filepath` (transfer list, WebSocket `storage`
  /// events). The transfer list may append `?xs` to request the reduced size;
  /// both apps strip it (http-api.md §2.5 step 3, connection-imagesync.md §4).
  /// Returns `null` when the text is not a `dir/file` pair; never throws.
  static GrPhotoPath? tryParseCamera(String filepath) {
    final path = filepath.replaceAll('?xs', '');
    final trimmed = path.startsWith('/') ? path.substring(1) : path;
    try {
      return GrPhotoPath.parse(trimmed);
    } on FormatException {
      return null;
    }
  }

  final String dir;
  final String file;

  /// Upper-case extension without the dot (`JPG`, `DNG`, `MOV`), or empty.
  String get extension {
    final dot = file.lastIndexOf('.');
    return dot < 0 ? '' : file.substring(dot + 1).toUpperCase();
  }

  @override
  String toString() => '$dir/$file';

  @override
  bool operator ==(Object other) =>
      other is GrPhotoPath && other.dir == dir && other.file == file;

  @override
  int get hashCode => Object.hash(dir, file);
}

/// `size=` values for image GETs (http-api.md §2.3–2.4, enum `hOb`).
enum GrImageSize {
  /// Original file (JPG/DNG/MOV).
  full,

  /// Large JPEG preview.
  view,

  /// Grid thumbnail.
  thumb,

  /// Reduced-size JPEG; GR WORLD only requests it for `JPG` files and falls
  /// back to `full` for DNG/MOV.
  xs,
}

/// Touch position for `pos=X,Y`: integer percent (0..100) of the live-view
/// frame in camera (landscape) orientation, origin top-left
/// (docs/protocol/remote-shooting.md §3.2). The firmware-side range is
/// [unknown]; 0..100 is what Image Sync sends.
final class GrFocusPoint {
  GrFocusPoint(this.x, this.y) {
    if (x < 0 || x > 100 || y < 0 || y > 100) {
      throw RangeError('focus point $x,$y outside 0..100');
    }
  }

  /// From normalized 0..1 coordinates, rounded like Image Sync
  /// (`Math.round(v*100)`).
  factory GrFocusPoint.normalized(double x, double y) =>
      GrFocusPoint((x * 100).round(), (y * 100).round());

  /// Parses `X,Y` (integers, no spaces required). Throws [FormatException].
  factory GrFocusPoint.parse(String text) {
    final m = RegExp(r'^\s*(\d{1,3})\s*,\s*(\d{1,3})\s*$').firstMatch(text);
    if (m == null) throw FormatException('expected X,Y in percent', text);
    final x = int.parse(m.group(1)!);
    final y = int.parse(m.group(2)!);
    try {
      return GrFocusPoint(x, y);
    } on RangeError {
      throw FormatException('X,Y must be 0..100', text);
    }
  }

  final int x;
  final int y;

  /// Wire form `X,Y`.
  String get wire => '$x,$y';

  /// Whether the point lies in the centered AF rectangle described by
  /// `/v1/props` `focusEffectiveArea: [W, H]` (percent of the frame). With no
  /// area, Image Sync's default (0.111,0.125)–(0.889,0.875) applies
  /// (remote-shooting.md §3.2).
  bool withinEffectiveArea(List<int>? area) {
    final double left, right, top, bottom;
    if (area != null && area.length >= 2) {
      left = 50 - area[0] / 2;
      right = 50 + area[0] / 2;
      top = 50 - area[1] / 2;
      bottom = 50 + area[1] / 2;
    } else {
      left = 11.1;
      right = 88.9;
      top = 12.5;
      bottom = 87.5;
    }
    return x >= left && x <= right && y >= top && y <= bottom;
  }

  @override
  String toString() => wire;
}

/// `af=` values for `POST /v1/camera/shoot`. The firmware's accepted
/// vocabulary is [unknown] (remote-shooting.md §3.2, §8): only [on] (GR III
/// Image Sync) and [camera] (GR II) are observed in shipping clients.
enum GrShootAf {
  /// Image Sync GR III "shoot with AF".
  on,

  /// Not observed in any client; offered for hardware validation of the
  /// firmware's `shutter_mode` parser.
  off,

  /// GR II official clients.
  camera,
}

/// Body for `POST /v1/camera/shoot`: `""`, `af=<v>`, `pos=X,Y` or
/// `af=<v>&pos=X,Y` (remote-shooting.md §2.1).
String shootBody({GrShootAf? af, GrFocusPoint? pos}) => encodeKeyValueBody({
  if (af != null) 'af': af.name,
  if (pos != null) 'pos': pos.wire,
});
