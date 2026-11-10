import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gr_camera/src/looks/look.dart';
import 'package:gr_camera/src/looks/render/gr4/gr4_curves.dart';
import 'package:gr_camera/src/looks/render/gr4/gr4_tone.dart';
import 'package:gr_camera/src/looks/render/look_renderer.dart';
import 'package:gr_camera/src/looks/render/render_maths.dart';

/// How the GR IV family (GR IV, GR IV HDF, GR IV Monochrome) renders the
/// colour and tone of a look, after firmware 1.20
/// (research/image-control-processing.md §2–§7, recipe in §10).
///
/// In the camera's order: the base's colour matrix on linear RGB, the
/// multi-axis hue correction of the four bases that have one, the tone
/// curve of the four tone sliders, the base's own curve per channel, then
/// on the encoded values saturation or the black-and-white mix, the hue
/// rotation and the toning. Scene-linear RGB here is the camera's
/// white-balanced RGB after its camera matrix.
///
/// Left out \[design\]: the effects that are not per pixel (Shading,
/// Clarity, Grain, HDR Tone's tone mapping, Sharpness); the gain curve
/// that fades chroma near black and white (§4.4), which every base shares
/// and the photo already carries; and Retro's ToneControl values (§3) and
/// the multi-axis block's level scaling (§4.5), whose workings are
/// \[unknown\]. Nothing here has been compared with a camera's photos
/// yet.
final class Gr4LookRenderer implements LookRenderer {
  /// The GR IV family's rendering.
  const new();

  @override
  LookTransform? encoder(Look target) => _Stages.of(target)?.encode;

  @override
  LookTransform? decoder(Look source) {
    if (!_canUndo(source)) return null;
    final stages = _Stages.of(source);
    if (stages == null) return null;
    return stages.setsChroma ? stages.decodeGrey : stages.decode;
  }

  @override
  LookSourceFit sourceFit(Look source, Look target) {
    if (!_canUndo(source)) return LookSourceFit.unusable;
    if (_isMonochrome(source)) {
      // A grey photo has its tones to offer another black-and-white look,
      // and nothing to offer a colour one.
      return _isMonochrome(target)
          ? LookSourceFit.rough
          : LookSourceFit.unusable;
    }
    return _isLossy(source) ? LookSourceFit.rough : LookSourceFit.good;
  }

  /// Whether [look]'s rendering has an inverse worth using: not HDR Tone,
  /// whose tone mapping depends on a pixel's surroundings, not Solarized
  /// Effect, whose curve gives one output for several inputs, and not a
  /// base whose processing is \[unknown\].
  static bool _canUndo(Look look) => switch (look.base) {
    null ||
    LookBase.palette ||
    LookBase.hdrTone ||
    LookBase.hdrMono ||
    LookBase.solarization => false,
    _ => true,
  };

  static bool _isMonochrome(Look look) => switch (look.base) {
    LookBase.monotone ||
    LookBase.softMonotone ||
    LookBase.hardMonotone ||
    LookBase.highContrast ||
    LookBase.standardMono ||
    LookBase.softMono ||
    LookBase.highContrastMono ||
    LookBase.grainy ||
    LookBase.solid ||
    LookBase.hdrMono ||
    LookBase.solarization ||
    LookBase.pictorialist => true,
    LookBase.hdrTone => _step(look, LookParameter.toningHdr) != 0,
    _ => false,
  };

  /// Whether a colour photo developed with [look] lost what undoing its
  /// rendering needs. Where the line falls is \[design\]: an effect that
  /// is not per pixel in the photo, a base that keeps under half the
  /// colour or caps a channel (§4.1, §5), saturation under 0.8, or a tone
  /// curve that clips the top tenth of the highlights (§3).
  static bool _isLossy(Look look) =>
      look.base == LookBase.bleachBypass ||
      look.base == LookBase.crossProcess ||
      _step(look, LookParameter.grain) != 0 ||
      _step(look, LookParameter.shading) != 0 ||
      _step(look, LookParameter.clarity) != 0 ||
      _step(look, LookParameter.saturation) <= -3 ||
      _step(look, LookParameter.key) >= 3 ||
      _step(look, LookParameter.contrast) >= 4;
}

/// [parameter]'s value in [look]; 0 when the look lacks it.
int _step(Look look, LookParameter parameter) => look.valueOf(parameter) ?? 0;

/// [parameter] as one of the camera's steps, −4 to +4.
int _slider(Look look, LookParameter parameter) =>
    _step(look, parameter).clamp(-4, 4);

/// The camera matrix, from white-balanced sensor RGB to the RGB the base
/// matrices work on (§4.1).
const List<double> _cameraMatrix = [
  1.6418, -0.8031, 0.1613, //
  -0.1865, 1.4833, -0.2968, //
  0.0635, -0.5145, 1.4510, //
];

final Float64List _cameraMatrixInverse = mat3Inverse(_cameraMatrix);

// The base look matrices (§4.1), each row summing to 1.
const List<double> _standard = [
  1.0664, 0.0039, -0.0703, //
  0.0273, 1.0117, -0.0391, //
  -0.0234, 0.0547, 0.9688, //
];
const List<double> _vivid = [
  1.1218, -0.0070, -0.1149, //
  -0.0022, 1.1348, -0.1326, //
  -0.0481, -0.0790, 1.1271, //
];
const List<double> _positiveFilm = [
  0.9688, 0.3047, -0.2734, //
  -0.0195, 1.1758, -0.1562, //
  -0.0703, 0.3945, 0.6758, //
];
const List<double> _negativeFilm = [
  1.0912, -0.2004, 0.1093, //
  0.1522, 0.7220, 0.1257, //
  0.0070, 0.2643, 0.7288, //
];
const List<double> _bleachBypass = [
  0.5469, 0.3445, 0.1086, //
  0.1558, 0.7135, 0.1307, //
  0.1343, 0.3202, 0.5455, //
];
const List<double> _bleachBypassCool = [
  0.4948, 0.3391, 0.1661, //
  0.1389, 0.7261, 0.1350, //
  0.0962, 0.2999, 0.6039, //
];
const List<double> _bleachBypassWarm = [
  0.5837, 0.3568, 0.0594, //
  0.1891, 0.6864, 0.1245, //
  0.2277, 0.3347, 0.4376, //
];
const List<double> _retro = [
  0.6182, 0.3350, 0.0469, //
  0.1395, 0.8092, 0.0513, //
  0.0582, 0.3354, 0.6063, //
];
const List<double> _cinemaYellow = [
  0.7656, 0.2266, 0.0078, //
  0.0078, 0.9062, 0.0859, //
  0.0000, 0.2500, 0.7500, //
];
const List<double> _cinemaGreen = [
  0.6758, 0.3008, 0.0234, //
  0.0234, 0.7930, 0.1836, //
  -0.0078, 0.2578, 0.7500, //
];
const List<double> _hardMonotone = [
  0.7773, 0.9297, -0.7070, //
  0.7773, 0.9297, -0.7070, //
  0.7773, 0.9297, -0.7070, //
];

/// Colour matrix block 0 as the camera's registers hold it (§2): the base
/// matrix [base] times the camera matrix in 1/256, each diagonal entry
/// then set so its row sums to 1, which keeps greys grey. The camera
/// leaves the rows as they come ([sumRowsToOne] false) for the three bases
/// it turns black-and-white in block 1.
Float64List _blockZero(List<double> base, {bool sumRowsToOne = true}) {
  final product = mat3Multiply(base, _cameraMatrix);
  final m = Float64List(9);
  for (var i = 0; i < 9; i++) {
    // Rounded to 1/8192, then cut to 1/256, as the camera's integers go.
    m[i] = ((product[i] * 8192 + 0.5).truncate() / 32).truncate() / 256;
  }
  if (sumRowsToOne) {
    m[0] = 1 - m[1] - m[2];
    m[4] = 1 - m[3] - m[5];
    m[8] = 1 - m[6] - m[7];
  }
  return m;
}

/// The multi-axis hue correction (§4.5) as GR Lab models it \[design\]:
/// the camera gives each of 12 hue areas of the (Cb, Cr) plane a matrix
/// that leaves luma alone, and neighbouring areas agree on the axis
/// between them. So the whole map is fixed by what it does to each of the
/// 12 axes, a chroma gain and a turn in degrees, and is linear in between.
/// This reproduces the camera's matrices to 0.0013 of full scale.
final class _HueAxes {
  new(List<double> gainsAndTurns)
    : _from = Float64List(12),
      _to = Float64List(12),
      _forward = List.filled(12, _noMap),
      _inverse = List.filled(12, _noMap) {
    final image = <(double, double)>[];
    for (var k = 0; k < 12; k++) {
      final gain = gainsAndTurns[k * 2];
      final angle = _axisDegrees[k] + gainsAndTurns[k * 2 + 1];
      _from[k] = _axisDegrees[k];
      _to[k] = angle;
      image.add(_polar(gain, angle));
    }
    for (var k = 0; k < 12; k++) {
      final next = (k + 1) % 12;
      final (ax, ay) = _polar(1, _axisDegrees[k]);
      final (bx, by) = _polar(1, _axisDegrees[next]);
      final (px, py) = image[k];
      final (qx, qy) = image[next];
      // The 2×2 map taking this area's two axes to their images.
      final det = ax * by - bx * ay;
      final m = Float64List.fromList([
        (px * by - qx * ay) / det,
        (qx * ax - px * bx) / det,
        (py * by - qy * ay) / det,
        (qy * ax - py * bx) / det,
      ]);
      final mDet = m[0] * m[3] - m[1] * m[2];
      _forward[k] = m;
      _inverse[k] = Float64List.fromList([
        m[3] / mDet,
        -m[1] / mDet,
        -m[2] / mDet,
        m[0] / mDet,
      ]);
    }
  }

  /// The axes between the camera's hue areas, as angles of atan2(Cr, Cb).
  static const List<double> _axisDegrees = [
    0, 30, 60, 90, 112.5, 145, 180, 210, 240, 270, 305, 325, //
  ];

  static final Float64List _noMap = Float64List(4);

  /// Each area's first axis, before and after the map.
  final Float64List _from;
  final Float64List _to;

  /// Each area's 2×2 chroma map and its inverse, row by row.
  final List<Float64List> _forward;
  final List<Float64List> _inverse;

  static (double, double) _polar(double radius, double degrees) {
    final a = degrees * math.pi / 180;
    return (radius * math.cos(a), radius * math.sin(a));
  }

  /// Applies the correction to the linear R, G, B in [v].
  void apply(Float64List v) => _map(v, _from, _forward);

  /// Undoes [apply].
  void undo(Float64List v) => _map(v, _to, _inverse);

  static void _map(Float64List v, Float64List starts, List<Float64List> maps) {
    rgbToYcc(v);
    final cb = v[1];
    final cr = v[2];
    if (cb != 0 || cr != 0) {
      // The area whose first axis is the last one at or before the hue,
      // counting round from the first area's axis.
      final hue = (math.atan2(cr, cb) * 180 / math.pi - starts[0]) % 360;
      var area = 11;
      while (area > 0 && starts[area] - starts[0] > hue) {
        area--;
      }
      final m = maps[area];
      v[1] = m[0] * cb + m[1] * cr;
      v[2] = m[2] * cb + m[3] * cr;
    }
    yccToRgb(v);
  }
}

// What the correction does on each axis, chroma gain then turn in degrees,
// for the four bases that have it (§4.5): GR Lab's own reduction of the
// camera's matrices.
final _HueAxes _standardAxes = _HueAxes(const [
  0.9865, 0.38, 0.9713, -3.11, 0.9961, -5.54, 1.0175, 1.64, //
  1.0191, -0.77, 1.0949, -4.05, 1.0179, -0.54, 0.9786, -3.50, //
  0.8953, -3.29, 0.8871, -3.71, 0.8999, -0.91, 0.9826, 0.51, //
]);
final _HueAxes _positiveFilmAxes = _HueAxes(const [
  0.9936, 0.26, 0.9599, -4.73, 0.8010, -1.68, 0.9192, -0.07, //
  1.0363, -0.83, 1.1429, -7.07, 1.0941, -10.15, 0.9790, -4.14, //
  0.9808, 4.31, 0.9454, 10.27, 0.9574, 8.36, 1.0007, 2.39, //
]);
final _HueAxes _cinemaYellowAxes = _HueAxes(const [
  0.9907, 3.16, 0.9768, -3.35, 0.8557, -4.66, 0.9774, 1.03, //
  1.0820, -0.39, 1.0635, -3.35, 1.1123, -8.97, 0.9857, -13.73, //
  0.9188, -9.80, 0.8050, -12.85, 0.7630, 1.58, 0.7996, 3.92, //
]);
final _HueAxes _cinemaGreenAxes = _HueAxes(const [
  0.9474, 0.48, 0.9991, 0.08, 0.9568, -3.10, 0.8792, -6.14, //
  0.9417, -0.28, 0.9811, 3.11, 1.0276, 10.83, 1.0557, 13.62, //
  1.1585, 10.71, 1.1214, 5.99, 1.1150, -4.90, 1.0208, -4.47, //
]);

// Toning, as (Cb, Cr) in 1/1024 of full scale (§4.4, §6.2).
const List<(int, int)> _retroToning = [
  (72, -24), (54, -18), (36, -12), (18, -6), (0, 0), //
  (-20, 16), (-40, 32), (-60, 48), (-80, 64), //
];
const List<(int, int)> _bleachBypassToning = [
  (0, 0), (12, -36), (40, -60), (-40, 0), //
];
const List<(int, int)> _monotoneToning = [
  (0, 0), (-24, 16), (-8, 28), (0, -24), (20, -8), (16, 4), //
];
const List<(int, int)> _monochromeBodyToning = [
  (0, 0), (-12, 8), (-4, 14), (0, -4), (10, -4), (8, 2), //
];
const (int, int) _hdrSepia = (-36, 24);

/// The grey HDR Tone makes of R, G and B when it is toned (§6.1).
const List<double> _hdrGrey = [
  0.3008, 0.5859, 0.1133, //
  0.3008, 0.5859, 0.1133, //
  0.3008, 0.5859, 0.1133, //
];

/// One step of the Hue slider, in radians (§4.3).
const double _hueStep = 2.46 * math.pi / 180;

/// A tone curve's point for a linear value of 1: point `i` is the 12-bit
/// input `16 · i`.
const double _curveScale = 4095 / 16;

/// The stages of one look's rendering, worked out once per look.
final class _Stages {
  new _({
    required List<double> block0,
    required this.axes,
    required this.curves,
    required this.mix,
    required this.setsChroma,
    required this.hue,
    required (int, int) chroma,
  }) : _block0 = block0,
       fromScene = mat3Multiply(block0, _cameraMatrixInverse),
       hueCos = math.cos(hue),
       hueSin = math.sin(hue),
       cb = chroma.$1 / 1024,
       cr = chroma.$2 / 1024;

  /// The stages for [look]; null when GR Lab does not know how its base
  /// image is processed.
  static _Stages? of(Look look) {
    final base = look.base;
    if (base == null || base == LookBase.palette) return null;

    // HDR Tone always develops with neutral tone sliders, and Solarized
    // Effect with neutral contrast sliders (§3).
    final hdr = base == LookBase.hdrTone || base == LookBase.hdrMono;
    final fixedContrast = hdr || base == LookBase.solarization;
    final tone = gr4ToneCurve(
      key: hdr ? 0 : _slider(look, LookParameter.key),
      contrast: fixedContrast ? 0 : _slider(look, LookParameter.contrast),
      highlight: fixedContrast ? 0 : _slider(look, LookParameter.contrastHigh),
      shadow: fixedContrast ? 0 : _slider(look, LookParameter.contrastLow),
    );

    final saturation = _saturation(_slider(look, LookParameter.saturation));
    final hue = _slider(look, LookParameter.hue) * _hueStep;
    final monoToning = _step(look, LookParameter.toningMonotone).clamp(0, 5);
    final hdrToning = _step(look, LookParameter.toningHdr);
    final plain = _plainCurves(tone);

    _Stages colour(
      List<double> matrix, {
      _HueAxes? axes,
      List<Float64List>? curves,
      (int, int) toning = (0, 0),
    }) => _Stages._(
      block0: _blockZero(matrix),
      axes: axes,
      curves: curves ?? plain,
      mix: saturation,
      setsChroma: false,
      hue: hue,
      chroma: toning,
    );

    // The bases of the GR IV Monochrome: no colour to convert, so the grey
    // is the luma of whatever the curves give.
    _Stages monochromeBody({CurveKnots? curve, (int, int)? toning}) =>
        _Stages._(
          block0: _blockZero(mat3Identity),
          axes: null,
          curves: curve == null ? plain : _shapedCurves(tone, [curve]),
          mix: mat3Identity,
          setsChroma: true,
          hue: 0,
          chroma: toning ?? _monochromeBodyToning[monoToning],
        );

    // The colour bodies' bases that average R, G and B, or weigh them by
    // the look's filter values (§6.1).
    _Stages averaged({CurveKnots? curve}) => _Stages._(
      block0: _blockZero(mat3Identity, sumRowsToOne: false),
      axes: null,
      curves: curve == null ? plain : _shapedCurves(tone, [curve]),
      mix: _greyMix(look),
      setsChroma: true,
      hue: 0,
      chroma: _monotoneToning[monoToning],
    );

    // HDR Tone and the Monochrome's HDR Tone with a toning: a luma-weighted
    // grey, plain or sepia (§6.1, §4.4).
    _Stages tonedHdr() => _Stages._(
      block0: _blockZero(mat3Identity),
      axes: null,
      curves: plain,
      mix: _hdrGrey,
      setsChroma: true,
      hue: 0,
      chroma: hdrToning == 2 ? _hdrSepia : (0, 0),
    );

    switch (base) {
      case LookBase.standard:
        return colour(_standard, axes: _standardAxes);
      case LookBase.vivid:
        return colour(_vivid);
      case LookBase.positiveFilm:
        return colour(_positiveFilm, axes: _positiveFilmAxes);
      case LookBase.negativeFilm:
        return colour(_negativeFilm);
      case LookBase.bleachBypass:
        final toning = _step(
          look,
          LookParameter.toningBleachBypass,
        ).clamp(0, 3);
        return colour(switch (toning) {
          2 => _bleachBypassCool,
          3 => _bleachBypassWarm,
          _ => _bleachBypass,
        }, toning: _bleachBypassToning[toning]);
      case LookBase.retro:
        return colour(
          _retro,
          toning: _retroToning[_slider(look, LookParameter.toningRetro) + 4],
        );
      case LookBase.cineYellow:
        return colour(
          _cinemaYellow,
          axes: _cinemaYellowAxes,
          curves: _cinemaCurves(tone, gr4CinemaYellowKnots, look),
        );
      case LookBase.cineGreen:
        return colour(
          _cinemaGreen,
          axes: _cinemaGreenAxes,
          curves: _cinemaCurves(tone, gr4CinemaGreenKnots, look),
        );
      case LookBase.crossProcess:
        final preset = _step(look, LookParameter.crossProcess).clamp(0, 2);
        return colour(
          _standard,
          curves: _shapedCurves(tone, gr4CrossProcessKnots[preset]),
        );
      case LookBase.hdrTone:
        return hdrToning == 0 ? colour(_standard) : tonedHdr();
      case LookBase.monotone || LookBase.softMonotone:
        return averaged();
      case LookBase.highContrast:
        return averaged(curve: gr4HighContrastKnots);
      case LookBase.hardMonotone:
        return _Stages._(
          block0: _blockZero(_hardMonotone),
          axes: null,
          curves: plain,
          mix: mat3Identity,
          setsChroma: true,
          hue: 0,
          chroma: _monotoneToning[monoToning],
        );
      case LookBase.standardMono || LookBase.softMono || LookBase.pictorialist:
        return monochromeBody();
      case LookBase.highContrastMono:
        return monochromeBody(curve: gr4HighContrastKnots);
      case LookBase.grainy:
        return monochromeBody(curve: gr4GrainyKnots);
      case LookBase.solid:
        return monochromeBody(curve: gr4SolidKnots);
      case LookBase.solarization:
        // The look holds types 1 to 3 (protocol/image-control.md §4).
        final type = _step(look, LookParameter.solarizationType).clamp(1, 3);
        return monochromeBody(curve: gr4SolarizationKnots[type - 1]);
      case LookBase.hdrMono:
        return hdrToning == 2 ? tonedHdr() : monochromeBody(toning: (0, 0));
      case LookBase.palette:
        return null;
    }
  }

  final List<double> _block0;

  /// From scene-linear RGB to the base's linear RGB, and back. Only a
  /// colour look's matrix has an inverse.
  final Float64List fromScene;
  late final Float64List toScene = mat3Multiply(
    _cameraMatrix,
    mat3Inverse(_block0),
  );

  /// The multi-axis correction, for the bases that have one.
  final _HueAxes? axes;

  /// The R, G and B curves from linear to encoded values: the tone curve
  /// and the base's own curve after it, 0..1 at each of the tone curve's
  /// points.
  final List<Float64List> curves;

  /// Colour matrix block 1 on the encoded values: saturation, or the
  /// black-and-white mix.
  final List<double> mix;
  late final Float64List unmix = mat3Inverse(mix);

  /// Whether the look replaces the chroma with ([cb], [cr]), as the
  /// black-and-white looks do, or adds it after the hue rotation.
  final bool setsChroma;

  /// The Hue slider's rotation of (Cb, Cr), in radians.
  final double hue;
  final double hueCos;
  final double hueSin;

  /// The toning, as Cb and Cr of full scale.
  final double cb;
  final double cr;

  /// Scene-linear RGB to this look's encoded RGB.
  void encode(Float64List v) {
    mat3Apply(fromScene, v);
    axes?.apply(v);
    // The curves hold their end values for what lies outside 0..1. Where
    // the camera's integers clip before them is \[unknown\]; clipping
    // only here keeps a photo unchanged under its own look.
    for (var c = 0; c < 3; c++) {
      v[c] = curveAt(curves[c], v[c] * _curveScale);
    }
    mat3Apply(mix, v);
    rgbToYcc(v);
    if (setsChroma) {
      v[1] = cb;
      v[2] = cr;
    } else {
      final b = v[1];
      final r = v[2];
      v[1] = hueCos * b - hueSin * r + cb;
      v[2] = hueSin * b + hueCos * r + cr;
    }
    yccToRgb(v);
    clampUnit(v);
  }

  /// The inverse of [encode] for a colour look.
  void decode(Float64List v) {
    rgbToYcc(v);
    final b = v[1] - cb;
    final r = v[2] - cr;
    v[1] = hueCos * b + hueSin * r;
    v[2] = hueCos * r - hueSin * b;
    yccToRgb(v);
    mat3Apply(unmix, v);
    for (var c = 0; c < 3; c++) {
      v[c] = curveInverse(curves[c], v[c]) / _curveScale;
    }
    axes?.undo(v);
    mat3Apply(toScene, v);
  }

  /// The nearest thing to an inverse of [encode] for a black-and-white
  /// look \[design\]: the grey the scene would be if it had no colour.
  void decodeGrey(Float64List v) {
    final luma = lumaRed * v[0] + lumaGreen * v[1] + lumaBlue * v[2];
    final grey = curveInverse(curves[1], luma) / _curveScale;
    v[0] = grey;
    v[1] = grey;
    v[2] = grey;
  }

  /// The Saturation slider's matrix (§4.2): each step scales the distance
  /// from the luma by 1.1.
  static Float64List _saturation(int step) {
    final s = math.pow(1.1, step).toDouble();
    final r = (1 - s) * lumaRed;
    final g = (1 - s) * lumaGreen;
    final b = (1 - s) * lumaBlue;
    return Float64List.fromList([r + s, g, b, r, g + s, b, r, g, b + s]);
  }

  /// The black-and-white mix of Monotone, Soft Monotone and Hi-Contrast
  /// B&W (§6.1): a plain average, or with the filter effect on, the look's
  /// R, G and B filter values as percentages.
  static Float64List _greyMix(Look look) {
    var weights = const [1 / 3, 1 / 3, 1 / 3];
    if (_step(look, LookParameter.filterEffect) == 1) {
      weights = [
        _percent(
          look,
          LookParameter.filterEffectRedHigh,
          LookParameter.filterEffectRedLow,
        ),
        _percent(
          look,
          LookParameter.filterEffectGreenHigh,
          LookParameter.filterEffectGreenLow,
        ),
        _percent(
          look,
          LookParameter.filterEffectBlueHigh,
          LookParameter.filterEffectBlueLow,
        ),
      ];
    }
    return Float64List.fromList([...weights, ...weights, ...weights]);
  }

  /// A filter value: a signed 16-bit percentage split over two parameters
  /// (protocol/image-control.md §4).
  static double _percent(Look look, LookParameter high, LookParameter low) {
    final bits = ((_step(look, high) & 0xff) << 8) | (_step(look, low) & 0xff);
    return (bits >= 0x8000 ? bits - 0x10000 : bits) / 100;
  }

  /// [tone] alone as the R, G and B curves.
  static List<Float64List> _plainCurves(Int32List tone) {
    final curve = Float64List.fromList([
      for (final v in tone) v / gr4CurveWhite,
    ]);
    return [curve, curve, curve];
  }

  /// [tone] followed by a base's own curves (§5), one for all channels or
  /// one each for R, G and B.
  static List<Float64List> _shapedCurves(
    Int32List tone,
    List<CurveKnots> shapes,
  ) {
    final curves = [
      for (final shape in shapes) _shaped(tone, shape.sample(gr4CurvePoints)),
    ];
    return curves.length == 1 ? [curves[0], curves[0], curves[0]] : curves;
  }

  /// The Cinema bases' curves (§5): the toning (Low, Medium, High) sets
  /// how far the R and B curves depart from the G curve, in thirds.
  static List<Float64List> _cinemaCurves(
    Int32List tone,
    List<CurveKnots> shapes,
    Look look,
  ) {
    final weight = _step(look, LookParameter.toningCinema).clamp(0, 2) + 1;
    final red = shapes[0].sample(gr4CurvePoints);
    final green = shapes[1].sample(gr4CurvePoints);
    final blue = shapes[2].sample(gr4CurvePoints);
    for (var i = 0; i < gr4CurvePoints; i++) {
      red[i] = (weight * red[i] + (3 - weight) * green[i]) / 3;
      blue[i] = (weight * blue[i] + (3 - weight) * green[i]) / 3;
    }
    return [_shaped(tone, red), _shaped(tone, green), _shaped(tone, blue)];
  }

  /// [shape] applied to [tone]'s output: [shape] has a point per 64 of the
  /// tone curve's output scale.
  static Float64List _shaped(Int32List tone, Float64List shape) =>
      Float64List.fromList([
        for (final v in tone) curveAt(shape, v / 64) / gr4CurveWhite,
      ]);
}
