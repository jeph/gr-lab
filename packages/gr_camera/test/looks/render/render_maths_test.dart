import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/src/looks/render/render_maths.dart';

void main() {
  test('a matrix times its inverse is the identity', () {
    const m = [1.07, 0.004, -0.07, 0.03, 1.01, -0.04, -0.02, 0.05, 0.97];
    final product = mat3Multiply(m, mat3Inverse(m));
    for (var i = 0; i < 9; i++) {
      expect(product[i], closeTo(mat3Identity[i], 1e-12));
    }
  });

  test('a matrix product applies its right-hand matrix first', () {
    const scale = <double>[2, 0, 0, 0, 3, 0, 0, 0, 4];
    const swapRedBlue = <double>[0, 0, 1, 0, 1, 0, 1, 0, 0];
    final v = Float64List.fromList([1, 10, 100]);
    mat3Apply(mat3Multiply(scale, swapRedBlue), v);
    expect(v, [200, 30, 4]);
  });

  test('YCbCr is the JFIF one and converts back', () {
    final v = Float64List.fromList([1, 0, 0]);
    rgbToYcc(v);
    expect(v[0], closeTo(0.299, 1e-9));
    expect(v[1], closeTo(-0.168736, 1e-6));
    expect(v[2], closeTo(0.5, 1e-9));
    yccToRgb(v);
    expect(v[0], closeTo(1, 1e-9));
    expect(v[1], closeTo(0, 1e-9));
    expect(v[2], closeTo(0, 1e-9));
  });

  test('a monotone cubic passes through its knots and never overshoots '
      'between them', () {
    const x = [0, 2, 3, 10, 40, 255];
    const y = [0, 500, 520, 4000, 4000, 16384];
    final curve = monotoneCubic(x, y, 256);
    for (var k = 0; k < x.length; k++) {
      expect(curve[x[k]], closeTo(y[k], 1e-9));
    }
    for (var i = 1; i < 256; i++) {
      expect(curve[i], greaterThanOrEqualTo(curve[i - 1] - 1e-9), reason: '$i');
    }
    // Flat between two equal knots, with no bump either side.
    expect(curve[25], closeTo(4000, 1e-9));
  });

  test('a monotone cubic follows knots that fall as well as rise', () {
    final curve = monotoneCubic(
      const [0, 80, 180, 255],
      const [0, 14000, 3000, 16000],
      256,
    );
    expect(curve[80], 14000);
    expect(curve[130], inExclusiveRange(3000, 14000));
    for (var i = 0; i <= 180; i++) {
      expect(curve[i], lessThanOrEqualTo(14000), reason: 'no overshoot at $i');
    }
    expect(curve[181], greaterThan(3000));
  });

  test('a sampled curve is straight between samples and flat beyond its '
      'ends', () {
    final curve = Float64List.fromList([0, 10, 30]);
    expect(curveAt(curve, 0.5), 5);
    expect(curveAt(curve, 1.25), 15);
    expect(curveAt(curve, -1), 0);
    expect(curveAt(curve, 7), 30);
  });

  test('the inverse of a sampled curve undoes it, and gives the start of a '
      'flat stretch for its value and for anything above it', () {
    final curve = Float64List.fromList([0, 10, 30, 30, 30]);
    for (final position in [0.0, 0.3, 1.0, 1.9]) {
      expect(
        curveInverse(curve, curveAt(curve, position)),
        closeTo(position, 1e-12),
      );
    }
    expect(curveInverse(curve, 30), 2, reason: 'where the clip begins');
    expect(curveInverse(curve, 30.0000001), 2, reason: 'just above the clip');
    expect(curveInverse(curve, 99), 2);
    expect(curveInverse(curve, -5), 0);
    expect(curveInverse(Float64List.fromList([0, 10, 30]), 99), 2);
  });
}
