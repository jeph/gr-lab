import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_camera/src/looks/render/gr4/gr4_effects.dart';
import 'package:gr_camera/src/looks/render/render_planes.dart';

import 'gr4_effects_reference.dart';

/// The luma of the picture the reference values were worked out for
/// (`gen_golden.py`), [referenceWidth] by [referenceHeight].
double _testLuma(int x, int y) =>
    (128 +
            70 * math.sin(0.35 * x + 0.2 * y) +
            35 * math.sin(0.07 * x * y) +
            12 * (((7 * x + 13 * y) % 11) - 5) / 5 +
            2.5 * y)
        .clamp(0, 255);

/// A grey picture of [width] by [height] with [luma] at each place.
LookPicture _picture(
  double Function(int x, int y) luma, {
  int width = referenceWidth,
  int height = referenceHeight,
}) {
  final picture = LookPicture(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      picture.luma.values[y * width + x] = luma(x, y);
    }
  }
  picture.blue.values.fillRange(0, width * height, 128);
  picture.red.values.fillRange(0, width * height, 128);
  return picture;
}

/// The luma of the faint picture of the reference values
/// (`gen_golden.py`): neighbours differ by a code or less, which is where
/// HDR Tone's two finest levels have a curve of their own.
double _faintLuma(int x, int y) =>
    128 + 1.2 * math.sin(1.1 * x + 0.7 * y) + 0.8 * math.sin(0.5 * x * y);

/// The largest difference between [picture]'s luma and [reference].
double _worst(LookPicture picture, List<double> reference) {
  var worst = 0.0;
  for (var i = 0; i < reference.length; i++) {
    worst = math.max(worst, (picture.luma.values[i] - reference[i]).abs());
  }
  return worst;
}

double _deviation(Iterable<double> values, {double about = 0}) {
  var sum = 0.0;
  var count = 0;
  for (final v in values) {
    sum += (v - about) * (v - about);
    count++;
  }
  return math.sqrt(sum / count);
}

Look _look(LookBase base, [Map<LookParameter, int> values = const {}]) {
  var look = Look.onBase(base);
  for (final MapEntry(:key, :value) in values.entries) {
    look = look.withValue(key, value);
  }
  return look;
}

/// [effects] applied to the reference picture taken as the frame reduced
/// [scale] times.
LookPicture _applied(Gr4Effects effects, double scale) {
  final picture = _picture(_testLuma);
  effects.apply(picture, scale: scale);
  return picture;
}

/// A picture with gentle tones, which no effect here drives to black or
/// white.
double _gentleLuma(int x, int y) =>
    128 + 30 * math.sin(0.35 * x + 0.2 * y) + 10 * math.sin(0.9 * x * y);

void main() {
  group("against the model that uses the camera's tables", () {
    test('Shading darkens or brightens towards the corners', () {
      expect(
        _worst(_applied(const Gr4Effects(shading: -4), 8), shadingDark),
        lessThan(0.01),
      );
      expect(
        _worst(_applied(const Gr4Effects(shading: 3), 8), shadingBright),
        lessThan(0.01),
      );
    });

    test('Clarity scales the bands of the level the picture is of the '
        'frame, and leaves the trace of the band just finer', () {
      expect(
        _worst(_applied(const Gr4Effects(clarity: 4), 1), clarityFrame),
        lessThan(0.1),
      );
      expect(
        _worst(_applied(const Gr4Effects(clarity: -3), 8), clarityEighth),
        lessThan(0.1),
      );
      expect(
        _worst(_applied(const Gr4Effects(clarity: 2), 64), clarityCoarse),
        lessThan(0.1),
      );
    });

    test('Grainy raises local contrast by its own band gains', () {
      final picture = _picture(_testLuma);
      final bands = gr4Bands(picture.luma, gr4RoughGains, 3);
      for (var i = 0; i < bands.values.length; i++) {
        picture.luma.values[i] = bands.values[i].clamp(0, 255);
      }
      expect(_worst(picture, roughEighth), lessThan(0.1));
    });

    test("HDR Tone follows within half a code with curves of GR Lab's "
        'own', () {
      expect(
        _worst(_applied(const Gr4Effects(hdr: 3), 8), hdrEighthHigh),
        lessThan(0.5),
      );
      expect(
        _worst(_applied(const Gr4Effects(hdr: 1), 2), hdrHalfLow),
        lessThan(0.5),
      );
      expect(
        _worst(_applied(const Gr4Effects(hdr: 2), 1), hdrFrameMedium),
        lessThan(0.5),
      );
      final faint = _picture(_faintLuma);
      const Gr4Effects(hdr: 3).apply(faint, scale: 1);
      expect(_worst(faint, hdrFrameFaint), lessThan(0.05));
    });

    test("grain is as strong as the camera's is once the frame is "
        'averaged down to the picture', () {
      for (var size = 0; size < 3; size++) {
        for (final (kind, reference) in [
          (Gr4GrainKind.colour, grainDeviationAtEighth[size]),
          // The black-and-white bases get twice the colour ones' limit.
          (Gr4GrainKind.grey, 2 * grainDeviationAtEighth[size]),
          (Gr4GrainKind.rough, roughDeviationAtEighth[size]),
        ]) {
          final picture = _picture((x, y) => 128, width: 256, height: 256);
          Gr4Effects(
            grain: Gr4Grain(strength: 2, size: size, kind: kind),
          ).apply(picture, scale: 8);
          expect(
            _deviation(picture.luma.values, about: 128) / reference,
            closeTo(1, 0.03),
            reason: '$kind size $size',
          );
        }
      }
    });
  });

  group('Shading', () {
    test('leaves the centre alone and reaches its full gain at the '
        'corners: half a stop a step down, a third of a stop up', () {
      for (final (step, gain) in [(-4, 0.25), (-1, 0.7071), (3, 2.0)]) {
        final plane = _picture((x, y) => 100, width: 33, height: 21).luma;
        gr4Shade(plane, step);
        expect(plane.values[10 * 33 + 16], 100, reason: 'centre, $step');
        expect(plane.values[0], closeTo(100 * gain, 0.01), reason: '$step');
        expect(
          plane.values[21 * 33 - 1],
          closeTo(100 * gain, 0.01),
          reason: '$step',
        );
        // Half-way out along the long side: a quarter of the way in area.
        final edge = plane.values[10 * 33];
        const share = 16 * 16 / (16 * 16 + 10 * 10);
        expect(edge, closeTo(100 + share * (100 * gain - 100), 0.01));
      }
    });

    test('clips at white and changes nothing at step 0', () {
      final plane = _picture((x, y) => 200, width: 9, height: 9).luma;
      gr4Shade(plane, 4);
      expect(plane.values[0], 255);
      final same = _picture(_testLuma).luma;
      gr4Shade(same, 0);
      expect(same.values, _picture(_testLuma).luma.values);
    });

    test('is taken out again where it did not clip, and a clipped pixel '
        'comes back as the darkest value that would have clipped', () {
      for (final step in [-4, -1, 2, 4]) {
        final plane = _picture(_gentleLuma).luma;
        gr4Shade(plane, step);
        gr4Shade(plane, step, undo: true);
        final was = _picture(_gentleLuma).luma;
        for (var i = 0; i < was.values.length; i++) {
          // +4 clips what was over 255 / 2.52 at the corners.
          if (step == 4 && was.values[i] > 100) continue;
          expect(plane.values[i], closeTo(was.values[i], 0.01), reason: '$i');
        }
      }
      final bright = _picture((x, y) => 240, width: 9, height: 9).luma;
      gr4Shade(bright, 3);
      gr4Shade(bright, 3, undo: true);
      expect(bright.values[0], closeTo(127.5, 0.01), reason: 'corner');
      expect(bright.values[4 * 9 + 4], 240, reason: 'centre');
    });
  });

  group('Clarity', () {
    test('is taken out again by the inverse gains', () {
      for (final step in [-4, -2, 2, 4]) {
        for (final scale in [1.0, 8.0]) {
          final picture = _picture(_gentleLuma);
          Gr4Effects(clarity: step)
            ..apply(picture, scale: scale)
            ..undo(picture, scale: scale);
          expect(
            _worst(picture, _picture(_gentleLuma).luma.values),
            lessThan(1),
            reason: 'step $step at $scale',
          );
        }
      }
    });

    test('raises or lowers local contrast and keeps a flat picture '
        'flat', () {
      final plain = _deviation(_picture(_gentleLuma).luma.values, about: 128);
      double after(int step) => _deviation(
        (_picture(_gentleLuma)
              ..let((p) => Gr4Effects(clarity: step).apply(p, scale: 8)))
            .luma
            .values,
        about: 128,
      );
      expect(after(4), greaterThan(plain * 1.1));
      expect(after(-4), lessThan(plain * 0.9));
      final flat = _picture((x, y) => 77);
      const Gr4Effects(clarity: 4).apply(flat, scale: 8);
      expect(_worst(flat, List.filled(flat.luma.values.length, 77)), 0);
    });

    test("works on the pyramid level nearest the picture's share of the "
        'frame, and on the frame itself for a larger picture', () {
      List<double> at(double scale) =>
          _applied(const Gr4Effects(clarity: 4), scale).luma.values;
      expect(at(11), at(8));
      expect(at(12), at(16));
      expect(at(8), isNot(at(16)));
      expect(at(0.5), at(1));
    });

    test('never leaves 0 to 255', () {
      final picture = _applied(const Gr4Effects(clarity: 4), 8);
      expect(picture.luma.values.every((v) => v >= 0 && v <= 255), isTrue);
      expect(picture.luma.values, contains(255));
    });
  });

  group('grain', () {
    LookPicture grained(
      Gr4Grain grain, {
      double luma = 128,
      Gr4Grain? over,
      double scale = 8,
    }) {
      final picture = _picture((x, y) => luma, width: 128, height: 128);
      Gr4Effects(grain: grain).apply(
        picture,
        scale: scale,
        over: Gr4Effects(grain: over),
      );
      return picture;
    }

    const colour = Gr4Grain(strength: 2, size: 1, kind: Gr4GrainKind.colour);
    const grey = Gr4Grain(strength: 2, size: 1, kind: Gr4GrainKind.grey);
    const rough = Gr4Grain(strength: 2, size: 1, kind: Gr4GrainKind.rough);

    test('is the same every time, so a preview does not flicker', () {
      expect(grained(colour).luma.values, grained(colour).luma.values);
      expect(grained(colour).red.values, grained(colour).red.values);
    });

    test("grows with Intensity and, at a picture's size, with Size", () {
      double luma(int strength, int size) => _deviation(
        grained(
          Gr4Grain(strength: strength, size: size, kind: Gr4GrainKind.colour),
        ).luma.values,
        about: 128,
      );
      expect(luma(0, 1), lessThan(luma(1, 1)));
      expect(luma(1, 1), lessThan(luma(2, 1)));
      expect(luma(2, 0), lessThan(luma(2, 1)));
      expect(luma(2, 1), lessThan(luma(2, 2)));
    });

    test("shows more the closer the picture is to the frame's size", () {
      double at(double scale) =>
          _deviation(grained(colour, scale: scale).luma.values, about: 128);
      // On the frame: the limit of 40 over the root of three, blurred.
      expect(at(1), closeTo(40 / math.sqrt(3) * 0.356, 0.3));
      expect(at(1), greaterThan(at(1.5)));
      expect(at(1.5), greaterThan(at(2)));
      expect(at(2), greaterThan(at(4)));
      expect(at(4), greaterThan(at(8)));
      expect(at(0.5), at(1), reason: 'a picture larger than the frame');
    });

    test('puts noise in the chroma of a colour base only, less of it '
        'near grey, and different in Cb and Cr', () {
      final picture = grained(colour);
      final blue = _deviation(picture.blue.values, about: 128);
      expect(blue, greaterThan(0.2));
      expect(picture.blue.values, isNot(picture.red.values));
      final vivid = _picture((x, y) => 128, width: 128, height: 128);
      vivid.blue.values.fillRange(0, 128 * 128, 180);
      const Gr4Effects(grain: colour).apply(vivid, scale: 8);
      // Limit 9 away from grey, 6 (0.72 of it, cut to a whole) at grey.
      expect(
        _deviation(vivid.blue.values, about: 180) / blue,
        closeTo(9 / 6, 0.1),
      );
      for (final plain in [grained(grey), grained(rough)]) {
        expect(plain.blue.values.every((v) => v == 128), isTrue);
        expect(plain.red.values.every((v) => v == 128), isTrue);
      }
    });

    test('never clips: it moves a pixel by no more than its distance '
        "from black or white, and Grainy's clips instead", () {
      final dark = grained(colour, luma: 3, scale: 1);
      expect(dark.luma.values.every((v) => v > 0 && v < 6), isTrue);
      expect(_deviation(dark.luma.values, about: 3), greaterThan(0.3));
      final black = grained(colour, luma: 0, scale: 1);
      expect(black.luma.values.every((v) => v == 0), isTrue);
      final bright = grained(colour, luma: 253, scale: 1);
      expect(bright.luma.values.every((v) => v > 250 && v < 256), isTrue);
      final roughDark = grained(rough, luma: 3, scale: 1);
      expect(roughDark.luma.values, contains(0));
      expect(roughDark.luma.values.every((v) => v >= 0), isTrue);
      expect(roughDark.luma.values.any((v) => v > 20), isTrue);
    });

    test('adds only what it has beyond the grain already in the photo', () {
      double added(Gr4Grain grain, Gr4Grain? over) =>
          _deviation(grained(grain, over: over).luma.values, about: 128);
      const low = Gr4Grain(strength: 0, size: 1, kind: Gr4GrainKind.colour);
      final full = added(colour, null);
      expect(added(colour, colour), 0);
      expect(added(low, colour), 0, reason: 'the photo has more already');
      final rest = added(colour, low);
      final lows = added(low, null);
      expect(rest, lessThan(full));
      expect(
        rest * rest + lows * lows,
        closeTo(full * full, full * full * 0.02),
        reason: 'deviations add as squares',
      );
    });
  });

  group('HDR Tone', () {
    test('lifts the dark side of a broad step and lowers the bright '
        'side, more at each level', () {
      LookPicture toned(int level) {
        final picture = _picture(
          (x, y) => x < 192 ? 40 : 200,
          width: 384,
          height: 256,
        );
        Gr4Effects(hdr: level).apply(picture, scale: 8);
        return picture;
      }

      double dark(LookPicture p) => p.luma.values[128 * 384 + 64];
      double bright(LookPicture p) => p.luma.values[128 * 384 + 320];
      final low = toned(1);
      final medium = toned(2);
      final high = toned(3);
      expect(dark(low), greaterThan(40.5));
      expect(dark(medium), greaterThan(dark(low)));
      expect(dark(high), greaterThan(dark(medium)));
      expect(bright(low), lessThan(199.5));
      expect(bright(high), lessThan(bright(medium)));
      expect(dark(high) - 40, closeTo(4 * (dark(low) - 40), 0.5));
    });

    test('changes a flat picture by under a hundredth of its level', () {
      final flat = _picture((x, y) => 100);
      const Gr4Effects(hdr: 3).apply(flat, scale: 8);
      expect(
        _worst(flat, List.filled(flat.luma.values.length, 100)),
        lessThan(1),
      );
    });
  });

  group('the effects of a look', () {
    test('are its Shading, Clarity and Grain Effect, limited to the '
        "camera's steps", () {
      final effects = Gr4Effects.of(
        _look(LookBase.positiveFilm, {
          LookParameter.shading: -3,
          LookParameter.clarity: 9,
          LookParameter.grain: 1,
          LookParameter.grainStrength: 2,
          LookParameter.grainSize: 0,
        }),
      );
      expect(effects.shading, -3);
      expect(effects.clarity, 4);
      expect(effects.hdr, 0);
      expect(
        effects.grain,
        const Gr4Grain(strength: 2, size: 0, kind: Gr4GrainKind.colour),
      );
      expect(Gr4Effects.of(_look(LookBase.standard)).grain, isNull);
    });

    test("have the grain of the base's kind", () {
      Gr4GrainKind? kind(LookBase base) =>
          Gr4Effects.of(_look(base, {LookParameter.grain: 1})).grain?.kind;
      expect(kind(LookBase.vivid), Gr4GrainKind.colour);
      expect(kind(LookBase.highContrast), Gr4GrainKind.grey);
      expect(kind(LookBase.standardMono), Gr4GrainKind.grey);
      expect(kind(LookBase.grainy), Gr4GrainKind.rough);
    });

    test('are only the level for an HDR Tone base, which the camera '
        'gives neutral Shading and Clarity and no grain', () {
      for (final base in [LookBase.hdrTone, LookBase.hdrMono]) {
        final effects = Gr4Effects.of(
          _look(base, {LookParameter.hdrStrength: 3}),
        );
        expect((effects.hdr, effects.shading, effects.clarity), (3, 0, 0));
        expect(effects.grain, isNull);
      }
    });

    test("can be undone when there is Shading, Clarity or Grainy's "
        'contrast to take out, and not for grain or HDR Tone alone', () {
      const grain = Gr4Grain(strength: 1, size: 1, kind: Gr4GrainKind.grey);
      const rough = Gr4Grain(strength: 1, size: 1, kind: Gr4GrainKind.rough);
      expect(const Gr4Effects().canUndo, isFalse);
      expect(const Gr4Effects(grain: grain).canUndo, isFalse);
      expect(const Gr4Effects(hdr: 2).canUndo, isFalse);
      expect(const Gr4Effects(shading: 1).canUndo, isTrue);
      expect(const Gr4Effects(clarity: -1).canUndo, isTrue);
      expect(const Gr4Effects(grain: rough).canUndo, isTrue);
    });

    test('change a photo unless they add nothing to what it has', () {
      const grain = Gr4Grain(strength: 1, size: 1, kind: Gr4GrainKind.grey);
      const none = Gr4Effects();
      expect(none.changes(over: none), isFalse);
      expect(const Gr4Effects(shading: 1).changes(over: none), isTrue);
      expect(const Gr4Effects(clarity: 1).changes(over: none), isTrue);
      expect(const Gr4Effects(hdr: 1).changes(over: none), isTrue);
      expect(const Gr4Effects(grain: grain).changes(over: none), isTrue);
      expect(
        const Gr4Effects(grain: grain)
            .changes(over: const Gr4Effects(grain: grain)),
        isFalse,
      );
    });

    test("take Grainy's contrast out of a photo again", () {
      const rough = Gr4Grain(strength: 0, size: 0, kind: Gr4GrainKind.rough);
      final picture = _picture(_gentleLuma);
      final bands = gr4Bands(picture.luma, gr4RoughGains, 3);
      picture.luma.values.setAll(0, bands.values);
      const Gr4Effects(grain: rough).undo(picture, scale: 8);
      // Scaling a rebuilt picture's bands back is not quite the inverse.
      expect(_worst(picture, _picture(_gentleLuma).luma.values), lessThan(4));
    });
  });
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
