import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/library/image_orientation.dart';
import 'package:grlab/src/looks/look_photo.dart';
import 'package:image/image.dart' as img;

/// A JPEG of [width] by [height] pixels, red on its left half and blue on
/// its right.
Uint8List _jpeg(int width, int height) {
  final picture = img.Image(width: width, height: height);
  for (final pixel in picture) {
    if (pixel.x < width / 2) {
      pixel.setRgb(200, 40, 40);
    } else {
      pixel.setRgb(40, 40, 200);
    }
  }
  return img.encodeJpg(picture);
}

Matcher _near(int r, int g, int b) => predicate<img.Pixel>(
  (p) => (p.r - r).abs() < 12 && (p.g - g).abs() < 12 && (p.b - b).abs() < 12,
  'near ($r, $g, $b)',
);

void main() {
  testWidgets('a photo larger than a look keeps is made a smaller JPEG of '
      'the same shape and picture', (tester) async {
    final full = _jpeg(400, 200);
    final kept = (await tester.runAsync(
      () => lookPhotoOf(full, longSide: 100),
    ))!;
    expect(readJpegLayout(kept), isNotNull, reason: 'a JPEG');
    final picture = img.decodeJpg(kept)!;
    expect((picture.width, picture.height), (100, 50));
    expect(picture.getPixel(20, 25), _near(200, 40, 40));
    expect(picture.getPixel(80, 25), _near(40, 40, 200));
    expect(kept.length, lessThan(full.length));

    final tall = (await tester.runAsync(
      () => lookPhotoOf(_jpeg(90, 300), longSide: 100),
    ))!;
    final tallPicture = img.decodeJpg(tall)!;
    expect((tallPicture.width, tallPicture.height), (30, 100));
  });

  testWidgets('a photo held on its side is kept as its tag turns it, with '
      'no tag of its own', (tester) async {
    // Stored 400 by 200; orientation 6 turns the left half to the top.
    final full = withExifOrientation(_jpeg(400, 200), 6);
    expect(readJpegLayout(full)!.exifOrientation, 6);
    final kept = (await tester.runAsync(
      () => lookPhotoOf(full, longSide: 100),
    ))!;
    expect(readJpegLayout(kept)!.exifOrientation, isNull);
    final picture = img.decodeJpg(kept)!;
    expect((picture.width, picture.height), (50, 100));
    expect(picture.getPixel(25, 20), _near(200, 40, 40));
    expect(picture.getPixel(25, 80), _near(40, 40, 200));
  });

  testWidgets('a photo no larger than a look keeps is kept as it is', (
    tester,
  ) async {
    final exact = _jpeg(100, 60);
    expect(
      await tester.runAsync(() => lookPhotoOf(exact, longSide: 100)),
      same(exact),
    );
    final small = _jpeg(40, 60);
    expect(
      await tester.runAsync(() => lookPhotoOf(small, longSide: 100)),
      same(small),
    );
  });

  testWidgets('bytes that are no picture give none', (tester) async {
    final broken = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9, 1, 2, 3]);
    expect(
      await tester.runAsync(() => lookPhotoOf(broken, longSide: 100)),
      isNull,
    );
    expect(
      await tester.runAsync(() => lookPhotoOf(Uint8List(0), longSide: 100)),
      isNull,
    );
  });
}
