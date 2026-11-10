import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/src/looks/render/render_planes.dart';

Plane _plane(int width, int height, double Function(int x, int y) value) {
  final plane = Plane(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      plane.values[y * width + x] = value(x, y);
    }
  }
  return plane;
}

double _uneven(int x, int y) => ((x * 37 + y * 101 + x * y * 7) % 23) * 9.0;

void main() {
  test('halving averages 2 × 2 blocks and repeats the edge of an odd '
      'side', () {
    final half = _plane(3, 3, (x, y) => (y * 3 + x).toDouble()).halved();
    expect((half.width, half.height), (2, 2));
    // 0 1 2 / 3 4 5 / 6 7 8: the last column and row stand in twice.
    expect(half.values, [2, 3.5, 6.5, 8]);
  });

  test('doubling puts each value at the middle of the block halving '
      'averaged, so the two together blur by 1, 6, 1 over 8', () {
    final plane = _plane(9, 7, _uneven);
    final there = plane.doubled(18, 14);
    expect(there.values[0], plane.values[0], reason: 'the edge repeats');
    expect(
      there.values[1],
      closeTo(0.75 * plane.values[0] + 0.25 * plane.values[1], 1e-4),
    );
    final back = there.halved();
    final blurred = plane.filtered(const [
      1 / 64, 6 / 64, 1 / 64, //
      6 / 64, 36 / 64, 6 / 64, //
      1 / 64, 6 / 64, 1 / 64, //
    ]);
    for (var i = 0; i < plane.values.length; i++) {
      expect(back.values[i], closeTo(blurred.values[i], 1e-3), reason: '$i');
    }
  });

  test('doubling cuts to an odd size', () {
    final plane = _plane(4, 3, _uneven);
    final full = plane.doubled(8, 6);
    final cut = plane.doubled(7, 5);
    expect((cut.width, cut.height), (7, 5));
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 7; x++) {
        expect(cut.values[y * 7 + x], full.values[y * 8 + x]);
      }
    }
  });

  test('spreading puts each value where taking every other finds it '
      'again, with the mean of two neighbours between them', () {
    final plane = _plane(5, 4, _uneven);
    final wide = plane.spread(10, 8);
    expect(wide.everyOther().values, plane.values);
    expect(
      wide.values[1],
      closeTo((plane.values[0] + plane.values[1]) / 2, 1e-4),
    );
    expect(wide.values[9], plane.values[4], reason: 'the edge repeats');
    final odd = _plane(5, 3, _uneven).everyOther();
    expect((odd.width, odd.height), (3, 2));
  });

  test('filtering weighs the square around each value and repeats the '
      'edge past it', () {
    final plane = _plane(4, 3, _uneven);
    expect(
      plane.filtered(const [0, 0, 0, 0, 1, 0, 0, 0, 0]).values,
      plane.values,
    );
    // The value to the left of each, which at the left edge is itself.
    final left = plane.filtered(const [0, 0, 0, 1, 0, 0, 0, 0, 0]);
    expect(left.values.sublist(0, 4), [
      plane.values[0],
      plane.values[0],
      plane.values[1],
      plane.values[2],
    ]);
    // Two rows up, in a 5 × 5 square.
    final up = plane.filtered(List.generate(25, (i) => i == 2 ? 1 : 0));
    expect(up.values.sublist(8, 12), plane.values.sublist(0, 4));
    expect(up.values.sublist(4, 8), plane.values.sublist(0, 4));
  });

  test('a copy shares nothing with the plane it was made from', () {
    final plane = _plane(2, 2, _uneven);
    final copy = plane.copy()..values[0] = -1;
    expect(plane.values[0], isNot(-1));
    expect(copy.values.sublist(1), plane.values.sublist(1));
  });

  group('a picture', () {
    final rgba = Uint8List.fromList([
      255, 0, 0, 7, //
      0, 255, 0, 7, //
      0, 0, 255, 7, //
      255, 255, 255, 7, //
      0, 0, 0, 7, //
      90, 160, 30, 7, //
    ]);

    test('holds JPEG luma and chroma and gives its bytes back, opaque', () {
      final picture = LookPicture.fromRgba(rgba, 3, 2);
      expect((picture.width, picture.height, picture.longSide), (3, 2, 3));
      expect(picture.luma.values[0], closeTo(76.245, 1e-3));
      expect(picture.blue.values[2], closeTo(255.5, 1e-3));
      expect(picture.red.values[0], closeTo(255.5, 1e-3));
      expect(picture.blue.values[3], closeTo(128, 1e-3));
      final opaque = Uint8List.fromList(rgba);
      for (var i = 3; i < opaque.length; i += 4) {
        opaque[i] = 255;
      }
      expect(picture.toRgba(), opaque);
    });

    test('limits what is out of range only on the way to bytes', () {
      final picture = LookPicture.fromRgba(rgba, 3, 2);
      picture.luma.values[3] = 300;
      picture.luma.values[4] = -20;
      expect(picture.luma.values[3], 300);
      final bytes = picture.toRgba();
      expect(bytes.sublist(12, 16), [255, 255, 255, 255]);
      expect(bytes.sublist(16, 20), [0, 0, 0, 255]);
    });

    test('recolours every pixel from R, G, B of 0 to 255', () {
      final picture = LookPicture.fromRgba(rgba, 3, 2);
      picture.luma.values[3] = 300;
      final seen = <List<double>>[];
      picture.recolourEach((rgb) {
        seen.add([...rgb]);
        final red = rgb[0];
        rgb[0] = rgb[2];
        rgb[2] = red;
      });
      expect(seen, hasLength(6));
      expect(seen[5][0], closeTo(90, 1e-3));
      expect(seen[5][1], closeTo(160, 1e-3));
      expect(seen[3], [255, 255, 255], reason: 'limited before recolouring');
      expect(picture.toRgba().sublist(20, 23), [30, 160, 90]);
      expect(picture.toRgba().sublist(0, 3), [0, 0, 255]);
    });
  });
}
