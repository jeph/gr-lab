import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// How a parameter's wire values read.
enum ImageControlValueKind {
  /// A signed adjustment the camera shows as the number itself (`-4`..`+4`).
  steps,

  /// An index into a list of choices (Off, Sepia, Red, …).
  choice,
}

/// The values a parameter takes on the wire, [min] to [max] in steps of 1.
@immutable
final class ImageControlRange {
  /// A range of [kind] from [min] to [max].
  const new(this.kind, this.min, this.max);

  /// How the values read.
  final ImageControlValueKind kind;

  /// The lowest value.
  final int min;

  /// The highest value.
  final int max;

  /// The value a parameter gets when a look gains it: 0, as in GR WORLD's
  /// fallback look, which holds 0 for every parameter (code 0x82cd88), or
  /// [min] when 0 is out of range. The camera's own defaults are
  /// \[unknown\] for most choices.
  int get initial => 0.clamp(min, max);
}

const _steps = ImageControlRange(ImageControlValueKind.steps, -4, 4);

/// A named value of a choice parameter, as GR WORLD's value formatter
/// names it (research/protocol/image-control.md §4).
enum ImageControlChoice {
  /// Off.
  off,

  /// Sepia.
  sepia,

  /// Red.
  red,

  /// Green.
  green,

  /// Blue.
  blue,

  /// Purple.
  purple,

  /// Low.
  low,

  /// Medium.
  medium,

  /// High.
  high,

  /// Normal.
  normal,

  /// Cool.
  cool,

  /// Warm.
  warm,

  /// Black & White.
  blackAndWhite,

  /// Custom filter 1.
  customFilter1,

  /// Custom filter 2.
  customFilter2,

  /// Custom filter 3.
  customFilter3,

  /// Custom filter 4.
  customFilter4,

  /// On.
  on,

  /// Small.
  small,

  /// Large.
  large,

  /// Basic.
  basic,

  /// Magenta.
  magenta,

  /// Yellow.
  yellow,
}

/// The named values of [parameter], indexed by wire value, or null when
/// the camera shows its value as a number. These are the cases of GR
/// WORLD's value formatter (code 0x95abc8–0x95b7f8,
/// research/protocol/image-control.md §4).
List<ImageControlChoice>? imageControlChoices(
  BleImageControlParameter parameter,
) => switch (parameter) {
  BleImageControlParameter.toningMonotone => const [
    ImageControlChoice.off,
    ImageControlChoice.sepia,
    ImageControlChoice.red,
    ImageControlChoice.green,
    ImageControlChoice.blue,
    ImageControlChoice.purple,
  ],
  BleImageControlParameter.toningCinema ||
  BleImageControlParameter.grainStrength => const [
    ImageControlChoice.low,
    ImageControlChoice.medium,
    ImageControlChoice.high,
  ],
  BleImageControlParameter.toningBleachBypass => const [
    ImageControlChoice.off,
    ImageControlChoice.normal,
    ImageControlChoice.cool,
    ImageControlChoice.warm,
  ],
  BleImageControlParameter.toningHdr => const [
    ImageControlChoice.off,
    ImageControlChoice.blackAndWhite,
    ImageControlChoice.sepia,
  ],
  // GR WORLD tells only 0 (Off) from anything else (On); that 1–4 select
  // custom filters 1–4 is \[inferred\] from the GR IIIx firmware.
  BleImageControlParameter.filterEffect => const [
    ImageControlChoice.off,
    ImageControlChoice.customFilter1,
    ImageControlChoice.customFilter2,
    ImageControlChoice.customFilter3,
    ImageControlChoice.customFilter4,
  ],
  // That On is 1 is \[inferred\].
  BleImageControlParameter.grain => const [
    ImageControlChoice.off,
    ImageControlChoice.on,
  ],
  BleImageControlParameter.grainSize => const [
    ImageControlChoice.small,
    ImageControlChoice.medium,
    ImageControlChoice.large,
  ],
  BleImageControlParameter.hdrStrength => const [
    ImageControlChoice.off,
    ImageControlChoice.low,
    ImageControlChoice.medium,
    ImageControlChoice.high,
  ],
  BleImageControlParameter.crossProcess => const [
    ImageControlChoice.basic,
    ImageControlChoice.magenta,
    ImageControlChoice.yellow,
  ],
  _ => null,
};

/// [parameter]'s [imageControlChoices] from [min] to the last one, or null
/// when it has none.
ImageControlRange? _choices(BleImageControlParameter parameter, {int min = 0}) {
  final choices = imageControlChoices(parameter);
  if (choices == null) return null;
  return ImageControlRange(
    ImageControlValueKind.choice,
    min,
    choices.length - 1,
  );
}

/// The values [parameter] takes, or null when they are not known well
/// enough to edit; such parameters keep the value the camera gave them.
///
/// Choices run over [imageControlChoices]; where the GR IIIx firmware's
/// settings start a choice at 1, so does the range
/// (research/protocol/image-control.md §4).
/// Steps are −4..+4 \[inferred\]: GR WORLD shows the wire value itself and
/// has no range table; −4..+4 is the GR IIIx firmware's vocabulary (`M4`
/// to `P4`) as a third-party settings dump reads it.
ImageControlRange? imageControlRange(BleImageControlParameter parameter) =>
    switch (parameter) {
      BleImageControlParameter.saturation ||
      BleImageControlParameter.hue ||
      BleImageControlParameter.key ||
      BleImageControlParameter.contrast ||
      BleImageControlParameter.contrastHigh ||
      BleImageControlParameter.contrastLow ||
      BleImageControlParameter.sharpness ||
      BleImageControlParameter.toningRetro ||
      BleImageControlParameter.shading ||
      BleImageControlParameter.clarity => _steps,
      // GR WORLD names 0 Off; that the camera takes only 1..3, as the GR
      // IIIx firmware's settings do, is \[inferred\].
      BleImageControlParameter.toningBleachBypass ||
      BleImageControlParameter.hdrStrength => _choices(parameter, min: 1),
      // The filter effect picks one of four custom filters whose R, G and
      // B values have an unknown range.
      BleImageControlParameter.filterEffect => null,
      // The rest are choices where GR WORLD names the values. The custom
      // filter values, the solarization type and the GR IVx's Palette
      // parameters have no names and unknown ranges.
      _ => _choices(parameter),
    };

const List<BleImageControlParameter> _filter = [
  BleImageControlParameter.filterEffect,
  BleImageControlParameter.filterEffectRedHigh,
  BleImageControlParameter.filterEffectRedLow,
  BleImageControlParameter.filterEffectGreenHigh,
  BleImageControlParameter.filterEffectGreenLow,
  BleImageControlParameter.filterEffectBlueHigh,
  BleImageControlParameter.filterEffectBlueLow,
];

const List<BleImageControlParameter> _grain = [
  BleImageControlParameter.grain,
  BleImageControlParameter.grainSize,
  BleImageControlParameter.grainStrength,
];

const List<BleImageControlParameter> _tone = [
  BleImageControlParameter.key,
  BleImageControlParameter.contrast,
  BleImageControlParameter.contrastHigh,
  BleImageControlParameter.contrastLow,
  BleImageControlParameter.sharpness,
];

const List<BleImageControlParameter> _colour = [
  BleImageControlParameter.saturation,
  BleImageControlParameter.hue,
  ..._tone,
];

const List<BleImageControlParameter> _monoBase = [
  ..._tone,
  BleImageControlParameter.toningMonotone,
];

/// The parameters the camera keeps for [base], in wire-id order: the GR IV
/// firmware 1.20 setting keys `StillImageControlNo0Param<Base><Param>` and
/// `AfterReleaseStillImageControlNo0Param<Base><Param>`, whose order
/// matches GR WORLD's parameter ids (research/protocol/image-control.md
/// §3). A base with the filter effect also carries its custom R, G and B
/// values. Empty for Palette, whose parameters are \[unknown\].
List<BleImageControlParameter> imageControlParameters(
  BleImageControlBase base,
) => switch (base) {
  BleImageControlBase.standard || BleImageControlBase.vivid => const [
    ..._colour,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
  ],
  BleImageControlBase.monotone || BleImageControlBase.highContrast => const [
    ..._monoBase,
    ..._filter,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
    ..._grain,
  ],
  BleImageControlBase.softMonotone => const [
    ..._monoBase,
    ..._filter,
    BleImageControlParameter.shading,
    ..._grain,
  ],
  BleImageControlBase.hardMonotone ||
  BleImageControlBase.standardMono ||
  BleImageControlBase.highContrastMono ||
  BleImageControlBase.grainy ||
  BleImageControlBase.solid => const [
    ..._monoBase,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
    ..._grain,
  ],
  BleImageControlBase.softMono || BleImageControlBase.pictorialist => const [
    ..._monoBase,
    BleImageControlParameter.shading,
    ..._grain,
  ],
  BleImageControlBase.positiveFilm ||
  BleImageControlBase.negativeFilm => const [
    ..._colour,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
    ..._grain,
  ],
  BleImageControlBase.bleachBypass => const [
    ..._colour,
    BleImageControlParameter.toningBleachBypass,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
  ],
  BleImageControlBase.retro => const [
    ..._colour,
    BleImageControlParameter.toningRetro,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
  ],
  BleImageControlBase.hdrTone => const [
    BleImageControlParameter.saturation,
    BleImageControlParameter.hue,
    BleImageControlParameter.toningHdr,
    BleImageControlParameter.hdrStrength,
  ],
  BleImageControlBase.cineYellow || BleImageControlBase.cineGreen => const [
    ..._colour,
    BleImageControlParameter.toningCinema,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
    ..._grain,
  ],
  BleImageControlBase.crossProcess => const [
    ..._colour,
    BleImageControlParameter.shading,
    BleImageControlParameter.clarity,
    BleImageControlParameter.crossProcess,
  ],
  BleImageControlBase.hdrMono => const [
    BleImageControlParameter.toningHdr,
    BleImageControlParameter.hdrStrength,
  ],
  BleImageControlBase.solarization => const [
    BleImageControlParameter.key,
    BleImageControlParameter.sharpness,
    BleImageControlParameter.toningMonotone,
    BleImageControlParameter.clarity,
    ..._grain,
    BleImageControlParameter.solarizationType,
  ],
  BleImageControlBase.pallet => const [],
};

const List<BleImageControlBase> _colourBases = [
  BleImageControlBase.standard,
  BleImageControlBase.vivid,
  BleImageControlBase.monotone,
  BleImageControlBase.softMonotone,
  BleImageControlBase.hardMonotone,
  BleImageControlBase.highContrast,
  BleImageControlBase.positiveFilm,
  BleImageControlBase.bleachBypass,
  BleImageControlBase.retro,
  BleImageControlBase.hdrTone,
  BleImageControlBase.negativeFilm,
  BleImageControlBase.cineYellow,
  BleImageControlBase.cineGreen,
  BleImageControlBase.crossProcess,
];

const List<BleImageControlBase> _monochromeBases = [
  BleImageControlBase.standardMono,
  BleImageControlBase.solid,
  BleImageControlBase.softMono,
  BleImageControlBase.highContrastMono,
  BleImageControlBase.grainy,
  BleImageControlBase.hdrMono,
  BleImageControlBase.solarization,
  BleImageControlBase.pictorialist,
];

/// The base images [model] offers: the GR IV Monochrome's monochrome
/// bases (its manual p.90, plus Solarized and Pictorialist in firmware
/// 1.10), every other body the colour bases of the GR IV manual p.94.
/// The GR III family and the GR IVx get the GR IV's list \[inferred\];
/// GR Lab cannot load looks into a GR III, and the GR IVx's Palette has
/// \[unknown\] parameters.
List<BleImageControlBase> imageControlBases(GrModel? model) =>
    model == GrModel.gr4Monochrome ? _monochromeBases : _colourBases;

int _initial(BleImageControlParameter p) => imageControlRange(p)?.initial ?? 0;

/// A look on [base] with every parameter the base has at its
/// [ImageControlRange.initial] value (0 where the range is unknown). The
/// header bytes (format version and byte 1) are copied from [template], a
/// blob the camera produced: GR WORLD never builds a blob itself, so which
/// header the camera expects of a new one is \[unknown\]
/// (research/protocol/image-control.md §1).
BleImageControlBlob newImageControl(
  BleImageControlBase base, {
  required BleImageControlBlob template,
}) => BleImageControlBlob(
  version: template.version,
  reserved: template.reserved,
  base: BleEnumValue.of(base),
  parameters: [
    for (final p in imageControlParameters(base))
      BleImageControlEntry(BleEnumValue.of(p), _initial(p)),
  ],
);

/// Reading and editing a look's parameters.
extension ImageControlEdits on BleImageControlBlob {
  /// The value of [parameter], or null when the look does not have it.
  int? valueOf(BleImageControlParameter parameter) {
    for (final e in parameters) {
      if (e.parameter.known == parameter) return e.value;
    }
    return null;
  }

  /// This look with [parameter] set to [value], in place when the look has
  /// it, else added at the end.
  BleImageControlBlob withValue(BleImageControlParameter parameter, int value) {
    final entry = BleImageControlEntry(BleEnumValue.of(parameter), value);
    final has = valueOf(parameter) != null;
    return _withParameters([
      for (final e in parameters)
        if (e.parameter.known == parameter) entry else e,
      if (!has) entry,
    ]);
  }

  /// This look on [base] instead: the parameters [base] has, in wire-id
  /// order, each keeping its value when this look has it and starting at
  /// its initial value when not. The header bytes and any bytes after the
  /// parameters stay. That the camera wants exactly its base's parameters
  /// is \[inferred\] from the firmware's per-base settings.
  BleImageControlBlob withBase(BleImageControlBase base) => BleImageControlBlob(
    version: version,
    reserved: reserved,
    base: BleEnumValue.of(base),
    parameters: [
      for (final p in imageControlParameters(base))
        BleImageControlEntry(BleEnumValue.of(p), valueOf(p) ?? _initial(p)),
    ],
    trailing: trailing,
  );

  /// Whether [other] is the same look: the same base image and the same
  /// value for every parameter, in any order. The header bytes are not
  /// compared, so a look still matches after the camera stored it in its
  /// own format version.
  bool sameLookAs(BleImageControlBlob other) {
    if (base.raw != other.base.raw) return false;
    if (parameters.length != other.parameters.length) return false;
    final values = {for (final e in parameters) e.parameter.raw: e.value};
    return other.parameters.every((e) => values[e.parameter.raw] == e.value);
  }

  BleImageControlBlob _withParameters(List<BleImageControlEntry> entries) =>
      BleImageControlBlob(
        version: version,
        reserved: reserved,
        base: base,
        parameters: entries,
        trailing: trailing,
      );
}
