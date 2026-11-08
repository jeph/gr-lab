import 'package:flutter/material.dart';

/// Colours from the mock-ups (`design/mockups/index.html` in the research
/// repo): a near-black or off-white base, three raised surfaces, hairlines,
/// three text levels and one accent (blue by default).
@immutable
final class GrColors extends ThemeExtension<GrColors> {
  const GrColors({
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
  });

  static const dark = GrColors(
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
    bg: Color(0xFFF6F5F2),
    s1: Color(0xFFFFFFFF),
    s2: Color(0xFFEDECE8),
    s3: Color(0xFFE4E3DE),
    s4: Color(0xFFD5D4CE),
    line: Color(0x12000000),
    line2: Color(0x1F000000),
    t1: Color(0xFF121214),
    t2: Color(0xFF5F5E59),
    t3: Color(0xFF8F8E88),
    accent: Color(0xFF1F63E0),
    accentInk: Color(0xFFFFFFFF),
    ok: Color(0xFF1E9E5A),
    danger: Color(0xFFFF5A4E),
    invBg: Color(0xFF121214),
    invFg: Color(0xFFF6F5F2),
    invFg2: Color(0xFF9C9B96),
    inv2: Color(0xFF2A2A2E),
    float: Color(0xEBFFFFFF),
    shadow: Color(0x1F000000),
    dim: Color(0x4D000000),
  );

  /// Badges drawn over photos keep the dark-theme colours on a 72 % black
  /// scrim in both themes, so they stay legible on bright images.
  static const photoBadgeScrim = Color(0xB8000000);
  static const photoBadgeOk = Color(0xFF5BD08B);

  final Color bg, s1, s2, s3, s4, line, line2, t1, t2, t3;
  final Color accent, accentInk, ok, danger;
  final Color invBg, invFg, invFg2, inv2, float, shadow, dim;

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

ThemeData grTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? GrColors.dark : GrColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
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
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: GrFonts.ui,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
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
      thumbColor: const WidgetStatePropertyAll(Colors.white),
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
