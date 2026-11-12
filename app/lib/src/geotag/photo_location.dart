import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gr_camera/gr_camera.dart';

/// What [writeLocation] did with a file.
enum PhotoLocationOutcome {
  /// The file has the location now.
  written,

  /// The file had a location already (the camera wrote one); it was left
  /// as it was.
  alreadyLocated,

  /// Not a file that can take a location: a movie, a JPEG without EXIF or
  /// with no room left in its EXIF segment, a BigTIFF. Left as it was.
  unsupported,

  /// The file could not be read, does not hold together as a JPEG or TIFF
  /// (something in it points outside it, or it was cut short), or could
  /// not be written. Left as it was.
  failed,
}

/// The capture time in the file (EXIF DateTimeOriginal: the camera's local
/// time, no zone), as a local DateTime in the phone's current zone; null
/// when the file has none or is not a JPEG/DNG.
///
/// A file without a readable DateTimeOriginal gives its DateTime (the tag
/// of the first directory) instead, which a camera sets to the same moment.
/// Never throws.
Future<DateTime?> readCaptureTime(File file) async {
  try {
    final source = await file.open();
    try {
      final length = await source.length();
      final tiff = switch (await _kindOf(source)) {
        _Kind.tiff => await _Tiff.open(source, base: 0, length: length),
        _Kind.jpeg => switch (await _findExif(source, length)) {
          null => null,
          final exif => await _Tiff.open(
            source,
            base: exif.tiffAt,
            length: exif.end - exif.tiffAt,
          ),
        },
        _Kind.other => null,
      };
      return tiff == null ? null : await _captureTime(tiff);
    } finally {
      await source.close();
    }
  } on _Malformed {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// Writes [fix] into the file's GPS directory in place. Never throws.
///
/// A JPEG (EXIF in its APP1 segment) or a DNG (any classic TIFF) gets a new
/// GPS directory with GPSVersionID (2.3.0.0), GPSLatitudeRef, GPSLatitude,
/// GPSLongitudeRef, GPSLongitude, GPSAltitudeRef and GPSAltitude (when
/// [fix] has an altitude), GPSTimeStamp and GPSDateStamp (when the phone
/// took [fix], UTC, so the photo shows how old its position is) and
/// GPSMapDatum (WGS-84). A file whose GPS directory has a GPSLatitude
/// already is left alone ([PhotoLocationOutcome.alreadyLocated]); other
/// tags of a directory without one are carried over.
///
/// Nothing in the file moves \[design\]: the new directory goes after the
/// end of the TIFF data, and the only bytes changed are the four of the
/// pointer to it (the value of the first directory's GPS tag or, when that
/// directory has no GPS tag, the header's offset of the first directory,
/// which then points to a copy of it that has the tag). In a JPEG the TIFF
/// data is the EXIF segment, which grows by the new directory; the
/// segments and image data after it are the same bytes further on.
///
/// A file is changed only when it holds together: every directory its
/// TIFF data leads to, the values of their entries and the image data
/// they give the place of are inside it, and a JPEG goes on through its
/// segments and image data to its end marker. The changed file is written
/// beside [file] and takes its place only once it is complete, so whatever
/// the outcome but [PhotoLocationOutcome.written], [file] is as it was.
Future<PhotoLocationOutcome> writeLocation(File file, LocationFix fix) async {
  final copy = File('${file.path}.${_copies++}.tmp');
  try {
    final outcome = await _writeLocated(file, copy, fix);
    if (outcome == PhotoLocationOutcome.written) await copy.rename(file.path);
    return outcome;
  } on Object {
    // Whatever went wrong, the photo is still the one that came from the
    // camera, and its download goes on without a location.
    _discard(copy);
    return PhotoLocationOutcome.failed;
  }
}

/// Numbers each [writeLocation]'s copy, so two of them on one file never
/// write into the same one.
int _copies = 0;

const _tagDateTime = 0x0132;
const _tagExifDirectory = 0x8769;
const _tagGpsDirectory = 0x8825;
const _tagDateTimeOriginal = 0x9003;

/// The tags whose values are offsets of other directories: SubIFDs (the
/// raw image of a DNG), the EXIF and GPS directories, and the EXIF
/// directory's Interoperability directory.
const Set<int> _directoryTags = {
  0x014A,
  _tagExifDirectory,
  _tagGpsDirectory,
  0xA005,
};

/// The pairs of tags that give the offsets and the lengths of data kept
/// outside the directories: strips, tiles, and the thumbnail in a JPEG's
/// EXIF.
const _dataTags = [(0x0111, 0x0117), (0x0144, 0x0145), (0x0201, 0x0202)];

/// More directories than any photo has; a file with more is not followed
/// further.
const _maxDirectories = 256;

const _gpsVersionId = 0x00;
const _gpsLatitudeRef = 0x01;
const _gpsLatitude = 0x02;
const _gpsLongitudeRef = 0x03;
const _gpsLongitude = 0x04;
const _gpsAltitudeRef = 0x05;
const _gpsAltitude = 0x06;
const _gpsTimeStamp = 0x07;
const _gpsMapDatum = 0x12;
const _gpsDateStamp = 0x1D;

const _typeByte = 1;
const _typeAscii = 2;
const _typeShort = 3;
const _typeLong = 4;
const _typeRational = 5;
const _typeDirectory = 13;

/// How many bytes one value of each type takes (TIFF 6.0, section 2, the
/// IFD type of its supplement 1, and the UTF-8 type of Exif 3.0).
const Map<int, int> _typeSizes = {
  _typeByte: 1,
  _typeAscii: 1,
  _typeShort: 2,
  _typeLong: 4,
  _typeRational: 8,
  6: 1,
  7: 1,
  8: 2,
  9: 4,
  10: 8,
  11: 4,
  12: 8,
  _typeDirectory: 4,
  129: 1,
};

/// The size of a directory entry: tag, type, count, value or offset.
const _entrySize = 12;

/// `YYYY:MM:DD HH:MM:SS`, the form of every EXIF time.
const _timeLength = 19;
final _timeForm = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$');

const _markerStartOfScan = 0xDA;
const _markerEndOfImage = 0xD9;
const _markerApp1 = 0xE1;

/// What an EXIF segment's data starts with, before its TIFF header.
const _exifId = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];

/// The largest value a 32-bit TIFF offset or count holds.
const _maxUint32 = 0xFFFFFFFF;

/// The file is not the JPEG or TIFF its first bytes say it is: something
/// in it points outside it, or it ends early.
final class _Malformed implements Exception {
  const new();
}

enum _Kind { jpeg, tiff, other }

/// What [source] is by its first bytes. A BigTIFF (64-bit offsets) is not
/// a TIFF here.
Future<_Kind> _kindOf(RandomAccessFile source) async {
  await source.setPosition(0);
  final head = await source.read(4);
  if (head.length >= 2 && head[0] == 0xFF && head[1] == 0xD8) {
    return _Kind.jpeg;
  }
  if (head.length < 4) return _Kind.other;
  return switch ((head[0], head[1], head[2], head[3])) {
    (0x49, 0x49, 0x2A, 0x00) || (0x4D, 0x4D, 0x00, 0x2A) => _Kind.tiff,
    _ => _Kind.other,
  };
}

/// One marker of a JPEG and what belongs to it: the FF before `marker`
/// is at `at`, and `end` is where the next marker is due.
typedef _Segment = ({int marker, int at, int end});

/// The segment of the JPEG [source] whose marker is at [at], or after the
/// FF bytes that may come before a marker. Throws [_Malformed] when no
/// marker is there or the segment does not fit into the [length] bytes of
/// the file.
Future<_Segment> _segmentAt(RandomAccessFile source, int at, int length) async {
  var start = at;
  while (true) {
    if (start + 2 > length) throw const _Malformed();
    await source.setPosition(start);
    final head = await source.read(4);
    if (head.length < 2 || head[0] != 0xFF) throw const _Malformed();
    final marker = head[1];
    if (marker == 0xFF) {
      start++;
      continue;
    }
    if (marker == 0x00) throw const _Malformed();
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      // A marker that stands alone, with no length after it.
      return (marker: marker, at: start, end: start + 2);
    }
    if (head.length < 4) throw const _Malformed();
    final size = head[2] << 8 | head[3];
    final end = start + 2 + size;
    if (size < 2 || end > length) throw const _Malformed();
    return (marker: marker, at: start, end: end);
  }
}

/// Where a JPEG's EXIF segment is in its file: its two length bytes at
/// `lengthAt`, its TIFF header at `tiffAt`, and its `end`.
typedef _ExifSegment = ({int lengthAt, int tiffAt, int end});

/// The EXIF segment among those before the image data of the JPEG
/// [source], or null when it has none. Throws [_Malformed].
Future<_ExifSegment?> _findExif(RandomAccessFile source, int length) async {
  var at = 2;
  while (true) {
    final segment = await _segmentAt(source, at, length);
    if (segment.marker == _markerStartOfScan ||
        segment.marker == _markerEndOfImage) {
      return null;
    }
    final tiffAt = segment.at + 4 + _exifId.length;
    if (segment.marker == _markerApp1 && tiffAt <= segment.end) {
      await source.setPosition(segment.at + 4);
      final id = await source.read(_exifId.length);
      if (_listsEqual(id, _exifId)) {
        return (lengthAt: segment.at + 2, tiffAt: tiffAt, end: segment.end);
      }
    }
    at = segment.end;
  }
}

/// Checks that the JPEG [source] goes on from the marker at [from] to the
/// end of its image: every segment fits into the [length] bytes of the
/// file and the image data ends with the end marker. What follows that
/// marker is not looked at. Throws [_Malformed] otherwise.
Future<void> _checkImage(RandomAccessFile source, int from, int length) async {
  var at = from;
  while (true) {
    final segment = await _segmentAt(source, at, length);
    if (segment.marker == _markerEndOfImage) return;
    at = segment.marker == _markerStartOfScan
        ? await _scanEnd(source, segment.end, length)
        : segment.end;
  }
}

/// Where the image data that starts at [from] in the JPEG [source] ends:
/// the FF of the next marker. In the data an FF is followed by 00 (it is
/// data) or by a restart marker (D0 to D7). Throws [_Malformed] when the
/// file ends first.
Future<int> _scanEnd(RandomAccessFile source, int from, int length) async {
  await source.setPosition(from);
  final buffer = Uint8List(math.min(math.max(length - from, 0), 1 << 20));
  var at = from;
  var afterFF = false;
  while (at < length) {
    final wanted = math.min(buffer.length, length - at);
    final read = await source.readInto(buffer, 0, wanted);
    if (read <= 0) break;
    for (var i = 0; i < read; i++) {
      final byte = buffer[i];
      if (!afterFF) {
        afterFF = byte == 0xFF;
        continue;
      }
      // Another FF fills up; the marker is still to come.
      if (byte == 0xFF) continue;
      afterFF = false;
      if (byte != 0x00 && (byte < 0xD0 || byte > 0xD7)) return at + i - 1;
    }
    at += read;
  }
  throw const _Malformed();
}

bool _listsEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Classic TIFF data inside an open file: a whole DNG, or the EXIF segment
/// of a JPEG from its TIFF header on. Offsets count from that header, as
/// TIFF's own do.
final class _Tiff {
  new _(this._file, this._base, this.length, this.endian, this.firstDirectory);

  /// Reads the header of the [length] bytes of TIFF data at [base] of
  /// [file]. Throws [_Malformed].
  static Future<_Tiff> open(
    RandomAccessFile file, {
    required int base,
    required int length,
  }) async {
    if (length < 8) throw const _Malformed();
    await file.setPosition(base);
    final header = await file.read(8);
    if (header.length < 8) throw const _Malformed();
    final endian = switch ((header[0], header[1])) {
      (0x49, 0x49) => Endian.little,
      (0x4D, 0x4D) => Endian.big,
      _ => throw const _Malformed(),
    };
    final view = ByteData.sublistView(header);
    if (view.getUint16(2, endian) != 42) throw const _Malformed();
    return _Tiff._(file, base, length, endian, view.getUint32(4, endian));
  }

  final RandomAccessFile _file;
  final int _base;

  /// How many bytes the TIFF data has.
  final int length;

  /// The byte order of every number in it.
  final Endian endian;

  /// The offset of the first directory (IFD0), from the header.
  final int firstDirectory;

  /// Throws [_Malformed] when the [count] bytes at [offset] are not all
  /// inside the data.
  void check(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw const _Malformed();
    }
  }

  /// The [count] bytes at [offset]. Throws [_Malformed] when they are not
  /// all inside the data.
  Future<Uint8List> read(int offset, int count) async {
    check(offset, count);
    await _file.setPosition(_base + offset);
    final bytes = await _file.read(count);
    if (bytes.length != count) throw const _Malformed();
    return bytes;
  }

  /// The directory at [offset]. Throws [_Malformed].
  Future<_Directory> directory(int offset) async {
    // The header is there.
    if (offset < 8) throw const _Malformed();
    final head = ByteData.sublistView(await read(offset, 2));
    final entries = head.getUint16(0, endian);
    final bytes = await read(offset, 2 + _entrySize * entries + 4);
    return _Directory(offset, bytes, endian);
  }
}

/// One TIFF directory (IFD) as it is in the file: the number of entries,
/// the entries, and the offset of the next directory.
final class _Directory {
  new(this.offset, this.bytes, this.endian)
    : _view = ByteData.sublistView(bytes);

  /// Where the directory starts, from the TIFF header.
  final int offset;

  /// Its bytes, from the entry count to the next directory's offset.
  final Uint8List bytes;

  /// The byte order of its numbers.
  final Endian endian;
  final ByteData _view;

  /// How many entries it has.
  int get count => (bytes.length - 6) ~/ _entrySize;

  int _at(int index) => 2 + _entrySize * index;

  /// The tag of entry [index].
  int tag(int index) => _view.getUint16(_at(index), endian);

  /// The value type of entry [index].
  int type(int index) => _view.getUint16(_at(index) + 2, endian);

  /// How many values entry [index] has.
  int valueCount(int index) => _view.getUint32(_at(index) + 4, endian);

  /// The value field of entry [index] as a 32-bit number: the offset of
  /// its values when they do not fit into four bytes.
  int value(int index) => _view.getUint32(_at(index) + 8, endian);

  /// Where the value field of entry [index] is, from the TIFF header.
  int valueAt(int index) => offset + _at(index) + 8;

  /// The four bytes of the value field of entry [index].
  Uint8List field(int index) =>
      Uint8List.sublistView(bytes, _at(index) + 8, _at(index) + _entrySize);

  /// The offset of the directory after this one; 0 when it is the last.
  int get next => _view.getUint32(bytes.length - 4, endian);

  /// The twelve bytes of entry [index].
  Uint8List entry(int index) =>
      Uint8List.sublistView(bytes, _at(index), _at(index) + _entrySize);

  /// The first entry with [tag], or null when there is none.
  int? indexOf(int tag) {
    for (var i = 0; i < count; i++) {
      if (this.tag(i) == tag) return i;
    }
    return null;
  }

  /// The offset of the directory entry [index] points to. Throws
  /// [_Malformed] when the entry is not one offset.
  int pointer(int index) {
    final type = this.type(index);
    if ((type != _typeLong && type != _typeDirectory) ||
        valueCount(index) != 1) {
      throw const _Malformed();
    }
    return value(index);
  }

  /// A copy of this directory with one more entry, [tag], pointing to the
  /// directory at [target]. The entry goes where its tag belongs (entries
  /// are sorted by tag); the others and the next directory's offset are
  /// the same bytes. Throws [_Malformed] when no entry can be added.
  Uint8List withPointer(int tag, int target) {
    if (count == 0xFFFF) throw const _Malformed();
    var index = 0;
    while (index < count && this.tag(index) < tag) {
      index++;
    }
    final at = _at(index);
    final copy = Uint8List(bytes.length + _entrySize)
      ..setRange(0, at, bytes)
      ..setRange(at + _entrySize, bytes.length + _entrySize, bytes, at);
    ByteData.sublistView(copy)
      ..setUint16(0, count + 1, endian)
      ..setUint16(at, tag, endian)
      ..setUint16(at + 2, _typeLong, endian)
      ..setUint32(at + 4, 1, endian)
      ..setUint32(at + 8, target, endian);
    return copy;
  }
}

/// The SHORT, LONG or IFD values of entry [index] of [directory]: offsets
/// or lengths. Throws [_Malformed] when the entry holds something else or
/// its values are not all inside [tiff].
Future<List<int>> _numbers(_Tiff tiff, _Directory directory, int index) async {
  final size = switch (directory.type(index)) {
    _typeShort => 2,
    _typeLong || _typeDirectory => 4,
    _ => throw const _Malformed(),
  };
  final count = directory.valueCount(index);
  final bytes = size * count <= 4
      ? directory.field(index)
      : await tiff.read(directory.value(index), size * count);
  final view = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < count; i++)
      if (size == 2)
        view.getUint16(2 * i, tiff.endian)
      else
        view.getUint32(4 * i, tiff.endian),
  ];
}

/// Checks that [tiff] holds together before anything is added to it: every
/// directory that can be reached (the chain from the first one, and the
/// directories their tags point to) is inside it, and so are the values
/// of every entry and the image data the directories give the place of.
/// A file cut short fails here. Throws [_Malformed].
///
/// What is inside a value (a maker note, say) is not looked at, and an
/// entry of a type not known here is passed over, as TIFF 6.0 asks of a
/// reader.
Future<void> _checkWhole(_Tiff tiff) async {
  final pending = [tiff.firstDirectory];
  final checked = <int>{};
  while (pending.isNotEmpty) {
    final offset = pending.removeLast();
    // Two tags may point to one directory, and a chain that comes back to
    // a directory must not be followed for ever.
    if (!checked.add(offset)) continue;
    if (checked.length > _maxDirectories) throw const _Malformed();
    final directory = await tiff.directory(offset);
    if (directory.next != 0) pending.add(directory.next);
    for (var i = 0; i < directory.count; i++) {
      final size = _typeSizes[directory.type(i)];
      if (size == null) continue;
      final length = size * directory.valueCount(i);
      if (length > 4) tiff.check(directory.value(i), length);
      if (_directoryTags.contains(directory.tag(i))) {
        pending.addAll(await _numbers(tiff, directory, i));
      }
    }
    for (final (offsetsTag, lengthsTag) in _dataTags) {
      final offsetsEntry = directory.indexOf(offsetsTag);
      final lengthsEntry = directory.indexOf(lengthsTag);
      if (offsetsEntry == null || lengthsEntry == null) continue;
      final offsets = await _numbers(tiff, directory, offsetsEntry);
      final lengths = await _numbers(tiff, directory, lengthsEntry);
      if (offsets.length != lengths.length) throw const _Malformed();
      for (var i = 0; i < offsets.length; i++) {
        tiff.check(offsets[i], lengths[i]);
      }
    }
  }
}

/// The capture time [tiff] holds, or null. Throws [_Malformed] when the
/// first directory cannot be read.
Future<DateTime?> _captureTime(_Tiff tiff) async {
  final first = await tiff.directory(tiff.firstDirectory);
  try {
    final exif = first.indexOf(_tagExifDirectory);
    if (exif != null) {
      final original = await _timeIn(
        tiff,
        await tiff.directory(first.pointer(exif)),
        _tagDateTimeOriginal,
      );
      if (original != null) return original;
    }
  } on _Malformed {
    // A damaged EXIF directory still leaves the first directory's time.
  }
  return await _timeIn(tiff, first, _tagDateTime);
}

/// The time the entry [tag] of [directory] holds, or null when there is no
/// such entry or it holds no time. Throws [_Malformed].
Future<DateTime?> _timeIn(_Tiff tiff, _Directory directory, int tag) async {
  final index = directory.indexOf(tag);
  if (index == null ||
      directory.type(index) != _typeAscii ||
      directory.valueCount(index) < _timeLength) {
    return null;
  }
  final text = await tiff.read(directory.value(index), _timeLength);
  final match = _timeForm.firstMatch(String.fromCharCodes(text));
  if (match == null) return null;
  final [year, month, day, hour, minute, second] = [
    for (var group = 1; group <= 6; group++) int.parse(match[group]!),
  ];
  // The date is checked in UTC, which has every hour of every day: a time
  // in the hour the phone's zone skips in spring is still what the
  // camera's clock showed. A camera with no time set writes zeros.
  final date = DateTime.utc(year, month, day);
  if (year == 0 ||
      date.month != month ||
      date.day != day ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  return DateTime(year, month, day, hour, minute, second);
}

/// Writes [file] with [fix] into [copy] and says what became of it; only
/// [PhotoLocationOutcome.written] leaves a complete [copy]. Throws when
/// [file] is malformed or a file operation fails.
Future<PhotoLocationOutcome> _writeLocated(
  File file,
  File copy,
  LocationFix fix,
) async {
  if (!_writable(fix)) return PhotoLocationOutcome.failed;
  final source = await file.open();
  try {
    final length = await source.length();
    switch (await _kindOf(source)) {
      case _Kind.tiff:
        return await _writeLocatedTiff(file, source, length, copy, fix);
      case _Kind.jpeg:
        return await _writeLocatedJpeg(source, length, copy, fix);
      case _Kind.other:
        return PhotoLocationOutcome.unsupported;
    }
  } finally {
    await source.close();
  }
}

Future<PhotoLocationOutcome> _writeLocatedTiff(
  File file,
  RandomAccessFile source,
  int length,
  File copy,
  LocationFix fix,
) async {
  final tiff = await _Tiff.open(source, base: 0, length: length);
  final edit = await _locate(tiff, fix);
  if (edit == null) return PhotoLocationOutcome.alreadyLocated;
  // A classic TIFF cannot point past 4 GB.
  if (length + edit.appended.length > _maxUint32) {
    return PhotoLocationOutcome.unsupported;
  }
  await _checkWhole(tiff);
  // The file system copies the file, so a raw file of tens of megabytes
  // never passes through memory.
  await file.copy(copy.path);
  // Append mode opens the copy for reading and writing as it is, placed
  // at its end; writes go where the position is set.
  final out = await copy.open(mode: FileMode.append);
  try {
    // The offsets were worked out for the file as it was read.
    if (await out.length() != length) throw const _Malformed();
    await out.writeFrom(edit.appended);
    await out.setPosition(edit.pointerAt);
    await out.writeFrom(_uint32(edit.pointer, tiff.endian));
    await out.flush();
  } finally {
    await out.close();
  }
  return PhotoLocationOutcome.written;
}

Future<PhotoLocationOutcome> _writeLocatedJpeg(
  RandomAccessFile source,
  int length,
  File copy,
  LocationFix fix,
) async {
  final exif = await _findExif(source, length);
  if (exif == null) return PhotoLocationOutcome.unsupported;
  final tiff = await _Tiff.open(
    source,
    base: exif.tiffAt,
    length: exif.end - exif.tiffAt,
  );
  final edit = await _locate(tiff, fix);
  if (edit == null) return PhotoLocationOutcome.alreadyLocated;
  // A segment's length is two bytes and counts itself.
  final segmentLength = exif.end - exif.lengthAt + edit.appended.length;
  if (segmentLength > 0xFFFF) return PhotoLocationOutcome.unsupported;
  await _checkWhole(tiff);
  await _checkImage(source, exif.end, length);
  final data = await tiff.read(0, tiff.length);
  data.setRange(
    edit.pointerAt,
    edit.pointerAt + 4,
    _uint32(edit.pointer, tiff.endian),
  );

  final out = await copy.open(mode: FileMode.write);
  try {
    await _copyBytes(source, out, start: 0, end: exif.lengthAt);
    await out.writeFrom([segmentLength >> 8, segmentLength & 0xFF]);
    await _copyBytes(source, out, start: exif.lengthAt + 2, end: exif.tiffAt);
    await out.writeFrom(data);
    await out.writeFrom(edit.appended);
    await _copyBytes(source, out, start: exif.end, end: length);
    await out.flush();
  } finally {
    await out.close();
  }
  return PhotoLocationOutcome.written;
}

/// Copies the bytes of [from] between [start] and [end] to where [to] is,
/// a piece at a time. Throws [_Malformed] when [from] ends before [end].
Future<void> _copyBytes(
  RandomAccessFile from,
  RandomAccessFile to, {
  required int start,
  required int end,
}) async {
  await from.setPosition(start);
  var left = end - start;
  final buffer = Uint8List(math.min(left, 1 << 20));
  while (left > 0) {
    final wanted = math.min(buffer.length, left);
    final read = await from.readInto(buffer, 0, wanted);
    if (read <= 0) throw const _Malformed();
    await to.writeFrom(buffer, 0, read);
    left -= read;
  }
}

void _discard(File copy) {
  try {
    if (copy.existsSync()) copy.deleteSync();
  } on FileSystemException {
    // A leftover beside the photo is deleted with the download's folder.
  }
}

Uint8List _uint32(int value, Endian endian) =>
    (ByteData(4)..setUint32(0, value, endian)).buffer.asUint8List();

/// What gives TIFF data a location: `appended` goes right after its end,
/// and the 32-bit number at `pointerAt` becomes `pointer`. Nothing else
/// changes.
typedef _Edit = ({Uint8List appended, int pointerAt, int pointer});

/// The edit that writes [fix] into [tiff], or null when [tiff] has a
/// location already. Throws [_Malformed].
Future<_Edit?> _locate(_Tiff tiff, LocationFix fix) async {
  final endian = tiff.endian;
  final first = await tiff.directory(tiff.firstDirectory);
  final fields = _gpsFields(fix, endian);
  final gpsEntry = first.indexOf(_tagGpsDirectory);
  var kept = const <Uint8List>[];
  if (gpsEntry != null) {
    final present = await tiff.directory(first.pointer(gpsEntry));
    if (present.indexOf(_gpsLatitude) != null) return null;
    // Whatever else the directory says stays said; a value kept outside
    // its entry is still where the entry points, as nothing moves.
    final written = {for (final field in fields) field.tag};
    kept = [
      for (var i = 0; i < present.count; i++)
        if (!written.contains(present.tag(i))) present.entry(i),
    ];
    // A directory counts its entries in 16 bits.
    if (kept.length + fields.length > 0xFFFF) throw const _Malformed();
  }

  // Directories and values start on even offsets (TIFF 6.0, section 2).
  final padding = tiff.length.isOdd ? 1 : 0;
  final gpsAt = tiff.length + padding;
  final gps = _gpsDirectory(fields, kept, at: gpsAt, endian: endian);
  final appended = BytesBuilder(copy: false)
    ..add(Uint8List(padding))
    ..add(gps);
  if (gpsEntry != null) {
    return (
      appended: appended.takeBytes(),
      pointerAt: first.valueAt(gpsEntry),
      pointer: gpsAt,
    );
  }
  // The first directory has no room for another entry where it is, so a
  // copy with the entry follows the GPS directory (whose length is even)
  // and the header points to the copy.
  appended.add(first.withPointer(_tagGpsDirectory, gpsAt));
  return (
    appended: appended.takeBytes(),
    pointerAt: 4,
    pointer: gpsAt + gps.length,
  );
}

/// One entry of a directory being built, its values in the file's byte
/// order.
typedef _Field = ({int tag, int type, int count, Uint8List value});

/// [fix] can be put into GPS tags: a place on Earth, at a time whose year
/// has four digits.
bool _writable(LocationFix fix) {
  final year = fix.time.toUtc().year;
  return fix.latitude.abs() <= 90 &&
      fix.longitude.abs() <= 180 &&
      year >= 0 &&
      year <= 9999;
}

/// The GPS tags of [fix], sorted by tag.
List<_Field> _gpsFields(LocationFix fix, Endian endian) {
  _Field bytes(int tag, List<int> values) => (
    tag: tag,
    type: _typeByte,
    count: values.length,
    value: Uint8List.fromList(values),
  );
  // An ASCII value ends with a NUL, which its count includes.
  _Field text(int tag, String value) => (
    tag: tag,
    type: _typeAscii,
    count: value.length + 1,
    value: Uint8List.fromList([...value.codeUnits, 0]),
  );
  _Field rationals(int tag, List<(int, int)> values) {
    final data = ByteData(8 * values.length);
    for (final (i, (numerator, denominator)) in values.indexed) {
      data
        ..setUint32(8 * i, numerator, endian)
        ..setUint32(8 * i + 4, denominator, endian);
    }
    return (
      tag: tag,
      type: _typeRational,
      count: values.length,
      value: data.buffer.asUint8List(),
    );
  }

  String digits(int value, int width) => value.toString().padLeft(width, '0');

  final time = fix.time.toUtc();
  // Metres above sea level (0) or below it (1), in hundredths, when the
  // phone gave a height that fits the tag's 32 bits.
  final altitude = fix.altitude;
  final below = altitude != null && altitude < 0;
  final height = altitude != null && altitude.abs() * 100 <= _maxUint32
      ? (altitude.abs() * 100).round()
      : null;
  return [
    bytes(_gpsVersionId, const [2, 3, 0, 0]),
    text(_gpsLatitudeRef, fix.latitude < 0 ? 'S' : 'N'),
    rationals(_gpsLatitude, _angle(fix.latitude)),
    text(_gpsLongitudeRef, fix.longitude < 0 ? 'W' : 'E'),
    rationals(_gpsLongitude, _angle(fix.longitude)),
    if (height != null) ...[
      bytes(_gpsAltitudeRef, [if (below) 1 else 0]),
      rationals(_gpsAltitude, [(height, 100)]),
    ],
    rationals(_gpsTimeStamp, [
      (time.hour, 1),
      (time.minute, 1),
      (time.second, 1),
    ]),
    text(_gpsMapDatum, 'WGS-84'),
    text(
      _gpsDateStamp,
      '${digits(time.year, 4)}:${digits(time.month, 2)}:'
      '${digits(time.day, 2)}',
    ),
  ];
}

/// [degrees] without its sign as degrees, minutes and seconds, the seconds
/// in ten-thousandths (about 3 mm on the ground).
List<(int, int)> _angle(double degrees) {
  const perSecond = 10000;
  // Rounded as one number, so that the seconds never round up to 60.
  final total = (degrees.abs() * 3600 * perSecond).round();
  return [
    (total ~/ (3600 * perSecond), 1),
    (total ~/ (60 * perSecond) % 60, 1),
    (total % (60 * perSecond), perSecond),
  ];
}

/// The bytes of a GPS directory at offset [at] (even) of TIFF data: the
/// entries of [fields] and the entries [kept] from the directory it takes
/// the place of, sorted by tag, no next directory, then the values of
/// [fields] that do not fit into an entry, each on an even offset. The
/// length is even.
Uint8List _gpsDirectory(
  List<_Field> fields,
  List<Uint8List> kept, {
  required int at,
  required Endian endian,
}) {
  final count = fields.length + kept.length;
  final valuesAt = at + 2 + _entrySize * count + 4;
  final values = BytesBuilder();
  final entries = [...kept];
  for (final field in fields) {
    final entry = Uint8List(_entrySize);
    final view = ByteData.sublistView(entry)
      ..setUint16(0, field.tag, endian)
      ..setUint16(2, field.type, endian)
      ..setUint32(4, field.count, endian);
    if (field.value.length <= 4) {
      // A value of up to four bytes is in the entry itself, from its left.
      entry.setRange(8, 8 + field.value.length, field.value);
    } else {
      view.setUint32(8, valuesAt + values.length, endian);
      values.add(field.value);
      if (values.length.isOdd) values.addByte(0);
    }
    entries.add(entry);
  }
  int tagOf(Uint8List entry) =>
      ByteData.sublistView(entry).getUint16(0, endian);
  entries.sort((a, b) => tagOf(a).compareTo(tagOf(b)));

  final directory = BytesBuilder()
    ..add((ByteData(2)..setUint16(0, count, endian)).buffer.asUint8List());
  entries.forEach(directory.add);
  directory
    ..add(Uint8List(4))
    ..add(values.takeBytes());
  return directory.takeBytes();
}
