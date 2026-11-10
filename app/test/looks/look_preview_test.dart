import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

final LookRenderer _renderer = lookRendererFor(CameraBody.unknown);
final Look _standard = Look.onBase(LookBase.standard);

/// A photo that has not loaded until [arrive] gives it its picture.
class _LatePhoto extends ImageProvider<_LatePhoto> {
  final Completer<ImageInfo> _loaded = Completer<ImageInfo>();

  void arrive(ui.Image picture) => _loaded.complete(ImageInfo(image: picture));

  @override
  Future<_LatePhoto> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_LatePhoto>(this);

  @override
  ImageStreamCompleter loadImage(_LatePhoto key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_loaded.future);
}

void main() {
  const boundary = Key('boundary');

  /// A [width] by [height] photo of [pixel] all over.
  Future<ImageProvider> photoOf(
    WidgetTester tester,
    List<int> pixel, {
    int width = 12,
    int height = 8,
  }) async => MemoryImage(
    (await tester.runAsync(() async {
      final picture = await _filled(width, height, pixel);
      final png = await picture.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    }))!,
  );

  /// Shows [child] in a box of [width] by [height].
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    double width = 40,
    double height = 60,
  }) => tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: width,
          height: height,
          child: Directionality(textDirection: TextDirection.ltr, child: child),
        ),
      ),
    ),
  );

  /// The colour drawn [across] and [down] the box, each 0..1.
  Future<List<int>> colourAt(
    WidgetTester tester, {
    double across = 0.5,
    double down = 0.5,
  }) async {
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    return (await tester.runAsync(() async {
      final shot = await render.toImage();
      final bytes = await shot.toByteData();
      final x = (across * (shot.width - 1)).round();
      final y = (down * (shot.height - 1)).round();
      final at = (y * shot.width + x) * 4;
      return bytes!.buffer.asUint8List().sublist(at, at + 4);
    }))!;
  }

  /// The colour [photo] is drawn in through [lut], at the middle of a box.
  Future<List<int>> drawn(
    WidgetTester tester,
    List<int> photo,
    LookLut lut,
  ) async {
    final image = await photoOf(tester, photo);
    await show(tester, LookTableView(image: image, lut: lut));
    await pumpUntilFound(tester, find.byType(CustomPaint));
    return await colourAt(tester);
  }

  Matcher near(List<int> colour, {int within = 2}) => pairwiseCompare<int, int>(
    colour,
    (wanted, actual) => (wanted - actual).abs() <= within,
    'within $within of',
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

  testWidgets('a table moved to another photo draws nothing until that '
      'photo has loaded, not the photo before through the new table', (
    tester,
  ) async {
    final first = await photoOf(tester, [200, 100, 50, 255]);
    final second = _LatePhoto();
    final swapped = _table(5, (r, g, b) => (b, r, g));
    await show(
      tester,
      LookTableView(image: first, lut: LookLut.identity(size: 5)),
    );
    await pumpUntilFound(tester, find.byType(CustomPaint));

    await show(tester, LookTableView(image: second, lut: swapped));
    await tester.pump();
    expect(find.byType(CustomPaint), findsNothing);

    second.arrive(
      (await tester.runAsync(() => _filled(12, 8, [0, 255, 0, 255])))!,
    );
    await pumpUntilFound(tester, find.byType(CustomPaint));
    expect(await colourAt(tester), near([0, 0, 255, 255]));
  });

  group('a look', () {
    Look shaded(int step) => _standard.withValue(LookParameter.shading, step);

    testWidgets('of colour and tone alone is drawn through its table', (
      tester,
    ) async {
      final image = await photoOf(tester, [200, 100, 50, 255]);
      final rerender = LookRerender(_renderer, source: _standard);
      final vivid = Look.onBase(LookBase.vivid);
      await show(
        tester,
        LookPreview(image: image, rerender: rerender, look: vivid),
      );
      await pumpUntilFound(tester, find.byType(CustomPaint));
      expect(find.byType(RawImage), findsNothing);
      expect(
        tester.widget<LookTableView>(find.byType(LookTableView)).lut.rgba,
        rerender.lutFor(vivid).rgba,
      );
      final table = rerender.lutFor(vivid);
      // 200, 100, 50 lies on no entry of a 49-step table, but near these.
      final (r, g, b) = table.at(38, 19, 10);
      expect(await colourAt(tester), near([r, g, b, 255], within: 6));
      expect(await colourAt(tester), isNot(near([200, 100, 50, 255])));
    });

    testWidgets('that shades the picture is worked out as a whole and '
        'takes the place of the table, which comes back when the shading '
        'goes', (tester) async {
      final image = await photoOf(
        tester,
        [200, 100, 50, 255],
        width: 48,
        height: 32,
      );
      final rerender = LookRerender(_renderer, source: _standard);
      Future<void> showUnder(Look look) => show(
        tester,
        LookPreview(image: image, rerender: rerender, look: look),
        width: 60,
        height: 40,
      );

      await showUnder(shaded(-4));
      await pumpUntilFound(tester, find.byType(RawImage));
      expect(find.byType(LookTableView), findsNothing);
      expect(await colourAt(tester), near([200, 100, 50, 255], within: 4));
      // A quarter of the luma (124) at the corner, with the chroma kept.
      expect(
        await colourAt(tester, across: 0, down: 0),
        near([107, 7, 0, 255], within: 8),
      );

      await showUnder(shaded(3));
      await pumpUntil(
        tester,
        () => tester.widget<RawImage>(find.byType(RawImage)).image != null,
      );
      Future<int> cornerRed() async =>
          (await colourAt(tester, across: 0, down: 0))[0];
      for (var i = 0; i < 200 && await cornerRed() < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(await cornerRed(), greaterThan(250), reason: 'twice the luma');

      await showUnder(_standard);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(find.byType(LookTableView), findsOneWidget);
    });

    testWidgets('whose shading goes while a picture is still being worked '
        'out is drawn through its table at once, not as the picture of a '
        'look before', (tester) async {
      final image = await photoOf(
        tester,
        [200, 100, 50, 255],
        width: 48,
        height: 32,
      );
      final rerender = LookRerender(_renderer, source: _standard);
      Future<void> showUnder(Look look) => show(
        tester,
        LookPreview(image: image, rerender: rerender, look: look),
        width: 60,
        height: 40,
      );

      await showUnder(shaded(-4));
      await pumpUntilFound(tester, find.byType(RawImage));
      // Shading +3 starts being worked out, and is not wanted any more
      // before it is done.
      await showUnder(shaded(3));
      await showUnder(_standard);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byType(LookTableView), findsOneWidget);
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('moved to another photo stops showing the picture worked '
        'out for the photo before, and shows the other photo once it has '
        'loaded', (tester) async {
      final first = await photoOf(
        tester,
        [200, 100, 50, 255],
        width: 48,
        height: 32,
      );
      final second = _LatePhoto();
      final plain = LookRerender(_renderer, source: _standard);
      // A photo developed with Shading −4: Standard takes the shading out,
      // so its picture is worked out as a whole too.
      final dark = LookRerender(_renderer, source: shaded(-4));
      Future<void> showing(
        ImageProvider image,
        LookRerender rerender,
        Look look,
      ) => show(
        tester,
        LookPreview(image: image, rerender: rerender, look: look),
        width: 60,
        height: 40,
      );

      await showing(first, plain, shaded(-4));
      await pumpUntilFound(tester, find.byType(RawImage));

      await showing(second, dark, _standard);
      expect(find.byType(RawImage), findsNothing);
      // Long enough for a picture of the first photo to be worked out, if
      // one had been started for the second photo's look.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsNothing);
      expect(find.byType(CustomPaint), findsNothing);

      second.arrive(
        (await tester.runAsync(() => _filled(48, 32, [60, 60, 60, 255])))!,
      );
      await pumpUntilFound(tester, find.byType(RawImage));
      expect(await colourAt(tester), near([60, 60, 60, 255], within: 4));

      // Another photo with the same look to undo and the same look to
      // show: nothing but the photo changes.
      await showing(_LatePhoto(), dark, _standard);
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets("is shown on another photo with that photo's own look "
        'undone', (tester) async {
      final first = await photoOf(tester, [200, 100, 50, 255]);
      final second = await photoOf(
        tester,
        [60, 60, 60, 255],
        width: 48,
        height: 32,
      );
      final plain = LookRerender(_renderer, source: _standard);
      // A photo developed with Shading −4: under Standard its corners
      // come back up, by four times.
      final dark = LookRerender(_renderer, source: shaded(-4));
      await show(
        tester,
        LookPreview(image: first, rerender: plain, look: _standard),
        width: 60,
        height: 40,
      );
      await pumpUntilFound(tester, find.byType(CustomPaint));
      await show(
        tester,
        LookPreview(image: second, rerender: dark, look: _standard),
        width: 60,
        height: 40,
      );
      await pumpUntilFound(tester, find.byType(RawImage));
      expect(await colourAt(tester), near([60, 60, 60, 255], within: 4));
      expect(
        await colourAt(tester, across: 0, down: 0),
        near([240, 240, 240, 255], within: 10),
      );
    });
  });
}
