import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gr_camera/src/looks/render/gr4/gr4_curves.dart';

/// The number of points in a GR IV tone curve.
const int gr4CurvePoints = 256;

/// The output a GR IV tone curve gives for white.
const int gr4CurveWhite = 0x4000;

/// The tone curve the GR IV builds for the four tone sliders, each a step
/// from −4 to +4 as the camera shows it: [gr4CurvePoints] points, point `i`
/// for the 12-bit linear input `16 · i`, each from 0 to [gr4CurveWhite]
/// (research/image-control-processing.md §3).
///
/// The camera blends tables it stores: three contrast sets (high, neutral,
/// low), each with a table per mid-grey level. This follows its arithmetic
/// step by step, in integers as the camera does it, on GR Photo's own curves
/// fitted to those tables ([gr4ToneKnots]) \[design\], so the result is
/// within about half an 8-bit code of the camera's curve
/// (image-control-processing.md §10). The per-shot gain that moves the
/// curve's mid-grey together with the white balance is left out, as a
/// preview can \[inferred\].
Int32List gr4ToneCurve({
  required int key,
  required int contrast,
  required int highlight,
  required int shadow,
}) {
  // High/Low Key moves the input that maps to mid-grey by a quarter of a
  // stop per step, from 1024 at −4 to 256 at +4 of 4096.
  final pivot = 2 * (512 * math.pow(2, -(key + 4) / 4)).round();
  // The two level tables around the pivot: table `l` is drawn for mid-grey
  // at input 128 · 2^l.
  final lower = pivot >= 1024 ? 3 : (pivot >= 512 ? 2 : 1);
  final upper = lower + 1;
  final pivotPoint = pivot >> 4;

  // The contrast blend above the pivot, at it and below it, in twelfths:
  // Contrast counts double, Highlight and Shadow single, and a positive
  // Shadow step lightens the shadows, which is less contrast there.
  final blends = [
    _ContrastBlend(2 * contrast + highlight),
    _ContrastBlend(2 * contrast),
    _ContrastBlend(2 * contrast - shadow),
  ];
  // How much of the lower level table each blend takes, so that the pivot
  // comes out at mid-grey whatever the contrast.
  final lowerShare = Int32List(3);
  for (var k = 0; k < 3; k++) {
    final low = blends[k].at(lower, pivotPoint);
    final high = blends[k].at(upper, pivotPoint);
    lowerShare[k] = low <= high
        ? 512
        : (high < _midGrey ? ((_midGrey - high) << 9) ~/ (low - high) : 0);
  }
  int level(int k, int point) {
    final low = blends[k].at(lower, point);
    final high = blends[k].at(upper, point);
    return (lowerShare[k] * low + (512 - lowerShare[k]) * high + 256) >> 9;
  }

  final curve = Int32List(gr4CurvePoints);
  for (var i = 0; i < gr4CurvePoints; i++) {
    final input = i * 16;
    final centre = level(1, i);
    var value = centre;
    if (input > pivot && highlight != 0) {
      // Highlight contrast comes in over the two stops above the pivot.
      final side = level(0, i);
      value = input >= pivot << 2
          ? side
          : _crossFade(centre, side, (i << 9) ~/ pivot - 32);
    }
    if (input < pivot && shadow != 0) {
      // Shadow contrast comes in over the two stops below it.
      final side = level(2, i);
      value = input <= pivot >> 2
          ? side
          : _crossFade(centre, side, (pivot << 5) ~/ input - 32);
    }
    curve[i] = math.min((value << 14) ~/ _tableWhite, gr4CurveWhite);
  }
  return curve;
}

/// The level tables put mid-grey at this value: 118 of 255 on their scale
/// of 64 per 8-bit code.
const int _midGrey = 118 * 64;

/// The table value that becomes [gr4CurveWhite].
const int _tableWhite = 0x3f02;

/// [side] in place of [centre] by the ramp's weight at [distance], which
/// counts 32 per multiple of the pivot (0 at the pivot, 96 two stops away).
int _crossFade(int centre, int side, int distance) {
  final weight = _ramp[distance.clamp(0, 96)];
  return (side * weight + 1024 + centre * (2048 - weight)) >> 11;
}

/// How far Highlight or Shadow contrast has come in, of 2048, by distance
/// from the pivot in 1/32 of the pivot: `1 − (1 − s/2)²` for a distance of
/// `s` stops. The camera stores these 97 values; the formula gives every
/// one of them exactly.
final Int32List _ramp = Int32List.fromList([
  for (var i = 0; i <= 96; i++)
    (2048 * (1 - math.pow(1 - math.log(1 + i / 32) / math.ln2 / 2, 2))).round(),
]);

/// A blend of two neighbouring contrast sets.
final class _ContrastBlend {
  /// The blend [twelfths] of the way from the neutral set to the
  /// high-contrast one, or for a negative number to the low-contrast one.
  new(int twelfths)
    : _first = twelfths > 0 ? 0 : 1,
      _firstWeight = twelfths > 0
          ? (twelfths << 9) ~/ 12
          : ((twelfths + 12) << 9) ~/ 12;

  /// The contrast set weighted [_firstWeight] of 512; the next set gets
  /// the rest.
  final int _first;
  final int _firstWeight;

  /// The blend's value in the table for [level] at [point].
  int at(int level, int point) =>
      (_firstWeight * _toneTables[_first][level - 1][point] +
          (512 - _firstWeight) * _toneTables[_first + 1][level - 1][point] +
          256) >>
      9;
}

/// The level tables of each contrast set (high, neutral, low), drawn from
/// [gr4ToneKnots]: the tables for mid-grey at input 256, 512, 1024 and
/// 2048.
final List<List<Int32List>> _toneTables = [
  for (final set in gr4ToneKnots)
    [
      for (final knots in set)
        Int32List.fromList([
          for (final v in knots.sample(gr4CurvePoints)) v.round(),
        ]),
    ],
];
