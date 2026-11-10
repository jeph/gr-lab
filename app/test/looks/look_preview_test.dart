import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/src/looks/look_preview.dart';

import '../support/test_app.dart';

/// A [width] by [height] picture of [pixel] over and over.
Future<ui.Image> _filled(int width, int height, List<int> pixel) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList([for (var i = 0; i < width * height; i++) ...pixel]),
    width,
    height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// A table of [size] steps per channel whose entry for steps (r, g, b),
/// each 0..1, is [colourOf] of them.
LookLut _table(
  int size,
  (double, double, double) Function(double r, double g, double b) colourOf,
) {
  final lut = LookLut.identity(size: size);
  final rgba = Uint8List.fromList(lut.rgba);
  final top = size - 1;
  for (var g = 0; g < size; g++) {
    for (var b = 0; b < size; b++) {
      for (var r = 0; r < size; r++) {
        final (red, green, blue) = colourOf(r / top, g / top, b / top);
        final at = ((g * size + b) * size + r) * 4;
        rgba[at] = (red * 255).round();
        rgba[at + 1] = (green * 255).round();
        rgba[at + 2] = (blue * 255).round();
      }
    }
  }
  return LookLut(size, rgba);
}

void main() {
  const boundary = Key('boundary');

  /// The colour [photo] is drawn in through [lut], at the middle of a box.
  Future<List<int>> drawn(
    WidgetTester tester,
    List<int> photo,
    LookLut lut,
  ) async {
    final image = MemoryImage(
      (await tester.runAsync(() async {
        final picture = await _filled(12, 8, photo);
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        return png!.buffer.asUint8List();
      }))!,
    );
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 40,
            height: 60,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LookPreview(image: image, lut: lut),
            ),
          ),
        ),
      ),
    );
    await pumpUntilFound(tester, find.byType(CustomPaint));
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    final pixels = (await tester.runAsync(() async {
      final shot = await render.toImage();
      final bytes = await shot.toByteData();
      final at = (shot.height ~/ 2 * shot.width + shot.width ~/ 2) * 4;
      return bytes!.buffer.asUint8List().sublist(at, at + 4);
    }))!;
    return pixels;
  }

  Matcher near(List<int> colour) => pairwiseCompare<int, int>(
    colour,
    (wanted, actual) => (wanted - actual).abs() <= 2,
    'within 2 of',
  );

  testWidgets('a table that changes nothing draws the photo as it is', (
    tester,
  ) async {
    final pixel = await drawn(tester, [200, 100, 50, 255], LookLut.identity());
    expect(pixel, near([200, 100, 50, 255]));
  });

  testWidgets("each pixel is drawn in the table's colour for it, blended "
      'between the entries around it', (tester) async {
    // Red read from the photo's blue, green from its red, blue from its
    // green: a table read with two channels swapped, or its rows in the
    // wrong order, gives another colour.
    final swapped = _table(3, (r, g, b) => (b, r, g));
    expect(
      await drawn(tester, [200, 100, 50, 255], swapped),
      near([50, 200, 100, 255]),
    );
  });

  testWidgets('a table that bends colours is followed between its entries '
      "and at both ends of a channel's range", (tester) async {
    final squared = _table(5, (r, g, b) => (r * r, 1 - g, b));
    // Red 160 lies between the entries for 128 (64) and 191 (143).
    expect(
      await drawn(tester, [160, 0, 255, 255], squared),
      near([104, 255, 255, 255]),
    );
  });
}
