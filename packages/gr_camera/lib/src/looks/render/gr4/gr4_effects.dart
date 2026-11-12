import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/looks/look.dart';
import 'package:gr_camera/src/looks/render/render_planes.dart';

/// The long side, in pixels, of the frame the GR IV family's detail effects
/// work on: the full 3:2 frame of the GR IV. A cropped or smaller photo is
/// taken to be this frame too \[design\], since a preview-sized copy does
/// not say what it was cut from.
const int gr4FrameLongSide = 6192;

/// What a GR IV family look does to a photo beyond each pixel's colour
/// (research/image-control-processing.md §8): Shading, Clarity, Grain and
/// HDR Tone's tone mapping, in the camera's order, on the luma and chroma
/// of the developed picture.
///
/// The camera works these on its full frame and a preview on a picture a
/// fraction of that size, so each effect is worked as the picture's share
/// of it \[design\]: the pyramids start at the level whose size is nearest
/// the picture's, and grain is the noise that is left of the camera's when
/// its pixels are averaged down to the picture's. `scale` is how many of
/// the frame's pixels lie across one of the picture's.
///
/// Sharpness is left out \[design\]: the camera sharpens edges one to a few
/// pixels wide, which a picture a quarter of the frame's size or smaller
/// barely holds (§10.2).
/// Nothing here has been compared with a camera's photos yet (§11).
@immutable
final class Gr4Effects {
  /// The effects with these settings: [shading] and [clarity] as the
  /// camera's steps, −4 to +4, [hdr] as HDR Tone's level, 0 (off) to 3.
  const new({this.shading = 0, this.clarity = 0, this.grain, this.hdr = 0});

  /// The effects of [look]. The HDR Tone bases have their level and
  /// nothing else: the camera forces their Shading and Clarity to neutral
  /// and gives them no grain (§8.4).
  factory of(Look look) {
    final base = look.base;
    if (base == LookBase.hdrTone || base == LookBase.hdrMono) {
      return Gr4Effects(hdr: _step(look, LookParameter.hdrStrength, 0, 3));
    }
    return Gr4Effects(
      shading: _step(look, LookParameter.shading, -4, 4),
      clarity: _step(look, LookParameter.clarity, -4, 4),
      grain: _step(look, LookParameter.grain, 0, 1) == 0
          ? null
          : Gr4Grain(
              strength: _step(look, LookParameter.grainStrength, 0, 2),
              size: _step(look, LookParameter.grainSize, 0, 2),
              kind: base == LookBase.grainy
                  ? Gr4GrainKind.rough
                  : _greyBases.contains(base)
                  ? Gr4GrainKind.grey
                  : Gr4GrainKind.colour,
            ),
    );
  }

  /// The Shading step.
  final int shading;

  /// The Clarity step.
  final int clarity;

  /// The grain; null when Grain Effect is off.
  final Gr4Grain? grain;

  /// The HDR Tone level; 0 when the look is not an HDR Tone one.
  final int hdr;

  /// Whether a photo developed with these effects has anything [undo] can
  /// take out again: Shading, Clarity or Grainy's contrast.
  bool get canUndo =>
      shading != 0 || clarity != 0 || grain?.kind == Gr4GrainKind.rough;

  /// Whether [apply] would change a photo that already went through
  /// [over].
  bool changes({required Gr4Effects over}) =>
      shading != 0 ||
      clarity != 0 ||
      hdr != 0 ||
      (grain != null && grain != over.grain);

  /// Applies the effects to [picture], a photo developed with [over]: its
  /// grain is still in the picture, so only what this grain has beyond it
  /// is added \[design\].
  void apply(
    LookPicture picture, {
    required double scale,
    Gr4Effects over = const Gr4Effects(),
  }) {
    final level = _levelOf(scale);
    final luma = picture.luma;
    gr4Shade(luma, shading);
    if (clarity != 0) {
      _replace(luma, gr4Bands(luma, _clarityGains(clarity), level));
    }
    final grain = this.grain;
    if (grain != null) {
      if (grain.kind == Gr4GrainKind.rough) {
        _replace(luma, gr4Bands(luma, gr4RoughGains, level));
      }
      _addGrain(picture, grain._at(scale), over.grain?._at(scale));
    }
    if (hdr != 0) _hdrTone(luma, hdr, level);
  }

  /// Takes the effects out of [picture], a photo developed with them, as
  /// far as they can be \[design\]: Clarity and Grainy's contrast by the
  /// inverse gains, Shading by the inverse gain where it did not clip.
  /// Grain stays in ([apply] allows for it), and HDR Tone has no inverse.
  void undo(LookPicture picture, {required double scale}) {
    final level = _levelOf(scale);
    final luma = picture.luma;
    if (grain?.kind == Gr4GrainKind.rough) {
      _replace(luma, gr4Bands(luma, _inverse(gr4RoughGains), level));
    }
    if (clarity != 0) {
      _replace(luma, gr4Bands(luma, _inverse(_clarityGains(clarity)), level));
    }
    gr4Shade(luma, shading, undo: true);
  }

  /// Puts [values] in [luma]'s place, limited to 0 to 255 as every stage
  /// of the camera's is (§8).
  static void _replace(Plane luma, Plane values) {
    for (var i = 0; i < luma.values.length; i++) {
      luma.values[i] = values.values[i].clamp(0, 255);
    }
  }

  static int _step(Look look, LookParameter parameter, int low, int high) =>
      (look.valueOf(parameter) ?? 0).clamp(low, high);

  /// The pyramid level whose size is nearest a picture's: level 0 is the
  /// frame and each level half the one before.
  static int _levelOf(double scale) =>
      scale <= 1 ? 0 : (math.log(scale) / math.ln2).round();

  static List<double> _inverse(List<double> gains) => [
    for (final g in gains) 1 / g,
  ];
}

/// The bases whose grain is luma only and twice as strong (§8.3): every
/// black-and-white one.
const Set<LookBase> _greyBases = {
  LookBase.monotone,
  LookBase.softMonotone,
  LookBase.hardMonotone,
  LookBase.highContrast,
  LookBase.standardMono,
  LookBase.softMono,
  LookBase.highContrastMono,
  LookBase.solid,
  LookBase.pictorialist,
  LookBase.solarization,
};

/// Which of the camera's grain a base gets (§8.3).
enum Gr4GrainKind {
  /// Luma and chroma noise: the colour bases.
  colour,

  /// Luma noise of twice the strength: the black-and-white bases.
  grey,

  /// The GR IV Monochrome's Grainy: stronger noise an octave at a time,
  /// and more local contrast with it.
  rough,
}

/// A look's Grain Effect while it is on.
@immutable
final class Gr4Grain {
  /// Grain of [kind] with Intensity [strength] (0 Low to 2 High) and Size
  /// [size] (0 Small to 2 Large).
  const new({required this.strength, required this.size, required this.kind});

  /// Intensity: 0 Low, 1 Medium, 2 High.
  final int strength;

  /// Size: 0 Small, 1 Medium, 2 Large.
  final int size;

  /// Which grain the base gets.
  final Gr4GrainKind kind;

  /// The most the camera's grain moves luma, in 8-bit codes, by Intensity
  /// and Size on the colour bases; the black-and-white ones get
  /// [_greyLimit].
  static const _colourLimit = [
    [8, 10, 13],
    [15, 20, 25],
    [30, 40, 50],
  ];

  /// See [_colourLimit].
  static const _greyLimit = [
    [15, 20, 25],
    [30, 40, 50],
    [60, 80, 100],
  ];

  /// The most the camera's grain moves Cb and Cr on the colour bases.
  static const _chromaLimit = [
    [1, 2, 3],
    [3, 5, 6],
    [6, 9, 12],
  ];

  /// What the camera's blur of each Size (3 × 3 for Small, 5 × 5 for
  /// Medium and Large) leaves of its noise's deviation on the frame: the
  /// root of the sum of its squared weights.
  static const _blurWhole = [0.506, 0.356, 0.291];

  /// What that blur costs the noise along one axis once pixels are
  /// averaged, in pixels ([_left]): how far apart, on average, two pixels
  /// that share noise are.
  static const _blurEdge = [0.55, 0.83, 1.03];

  /// Grainy's noise by Size, then Intensity, then pyramid level (1, 2 and
  /// 4 frame pixels a grain): its peak in 8-bit codes.
  static const _roughPeak = [
    [
      [30, 0, 0],
      [50, 3, 3],
      [70, 3, 0],
    ],
    [
      [3, 20, 3],
      [6, 40, 6],
      [10, 60, 10],
    ],
    [
      [7, 7, 20],
      [10, 10, 30],
      [14, 14, 40],
    ],
  ];

  /// What doubling a level of Grainy's noise back to the frame's size
  /// leaves of its deviation when the picture is that level: all of the
  /// frame's own, and less of the next two (for the first, what the 1, 6,
  /// 1 over 8 of doubling and halving leave).
  static const _roughWhole = [1.0, 0.594, 0.52];

  /// See [_blurEdge]: none for the frame's own level, 7/16 for the next
  /// and 0.53 for the one after.
  static const List<double> _roughEdge = [0, 7 / 16, 0.53];

  /// The share of a noise's deviation left when [across] of its values
  /// each way are averaged into one pixel of the picture. From two up
  /// that is `(across − edge) / across²`: the mean of that many along
  /// each axis, less the [edge] their smoothing costs. Under two it runs
  /// straight from [whole], the share at one, and a picture finer than
  /// the noise shows it as it would at one.
  static double _left(double across, double edge, double whole) {
    if (across >= 2) return (across - edge) / (across * across);
    final atTwo = (2 - edge) / 4;
    return whole + (atTwo - whole) * (across.clamp(1, 2) - 1);
  }

  /// This grain as a picture at [scale] shows it. The camera's noise is
  /// uniform, so its deviation is its peak over the root of three;
  /// averaging the frame's pixels into the picture's leaves [_left] of
  /// it.
  _GrainAt _at(double scale) {
    if (kind == Gr4GrainKind.rough) {
      var variance = 0.0;
      for (var level = 0; level < 3; level++) {
        final peak = _roughPeak[size][strength][level];
        final left = _left(
          scale / (1 << level),
          _roughEdge[level],
          _roughWhole[level],
        );
        variance += peak * peak * left * left / 3;
      }
      return _GrainAt(flat: math.sqrt(variance));
    }
    final left = _left(scale, _blurEdge[size], _blurWhole[size]);
    final grey = kind == Gr4GrainKind.grey;
    return _GrainAt(
      spread: left / math.sqrt(3),
      lumaLimit: (grey ? _greyLimit : _colourLimit)[strength][size].toDouble(),
      chromaLimit: grey ? 0 : _chromaLimit[strength][size].toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Gr4Grain &&
      other.strength == strength &&
      other.size == size &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(strength, size, kind);
}

/// A grain's standard deviation in a picture of one size, per pixel.
final class _GrainAt {
  new({
    this.flat = 0,
    this.spread = 0,
    this.lumaLimit = 0,
    this.chromaLimit = 0,
  });

  /// Grainy's noise: the same everywhere.
  final double flat;

  /// The other grain's noise for a limit of 1.
  final double spread;
  final double lumaLimit;
  final double chromaLimit;

  /// The deviation at luma [y]. The camera's grain never clips: it moves a
  /// pixel by no more than its distance from black or white (§8.3).
  double luma(double y) {
    final room = math.min(y, 255 - y).clamp(0, lumaLimit);
    return flat + room * spread;
  }

  /// The deviation at chroma [c]. Near grey the camera's table thins the
  /// chroma noise to 0.72 of its size, back to full ten codes away.
  double chroma(double c) {
    final near = (0.72 + 0.04 * ((c - 127).abs() - 3)).clamp(0.72, 1.0);
    return (chromaLimit * near).truncateToDouble() * spread;
  }
}

/// Adds [grain] to [picture], less the grain [already] in it: deviations
/// add as squares, so what is added has the difference of the squares, and
/// a photo with as much grain or more gets none.
void _addGrain(LookPicture picture, _GrainAt grain, _GrainAt? already) {
  final count = picture.width * picture.height;
  final lumaNoise = _noise(count, 0x9e3779b9);
  final luma = picture.luma.values;
  for (var i = 0; i < count; i++) {
    final y = luma[i].clamp(0.0, 255.0);
    final had = already?.luma(y) ?? 0;
    final wanted = grain.luma(y);
    if (wanted <= had) continue;
    luma[i] = y + math.sqrt(wanted * wanted - had * had) * lumaNoise[i];
  }
  if (grain.flat != 0) {
    // Grainy's noise is not held back near black and white: it clips.
    for (var i = 0; i < count; i++) {
      luma[i] = luma[i].clamp(0, 255);
    }
  }
  if (grain.chromaLimit == 0) return;
  // Cb and Cr each get noise of their own \[design\]; whether the camera's
  // share one is \[unknown\].
  final planes = [picture.blue.values, picture.red.values];
  for (var which = 0; which < 2; which++) {
    final plane = planes[which];
    final noise = _noise(count, 0x7f4a7c15 + which);
    for (var i = 0; i < count; i++) {
      final c = plane[i];
      final had = already?.chroma(c) ?? 0;
      final wanted = grain.chroma(c);
      if (wanted <= had) continue;
      plane[i] = c + math.sqrt(wanted * wanted - had * had) * noise[i];
    }
  }
}

/// [count] values of mean 0 and deviation 1, the same for the same [seed]:
/// the camera draws new grain for every shot (§8.3), and a preview that
/// redrew it on every change would flicker \[design\]. Close to a normal
/// distribution, as the average of many of the camera's uniform values is.
Float32List _noise(int count, int seed) {
  final out = Float32List(count);
  var state = seed;
  for (var i = 0; i < count; i++) {
    var sum = 0;
    for (var draw = 0; draw < 4; draw++) {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      sum += state & 0xffff;
    }
    // Four uniform values of 0 to 1 have a variance of a third together.
    out[i] = (sum / 0x10000 - 2) * math.sqrt(3);
  }
  return out;
}

/// The camera's Shading on [luma] (§8.1): a gain that grows with the
/// square of the distance from the centre, to `2^(step/2)` at the corner
/// for a negative [step] and `2^(step/3)` for a positive one, clipping at
/// white. With [undo] it takes that gain out again; a pixel the gain
/// clipped comes back as the darkest value that would have clipped.
@visibleForTesting
void gr4Shade(Plane luma, int step, {bool undo = false}) {
  if (step == 0) return;
  final corner = math.pow(2, step < 0 ? step / 2 : step / 3).toDouble();
  final centreX = (luma.width - 1) / 2;
  final centreY = (luma.height - 1) / 2;
  final reach = centreX * centreX + centreY * centreY;
  if (reach == 0) return;
  final values = luma.values;
  var i = 0;
  for (var y = 0; y < luma.height; y++) {
    final down = (y - centreY) * (y - centreY);
    for (var x = 0; x < luma.width; x++, i++) {
      final across = (x - centreX) * (x - centreX);
      final share = math.min((across + down) / reach, 1);
      final v = values[i];
      if (!undo) {
        values[i] = v + share * (math.min(255, corner * v) - v);
        continue;
      }
      final plain = v / (1 + share * (corner - 1));
      if (corner * plain <= 255) {
        values[i] = plain;
        continue;
      }
      // Clipped: the pixel was moved `share` of the way to white.
      final least = 255 / corner;
      values[i] = share < 1
          ? ((v - 255 * share) / (1 - share)).clamp(least, 255)
          : least;
    }
  }
}

/// The gain Clarity gives each band of the camera's pyramid, finest first
/// (§8.2): `2^(e · step)` with e = 0.1 for bands 2 to 5, 0.08 for bands 1
/// and 6 and 0.07 for band 7, which follows the camera's table to 0.0005.
/// The finest band and those past the seventh are left alone.
List<double> _clarityGains(int step) => [
  for (final e in const [0, 0.08, 0.1, 0.1, 0.1, 0.1, 0.08, 0.07])
    math.pow(2, e * step).toDouble(),
];

/// The gain Grainy gives each band of the camera's pyramid while its grain
/// is on, finest first (§8.3).
@visibleForTesting
const List<double> gr4RoughGains = [2, 2, 3, 1.4, 1.3];

/// [picture] with the bands of the camera's pyramid multiplied by [gains]
/// (§8.2): each level is the 2 × 2 average of the one before, a band is
/// what a level has beyond the next one doubled, and the picture is level
/// [level] of the frame's pyramid, so its finest band is band [level].
///
/// The band one level finer than the picture still shows at the picture's
/// size: halving that band leaves what the picture has beyond itself
/// doubled and halved again, a slight blur B with weights 1, 6, 1 over 8
/// each way. So with h that band's gain less one, the result is
/// `(1 + h)·P + B·(R − (1 + h)·P)`, R being the picture with its own bands
/// scaled. Finer bands still are left out.
@visibleForTesting
Plane gr4Bands(Plane picture, List<double> gains, int level) {
  double gain(int band) => band < gains.length ? gains[band] : 1;
  var last = gains.length - 1;
  while (last >= 0 && gains[last] == 1) {
    last--;
  }

  Plane rebuilt(Plane from, int band) {
    if (band > last || from.width < 2 || from.height < 2) return from;
    final coarse = from.halved();
    final smooth = coarse.doubled(from.width, from.height);
    final coarseRebuilt = rebuilt(coarse, band + 1);
    final below = identical(coarseRebuilt, coarse)
        ? smooth
        : coarseRebuilt.doubled(from.width, from.height);
    final out = Plane(from.width, from.height);
    final scale = gain(band);
    for (var i = 0; i < out.values.length; i++) {
      out.values[i] =
          below.values[i] + (from.values[i] - smooth.values[i]) * scale;
    }
    return out;
  }

  final own = rebuilt(picture, level);
  final finer = level >= 1 ? gain(level - 1) : 1.0;
  if (finer == 1) return own;
  final rest = Plane(picture.width, picture.height);
  for (var i = 0; i < rest.values.length; i++) {
    rest.values[i] = own.values[i] - finer * picture.values[i];
  }
  final out = rest.filtered(_halvedDoubled);
  for (var i = 0; i < out.values.length; i++) {
    out.values[i] += finer * picture.values[i];
  }
  return out;
}

/// What doubling a plane and halving it again does to it: weights 1, 6, 1
/// over 8 along each axis.
const List<double> _halvedDoubled = [
  1 / 64, 6 / 64, 1 / 64, //
  6 / 64, 36 / 64, 6 / 64, //
  1 / 64, 6 / 64, 1 / 64, //
];

/// HDR Tone's smoothing of a level before it is halved (§8.4), over 256.
const List<double> _hdrSmooth = [
  4 / 256, 28 / 256, 4 / 256, //
  28 / 256, 128 / 256, 28 / 256, //
  4 / 256, 28 / 256, 4 / 256, //
];

/// HDR Tone's blur of a level doubled back to the size of the one before
/// (§8.4), over 256.
const List<double> _hdrBlur = [
  4 / 256, 8 / 256, 8 / 256, 8 / 256, 4 / 256, //
  8 / 256, 12 / 256, 16 / 256, 12 / 256, 8 / 256, //
  8 / 256, 16 / 256, 32 / 256, 16 / 256, 8 / 256, //
  8 / 256, 12 / 256, 16 / 256, 12 / 256, 8 / 256, //
  4 / 256, 8 / 256, 8 / 256, 8 / 256, 4 / 256, //
];

/// What HDR Tone makes of the difference between a level and the next one
/// (§8.4), in 8-bit codes each way: a curve of GR Photo's own \[design\],
/// straight between a few points fitted to the camera's 256-entry tables
/// by least squares (within 0.2 of a code). The two finest levels of the
/// camera's pyramid raise the smallest differences a little further than
/// the next five; all seven push any difference of a code or more to about
/// 17 and let larger ones grow at half their size. The four coarsest keep
/// about a third of a difference up to 18 codes and a sixth of the rest.
enum _HdrCurve {
  finest(
    [0, 0.5, 1, 1.5, 2.5, 18, 127.5],
    [0, 1.9375, 12.9375, 17.1051, 17.4747, 18.0055, 72.8637],
  ),
  fine(
    [0, 0.5, 1, 1.5, 2.5, 18, 127.5],
    [0, 1.5, 12.375, 17.1051, 17.4747, 18.0055, 72.8637],
  ),
  coarse([0, 18, 127.5], [0, 6.2791, 25.4813]);

  new(this._at, this._to);

  /// The curve for level [level] of HDR Tone's pyramid.
  static _HdrCurve of(int level) => level < 2
      ? finest
      : level < 7
      ? fine
      : coarse;

  final List<double> _at;
  final List<double> _to;

  /// The curve's value for [difference], with its sign.
  double call(double difference) {
    final size = difference.abs();
    var i = 1;
    while (i < _at.length - 1 && size > _at[i]) {
      i++;
    }
    final part = ((size - _at[i - 1]) / (_at[i] - _at[i - 1])).clamp(0, 1);
    final value = _to[i - 1] + (_to[i] - _to[i - 1]) * part;
    return difference < 0 ? -value : value;
  }
}

/// The share of a level HDR Tone takes out of the finest one, so that the
/// pyramid adds up to a change of the picture and not to a picture (§8.4).
const double _hdrKept = 0x100a / 4096;

/// HDR Tone's rebuilt pyramid from level [level] down (§8.4), [from] being
/// that level: Z is the level smoothed, S the next level (every other
/// value of Z) doubled and blurred, and the level becomes
/// `S' + f·(G − Z) + curve(Z − S)`, S' being the next level rebuilt, doubled
/// and blurred, with f = 1.2 for the five finest levels and 1 after. That
/// reading of the camera's units is \[inferred\] from its being the only
/// one that gives the picture back when the curve changes nothing.
Plane _hdrRebuilt(Plane from, int level) {
  if (level > 10 || from.width < 2 || from.height < 2) return from;
  final smooth = from.filtered(_hdrSmooth);
  final next = smooth.everyOther();
  final width = from.width;
  final height = from.height;
  final spread = next.spread(width, height).filtered(_hdrBlur);
  final below = _hdrRebuilt(
    next,
    level + 1,
  ).spread(width, height).filtered(_hdrBlur);
  final fine = level < 5 ? 0x1333 / 4096 : 1.0;
  final curve = _HdrCurve.of(level);
  final out = Plane(width, height);
  for (var i = 0; i < out.values.length; i++) {
    final z = smooth.values[i];
    // The camera's planes hold ±512 codes.
    final band = (fine * (from.values[i] - z) + curve(z - spread.values[i]))
        .clamp(-512, 512);
    out.values[i] = (below.values[i] + band).clamp(-512, 512);
  }
  return out;
}

/// HDR Tone at level [strength] (1 Low to 3 High) on [luma], a picture at
/// level [level] of the frame's pyramid (§8.4). The camera works on the
/// frame at half size, so a picture at level 1 or coarser is a level of
/// HDR Tone's own pyramid and starts there; its finer levels, which the
/// picture does not hold, are left out. The correction is added at a
/// quarter, a half and the whole of its size, which is \[inferred\] from
/// the range of the camera's planes.
void _hdrTone(Plane luma, int strength, int level) {
  final weight = (1 << (strength - 1)) / 4;
  final start = level == 0 ? luma.everyOther() : luma;
  final change = _hdrRebuilt(start, math.max(level - 1, 0));
  for (var i = 0; i < change.values.length; i++) {
    change.values[i] = (change.values[i] - _hdrKept * start.values[i]).clamp(
      -256,
      255.94,
    );
  }
  final whole = level == 0 ? change.spread(luma.width, luma.height) : change;
  for (var i = 0; i < luma.values.length; i++) {
    luma.values[i] = (luma.values[i] + weight * whole.values[i]).clamp(0, 255);
  }
}
