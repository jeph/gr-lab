import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';

/// Self-timer choices of the Shoot screen.
enum ShootTimer {
  off(null),
  twoSeconds(Duration(seconds: 2)),
  tenSeconds(Duration(seconds: 10));

  new(this.delay);

  /// Null for [off].
  final Duration? delay;

  /// `Off`, `2 s`, `10 s`.
  String label(AppLocalizations l10n) => switch (delay) {
    null => l10n.shootTimerOff,
    final delay => l10n.shootTimerSeconds(delay.inSeconds),
  };
}

/// Drive modes without their self-timer, in the camera's menu order. The
/// camera combines each with a timer into one Drive Mode value (BLE
/// `B29E6DE3`, ble.md); [continuous] has no timed variant.
enum ShootDrive {
  single,
  continuous,
  bracket,
  multipleExposure,
  interval,
  intervalComposite;

  /// The name the camera's Drive menu uses.
  String label(AppLocalizations l10n) => switch (this) {
    single => l10n.shootDriveSingle,
    continuous => l10n.shootDriveContinuous,
    bracket => l10n.shootDriveBracket,
    multipleExposure => l10n.shootDriveMultipleExposure,
    interval => l10n.shootDriveInterval,
    intervalComposite => l10n.shootDriveIntervalComposite,
  };

  bool get hasTimer => this != continuous;

  /// The Drive Mode value for this drive with [timer]; [timer] is ignored
  /// for [continuous].
  BleDriveMode withTimer(ShootTimer timer) {
    final (off, ten, two) = switch (this) {
      single => (
        BleDriveMode.single,
        BleDriveMode.selfTimer10s,
        BleDriveMode.selfTimer2s,
      ),
      continuous => (
        BleDriveMode.continuous,
        BleDriveMode.continuous,
        BleDriveMode.continuous,
      ),
      bracket => (
        BleDriveMode.bracket,
        BleDriveMode.bracketSelfTimer10s,
        BleDriveMode.bracketSelfTimer2s,
      ),
      multipleExposure => (
        BleDriveMode.multipleExposure,
        BleDriveMode.multipleExposureSelfTimer10s,
        BleDriveMode.multipleExposureSelfTimer2s,
      ),
      interval => (
        BleDriveMode.interval,
        BleDriveMode.intervalSelfTimer10s,
        BleDriveMode.intervalSelfTimer2s,
      ),
      intervalComposite => (
        BleDriveMode.intervalComposite,
        BleDriveMode.intervalCompositeSelfTimer10s,
        BleDriveMode.intervalCompositeSelfTimer2s,
      ),
    };
    return switch (timer) {
      ShootTimer.off => off,
      ShootTimer.tenSeconds => ten,
      ShootTimer.twoSeconds => two,
    };
  }

  /// Splits a Drive Mode value; null for values outside the GR III/IV
  /// table (0-15), which other models use.
  static (ShootDrive, ShootTimer)? split(BleDriveMode? mode) {
    if (mode == null) return null;
    for (final drive in values) {
      for (final timer in ShootTimer.values) {
        if (drive.withTimer(timer) == mode) return (drive, timer);
      }
    }
    return null;
  }
}

/// Mode dial label: `Av`, `U1`, `SFP` as the camera's dial reads; the modes
/// named by a word (Auto, Movie, Astro) are messages.
String exposureLabel(AppLocalizations l10n, BleShootingMode mode) {
  final user = mode.userMode.known;
  if (user != null && user != BleUserMode.none) {
    return user.name.toUpperCase();
  }
  final known = mode.mode.known;
  if (known == null) return '${mode.mode.raw}';
  return switch (known) {
    BleExposureMode.p => 'P',
    BleExposureMode.av => 'Av',
    BleExposureMode.tv => 'Tv',
    BleExposureMode.m => 'M',
    BleExposureMode.b => 'B',
    BleExposureMode.bt => 'BT',
    BleExposureMode.t => 'T',
    BleExposureMode.auto => l10n.shootExposureAuto,
    BleExposureMode.tav => 'TAv',
    BleExposureMode.sv => 'Sv',
    BleExposureMode.x => 'X',
    BleExposureMode.movieP ||
    BleExposureMode.movieTv ||
    BleExposureMode.movieAv ||
    BleExposureMode.movieTav ||
    BleExposureMode.movieM => l10n.shootExposureMovie,
    BleExposureMode.astroTracer ||
    BleExposureMode.astroTracerT ||
    BleExposureMode.astroTracerBt ||
    BleExposureMode.astroTracerType3 => l10n.shootExposureAstro,
    BleExposureMode.sfp => 'SFP',
  };
}

/// A `/v1/props` setting value as the camera shows it
/// (remote-shooting.md §4.3; the Image Controls of the GR IV family,
/// whose names the GR IV 1.20 firmware lists for every body,
/// image-control.md §3): readouts such as `f/2.8`, `1/250` and `AUTO` as
/// data, menu names such as Spot and Positive Film as messages.
String settingLabel(AppLocalizations l10n, String key, String value) =>
    switch (key) {
      'av' => value == '---' ? '---' : 'f/$value',
      'tv' => _shutterLabel(value),
      'sv' => value == 'auto' ? 'AUTO' : value,
      'xv' => _evLabel(value),
      'meteringMode' => switch (value) {
        'multi' => l10n.shootMeteringMulti,
        'center' => l10n.shootMeteringCenter,
        'spot' => l10n.shootMeteringSpot,
        'highlight' => l10n.shootMeteringHighlight,
        _ => value,
      },
      'effect' => switch (value) {
        'off' => l10n.shootEffectStandard,
        'col_vivid' => l10n.shootEffectVivid,
        'efc_monochrome' => l10n.shootEffectMonotone,
        'efc_softMonochrome' => l10n.shootEffectSoftMonotone,
        'efc_hardMonochrome' => l10n.shootEffectHardMonotone,
        'efc_highContrast' => l10n.shootEffectHiContrast,
        'efc_negaFilm' => l10n.looksBaseNegativeFilm,
        'efc_posiFilm' => l10n.shootEffectPositiveFilm,
        'efc_cineYellow' => l10n.looksBaseCinemaYellow,
        'efc_cineGreen' => l10n.looksBaseCinemaGreen,
        'efc_crossProcess' => l10n.looksBaseCrossProcessing,
        'efc_bleachBypass' => l10n.shootEffectBleachBypass,
        'efc_retro' => l10n.shootEffectRetro,
        'efc_HDRTone' => l10n.shootEffectHdrTone,
        'efc_monoStandard' => l10n.looksBaseMonoStandard,
        'efc_monoSoft' => l10n.looksBaseMonoSoft,
        'efc_monoHighContrast' => l10n.looksBaseMonoHighContrast,
        'efc_monoGrainy' => l10n.looksBaseGrainy,
        'efc_monoSolid' => l10n.looksBaseSolid,
        'efc_monoHDRTone' => l10n.looksBaseMonoHdrTone,
        // The firmware's spelling.
        'efc_pallete' => l10n.looksBasePalette,
        'efc_solarization' => l10n.looksBaseSolarized,
        'efc_pictorialism' => l10n.looksBasePictorialist,
        'col_custom1' => l10n.shootEffectCustom1,
        'col_custom2' => l10n.shootEffectCustom2,
        'col_custom3' => l10n.shootEffectCustom3,
        _ => value,
      },
      _ => value,
    };

/// `N.D` is N/D seconds: `1.320` -> `1/320`, `3.10` -> `0.3"`,
/// `2.1` -> `2"`.
String _shutterLabel(String value) {
  final parts = value.split('.');
  if (parts.length != 2) return value;
  final n = int.tryParse(parts[0]);
  final d = int.tryParse(parts[1]);
  if (n == null || d == null || d == 0) return value;
  if (n == 1 && d > 1) return '1/$d';
  final seconds = n / d;
  final text = seconds == seconds.roundToDouble()
      ? '${seconds.round()}'
      : '$seconds';
  return '$text"';
}

String _evLabel(String value) {
  final v = double.tryParse(value);
  if (v == null) return value;
  if (v == 0) return '±0.0';
  return value.startsWith('+') || value.startsWith('-') ? value : '+$value';
}
