import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/looks/image_control.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// A look: a base image and the adjustments made to it, as an Image
/// Control Custom slot (C1–C3) holds it and `/imgctrl` reports it for a
/// photo (research/protocol/image-control.md §1).
///
/// A look keeps everything its bytes held: the header (format version and
/// byte 1) and any base or parameter GR Photo does not know. A look read from
/// a camera therefore writes back unchanged, and only what GR Photo knows is
/// shown: [base], [values].
@immutable
final class Look {
  new _(this._blob);

  /// A new look on [base] with every parameter the base has
  /// ([lookParameters]) at its [LookRange.initial] value (0 where the range
  /// is unknown). The header is copied from [template], a look a camera
  /// produced, when there is one: which header a camera expects of a blob
  /// it did not produce is \[unknown\]. Without one it is format version 1
  /// and byte 1 zero, the header of GR WORLD's own fallback look and the
  /// version a GR IV HDF on firmware 1.20 stores
  /// (research/protocol/image-control.md §1).
  factory onBase(LookBase base, {Look? template}) => Look._(
    BleImageControlBlob(
      version: template?._blob.version ?? 1,
      reserved: template?._blob.reserved ?? 0,
      base: BleEnumValue.of(base._wire),
      parameters: [
        for (final p in lookParameters(base)) _entry(p, _initial(p)),
      ],
    ),
  );

  /// The look [bytes] hold, laid out as the Custom slots and `/imgctrl`
  /// carry it (ble.md § Image Control blob); null when they do not even
  /// hold the header. Bytes shorter than a slot's, as GR Photo saved looks
  /// before it padded them, still read.
  static Look? fromBytes(Uint8List bytes) {
    final blob = BleImageControlBlob.readFrom(BleByteReader(bytes), []);
    return blob == null ? null : Look._(blob);
  }

  final BleImageControlBlob _blob;

  /// The base image; null when it is one GR Photo does not know.
  late final LookBase? base = LookBase._byWire[_blob.base.known];

  /// The number of a base image GR Photo does not know, as the look holds
  /// it, so it can still be named; null when [base] is known.
  int? get unknownBaseNumber => base == null ? _blob.base.raw : null;

  /// The parameters GR Photo knows and their values, in the order the look
  /// lists them; unmodifiable. Parameters it does not know are kept, but
  /// left out here. A parameter listed twice has its first value.
  late final Map<LookParameter, int> values = _knownValues();

  /// The value of [parameter], or null when the look does not have it.
  int? valueOf(LookParameter parameter) => values[parameter];

  /// This look with [parameter] set to [value], in place when the look has
  /// it, else added at the end.
  Look withValue(LookParameter parameter, int value) {
    final entry = _entry(parameter, value);
    final has = values.containsKey(parameter);
    return _withParameters([
      for (final e in _blob.parameters)
        if (e.parameter.known == parameter._wire) entry else e,
      if (!has) entry,
    ]);
  }

  /// This look on [base] instead: the parameters [base] has, in wire-id
  /// order, each keeping its value when this look has it and starting at
  /// its initial value when not. The header stays. That the camera wants
  /// exactly its base's parameters is \[inferred\] from the firmware's
  /// per-base settings.
  Look withBase(LookBase base) => Look._(
    BleImageControlBlob(
      version: _blob.version,
      reserved: _blob.reserved,
      base: BleEnumValue.of(base._wire),
      parameters: [
        for (final p in lookParameters(base))
          _entry(p, valueOf(p) ?? _initial(p)),
      ],
    ),
  );

  /// Whether [camera] offers this look's base image ([lookBases]); false
  /// when the base is one GR Photo does not know. GR WORLD offers a body only
  /// the looks of its own type (observed in GR WORLD 2.0.0's code,
  /// `findSupportedByCameraType` 0xda1db4).
  bool offeredBy(CameraBody camera) {
    final base = this.base;
    return base != null && lookBases(camera).contains(base);
  }

  /// What this look does to a picture, apart from how its bytes lay it
  /// out: compare two looks' settings with `==` to tell whether they are
  /// the same look.
  late final LookSettings settings = LookSettings._(_blob);

  /// The look as the Custom slots and `/imgctrl` carry it: the header, each
  /// parameter, then zeros up to the slot's 56 bytes (ble.md § Image
  /// Control blob). Throws [ArgumentError] when a value does not fit its
  /// byte or the look has more parameters than a slot holds.
  Uint8List toBytes() {
    final out = BleByteWriter();
    _blob.writeTo(out);
    return out.toBytes();
  }

  Map<LookParameter, int> _knownValues() {
    final known = <LookParameter, int>{};
    for (final e in _blob.parameters) {
      final parameter = LookParameter._byWire[e.parameter.known];
      if (parameter != null) known.putIfAbsent(parameter, () => e.value);
    }
    return Map.unmodifiable(known);
  }

  Look _withParameters(List<BleImageControlEntry> parameters) => Look._(
    BleImageControlBlob(
      version: _blob.version,
      reserved: _blob.reserved,
      base: _blob.base,
      parameters: parameters,
    ),
  );

  static BleImageControlEntry _entry(LookParameter parameter, int value) =>
      BleImageControlEntry(BleEnumValue.of(parameter._wire), value);

  static int _initial(LookParameter parameter) =>
      lookRange(parameter)?.initial ?? 0;
}

/// A look's base image and the value of each of its parameters, compared
/// by value: two looks with equal settings are the same look, whatever
/// their bytes.
///
/// The settings are derived from a look's bytes and never stored, so what
/// counts as the same look can change without converting saved looks. Only
/// what the look means is compared \[design\]:
///
/// - the header (format version and byte 1) is left out, so a look still
///   matches after a camera stored it in its own format version;
/// - so are the order of the parameters, the zeros after them and the
///   length of the bytes;
/// - a base image or parameter GR Photo does not know is compared by its
///   number, so looks from a newer camera or firmware compare too;
/// - a parameter listed twice has its first value, as in [Look.values].
///
/// A look that lacks a parameter differs from one that has it, even at its
/// initial value: what a camera takes a missing parameter to be is
/// \[unknown\], and the GR IV's firmware refuses a look without exactly
/// its base's parameters (research/protocol/image-control.md §1).
@immutable
final class LookSettings {
  new _(BleImageControlBlob blob)
    : _base = blob.base.raw,
      _values = {
        // Last to first, so that a parameter's first value is the one kept.
        for (final e in blob.parameters.reversed) e.parameter.raw: e.value,
      };

  /// The base image's number on the wire.
  final int _base;

  /// Each parameter's value, by the parameter's number on the wire.
  final Map<int, int> _values;

  @override
  bool operator ==(Object other) =>
      other is LookSettings &&
      _base == other._base &&
      mapEquals(_values, other._values);

  @override
  late final int hashCode = Object.hash(
    _base,
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in _values.entries)
        Object.hash(key, value),
    ]),
  );
}

/// The look [blob] holds. Used inside the camera layer only; not exported.
Look lookOf(BleImageControlBlob blob) => Look._(blob);

/// A look's Image Control blob, for the camera layer. Not exported.
extension LookInternals on Look {
  /// The blob this look is.
  BleImageControlBlob get blob => _blob;
}

/// A base image: the starting point of a look, before its adjustments
/// (research/protocol/image-control.md §3).
enum LookBase {
  /// Standard.
  standard(BleImageControlBase.standard),

  /// Vivid.
  vivid(BleImageControlBase.vivid),

  /// Monotone.
  monotone(BleImageControlBase.monotone),

  /// Soft Monotone.
  softMonotone(BleImageControlBase.softMonotone),

  /// Hard Monotone.
  hardMonotone(BleImageControlBase.hardMonotone),

  /// Hi-Contrast B&W.
  highContrast(BleImageControlBase.highContrast),

  /// Positive Film.
  positiveFilm(BleImageControlBase.positiveFilm),

  /// Bleach Bypass.
  bleachBypass(BleImageControlBase.bleachBypass),

  /// Retro.
  retro(BleImageControlBase.retro),

  /// HDR Tone.
  hdrTone(BleImageControlBase.hdrTone),

  /// Negative Film.
  negativeFilm(BleImageControlBase.negativeFilm),

  /// Cinema (Yellow).
  cineYellow(BleImageControlBase.cineYellow),

  /// Cinema (Green).
  cineGreen(BleImageControlBase.cineGreen),

  /// Cross Processing.
  crossProcess(BleImageControlBase.crossProcess),

  /// Monochrome Standard.
  standardMono(BleImageControlBase.standardMono),

  /// Monochrome Soft.
  softMono(BleImageControlBase.softMono),

  /// Monochrome High Contrast.
  highContrastMono(BleImageControlBase.highContrastMono),

  /// Grainy.
  grainy(BleImageControlBase.grainy),

  /// Solid.
  solid(BleImageControlBase.solid),

  /// Monochrome HDR Tone.
  hdrMono(BleImageControlBase.hdrMono),

  /// Palette.
  palette(BleImageControlBase.pallet),

  /// Solarized Effect.
  solarization(BleImageControlBase.solarization),

  /// Pictorialist Effect.
  pictorialist(BleImageControlBase.pictorialist);

  new(this._wire);

  /// The base as the Image Control blob carries it.
  final BleImageControlBase _wire;

  static final Map<BleImageControlBase, LookBase> _byWire = {
    for (final b in values) b._wire: b,
  };
}

/// One adjustment a look carries (research/protocol/image-control.md §3).
enum LookParameter {
  /// Saturation.
  saturation(BleImageControlParameter.saturation),

  /// Hue.
  hue(BleImageControlParameter.hue),

  /// Key (brightness).
  key(BleImageControlParameter.key),

  /// Contrast.
  contrast(BleImageControlParameter.contrast),

  /// Contrast in the highlights.
  contrastHigh(BleImageControlParameter.contrastHigh),

  /// Contrast in the shadows.
  contrastLow(BleImageControlParameter.contrastLow),

  /// Sharpness.
  sharpness(BleImageControlParameter.sharpness),

  /// Toning of the monotone bases.
  toningMonotone(BleImageControlParameter.toningMonotone),

  /// Toning of the cinema bases.
  toningCinema(BleImageControlParameter.toningCinema),

  /// Toning of Bleach Bypass.
  toningBleachBypass(BleImageControlParameter.toningBleachBypass),

  /// Toning of Retro.
  toningRetro(BleImageControlParameter.toningRetro),

  /// HDR Tone level.
  toningHdr(BleImageControlParameter.toningHdr),

  /// Filter effect.
  filterEffect(BleImageControlParameter.filterEffect),

  /// Custom filter, red, high byte.
  filterEffectRedHigh(BleImageControlParameter.filterEffectRedHigh),

  /// Custom filter, red, low byte.
  filterEffectRedLow(BleImageControlParameter.filterEffectRedLow),

  /// Custom filter, green, high byte.
  filterEffectGreenHigh(BleImageControlParameter.filterEffectGreenHigh),

  /// Custom filter, green, low byte.
  filterEffectGreenLow(BleImageControlParameter.filterEffectGreenLow),

  /// Custom filter, blue, high byte.
  filterEffectBlueHigh(BleImageControlParameter.filterEffectBlueHigh),

  /// Custom filter, blue, low byte.
  filterEffectBlueLow(BleImageControlParameter.filterEffectBlueLow),

  /// Shading.
  shading(BleImageControlParameter.shading),

  /// Clarity.
  clarity(BleImageControlParameter.clarity),

  /// Grain effect on or off.
  grain(BleImageControlParameter.grain),

  /// Grain size.
  grainSize(BleImageControlParameter.grainSize),

  /// Grain intensity.
  grainStrength(BleImageControlParameter.grainStrength),

  /// HDR strength.
  hdrStrength(BleImageControlParameter.hdrStrength),

  /// Cross Processing colour tone.
  crossProcess(BleImageControlParameter.crossProcess),

  /// Base colour.
  baseColor(BleImageControlParameter.baseColor),

  /// White point.
  whitePoint(BleImageControlParameter.whitePoint),

  /// Black point.
  blackPoint(BleImageControlParameter.blackPoint),

  /// RGB tone, highlights, green–magenta.
  rgbToneHighlightsGm(BleImageControlParameter.rgbToneHighlightsGm),

  /// RGB tone, highlights, blue–amber.
  rgbToneHighlightsBa(BleImageControlParameter.rgbToneHighlightsBa),

  /// RGB tone, midtones, green–magenta.
  rgbToneMidtonesGm(BleImageControlParameter.rgbToneMidtonesGm),

  /// RGB tone, midtones, blue–amber.
  rgbToneMidtonesBa(BleImageControlParameter.rgbToneMidtonesBa),

  /// RGB tone, shadows, green–magenta.
  rgbToneShadowsGm(BleImageControlParameter.rgbToneShadowsGm),

  /// RGB tone, shadows, blue–amber.
  rgbToneShadowsBa(BleImageControlParameter.rgbToneShadowsBa),

  /// Solarization type.
  solarizationType(BleImageControlParameter.solarizationType);

  new(this._wire);

  /// The parameter as the Image Control blob carries it.
  final BleImageControlParameter _wire;

  static final Map<BleImageControlParameter, LookParameter> _byWire = {
    for (final p in values) p._wire: p,
  };
}
