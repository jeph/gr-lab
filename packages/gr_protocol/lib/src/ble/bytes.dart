import 'dart:typed_data';

import 'package:gr_protocol/src/ble/codecs.dart';

/// Hex conversion for BLE payloads in traces, JSON output and CLI input.
abstract final class BleBytes {
  /// Lowercase hex without separators.
  static String toHex(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  /// Parses hex digit pairs. Accepts an optional `0x` prefix and spaces,
  /// colons or dashes between bytes. Throws [FormatException].
  static Uint8List fromHex(String text) {
    var digits = text.trim();
    if (digits.startsWith('0x') || digits.startsWith('0X')) {
      digits = digits.substring(2);
    }
    digits = digits.replaceAll(RegExp(r'[\s:\-]'), '');
    if (digits.length.isOdd || !RegExp(r'^[0-9A-Fa-f]*$').hasMatch(digits)) {
      throw FormatException('Expected hex bytes', text);
    }
    final out = Uint8List(digits.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(digits.substring(2 * i, 2 * i + 2), radix: 16);
    }
    return out;
  }
}

/// Builds a payload one field after another.
final class BleByteWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  /// Bytes written so far.
  int get length => _out.length;

  /// Appends [value] in [format], little-endian. Throws [ArgumentError]
  /// naming [field] when [value] does not fit.
  void writeInt(int value, BleIntFormat format, String field) {
    format.check(value, field);
    for (var i = 0; i < format.width; i++) {
      _out.addByte((value >> (8 * i)) & 0xff);
    }
  }

  /// Appends zeros until the payload is [size] bytes. Throws [StateError]
  /// when more than [size] bytes are already written.
  void padTo(int size) {
    if (length > size) {
      throw StateError('$length bytes written, more than the $size allowed');
    }
    _out.add(Uint8List(size - length));
  }

  /// The payload written.
  Uint8List toBytes() => _out.toBytes();
}

/// Reads a payload one field after another.
final class BleByteReader {
  /// Reads the given bytes from the start.
  new(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  /// Bytes not read yet.
  int get remaining => _bytes.length - _offset;

  /// Whether a [format] integer is left to read.
  bool has(BleIntFormat format) => remaining >= format.width;

  /// Reads the next [format] integer. Throws [RangeError] when fewer than
  /// its width are left.
  int readInt(BleIntFormat format) {
    if (!has(format)) {
      throw RangeError(
        '${format.name} needs ${format.width} bytes, '
        '$remaining left',
      );
    }
    final value = format.read(_bytes, _offset);
    _offset += format.width;
    return value;
  }

  /// Reads everything left.
  Uint8List readRest() {
    final rest = Uint8List.sublistView(_bytes, _offset);
    _offset = _bytes.length;
    return rest;
  }
}
