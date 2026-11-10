/// The arithmetic every camera's look rendering shares: 3×3 matrices,
/// BT.601 YCbCr, monotone cubics and sampled curves. Nothing here knows a
/// camera; what a camera does with it lives in that camera's renderer.
library;

import 'dart:typed_data';

/// The 3×3 identity matrix, row by row.
const List<double> mat3Identity = [1, 0, 0, 0, 1, 0, 0, 0, 1];

/// The product `a · b` of two 3×3 matrices held row by row: [b] applies
/// first.
Float64List mat3Multiply(List<double> a, List<double> b) {
  final out = Float64List(9);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      var sum = 0.0;
      for (var k = 0; k < 3; k++) {
        sum += a[row * 3 + k] * b[k * 3 + col];
      }
      out[row * 3 + col] = sum;
    }
  }
  return out;
}

/// The inverse of the 3×3 matrix [m]. A matrix without one (determinant
/// zero) gives non-finite entries; callers invert only matrices they know
/// have one.
Float64List mat3Inverse(List<double> m) {
  final c0 = m[4] * m[8] - m[5] * m[7];
  final c1 = m[5] * m[6] - m[3] * m[8];
  final c2 = m[3] * m[7] - m[4] * m[6];
  final det = m[0] * c0 + m[1] * c1 + m[2] * c2;
  return Float64List.fromList([
    c0 / det,
    (m[2] * m[7] - m[1] * m[8]) / det,
    (m[1] * m[5] - m[2] * m[4]) / det,
    c1 / det,
    (m[0] * m[8] - m[2] * m[6]) / det,
    (m[2] * m[3] - m[0] * m[5]) / det,
    c2 / det,
    (m[1] * m[6] - m[0] * m[7]) / det,
    (m[0] * m[4] - m[1] * m[3]) / det,
  ]);
}

/// Replaces the vector in [v] with `m · v`.
void mat3Apply(List<double> m, Float64List v) {
  final a = v[0];
  final b = v[1];
  final c = v[2];
  v[0] = m[0] * a + m[1] * b + m[2] * c;
  v[1] = m[3] * a + m[4] * b + m[5] * c;
  v[2] = m[6] * a + m[7] * b + m[8] * c;
}

/// Limits each of [v]'s three values to 0..1.
void clampUnit(Float64List v) {
  v[0] = v[0].clamp(0.0, 1.0);
  v[1] = v[1].clamp(0.0, 1.0);
  v[2] = v[2].clamp(0.0, 1.0);
}

/// The BT.601 luma weights of R, G and B, as JPEG uses them.
const double lumaRed = 0.299;

/// See [lumaRed].
const double lumaGreen = 0.587;

/// See [lumaRed].
const double lumaBlue = 0.114;

/// Replaces the R, G, B in [v] with full-range BT.601 Y, Cb, Cr (JFIF):
/// Y in 0..1 and Cb, Cr in −0.5..+0.5 for R, G, B in 0..1.
void rgbToYcc(Float64List v) {
  final r = v[0];
  final g = v[1];
  final b = v[2];
  final y = lumaRed * r + lumaGreen * g + lumaBlue * b;
  v[0] = y;
  v[1] = (b - y) / 1.772;
  v[2] = (r - y) / 1.402;
}

/// The inverse of [rgbToYcc].
void yccToRgb(Float64List v) {
  final y = v[0];
  final r = y + 1.402 * v[2];
  final b = y + 1.772 * v[1];
  v[0] = r;
  v[1] = (y - lumaRed * r - lumaBlue * b) / lumaGreen;
  v[2] = b;
}

/// The monotone cubic (Fritsch–Carlson) through the knots ([x], [y]),
/// sampled at 0, 1, … [count] − 1. [x] ascends from 0 to [count] − 1.
/// Between two knots the curve never leaves their values, so knots that
/// rise give a curve that rises.
Float64List monotoneCubic(List<int> x, List<int> y, int count) {
  final last = x.length - 1;
  final width = [for (var i = 0; i < last; i++) (x[i + 1] - x[i]).toDouble()];
  final slope = [for (var i = 0; i < last; i++) (y[i + 1] - y[i]) / width[i]];
  // The tangent at each knot: the weighted harmonic mean of the slopes
  // either side, or flat where they differ in sign.
  final tangent = Float64List(x.length);
  tangent[0] = slope[0];
  tangent[last] = slope[last - 1];
  for (var i = 1; i < last; i++) {
    if (slope[i - 1] * slope[i] <= 0) continue;
    final before = 2 * width[i] + width[i - 1];
    final after = width[i] + 2 * width[i - 1];
    tangent[i] = (before + after) / (before / slope[i - 1] + after / slope[i]);
  }
  final out = Float64List(count);
  var segment = 0;
  for (var i = 0; i < count; i++) {
    while (segment < last - 1 && i >= x[segment + 1]) {
      segment++;
    }
    final w = width[segment];
    final t = (i - x[segment]) / w;
    final t2 = t * t;
    final t3 = t2 * t;
    out[i] =
        (2 * t3 - 3 * t2 + 1) * y[segment] +
        (t3 - 2 * t2 + t) * w * tangent[segment] +
        (-2 * t3 + 3 * t2) * y[segment + 1] +
        (t3 - t2) * w * tangent[segment + 1];
  }
  return out;
}

/// A curve as the knots of a monotone cubic ([monotoneCubic]).
final class CurveKnots {
  /// The curve through the knots ([x], [y]); [x] ascends from 0 to the
  /// curve's last index.
  const new(this.x, this.y);

  /// Each knot's index into the sampled curve.
  final List<int> x;

  /// Each knot's value.
  final List<int> y;

  /// The curve at 0, 1, … [count] − 1.
  Float64List sample(int count) => monotoneCubic(x, y, count);
}

/// The value of the sampled [curve] at [position], a fractional index into
/// it: straight lines between samples, the end values beyond them.
double curveAt(Float64List curve, double position) {
  final last = curve.length - 1;
  if (position <= 0) return curve[0];
  if (position >= last) return curve[last];
  final i = position.floor();
  final low = curve[i];
  return low + (curve[i + 1] - low) * (position - i);
}

/// The lowest fractional index at which the rising sampled [curve] reaches
/// [value]: the inverse of [curveAt]. A value below the curve's start gives
/// 0 and one above its end the last index, and across a flat stretch the
/// answer is where the stretch begins, so what a curve clipped stays at
/// the clip point.
double curveInverse(Float64List curve, double value) {
  final last = curve.length - 1;
  if (value <= curve[0]) return 0;
  if (value > curve[last]) return last.toDouble();
  // The first sample at or above the value.
  var low = 0;
  var high = last;
  while (high - low > 1) {
    final mid = (low + high) >> 1;
    if (curve[mid] >= value) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return low + (value - curve[low]) / (curve[high] - curve[low]);
}
