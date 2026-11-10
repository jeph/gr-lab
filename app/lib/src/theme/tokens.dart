import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A base, three raised surfaces, hairlines, three text levels and one
/// accent, for a dark or a light interface ([brightness]). The dark colours
/// come from the mock-ups (`design/mockups/index.html` in the local research
/// workspace, `../gr`). The light theme is a white page: its cards are white
/// too, set off by their hairlines, its greys lean as slightly blue as the
/// dark surfaces do, and its accent and status colours are deep enough to
/// read on white. [darkroom], [paper] and [cyanotype] tint every level
/// (`design/mockups/themes.html`); their text, accent and status colours
/// contrast with their surfaces about as much as those of [dark] and
/// [light] do.
@immutable
final class GrColors extends ThemeExtension<GrColors> {
  const new({
    required this.brightness,
    required this.bg,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.s4,
    required this.line,
    required this.line2,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.accent,
    required this.accentInk,
    required this.ok,
    required this.danger,
    required this.invBg,
    required this.invFg,
    required this.invFg2,
    required this.inv2,
    required this.float,
    required this.shadow,
    required this.dim,
    this.switchThumb = const Color(0xFFFFFFFF),
  });

  static const dark = GrColors(
    brightness: Brightness.dark,
    bg: Color(0xFF0A0A0B),
    s1: Color(0xFF121214),
    s2: Color(0xFF1A1A1D),
    s3: Color(0xFF242428),
    s4: Color(0xFF2E2E33),
    line: Color(0x12FFFFFF),
    line2: Color(0x1FFFFFFF),
    t1: Color(0xFFF3F1EC),
    t2: Color(0xFFA8A6A0),
    t3: Color(0xFF6B6A66),
    accent: Color(0xFF6EA8FF),
    accentInk: Color(0xFF06142E),
    ok: Color(0xFF5BD08B),
    danger: Color(0xFFFF5A4E),
    invBg: Color(0xFFF3F1EC),
    invFg: Color(0xFF0B0B0C),
    invFg2: Color(0xFF55534E),
    inv2: Color(0xFFE2E0DA),
    float: Color(0xEB242428),
    shadow: Color(0x73000000),
    dim: Color(0x8C000000),
  );

  static const light = GrColors(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    s1: Color(0xFFFFFFFF),
    s2: Color(0xFFF3F3F5),
    s3: Color(0xFFE9E9EC),
    s4: Color(0xFFD6D6DB),
    line: Color(0x14000000),
    line2: Color(0x1F000000),
    t1: Color(0xFF121214),
    t2: Color(0xFF5C5C63),
    t3: Color(0xFF8B8B93),
    accent: Color(0xFF1B50CF),
    accentInk: Color(0xFFFFFFFF),
    ok: Color(0xFF17864A),
    danger: Color(0xFFD7372B),
    invBg: Color(0xFF121214),
    invFg: Color(0xFFFFFFFF),
    invFg2: Color(0xFF9A9AA1),
    inv2: Color(0xFF2A2A2E),
    float: Color(0xEBFFFFFF),
    shadow: Color(0x1F000000),
    dim: Color(0x4D000000),
  );

  /// A darkroom under its safelight: warm black with a red accent. Danger
  /// is a rose red, so it differs from the accent.
  static const darkroom = GrColors(
    brightness: Brightness.dark,
    bg: Color(0xFF0E0908),
    s1: Color(0xFF170F0D),
    s2: Color(0xFF201613),
    s3: Color(0xFF2B1E1A),
    s4: Color(0xFF372722),
    line: Color(0x12FFFFFF),
    line2: Color(0x1FFFFFFF),
    t1: Color(0xFFF5E8E0),
    t2: Color(0xFFB39A8F),
    t3: Color(0xFF786259),
    accent: Color(0xFFFF6038),
    accentInk: Color(0xFF2C0700),
    ok: Color(0xFF6FD08F),
    danger: Color(0xFFFF4F86),
    invBg: Color(0xFFF5E8E0),
    invFg: Color(0xFF140C0A),
    invFg2: Color(0xFF5E4C44),
    inv2: Color(0xFFE3D3C9),
    float: Color(0xEB2B1E1A),
    shadow: Color(0x73000000),
    dim: Color(0x8C000000),
  );

  /// Warm fibre paper with a burnt sienna accent. Danger is a crimson, so
  /// it differs from the accent.
  static const paper = GrColors(
    brightness: Brightness.light,
    bg: Color(0xFFF7F2E8),
    s1: Color(0xFFFCF9F2),
    s2: Color(0xFFEFE8DA),
    s3: Color(0xFFE6DDCC),
    s4: Color(0xFFD3C8B3),
    line: Color(0x14000000),
    line2: Color(0x1F000000),
    t1: Color(0xFF1E1912),
    t2: Color(0xFF5F5646),
    t3: Color(0xFF8C826F),
    accent: Color(0xFFA8481A),
    accentInk: Color(0xFFFFFFFF),
    ok: Color(0xFF2A7A45),
    danger: Color(0xFFC2263A),
    invBg: Color(0xFF1E1912),
    invFg: Color(0xFFFCF9F2),
    invFg2: Color(0xFFA39A88),
    inv2: Color(0xFF352D22),
    float: Color(0xEBFCF9F2),
    shadow: Color(0x1F000000),
    dim: Color(0x4D000000),
  );

  /// A cyanotype print: Prussian blue surfaces with a pale cyan accent.
  static const cyanotype = GrColors(
    brightness: Brightness.dark,
    bg: Color(0xFF071626),
    s1: Color(0xFF0C1E33),
    s2: Color(0xFF12273F),
    s3: Color(0xFF1A324E),
    s4: Color(0xFF233E5E),
    line: Color(0x12FFFFFF),
    line2: Color(0x1FFFFFFF),
    t1: Color(0xFFEAF1F7),
    t2: Color(0xFF9BB1C8),
    t3: Color(0xFF607A96),
    accent: Color(0xFF7FD6F7),
    accentInk: Color(0xFF032436),
    ok: Color(0xFF5FD9A0),
    danger: Color(0xFFFF6B5E),
    invBg: Color(0xFFEAF1F7),
    invFg: Color(0xFF071626),
    invFg2: Color(0xFF4A6079),
    inv2: Color(0xFFD5E0EA),
    float: Color(0xEB1A324E),
    shadow: Color(0x73000000),
    dim: Color(0x8C000000),
    switchThumb: Color(0xFF032436),
  );

  /// Badges drawn over photos keep the dark-theme colours on a 72 % black
  /// scrim in every theme, so they stay legible on bright images.
  static const photoBadgeScrim = Color(0xB8000000);
  static const photoBadgeOk = Color(0xFF5BD08B);

  /// Whether the colours make a dark or a light interface.
  final Brightness brightness;

  final Color bg;
  final Color s1;
  final Color s2;
  final Color s3;
  final Color s4;
  final Color line;
  final Color line2;
  final Color t1;
  final Color t2;
  final Color t3;
  final Color accent;
  final Color accentInk;
  final Color ok;
  final Color danger;
  final Color invBg;
  final Color invFg;
  final Color invFg2;
  final Color inv2;
  final Color float;
  final Color shadow;
  final Color dim;

  /// The thumb of a switch that is on, over [accent]: white, except where
  /// the accent is too pale for white to show on it.
  final Color switchThumb;

  Color get accentSoft => accent.withValues(alpha: .14);
  Color get accentLine => accent.withValues(alpha: .32);

  static GrColors of(BuildContext context) =>
      Theme.of(context).extension<GrColors>()!;

  @override
  GrColors copyWith() => this;

  @override
  GrColors lerp(GrColors? other, double t) => t < .5 ? this : (other ?? this);
}

abstract final class GrRadii {
  static const xl = 28.0;
  static const lg = 20.0;
  static const md = 14.0;
  static const sm = 10.0;
}

/// Interface text is Inter; camera data (exposure, counts, serials, file
/// names) is JetBrains Mono, echoing the camera's own readouts.
abstract final class GrFonts {
  static const ui = 'Inter';
  static const mono = 'JetBrainsMono';

  static TextStyle monoStyle(
    BuildContext context, {
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: mono,
    fontSize: size,
    fontWeight: weight,
    color: color ?? GrColors.of(context).t2,
  );
}

/// The themes Settings offers. [system] follows the phone between [light]
/// and [dark]; every other theme keeps its colours whatever the phone's
/// setting.
enum AppTheme {
  system(null),
  light(GrColors.light),
  dark(GrColors.dark),
  darkroom(GrColors.darkroom),
  paper(GrColors.paper),
  cyanotype(GrColors.cyanotype);

  new(this.colors);

  /// Null for [system].
  final GrColors? colors;
}

ThemeData grTheme(GrColors c) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: c.brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.accentInk,
        surface: c.bg,
        onSurface: c.t1,
        onSurfaceVariant: c.t2,
        surfaceContainerLowest: c.bg,
        surfaceContainerLow: c.s1,
        surfaceContainer: c.s1,
        surfaceContainerHigh: c.s2,
        surfaceContainerHighest: c.s3,
        outline: c.line2,
        outlineVariant: c.line,
        error: c.danger,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: c.brightness,
    colorScheme: scheme,
    fontFamily: GrFonts.ui,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    // Pages slide in over the one they open from, on every platform.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const CupertinoPageTransitionsBuilder(),
      },
    ),
    textTheme: base.textTheme.apply(bodyColor: c.t1, displayColor: c.t1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.t1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: GrFonts.ui,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: c.t1,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.accentInk,
        minimumSize: const Size(64, 50),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: GrFonts.ui,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.t1,
        backgroundColor: c.s2,
        side: BorderSide(color: c.line2),
        minimumSize: const Size(64, 50),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: GrFonts.ui,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.accent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.s1,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.s4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.s4,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.switchThumb : Colors.white,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.invBg,
      contentTextStyle: TextStyle(fontFamily: GrFonts.ui, color: c.invFg),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
