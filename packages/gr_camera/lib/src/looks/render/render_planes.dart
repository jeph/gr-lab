/// Pictures as planes of numbers, and the resizing and filtering every
/// camera's look rendering shares. Nothing here knows a camera; what a
/// camera does with it lives in that camera's renderer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gr_camera/src/looks/render/render_maths.dart';

/// One channel of a picture, row by row.
final class Plane {
  /// A plane of [width] by [height] zeros.
  new(this.width, this.height) : values = Float32List(width * height);

  /// The number of values in a row.
  final int width;

  /// The number of rows.
  final int height;

  /// The values, row by row.
  final Float32List values;

  /// A copy that shares nothing with this plane.
  Plane copy() => Plane(width, height)..values.setAll(0, values);

  /// This plane at half the size, rounded up: each value the mean of a
  /// 2 × 2 block, with the last row and column repeated at an odd edge.
  Plane halved() {
    final out = Plane((width + 1) >> 1, (height + 1) >> 1);
    final to = out.values;
    var at = 0;
    for (var y = 0; y < out.height; y++) {
      final top = 2 * y * width;
      final bottom = math.min(2 * y + 1, height - 1) * width;
      for (var x = 0; x < out.width; x++) {
        final left = 2 * x;
        final right = math.min(left + 1, width - 1);
        to[at++] =
            (values[top + left] +
                values[top + right] +
                values[bottom + left] +
                values[bottom + right]) /
            4;
      }
    }
    return out;
  }

  /// This plane at twice the size, cut to [width] by [height], with
  /// straight lines between its values. Each value sits at the middle of
  /// the 2 × 2 block [halved] would average into it.
  Plane doubled(int width, int height) => _doubled(width, height, -0.5);

  /// Every other value of every other row, starting with the first.
  Plane everyOther() {
    final out = Plane((width + 1) >> 1, (height + 1) >> 1);
    final to = out.values;
    var at = 0;
    for (var y = 0; y < out.height; y++) {
      final row = 2 * y * width;
      for (var x = 0; x < out.width; x++) {
        to[at++] = values[row + 2 * x];
      }
    }
    return out;
  }

  /// This plane at twice the size, cut to [width] by [height], with
  /// straight lines between its values. Each value sits where
  /// [everyOther] would pick it up again.
  Plane spread(int width, int height) => _doubled(width, height, 0);

  /// Position `x` of the doubled plane reads position `(x + shift) / 2`
  /// of this one; positions past an edge read the edge.
  Plane _doubled(int width, int height, double shift) {
    final columns = _Taps(width, this.width, shift);
    final rows = _Taps(height, this.height, shift);
    final wide = Float32List(width * this.height);
    for (var y = 0; y < this.height; y++) {
      final from = y * this.width;
      final to = y * width;
      for (var x = 0; x < width; x++) {
        final low = values[from + columns.low[x]];
        final high = values[from + columns.high[x]];
        wide[to + x] = low + (high - low) * columns.part[x];
      }
    }
    final out = Plane(width, height);
    for (var y = 0; y < height; y++) {
      final low = rows.low[y] * width;
      final high = rows.high[y] * width;
      final part = rows.part[y];
      final to = y * width;
      for (var x = 0; x < width; x++) {
        final a = wide[low + x];
        out.values[to + x] = a + (wide[high + x] - a) * part;
      }
    }
    return out;
  }

  /// Each value replaced by the weighted sum of the square of values
  /// around it: [kernel] holds the weights of that square row by row, an
  /// odd number of them a side. Past an edge the edge's values repeat.
  Plane filtered(List<double> kernel) {
    final side = math.sqrt(kernel.length).round();
    final reach = side ~/ 2;
    final paddedWidth = width + 2 * reach;
    final padded = Float32List(paddedWidth * (height + 2 * reach));
    for (var y = 0; y < height + 2 * reach; y++) {
      final from = (y - reach).clamp(0, height - 1) * width;
      final to = y * paddedWidth;
      for (var x = 0; x < paddedWidth; x++) {
        padded[to + x] = values[from + (x - reach).clamp(0, width - 1)];
      }
    }
    final out = Plane(width, height);
    final sums = Float64List(width);
    for (var y = 0; y < height; y++) {
      sums.fillRange(0, width, 0);
      for (var ky = 0; ky < side; ky++) {
        for (var kx = 0; kx < side; kx++) {
          final weight = kernel[ky * side + kx];
          if (weight == 0) continue;
          final from = (y + ky) * paddedWidth + kx;
          for (var x = 0; x < width; x++) {
            sums[x] += weight * padded[from + x];
          }
        }
      }
      out.values.setAll(y * width, sums);
    }
    return out;
  }
}

/// Where each position of a doubled row or column reads the original:
/// between [low] and [high], [part] of the way to [high].
final class _Taps {
  new(int count, int from, double shift)
    : low = Int32List(count),
      high = Int32List(count),
      part = Float32List(count) {
    for (var i = 0; i < count; i++) {
      final position = (i + shift) / 2;
      final floor = position.floor();
      low[i] = floor.clamp(0, from - 1);
      high[i] = (floor + 1).clamp(0, from - 1);
      part[i] = position - floor;
    }
  }

  final Int32List low;
  final Int32List high;
  final Float32List part;
}

/// A picture as JPEG holds it: full-range BT.601 luma and chroma, 0 to 255
/// with chroma about 128, not rounded and not limited to that range until
/// it goes back to bytes.
final class LookPicture {
  /// A picture of [width] by [height] pixels, black.
  new(int width, int height)
    : luma = Plane(width, height),
      blue = Plane(width, height),
      red = Plane(width, height);

  /// The picture in [rgba]: [width] by [height] pixels of 8-bit R, G, B
  /// and alpha, row by row. The alpha is not kept.
  factory fromRgba(Uint8List rgba, int width, int height) {
    final picture = LookPicture(width, height);
    final pixel = Float64List(3);
    for (var i = 0; i < width * height; i++) {
      pixel[0] = rgba[i * 4].toDouble();
      pixel[1] = rgba[i * 4 + 1].toDouble();
      pixel[2] = rgba[i * 4 + 2].toDouble();
      picture._store(i, pixel);
    }
    return picture;
  }

  /// Y, the luma.
  final Plane luma;

  /// Cb, the blue chroma, about 128.
  final Plane blue;

  /// Cr, the red chroma, about 128.
  final Plane red;

  /// The number of pixels in a row.
  int get width => luma.width;

  /// The number of rows.
  int get height => luma.height;

  /// The longer of [width] and [height].
  int get longSide => math.max(width, height);

  /// Puts every pixel through [recolour], which takes and leaves R, G, B
  /// of 0 to 255.
  void recolourEach(void Function(Float64List rgb) recolour) {
    final pixel = Float64List(3);
    for (var i = 0; i < width * height; i++) {
      pixel[0] = luma.values[i] / 255;
      pixel[1] = (blue.values[i] - 128) / 255;
      pixel[2] = (red.values[i] - 128) / 255;
      yccToRgb(pixel);
      pixel[0] = (pixel[0] * 255).clamp(0, 255);
      pixel[1] = (pixel[1] * 255).clamp(0, 255);
      pixel[2] = (pixel[2] * 255).clamp(0, 255);
      recolour(pixel);
      _store(i, pixel);
    }
  }

  /// The picture as 8-bit R, G, B and opaque alpha, row by row.
  Uint8List toRgba() {
    final rgba = Uint8List(width * height * 4);
    final pixel = Float64List(3);
    for (var i = 0; i < width * height; i++) {
      pixel[0] = luma.values[i] / 255;
      pixel[1] = (blue.values[i] - 128) / 255;
      pixel[2] = (red.values[i] - 128) / 255;
      yccToRgb(pixel);
      rgba[i * 4] = (pixel[0] * 255).round().clamp(0, 255);
      rgba[i * 4 + 1] = (pixel[1] * 255).round().clamp(0, 255);
      rgba[i * 4 + 2] = (pixel[2] * 255).round().clamp(0, 255);
      rgba[i * 4 + 3] = 255;
    }
    return rgba;
  }

  /// Stores the R, G, B (0 to 255) in [pixel] as pixel [index].
  void _store(int index, Float64List pixel) {
    pixel[0] /= 255;
    pixel[1] /= 255;
    pixel[2] /= 255;
    rgbToYcc(pixel);
    luma.values[index] = pixel[0] * 255;
    blue.values[index] = pixel[1] * 255 + 128;
    red.values[index] = pixel[2] * 255 + 128;
  }
}
