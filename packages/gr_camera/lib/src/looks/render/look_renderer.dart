import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/looks/look.dart';
import 'package:gr_camera/src/looks/render/gr4/gr4_look_renderer.dart';
import 'package:gr_camera/src/looks/render/render_planes.dart';

/// A colour transform of one pixel: replaces the R, G, B in the list's
/// first three places.
typedef LookTransform = void Function(Float64List rgb);

/// A change to a whole picture, in place: what a look does that depends
/// on where a pixel is or on the pixels around it.
typedef LookFilter = void Function(LookPicture picture);

/// How well a photo's own rendering can be undone before another look is
/// applied to it (research/image-control-processing.md §10).
enum LookSourceFit {
  /// The photo's look is undone closely.
  good,

  /// The photo's look threw information away or added what cannot be taken
  /// out per pixel (crushed or clipped tones, thinned colour, grain,
  /// shading, clarity), so the result is rougher.
  rough,

  /// The look the photo was developed with is not known; it is taken to be
  /// Standard with every adjustment at 0.
  unknown,

  /// The photo's look cannot be undone for the target look at all: a
  /// monochrome photo under a colour look, or a look whose effect is not
  /// per pixel.
  unusable,
}

/// How one camera generation renders looks
/// (research/image-control-processing.md §10). Colour and tone are per
/// pixel and come in two halves that meet in scene-linear RGB, so a photo
/// developed with one look can be shown under another; what a look does
/// to the picture as a whole (shading, clarity, grain) comes as filters
/// to run before and after them.
///
/// Each generation has its own implementation, which shares no camera
/// knowledge with the others \[design\]: a new generation is added beside
/// them, and none changes when another does.
abstract interface class LookRenderer {
  /// How well a photo developed with [source] can be shown under [target].
  /// Never [LookSourceFit.unknown], which is for a photo without a known
  /// look ([LookRerender]).
  LookSourceFit sourceFit(Look source, Look target);

  /// From the encoded R, G, B (0..1) of a photo developed with [source]
  /// back to scene-linear RGB; null when [source]'s rendering has no
  /// inverse. Best effort: what the look clipped stays clipped.
  LookTransform? decoder(Look source);

  /// From scene-linear RGB to the encoded R, G, B (0..1) of a photo
  /// developed with [target]; null when the renderer does not know
  /// [target]'s base image.
  LookTransform? encoder(Look target);

  /// Takes out of a photo developed with [source] what the look did to the
  /// picture as a whole, as far as that can be taken out, leaving a
  /// picture [decoder] applies to; null when there is nothing to take out.
  LookFilter? unfilter(Look source);

  /// What [target] does to the picture as a whole, after [encoder], for a
  /// photo developed with [source]: what [unfilter] could not take out of
  /// the photo is still in it. Null when it does nothing.
  LookFilter? filter(Look target, {required Look source});

  /// The long side, in pixels, of the picture the filters come out best
  /// on. They work on a small copy of the photo, and how closely they
  /// follow the camera depends on that copy's size.
  int get pictureLongSide;
}

/// The renderer for [camera]'s looks. Only the GR IV family's processing
/// is implemented, so every camera gets it for now \[design\]: the GR III
/// family, whose curves are the same and whose colour differs
/// (image-control-processing.md §9), and a camera that is not known.
LookRenderer lookRendererFor(CameraBody camera) => const Gr4LookRenderer();

/// A table of the colour a renderer gives for each colour of a photo: the
/// whole per-pixel effect of showing the photo under another look.
@immutable
final class LookLut {
  /// A table of [size] steps per channel holding [rgba].
  const new(this.size, this.rgba);

  /// A table that changes nothing.
  factory identity({int size = 2}) {
    final rgba = Uint8List(size * size * size * 4);
    final scale = 255 / (size - 1);
    var at = 0;
    for (var g = 0; g < size; g++) {
      for (var b = 0; b < size; b++) {
        for (var r = 0; r < size; r++) {
          rgba[at++] = (r * scale).round();
          rgba[at++] = (g * scale).round();
          rgba[at++] = (b * scale).round();
          rgba[at++] = 255;
        }
      }
    }
    return LookLut(size, rgba);
  }

  /// The number of steps per channel: input value `i / (size − 1)` is step
  /// `i`.
  final int size;

  /// The table as an RGBA image of `size · size` by `size` pixels, opaque:
  /// the output for input steps (r, g, b) is the pixel at column
  /// `b · size + r` of row `g`.
  final Uint8List rgba;

  /// The output for input steps ([r], [g], [b]), as 8-bit R, G, B.
  (int, int, int) at(int r, int g, int b) {
    final i = ((g * size + b) * size + r) * 4;
    return (rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  /// Replaces the R, G, B (0 to 255) in [rgb] with the table's colour for
  /// them, blended from the eight entries around them.
  void recolour(Float64List rgb) {
    final perCode = (size - 1) / 255;
    final r = rgb[0] * perCode;
    final g = rgb[1] * perCode;
    final b = rgb[2] * perCode;
    final lowR = r.floor().clamp(0, size - 2);
    final lowG = g.floor().clamp(0, size - 2);
    final lowB = b.floor().clamp(0, size - 2);
    final partR = r - lowR;
    final partG = g - lowG;
    final partB = b - lowB;
    final nextB = size * 4;
    final nextG = size * nextB;
    final first = ((lowG * size + lowB) * size + lowR) * 4;
    for (var channel = 0; channel < 3; channel++) {
      final i = first + channel;
      final near = _between(
        _between(rgba[i], rgba[i + 4], partR),
        _between(rgba[i + nextB], rgba[i + nextB + 4], partR),
        partB,
      );
      final far = _between(
        _between(rgba[i + nextG], rgba[i + nextG + 4], partR),
        _between(rgba[i + nextG + nextB], rgba[i + nextG + nextB + 4], partR),
        partB,
      );
      rgb[channel] = _between(near, far, partG);
    }
  }

  static double _between(num low, num high, double part) =>
      low + (high - low) * part;
}

/// A photo developed with one look, shown under others: undoes the photo's
/// own rendering once and applies each target look to the result.
final class LookRerender {
  /// For a photo developed with [source] on a camera [renderer] renders
  /// for; a null [source] is a photo whose look is not known. Tables get
  /// [size] steps per channel: 49 unless told otherwise \[design\]. Between
  /// its entries a table is only as good as straight lines are, and a look
  /// bends most where a channel clips. In the worst pair of looks measured
  /// the worst hundredth of the colours is 2.3 codes or more from the
  /// renderer's own answer with 49 steps and 4.3 with 33
  /// (research/image-control-processing.md §10.1).
  new(this.renderer, {required this.source, this.size = 49})
    : _decoder = renderer.decoder(source ?? Look.onBase(LookBase.standard));

  /// The camera generation's rendering.
  final LookRenderer renderer;

  /// The look the photo was developed with; null when it is not known.
  final Look? source;

  /// The steps per channel of the tables [lutFor] makes.
  final int size;

  final LookTransform? _decoder;

  /// The scene-linear R, G, B of every table entry, in the table's order:
  /// the same for every target look, so worked out once.
  Float64List? _scene;

  /// The look the photo is taken to be developed with.
  Look get _source => source ?? Look.onBase(LookBase.standard);

  /// The long side, in pixels, of the copy of the photo to give [render].
  int get pictureLongSide => renderer.pictureLongSide;

  /// Works out now what every target look shares, which is otherwise
  /// left until the first one is asked for: a copy of this object, such
  /// as another isolate gets, would work it out again.
  void prepare() {
    if (_decoder != null) _scene ??= _decodeGrid();
  }

  /// How well the photo can be shown under [target].
  LookSourceFit fitFor(Look target) {
    final source = this.source;
    return source == null
        ? LookSourceFit.unknown
        : renderer.sourceFit(source, target);
  }

  /// Whether the photo can be shown under [target]: not when its own look
  /// cannot be undone for it ([LookSourceFit.unusable]) or the renderer
  /// does not know [target]'s base image.
  bool _shows(Look target) =>
      _decoder != null &&
      renderer.encoder(target) != null &&
      fitFor(target) != LookSourceFit.unusable;

  /// Whether showing the photo under [target] takes more than
  /// [lutFor]'s table: [target], or the photo's own look, does something
  /// to the picture as a whole, which only [render] shows.
  bool filters(Look target) =>
      _shows(target) &&
      (renderer.unfilter(_source) != null ||
          renderer.filter(target, source: _source) != null);

  /// The photo in [rgba], [width] by [height] pixels of 8-bit R, G, B and
  /// alpha row by row, as it would look developed with [target]: the
  /// photo's own look taken out, [target]'s colour and tone put in and
  /// then what [target] does to the picture as a whole. A photo that
  /// cannot be shown under [target] comes back as it is.
  Uint8List render(
    Uint8List rgba, {
    required int width,
    required int height,
    required Look target,
  }) {
    if (!_shows(target)) return rgba;
    final lut = lutFor(target);
    final before = renderer.unfilter(_source);
    final after = renderer.filter(target, source: _source);
    if (before == null && after == null) {
      final out = Uint8List(rgba.length);
      final pixel = Float64List(3);
      for (var i = 0; i < rgba.length; i += 4) {
        pixel[0] = rgba[i].toDouble();
        pixel[1] = rgba[i + 1].toDouble();
        pixel[2] = rgba[i + 2].toDouble();
        lut.recolour(pixel);
        out[i] = pixel[0].round();
        out[i + 1] = pixel[1].round();
        out[i + 2] = pixel[2].round();
        out[i + 3] = 255;
      }
      return out;
    }
    final picture = LookPicture.fromRgba(rgba, width, height);
    before?.call(picture);
    picture.recolourEach(lut.recolour);
    after?.call(picture);
    return picture.toRgba();
  }

  /// The table that shows the photo under [target]. It changes nothing
  /// when the photo cannot be shown under it ([LookSourceFit.unusable]) or
  /// the renderer does not know [target]'s base image.
  LookLut lutFor(Look target) {
    final encoder = renderer.encoder(target);
    if (encoder == null || !_shows(target)) {
      return LookLut.identity(size: size);
    }
    final scene = _scene ??= _decodeGrid();
    final count = size * size * size;
    final rgba = Uint8List(count * 4);
    final pixel = Float64List(3);
    for (var i = 0; i < count; i++) {
      pixel[0] = scene[i * 3];
      pixel[1] = scene[i * 3 + 1];
      pixel[2] = scene[i * 3 + 2];
      encoder(pixel);
      rgba[i * 4] = (pixel[0] * 255).round();
      rgba[i * 4 + 1] = (pixel[1] * 255).round();
      rgba[i * 4 + 2] = (pixel[2] * 255).round();
      rgba[i * 4 + 3] = 255;
    }
    return LookLut(size, rgba);
  }

  Float64List _decodeGrid() {
    final decoder = _decoder!;
    final scene = Float64List(size * size * size * 3);
    final pixel = Float64List(3);
    final scale = 1 / (size - 1);
    var at = 0;
    for (var g = 0; g < size; g++) {
      for (var b = 0; b < size; b++) {
        for (var r = 0; r < size; r++) {
          pixel[0] = r * scale;
          pixel[1] = g * scale;
          pixel[2] = b * scale;
          decoder(pixel);
          scene[at++] = pixel[0];
          scene[at++] = pixel[1];
          scene[at++] = pixel[2];
        }
      }
    }
    return scene;
  }
}
