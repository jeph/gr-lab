import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// The tabs of the look editor (mock `b-look-edit`).
enum LookGroup { tone, colour, detail, effects }

/// The editor tab [parameter] is on; null for the custom filter's R, G
/// and B bytes, which GR WORLD never shows either.
LookGroup? groupOf(LookParameter parameter) => switch (parameter) {
  LookParameter.key ||
  LookParameter.contrast ||
  LookParameter.contrastHigh ||
  LookParameter.contrastLow ||
  LookParameter.shading ||
  LookParameter.whitePoint ||
  LookParameter.blackPoint => LookGroup.tone,
  LookParameter.saturation ||
  LookParameter.hue ||
  LookParameter.toningMonotone ||
  LookParameter.toningCinema ||
  LookParameter.toningBleachBypass ||
  LookParameter.toningRetro ||
  LookParameter.toningHdr ||
  LookParameter.crossProcess ||
  LookParameter.baseColor ||
  LookParameter.rgbToneHighlightsGm ||
  LookParameter.rgbToneHighlightsBa ||
  LookParameter.rgbToneMidtonesGm ||
  LookParameter.rgbToneMidtonesBa ||
  LookParameter.rgbToneShadowsGm ||
  LookParameter.rgbToneShadowsBa => LookGroup.colour,
  LookParameter.sharpness || LookParameter.clarity => LookGroup.detail,
  LookParameter.filterEffect ||
  LookParameter.grain ||
  LookParameter.grainSize ||
  LookParameter.grainStrength ||
  LookParameter.hdrStrength ||
  LookParameter.solarizationType => LookGroup.effects,
  LookParameter.filterEffectRedHigh ||
  LookParameter.filterEffectRedLow ||
  LookParameter.filterEffectGreenHigh ||
  LookParameter.filterEffectGreenLow ||
  LookParameter.filterEffectBlueHigh ||
  LookParameter.filterEffectBlueLow => null,
};

/// Whether the editor shows [parameter] of [look]: Grain's size and
/// intensity only while grain is on, as in GR WORLD.
bool shownIn(Look look, LookParameter parameter) {
  if (groupOf(parameter) == null) return false;
  return switch (parameter) {
    LookParameter.grainSize || LookParameter.grainStrength =>
      (look.valueOf(LookParameter.grain) ?? 0) != 0,
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
bool isMonoBase(LookBase base) => switch (base) {
  LookBase.monotone ||
  LookBase.softMonotone ||
  LookBase.hardMonotone ||
  LookBase.highContrast ||
  LookBase.standardMono ||
  LookBase.softMono ||
  LookBase.highContrastMono ||
  LookBase.grainy ||
  LookBase.solid ||
  LookBase.hdrMono ||
  LookBase.solarization ||
  LookBase.pictorialist => true,
  _ => false,
};

/// The name of [look]'s base image as the camera's menu shows it, or its
/// number when GR Lab does not know it.
String lookBaseLabel(AppLocalizations l10n, Look look) => switch (look.base) {
  final base? => baseLabel(l10n, base),
  null => l10n.looksBaseUnknown(look.unknownBaseNumber!),
};

/// The base image's name as the camera's menu shows it.
String baseLabel(AppLocalizations l10n, LookBase base) => switch (base) {
  LookBase.standard => l10n.looksBaseStandard,
  LookBase.vivid => l10n.looksBaseVivid,
  LookBase.monotone => l10n.looksBaseMonotone,
  LookBase.softMonotone => l10n.looksBaseSoftMonotone,
  LookBase.hardMonotone => l10n.looksBaseHardMonotone,
  LookBase.highContrast => l10n.looksBaseHighContrastBw,
  LookBase.positiveFilm => l10n.looksBasePositiveFilm,
  LookBase.bleachBypass => l10n.looksBaseBleachBypass,
  LookBase.retro => l10n.looksBaseRetro,
  LookBase.hdrTone => l10n.looksBaseHdrTone,
  LookBase.negativeFilm => l10n.looksBaseNegativeFilm,
  LookBase.cineYellow => l10n.looksBaseCinemaYellow,
  LookBase.cineGreen => l10n.looksBaseCinemaGreen,
  LookBase.crossProcess => l10n.looksBaseCrossProcessing,
  LookBase.standardMono => l10n.looksBaseMonoStandard,
  LookBase.softMono => l10n.looksBaseMonoSoft,
  LookBase.highContrastMono => l10n.looksBaseMonoHighContrast,
  LookBase.grainy => l10n.looksBaseGrainy,
  LookBase.solid => l10n.looksBaseSolid,
  LookBase.hdrMono => l10n.looksBaseMonoHdrTone,
  LookBase.palette => l10n.looksBasePalette,
  LookBase.solarization => l10n.looksBaseSolarized,
  LookBase.pictorialist => l10n.looksBasePictorialist,
};

String parameterLabel(AppLocalizations l10n, LookParameter parameter) =>
    switch (parameter) {
      LookParameter.saturation => l10n.looksParamSaturation,
      LookParameter.hue => l10n.looksParamHue,
      LookParameter.key => l10n.looksParamKey,
      LookParameter.contrast => l10n.looksParamContrast,
      LookParameter.contrastHigh => l10n.looksParamContrastHighlight,
      LookParameter.contrastLow => l10n.looksParamContrastShadow,
      LookParameter.sharpness => l10n.looksParamSharpness,
      LookParameter.toningMonotone ||
      LookParameter.toningCinema ||
      LookParameter.toningBleachBypass ||
      LookParameter.toningRetro ||
      LookParameter.toningHdr => l10n.looksParamToning,
      LookParameter.filterEffect => l10n.looksParamFilterEffect,
      LookParameter.filterEffectRedHigh ||
      LookParameter.filterEffectRedLow => l10n.looksParamFilterRed,
      LookParameter.filterEffectGreenHigh ||
      LookParameter.filterEffectGreenLow => l10n.looksParamFilterGreen,
      LookParameter.filterEffectBlueHigh ||
      LookParameter.filterEffectBlueLow => l10n.looksParamFilterBlue,
      LookParameter.shading => l10n.looksParamShading,
      LookParameter.clarity => l10n.looksParamClarity,
      LookParameter.grain => l10n.looksParamGrain,
      LookParameter.grainSize => l10n.looksParamGrainSize,
      LookParameter.grainStrength => l10n.looksParamGrainStrength,
      LookParameter.hdrStrength => l10n.looksParamHdrLevel,
      LookParameter.crossProcess => l10n.looksParamColorTone,
      LookParameter.baseColor => l10n.looksParamBaseColor,
      LookParameter.whitePoint => l10n.looksParamWhitePoint,
      LookParameter.blackPoint => l10n.looksParamBlackPoint,
      LookParameter.rgbToneHighlightsGm ||
      LookParameter.rgbToneHighlightsBa => l10n.looksParamRgbToneHighlights,
      LookParameter.rgbToneMidtonesGm ||
      LookParameter.rgbToneMidtonesBa => l10n.looksParamRgbToneMidtones,
      LookParameter.rgbToneShadowsGm ||
      LookParameter.rgbToneShadowsBa => l10n.looksParamRgbToneShadows,
      LookParameter.solarizationType => l10n.looksParamSolarizationType,
    };

/// [value] of [parameter] as the camera shows it: a choice's name, or a
/// signed number (`+2`, `-1`, `0`). Values past a choice's last name read
/// as the number.
String valueLabel(AppLocalizations l10n, LookParameter parameter, int value) {
  final choices = lookChoices(parameter);
  if (choices != null && value >= 0 && value < choices.length) {
    return _choiceLabel(l10n, choices[value]);
  }
  final number = NumberFormat.decimalPattern(l10n.localeName).format(value);
  return value > 0 ? '+$number' : number;
}

String _choiceLabel(AppLocalizations l10n, LookChoice choice) =>
    switch (choice) {
      LookChoice.off => l10n.looksValueOff,
      LookChoice.sepia => l10n.looksValueSepia,
      LookChoice.red => l10n.looksValueRed,
      LookChoice.green => l10n.looksValueGreen,
      LookChoice.blue => l10n.looksValueBlue,
      LookChoice.purple => l10n.looksValuePurple,
      LookChoice.low => l10n.looksValueLow,
      LookChoice.medium => l10n.looksValueMedium,
      LookChoice.high => l10n.looksValueHigh,
      LookChoice.normal => l10n.looksValueNormal,
      LookChoice.cool => l10n.looksValueCool,
      LookChoice.warm => l10n.looksValueWarm,
      LookChoice.blackAndWhite => l10n.looksValueBlackAndWhite,
      LookChoice.customFilter1 => l10n.looksValueCustomFilter(1),
      LookChoice.customFilter2 => l10n.looksValueCustomFilter(2),
      LookChoice.customFilter3 => l10n.looksValueCustomFilter(3),
      LookChoice.customFilter4 => l10n.looksValueCustomFilter(4),
      LookChoice.on => l10n.looksValueOn,
      LookChoice.small => l10n.looksValueSmall,
      LookChoice.large => l10n.looksValueLarge,
      LookChoice.basic => l10n.looksValueBasic,
      LookChoice.magenta => l10n.looksValueMagenta,
      LookChoice.yellow => l10n.looksValueYellow,
    };

/// One line about [look] (mock `.lookcard .d`): the base image, then each
/// adjustment that is not neutral, as `Contrast +1`. [withBase] false
/// leaves the base out.
String lookSummary(AppLocalizations l10n, Look look, {bool withBase = true}) {
  final parts = [
    if (withBase) lookBaseLabel(l10n, look),
    for (final MapEntry(key: p, :value) in look.values.entries)
      if (groupOf(p) != null &&
          shownIn(look, p) &&
          value != (lookRange(p)?.initial ?? 0))
        l10n.looksSummaryValue(
          parameterLabel(l10n, p),
          valueLabel(l10n, p, value),
        ),
  ];
  return parts.join(' · ');
}

/// The colours of a look's swatch when it has no photo: a gradient that
/// hints at the base image.
List<Color> swatchColors(LookBase base) => switch (base) {
  LookBase.vivid => const [Color(0xFFE2563B), Color(0xFF2F6FD6)],
  LookBase.positiveFilm => const [Color(0xFFE7A24A), Color(0xFF2E7D8C)],
  LookBase.negativeFilm => const [Color(0xFFD9B48A), Color(0xFF6E8F7A)],
  LookBase.bleachBypass => const [Color(0xFF8C9296), Color(0xFF3F4A4F)],
  LookBase.retro => const [Color(0xFFC9A46A), Color(0xFF7A5A3A)],
  LookBase.hdrTone => const [Color(0xFF6A88A8), Color(0xFF3C3A4A)],
  LookBase.cineYellow => const [Color(0xFFD8B04A), Color(0xFF3A5A5A)],
  LookBase.cineGreen => const [Color(0xFF6FA88A), Color(0xFF2A3F4A)],
  LookBase.crossProcess => const [Color(0xFFCF6FA0), Color(0xFFD8D06A)],
  LookBase.palette => const [Color(0xFFB08AD0), Color(0xFF4AA0B0)],
  LookBase.standard => const [Color(0xFF8AA0B8), Color(0xFF4A5A6A)],
  _ when isMonoBase(base) => const [Color(0xFFBDBDBD), Color(0xFF2A2A2A)],
  _ => const [Color(0xFF8AA0B8), Color(0xFF4A5A6A)],
};
