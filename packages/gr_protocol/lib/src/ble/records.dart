import 'dart:typed_data';

import 'bytes.dart';
import 'codecs.dart';
import 'enums.dart';

// Multi-field characteristic values. Layouts: docs/protocol/ble.md
// §Service and characteristic map / §Payload details (GR WORLD) and
// docs/protocol/ble-imagesync.md §1 (Image Sync `def_ble.yaml`): fields are
// concatenated in order with no separators; integers little-endian.

List<String> _fields(String text, int min, int max) {
  final parts = text.split(',').map((p) => p.trim()).toList();
  if (parts.length < min || parts.length > max) {
    final want = min == max ? '$min' : '$min to $max';
    throw FormatException('Expected $want comma-separated fields', text);
  }
  return parts;
}

BleEnumValue<E> _enumAt<E extends BleWireEnum>(
  Uint8List b,
  int offset,
  List<E> values, [
  BleIntFormat format = BleIntFormat.sint8,
]) => BleEnumValue.decode(format.read(b, offset), values);

void _put(
  Uint8List out,
  int offset,
  int value,
  String name, [
  BleIntFormat format = BleIntFormat.sint8,
]) => format.write(out, offset, value, name);

void _checkRange(int value, int min, int max, String name) {
  if (value < min || value > max) {
    throw ArgumentError.value(value, name, 'must be $min..$max');
  }
}

/// Shared shape of record codecs: `hex:<bytes>` input is accepted by every
/// record codec in addition to its field syntax.
abstract class BleRecordCodec<T extends Object> extends BleCodec<T> {
  const BleRecordCodec();

  T parseFields(String text);

  @override
  T parse(String text) {
    final t = text.trim();
    if (t.startsWith('hex:')) return parseHex(t.substring(4));
    return parseFields(t);
  }
}

// ---------------------------------------------------------------------------
// Operation Request `559644B8`

/// Operation Request: `[OperationCode sint8][Parameter sint8]`
/// (ble-imagesync.md §1, §4.5; GR WORLD sends `01 01`).
final class BleOperationRequest {
  const BleOperationRequest(this.code, this.parameter);

  BleOperationRequest.of(BleOperationCode code, BleOperationParameter parameter)
    : this(BleEnumValue.of(code), BleEnumValue.of(parameter));

  /// Release with AF, `01 01` (both apps).
  static final shutterWithAf = BleOperationRequest.of(
    BleOperationCode.start,
    BleOperationParameter.af,
  );

  /// Release without AF, `01 00` (Image Sync; also its stop toggle).
  static final shutterWithoutAf = BleOperationRequest.of(
    BleOperationCode.start,
    BleOperationParameter.noAf,
  );

  /// AF only, `00 01` (Image Sync `focus()`).
  static final focusOnly = BleOperationRequest.of(
    BleOperationCode.nop,
    BleOperationParameter.af,
  );

  /// Green-button function, `00 02` (Image Sync `applyGreenButton`).
  static final greenButton = BleOperationRequest.of(
    BleOperationCode.nop,
    BleOperationParameter.greenButton,
  );

  final BleEnumValue<BleOperationCode> code;
  final BleEnumValue<BleOperationParameter> parameter;

  Map<String, Object?> toJson() => {
    'code': code.toJson(),
    'parameter': parameter.toJson(),
  };
}

final class BleOperationRequestCodec
    extends BleRecordCodec<BleOperationRequest> {
  const BleOperationRequestCodec();

  @override
  BleDecoded<BleOperationRequest> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 2, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BleOperationRequest(
        _enumAt(bytes, 0, BleOperationCode.values),
        _enumAt(bytes, 1, BleOperationParameter.values),
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleOperationRequest value) {
    final out = Uint8List(2);
    _put(out, 0, value.code.raw, 'code');
    _put(out, 1, value.parameter.raw, 'parameter');
    return out;
  }

  @override
  BleOperationRequest parseFields(String text) {
    final f = _fields(text, 2, 2);
    return BleOperationRequest(
      BleEnumValue.parse(f[0], BleOperationCode.values),
      BleEnumValue.parse(f[1], BleOperationParameter.values),
    );
  }

  @override
  Object? valueToJson(BleOperationRequest value) => value.toJson();

  @override
  String describeValue(BleOperationRequest value) =>
      '${value.code} ${value.parameter}';

  @override
  String get syntax => '<code>,<parameter> e.g. start,af | nop,greenButton';
}

// ---------------------------------------------------------------------------
// Shooting Mode `A3C51525`

/// Shooting Mode: GR WORLD decodes 2 bytes `[mode][user mode]`; Image Sync
/// declares 3 bytes `[mode uint8][user mode sint8][option sint8]`.
/// [option] is null when the camera sent the 2-byte form, and encoding
/// preserves that length.
final class BleShootingMode {
  const BleShootingMode(this.mode, this.userMode, [this.option]);

  final BleEnumValue<BleExposureMode> mode;
  final BleEnumValue<BleUserMode> userMode;
  final BleEnumValue<BleShootingModeOption>? option;

  BleShootingMode copyWith({
    BleEnumValue<BleExposureMode>? mode,
    BleEnumValue<BleUserMode>? userMode,
  }) => BleShootingMode(mode ?? this.mode, userMode ?? this.userMode, option);

  Map<String, Object?> toJson() => {
    'mode': mode.toJson(),
    'userMode': userMode.toJson(),
    'option': option?.toJson(),
  };
}

final class BleShootingModeCodec extends BleRecordCodec<BleShootingMode> {
  const BleShootingModeCodec();

  @override
  BleDecoded<BleShootingMode> decode(Uint8List bytes) {
    final issues = <String>[];
    if (bytes.length < 2) {
      return result(bytes, null, [
        'expected 2 (GR WORLD) or 3 (Image Sync) bytes, got ${bytes.length}',
      ]);
    }
    if (bytes.length > 3) {
      issues.add('${bytes.length - 3} unexpected trailing byte(s)');
    }
    return result(
      bytes,
      BleShootingMode(
        _enumAt(bytes, 0, BleExposureMode.values, BleIntFormat.uint8),
        _enumAt(bytes, 1, BleUserMode.values),
        bytes.length >= 3
            ? _enumAt(bytes, 2, BleShootingModeOption.values)
            : null,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleShootingMode value) {
    final option = value.option;
    final out = Uint8List(option == null ? 2 : 3);
    _put(out, 0, value.mode.raw, 'mode', BleIntFormat.uint8);
    _put(out, 1, value.userMode.raw, 'userMode');
    if (option != null) _put(out, 2, option.raw, 'option');
    return out;
  }

  @override
  BleShootingMode parseFields(String text) {
    final f = _fields(text, 2, 3);
    return BleShootingMode(
      BleEnumValue.parse(f[0], BleExposureMode.values),
      BleEnumValue.parse(f[1], BleUserMode.values),
      f.length == 3
          ? BleEnumValue.parse(f[2], BleShootingModeOption.values)
          : null,
    );
  }

  @override
  Object? valueToJson(BleShootingMode value) => value.toJson();

  @override
  String describeValue(BleShootingMode value) =>
      [value.mode, value.userMode, ?value.option].join(' ');

  @override
  String get syntax =>
      '<mode>,<userMode>[,<option>] e.g. av,none (2-byte) or av,u1,none';
}

// ---------------------------------------------------------------------------
// Capture Status `B5589C08`

/// Capture Status: GR WORLD reads 2 bytes `[capturing][countdown]`; Image
/// Sync declares 8 bytes adding still/movie state, AstroTracer Type 3
/// state/result and a uint16 tracking time. Extended fields are null for
/// the 2-byte form.
final class BleCaptureStatus {
  const BleCaptureStatus({
    required this.capturing,
    required this.countdown,
    this.still,
    this.movie,
    this.type3CaptureState,
    this.type3PreCaptureResult,
    this.astroTrackingTime,
  });

  final BleEnumValue<BleCapturing> capturing;
  final BleEnumValue<BleCountdown> countdown;
  final BleEnumValue<BleStillCaptureState>? still;
  final BleEnumValue<BleMovieCaptureState>? movie;
  final BleEnumValue<BleType3CaptureState>? type3CaptureState;
  final BleEnumValue<BleType3PreCaptureResult>? type3PreCaptureResult;

  /// Unit not documented.
  final int? astroTrackingTime;

  bool get isExtended => still != null;

  Map<String, Object?> toJson() => {
    'capturing': capturing.toJson(),
    'countdown': countdown.toJson(),
    if (isExtended) ...{
      'still': still?.toJson(),
      'movie': movie?.toJson(),
      'type3CaptureState': type3CaptureState?.toJson(),
      'type3PreCaptureResult': type3PreCaptureResult?.toJson(),
      'astroTrackingTime': astroTrackingTime,
    },
  };
}

final class BleCaptureStatusCodec extends BleRecordCodec<BleCaptureStatus> {
  const BleCaptureStatusCodec();

  @override
  BleDecoded<BleCaptureStatus> decode(Uint8List bytes) {
    final issues = <String>[];
    if (bytes.length < 2) {
      return result(bytes, null, [
        'expected 2 (GR WORLD) or 8 (Image Sync) bytes, got ${bytes.length}',
      ]);
    }
    final extended = bytes.length >= 8;
    if (bytes.length != 2 && bytes.length != 8) {
      issues.add(
        'length ${bytes.length} is neither 2 nor 8; decoded as the '
        '${extended ? 8 : 2}-byte form',
      );
    }
    return result(
      bytes,
      BleCaptureStatus(
        capturing: _enumAt(bytes, 0, BleCapturing.values),
        countdown: _enumAt(bytes, 1, BleCountdown.values),
        still: extended ? _enumAt(bytes, 2, BleStillCaptureState.values) : null,
        movie: extended ? _enumAt(bytes, 3, BleMovieCaptureState.values) : null,
        type3CaptureState: extended
            ? _enumAt(bytes, 4, BleType3CaptureState.values)
            : null,
        type3PreCaptureResult: extended
            ? _enumAt(bytes, 5, BleType3PreCaptureResult.values)
            : null,
        astroTrackingTime: extended ? BleIntFormat.uint16.read(bytes, 6) : null,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleCaptureStatus value) {
    final out = Uint8List(value.isExtended ? 8 : 2);
    _put(out, 0, value.capturing.raw, 'capturing');
    _put(out, 1, value.countdown.raw, 'countdown');
    if (value.isExtended) {
      _put(out, 2, value.still?.raw ?? 0, 'still');
      _put(out, 3, value.movie?.raw ?? 0, 'movie');
      _put(out, 4, value.type3CaptureState?.raw ?? 0, 'type3CaptureState');
      _put(
        out,
        5,
        value.type3PreCaptureResult?.raw ?? 0,
        'type3PreCaptureResult',
      );
      _put(
        out,
        6,
        value.astroTrackingTime ?? 0,
        'astroTrackingTime',
        BleIntFormat.uint16,
      );
    }
    return out;
  }

  @override
  BleCaptureStatus parseFields(String text) {
    final f = _fields(text, 2, 2);
    return BleCaptureStatus(
      capturing: BleEnumValue.parse(f[0], BleCapturing.values),
      countdown: BleEnumValue.parse(f[1], BleCountdown.values),
    );
  }

  @override
  Object? valueToJson(BleCaptureStatus value) => value.toJson();

  @override
  String describeValue(BleCaptureStatus value) {
    final base = '${value.capturing} countdown=${value.countdown}';
    if (!value.isExtended) return base;
    return '$base still=${value.still} movie=${value.movie} '
        'type3=${value.type3CaptureState}/${value.type3PreCaptureResult} '
        'astroTrackingTime=${value.astroTrackingTime}';
  }

  @override
  String get syntax => '<capturing>,<countdown> or hex:<8 bytes>';
}

// ---------------------------------------------------------------------------
// Self Timer / Cancel `009A8E70`

/// Which app's Self Timer payload to send; the two differ and which one
/// GR IV expects is an open hardware question (ble-imagesync.md §4.5).
enum BleSelfTimerCancelFormat {
  /// 1 byte `01` (GR WORLD 0xe61dd8; GR IV-capable app).
  grWorld,

  /// 2 bytes `01 01` = [cancel][remocon on] (Image Sync, GR III).
  imageSync;

  BleSelfTimerCommand get command => switch (this) {
    BleSelfTimerCancelFormat.grWorld => BleSelfTimerCommand(
      BleEnumValue.of(BleCountdownCancel.cancel),
    ),
    BleSelfTimerCancelFormat.imageSync => BleSelfTimerCommand(
      BleEnumValue.of(BleCountdownCancel.cancel),
      BleEnumValue.of(BleRemocon.on),
    ),
  };
}

/// Self Timer command: `[Countdown Cancel]` (GR WORLD) or
/// `[Countdown Cancel][Remocon]` (Image Sync). [remocon] null = 1-byte form.
final class BleSelfTimerCommand {
  const BleSelfTimerCommand(this.cancel, [this.remocon]);

  final BleEnumValue<BleCountdownCancel> cancel;
  final BleEnumValue<BleRemocon>? remocon;

  Map<String, Object?> toJson() => {
    'cancel': cancel.toJson(),
    'remocon': remocon?.toJson(),
  };
}

final class BleSelfTimerCodec extends BleRecordCodec<BleSelfTimerCommand> {
  const BleSelfTimerCodec();

  @override
  BleDecoded<BleSelfTimerCommand> decode(Uint8List bytes) {
    final issues = <String>[];
    if (bytes.isEmpty) return result(bytes, null, ['empty value']);
    if (bytes.length > 2) {
      issues.add('${bytes.length - 2} unexpected trailing byte(s)');
    }
    return result(
      bytes,
      BleSelfTimerCommand(
        _enumAt(bytes, 0, BleCountdownCancel.values),
        bytes.length >= 2 ? _enumAt(bytes, 1, BleRemocon.values) : null,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleSelfTimerCommand value) {
    final remocon = value.remocon;
    final out = Uint8List(remocon == null ? 1 : 2);
    _put(out, 0, value.cancel.raw, 'cancel');
    if (remocon != null) _put(out, 1, remocon.raw, 'remocon');
    return out;
  }

  @override
  BleSelfTimerCommand parseFields(String text) {
    final f = _fields(text, 1, 2);
    return BleSelfTimerCommand(
      BleEnumValue.parse(f[0], BleCountdownCancel.values),
      f.length == 2 ? BleEnumValue.parse(f[1], BleRemocon.values) : null,
    );
  }

  @override
  Object? valueToJson(BleSelfTimerCommand value) => value.toJson();

  @override
  String describeValue(BleSelfTimerCommand value) =>
      '${value.cancel}${value.remocon == null ? '' : ' remocon=${value.remocon}'}';

  @override
  String get syntax => '<cancel>[,<remocon>] e.g. cancel | cancel,on';
}

// ---------------------------------------------------------------------------
// Image Control custom data (GR WORLD)

/// One Image Control parameter: id byte and signed value.
final class BleImageControlEntry {
  const BleImageControlEntry(this.parameter, this.value);

  final BleEnumValue<BleImageControlParameter> parameter;
  final int value;

  Map<String, Object?> toJson() => {
    'parameter': parameter.toJson(),
    'value': value,
  };
}

/// Image Control custom 1–3 data blob (ble.md §Image Control blob):
/// `[version][unknown][base image][N][N × (id, sint8 value)]`.
/// GR WORLD accepts versions 1, 2 and 4 only.
final class BleImageControlBlob {
  BleImageControlBlob({
    required this.version,
    required this.reserved,
    required this.base,
    required List<BleImageControlEntry> parameters,
    Uint8List? trailing,
  }) : parameters = List.unmodifiable(parameters),
       trailing = trailing ?? Uint8List(0);

  static const supportedVersions = {1, 2, 4};

  final int version;

  /// Byte 1; GR WORLD never reads it, meaning unknown.
  final int reserved;
  final BleEnumValue<BleImageControlBase> base;
  final List<BleImageControlEntry> parameters;

  /// Bytes after the declared parameters; not documented, kept verbatim.
  final Uint8List trailing;

  Map<String, Object?> toJson() => {
    'version': version,
    'reserved': reserved,
    'base': base.toJson(),
    'parameters': [for (final p in parameters) p.toJson()],
    if (trailing.isNotEmpty) 'trailingHex': BleBytes.toHex(trailing),
  };
}

final class BleImageControlCodec extends BleCodec<BleImageControlBlob> {
  const BleImageControlCodec();

  @override
  BleDecoded<BleImageControlBlob> decode(Uint8List bytes) {
    final issues = <String>[];
    if (bytes.length < 4) {
      return result(bytes, null, [
        'expected at least 4 header bytes, got ${bytes.length}',
      ]);
    }
    final version = bytes[0];
    if (!BleImageControlBlob.supportedVersions.contains(version)) {
      issues.add('version $version is not 1, 2 or 4 (GR WORLD ignores it)');
    }
    final count = bytes[3];
    final available = (bytes.length - 4) ~/ 2;
    if (available < count) {
      issues.add('declares $count parameters, only $available present');
    }
    final n = count < available ? count : available;
    final params = <BleImageControlEntry>[
      for (var i = 0; i < n; i++)
        BleImageControlEntry(
          BleEnumValue.decode(
            bytes[4 + 2 * i],
            BleImageControlParameter.values,
          ),
          BleIntFormat.sint8.read(bytes, 5 + 2 * i),
        ),
    ];
    final end = 4 + 2 * n;
    final trailing = Uint8List.fromList(bytes.sublist(end));
    if (trailing.isNotEmpty) {
      issues.add('${trailing.length} byte(s) after the parameters');
    }
    return result(
      bytes,
      BleImageControlBlob(
        version: version,
        reserved: bytes[1],
        base: BleEnumValue.decode(bytes[2], BleImageControlBase.values),
        parameters: params,
        trailing: trailing,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleImageControlBlob value) {
    final out = Uint8List(4 + 2 * value.parameters.length);
    _put(out, 0, value.version, 'version', BleIntFormat.uint8);
    _put(out, 1, value.reserved, 'reserved', BleIntFormat.uint8);
    _put(out, 2, value.base.raw, 'base', BleIntFormat.uint8);
    _put(out, 3, value.parameters.length, 'count', BleIntFormat.uint8);
    for (var i = 0; i < value.parameters.length; i++) {
      final p = value.parameters[i];
      _put(out, 4 + 2 * i, p.parameter.raw, 'parameter', BleIntFormat.uint8);
      _put(out, 5 + 2 * i, p.value, 'value');
    }
    return Uint8List.fromList([...out, ...value.trailing]);
  }

  @override
  BleImageControlBlob parse(String text) {
    final t = text.trim();
    return parseHex(t.startsWith('hex:') ? t.substring(4) : t);
  }

  @override
  Object? valueToJson(BleImageControlBlob value) => value.toJson();

  @override
  String describeValue(BleImageControlBlob value) =>
      'v${value.version} ${value.base} '
      '${value.parameters.map((p) => '${p.parameter.label}=${p.value}').join(' ')}';

  @override
  String get syntax => 'hex bytes of the whole blob';
}

// ---------------------------------------------------------------------------
// Date Time `FA46BBDD`

/// Camera clock: `[year uint16 LE][month][day][hour][minute][second]`, in
/// the camera's local time; no zone, weekday or milliseconds (ble.md
/// §Date/time sync; both apps send phone local time).
final class BleDateTime {
  const BleDateTime({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
  });

  /// Uses [time]'s own calendar fields; pass a local [DateTime] to match
  /// both apps.
  factory BleDateTime.fromDateTime(DateTime time) => BleDateTime(
    year: time.year,
    month: time.month,
    day: time.day,
    hour: time.hour,
    minute: time.minute,
    second: time.second,
  );

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;

  /// Local [DateTime], or null when a field is out of calendar range.
  DateTime? toLocalDateTime() {
    if (_problems().isNotEmpty) return null;
    return DateTime(year, month, day, hour, minute, second);
  }

  List<String> _problems() => [
    if (month < 1 || month > 12) 'month $month out of range',
    if (day < 1 || day > 31) 'day $day out of range',
    if (hour > 23) 'hour $hour out of range',
    if (minute > 59) 'minute $minute out of range',
    if (second > 59) 'second $second out of range',
  ];

  String get iso =>
      '${year.toString().padLeft(4, '0')}-${_pad2(month)}-${_pad2(day)}'
      'T${_pad2(hour)}:${_pad2(minute)}:${_pad2(second)}';

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  Map<String, Object?> toJson() => {
    'year': year,
    'month': month,
    'day': day,
    'hour': hour,
    'minute': minute,
    'second': second,
    'iso': iso,
  };
}

final class BleDateTimeCodec extends BleRecordCodec<BleDateTime> {
  const BleDateTimeCodec();

  @override
  BleDecoded<BleDateTime> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 7, issues)) {
      return result(bytes, null, issues);
    }
    final value = BleDateTime(
      year: BleIntFormat.uint16.read(bytes, 0),
      month: bytes[2],
      day: bytes[3],
      hour: bytes[4],
      minute: bytes[5],
      second: bytes[6],
    );
    issues.addAll(value._problems());
    return result(bytes, value, issues);
  }

  @override
  Uint8List encode(BleDateTime value) {
    _checkRange(value.month, 1, 12, 'month');
    _checkRange(value.day, 1, 31, 'day');
    _checkRange(value.hour, 0, 23, 'hour');
    _checkRange(value.minute, 0, 59, 'minute');
    _checkRange(value.second, 0, 59, 'second');
    final out = Uint8List(7);
    _put(out, 0, value.year, 'year', BleIntFormat.uint16);
    out
      ..[2] = value.month
      ..[3] = value.day
      ..[4] = value.hour
      ..[5] = value.minute
      ..[6] = value.second;
    return out;
  }

  /// `now` (local clock) or an ISO-8601 date-time whose calendar fields are
  /// sent as written (a `Z`/offset suffix is not converted).
  @override
  BleDateTime parseFields(String text) {
    if (text.toLowerCase() == 'now') {
      return BleDateTime.fromDateTime(DateTime.now());
    }
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(text);
    if (m == null) {
      throw FormatException('Expected now or YYYY-MM-DDTHH:MM[:SS]', text);
    }
    int g(int i) => int.parse(m.group(i) ?? '0');
    return BleDateTime(
      year: g(1),
      month: g(2),
      day: g(3),
      hour: g(4),
      minute: g(5),
      second: g(6),
    );
  }

  @override
  Object? valueToJson(BleDateTime value) => value.toJson();

  @override
  String describeValue(BleDateTime value) => value.iso;

  @override
  String get syntax => 'now | YYYY-MM-DDTHH:MM:SS (camera local time)';
}

// ---------------------------------------------------------------------------
// Battery Level `875FC41D`

/// Battery Level. Byte 0 is the level (sint8) in both apps; byte 1 differs:
/// - Image Sync (2 bytes): power source, 0 battery / 1 AC adapter.
/// - GR WORLD: when length ≥ 130 and byte 1 == 1, bytes [2..130) are 128
///   bytes of end-screen data (layout unknown).
///
/// Both readings are exposed; [byte1] keeps the raw value.
final class BleBatteryLevel {
  const BleBatteryLevel({
    required this.level,
    this.byte1,
    this.powerSource,
    this.endScreenData,
  });

  final int level;
  final int? byte1;

  /// Image Sync reading of byte 1; set only for the 2-byte form.
  final BleEnumValue<BlePowerSource>? powerSource;

  /// GR WORLD long form; null otherwise.
  final Uint8List? endScreenData;

  Map<String, Object?> toJson() => {
    'level': level,
    'byte1': byte1,
    'powerSource': powerSource?.toJson(),
    if (endScreenData != null)
      'endScreenDataHex': BleBytes.toHex(endScreenData!),
  };
}

final class BleBatteryLevelCodec extends BleRecordCodec<BleBatteryLevel> {
  const BleBatteryLevelCodec();

  @override
  BleDecoded<BleBatteryLevel> decode(Uint8List bytes) {
    final issues = <String>[];
    if (bytes.isEmpty) return result(bytes, null, ['empty value']);
    final level = BleIntFormat.sint8.read(bytes, 0);
    final byte1 = bytes.length >= 2 ? bytes[1] : null;
    Uint8List? endScreen;
    BleEnumValue<BlePowerSource>? source;
    if (bytes.length >= 130 && byte1 == 1) {
      endScreen = Uint8List.fromList(bytes.sublist(2, 130));
      if (bytes.length > 130) {
        issues.add('${bytes.length - 130} byte(s) after the end-screen data');
      }
    } else if (bytes.length == 2) {
      source = _enumAt(bytes, 1, BlePowerSource.values);
    } else if (bytes.length != 1) {
      issues.add(
        'length ${bytes.length} matches neither the 1/2-byte form nor the '
        'long form (≥130 bytes with byte1 == 1)',
      );
    }
    return result(
      bytes,
      BleBatteryLevel(
        level: level,
        byte1: byte1,
        powerSource: source,
        endScreenData: endScreen,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleBatteryLevel value) {
    final endScreen = value.endScreenData;
    final b1 = value.byte1 ?? value.powerSource?.raw;
    final out = BytesBuilder(copy: false);
    final head = Uint8List(b1 == null ? 1 : 2);
    _put(head, 0, value.level, 'level');
    if (b1 != null) _put(head, 1, b1, 'byte1', BleIntFormat.uint8);
    out.add(head);
    if (endScreen != null) out.add(endScreen);
    return out.takeBytes();
  }

  @override
  BleBatteryLevel parseFields(String text) {
    final f = _fields(text, 1, 2);
    final source = f.length == 2
        ? BleEnumValue.parse(f[1], BlePowerSource.values)
        : null;
    return BleBatteryLevel(
      level: parseIntText(f[0]),
      byte1: source?.raw,
      powerSource: source,
    );
  }

  @override
  Object? valueToJson(BleBatteryLevel value) => value.toJson();

  @override
  String describeValue(BleBatteryLevel value) {
    final parts = ['${value.level}%'];
    if (value.powerSource != null) parts.add('source=${value.powerSource}');
    if (value.endScreenData != null) parts.add('+128 B end-screen data');
    if (value.byte1 != null && value.powerSource == null) {
      parts.add('byte1=${value.byte1}');
    }
    return parts.join(' ');
  }

  @override
  String get syntax => '<level>[,<battery|acAdapter>]';
}

// ---------------------------------------------------------------------------
// Storage Information `A0C10148`

/// One storage entry. The first 14 bytes are common to both apps; the
/// 15-byte Image Sync form adds [active] (write target).
final class BleStorageEntry {
  const BleStorageEntry({
    required this.type,
    required this.exists,
    required this.locked,
    required this.available,
    required this.formatted,
    required this.remainingPictures,
    required this.remainingVideoSeconds,
    required this.fileType,
    this.active,
  });

  final BleEnumValue<BleStorageType> type;
  final bool exists;
  final bool locked;
  final bool available;
  final bool formatted;
  final int remainingPictures;
  final int remainingVideoSeconds;

  /// Raw int8; meaning unknown in both apps.
  final int fileType;
  final bool? active;

  Map<String, Object?> toJson() => {
    'type': type.toJson(),
    'exists': exists,
    'locked': locked,
    'available': available,
    'formatted': formatted,
    'remainingPictures': remainingPictures,
    'remainingVideoSeconds': remainingVideoSeconds,
    'fileTypeRaw': fileType,
    'active': active,
  };
}

/// Storage Information: `[N]` + N × 14-byte (GR WORLD; GR III per Image
/// Sync's padding code) or 15-byte (Image Sync) entries. [entrySize] is the
/// size the payload length matched, or null when N is 0.
final class BleStorageInformation {
  BleStorageInformation(List<BleStorageEntry> entries, this.entrySize)
    : entries = List.unmodifiable(entries);

  final List<BleStorageEntry> entries;
  final int? entrySize;

  Map<String, Object?> toJson() => {
    'entrySize': entrySize,
    'entries': [for (final e in entries) e.toJson()],
  };
}

final class BleStorageInformationCodec
    extends BleRecordCodec<BleStorageInformation> {
  const BleStorageInformationCodec();

  @override
  BleDecoded<BleStorageInformation> decode(Uint8List bytes) {
    if (bytes.isEmpty) return result(bytes, null, ['empty value']);
    final n = bytes[0];
    final rest = bytes.length - 1;
    final int? size;
    if (n == 0 && rest == 0) {
      size = null;
    } else if (rest == n * 15) {
      size = 15;
    } else if (rest == n * 14) {
      size = 14;
    } else {
      return result(bytes, null, [
        'count $n with $rest entry byte(s) matches neither 14- nor 15-byte '
            'entries',
      ]);
    }
    final entries = <BleStorageEntry>[];
    for (var i = 0; i < n; i++) {
      final o = 1 + i * size!;
      entries.add(
        BleStorageEntry(
          type: _enumAt(bytes, o, BleStorageType.values),
          exists: bytes[o + 1] == 1,
          locked: bytes[o + 2] == 1,
          available: bytes[o + 3] == 1,
          formatted: bytes[o + 4] == 1,
          remainingPictures: BleIntFormat.sint32.read(bytes, o + 5),
          remainingVideoSeconds: BleIntFormat.sint32.read(bytes, o + 9),
          fileType: BleIntFormat.sint8.read(bytes, o + 13),
          active: size == 15 ? bytes[o + 14] == 1 : null,
        ),
      );
    }
    return result(bytes, BleStorageInformation(entries, size));
  }

  @override
  Uint8List encode(BleStorageInformation value) {
    final size = value.entries.any((e) => e.active != null) ? 15 : 14;
    final out = Uint8List(1 + size * value.entries.length);
    _put(out, 0, value.entries.length, 'count', BleIntFormat.uint8);
    for (var i = 0; i < value.entries.length; i++) {
      final e = value.entries[i];
      final o = 1 + i * size;
      _put(out, o, e.type.raw, 'type');
      out[o + 1] = e.exists ? 1 : 0;
      out[o + 2] = e.locked ? 1 : 0;
      out[o + 3] = e.available ? 1 : 0;
      out[o + 4] = e.formatted ? 1 : 0;
      _put(
        out,
        o + 5,
        e.remainingPictures,
        'remainingPictures',
        BleIntFormat.sint32,
      );
      _put(
        out,
        o + 9,
        e.remainingVideoSeconds,
        'remainingVideoSeconds',
        BleIntFormat.sint32,
      );
      _put(out, o + 13, e.fileType, 'fileType');
      if (size == 15) out[o + 14] = (e.active ?? false) ? 1 : 0;
    }
    return out;
  }

  @override
  BleStorageInformation parseFields(String text) => parseHex(text);

  @override
  Object? valueToJson(BleStorageInformation value) => value.toJson();

  @override
  String describeValue(BleStorageInformation value) => value.entries
      .map(
        (e) =>
            '${e.type}: exists=${e.exists} locked=${e.locked} '
            'available=${e.available} formatted=${e.formatted} '
            'pictures=${e.remainingPictures} '
            'videoSeconds=${e.remainingVideoSeconds} '
            'fileType=${e.fileType}'
            '${e.active == null ? '' : ' active=${e.active}'}',
      )
      .join('; ');

  @override
  String get syntax => 'hex bytes';
}

// ---------------------------------------------------------------------------
// Small two-field records

/// File Transfer List: `[not empty][changed]`, each `== 1`.
final class BleFileTransferList {
  const BleFileTransferList({required this.notEmpty, required this.changed});

  final bool notEmpty;
  final bool changed;

  Map<String, Object?> toJson() => {'notEmpty': notEmpty, 'changed': changed};
}

final class BleFileTransferListCodec
    extends BleRecordCodec<BleFileTransferList> {
  const BleFileTransferListCodec();

  @override
  BleDecoded<BleFileTransferList> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 2, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BleFileTransferList(notEmpty: bytes[0] == 1, changed: bytes[1] == 1),
      issues,
    );
  }

  @override
  Uint8List encode(BleFileTransferList value) =>
      Uint8List.fromList([value.notEmpty ? 1 : 0, value.changed ? 1 : 0]);

  @override
  BleFileTransferList parseFields(String text) {
    final f = _fields(text, 2, 2);
    return BleFileTransferList(
      notEmpty: parseBoolText(f[0]),
      changed: parseBoolText(f[1]),
    );
  }

  @override
  Object? valueToJson(BleFileTransferList value) => value.toJson();

  @override
  String describeValue(BleFileTransferList value) =>
      'notEmpty=${value.notEmpty} changed=${value.changed}';

  @override
  String get syntax => '<notEmpty>,<changed> booleans';
}

/// Power Off During File Transfer: `[behavior][auto resize]`.
final class BlePowerOffDuringTransfer {
  const BlePowerOffDuringTransfer(this.behavior, this.autoResize);

  final BleEnumValue<BleTransferPowerOffBehavior> behavior;
  final bool autoResize;

  Map<String, Object?> toJson() => {
    'behavior': behavior.toJson(),
    'autoResize': autoResize,
  };
}

final class BlePowerOffDuringTransferCodec
    extends BleRecordCodec<BlePowerOffDuringTransfer> {
  const BlePowerOffDuringTransferCodec();

  @override
  BleDecoded<BlePowerOffDuringTransfer> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 2, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BlePowerOffDuringTransfer(
        _enumAt(bytes, 0, BleTransferPowerOffBehavior.values),
        bytes[1] == 1,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BlePowerOffDuringTransfer value) {
    final out = Uint8List(2);
    _put(out, 0, value.behavior.raw, 'behavior');
    out[1] = value.autoResize ? 1 : 0;
    return out;
  }

  @override
  BlePowerOffDuringTransfer parseFields(String text) {
    final f = _fields(text, 2, 2);
    return BlePowerOffDuringTransfer(
      BleEnumValue.parse(f[0], BleTransferPowerOffBehavior.values),
      parseBoolText(f[1]),
    );
  }

  @override
  Object? valueToJson(BlePowerOffDuringTransfer value) => value.toJson();

  @override
  String describeValue(BlePowerOffDuringTransfer value) =>
      '${value.behavior} autoResize=${value.autoResize}';

  @override
  String get syntax =>
      '<abortTransferAndPowerOff|powerOffAfterTransfer>,<autoResize bool>';
}

/// Focus Mode (`89458F80`, R/N only): `[focus mode][focus setting]`.
final class BleFocus {
  const BleFocus(this.mode, this.setting);

  final BleEnumValue<BleFocusMode> mode;
  final BleEnumValue<BleFocusSetting> setting;

  Map<String, Object?> toJson() => {
    'mode': mode.toJson(),
    'setting': setting.toJson(),
  };
}

final class BleFocusCodec extends BleRecordCodec<BleFocus> {
  const BleFocusCodec();

  @override
  BleDecoded<BleFocus> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 2, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BleFocus(
        _enumAt(bytes, 0, BleFocusMode.values),
        _enumAt(bytes, 1, BleFocusSetting.values),
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleFocus value) {
    final out = Uint8List(2);
    _put(out, 0, value.mode.raw, 'mode');
    _put(out, 1, value.setting.raw, 'setting');
    return out;
  }

  @override
  BleFocus parseFields(String text) {
    final f = _fields(text, 2, 2);
    return BleFocus(
      BleEnumValue.parse(f[0], BleFocusMode.values),
      BleEnumValue.parse(f[1], BleFocusSetting.values),
    );
  }

  @override
  Object? valueToJson(BleFocus value) => value.toJson();

  @override
  String describeValue(BleFocus value) => '${value.mode} ${value.setting}';

  @override
  String get syntax => '<manual|auto>,<focus setting>';
}

/// Auto Focus Status (`CDFC734E`): `[running][in focus]`.
final class BleAfStatus {
  const BleAfStatus(this.running, this.inFocus);

  final BleEnumValue<BleAfRunning> running;
  final BleEnumValue<BleAfInFocus> inFocus;

  Map<String, Object?> toJson() => {
    'running': running.toJson(),
    'inFocus': inFocus.toJson(),
  };
}

final class BleAfStatusCodec extends BleRecordCodec<BleAfStatus> {
  const BleAfStatusCodec();

  @override
  BleDecoded<BleAfStatus> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 2, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BleAfStatus(
        _enumAt(bytes, 0, BleAfRunning.values),
        _enumAt(bytes, 1, BleAfInFocus.values),
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleAfStatus value) {
    final out = Uint8List(2);
    _put(out, 0, value.running.raw, 'running');
    _put(out, 1, value.inFocus.raw, 'inFocus');
    return out;
  }

  @override
  BleAfStatus parseFields(String text) {
    final f = _fields(text, 2, 2);
    return BleAfStatus(
      BleEnumValue.parse(f[0], BleAfRunning.values),
      BleEnumValue.parse(f[1], BleAfInFocus.values),
    );
  }

  @override
  Object? valueToJson(BleAfStatus value) => value.toJson();

  @override
  String describeValue(BleAfStatus value) =>
      '${value.running} ${value.inFocus}';

  @override
  String get syntax => '<stopped|running>,<notInFocus|inFocus>';
}

/// Shot Count (`12D262BA`): `[current sint8][total sint8]`.
final class BleShotCount {
  const BleShotCount(this.current, this.total);

  final int current;
  final int total;

  Map<String, Object?> toJson() => {'current': current, 'total': total};
}

final class BleShotCountCodec extends BleRecordCodec<BleShotCount> {
  const BleShotCountCodec();

  @override
  BleDecoded<BleShotCount> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 2, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BleShotCount(
        BleIntFormat.sint8.read(bytes, 0),
        BleIntFormat.sint8.read(bytes, 1),
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleShotCount value) {
    final out = Uint8List(2);
    _put(out, 0, value.current, 'current');
    _put(out, 1, value.total, 'total');
    return out;
  }

  @override
  BleShotCount parseFields(String text) {
    final f = _fields(text, 2, 2);
    return BleShotCount(parseIntText(f[0]), parseIntText(f[1]));
  }

  @override
  Object? valueToJson(BleShotCount value) => value.toJson();

  @override
  String describeValue(BleShotCount value) => '${value.current}/${value.total}';

  @override
  String get syntax => '<current>,<total>';
}

/// File Type (`95BFA8CA`): `[file type][raw type][card slot][slot mode]`.
final class BleFileType {
  const BleFileType(this.fileType, this.rawType, this.cardSlot, this.slotMode);

  final BleEnumValue<BleStillFileType> fileType;
  final BleEnumValue<BleRawType> rawType;
  final BleEnumValue<BleCardSlot> cardSlot;
  final BleEnumValue<BleSlotMode> slotMode;

  BleFileType copyWith({
    BleEnumValue<BleStillFileType>? fileType,
    BleEnumValue<BleRawType>? rawType,
  }) => BleFileType(
    fileType ?? this.fileType,
    rawType ?? this.rawType,
    cardSlot,
    slotMode,
  );

  Map<String, Object?> toJson() => {
    'fileType': fileType.toJson(),
    'rawType': rawType.toJson(),
    'cardSlot': cardSlot.toJson(),
    'slotMode': slotMode.toJson(),
  };
}

final class BleFileTypeCodec extends BleRecordCodec<BleFileType> {
  const BleFileTypeCodec();

  @override
  BleDecoded<BleFileType> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 4, issues)) {
      return result(bytes, null, issues);
    }
    return result(
      bytes,
      BleFileType(
        _enumAt(bytes, 0, BleStillFileType.values),
        _enumAt(bytes, 1, BleRawType.values),
        _enumAt(bytes, 2, BleCardSlot.values),
        _enumAt(bytes, 3, BleSlotMode.values),
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleFileType value) {
    final out = Uint8List(4);
    _put(out, 0, value.fileType.raw, 'fileType');
    _put(out, 1, value.rawType.raw, 'rawType');
    _put(out, 2, value.cardSlot.raw, 'cardSlot');
    _put(out, 3, value.slotMode.raw, 'slotMode');
    return out;
  }

  @override
  BleFileType parseFields(String text) {
    final f = _fields(text, 4, 4);
    return BleFileType(
      BleEnumValue.parse(f[0], BleStillFileType.values),
      BleEnumValue.parse(f[1], BleRawType.values),
      BleEnumValue.parse(f[2], BleCardSlot.values),
      BleEnumValue.parse(f[3], BleSlotMode.values),
    );
  }

  @override
  Object? valueToJson(BleFileType value) => value.toJson();

  @override
  String describeValue(BleFileType value) =>
      '${value.fileType} raw=${value.rawType} slot=${value.cardSlot} '
      'mode=${value.slotMode}';

  @override
  String get syntax => '<fileType>,<rawType>,<cardSlot>,<slotMode>';
}

// ---------------------------------------------------------------------------
// GPS Information `28F59D60`

/// GPS record, 32 bytes (ble.md §GPS push; ble-imagesync.md §1):
/// latitude, longitude, altitude as float64 **big-endian**, then the fix
/// time `[year sint16 LE][month][day][hour][minute][second]` and a datum
/// byte (0 WGS84). Image Sync sends the fix time in UTC; GR WORLD's basis
/// is unknown, so callers choose it when building the record.
final class BleGpsInformation {
  const BleGpsInformation({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    required this.datum,
  });

  /// Takes calendar fields from [time] as given; convert it to UTC or local
  /// first.
  factory BleGpsInformation.at({
    required double latitude,
    required double longitude,
    required double altitude,
    required DateTime time,
  }) => BleGpsInformation(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    year: time.year,
    month: time.month,
    day: time.day,
    hour: time.hour,
    minute: time.minute,
    second: time.second,
    datum: BleEnumValue.of(BleGpsDatum.wgs84),
  );

  final double latitude;
  final double longitude;
  final double altitude;
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
  final BleEnumValue<BleGpsDatum> datum;

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'time': BleDateTime(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
    ).iso,
    'datum': datum.toJson(),
  };
}

final class BleGpsInformationCodec extends BleRecordCodec<BleGpsInformation> {
  const BleGpsInformationCodec();

  @override
  BleDecoded<BleGpsInformation> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 32, issues)) {
      return result(bytes, null, issues);
    }
    final data = ByteData.sublistView(bytes);
    final value = BleGpsInformation(
      latitude: data.getFloat64(0, Endian.big),
      longitude: data.getFloat64(8, Endian.big),
      altitude: data.getFloat64(16, Endian.big),
      year: BleIntFormat.sint16.read(bytes, 24),
      month: bytes[26],
      day: bytes[27],
      hour: bytes[28],
      minute: bytes[29],
      second: bytes[30],
      datum: _enumAt(bytes, 31, BleGpsDatum.values),
    );
    return result(bytes, value, issues);
  }

  @override
  Uint8List encode(BleGpsInformation value) {
    if (!value.latitude.isFinite || value.latitude.abs() > 90) {
      throw ArgumentError.value(value.latitude, 'latitude', 'must be -90..90');
    }
    if (!value.longitude.isFinite || value.longitude.abs() > 180) {
      throw ArgumentError.value(
        value.longitude,
        'longitude',
        'must be -180..180',
      );
    }
    if (!value.altitude.isFinite) {
      throw ArgumentError.value(value.altitude, 'altitude', 'must be finite');
    }
    _checkRange(value.month, 1, 12, 'month');
    _checkRange(value.day, 1, 31, 'day');
    _checkRange(value.hour, 0, 23, 'hour');
    _checkRange(value.minute, 0, 59, 'minute');
    _checkRange(value.second, 0, 59, 'second');
    final out = Uint8List(32);
    ByteData.sublistView(out)
      ..setFloat64(0, value.latitude, Endian.big)
      ..setFloat64(8, value.longitude, Endian.big)
      ..setFloat64(16, value.altitude, Endian.big);
    _put(out, 24, value.year, 'year', BleIntFormat.sint16);
    out
      ..[26] = value.month
      ..[27] = value.day
      ..[28] = value.hour
      ..[29] = value.minute
      ..[30] = value.second;
    _put(out, 31, value.datum.raw, 'datum');
    return out;
  }

  /// `lat,lon,alt,YYYY-MM-DDTHH:MM:SS` with the time fields sent as written.
  @override
  BleGpsInformation parseFields(String text) {
    final f = _fields(text, 4, 4);
    double d(String s, String name) =>
        double.tryParse(s) ?? (throw FormatException('Bad $name', s));
    final t = const BleDateTimeCodec().parseFields(f[3]);
    return BleGpsInformation(
      latitude: d(f[0], 'latitude'),
      longitude: d(f[1], 'longitude'),
      altitude: d(f[2], 'altitude'),
      year: t.year,
      month: t.month,
      day: t.day,
      hour: t.hour,
      minute: t.minute,
      second: t.second,
      datum: BleEnumValue.of(BleGpsDatum.wgs84),
    );
  }

  @override
  Object? valueToJson(BleGpsInformation value) => value.toJson();

  @override
  String describeValue(BleGpsInformation value) {
    final j = value.toJson();
    return '${value.latitude},${value.longitude} alt ${value.altitude} m '
        'at ${j['time']} ${value.datum}';
  }

  @override
  String get syntax => '<lat>,<lon>,<alt m>,<YYYY-MM-DDTHH:MM:SS>';
}
