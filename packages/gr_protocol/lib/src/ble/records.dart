import 'dart:typed_data';

import 'package:gr_protocol/src/ble/bytes.dart';
import 'package:gr_protocol/src/ble/codecs.dart';
import 'package:gr_protocol/src/ble/enums.dart';

// Multi-field characteristic values. Layouts: research/protocol/ble.md
// §Service and characteristic map / §Payload details (GR WORLD) and
// research/protocol/ble-imagesync.md §1 (Image Sync `def_ble.yaml`): fields are
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
  /// Const constructor for subclasses.
  const new();

  /// Parses the codec's field syntax (see [syntax]). [parse] strips
  /// surrounding whitespace and handles `hex:` input before calling this.
  /// Throws [FormatException].
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
  /// Request from decoded or parsed wire values, which may be undocumented.
  const new(this.code, this.parameter);

  /// Request from documented enum members.
  new of(BleOperationCode code, BleOperationParameter parameter)
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

  /// Byte 0: 0 NOP, 1 start shooting/recording, 2 stop.
  final BleEnumValue<BleOperationCode> code;

  /// Byte 1: 0 no AF, 1 AF, 2 green-button function.
  final BleEnumValue<BleOperationParameter> parameter;

  /// `{code, parameter}`.
  Map<String, Object?> toJson() => {
    'code': code.toJson(),
    'parameter': parameter.toJson(),
  };
}

/// Codec for [BleOperationRequest].
final class BleOperationRequestCodec
    extends BleRecordCodec<BleOperationRequest> {
  /// Creates the codec.
  const new();

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
  /// Pass [option] only for the 3-byte Image Sync form.
  const new(this.mode, this.userMode, [this.option]);

  /// Byte 0 (uint8): exposure mode (P, Av, Tv, M, …, AstroTracer, movie).
  final BleEnumValue<BleExposureMode> mode;

  /// Byte 1: active user mode, 0 none or 1–5 for U1–U5.
  final BleEnumValue<BleUserMode> userMode;

  /// Byte 2 (Image Sync only): 0 none, 1 hyper, 2 shift.
  final BleEnumValue<BleShootingModeOption>? option;

  /// Copy with [mode] and/or [userMode] replaced. [option] is kept, so the
  /// encoded length does not change.
  BleShootingMode copyWith({
    BleEnumValue<BleExposureMode>? mode,
    BleEnumValue<BleUserMode>? userMode,
  }) => BleShootingMode(mode ?? this.mode, userMode ?? this.userMode, option);

  /// `{mode, userMode, option}`; option is null for the 2-byte form.
  Map<String, Object?> toJson() => {
    'mode': mode.toJson(),
    'userMode': userMode.toJson(),
    'option': option?.toJson(),
  };
}

/// Codec for [BleShootingMode], accepting both lengths.
final class BleShootingModeCodec extends BleRecordCodec<BleShootingMode> {
  /// Creates the codec.
  const new();

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
  /// Leave the extended fields null for the 2-byte GR WORLD form; setting
  /// [still] selects the 8-byte form.
  const new({
    required this.capturing,
    required this.countdown,
    this.still,
    this.movie,
    this.type3CaptureState,
    this.type3PreCaptureResult,
    this.astroTrackingTime,
  });

  /// Byte 0: 0 idle, 1 shooting in progress.
  final BleEnumValue<BleCapturing> capturing;

  /// Byte 1: 0 none, 1 self-timer counting down, 2 waiting for scheduled
  /// time.
  final BleEnumValue<BleCountdown> countdown;

  /// Byte 2: 0 other, 1 continuous, 2 bracket, 3 multi-exposure,
  /// 4 interval, 5 interval-composite.
  final BleEnumValue<BleStillCaptureState>? still;

  /// Byte 3: 0 other, 1 recording.
  final BleEnumValue<BleMovieCaptureState>? movie;

  /// Byte 4: AstroTracer Type 3 state, 0 idle, 1 pre-capture, 2 main
  /// capture.
  final BleEnumValue<BleType3CaptureState>? type3CaptureState;

  /// Byte 5: AstroTracer Type 3 pre-capture result, 0 ok, 1 motion not
  /// detectable, 2 exposure-time error.
  final BleEnumValue<BleType3PreCaptureResult>? type3PreCaptureResult;

  /// Bytes 6–7 (uint16): AstroTracer tracking time. Unit not documented.
  final int? astroTrackingTime;

  /// Whether this is the 8-byte Image Sync form (keyed on [still]).
  bool get isExtended => still != null;

  /// Extended fields are included only when [isExtended].
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

/// Codec for [BleCaptureStatus], accepting both lengths.
final class BleCaptureStatusCodec extends BleRecordCodec<BleCaptureStatus> {
  /// Creates the codec.
  const new();

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

  /// The command this app's format sends to cancel a countdown.
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
  /// Omit [remocon] for the 1-byte GR WORLD form.
  const new(this.cancel, [this.remocon]);

  /// Byte 0: 0 other, 1 cancel the running countdown.
  final BleEnumValue<BleCountdownCancel> cancel;

  /// Byte 1 (Image Sync only): remote control 0 off, 1 on.
  final BleEnumValue<BleRemocon>? remocon;

  /// `{cancel, remocon}`; remocon is null for the 1-byte form.
  Map<String, Object?> toJson() => {
    'cancel': cancel.toJson(),
    'remocon': remocon?.toJson(),
  };
}

/// Codec for [BleSelfTimerCommand], accepting both lengths.
final class BleSelfTimerCodec extends BleRecordCodec<BleSelfTimerCommand> {
  /// Creates the codec.
  const new();

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
  String describeValue(BleSelfTimerCommand value) => [
    '${value.cancel}',
    if (value.remocon != null) 'remocon=${value.remocon}',
  ].join(' ');

  @override
  String get syntax => '<cancel>[,<remocon>] e.g. cancel | cancel,on';
}

// ---------------------------------------------------------------------------
// Image Control custom data (GR WORLD)

/// One Image Control parameter: id byte and signed value.
final class BleImageControlEntry {
  /// Entry for one parameter id and its value.
  const new(this.parameter, this.value);

  /// Parameter id (saturation, hue, key, contrast, …). GR WORLD skips ids
  /// it does not know; they keep their raw value here.
  final BleEnumValue<BleImageControlParameter> parameter;

  /// Signed adjustment (sint8); per-parameter range not documented.
  final int value;

  /// `{parameter, value}`.
  Map<String, Object?> toJson() => {
    'parameter': parameter.toJson(),
    'value': value,
  };
}

/// Image Control custom 1–3 data blob (ble.md §Image Control blob):
/// `[version][unknown][base image][N][N × (id, sint8 value)]`, zero-filled
/// to [length] bytes. GR WORLD accepts versions 1, 2 and 4 only.
final class BleImageControlBlob {
  /// Copies [parameters] into an unmodifiable list.
  new({
    required this.version,
    required this.reserved,
    required this.base,
    required List<BleImageControlEntry> parameters,
  }) : parameters = List.unmodifiable(parameters);

  /// Versions GR WORLD accepts; it ignores blobs with any other version.
  static const supportedVersions = {1, 2, 4};

  /// Bytes in every blob the Custom slots and `/imgctrl` carry, zero after
  /// the parameters. A GR IV HDF on firmware 1.20 refused slot writes of
  /// 22 and 74 bytes and accepted 56 (observed 2026-11-09, ble.md § Image
  /// Control blob).
  static const length = 56;

  /// The most parameters that fit in [length].
  static const int maxParameters = (length - 4) ~/ 2;

  /// Byte 0: blob format version, see [supportedVersions].
  final int version;

  /// Byte 1; GR WORLD never reads it, meaning unknown.
  final int reserved;

  /// Byte 2: base image (standard, vivid, monotone, positive film, …).
  final BleEnumValue<BleImageControlBase> base;

  /// Adjustments in wire order (count in byte 3); unmodifiable.
  final List<BleImageControlEntry> parameters;

  /// Header fields and parameters.
  Map<String, Object?> toJson() => {
    'version': version,
    'reserved': reserved,
    'base': base.toJson(),
    'parameters': [for (final p in parameters) p.toJson()],
  };
}

/// Codec for [BleImageControlBlob]. Text input is hex only.
final class BleImageControlCodec extends BleCodec<BleImageControlBlob> {
  /// Creates the codec.
  const new();

  @override
  BleDecoded<BleImageControlBlob> decode(Uint8List bytes) {
    final issues = <String>[];
    if (bytes.length < 4) {
      return result(bytes, null, [
        'expected at least 4 header bytes, got ${bytes.length}',
      ]);
    }
    if (bytes.length != BleImageControlBlob.length) {
      issues.add('${bytes.length} bytes, not ${BleImageControlBlob.length}');
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
    if (bytes.skip(4 + 2 * n).any((b) => b != 0)) {
      issues.add('non-zero byte(s) after the parameters');
    }
    return result(
      bytes,
      BleImageControlBlob(
        version: version,
        reserved: bytes[1],
        base: BleEnumValue.decode(bytes[2], BleImageControlBase.values),
        parameters: params,
      ),
      issues,
    );
  }

  @override
  Uint8List encode(BleImageControlBlob value) {
    if (value.parameters.length > BleImageControlBlob.maxParameters) {
      throw ArgumentError.value(
        value.parameters.length,
        'parameters',
        'at most ${BleImageControlBlob.maxParameters} fit in '
            '${BleImageControlBlob.length} bytes',
      );
    }
    final out = Uint8List(BleImageControlBlob.length);
    _put(out, 0, value.version, 'version', BleIntFormat.uint8);
    _put(out, 1, value.reserved, 'reserved', BleIntFormat.uint8);
    _put(out, 2, value.base.raw, 'base', BleIntFormat.uint8);
    _put(out, 3, value.parameters.length, 'count', BleIntFormat.uint8);
    for (var i = 0; i < value.parameters.length; i++) {
      final p = value.parameters[i];
      _put(out, 4 + 2 * i, p.parameter.raw, 'parameter', BleIntFormat.uint8);
      _put(out, 5 + 2 * i, p.value, 'value');
    }
    return out;
  }

  @override
  BleImageControlBlob parse(String text) {
    final t = text.trim();
    return parseHex(t.startsWith('hex:') ? t.substring(4) : t);
  }

  @override
  Object? valueToJson(BleImageControlBlob value) => value.toJson();

  @override
  String describeValue(BleImageControlBlob value) {
    final params = value.parameters
        .map((p) => '${p.parameter.label}=${p.value}')
        .join(' ');
    return 'v${value.version} ${value.base} $params';
  }

  @override
  String get syntax => 'hex bytes of the whole blob';
}

// ---------------------------------------------------------------------------
// Date Time `FA46BBDD`

/// Camera clock: `[year uint16 LE][month][day][hour][minute][second]`, in
/// the camera's local time; no zone, weekday or milliseconds (ble.md
/// §Date/time sync; both apps send phone local time).
final class BleDateTime {
  /// Fields are range-checked only by [BleDateTimeCodec.encode].
  const new({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
  });

  /// Uses [time]'s own calendar fields; pass a local [DateTime] to match
  /// both apps.
  factory fromDateTime(DateTime time) => BleDateTime(
    year: time.year,
    month: time.month,
    day: time.day,
    hour: time.hour,
    minute: time.minute,
    second: time.second,
  );

  /// Bytes 0–1 (uint16).
  final int year;

  /// Byte 2, 1–12.
  final int month;

  /// Byte 3, 1–31.
  final int day;

  /// Byte 4, 0–23.
  final int hour;

  /// Byte 5, 0–59.
  final int minute;

  /// Byte 6, 0–59.
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

  /// `YYYY-MM-DDTHH:MM:SS` with no zone suffix; the camera clock has none.
  String get iso =>
      '${year.toString().padLeft(4, '0')}-${_pad2(month)}-${_pad2(day)}'
      'T${_pad2(hour)}:${_pad2(minute)}:${_pad2(second)}';

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  /// Calendar fields plus [iso].
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

/// Codec for [BleDateTime].
final class BleDateTimeCodec extends BleRecordCodec<BleDateTime> {
  /// Creates the codec.
  const new();

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
  /// Set [powerSource] or [endScreenData] only for their wire form. When
  /// encoding, [byte1] wins over [powerSource].
  const new({
    required this.level,
    this.byte1,
    this.powerSource,
    this.endScreenData,
  });

  /// Byte 0 (sint8): battery charge level. Shown as a percentage; neither
  /// app documents the scale.
  final int level;

  /// Raw byte 1, or null for the 1-byte form; see the class doc.
  final int? byte1;

  /// Image Sync reading of byte 1; set only for the 2-byte form.
  final BleEnumValue<BlePowerSource>? powerSource;

  /// GR WORLD long form; null otherwise.
  final Uint8List? endScreenData;

  /// `{level, byte1, powerSource}`, plus `endScreenDataHex` for the long
  /// form.
  Map<String, Object?> toJson() => {
    'level': level,
    'byte1': byte1,
    'powerSource': powerSource?.toJson(),
    if (endScreenData != null)
      'endScreenDataHex': BleBytes.toHex(endScreenData!),
  };
}

/// Codec for [BleBatteryLevel], accepting the 1-byte, 2-byte and long
/// forms.
final class BleBatteryLevelCodec extends BleRecordCodec<BleBatteryLevel> {
  /// Creates the codec.
  const new();

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
  /// Pass [active] only for the 15-byte Image Sync form.
  const new({
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

  /// Byte 0: 0 internal memory, 1 SD slot 1, 2 SD slot 2.
  final BleEnumValue<BleStorageType> type;

  /// Byte 1 == 1: the storage is present.
  final bool exists;

  /// Byte 2 == 1: the storage is locked.
  final bool locked;

  /// Byte 3 == 1: the storage is available.
  final bool available;

  /// Byte 4 == 1: the storage is formatted.
  final bool formatted;

  /// Bytes 5–8 (sint32): remaining still-picture capacity.
  final int remainingPictures;

  /// Bytes 9–12 (sint32): remaining video recording time in seconds.
  final int remainingVideoSeconds;

  /// Raw int8; meaning unknown in both apps.
  final int fileType;

  /// Byte 14 == 1: the camera writes to this storage. Null for 14-byte
  /// entries.
  final bool? active;

  /// All fields; `fileTypeRaw` holds [fileType].
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
  /// Copies [entries] into an unmodifiable list.
  new(List<BleStorageEntry> entries, this.entrySize)
    : entries = List.unmodifiable(entries);

  /// Entries in wire order; unmodifiable.
  final List<BleStorageEntry> entries;

  /// 14 or 15. Encoding ignores it and uses 15 when any entry has
  /// [BleStorageEntry.active].
  final int? entrySize;

  /// `{entrySize, entries}`.
  Map<String, Object?> toJson() => {
    'entrySize': entrySize,
    'entries': [for (final e in entries) e.toJson()],
  };
}

/// Codec for [BleStorageInformation], accepting 14- and 15-byte entries.
/// Text input is hex only.
final class BleStorageInformationCodec
    extends BleRecordCodec<BleStorageInformation> {
  /// Creates the codec.
  const new();

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
      const sizes = 'matches neither 14- nor 15-byte entries';
      return result(bytes, null, ['count $n with $rest entry byte(s) $sizes']);
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
  /// Record from both flags.
  const new({required this.notEmpty, required this.changed});

  /// Byte 0 == 1: the camera's file transfer list has entries.
  final bool notEmpty;

  /// Byte 1 == 1: the list changed.
  final bool changed;

  /// `{notEmpty, changed}`.
  Map<String, Object?> toJson() => {'notEmpty': notEmpty, 'changed': changed};
}

/// Codec for [BleFileTransferList].
final class BleFileTransferListCodec
    extends BleRecordCodec<BleFileTransferList> {
  /// Creates the codec.
  const new();

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
  Uint8List encode(BleFileTransferList value) => Uint8List.fromList([
    if (value.notEmpty) 1 else 0,
    if (value.changed) 1 else 0,
  ]);

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
  /// Record from both fields.
  const new(this.behavior, {required this.autoResize});

  /// Byte 0: 0 abort the transfer and power off, 1 power off after the
  /// transfer (Image Sync). GR WORLD only tests `== 1`.
  final BleEnumValue<BleTransferPowerOffBehavior> behavior;

  /// Byte 1 == 1: auto resize is on.
  final bool autoResize;

  /// `{behavior, autoResize}`.
  Map<String, Object?> toJson() => {
    'behavior': behavior.toJson(),
    'autoResize': autoResize,
  };
}

/// Codec for [BlePowerOffDuringTransfer].
final class BlePowerOffDuringTransferCodec
    extends BleRecordCodec<BlePowerOffDuringTransfer> {
  /// Creates the codec.
  const new();

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
        autoResize: bytes[1] == 1,
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
      autoResize: parseBoolText(f[1]),
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
  /// Record from both fields.
  const new(this.mode, this.setting);

  /// Byte 0: 0 MF, 1 AF.
  final BleEnumValue<BleFocusMode> mode;

  /// Byte 1: 0 MF, 1 auto-area, 2 select, 3 pinpoint, 4 tracking,
  /// 5 continuous, 6 snap, 7 infinity, 8 movie, 9 auto-area (center),
  /// 10 star AF.
  final BleEnumValue<BleFocusSetting> setting;

  /// `{mode, setting}`.
  Map<String, Object?> toJson() => {
    'mode': mode.toJson(),
    'setting': setting.toJson(),
  };
}

/// Codec for [BleFocus].
final class BleFocusCodec extends BleRecordCodec<BleFocus> {
  /// Creates the codec.
  const new();

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
  /// Record from both fields.
  const new(this.running, this.inFocus);

  /// Byte 0: 0 stopped, 1 AF running.
  final BleEnumValue<BleAfRunning> running;

  /// Byte 1: 0 not in focus, 1 in focus.
  final BleEnumValue<BleAfInFocus> inFocus;

  /// `{running, inFocus}`.
  Map<String, Object?> toJson() => {
    'running': running.toJson(),
    'inFocus': inFocus.toJson(),
  };
}

/// Codec for [BleAfStatus].
final class BleAfStatusCodec extends BleRecordCodec<BleAfStatus> {
  /// Creates the codec.
  const new();

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

/// Shot Count (`12D262BA`): `[current sint8][total sint8]`. Image Sync
/// names the fields only; what they count is not documented.
final class BleShotCount {
  /// Record from both counts.
  const new(this.current, this.total);

  /// Byte 0: current shot.
  final int current;

  /// Byte 1: total shots.
  final int total;

  /// `{current, total}`.
  Map<String, Object?> toJson() => {'current': current, 'total': total};
}

/// Codec for [BleShotCount].
final class BleShotCountCodec extends BleRecordCodec<BleShotCount> {
  /// Creates the codec.
  const new();

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
  /// Record from all four fields.
  const new(this.fileType, this.rawType, this.cardSlot, this.slotMode);

  /// Byte 0: 0 JPEG, 1 PEF, 2 DNG, 3 JPEG+PEF, 4 JPEG+DNG.
  final BleEnumValue<BleStillFileType> fileType;

  /// Byte 1: 0 PEF, 1 DNG.
  final BleEnumValue<BleRawType> rawType;

  /// Byte 2: 0 SD slot 1, 1 SD slot 2.
  final BleEnumValue<BleCardSlot> cardSlot;

  /// Byte 3: 0 sequential, 1 duplicate, 2 RAW/JPEG split.
  final BleEnumValue<BleSlotMode> slotMode;

  /// Copy with [fileType] and/or [rawType] replaced; slot fields are kept.
  BleFileType copyWith({
    BleEnumValue<BleStillFileType>? fileType,
    BleEnumValue<BleRawType>? rawType,
  }) => BleFileType(
    fileType ?? this.fileType,
    rawType ?? this.rawType,
    cardSlot,
    slotMode,
  );

  /// `{fileType, rawType, cardSlot, slotMode}`.
  Map<String, Object?> toJson() => {
    'fileType': fileType.toJson(),
    'rawType': rawType.toJson(),
    'cardSlot': cardSlot.toJson(),
    'slotMode': slotMode.toJson(),
  };
}

/// Codec for [BleFileType].
final class BleFileTypeCodec extends BleRecordCodec<BleFileType> {
  /// Creates the codec.
  const new();

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
  /// Fields are range-checked only by [BleGpsInformationCodec.encode].
  const new({
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
  factory at({
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

  /// Bytes 0–7: degrees, -90..90.
  final double latitude;

  /// Bytes 8–15: degrees, -180..180.
  final double longitude;

  /// Bytes 16–23: metres.
  final double altitude;

  /// Bytes 24–25 (sint16): fix time year.
  final int year;

  /// Byte 26: fix time month, 1–12.
  final int month;

  /// Byte 27: fix time day, 1–31.
  final int day;

  /// Byte 28: fix time hour, 0–23.
  final int hour;

  /// Byte 29: fix time minute, 0–59.
  final int minute;

  /// Byte 30: fix time second, 0–59.
  final int second;

  /// Byte 31: 0 WGS84, the only value either app sends.
  final BleEnumValue<BleGpsDatum> datum;

  /// Coordinates, fix `time` as ISO-8601 without a zone, and datum.
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

/// Codec for [BleGpsInformation].
final class BleGpsInformationCodec extends BleRecordCodec<BleGpsInformation> {
  /// Creates the codec.
  const new();

  @override
  BleDecoded<BleGpsInformation> decode(Uint8List bytes) {
    final issues = <String>[];
    if (!fixedLengthUsable(bytes, 32, issues)) {
      return result(bytes, null, issues);
    }
    final data = ByteData.sublistView(bytes);
    final value = BleGpsInformation(
      latitude: data.getFloat64(0),
      longitude: data.getFloat64(8),
      altitude: data.getFloat64(16),
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
      ..setFloat64(0, value.latitude)
      ..setFloat64(8, value.longitude)
      ..setFloat64(16, value.altitude);
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
