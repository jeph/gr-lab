import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/looks/look.dart';
import 'package:gr_camera/src/looks/render/gr4/gr4_look_renderer.dart';

/// A colour transform of one pixel: replaces the R, G, B in the list's
/// first three places.
typedef LookTransform = void Function(Float64List rgb);

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

/// How one camera generation renders looks, per pixel and as far as colour
/// and tone go (research/image-control-processing.md §10): in two halves
/// that meet in scene-linear RGB, so a photo developed with one look can be
/// shown under another.
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
}

/// The renderer for [camera]'s looks. Only the GR IV family's processing
/// is implemented, so every camera gets it for now \[design\]: the GR III
/// family, whose curves are the same and whose colour differs
/// (image-control-processing.md §9), and a camera that is not known.
LookRenderer lookRendererFor(CameraBody camera) => const Gr4LookRenderer();

/// A table of the colour a renderer gives for each colour of a photo: the
/// whole per-pixel effect of showing the photo under another look, for
/// drawing with any model-agnostic sampler.
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
}

/// A photo developed with one look, shown under others: undoes the photo's
/// own rendering once and applies each target look to the result.
final class LookRerender {
  /// For a photo developed with [source] on a camera [renderer] renders
  /// for; a null [source] is a photo whose look is not known. Tables get
  /// [size] steps per channel.
  new(this.renderer, {required this.source, this.size = 33})
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
  late final Float64List _scene = _decodeGrid();

  /// How well the photo can be shown under [target].
  LookSourceFit fitFor(Look target) {
    final source = this.source;
    return source == null
        ? LookSourceFit.unknown
        : renderer.sourceFit(source, target);
  }

  /// The table that shows the photo under [target]. It changes nothing
  /// when the photo cannot be shown under it ([LookSourceFit.unusable]) or
  /// the renderer does not know [target]'s base image.
  LookLut lutFor(Look target) {
    final encoder = renderer.encoder(target);
    if (encoder == null ||
        _decoder == null ||
        fitFor(target) == LookSourceFit.unusable) {
      return LookLut.identity(size: size);
    }
    final scene = _scene;
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
