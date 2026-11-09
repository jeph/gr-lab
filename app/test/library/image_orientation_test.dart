import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/library/image_orientation.dart';

/// 32×16 baseline JPEG without EXIF, four 16×8 quadrants: red top-left,
/// green top-right, blue bottom-left, yellow bottom-right.
final Uint8List _quad = base64.decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUG'
  'BgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYH'
  'CgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgr/wAAR'
  'CAAQACADAREAAhEBAxEB/8QAFwABAQEBAAAAAAAAAAAAAAAAAAkICv/EABQQAQAAAAAAAAAA'
  'AAAAAAAAAAD/xAAXAQEBAQEAAAAAAAAAAAAAAAAACAoJ/8QAFBEBAAAAAAAAAAAAAAAAAAAA'
  'AP/aAAwDAQACEQMRAD8AxelN38AUoS2wrgINtpjqwA7FGANVAD//2Q==',
);

enum _Q { red, green, blue, yellow }

const List<List<_Q>> _stored = [
  [_Q.red, _Q.green],
  [_Q.blue, _Q.yellow],
];

/// The quadrants as shown for EXIF [orientation], straight from the TIFF 6.0
/// definition of where the stored 0th row and 0th column go.
List<List<_Q>> _shown(int orientation) {
  final d = [
    [_Q.red, _Q.red],
    [_Q.red, _Q.red],
  ];
  for (var r = 0; r < 2; r++) {
    for (var c = 0; c < 2; c++) {
      final (y, x) = switch (orientation) {
        2 => (r, 1 - c), // row 0 top, column 0 right
        3 => (1 - r, 1 - c), // bottom, right
        4 => (1 - r, c), // bottom, left
        5 => (c, r), // row 0 left, column 0 top
        6 => (c, 1 - r), // right, top
        7 => (1 - c, 1 - r), // right, bottom
        8 => (1 - c, r), // left, bottom
        _ => (r, c),
      };
      d[y][x] = _stored[r][c];
    }
  }
  return d;
}

/// Nearest quadrant colour at the centre of each quadrant of [image].
Future<List<List<_Q>>> _quadrants(ui.Image image) async {
  final data = (await image.toByteData())!;
  _Q at(int x, int y) {
    final i = (y * image.width + x) * 4;
    final (r, g, b) = (
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
    return switch ((r > 128, g > 128, b > 128)) {
      (true, false, false) => _Q.red,
      (false, true, false) => _Q.green,
      (false, false, true) => _Q.blue,
      (true, true, false) => _Q.yellow,
      final other => throw StateError('unexpected colour $other'),
    };
  }

  final (w, h) = (image.width, image.height);
  return [
    [at(w ~/ 4, h ~/ 4), at(w * 3 ~/ 4, h ~/ 4)],
    [at(w ~/ 4, h * 3 ~/ 4), at(w * 3 ~/ 4, h * 3 ~/ 4)],
  ];
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// A JPEG whose first segment is an `Exif` APP1 with IFD0 [entries]
/// (tag, type, value) in the given byte order.
Uint8List _exifJpeg(
  List<(int, int, int)> entries, {
  bool bigEndian = false,
  Uint8List? base,
}) {
  final endian = bigEndian ? Endian.big : Endian.little;
  final tiff = ByteData(8 + 2 + entries.length * 12 + 4)
    ..setUint8(0, bigEndian ? 0x4D : 0x49)
    ..setUint8(1, bigEndian ? 0x4D : 0x49)
    ..setUint16(2, 42, endian)
    ..setUint32(4, 8, endian)
    ..setUint16(8, entries.length, endian);
  for (final (i, (tag, type, value)) in entries.indexed) {
    final at = 10 + i * 12;
    tiff
      ..setUint16(at, tag, endian)
      ..setUint16(at + 2, type, endian)
      ..setUint32(at + 4, 1, endian);
    if (type == 3) {
      tiff.setUint16(at + 8, value, endian);
    } else {
      tiff.setUint32(at + 8, value, endian);
    }
  }
  final payload = [...'Exif'.codeUnits, 0, 0, ...tiff.buffer.asUint8List()];
  final length = payload.length + 2;
  final jpeg = base ?? _quad;
  return Uint8List.fromList([
    0xFF, 0xD8, 0xFF, 0xE1, length >> 8, length & 0xFF, ...payload, //
    ...jpeg.sublist(2),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Flutter's JPEG decoder", () {
    test('applies the EXIF Orientation tag itself, for every value', () async {
      for (var o = 1; o <= 8; o++) {
        final image = await _decode(withExifOrientation(_quad, o));
        expect(
          (image.width, image.height),
          o >= 5 ? (16, 32) : (32, 16),
          reason: 'orientation $o',
        );
        expect(await _quadrants(image), _shown(o), reason: 'orientation $o');
      }
    });

    test('shows a JPEG without EXIF as stored', () async {
      final image = await _decode(_quad);
      expect((image.width, image.height), (32, 16));
      expect(await _quadrants(image), _stored);
    });
  });

  group('readJpegLayout', () {
    test('stored size and no tag for a JPEG without EXIF', () {
      final layout = readJpegLayout(_quad)!;
      expect((layout.width, layout.height), (32, 16));
      expect(layout.exifOrientation, isNull);
      expect(layout.decoderOrients, isFalse);
    });

    test('reads the tag as a GR writes it, and in big-endian files', () {
      for (var o = 1; o <= 8; o++) {
        final layout = readJpegLayout(withExifOrientation(_quad, o))!;
        expect(layout.exifOrientation, o);
        expect((layout.width, layout.height), (32, 16));
        expect(layout.decoderOrients, o != 1);
      }
      final big = _exifJpeg([(0x0112, 3, 6)], bigEndian: true);
      expect(readJpegLayout(big)!.exifOrientation, 6);
    });

    test('finds Orientation after other IFD0 entries (Make, Model)', () {
      final jpeg = _exifJpeg([
        (0x010F, 2, 0x1E),
        (0x0110, 2, 0x3E),
        (0x0112, 3, 8),
      ]);
      expect(readJpegLayout(jpeg)!.exifOrientation, 8);
    });

    test('an out-of-range tag is not one the decoder applies', () {
      for (final o in [0, 9, 0x100]) {
        final layout = readJpegLayout(_exifJpeg([(0x0112, 3, o)]))!;
        expect(layout.exifOrientation, o);
        expect(layout.decoderOrients, isFalse, reason: '$o');
      }
    });

    test('skips APP1 segments that are not EXIF', () {
      final xmp = [...'http://ns.adobe.com/xap/1.0/'.codeUnits, 0, 1, 2];
      final withExif = withExifOrientation(_quad, 6);
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE1, 0, xmp.length + 2, ...xmp, //
        ...withExif.sublist(2),
      ]);
      expect(readJpegLayout(jpeg)!.exifOrientation, 6);
    });

    test(
      'the camera-style thumbnails of the fake camera: 3:2, no tag',
      () async {
        final thumb = await syntheticMedia()(
          FakePhoto('100RICOH', 'R0000001.JPG', DateTime(2026), orientation: 6),
          GrImageSize.thumb,
        );
        final layout = readJpegLayout(thumb)!;
        expect((layout.width, layout.height), (24, 16));
        expect(layout.exifOrientation, isNull);
      },
    );

    test('null for bytes that are not a JPEG or are cut short', () {
      expect(readJpegLayout(Uint8List(0)), isNull);
      expect(
        readJpegLayout(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
        isNull,
      );
      final oriented = withExifOrientation(_quad, 6);
      expect(readJpegLayout(oriented.sublist(0, 20)), isNull);
      // Frame header missing: SOS follows the tables directly.
      expect(
        readJpegLayout(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDA, 0, 2])),
        isNull,
      );
      // A segment length running past the end.
      expect(
        readJpegLayout(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x7F, 0])),
        isNull,
      );
    });
  });

  group('orientationToApply', () {
    final landscape = readJpegLayout(_quad);

    test('a landscape image without a tag gets the camera orientation', () {
      for (var o = 1; o <= 8; o++) {
        expect(orientationToApply(landscape, o), o, reason: '$o');
      }
    });

    test('missing or unknown orientation shows the image as stored', () {
      for (final o in [null, 0, 9, -1, 255]) {
        expect(orientationToApply(landscape, o), 1, reason: '$o');
      }
    });

    test('never turns an image the decoder already turns', () {
      for (var tag = 2; tag <= 8; tag++) {
        final layout = readJpegLayout(withExifOrientation(_quad, tag));
        for (var o = 1; o <= 8; o++) {
          expect(orientationToApply(layout, o), 1, reason: 'tag $tag, info $o');
        }
      }
    });

    test('an out-of-range tag (0, 9) does not stop the turn', () {
      for (final tag in [0, 9]) {
        final layout = readJpegLayout(_exifJpeg([(0x0112, 3, tag)]));
        for (var o = 2; o <= 8; o++) {
          expect(orientationToApply(layout, o), o, reason: 'tag $tag, $o');
        }
      }
    });

    test('an explicit tag 1 is trusted unless the frame is visibly on its '
        'side', () {
      final landscape = readJpegLayout(_exifJpeg([(0x0112, 3, 1)]))!;
      // Already upright: a half turn or mirror would apply twice.
      for (final o in [2, 3, 4]) {
        expect(orientationToApply(landscape, o), 1, reason: '$o');
      }
      // A landscape frame of a shot held on its side is not upright.
      for (final o in [5, 6, 7, 8]) {
        expect(orientationToApply(landscape, o), o, reason: '$o');
      }
      const square = JpegLayout(width: 16, height: 16, exifOrientation: 1);
      for (var o = 2; o <= 8; o++) {
        expect(orientationToApply(square, o), 1, reason: 'square, $o');
      }
    });

    test('an image already taller than wide gets no quarter turn', () {
      const tall = JpegLayout(width: 16, height: 24);
      for (final o in [5, 6, 7, 8]) {
        expect(orientationToApply(tall, o), 1, reason: '$o');
      }
      expect(orientationToApply(tall, 3), 3);
      expect(orientationToApply(tall, 2), 2);
    });

    test('bytes without a readable header get the camera orientation', () {
      expect(orientationToApply(null, 6), 6);
    });
  });

  group('decode size', () {
    const cell = Size(390, 390);

    test('a thumbnail smaller than its cell is enlarged and decoded as it '
        'is', () {
      const thumb = JpegLayout(width: 160, height: 120);
      expect(enlargement(thumb, 1, cell, BoxFit.cover), closeTo(3.25, .01));
      expect(decodeWidth(thumb, 1, cell, BoxFit.cover), isNull);
    });

    test('a landscape preview covering a square cell keeps the cell height '
        'in pixels', () {
      const view = JpegLayout(width: 1620, height: 1080);
      expect(enlargement(view, 1, cell, BoxFit.cover), lessThan(1));
      final width = decodeWidth(view, 1, cell, BoxFit.cover)!;
      // Decoding to the cell width would leave 260 rows for 390.
      expect(width, 585);
      expect(width * 1080 / 1620, greaterThanOrEqualTo(cell.height));
    });

    test('a stored frame turned upright counts its stored width', () {
      const view = JpegLayout(width: 1620, height: 1080);
      // Shown 1080×1620: its shorter side, the stored height, fills 390.
      expect(decodeWidth(view, 6, cell, BoxFit.cover), 585);
      // Shown 1080×1620 in 540×1000: half size.
      expect(decodeWidth(view, 6, const Size(540, 1000), BoxFit.contain), 810);
    });

    test('an image the decoder turns counts turned pixels', () {
      const full = JpegLayout(width: 6192, height: 4128, exifOrientation: 6);
      expect(orientationToApply(full, 6), 1);
      // Decoded 4128×6192, fitted into 3240×6000.
      expect(
        decodeWidth(full, 1, const Size(3240, 6000), BoxFit.contain),
        3240,
      );
    });

    test('unknown sizes leave the image as it is', () {
      const view = JpegLayout(width: 1620, height: 1080);
      expect(decodeWidth(null, 1, cell, BoxFit.cover), isNull);
      expect(decodeWidth(view, 1, Size.zero, BoxFit.cover), isNull);
      expect(enlargement(view, 1, Size.infinite, BoxFit.cover), 1);
    });
  });

  group('ExifOrientation', () {
    Future<ui.Image> render(WidgetTester tester, ui.Image image, int o) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: boundary,
            child: ExifOrientation(
              orientation: o,
              child: RawImage(image: image),
            ),
          ),
        ),
      );
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(render.toImage))!;
    }

    testWidgets('shows a stored image as its decoder does with the tag, for '
        'every orientation', (tester) async {
      final stored = (await tester.runAsync(() => _decode(_quad)))!;
      for (var o = 1; o <= 8; o++) {
        final shown = await render(tester, stored.clone(), o);
        final decoded = (await tester.runAsync(
          () => _decode(withExifOrientation(_quad, o)),
        ))!;
        expect(
          (shown.width, shown.height),
          (decoded.width, decoded.height),
          reason: 'orientation $o',
        );
        final (got, want) = (await tester.runAsync(
          () async => (await _quadrants(shown), await _quadrants(decoded)),
        ))!;
        expect(got, want, reason: 'orientation $o');
        expect(got, _shown(o), reason: 'orientation $o');
      }
      stored.dispose();
    });

    testWidgets('bytes and /info together never turn twice: an upright '
        'image tagged 1 stays as it is, a sideways one turns', (tester) async {
      // What the app shows for [bytes] given /info [o]: the decoder's own
      // orientation, then orientationToApply's.
      Future<List<List<_Q>>> show(Uint8List bytes, int o) async {
        final decoded = (await tester.runAsync(() => _decode(bytes)))!;
        final apply = orientationToApply(readJpegLayout(bytes), o);
        final shown = await render(tester, decoded, apply);
        return (await tester.runAsync(() => _quadrants(shown)))!;
      }

      final taggedUpright = withExifOrientation(_quad, 1);
      for (final o in [2, 3, 4]) {
        expect(await show(taggedUpright, o), _stored, reason: 'tag 1, $o');
      }
      for (var o = 2; o <= 8; o++) {
        final tagged = withExifOrientation(_quad, o);
        expect(await show(tagged, o), _shown(o), reason: 'tag $o, info $o');
        expect(await show(_quad, o), _shown(o), reason: 'no tag, info $o');
      }
      expect(await show(taggedUpright, 6), _shown(6), reason: 'tag 1, 6');
    });

    testWidgets('lays out with the upright aspect ratio', (tester) async {
      await tester.pumpWidget(
        const Center(
          child: ExifOrientation(
            orientation: 6,
            child: SizedBox(width: 30, height: 20),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ExifOrientation)), const Size(20, 30));
    });
  });
}
