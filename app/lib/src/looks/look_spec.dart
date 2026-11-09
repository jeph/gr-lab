import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// The tabs of the look editor (mock `b-look-edit`).
enum LookGroup { tone, colour, detail, effects }

/// The editor tab [parameter] is on; null for the custom filter's R, G
/// and B bytes, which GR WORLD never shows either.
LookGroup? groupOf(BleImageControlParameter parameter) => switch (parameter) {
  BleImageControlParameter.key ||
  BleImageControlParameter.contrast ||
  BleImageControlParameter.contrastHigh ||
  BleImageControlParameter.contrastLow ||
  BleImageControlParameter.shading ||
  BleImageControlParameter.whitePoint ||
  BleImageControlParameter.blackPoint => LookGroup.tone,
  BleImageControlParameter.saturation ||
  BleImageControlParameter.hue ||
  BleImageControlParameter.toningMonotone ||
  BleImageControlParameter.toningCinema ||
  BleImageControlParameter.toningBleachBypass ||
  BleImageControlParameter.toningRetro ||
  BleImageControlParameter.toningHdr ||
  BleImageControlParameter.crossProcess ||
  BleImageControlParameter.baseColor ||
  BleImageControlParameter.rgbToneHighlightsGm ||
  BleImageControlParameter.rgbToneHighlightsBa ||
  BleImageControlParameter.rgbToneMidtonesGm ||
  BleImageControlParameter.rgbToneMidtonesBa ||
  BleImageControlParameter.rgbToneShadowsGm ||
  BleImageControlParameter.rgbToneShadowsBa => LookGroup.colour,
  BleImageControlParameter.sharpness ||
  BleImageControlParameter.clarity => LookGroup.detail,
  BleImageControlParameter.filterEffect ||
  BleImageControlParameter.grain ||
  BleImageControlParameter.grainSize ||
  BleImageControlParameter.grainStrength ||
  BleImageControlParameter.hdrStrength ||
  BleImageControlParameter.solarizationType => LookGroup.effects,
  BleImageControlParameter.filterEffectRedHigh ||
  BleImageControlParameter.filterEffectRedLow ||
  BleImageControlParameter.filterEffectGreenHigh ||
  BleImageControlParameter.filterEffectGreenLow ||
  BleImageControlParameter.filterEffectBlueHigh ||
  BleImageControlParameter.filterEffectBlueLow => null,
};

/// Whether the editor shows [parameter] of [look]: Grain's size and
/// intensity only while grain is on, as in GR WORLD.
bool shownIn(BleImageControlBlob look, BleImageControlParameter parameter) {
  if (groupOf(parameter) == null) return false;
  return switch (parameter) {
    BleImageControlParameter.grainSize ||
    BleImageControlParameter.grainStrength =>
      (look.valueOf(BleImageControlParameter.grain) ?? 0) != 0,
    _ => true,
  };
}

String groupLabel(AppLocalizations l10n, LookGroup group) => switch (group) {
  LookGroup.tone => l10n.looksGroupTone,
  LookGroup.colour => l10n.looksGroupColour,
  LookGroup.detail => l10n.looksGroupDetail,
  LookGroup.effects => l10n.looksGroupEffects,
};

/// Whether [base] makes black-and-white pictures.
bool isMonoBase(BleImageControlBase base) => switch (base) {
  BleImageControlBase.monotone ||
  BleImageControlBase.softMonotone ||
  BleImageControlBase.hardMonotone ||
  BleImageControlBase.highContrast ||
  BleImageControlBase.standardMono ||
  BleImageControlBase.softMono ||
  BleImageControlBase.highContrastMono ||
  BleImageControlBase.grainy ||
  BleImageControlBase.solid ||
  BleImageControlBase.hdrMono ||
  BleImageControlBase.solarization ||
  BleImageControlBase.pictorialist => true,
  _ => false,
};

/// The base image's name as the camera's menu shows it.
String baseLabel(
  AppLocalizations l10n,
  BleEnumValue<BleImageControlBase> base,
) => switch (base.known) {
  null => l10n.looksBaseUnknown(base.raw),
  BleImageControlBase.standard => l10n.looksBaseStandard,
  BleImageControlBase.vivid => l10n.looksBaseVivid,
  BleImageControlBase.monotone => l10n.looksBaseMonotone,
  BleImageControlBase.softMonotone => l10n.looksBaseSoftMonotone,
  BleImageControlBase.hardMonotone => l10n.looksBaseHardMonotone,
  BleImageControlBase.highContrast => l10n.looksBaseHighContrastBw,
  BleImageControlBase.positiveFilm => l10n.looksBasePositiveFilm,
  BleImageControlBase.bleachBypass => l10n.looksBaseBleachBypass,
  BleImageControlBase.retro => l10n.looksBaseRetro,
  BleImageControlBase.hdrTone => l10n.looksBaseHdrTone,
  BleImageControlBase.negativeFilm => l10n.looksBaseNegativeFilm,
  BleImageControlBase.cineYellow => l10n.looksBaseCinemaYellow,
  BleImageControlBase.cineGreen => l10n.looksBaseCinemaGreen,
  BleImageControlBase.crossProcess => l10n.looksBaseCrossProcessing,
  BleImageControlBase.standardMono => l10n.looksBaseMonoStandard,
  BleImageControlBase.softMono => l10n.looksBaseMonoSoft,
  BleImageControlBase.highContrastMono => l10n.looksBaseMonoHighContrast,
  BleImageControlBase.grainy => l10n.looksBaseGrainy,
  BleImageControlBase.solid => l10n.looksBaseSolid,
  BleImageControlBase.hdrMono => l10n.looksBaseMonoHdrTone,
  BleImageControlBase.pallet => l10n.looksBasePalette,
  BleImageControlBase.solarization => l10n.looksBaseSolarized,
  BleImageControlBase.pictorialist => l10n.looksBasePictorialist,
};

String parameterLabel(
  AppLocalizations l10n,
  BleImageControlParameter parameter,
) => switch (parameter) {
  BleImageControlParameter.saturation => l10n.looksParamSaturation,
  BleImageControlParameter.hue => l10n.looksParamHue,
  BleImageControlParameter.key => l10n.looksParamKey,
  BleImageControlParameter.contrast => l10n.looksParamContrast,
  BleImageControlParameter.contrastHigh => l10n.looksParamContrastHighlight,
  BleImageControlParameter.contrastLow => l10n.looksParamContrastShadow,
  BleImageControlParameter.sharpness => l10n.looksParamSharpness,
  BleImageControlParameter.toningMonotone ||
  BleImageControlParameter.toningCinema ||
  BleImageControlParameter.toningBleachBypass ||
  BleImageControlParameter.toningRetro ||
  BleImageControlParameter.toningHdr => l10n.looksParamToning,
  BleImageControlParameter.filterEffect => l10n.looksParamFilterEffect,
  BleImageControlParameter.filterEffectRedHigh ||
  BleImageControlParameter.filterEffectRedLow => l10n.looksParamFilterRed,
  BleImageControlParameter.filterEffectGreenHigh ||
  BleImageControlParameter.filterEffectGreenLow => l10n.looksParamFilterGreen,
  BleImageControlParameter.filterEffectBlueHigh ||
  BleImageControlParameter.filterEffectBlueLow => l10n.looksParamFilterBlue,
  BleImageControlParameter.shading => l10n.looksParamShading,
  BleImageControlParameter.clarity => l10n.looksParamClarity,
  BleImageControlParameter.grain => l10n.looksParamGrain,
  BleImageControlParameter.grainSize => l10n.looksParamGrainSize,
  BleImageControlParameter.grainStrength => l10n.looksParamGrainStrength,
  BleImageControlParameter.hdrStrength => l10n.looksParamHdrLevel,
  BleImageControlParameter.crossProcess => l10n.looksParamColorTone,
  BleImageControlParameter.baseColor => l10n.looksParamBaseColor,
  BleImageControlParameter.whitePoint => l10n.looksParamWhitePoint,
  BleImageControlParameter.blackPoint => l10n.looksParamBlackPoint,
  BleImageControlParameter.rgbToneHighlightsGm ||
  BleImageControlParameter.rgbToneHighlightsBa =>
    l10n.looksParamRgbToneHighlights,
  BleImageControlParameter.rgbToneMidtonesGm ||
  BleImageControlParameter.rgbToneMidtonesBa => l10n.looksParamRgbToneMidtones,
  BleImageControlParameter.rgbToneShadowsGm ||
  BleImageControlParameter.rgbToneShadowsBa => l10n.looksParamRgbToneShadows,
  BleImageControlParameter.solarizationType => l10n.looksParamSolarizationType,
};

/// [value] of [parameter] as the camera shows it: a choice's name, or a
/// signed number (`+2`, `-1`, `0`). Values past a choice's last name read
/// as the number.
String valueLabel(
  AppLocalizations l10n,
  BleImageControlParameter parameter,
  int value,
) {
  final choices = _choiceLabels(l10n, parameter);
  if (choices != null && value >= 0 && value < choices.length) {
    return choices[value];
  }
  final number = NumberFormat.decimalPattern(l10n.localeName).format(value);
  return value > 0 ? '+$number' : number;
}

/// Names of [parameter]'s values by wire value (GR WORLD's formatter,
/// research/protocol/image-control.md §4); null for a number.
List<String>? _choiceLabels(
  AppLocalizations l10n,
  BleImageControlParameter parameter,
) {
  final lowMediumHigh = [
    l10n.looksValueLow,
    l10n.looksValueMedium,
    l10n.looksValueHigh,
  ];
  return switch (parameter) {
    BleImageControlParameter.toningMonotone => [
      l10n.looksValueOff,
      l10n.looksValueSepia,
      l10n.looksValueRed,
      l10n.looksValueGreen,
      l10n.looksValueBlue,
      l10n.looksValuePurple,
    ],
    BleImageControlParameter.toningCinema ||
    BleImageControlParameter.grainStrength => lowMediumHigh,
    BleImageControlParameter.toningBleachBypass => [
      l10n.looksValueOff,
      l10n.looksValueNormal,
      l10n.looksValueCool,
      l10n.looksValueWarm,
    ],
    BleImageControlParameter.toningHdr => [
      l10n.looksValueOff,
      l10n.looksValueBlackAndWhite,
      l10n.looksValueSepia,
    ],
    BleImageControlParameter.filterEffect => [
      l10n.looksValueOff,
      for (var n = 1; n <= 4; n++) l10n.looksValueCustomFilter(n),
    ],
    BleImageControlParameter.grain => [l10n.looksValueOff, l10n.looksValueOn],
    BleImageControlParameter.grainSize => [
      l10n.looksValueSmall,
      l10n.looksValueMedium,
      l10n.looksValueLarge,
    ],
    BleImageControlParameter.hdrStrength => [
      l10n.looksValueOff,
      ...lowMediumHigh,
    ],
    BleImageControlParameter.crossProcess => [
      l10n.looksValueBasic,
      l10n.looksValueMagenta,
      l10n.looksValueYellow,
    ],
    _ => null,
  };
}

/// One line about [look] (mock `.lookcard .d`): the base image, then each
/// adjustment that is not neutral, as `Contrast +1`. [withBase] false
/// leaves the base out.
String lookSummary(
  AppLocalizations l10n,
  BleImageControlBlob look, {
  bool withBase = true,
}) {
  final parts = [
    if (withBase) baseLabel(l10n, look.base),
    for (final e in look.parameters)
      if (e.parameter.known case final p?)
        if (groupOf(p) != null &&
            shownIn(look, p) &&
            e.value != (imageControlRange(p)?.initial ?? 0))
          l10n.looksSummaryValue(
            parameterLabel(l10n, p),
            valueLabel(l10n, p, e.value),
          ),
  ];
  return parts.join(' · ');
}

/// The colours of a look's swatch when it has no photo: a gradient that
/// hints at the base image.
List<Color> swatchColors(BleImageControlBase base) => switch (base) {
  BleImageControlBase.vivid => const [Color(0xFFE2563B), Color(0xFF2F6FD6)],
  BleImageControlBase.positiveFilm => const [
    Color(0xFFE7A24A),
    Color(0xFF2E7D8C),
  ],
  BleImageControlBase.negativeFilm => const [
    Color(0xFFD9B48A),
    Color(0xFF6E8F7A),
  ],
  BleImageControlBase.bleachBypass => const [
    Color(0xFF8C9296),
    Color(0xFF3F4A4F),
  ],
  BleImageControlBase.retro => const [Color(0xFFC9A46A), Color(0xFF7A5A3A)],
  BleImageControlBase.hdrTone => const [Color(0xFF6A88A8), Color(0xFF3C3A4A)],
  BleImageControlBase.cineYellow => const [
    Color(0xFFD8B04A),
    Color(0xFF3A5A5A),
  ],
  BleImageControlBase.cineGreen => const [Color(0xFF6FA88A), Color(0xFF2A3F4A)],
  BleImageControlBase.crossProcess => const [
    Color(0xFFCF6FA0),
    Color(0xFFD8D06A),
  ],
  BleImageControlBase.pallet => const [Color(0xFFB08AD0), Color(0xFF4AA0B0)],
  BleImageControlBase.standard => const [Color(0xFF8AA0B8), Color(0xFF4A5A6A)],
  _ when isMonoBase(base) => const [Color(0xFFBDBDBD), Color(0xFF2A2A2A)],
  _ => const [Color(0xFF8AA0B8), Color(0xFF4A5A6A)],
};
