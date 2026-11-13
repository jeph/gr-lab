import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/looks/look.dart';

/// How a parameter's wire values read.
enum LookValueKind {
  /// A signed adjustment the camera shows as the number itself (`-4`..`+4`).
  steps,

  /// An index into a list of choices (Off, Sepia, Red, …).
  choice,
}

/// The values the editor offers for a parameter: [min] to [max] in steps
/// of 1, without those in [refused].
@immutable
final class LookRange {
  /// A range of [kind] from [min] to [max] without [refused].
  const new(this.kind, this.min, this.max, {this.refused = const {}});

  /// How the values read.
  final LookValueKind kind;

  /// The lowest value, unless it is [refused].
  final int min;

  /// The highest value.
  final int max;

  /// Values between [min] and [max] the camera refuses in a blob (found
  /// in its firmware). A value outside [min] to [max] is only one the
  /// editor does not offer: the camera may take it.
  final Set<int> refused;

  /// Every value of the range, lowest first.
  List<int> get values => [
    for (var v = min; v <= max; v++)
      if (!refused.contains(v)) v,
  ];

  /// The value a parameter gets when a look gains it: 0, as in GR WORLD's
  /// fallback look, which holds 0 for every parameter (code 0x82cd88), or
  /// the lowest of [values] when 0 is not one of them. The camera's own
  /// defaults are \[unknown\] for most choices.
  int get initial => values.contains(0) ? 0 : values.first;
}

const _steps = LookRange(LookValueKind.steps, -4, 4);

/// A named value of a choice parameter, as GR WORLD's value formatter
/// names it (research/protocol/image-control.md §4).
enum LookChoice {
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

  /// Type 1.
  type1,

  /// Type 2.
  type2,

  /// Type 3.
  type3,
}

/// The named values of [parameter], indexed by wire value, or null when
/// the camera shows its value as a number; a wire value that is none of
/// the parameter's has no name. These are the cases of GR WORLD's value
/// formatter (code 0x95abc8–0x95b7f8, research/protocol/image-control.md
/// §4), and for the Solarization Type, which GR WORLD does not name, the
/// camera's own names.
List<LookChoice?>? lookChoices(LookParameter parameter) => switch (parameter) {
  LookParameter.toningMonotone => const [
    LookChoice.off,
    LookChoice.sepia,
    LookChoice.red,
    LookChoice.green,
    LookChoice.blue,
    LookChoice.purple,
  ],
  LookParameter.toningCinema || LookParameter.grainStrength => const [
    LookChoice.low,
    LookChoice.medium,
    LookChoice.high,
  ],
  LookParameter.toningBleachBypass => const [
    LookChoice.off,
    LookChoice.normal,
    LookChoice.cool,
    LookChoice.warm,
  ],
  LookParameter.toningHdr => const [
    LookChoice.off,
    LookChoice.blackAndWhite,
    LookChoice.sepia,
  ],
  // GR WORLD tells only 0 (Off) from anything else (On); that 1–4 select
  // custom filters 1–4 is \[inferred\] from the GR IIIx firmware.
  LookParameter.filterEffect => const [
    LookChoice.off,
    LookChoice.customFilter1,
    LookChoice.customFilter2,
    LookChoice.customFilter3,
    LookChoice.customFilter4,
  ],
  // That On is 1 is \[inferred\].
  LookParameter.grain => const [LookChoice.off, LookChoice.on],
  LookParameter.grainSize => const [
    LookChoice.small,
    LookChoice.medium,
    LookChoice.large,
  ],
  LookParameter.hdrStrength => const [
    LookChoice.off,
    LookChoice.low,
    LookChoice.medium,
    LookChoice.high,
  ],
  LookParameter.crossProcess => const [
    LookChoice.basic,
    LookChoice.magenta,
    LookChoice.yellow,
  ],
  // The camera's menu names them Type 1 to Type 3 (Ricoh's notes on GR IV
  // Monochrome firmware 1.10) and a blob holds 1..3 (found in the GR IV
  // 1.20 firmware's parser; image-control.md §4).
  LookParameter.solarizationType => const [
    null,
    LookChoice.type1,
    LookChoice.type2,
    LookChoice.type3,
  ],
  _ => null,
};

/// [parameter]'s [lookChoices] from [min] to the last one without
/// [refused], or null when it has none.
LookRange? _choices(
  LookParameter parameter, {
  int min = 0,
  Set<int> refused = const {},
}) {
  final choices = lookChoices(parameter);
  if (choices == null) return null;
  return LookRange(
    LookValueKind.choice,
    min,
    choices.length - 1,
    refused: refused,
  );
}

/// The values [parameter] takes on [base], or null when they are not
/// known well enough to edit; such parameters keep the value the camera
/// gave them. A [base] GR Photo does not know (null) gets the values the
/// parameter has on most bases.
///
/// Choices run over [lookChoices]; where the GR IIIx firmware's
/// settings start a choice at 1, so does the range
/// (research/protocol/image-control.md §4).
/// Steps are −4..+4 \[inferred\]: GR WORLD shows the wire value itself and
/// has no range table; −4..+4 is the GR IIIx firmware's vocabulary (`M4`
/// to `P4`) as a third-party settings dump reads it.
LookRange? lookRange(LookParameter parameter, LookBase? base) =>
    switch (parameter) {
      LookParameter.saturation ||
      LookParameter.hue ||
      LookParameter.key ||
      LookParameter.contrast ||
      LookParameter.contrastHigh ||
      LookParameter.contrastLow ||
      LookParameter.sharpness ||
      LookParameter.toningRetro ||
      LookParameter.shading ||
      LookParameter.clarity => _steps,
      // GR WORLD names 0 Off; that the camera takes only 1..3, as the GR
      // IIIx firmware's settings do, is \[inferred\].
      LookParameter.toningBleachBypass ||
      LookParameter.hdrStrength => _choices(parameter, min: 1),
      // The Monochrome's HDR Tone has no Black & White toning: the camera
      // refuses 1 in a blob on that base (found in the GR IV 1.20 firmware's
      // parser; image-control.md §4).
      LookParameter.toningHdr when base == LookBase.hdrMono => _choices(
        parameter,
        refused: const {1},
      ),
      // The camera refuses 0 (as above), and Type 1 is its default (Ricoh's
      // notes on GR IV Monochrome firmware 1.10).
      LookParameter.solarizationType => _choices(parameter, refused: const {0}),
      // The filter effect picks one of four custom filters whose R, G and
      // B values have an unknown range.
      LookParameter.filterEffect => null,
      // The rest are choices where GR WORLD names the values. The custom
      // filter values and the GR IVx's Palette parameters have no names and
      // unknown ranges.
      _ => _choices(parameter),
    };

const List<LookParameter> _filter = [
  LookParameter.filterEffect,
  LookParameter.filterEffectRedHigh,
  LookParameter.filterEffectRedLow,
  LookParameter.filterEffectGreenHigh,
  LookParameter.filterEffectGreenLow,
  LookParameter.filterEffectBlueHigh,
  LookParameter.filterEffectBlueLow,
];

const List<LookParameter> _grain = [
  LookParameter.grain,
  LookParameter.grainSize,
  LookParameter.grainStrength,
];

const List<LookParameter> _tone = [
  LookParameter.key,
  LookParameter.contrast,
  LookParameter.contrastHigh,
  LookParameter.contrastLow,
  LookParameter.sharpness,
];

const List<LookParameter> _colour = [
  LookParameter.saturation,
  LookParameter.hue,
  ..._tone,
];

const List<LookParameter> _monoBase = [..._tone, LookParameter.toningMonotone];

/// The parameters the camera keeps for [base], in wire-id order: the GR IV
/// firmware 1.20 setting keys `StillImageControlNo0Param<Base><Param>` and
/// `AfterReleaseStillImageControlNo0Param<Base><Param>`, whose order
/// matches GR WORLD's parameter ids (research/protocol/image-control.md
/// §3). A base with the filter effect also carries its custom R, G and B
/// values. Empty for Palette, whose parameters are \[unknown\].
List<LookParameter> lookParameters(LookBase base) => switch (base) {
  LookBase.standard || LookBase.vivid => const [
    ..._colour,
    LookParameter.shading,
    LookParameter.clarity,
  ],
  LookBase.monotone || LookBase.highContrast => const [
    ..._monoBase,
    ..._filter,
    LookParameter.shading,
    LookParameter.clarity,
    ..._grain,
  ],
  LookBase.softMonotone => const [
    ..._monoBase,
    ..._filter,
    LookParameter.shading,
    ..._grain,
  ],
  LookBase.hardMonotone ||
  LookBase.standardMono ||
  LookBase.highContrastMono ||
  LookBase.grainy ||
  LookBase.solid => const [
    ..._monoBase,
    LookParameter.shading,
    LookParameter.clarity,
    ..._grain,
  ],
  LookBase.softMono || LookBase.pictorialist => const [
    ..._monoBase,
    LookParameter.shading,
    ..._grain,
  ],
  LookBase.positiveFilm || LookBase.negativeFilm => const [
    ..._colour,
    LookParameter.shading,
    LookParameter.clarity,
    ..._grain,
  ],
  LookBase.bleachBypass => const [
    ..._colour,
    LookParameter.toningBleachBypass,
    LookParameter.shading,
    LookParameter.clarity,
  ],
  LookBase.retro => const [
    ..._colour,
    LookParameter.toningRetro,
    LookParameter.shading,
    LookParameter.clarity,
  ],
  LookBase.hdrTone => const [
    LookParameter.saturation,
    LookParameter.hue,
    LookParameter.toningHdr,
    LookParameter.hdrStrength,
  ],
  LookBase.cineYellow || LookBase.cineGreen => const [
    ..._colour,
    LookParameter.toningCinema,
    LookParameter.shading,
    LookParameter.clarity,
    ..._grain,
  ],
  LookBase.crossProcess => const [
    ..._colour,
    LookParameter.shading,
    LookParameter.clarity,
    LookParameter.crossProcess,
  ],
  LookBase.hdrMono => const [
    LookParameter.toningHdr,
    LookParameter.hdrStrength,
  ],
  LookBase.solarization => const [
    LookParameter.key,
    LookParameter.sharpness,
    LookParameter.toningMonotone,
    LookParameter.clarity,
    ..._grain,
    LookParameter.solarizationType,
  ],
  LookBase.palette => const [],
};

const List<LookBase> _colourBases = [
  LookBase.standard,
  LookBase.vivid,
  LookBase.monotone,
  LookBase.softMonotone,
  LookBase.hardMonotone,
  LookBase.highContrast,
  LookBase.positiveFilm,
  LookBase.bleachBypass,
  LookBase.retro,
  LookBase.hdrTone,
  LookBase.negativeFilm,
  LookBase.cineYellow,
  LookBase.cineGreen,
  LookBase.crossProcess,
];

const List<LookBase> _monochromeBases = [
  LookBase.standardMono,
  LookBase.solid,
  LookBase.softMono,
  LookBase.highContrastMono,
  LookBase.grainy,
  LookBase.hdrMono,
  LookBase.solarization,
];

/// The base images [camera] offers, split by body as GR WORLD splits them
/// (table 0x82ca84, `findSupportedByCameraType` 0xda1db4, observed in GR
/// WORLD 2.0.0's code; research/protocol/image-control.md §3): a camera
/// with [CameraFeature.monochromeLooks] (the GR IV Monochrome) its
/// monochrome bases (0x11–0x16, its manual p.90) and Solarized, every
/// other camera the 14 colour bases. GR WORLD gives Pictorialist to the GR
/// IVx Monochrome only, a body GR Photo does not know. The colour list is the
/// GR IV manual's (p.94), and a GR IV HDF on firmware 1.20 offered exactly
/// it in its `/v1/props` effectList (observed 2026-11-09). GR WORLD adds
/// Palette for the GR IVx; it is left out here because its parameters are
/// \[unknown\]. Cameras without [CameraFeature.lookSlots] have no slots to
/// load into, so GR Photo edits looks for them only away from a camera
/// ([lookBasesWith]).
List<LookBase> lookBases(CameraBody camera) =>
    camera.supports(CameraFeature.monochromeLooks)
    ? _monochromeBases
    : _colourBases;

/// The base images a look on [base] is edited among away from a camera:
/// the list of the bodies that offer [base] ([lookBases]), the monochrome
/// one for a monochrome base and the colour one otherwise, so an edit
/// never moves a look off the bodies it was loadable into \[design\]. A
/// base on neither list, or none, gets the colour list.
List<LookBase> lookBasesWith(LookBase? base) =>
    _monochromeBases.contains(base) ? _monochromeBases : _colourBases;
