import 'dart:typed_data';

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
