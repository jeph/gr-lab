import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_camera/src/looks/render/gr4/gr4_look_renderer.dart';
import 'package:gr_camera/src/looks/render/gr4/gr4_tone.dart';
import 'package:gr_camera/src/looks/render/render_planes.dart';

import 'gr4_effects_reference.dart';
import 'gr4_reference.dart';

const _renderer = Gr4LookRenderer();

Look _look(LookBase base, [Map<LookParameter, int> values = const {}]) {
  var look = Look.onBase(base);
  for (final MapEntry(:key, :value) in values.entries) {
    look = look.withValue(key, value);
  }
  return look;
}

final Look _standard = _look(LookBase.standard);

/// [colour] (8-bit) of a photo developed with [source], under [target].
List<double> _render(Look source, Look target, List<int> colour) {
  final v = Float64List.fromList([for (final c in colour) c / 255]);
  _renderer.decoder(source)!(v);
  _renderer.encoder(target)!(v);
  return [for (final c in v) c * 255];
}

double _grey(Look target, int level) =>
    _render(_standard, target, [level, level, level])[1];

double _chroma(List<double> rgb) =>
    rgb.reduce((a, b) => a > b ? a : b) - rgb.reduce((a, b) => a < b ? a : b);

void main() {
  test("the tone curve is within half an 8-bit code of the camera's for "
      'every reference setting of the four tone sliders', () {
    for (final (:steps, :curve) in referenceTones) {
      final ours = gr4ToneCurve(
        key: steps[0],
        contrast: steps[1],
        highlight: steps[2],
        shadow: steps[3],
      );
      for (var i = 0; i < referenceTonePoints.length; i++) {
        final point = referenceTonePoints[i];
        expect(
          ours[point] * 255 / gr4CurveWhite,
          closeTo(curve[i] * 255 / gr4CurveWhite, 0.5),
          reason: 'steps $steps, point $point',
        );
      }
    }
  });

  // The curves are fits and the saturation matrix is a formula where the
  // camera holds tables, so the colours agree to within a few codes, not
  // exactly.
  const tolerance = 2.5;
  for (final c in referenceCases) {
    test('${c.name}: every reference colour is within $tolerance 8-bit '
        "codes of what the camera's tables give", () {
      final source = _look(c.source, c.sourceValues);
      final target = _look(c.target, c.targetValues);
      for (var i = 0; i < referenceColours.length; i++) {
        final ours = _render(source, target, referenceColours[i]);
        for (var channel = 0; channel < 3; channel++) {
          expect(
            ours[channel],
            closeTo(c.colours[i][channel], tolerance),
            reason: '${referenceColours[i]} gives $ours, not ${c.colours[i]}',
          );
        }
      }
    });
  }

  test("the Hue slider alone follows the camera's rounded matrices to a "
      'fifth of a code', () {
    final turns = [
      for (final c in referenceCases)
        if (c.source == LookBase.standard &&
            c.sourceValues.isEmpty &&
            c.target == LookBase.standard &&
            c.targetValues.length == 1 &&
            c.targetValues.containsKey(LookParameter.hue))
          c,
    ];
    expect(turns, hasLength(4));
    for (final c in turns) {
      final target = _look(c.target, c.targetValues);
      for (var i = 0; i < referenceColours.length; i++) {
        final ours = _render(_standard, target, referenceColours[i]);
        for (var channel = 0; channel < 3; channel++) {
          expect(
            ours[channel],
            closeTo(c.colours[i][channel], 0.2),
            reason: '${c.name}: ${referenceColours[i]} gives $ours',
          );
        }
      }
    }
  });

  /// Checks that [look]'s table for a photo of its own leaves every entry
  /// from step [first] to step [last] of 17 as it is.
  void expectUnchanged(Look look, {int first = 0, int last = 16}) {
    final lut = LookRerender(_renderer, source: look, size: 17).lutFor(look);
    for (var r = first; r <= last; r++) {
      for (var g = first; g <= last; g++) {
        for (var b = first; b <= last; b++) {
          final (outR, outG, outB) = lut.at(r, g, b);
          final reason = '${look.base} at $r, $g, $b';
          expect(outR, closeTo(r * 255 / 16, 1), reason: reason);
          expect(outG, closeTo(g * 255 / 16, 1), reason: reason);
          expect(outB, closeTo(b * 255 / 16, 1), reason: reason);
        }
      }
    }
  }

  test('a photo shown under the look it was developed with is unchanged, '
      'over the whole colour cube', () {
    expectUnchanged(_standard);
    expectUnchanged(
      _look(LookBase.positiveFilm, {
        LookParameter.key: -1,
        LookParameter.contrast: 3,
        LookParameter.contrastHigh: -1,
        LookParameter.contrastLow: -2,
      }),
    );
  });

  test('a photo with less saturation and a turned hue is unchanged under '
      'its own look for the colours such a photo can hold', () {
    // Lowering saturation leaves the cube's outer colours unused; they
    // have nothing to be undone to.
    expectUnchanged(
      _look(LookBase.vivid, {
        LookParameter.saturation: -2,
        LookParameter.hue: 1,
        LookParameter.contrast: 1,
      }),
      first: 5,
      last: 11,
    );
  });

  test('each tone slider moves the side of mid-grey the camera moves, '
      'brighter for a positive step', () {
    double at(LookParameter slider, int step, int level) =>
        _grey(_look(LookBase.standard, {slider: step}), level);

    // High/Low Key moves everything.
    expect(at(LookParameter.key, 4, 128), greaterThan(160));
    expect(at(LookParameter.key, -4, 128), lessThan(100));
    // Contrast pivots on mid-grey: shadows down and highlights up.
    expect(at(LookParameter.contrast, 4, 119), closeTo(119, 2));
    expect(at(LookParameter.contrast, 4, 40), lessThan(30));
    expect(at(LookParameter.contrast, 4, 200), greaterThan(210));
    expect(at(LookParameter.contrast, -4, 40), greaterThan(50));
    // Highlight and Shadow each leave the other side alone.
    expect(at(LookParameter.contrastHigh, 4, 200), greaterThan(203));
    expect(at(LookParameter.contrastHigh, -4, 200), lessThan(197));
    expect(at(LookParameter.contrastHigh, 4, 40), closeTo(40, 0.5));
    expect(at(LookParameter.contrastLow, 4, 40), greaterThan(43));
    expect(at(LookParameter.contrastLow, -4, 40), lessThan(37));
    expect(at(LookParameter.contrastLow, 4, 200), closeTo(200, 0.5));
  });

  test('every slider renders at both ends of its range, and saturation '
      'scales colour by 1.1 a step', () {
    const red = [204, 51, 38];
    for (final slider in [
      LookParameter.saturation,
      LookParameter.hue,
      LookParameter.key,
      LookParameter.contrast,
      LookParameter.contrastHigh,
      LookParameter.contrastLow,
    ]) {
      for (final step in [-4, 4]) {
        final out = _render(
          _standard,
          _look(LookBase.standard, {slider: step}),
          red,
        );
        expect(out.every((c) => c >= 0 && c <= 255), isTrue, reason: '$slider');
        expect(
          out,
          isNot(_render(_standard, _standard, red)),
          reason: '$slider',
        );
      }
    }
    const dull = [140, 120, 110];
    final plain = _chroma(_render(_standard, _standard, dull));
    final more = _chroma(
      _render(
        _standard,
        _look(LookBase.standard, {LookParameter.saturation: 4}),
        dull,
      ),
    );
    final less = _chroma(
      _render(
        _standard,
        _look(LookBase.standard, {LookParameter.saturation: -4}),
        dull,
      ),
    );
    expect(more / plain, closeTo(1.4641, 0.01));
    expect(less / plain, closeTo(1 / 1.4641, 0.01));
  });

  test("a value outside a slider's range renders as the nearest step", () {
    final beyond = _look(LookBase.standard, {LookParameter.key: 9});
    final most = _look(LookBase.standard, {LookParameter.key: 4});
    expect(_grey(beyond, 128), _grey(most, 128));
  });

  test("a value outside HDR Tone's toning choices renders as the nearest "
      'one', () {
    const orange = [242, 115, 26];
    List<double> toned(int toning) => _render(
      _standard,
      _look(LookBase.hdrTone, {LookParameter.toningHdr: toning}),
      orange,
    );
    expect(toned(-1), toned(0), reason: 'under Off');
    expect(toned(7), toned(2), reason: 'over Sepia');
    expect(toned(2), isNot(toned(1)));
    expect(toned(1), isNot(toned(0)));
  });

  test('a colour photo with moderate settings can be undone well', () {
    for (final source in [
      _standard,
      _look(LookBase.vivid, {LookParameter.contrast: 1}),
      _look(LookBase.positiveFilm, {
        LookParameter.contrast: 3,
        LookParameter.key: -1,
      }),
      _look(LookBase.cineGreen, {LookParameter.saturation: -2}),
      _look(LookBase.retro, {LookParameter.key: 2}),
      _look(LookBase.standard, {LookParameter.key: 3}),
      _look(LookBase.standard, {
        LookParameter.contrast: 4,
        LookParameter.contrastHigh: 4,
      }),
      // Darkening Shading and Clarity are taken out of the picture again.
      _look(LookBase.standard, {LookParameter.shading: -4}),
      _look(LookBase.standard, {LookParameter.clarity: 2}),
    ]) {
      expect(
        _renderer.sourceFit(source, _standard),
        LookSourceFit.good,
        reason: '${source.base}',
      );
    }
  });

  test('a photo whose look threw information away, or added grain, can '
      'only be undone roughly', () {
    for (final source in [
      _look(LookBase.bleachBypass),
      _look(LookBase.crossProcess),
      _look(LookBase.standard, {LookParameter.saturation: -3}),
      // Tone sliders that put white under nine tenths of the range: High/Low
      // Key alone at +4, or less of it with Contrast or Contrast (Highlight).
      _look(LookBase.standard, {LookParameter.key: 4}),
      _look(LookBase.standard, {
        LookParameter.key: 2,
        LookParameter.contrast: 4,
      }),
      _look(LookBase.standard, {
        LookParameter.key: 3,
        LookParameter.contrastHigh: 4,
      }),
      // Shading that brightens the corners may have clipped them.
      _look(LookBase.standard, {LookParameter.shading: 1}),
      _look(LookBase.positiveFilm, {LookParameter.grain: 1}),
    ]) {
      expect(
        _renderer.sourceFit(source, _standard),
        LookSourceFit.rough,
        reason: '${source.base} ${source.values}',
      );
    }
  });

  test('what a look does to the picture as a whole is taken out of a '
      'photo and put into one only when there is something to do', () {
    final shaded = _look(LookBase.standard, {LookParameter.shading: -2});
    final grained = _look(LookBase.vivid, {LookParameter.grain: 1});
    final hdr = _look(LookBase.hdrTone, {LookParameter.hdrStrength: 2});
    expect(_renderer.unfilter(_standard), isNull);
    expect(_renderer.unfilter(grained), isNull, reason: 'grain stays in');
    expect(_renderer.unfilter(shaded), isNotNull);
    expect(_renderer.filter(_standard, source: shaded), isNull);
    expect(_renderer.filter(shaded, source: _standard), isNotNull);
    expect(_renderer.filter(grained, source: grained), isNull);
    expect(_renderer.filter(grained, source: _standard), isNotNull);
    expect(_renderer.filter(hdr, source: _standard), isNotNull);
    expect(_renderer.pictureLongSide, 1548);
  });

  test("a look's grain is put into a picture as the picture's share of "
      'the frame shows it, less the grain its photo already has', () {
    Look grained(int strength) => _look(LookBase.standard, {
      LookParameter.grain: 1,
      LookParameter.grainStrength: strength,
      LookParameter.grainSize: 1,
    });
    // The deviation of the luma of a mid-grey picture afterwards.
    double added(Look source, {int width = 774, int height = 516}) {
      final picture = LookPicture(width, height);
      for (final plane in [picture.luma, picture.blue, picture.red]) {
        plane.values.fillRange(0, width * height, 128);
      }
      _renderer.filter(grained(2), source: source)!(picture);
      var sum = 0.0;
      for (final v in picture.luma.values) {
        sum += (v - 128) * (v - 128);
      }
      return math.sqrt(sum / (width * height));
    }

    // 774 pixels are an eighth of the frame.
    final whole = added(_standard);
    expect(whole / grainDeviationAtEighth[1], closeTo(1, 0.03));
    expect(added(_standard, width: 387, height: 258), lessThan(0.7 * whole));
    // Intensity Medium's grain is half High's, and deviations add as
    // squares: three quarters of High's square are still to come.
    expect(added(grained(1)) / whole, closeTo(math.sqrt(3) / 2, 0.03));
  });

  test("a photo's brightest pixels are taken as the point where its look "
      'clipped, so neighbouring highlights stay neighbours', () {
    // Undoing the toning leaves these channels a little above the top of
    // the photo's curve, one pixel more than the next.
    final bleach = _look(LookBase.bleachBypass, {
      LookParameter.key: 4,
      LookParameter.contrast: 4,
      LookParameter.contrastHigh: 4,
      LookParameter.toningBleachBypass: 1,
    });
    final darker = _look(LookBase.standard, {LookParameter.key: -4});
    for (final (source, target, first, second) in [
      (bleach, _standard, [243, 255, 255], [242, 255, 255]),
      (_standard, darker, [191, 255, 190], [191, 255, 191]),
      (_standard, darker, [255, 255, 255], [254, 254, 254]),
    ]) {
      final a = _render(source, target, first);
      final b = _render(source, target, second);
      for (var channel = 0; channel < 3; channel++) {
        expect(
          a[channel],
          closeTo(b[channel], 6),
          reason: '$first gives $a and $second gives $b',
        );
      }
    }
  });

  test('a black-and-white photo serves another black-and-white look '
      'roughly and a colour look not at all', () {
    final monotone = _look(LookBase.monotone);
    final sepiaHdr = _look(LookBase.hdrTone, {LookParameter.toningHdr: 2});
    expect(
      _renderer.sourceFit(monotone, _look(LookBase.hardMonotone)),
      LookSourceFit.rough,
    );
    expect(_renderer.sourceFit(monotone, sepiaHdr), LookSourceFit.rough);
    expect(_renderer.sourceFit(monotone, _standard), LookSourceFit.unusable);
    expect(
      _renderer.sourceFit(_look(LookBase.grainy), _look(LookBase.solid)),
      LookSourceFit.rough,
    );
    // Its tones carry over: mid-grey stays mid-grey, and a harder look
    // spreads the tones either side of it.
    final harder = _look(LookBase.hardMonotone, {LookParameter.contrast: 3});
    expect(
      _render(monotone, _look(LookBase.hardMonotone), [119, 119, 119])[1],
      closeTo(119, 1.5),
    );
    expect(_render(monotone, harder, [60, 60, 60])[1], lessThan(55));
    expect(_render(monotone, harder, [190, 190, 190])[1], greaterThan(195));
  });

  /// [base] with the filter effect on and [red], [green] and [blue] as its
  /// percentages, each split over two bytes as the look holds them.
  Look filtered(LookBase base, int red, int green, int blue) => _look(base, {
    LookParameter.filterEffect: 1,
    LookParameter.filterEffectRedHigh: (red >> 8) & 0xff,
    LookParameter.filterEffectRedLow: red & 0xff,
    LookParameter.filterEffectGreenHigh: (green >> 8) & 0xff,
    LookParameter.filterEffectGreenLow: green & 0xff,
    LookParameter.filterEffectBlueHigh: (blue >> 8) & 0xff,
    LookParameter.filterEffectBlueLow: blue & 0xff,
  });

  test('a black-and-white photo taken through a filter is unchanged under '
      'its own look, whatever its filter values add up to', () {
    // The last number is the brightest level such a photo holds: a filter
    // that adds up to 60 % leaves the top of the range unused.
    for (final (base, red, green, blue, brightest) in [
      (LookBase.monotone, 120, -10, -10, 247),
      (LookBase.monotone, 200, 0, 0, 247),
      (LookBase.softMonotone, 30, 20, 10, 150),
      (LookBase.highContrast, 90, 80, -20, 247),
    ]) {
      final look = filtered(base, red, green, blue);
      for (final level in [8, 40, 119, brightest]) {
        expect(
          _render(look, look, [level, level, level])[1],
          closeTo(level, 1),
          reason: '$base through $red, $green, $blue at $level',
        );
      }
    }
    // Twice the light reached that photo: under the unfiltered look its
    // tones are those of half as much.
    final doubled = filtered(LookBase.monotone, 200, 0, 0);
    final plain = _look(LookBase.monotone);
    final halved = _render(doubled, plain, [200, 200, 200])[1];
    expect(
      _render(plain, doubled, [
        halved.round(),
        halved.round(),
        halved.round(),
      ])[1],
      closeTo(200, 2),
    );
    expect(halved, lessThan(150));
  });

  test('a photo whose filter values add up to little, nothing or less is '
      'too dark to be undone', () {
    final plain = _look(LookBase.monotone);
    for (final (base, red, green, blue) in [
      (LookBase.monotone, 0, 0, 0),
      (LookBase.monotone, 50, -30, -20),
      (LookBase.softMonotone, 20, 0, 0),
      (LookBase.highContrast, -100, 0, 0),
      // A quarter exactly, however the values are spread.
      (LookBase.monotone, 25, 0, 0),
      (LookBase.monotone, 13, 6, 6),
      (LookBase.monotone, 10, 10, 5),
    ]) {
      final look = filtered(base, red, green, blue);
      final reason = '$base through $red, $green, $blue';
      expect(_renderer.decoder(look), isNull, reason: reason);
      expect(
        _renderer.sourceFit(look, plain),
        LookSourceFit.unusable,
        reason: reason,
      );
    }
    expect(
      _renderer.decoder(filtered(LookBase.monotone, 26, 0, 0)),
      isNotNull,
      reason: 'just over a quarter',
    );
  });

  test('HDR Tone, Solarized Effect and bases GR Photo does not know cannot '
      'be undone', () {
    final unknownBase = Look.fromBytes(Uint8List.fromList([1, 0, 0x7f, 0]))!;
    for (final source in [
      _look(LookBase.hdrTone),
      _look(LookBase.hdrMono),
      _look(LookBase.solarization),
      _look(LookBase.palette),
      unknownBase,
    ]) {
      expect(
        _renderer.sourceFit(source, _standard),
        LookSourceFit.unusable,
        reason: '${source.base}',
      );
      expect(_renderer.decoder(source), isNull, reason: '${source.base}');
    }
    expect(_renderer.encoder(unknownBase), isNull);
    expect(_renderer.encoder(_look(LookBase.palette)), isNull);
  });
}
