import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';

/// [image] as it would look developed with [look]: the photo [rerender]
/// was made for, shown under another look.
///
/// The camera layer works the look out (`LookRerender`); this only draws
/// \[design\]. Colour and tone are a table the photo is drawn through at
/// once ([LookTableView]). What a look does to the picture as a whole, such
/// as shading or grain, is worked out away from the UI's thread and takes
/// the table's place when it is ready, so while a slider moves the picture
/// can be a change behind.
class LookPreview extends StatefulWidget {
  const new({
    required this.image,
    required this.rerender,
    required this.look,
    super.key,
  });

  final ImageProvider image;

  /// The photo's own look, to be undone.
  final LookRerender rerender;

  /// The look to show the photo under.
  final Look look;

  @override
  State<LookPreview> createState() => _LookPreviewState();
}

class _LookPreviewState extends State<LookPreview> {
  late LookLut _lut = widget.rerender.lutFor(widget.look);
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onPhoto,
    onError: (_, _) {},
  );
  ImageInfo? _photo;

  /// The whole picture under the look, once worked out; null while the
  /// table alone shows the look.
  ui.Image? _filtered;

  /// Whether a picture is being worked out, and whether the photo or the
  /// look changed since that began.
  bool _filtering = false;
  bool _changed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolvePhoto();
  }

  @override
  void didUpdateWidget(LookPreview old) {
    super.didUpdateWidget(old);
    if (widget.image != old.image) _resolvePhoto();
    if (identical(widget.rerender, old.rerender) &&
        widget.look.settings == old.look.settings) {
      return;
    }
    _lut = widget.rerender.lutFor(widget.look);
    unawaited(_filter());
  }

  void _resolvePhoto() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onPhoto(ImageInfo photo, bool synchronous) {
    _photo?.dispose();
    _photo = photo;
    unawaited(_filter());
  }

  /// Works the whole picture out when the look takes more than the table,
  /// and again when the photo or the look changed meanwhile: one at a
  /// time, each for the latest of both.
  Future<void> _filter() async {
    if (_filtering) {
      _changed = true;
      return;
    }
    _filtering = true;
    try {
      do {
        _changed = false;
        final photo = _photo;
        final rerender = widget.rerender;
        final look = widget.look;
        if (photo == null || !rerender.filters(look)) {
          _show(null);
          continue;
        }
        final picture = await _rendered(photo.image.clone(), rerender, look);
        // A picture for the look of a moment ago still beats none while a
        // slider moves; one of another photo does not.
        if (mounted &&
            identical(photo, _photo) &&
            identical(rerender, widget.rerender) &&
            rerender.filters(widget.look)) {
          _show(picture);
        } else {
          picture?.dispose();
        }
      } while (mounted && _changed);
    } finally {
      _filtering = false;
    }
  }

  /// [photo] as [rerender] renders it under [look], worked out in another
  /// isolate; null when the photo's pixels cannot be read. Disposes
  /// [photo].
  static Future<ui.Image?> _rendered(
    ui.Image photo,
    LookRerender rerender,
    Look look,
  ) async {
    try {
      final pixels = await photo.toByteData();
      if (pixels == null) return null;
      final width = photo.width;
      final height = photo.height;
      // The isolate gets a copy of the rerender: what every look shares is
      // worked out here first, once, so that each copy has it.
      rerender.prepare();
      final rgba = await compute(_render, (
        rerender,
        pixels.buffer.asUint8List(),
        width,
        height,
        look,
      ));
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      return await done.future;
    } finally {
      photo.dispose();
    }
  }

  void _show(ui.Image? picture) {
    if (!mounted) {
      picture?.dispose();
      return;
    }
    if (picture == null && _filtered == null) return;
    setState(() {
      _filtered?.dispose();
      _filtered = picture;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _photo?.dispose();
    _filtered?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (filtered != null && widget.rerender.filters(widget.look)) {
      return RawImage(image: filtered, fit: BoxFit.cover);
    }
    return LookTableView(image: widget.image, lut: _lut);
  }
}

Uint8List _render((LookRerender, Uint8List, int, int, Look) job) {
  final (rerender, rgba, width, height, look) = job;
  return rerender.render(rgba, width: width, height: height, target: look);
}

/// [image] drawn through [lut], filling its box as `BoxFit.cover` does,
/// with a fragment shader that knows nothing about cameras \[design\].
/// Nothing is drawn until the photo, the table and the shader have loaded,
/// and a new table replaces the old one when it is ready, so the picture
/// never shows without its table.
class LookTableView extends StatefulWidget {
  const new({required this.image, required this.lut, super.key});

  final ImageProvider image;
  final LookLut lut;

  @override
  State<LookTableView> createState() => _LookTableViewState();
}

class _LookTableViewState extends State<LookTableView> {
  ui.FragmentShader? _shader;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onPhoto,
    onError: (_, _) {},
  );
  ImageInfo? _photo;

  /// The table as a picture the shader samples, and the table it shows.
  ui.Image? _table;
  LookLut? _tableOf;

  /// The latest table asked for; an older one that finishes decoding later
  /// is dropped.
  LookLut? _wanted;

  @override
  void initState() {
    super.initState();
    unawaited(_loadShader());
    _decodeTable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolvePhoto();
  }

  @override
  void didUpdateWidget(LookTableView old) {
    super.didUpdateWidget(old);
    if (widget.image != old.image) _resolvePhoto();
    if (!identical(widget.lut, old.lut)) _decodeTable();
  }

  Future<void> _loadShader() async {
    // The engine compiles the shader once and hands the same program to
    // every later call.
    final program = await ui.FragmentProgram.fromAsset('shaders/look_lut.frag');
    if (!mounted) return;
    setState(() => _shader = program.fragmentShader());
  }

  void _resolvePhoto() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onPhoto(ImageInfo photo, bool synchronous) {
    setState(() {
      _photo?.dispose();
      _photo = photo;
    });
  }

  void _decodeTable() {
    final lut = widget.lut;
    _wanted = lut;
    ui.decodeImageFromPixels(
      lut.rgba,
      lut.size * lut.size,
      lut.size,
      ui.PixelFormat.rgba8888,
      (table) {
        if (!mounted || !identical(_wanted, lut)) {
          table.dispose();
          return;
        }
        setState(() {
          _table?.dispose();
          _table = table;
          _tableOf = lut;
        });
      },
    );
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _photo?.dispose();
    _table?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final photo = _photo?.image;
    final table = _table;
    final lut = _tableOf;
    if (shader == null || photo == null || table == null || lut == null) {
      return const SizedBox.expand();
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _LookPainter(
        shader: shader,
        photo: photo,
        table: table,
        steps: lut.size,
      ),
    );
  }
}

class _LookPainter extends CustomPainter {
  new({
    required this.shader,
    required this.photo,
    required this.table,
    required this.steps,
  });

  final ui.FragmentShader shader;
  final ui.Image photo;
  final ui.Image table;
  final int steps;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // The part of the photo a box of this shape shows when the photo covers
    // it: the whole of one side, the middle of the other.
    final photoShape = photo.width / photo.height;
    final boxShape = size.width / size.height;
    final shownWidth = boxShape < photoShape ? boxShape / photoShape : 1.0;
    final shownHeight = boxShape < photoShape ? 1.0 : photoShape / boxShape;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, (1 - shownWidth) / 2)
      ..setFloat(3, (1 - shownHeight) / 2)
      ..setFloat(4, shownWidth)
      ..setFloat(5, shownHeight)
      ..setFloat(6, steps.toDouble())
      ..setImageSampler(0, photo, filterQuality: FilterQuality.medium)
      // The shader blends the table's entries itself.
      ..setImageSampler(1, table);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_LookPainter old) =>
      old.shader != shader ||
      old.photo != photo ||
      old.table != table ||
      old.steps != steps;
}
