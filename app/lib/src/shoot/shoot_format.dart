import 'package:gr_protocol/gr_protocol.dart';

/// Self-timer choices of the Shoot screen.
enum ShootTimer {
  off(null, 'Off'),
  twoSeconds(Duration(seconds: 2), '2 s'),
  tenSeconds(Duration(seconds: 10), '10 s');

  const ShootTimer(this.delay, this.label);

  /// Null for [off].
  final Duration? delay;
  final String label;
}

/// Drive modes without their self-timer, in the camera's menu order. The
/// camera combines each with a timer into one Drive Mode value (BLE
/// `B29E6DE3`, ble.md); [continuous] has no timed variant.
enum ShootDrive {
  single('Single'),
  continuous('Continuous'),
  bracket('Bracket'),
  multipleExposure('Multi-exposure'),
  interval('Interval'),
  intervalComposite('Interval composite');

  const ShootDrive(this.label);

  final String label;

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

/// Mode dial label: `Av`, `U1`, `SFP`.
String exposureLabel(BleShootingMode mode) {
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
    BleExposureMode.auto => 'Auto',
    BleExposureMode.tav => 'TAv',
    BleExposureMode.sv => 'Sv',
    BleExposureMode.x => 'X',
    BleExposureMode.movieP ||
    BleExposureMode.movieTv ||
    BleExposureMode.movieAv ||
    BleExposureMode.movieTav ||
    BleExposureMode.movieM => 'Movie',
    BleExposureMode.astroTracer ||
    BleExposureMode.astroTracerT ||
    BleExposureMode.astroTracerBt ||
    BleExposureMode.astroTracerType3 => 'Astro',
    BleExposureMode.sfp => 'SFP',
  };
}

/// A `/v1/props` setting value as the camera shows it
/// (remote-shooting.md §4.3).
String settingLabel(String key, String value) => switch (key) {
  'av' => value == '---' ? '---' : 'f/$value',
  'tv' => _shutterLabel(value),
  'sv' =>
    value == 'auto'
        ? 'AUTO'
        : value == '---'
        ? '---'
        : value,
  'xv' => _evLabel(value),
  'meteringMode' => switch (value) {
    'multi' => 'Multi',
    'center' => 'Center',
    'spot' => 'Spot',
    'highlight' => 'Highlight',
    _ => value,
  },
  'effect' => switch (value) {
    'off' => 'Standard',
    'col_vivid' => 'Vivid',
    'col_custom1' => 'Custom 1',
    'col_custom2' => 'Custom 2',
    'efc_monochrome' => 'Monotone',
    'efc_softMonochrome' => 'Soft Monotone',
    'efc_hardMonochrome' => 'Hard Monotone',
    'efc_highContrast' => 'Hi-Contrast B&W',
    'efc_posiFilm' => 'Positive Film',
    'efc_bleachBypass' => 'Bleach Bypass',
    'efc_retro' => 'Retro',
    'efc_HDRTone' => 'HDR Tone',
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
