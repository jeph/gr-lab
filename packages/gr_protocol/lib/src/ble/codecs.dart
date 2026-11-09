import 'dart:convert';
import 'dart:typed_data';

import 'package:gr_protocol/src/ble/bytes.dart';
import 'package:meta/meta.dart';

/// An enum whose members carry the integer sent on the wire.
abstract interface class BleWireEnum {
  /// Integer the camera sends and accepts for this member.
  int get wire;

  /// Stable identifier used in JSON output and accepted by CLI parsing.
  String get label;
}

/// A decoded enum field that keeps the raw integer, so values the camera
/// sends outside the documented table survive decoding.
@immutable
final class BleEnumValue<E extends BleWireEnum> {
  /// Pairs a [raw] wire value with its [known] member, if any.
  const new(this.raw, this.known);

  /// Value for writing [value] to the camera.
  factory of(E value) => BleEnumValue(value.wire, value);

  /// Looks [raw] up in [values]; [known] is null when no member matches.
  factory decode(int raw, List<E> values) {
    for (final v in values) {
      if (v.wire == raw) return BleEnumValue(raw, v);
    }
    return BleEnumValue(raw, null);
  }

  /// Accepts a member label (case-insensitive) or an integer wire value.
  /// Throws [FormatException] for anything else.
  factory parse(String text, List<E> values) {
    final t = text.trim();
    final asInt = int.tryParse(t);
    if (asInt != null) return BleEnumValue.decode(asInt, values);
    for (final v in values) {
      if (v.label.toLowerCase() == t.toLowerCase()) return BleEnumValue.of(v);
    }
    throw FormatException(
      'Expected one of ${values.map((v) => v.label).join(', ')} '
      'or an integer',
      text,
    );
  }

  /// Integer exactly as sent or received on the wire.
  final int raw;

  /// Member for [raw], or null when the camera sent an undocumented value.
  final E? known;

  /// [known]'s label, or `unknown(<raw>)` for undocumented values.
  String get label => known?.label ?? 'unknown($raw)';

  /// `{raw, name}`; `name` is null for undocumented values.
  Object? toJson() => {'raw': raw, 'name': known?.label};

  @override
  bool operator ==(Object other) =>
      other is BleEnumValue<E> && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => label;
}

/// An index-coded setting (shutter speed, aperture, exposure compensation,
/// ISO) with the display label from Image Sync's `def_ble.yaml`, when the
/// index is in that table.
@immutable
final class BleIndexedValue {
  /// Pairs a wire index with its table [label], if any.
  const new(this.raw, this.label);

  /// Index exactly as sent or received on the wire.
  final int raw;

  /// Display label from the `def_ble.yaml` table, or null when [raw] is not
  /// in it.
  final String? label;

  /// `{raw, label}`; `label` is null when the index is not in the table.
  Object? toJson() => {'raw': raw, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is BleIndexedValue && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => label ?? 'unknown($raw)';
}

/// Outcome of decoding a characteristic value. Decoding never throws:
/// [value] is null when nothing could be decoded, and [issues] lists every
/// deviation from the documented layout (wrong length, unexpected bytes).
final class BleDecoded<T extends Object> {
  new _(this.raw, this.value, List<String> issues, this._codec)
    : issues = List.unmodifiable(issues);

  /// Bytes as received.
  final Uint8List raw;

  /// Decoded value, or null when nothing could be decoded.
  final T? value;

  /// Every deviation from the documented layout; empty for a clean decode.
  final List<String> issues;
  final BleCodec<T> _codec;

  /// True when a value was decoded without any issue.
  bool get isComplete => value != null && issues.isEmpty;

  /// `{hex, value, issues?}` with JSON-encodable contents.
  Map<String, Object?> toJson() {
    final v = value;
    return {
      'hex': BleBytes.toHex(raw),
      'value': v == null ? null : _codec.valueToJson(v),
      if (issues.isNotEmpty) 'issues': issues,
    };
  }

  /// One-line human rendering.
  String describe() {
    final v = value;
    final text = v == null ? '(undecodable)' : _codec.describeValue(v);
    final hex = BleBytes.toHex(raw);
    final notes = issues.isEmpty ? '' : '  [${issues.join('; ')}]';
    return '$text  <$hex>$notes';
  }
}

/// Typed codec for one characteristic value.
abstract class BleCodec<T extends Object> {
  /// Const constructor for subclasses; codecs hold no mutable state.
  const new();

  /// Never throws; see [BleDecoded].
  BleDecoded<T> decode(Uint8List bytes);

  /// Throws [ArgumentError] when [value] cannot be represented on the wire.
  Uint8List encode(T value);

  /// Parses user text (CLI) into a value. Throws [FormatException].
  T parse(String text);

  /// JSON-encodable form of [value] for traces and CLI output.
  Object? valueToJson(T value);

  /// One-line human rendering of [value]; JSON unless overridden.
  String describeValue(T value) => jsonEncode(valueToJson(value));

  /// Accepted text syntax for [parse], for CLI help and error messages.
  String get syntax;

  /// Parses user text with [parse] and encodes it for writing.
  Uint8List encodeText(String text) => encode(parse(text));

  /// Parses hex bytes and decodes them; throws [FormatException] unless the
  /// bytes decode without issues. Used for `hex:` input to record codecs.
  T parseHex(String text) {
    final d = decode(BleBytes.fromHex(text));
    final v = d.value;
    if (v == null || d.issues.isNotEmpty) {
      throw FormatException(
        'Bytes do not decode cleanly: ${d.issues.join('; ')}',
        text,
      );
    }
    return v;
  }

  /// Builds a decode result bound to this codec.
  BleDecoded<T> result(
    Uint8List raw,
    T? value, [
    List<String> issues = const [],
  ]) => BleDecoded._(raw, value, issues, this);
}

/// Integer wire formats from Image Sync's generic codec (`c.java`): all
/// multi-byte integers are little-endian.
enum BleIntFormat {
  /// Signed 8-bit.
  sint8(1, signed: true),

  /// Unsigned 8-bit.
  uint8(1, signed: false),

  /// Signed 16-bit little-endian.
  sint16(2, signed: true),

  /// Unsigned 16-bit little-endian.
  uint16(2, signed: false),

  /// Signed 32-bit little-endian.
  sint32(4, signed: true),

  /// Unsigned 32-bit little-endian.
  uint32(4, signed: false);

  new(this.width, {required this.signed});

  /// Size on the wire in bytes.
  final int width;

  /// Whether the value is two's-complement signed.
  final bool signed;

  /// Smallest representable value.
  int get min => signed ? -(1 << (8 * width - 1)) : 0;

  /// Largest representable value.
  int get max => signed ? (1 << (8 * width - 1)) - 1 : (1 << (8 * width)) - 1;

  /// Little-endian read; the caller guarantees `offset + width <= length`.
  int read(Uint8List bytes, int offset) {
    var v = 0;
    for (var i = 0; i < width; i++) {
      v |= bytes[offset + i] << (8 * i);
    }
    if (signed && (v & (1 << (8 * width - 1))) != 0) v -= 1 << (8 * width);
    return v;
  }

  /// Little-endian write. Throws [ArgumentError] when out of range.
  void write(Uint8List out, int offset, int value, [String name = 'value']) {
    check(value, name);
    for (var i = 0; i < width; i++) {
      out[offset + i] = (value >> (8 * i)) & 0xff;
    }
  }

  /// Throws [ArgumentError] naming [name] when [value] is outside
  /// [min]..[max].
  void check(int value, [String name = 'value']) {
    if (value < min || value > max) {
      throw ArgumentError.value(value, name, 'outside ${this.name} range');
    }
  }
}

/// Parses a decimal or `0x` hex integer from user text.
int parseIntText(String text) {
  final v = int.tryParse(text.trim());
  if (v == null) throw FormatException('Expected an integer', text);
  return v;
}

/// Parses a boolean from user text: true/false, on/off, yes/no, 1/0.
bool parseBoolText(String text) {
  switch (text.trim().toLowerCase()) {
    case 'true' || 'on' || 'yes' || '1':
      return true;
    case 'false' || 'off' || 'no' || '0':
      return false;
  }
  throw FormatException('Expected true/false, on/off, yes/no or 1/0', text);
}

/// Common length check for fixed-size values. Returns false when the value
/// is too short to decode; otherwise adds an issue for trailing bytes.
bool fixedLengthUsable(Uint8List bytes, int width, List<String> issues) {
  if (bytes.length < width) {
    issues.add(
      bytes.isEmpty
          ? 'empty value, expected $width byte(s)'
          : 'expected $width byte(s), got ${bytes.length}',
    );
    return false;
  }
  if (bytes.length > width) {
    issues.add('${bytes.length - width} unexpected trailing byte(s)');
  }
  return true;
}

/// Plain integer of a fixed [format].
final class BleIntCodec extends BleCodec<int> {
  /// Codec for integers of [format].
  const new(this.format);

  /// Wire width and signedness.
  final BleIntFormat format;

  @override
  BleDecoded<int> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, format.width, issues)) {
      return result(bytes, null, issues);
    }
    return result(bytes, format.read(bytes, 0), issues);
  }

  @override
  Uint8List encode(int value) {
    final out = Uint8List(format.width);
    format.write(out, 0, value);
    return out;
  }

  @override
  int parse(String text) => parseIntText(text);

  @override
  Object? valueToJson(int value) => value;

  @override
  String describeValue(int value) => '$value';

  @override
  String get syntax => 'integer (${format.name})';
}

/// One-byte boolean. Both apps decode `byte0 == 1` (research/protocol/ble.md
/// §Quick reference); other values are kept as an issue.
final class BleBoolCodec extends BleCodec<bool> {
  /// Stateless; one shared instance is enough.
  const new();

  @override
  BleDecoded<bool> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 1, issues)) {
      return result(bytes, null, issues);
    }
    if (bytes[0] > 1) {
      issues.add('value ${bytes[0]} is neither 0 nor 1 (decoded as false)');
    }
    return result(bytes, bytes[0] == 1, issues);
  }

  @override
  Uint8List encode(bool value) => Uint8List.fromList([if (value) 1 else 0]);

  @override
  bool parse(String text) => parseBoolText(text);

  @override
  Object? valueToJson(bool value) => value;

  @override
  String describeValue(bool value) => '$value';

  @override
  String get syntax => 'true|false (on/off, 1/0)';
}

/// Enum carried in one integer of [format].
final class BleEnumCodec<E extends BleWireEnum>
    extends BleCodec<BleEnumValue<E>> {
  /// Codec for [values] carried in one [format] integer (sint8 unless
  /// given).
  const new(this.values, [this.format = BleIntFormat.sint8]);

  /// Documented members; other wire values decode with a null
  /// [BleEnumValue.known].
  final List<E> values;

  /// Wire width and signedness.
  final BleIntFormat format;

  @override
  BleDecoded<BleEnumValue<E>> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, format.width, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BleEnumValue.decode(format.read(bytes, 0), values),
      issues,
    );
  }

  @override
  Uint8List encode(BleEnumValue<E> value) {
    final out = Uint8List(format.width);
    format.write(out, 0, value.raw);
    return out;
  }

  @override
  BleEnumValue<E> parse(String text) => BleEnumValue.parse(text, values);

  @override
  Object? valueToJson(BleEnumValue<E> value) => value.toJson();

  @override
  String describeValue(BleEnumValue<E> value) => value.label;

  @override
  String get syntax => '${values.map((v) => v.label).join('|')} or integer';
}

/// Index-coded setting with a label table (see [BleIndexedValue]).
///
/// Parsing: a plain integer is the raw wire index; other text, or text
/// prefixed with `@`, selects by label (so `@30` means the label "30").
final class BleIndexedCodec extends BleCodec<BleIndexedValue> {
  /// Codec for indexes of [format] labelled by [labels].
  const new(this.format, this.labels, {this.encodeMin, this.encodeMax});

  /// Wire width and signedness.
  final BleIntFormat format;

  /// Display label by wire index (`def_ble.yaml` table).
  final Map<int, String> labels;

  /// Lower end of a narrower write range than [format], when an app
  /// documents one.
  final int? encodeMin;

  /// Upper end of the narrower write range, see [encodeMin].
  final int? encodeMax;

  /// Value for wire index [raw], labelled from [labels].
  BleIndexedValue value(int raw) => BleIndexedValue(raw, labels[raw]);

  @override
  BleDecoded<BleIndexedValue> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, format.width, issues)) {
      return result(bytes, null, issues);
    }
    return result(bytes, value(format.read(bytes, 0)), issues);
  }

  @override
  Uint8List encode(BleIndexedValue value) {
    final lo = encodeMin;
    final hi = encodeMax;
    if ((lo != null && value.raw < lo) || (hi != null && value.raw > hi)) {
      throw ArgumentError.value(value.raw, 'value', 'outside writable range');
    }
    final out = Uint8List(format.width);
    format.write(out, 0, value.raw);
    return out;
  }

  @override
  BleIndexedValue parse(String text) {
    var t = text.trim();
    final byLabel = t.startsWith('@');
    if (byLabel) t = t.substring(1);
    if (!byLabel) {
      final asInt = int.tryParse(t);
      if (asInt != null) return value(asInt);
    }
    final matches = [
      for (final e in labels.entries)
        if (e.value.toLowerCase() == t.toLowerCase()) e.key,
    ];
    if (matches.length == 1) return value(matches.single);
    if (matches.isEmpty) {
      throw FormatException('No value labelled "$t"', text);
    }
    throw FormatException(
      'Label "$t" is ambiguous (indexes ${matches.join(', ')}); '
      'give the integer index',
      text,
    );
  }

  @override
  Object? valueToJson(BleIndexedValue value) => value.toJson();

  @override
  String describeValue(BleIndexedValue value) => '$value (index ${value.raw})';

  @override
  String get syntax => 'integer index, or label (e.g. @${labels.values.first})';
}

/// `type: list` from Image Sync's codec (`c.java:299-323`, `396-445`):
/// `[count sint8][count × element]`.
final class BleListCodec<E extends Object> extends BleCodec<List<E>> {
  /// Codec for a list of [element] values, each [elementWidth] bytes.
  const new(this.element, this.elementWidth);

  /// Codec for one element.
  final BleCodec<E> element;

  /// Size of one element on the wire in bytes.
  final int elementWidth;

  @override
  BleDecoded<List<E>> decode(Uint8List bytes) {
    final issues = <String>[];
    if (bytes.isEmpty) {
      return result(bytes, null, ['empty value, expected a count byte']);
    }
    final count = BleIntFormat.sint8.read(bytes, 0);
    if (count < 0) {
      return result(bytes, null, ['negative element count $count']);
    }
    final available = (bytes.length - 1) ~/ elementWidth;
    final expected = 1 + count * elementWidth;
    if (bytes.length != expected) {
      issues.add(
        'count $count needs $expected byte(s) of $elementWidth-byte '
        'elements, got ${bytes.length}',
      );
    }
    final n = count < available ? count : available;
    final values = <E>[];
    for (var i = 0; i < n; i++) {
      final start = 1 + i * elementWidth;
      final d = element.decode(
        Uint8List.sublistView(bytes, start, start + elementWidth),
      );
      for (final issue in d.issues) {
        issues.add('element $i: $issue');
      }
      final v = d.value;
      if (v != null) values.add(v);
    }
    return result(bytes, values, issues);
  }

  @override
  Uint8List encode(List<E> value) {
    BleIntFormat.sint8.check(value.length, 'element count');
    final out = BytesBuilder(copy: false)..addByte(value.length);
    for (final v in value) {
      out.add(element.encode(v));
    }
    return out.takeBytes();
  }

  @override
  List<E> parse(String text) {
    final t = text.trim();
    if (t.isEmpty) return <E>[];
    return [for (final part in t.split(',')) element.parse(part)];
  }

  @override
  Object? valueToJson(List<E> value) => [
    for (final v in value) element.valueToJson(v),
  ];

  @override
  String describeValue(List<E> value) =>
      '[${value.map(element.describeValue).join(', ')}]';

  @override
  String get syntax => 'comma-separated list of: ${element.syntax}';
}

/// Raw UTF-8 with no length prefix or terminator. Decoding stops at the
/// first NUL, as both apps strip NUL padding (research/protocol/ble.md
/// §Quick reference; ble-imagesync.md §4.1).
final class BleUtf8Codec extends BleCodec<String> {
  /// Stateless; one shared instance is enough.
  const new();

  @override
  BleDecoded<String> decode(Uint8List bytes) {
    final issues = <String>[];
    var end = bytes.indexOf(0);
    if (end < 0) {
      end = bytes.length;
    } else if (bytes.skip(end).any((b) => b != 0)) {
      issues.add('non-zero bytes after the first NUL were ignored');
    }
    final body = Uint8List.sublistView(bytes, 0, end);
    try {
      return result(bytes, utf8.decode(body), issues);
    } on FormatException {
      issues.add('malformed UTF-8 (replacement characters substituted)');
      return result(bytes, utf8.decode(body, allowMalformed: true), issues);
    }
  }

  @override
  Uint8List encode(String value) => utf8.encode(value);

  @override
  String parse(String text) => text;

  @override
  Object? valueToJson(String value) => value;

  @override
  String describeValue(String value) => jsonEncode(value);

  @override
  String get syntax => 'text (UTF-8)';
}

/// Opaque bytes, for characteristics whose layout is unknown.
final class BleBytesCodec extends BleCodec<Uint8List> {
  /// Stateless; one shared instance is enough.
  const new();

  @override
  BleDecoded<Uint8List> decode(Uint8List bytes) => result(bytes, bytes);

  @override
  Uint8List encode(Uint8List value) => value;

  @override
  Uint8List parse(String text) => BleBytes.fromHex(text);

  @override
  Object? valueToJson(Uint8List value) => BleBytes.toHex(value);

  @override
  String describeValue(Uint8List value) => BleBytes.toHex(value);

  @override
  String get syntax => 'hex bytes';
}
