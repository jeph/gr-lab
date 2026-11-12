import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// Synthetic photo files for the geotagging tests, and a reader for what
// the code under test wrote into them. Nothing here comes from a real
// camera: the layouts follow the TIFF 6.0 and Exif specifications. The
// readers fail a test with `fail`, which also works where a group builds
// its cases.

const typeByte = 1;
const typeAscii = 2;
const typeShort = 3;
const typeLong = 4;
const typeRational = 5;

const tagDateTime = 0x0132;
const tagExif = 0x8769;
const tagGps = 0x8825;
const tagDateTimeOriginal = 0x9003;

/// What an EXIF segment's data starts with.
const exifId = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];

/// What the first directory of a synthetic photo says about GPS.
enum TestGps {
  /// It has no GPS tag.
  none,

  /// It points to a GPS directory holding only GPSVersionID, as a camera
  /// that had no location writes it.
  versionOnly,

  /// It points to a GPS directory with a direction (GPSImgDirectionRef,
  /// GPSImgDirection) but no position.
  direction,

  /// It points to a GPS directory with a position.
  located,
}

/// Lays out a classic TIFF from its values up to its first directory.
final class TiffBuilder {
  new(this.endian);

  final Endian endian;

  /// Everything after the 8-byte header.
  final BytesBuilder _body = BytesBuilder();

  int get length => 8 + _body.length;

  /// Appends [bytes] on an even offset and returns that offset.
  int data(List<int> bytes) {
    if (length.isOdd) _body.addByte(0);
    final at = length;
    _body.add(bytes);
    return at;
  }

  List<int> _number(int value, int size) {
    final data = ByteData(size);
    if (size == 2) {
      data.setUint16(0, value, endian);
    } else {
      data.setUint32(0, value, endian);
    }
    return data.buffer.asUint8List();
  }

  /// An entry whose [value] is in it when it fits into four bytes, and
  /// appended otherwise.
  Uint8List _entry(int tag, int type, int count, List<int> value) {
    final entry = Uint8List(12);
    final view = ByteData.sublistView(entry)
      ..setUint16(0, tag, endian)
      ..setUint16(2, type, endian)
      ..setUint32(4, count, endian);
    if (value.length <= 4) {
      entry.setRange(8, 8 + value.length, value);
    } else {
      view.setUint32(8, data(value), endian);
    }
    return entry;
  }

  Uint8List bytes(int tag, List<int> values) =>
      _entry(tag, typeByte, values.length, values);

  Uint8List ascii(int tag, String text) =>
      _entry(tag, typeAscii, text.length + 1, [...text.codeUnits, 0]);

  Uint8List short(int tag, int value) =>
      _entry(tag, typeShort, 1, _number(value, 2));

  Uint8List long(int tag, int value) =>
      _entry(tag, typeLong, 1, _number(value, 4));

  Uint8List rationals(int tag, List<(int, int)> values) =>
      _entry(tag, typeRational, values.length, [
        for (final (numerator, denominator) in values) ...[
          ..._number(numerator, 4),
          ..._number(denominator, 4),
        ],
      ]);

  /// Appends a directory of [entries], sorted by tag, followed by the
  /// offset [next]; returns its offset.
  int directory(List<Uint8List> entries, {int next = 0}) {
    int tagOf(Uint8List entry) =>
        ByteData.sublistView(entry).getUint16(0, endian);
    final sorted = [...entries]..sort((a, b) => tagOf(a).compareTo(tagOf(b)));
    return data([
      ..._number(sorted.length, 2),
      for (final entry in sorted) ...entry,
      ..._number(next, 4),
    ]);
  }

  /// The file, its header pointing to the directory at [first].
  Uint8List build(int first) {
    final order = endian == Endian.little ? 0x49 : 0x4D;
    return Uint8List.fromList([
      order,
      order,
      ..._number(42, 2),
      ..._number(first, 4),
      ..._body.toBytes(),
    ]);
  }
}

/// [length] bytes that follow [seed] and are never FF, so they can stand
/// for a JPEG's image data too.
List<int> noise(int length, {int seed = 7}) {
  final bytes = Uint8List(length);
  var x = seed;
  for (var i = 0; i < length; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    bytes[i] = (x >> 16) & 0x7F;
  }
  return bytes;
}

/// A classic TIFF shaped like a raw file: a first directory with image
/// tags, the capture time [dateTime], an EXIF directory holding
/// [original] (DateTimeOriginal) and a GPS directory as [gps] says, a
/// second directory after it, and [imageBytes] of image data at the end.
/// With [filler], the first directory also has a value of that many bytes.
///
/// The image data starts on an even offset, so the file's length is odd
/// when [imageBytes] is.
Uint8List testTiff({
  Endian endian = Endian.little,
  TestGps gps = TestGps.versionOnly,
  String? original = '2026:11:05 10:15:30',
  String? dateTime = '2026:11:05 10:15:30',
  int imageBytes = 2000,
  int filler = 0,
}) {
  final b = TiffBuilder(endian);
  const version = [2, 3, 0, 0];
  final exifAt = original == null
      ? null
      : b.directory([
          b.ascii(tagDateTimeOriginal, original),
          b.short(0x8827, 200),
        ]);
  final gpsAt = switch (gps) {
    TestGps.none => null,
    TestGps.versionOnly => b.directory([b.bytes(0x00, version)]),
    TestGps.direction => b.directory([
      b.bytes(0x00, version),
      b.ascii(0x10, 'T'),
      b.rationals(0x11, [(12345, 100)]),
    ]),
    TestGps.located => b.directory([
      b.bytes(0x00, version),
      b.ascii(0x01, 'N'),
      b.rationals(0x02, [(10, 1), (20, 1), (30, 1)]),
      b.ascii(0x03, 'E'),
      b.rationals(0x04, [(40, 1), (50, 1), (0, 1)]),
    ]),
  };
  final secondAt = b.directory([b.short(0x0100, 16), b.short(0x0101, 12)]);
  final entries = [
    b.short(0x0100, 64),
    b.short(0x0101, 48),
    b.ascii(0x010F, 'TEST CAMERA'),
    if (dateTime != null) b.ascii(tagDateTime, dateTime),
    if (exifAt != null) b.long(tagExif, exifAt),
    if (gpsAt != null) b.long(tagGps, gpsAt),
    if (filler > 0) b.bytes(0xC634, List.filled(filler, 0x5A)),
    // A tag after the GPS tag, so a GPS tag added later goes between two.
    b.bytes(0xC612, [1, 4, 0, 0]),
  ];
  // The image data follows the first directory, whose size is known from
  // its entry count.
  final firstAt = b.length + (b.length.isOdd ? 1 : 0);
  final imageAt = firstAt + 2 + 12 * (entries.length + 2) + 4;
  final first = b.directory([
    ...entries,
    b.long(0x0111, imageAt),
    b.long(0x0117, imageBytes),
  ], next: secondAt);
  final image = b.data(noise(imageBytes));
  if (first != firstAt || image != imageAt) {
    throw StateError('The synthetic TIFF is laid out wrong');
  }
  return b.build(first);
}

/// One JPEG segment: its marker, its length and [payload].
List<int> jpegSegment(int marker, List<int> payload) {
  final length = payload.length + 2;
  if (length > 0xFFFF) throw ArgumentError.value(length, 'payload');
  return [0xFF, marker, length >> 8, length & 0xFF, ...payload];
}

/// What follows the image data in [testJpeg].
const jpegTrailer = [0xFF, 0xD9, 0x01, 0x02, 0x03];

/// A JPEG's structure around made-up content: a JFIF segment, the EXIF
/// segment with [exif] as its TIFF data (none when null), an XMP segment,
/// a quantization table, about [scanBytes] of image data (with an FF that
/// is data and a restart marker in it), the end marker and three bytes
/// after it.
Uint8List testJpeg({Uint8List? exif, int scanBytes = 3000}) {
  const jfif = [0x4A, 0x46, 0x49, 0x46, 0, 1, 2, 0, 0, 1, 0, 1, 0, 0];
  final xmp = [
    ...'http://ns.adobe.com/xap/1.0/'.codeUnits,
    0,
    ...'<x:xmpmeta/>'.codeUnits,
  ];
  return Uint8List.fromList([
    0xFF, 0xD8, //
    ...jpegSegment(0xE0, jfif),
    if (exif != null) ...jpegSegment(0xE1, [...exifId, ...exif]),
    ...jpegSegment(0xE1, xmp),
    ...jpegSegment(0xDB, [0, ...List.filled(64, 16)]),
    ...jpegSegment(0xDA, [1, 1, 0, 0, 63, 0]),
    ...noise(scanBytes ~/ 2, seed: 11),
    0xFF, 0x00, 0xFF, 0xD0, //
    ...noise(scanBytes ~/ 2, seed: 13),
    ...jpegTrailer,
  ]);
}

/// A JPEG segment's place in its file: `start` is its FF byte, `end` the
/// byte after it.
typedef JpegSegment = ({int marker, int start, int end});

/// The segments of [jpeg] up to and with the one that starts the image
/// data.
List<JpegSegment> jpegSegments(Uint8List jpeg) {
  final segments = <JpegSegment>[];
  var at = 2;
  while (true) {
    if (jpeg[at] != 0xFF) fail('No marker at $at');
    final marker = jpeg[at + 1];
    final end = at + 2 + (jpeg[at + 2] << 8 | jpeg[at + 3]);
    segments.add((marker: marker, start: at, end: end));
    if (marker == 0xDA) return segments;
    at = end;
  }
}

/// The EXIF segment of [jpeg].
JpegSegment exifSegment(Uint8List jpeg) => jpegSegments(jpeg).firstWhere(
  (s) =>
      s.marker == 0xE1 &&
      String.fromCharCodes(jpeg, s.start + 4, s.start + 10) ==
          String.fromCharCodes(exifId),
);

/// The TIFF data in the EXIF segment of [jpeg].
Uint8List exifTiff(Uint8List jpeg) {
  final segment = exifSegment(jpeg);
  return jpeg.sublist(segment.start + 10, segment.end);
}

/// The byte order [tiff]'s header names.
Endian endianOf(Uint8List tiff) => tiff[0] == 0x49 ? Endian.little : Endian.big;

/// The offset of the first directory in [tiff]'s header.
int firstDirectoryOf(Uint8List tiff) =>
    ByteData.sublistView(tiff).getUint32(4, endianOf(tiff));

/// [bytes] with the 32-bit number at [at] set to [value].
Uint8List withLong(Uint8List bytes, int at, int value) {
  final copy = Uint8List.fromList(bytes);
  ByteData.sublistView(copy).setUint32(at, value, endianOf(bytes));
  return copy;
}

/// [bytes] with the 16-bit number at [at] set to [value].
Uint8List withShort(Uint8List bytes, int at, int value) {
  final copy = Uint8List.fromList(bytes);
  ByteData.sublistView(copy).setUint16(at, value, endianOf(bytes));
  return copy;
}

/// Where [before] and [after] differ, among the bytes [before] has.
List<int> changedBytes(Uint8List before, Uint8List after) => [
  for (var i = 0; i < before.length; i++)
    if (i >= after.length || before[i] != after[i]) i,
];

/// One directory entry read back from a file.
final class ReadEntry {
  new({
    required this.raw,
    required this.fieldAt,
    required this.type,
    required this.count,
    required this.valuesAt,
    required this.data,
    required this.endian,
  });

  /// The entry's twelve bytes.
  final Uint8List raw;

  /// Where its four-byte value field is in the TIFF data.
  final int fieldAt;
  final int type;
  final int count;

  /// Where its values are when they are not in the entry itself.
  final int? valuesAt;

  /// The bytes of its values.
  final Uint8List data;
  final Endian endian;

  /// A SHORT or LONG value.
  int get number => type == typeShort
      ? ByteData.sublistView(data).getUint16(0, endian)
      : ByteData.sublistView(data).getUint32(0, endian);

  /// An ASCII value without the NUL that ends it.
  String get text {
    if (data.last != 0) fail('An ASCII value does not end with NUL');
    return String.fromCharCodes(data, 0, data.length - 1);
  }

  /// RATIONAL values as `[numerator, denominator]` pairs.
  List<List<int>> get rationals {
    final view = ByteData.sublistView(data);
    return [
      for (var i = 0; i < count; i++)
        [view.getUint32(8 * i, endian), view.getUint32(8 * i + 4, endian)],
    ];
  }

  /// The value in the form its type has: a text, a list of bytes or pairs,
  /// or a number.
  Object get value => switch (type) {
    typeAscii => text,
    typeByte => data.toList(),
    typeRational => rationals,
    _ => number,
  };
}

/// A directory read back from a file.
final class ReadDirectory {
  new(this.offset, this.tags, this.entries, this.next);

  final int offset;

  /// The tags in the order of the entries.
  final List<int> tags;
  final Map<int, ReadEntry> entries;

  /// The offset of the next directory.
  final int next;

  ReadEntry operator [](int tag) => entries[tag]!;

  /// Every value by its tag.
  Map<int, Object> get values => {
    for (final tag in tags) tag: entries[tag]!.value,
  };

  /// The `[type, count]` of every entry by its tag.
  Map<int, List<int>> get shapes => {
    for (final tag in tags) tag: [entries[tag]!.type, entries[tag]!.count],
  };
}

const Map<int, int> _typeSizes = {
  typeByte: 1,
  typeAscii: 1,
  typeShort: 2,
  typeLong: 4,
  typeRational: 8,
};

/// Reads the directory at [offset] of [tiff], checking on the way that it
/// and its values are inside [tiff] and on even offsets.
ReadDirectory readDirectory(Uint8List tiff, int offset) {
  final endian = endianOf(tiff);
  final view = ByteData.sublistView(tiff);
  if (offset.isOdd) fail('A directory on the odd offset $offset');
  final count = view.getUint16(offset, endian);
  final tags = <int>[];
  final entries = <int, ReadEntry>{};
  for (var i = 0; i < count; i++) {
    final at = offset + 2 + 12 * i;
    final tag = view.getUint16(at, endian);
    final type = view.getUint16(at + 2, endian);
    final values = view.getUint32(at + 4, endian);
    final size = _typeSizes[type]! * values;
    final valuesAt = size > 4 ? view.getUint32(at + 8, endian) : null;
    if (valuesAt != null && valuesAt.isOdd) {
      fail('Values on the odd offset $valuesAt');
    }
    final start = valuesAt ?? at + 8;
    tags.add(tag);
    entries[tag] = ReadEntry(
      raw: tiff.sublist(at, at + 12),
      fieldAt: at + 8,
      type: type,
      count: values,
      valuesAt: valuesAt,
      data: tiff.sublist(start, start + size),
      endian: endian,
    );
  }
  final next = view.getUint32(offset + 2 + 12 * count, endian);
  return ReadDirectory(offset, tags, entries, next);
}

/// The first directory of [tiff].
ReadDirectory firstDirectory(Uint8List tiff) =>
    readDirectory(tiff, firstDirectoryOf(tiff));

/// The names of the files in [dir], sorted.
List<String> namesIn(Directory dir) =>
    [for (final entry in dir.listSync()) entry.uri.pathSegments.last]..sort();
