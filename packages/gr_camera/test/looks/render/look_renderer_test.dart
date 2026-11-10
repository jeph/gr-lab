import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';

final LookRenderer _renderer = lookRendererFor(CameraBody.unknown);
final Look _standard = Look.onBase(LookBase.standard);
final Look _vivid = Look.onBase(LookBase.vivid);

void main() {
  test('a table that changes nothing holds each input at its own place', () {
    final lut = LookLut.identity(size: 5);
    expect(lut.rgba, hasLength(5 * 5 * 5 * 4));
    expect(lut.at(0, 0, 0), (0, 0, 0));
    expect(lut.at(4, 2, 1), (255, 128, 64));
    // Column b · size + r of row g.
    const pixel = (2 * 25 + 1 * 5 + 4) * 4;
    expect(lut.rgba.sublist(pixel, pixel + 4), [255, 128, 64, 255]);
  });

  test('a table shows the photo under the target look: Vivid deepens a '
      'red and leaves grey grey', () {
    final lut = LookRerender(
      _renderer,
      source: _standard,
      size: 9,
    ).lutFor(_vivid);
    expect(lut.size, 9);
    final (greyR, greyG, greyB) = lut.at(4, 4, 4);
    expect(greyR, closeTo(greyG, 1));
    expect(greyB, closeTo(greyG, 1));
    final (r, g, b) = lut.at(6, 2, 2);
    expect(r, greaterThan(191));
    expect(g, lessThan(64));
    expect(b, lessThan(64));
    for (var i = 3; i < lut.rgba.length; i += 4) {
      expect(lut.rgba[i], 255, reason: 'opaque');
    }
  });

  test('a photo whose look is not known is taken to be Standard, and says '
      'so', () {
    final unknown = LookRerender(_renderer, source: null, size: 5);
    final standard = LookRerender(_renderer, source: _standard, size: 5);
    expect(unknown.fitFor(_vivid), LookSourceFit.unknown);
    expect(standard.fitFor(_vivid), LookSourceFit.good);
    expect(unknown.lutFor(_vivid).rgba, standard.lutFor(_vivid).rgba);
  });

  test('a photo that cannot be shown under the target look, or a target '
      'base GR Lab does not know, leaves the photo as it is', () {
    final identity = LookLut.identity(size: 5).rgba;
    final monotone = LookRerender(
      _renderer,
      source: Look.onBase(LookBase.monotone),
      size: 5,
    );
    expect(monotone.fitFor(_vivid), LookSourceFit.unusable);
    expect(monotone.lutFor(_vivid).rgba, identity);
    final hdr = LookRerender(
      _renderer,
      source: Look.onBase(LookBase.hdrTone),
      size: 5,
    );
    expect(hdr.lutFor(_vivid).rgba, identity);
    final unknownBase = Look.fromBytes(Uint8List.fromList([1, 0, 0x7f, 0]))!;
    final standard = LookRerender(_renderer, source: _standard, size: 5);
    expect(standard.lutFor(unknownBase).rgba, identity);
  });
}
