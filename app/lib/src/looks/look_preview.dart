import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';

/// [image] drawn through [lut], filling its box as `BoxFit.cover` does: the
/// photo as another look would render it.
///
/// The camera layer works the look out into the colour table
/// (`LookRerender`); this only draws, with a fragment shader that knows
/// nothing about cameras \[design\]. Nothing is drawn until the photo, the
/// table and the shader have loaded, and a new table replaces the old one
/// when it is ready, so the picture never shows without a look.
class LookPreview extends StatefulWidget {
  const new({required this.image, required this.lut, super.key});

  final ImageProvider image;
  final LookLut lut;

  @override
  State<LookPreview> createState() => _LookPreviewState();
}

class _LookPreviewState extends State<LookPreview> {
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
  void didUpdateWidget(LookPreview old) {
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
