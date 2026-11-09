import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';

/// [child] tinted to suggest how [look] renders. It is an approximation
/// \[design\]: a colour matrix per base image and adjustment, not the
/// camera's processing, so the editor labels it as one.
class LookPreview extends StatelessWidget {
  const new({required this.look, required this.child, super.key});

  final BleImageControlBlob look;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColorFiltered(
    colorFilter: ColorFilter.matrix(lookMatrix(look)),
    child: child,
  );
}

/// The 4×5 colour matrix [LookPreview] applies for [look].
List<double> lookMatrix(BleImageControlBlob look) {
  int v(BleImageControlParameter p) => look.valueOf(p) ?? 0;
  final base = look.base.known ?? BleImageControlBase.standard;
  var m = _identity;
  m = _mul(_baseMatrix(base), m);
  m = _mul(_saturation(1 + v(BleImageControlParameter.saturation) * .1), m);
  m = _mul(_hue(v(BleImageControlParameter.hue) * 6), m);
  m = _mul(_contrast(1 + v(BleImageControlParameter.contrast) * .07), m);
  m = _mul(_brightness(v(BleImageControlParameter.key) * 7), m);
  final toning = _toning(look);
  if (toning != null) m = _mul(toning, m);
  return m;
}

const _identity = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

// Rec. 709 luma weights.
const _lr = .2126;
const _lg = .7152;
const _lb = .0722;

List<double> _baseMatrix(BleImageControlBase base) => switch (base) {
  BleImageControlBase.standard => _identity,
  BleImageControlBase.vivid => _mul(_contrast(1.08), _saturation(1.4)),
  BleImageControlBase.positiveFilm => _mul(
    _tint(1.04, 1, .94),
    _mul(_contrast(1.12), _saturation(1.2)),
  ),
  BleImageControlBase.negativeFilm => _mul(
    _tint(1.03, 1.01, .95),
    _mul(_contrast(.88), _saturation(.85)),
  ),
  BleImageControlBase.bleachBypass => _mul(_contrast(1.25), _saturation(.45)),
  BleImageControlBase.retro => _mul(
    _tint(1.08, 1, .82),
    _mul(_contrast(.92), _saturation(.7)),
  ),
  BleImageControlBase.hdrTone => _mul(_contrast(.85), _saturation(1.15)),
  BleImageControlBase.cineYellow => _mul(
    _tint(1.06, 1.03, .86),
    _saturation(.85),
  ),
  BleImageControlBase.cineGreen => _mul(_tint(.94, 1.04, .98), _saturation(.8)),
  BleImageControlBase.crossProcess => _mul(
    _tint(1.05, 1.06, .8),
    _mul(_contrast(1.15), _saturation(1.25)),
  ),
  BleImageControlBase.softMonotone ||
  BleImageControlBase.softMono => _mul(_contrast(.85), _saturation(0)),
  BleImageControlBase.hardMonotone ||
  BleImageControlBase.highContrastMono ||
  BleImageControlBase.solid => _mul(_contrast(1.3), _saturation(0)),
  BleImageControlBase.highContrast => _mul(_contrast(1.6), _saturation(0)),
  BleImageControlBase.solarization => _mul(_contrast(1.4), _saturation(0)),
  BleImageControlBase.monotone ||
  BleImageControlBase.standardMono ||
  BleImageControlBase.grainy ||
  BleImageControlBase.hdrMono ||
  BleImageControlBase.pictorialist => _saturation(0),
  BleImageControlBase.pallet => _identity,
};

/// A toning tint over the result, when the look has one set.
List<double>? _toning(BleImageControlBlob look) {
  final mono = look.valueOf(BleImageControlParameter.toningMonotone) ?? 0;
  final tint = switch (mono) {
    1 => _tint(1.1, 1, .82),
    2 => _tint(1.12, .95, .95),
    3 => _tint(.95, 1.08, .95),
    4 => _tint(.92, .98, 1.12),
    5 => _tint(1.06, .92, 1.08),
    _ => null,
  };
  if (tint != null) return tint;
  final hdr = look.valueOf(BleImageControlParameter.toningHdr) ?? 0;
  if (hdr == 1) return _saturation(0);
  if (hdr == 2) return _mul(_tint(1.1, 1, .82), _saturation(0));
  return switch (look.valueOf(BleImageControlParameter.crossProcess)) {
    1 => _tint(1.06, .94, 1.04),
    2 => _tint(1.04, 1.04, .88),
    _ => null,
  };
}

List<double> _saturation(double s) {
  final r = (1 - s) * _lr;
  final g = (1 - s) * _lg;
  final b = (1 - s) * _lb;
  return [
    r + s, g, b, 0, 0, //
    r, g + s, b, 0, 0, //
    r, g, b + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _contrast(double c) {
  final t = 128 * (1 - c);
  return [
    c, 0, 0, 0, t, //
    0, c, 0, 0, t, //
    0, 0, c, 0, t, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _brightness(double d) => [
  1, 0, 0, 0, d, //
  0, 1, 0, 0, d, //
  0, 0, 1, 0, d, //
  0, 0, 0, 1, 0, //
];

List<double> _tint(double r, double g, double b) => [
  r, 0, 0, 0, 0, //
  0, g, 0, 0, 0, //
  0, 0, b, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Rotation of hue by [degrees] around the luma axis.
List<double> _hue(double degrees) {
  final a = degrees * math.pi / 180;
  final c = math.cos(a);
  final s = math.sin(a);
  return [
    _lr + c * (1 - _lr) - s * _lr,
    _lg - c * _lg - s * _lg,
    _lb - c * _lb + s * (1 - _lb),
    0,
    0,
    _lr - c * _lr + s * .143,
    _lg + c * (1 - _lg) + s * .14,
    _lb - c * _lb - s * .283,
    0,
    0,
    _lr - c * _lr - s * (1 - _lr),
    _lg - c * _lg + s * _lg,
    _lb + c * (1 - _lb) + s * _lb,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// [a] applied after [b].
List<double> _mul(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = col == 4 ? a[row * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      out[row * 5 + col] = sum;
    }
  }
  return out;
}
