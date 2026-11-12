import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// A line drawing of a GR seen from the front (mock direction B, "Front",
/// in `design/mockups/camera-drawings.html` in the local research
/// workspace, `../gr`), traced from Ricoh's front product photos: the
/// grip, the shutter button and dials along the top, the lens and the GR
/// logo.
///
/// It shows what tells [body]'s model apart from the front
/// (research/camera-models.md §7): the 40 mm lens of an x body, the silver
/// shutter button of an HDF body and the black finish of the Monochrome.
/// The GR III and GR IV look alike from here, so they share one body.
/// Drawn in the theme's colours, except the Monochrome, which is black in
/// both themes.
class CameraDrawing extends StatelessWidget {
  const new({required this.body, super.key, this.strokeWidth = 1.6});

  /// The camera to draw; one whose model is not known is drawn as a GR
  /// with the 28 mm lens and no focal length on it.
  final CameraBody body;

  /// Width of the outlines in logical pixels, whatever the drawing's size.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final lens40mm = body.supports(CameraFeature.lens40mm);
    return AspectRatio(
      aspectRatio: _CameraPainter.width / _CameraPainter.height,
      child: CustomPaint(
        painter: _CameraPainter(
          colors: GrColors.of(context),
          strokeWidth: strokeWidth,
          lens40mm: lens40mm,
          silverShutterButton: body.supports(CameraFeature.silverShutterButton),
          blackFinish: body.supports(CameraFeature.blackFinish),
          engraving: switch (body.model) {
            null => _CameraPainter.lensName,
            _ when lens40mm => '${_CameraPainter.lensName} f=26.1mm 1:2.8',
            _ => '${_CameraPainter.lensName} f=18.3mm 1:2.8',
          },
        ),
      ),
    );
  }
}

class _CameraPainter extends CustomPainter {
  new({
    required this.colors,
    required this.strokeWidth,
    required this.lens40mm,
    required this.silverShutterButton,
    required this.blackFinish,
    required this.engraving,
  });

  /// The drawing's own coordinates, those of the mock's SVG.
  static const double width = 300;
  static const double height = 176;

  /// Below this scale the grip's grain, the front dial's grooves and the
  /// lens's engraving run together, so they are left out.
  static const double _detailScale = .5;

  /// What the camera carries on its lens and its front. They are its own
  /// markings, the same in every language, so they are not translated.
  static const lensName = 'GR LENS';
  static const _logo = 'GR';

  static const _lens = Offset(188, 96);
  static const _glass = Color(0xFF0B0B0C);
  static const _silver = Color(0xFFB9B8B2);
  static const _black = Color(0xFF0B0B0C);

  final GrColors colors;
  final double strokeWidth;

  /// The larger front element and extra barrel ring of the 26.1 mm lens.
  final bool lens40mm;
  final bool silverShutterButton;

  /// Black body with light outlines in both themes, and a hollow logo
  /// after the camera's black-on-black one.
  final bool blackFinish;

  /// The text round the lens's front. The GR IIIx's `f=26.1mm` is
  /// \[inferred\] from its focal length (research/camera-models.md §7).
  final String engraving;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / width;
    canvas.scale(scale);
    final ink = (blackFinish ? GrColors.dark.t1 : colors.t1).withValues(
      alpha: .88,
    );
    final body = Paint()..color = blackFinish ? _black : colors.s2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth / scale
      ..color = ink;
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = line.strokeWidth * .62
      ..color = ink;
    final detailed = scale >= _detailScale;

    void rect(double x, double y, double w, double h, double r, {Paint? fill}) {
      final shape = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(r),
      );
      if (fill != null) canvas.drawRRect(shape, fill);
      canvas.drawRRect(shape, line);
    }

    void ring(double radius, {Paint? fill, Paint? stroke}) {
      if (fill != null) canvas.drawCircle(_lens, radius, fill);
      canvas.drawCircle(_lens, radius, stroke ?? line);
    }

    // Mode dial and shutter button, behind the body's top edge.
    rect(10, 3.5, 27, 8, 1.5, fill: body);
    rect(
      47,
      1.5,
      44,
      10,
      4,
      fill: silverShutterButton ? (Paint()..color = _silver) : body,
    );

    rect(4, 8, 292, 164, 9, fill: body);
    if (detailed) _grain(canvas, ink);
    canvas
      // Top plate and the grip's edge.
      ..drawLine(const Offset(5, 35), const Offset(295, 35), fine)
      ..drawLine(const Offset(97, 35), const Offset(97, 172), line);

    // Front dial and AF assist lamp.
    rect(38, 11.5, 40, 8, 2);
    if (detailed) {
      for (var x = 42.0; x <= 74; x += 4) {
        canvas.drawLine(Offset(x, 13), Offset(x, 18), fine);
      }
    }
    canvas.drawCircle(const Offset(110, 26.5), 3, fine);

    // Lens: ring cap, barrel, front face, hood and glass.
    ring(72, fill: body);
    ring(64.5, stroke: fine);
    if (lens40mm) ring(58.5, stroke: fine);
    ring(52, fill: body);
    final hood = lens40mm ? 27.0 : 22.5;
    rect(
      _lens.dx - hood,
      _lens.dy - hood,
      hood * 2,
      hood * 2,
      lens40mm ? 11 : 9.5,
    );
    ring(lens40mm ? 16.5 : 11.5, fill: Paint()..color = _glass);
    if (detailed) _engrave(canvas, ink);

    final logo = TextPainter(
      text: TextSpan(
        text: _logo,
        style: TextStyle(
          fontFamily: GrFonts.ui,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1,
          letterSpacing: blackFinish ? 1 : -.3,
          foreground: blackFinish
              ? (Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = .9 / scale
                  ..color = ink)
              : (Paint()..color = ink),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    logo
      ..paint(
        canvas,
        Offset(
          268 - logo.width / 2,
          161 - logo.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        ),
      )
      ..dispose();
  }

  /// The grip's leather grain, as staggered rows of dots.
  void _grain(Canvas canvas, Color ink) {
    final dots = <Offset>[
      for (var row = 0; row < 41; row++)
        for (var x = row.isEven ? 8.0 : 10.5; x <= 94; x += 5)
          Offset(x, 40 + row * 3.2),
    ];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.1
        ..color = ink.withValues(alpha: .37),
    );
  }

  /// Sets [engraving] along the lower half of the lens's front, letter
  /// tops towards the glass, as it runs on the camera.
  void _engrave(Canvas canvas, Color ink) {
    const radius = 45.0;
    const spacing = .35;
    final style = TextStyle(
      fontFamily: GrFonts.ui,
      fontSize: 6.4,
      fontWeight: FontWeight.w500,
      height: 1,
      color: ink,
    );
    final letters = [
      for (final letter in engraving.split(''))
        TextPainter(
          text: TextSpan(text: letter, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final length =
        letters.fold<double>(0, (sum, letter) => sum + letter.width) +
        spacing * (letters.length - 1);
    var along = -length / 2;
    for (final letter in letters) {
      final width = letter.width;
      // Measured from straight down, growing to the right.
      final angle = (along + width / 2) / radius;
      canvas
        ..save()
        ..translate(
          _lens.dx + radius * math.sin(angle),
          _lens.dy + radius * math.cos(angle),
        )
        ..rotate(-angle);
      letter
        ..paint(
          canvas,
          Offset(
            -width / 2,
            -letter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          ),
        )
        ..dispose();
      canvas.restore();
      along += width + spacing;
    }
  }

  @override
  bool shouldRepaint(_CameraPainter old) =>
      old.colors != colors ||
      old.strokeWidth != strokeWidth ||
      old.lens40mm != lens40mm ||
      old.silverShutterButton != silverShutterButton ||
      old.blackFinish != blackFinish ||
      old.engraving != engraving;
}
