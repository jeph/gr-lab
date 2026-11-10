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

  test('blending between the entries of a table of the usual size gives '
      'what the renderer gives, within 2 codes for all but one colour in '
      'fifty', () {
    // A pair of looks whose colours bend sharply where channels clip.
    var source = Look.onBase(LookBase.positiveFilm);
    for (final MapEntry(:key, :value) in {
      LookParameter.key: -1,
      LookParameter.contrast: 3,
      LookParameter.contrastHigh: -1,
      LookParameter.contrastLow: -2,
    }.entries) {
      source = source.withValue(key, value);
    }
    final lut = LookRerender(_renderer, source: source).lutFor(_standard);
    final decode = _renderer.decoder(source)!;
    final encode = _renderer.encoder(_standard)!;
    final top = lut.size - 1;
    final exact = Float64List(3);
    var colours = 0;
    var far = 0;
    for (var r = 0; r <= 255; r += 15) {
      for (var g = 0; g <= 255; g += 15) {
        for (var b = 0; b <= 255; b += 15) {
          exact[0] = r / 255;
          exact[1] = g / 255;
          exact[2] = b / 255;
          decode(exact);
          encode(exact);
          final blended = _blend(
            lut,
            r / 255 * top,
            g / 255 * top,
            b / 255 * top,
          );
          colours++;
          for (var channel = 0; channel < 3; channel++) {
            if ((blended[channel] - exact[channel] * 255).abs() > 2) {
              far++;
              break;
            }
          }
        }
      }
    }
    expect(far / colours, lessThan(0.02));
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

/// The colour at the fractional steps ([r], [g], [b]) of [lut], blended
/// from the eight entries around it as the app's shader does.
List<double> _blend(LookLut lut, double r, double g, double b) {
  final lowR = r.floor().clamp(0, lut.size - 2);
  final lowG = g.floor().clamp(0, lut.size - 2);
  final lowB = b.floor().clamp(0, lut.size - 2);
  final out = [0.0, 0.0, 0.0];
  for (var corner = 0; corner < 8; corner++) {
    final upR = corner & 1;
    final upG = (corner >> 1) & 1;
    final upB = corner >> 2;
    final weight =
        (upR == 1 ? r - lowR : 1 - (r - lowR)) *
        (upG == 1 ? g - lowG : 1 - (g - lowG)) *
        (upB == 1 ? b - lowB : 1 - (b - lowB));
    final (er, eg, eb) = lut.at(lowR + upR, lowG + upG, lowB + upB);
    out[0] += weight * er;
    out[1] += weight * eg;
    out[2] += weight * eb;
  }
  return out;
}
