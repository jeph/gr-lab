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
      'base GR Photo does not know, leaves the photo as it is', () {
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

  group('a whole picture', () {
    const width = 48;
    const height = 32;

    // Soft colours that no look here drives to black or white, nor
    // Shading out of the range of R, G and B.
    Uint8List photo() {
      final rgba = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          rgba[i] = 110 + x;
          rgba[i + 1] = 120 + y;
          rgba[i + 2] = 130 - (x + y) ~/ 4;
          rgba[i + 3] = 7;
        }
      }
      return rgba;
    }

    Look look(LookBase base, Map<LookParameter, int> values) {
      var look = Look.onBase(base);
      for (final MapEntry(:key, :value) in values.entries) {
        look = look.withValue(key, value);
      }
      return look;
    }

    List<int> pixel(Uint8List rgba, int x, int y) =>
        rgba.sublist((y * width + x) * 4, (y * width + x) * 4 + 4);

    int worst(Uint8List a, Uint8List b) {
      var worst = 0;
      for (var i = 0; i < a.length; i++) {
        final d = (a[i] - b[i]).abs();
        if (i % 4 != 3 && d > worst) worst = d;
      }
      return worst;
    }

    test('under a look of colour and tone alone is each pixel put '
        'through the table, opaque', () {
      final rerender = LookRerender(_renderer, source: _standard);
      expect(rerender.filters(_vivid), isFalse);
      final before = photo();
      final out = rerender.render(
        before,
        width: width,
        height: height,
        target: _vivid,
      );
      expect(before, photo(), reason: 'the photo itself is left alone');
      final lut = rerender.lutFor(_vivid);
      final top = lut.size - 1;
      for (final (x, y) in [(0, 0), (47, 31), (13, 20)]) {
        final was = pixel(before, x, y);
        final blended = _blend(
          lut,
          was[0] / 255 * top,
          was[1] / 255 * top,
          was[2] / 255 * top,
        );
        expect(pixel(out, x, y), [
          for (final c in blended) c.round(),
          255,
        ], reason: '$x, $y');
      }
    });

    test("under a look with Shading has the look's colour at the centre "
        'and its corners darkened', () {
      final rerender = LookRerender(_renderer, source: _standard);
      final shaded = look(LookBase.vivid, {LookParameter.shading: -4});
      expect(rerender.filters(shaded), isTrue);
      final plain = rerender.render(
        photo(),
        width: width,
        height: height,
        target: _vivid,
      );
      final out = rerender.render(
        photo(),
        width: width,
        height: height,
        target: shaded,
      );
      for (var c = 0; c < 3; c++) {
        // A quarter of the luma at the corner, and under 1 % off at the
        // two pixels either side of the centre.
        expect(pixel(out, 0, 0)[c], lessThan(pixel(plain, 0, 0)[c] * 0.5));
        expect(
          pixel(out, 24, 16)[c],
          closeTo(pixel(plain, 24, 16)[c], 3),
          reason: 'centre',
        );
      }
    });

    test('developed with Shading and Clarity comes back as it was under '
        'its own look, and as the photo without them under that look', () {
      final settings = {LookParameter.shading: -2, LookParameter.clarity: 3};
      final source = look(LookBase.standard, settings);
      final developed = LookRerender(
        _renderer,
        source: _standard,
      ).render(photo(), width: width, height: height, target: source);
      // Shading −2 halves the luma at the corner, about 134 there, and
      // leaves the chroma.
      expect(
        pixel(developed, 0, 31)[1],
        closeTo(pixel(photo(), 0, 31)[1] - 67, 8),
      );
      final rerender = LookRerender(_renderer, source: source);
      expect(rerender.fitFor(_standard), LookSourceFit.good);
      expect(rerender.filters(source), isTrue);
      expect(rerender.filters(_standard), isTrue);
      final same = rerender.render(
        developed,
        width: width,
        height: height,
        target: source,
      );
      expect(worst(same, developed), lessThan(3));
      final without = rerender.render(
        developed,
        width: width,
        height: height,
        target: _standard,
      );
      expect(worst(without, photo()), lessThan(6));
    });

    test("gets a look's grain once: none when the photo has it "
        'already', () {
      final grainy = look(LookBase.standard, {
        LookParameter.grain: 1,
        LookParameter.grainStrength: 2,
        LookParameter.grainSize: 1,
      });
      final plain = LookRerender(_renderer, source: _standard);
      expect(plain.filters(grainy), isTrue);
      final once = plain.render(
        photo(),
        width: width,
        height: height,
        target: grainy,
      );
      expect(worst(once, photo()), greaterThan(0));
      expect(
        once,
        plain.render(photo(), width: width, height: height, target: grainy),
        reason: 'the same grain each time',
      );
      final already = LookRerender(_renderer, source: grainy);
      expect(already.fitFor(grainy), LookSourceFit.rough);
      expect(already.filters(grainy), isFalse);
      expect(
        worst(
          already.render(photo(), width: width, height: height, target: grainy),
          photo(),
        ),
        lessThan(2),
      );
    });

    test('that cannot be shown under the target look comes back as it '
        'is', () {
      final monotone = LookRerender(
        _renderer,
        source: Look.onBase(LookBase.monotone),
      );
      final shaded = look(LookBase.vivid, {LookParameter.shading: -4});
      expect(monotone.filters(shaded), isFalse);
      expect(
        monotone.render(photo(), width: width, height: height, target: shaded),
        photo(),
      );
    });

    test("is worked on at a quarter of the GR IV's frame", () {
      expect(LookRerender(_renderer, source: null).pictureLongSide, 1548);
    });

    test('is rendered the same after the shared work is done ahead', () {
      final ahead = LookRerender(_renderer, source: _standard)..prepare();
      final late = LookRerender(_renderer, source: _standard);
      expect(ahead.lutFor(_vivid).rgba, late.lutFor(_vivid).rgba);
      LookRerender(_renderer, source: Look.onBase(LookBase.hdrTone)).prepare();
    });
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
