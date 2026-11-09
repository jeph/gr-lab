import 'package:flutter/material.dart';
import 'package:grlab/src/theme/tokens.dart';

/// A line drawing of a GR seen from the back (mock direction H, "Drawn"): a
/// GR IV traced to scale from Ricoh's rear product photo, with the screen,
/// the ADJ thumbwheel, the +/− rocker and the four-way pad, and the hot
/// shoe and mode dial along the top. Drawn in the theme's colours; [on]
/// lights the screen.
class CameraDrawing extends StatelessWidget {
  const new({super.key, this.on = false, this.strokeWidth = 1.6});

  /// Width over height of the drawing.
  static const double aspectRatio =
      _CameraPainter.width / _CameraPainter.height;

  /// The camera is switched on.
  final bool on;

  /// Width of the outlines in logical pixels, whatever the drawing's size.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio,
    child: CustomPaint(
      painter: _CameraPainter(
        colors: GrColors.of(context),
        on: on,
        strokeWidth: strokeWidth,
      ),
    ),
  );
}

class _CameraPainter extends CustomPainter {
  new({required this.colors, required this.on, required this.strokeWidth});

  /// The drawing's own coordinates, those of the mock's SVG.
  static const double width = 300;
  static const double height = 176;

  /// Below this scale the thumbwheel's and mode dial's grooves run
  /// together, so they are left out.
  static const double _grooveScale = .5;

  // The screen stays dark in the light theme too: it is glass.
  static const _screenOff = Color(0xFF0B0B0C);
  static const _screenOn = Color(0xFF2A2B30);

  final GrColors colors;
  final bool on;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / width;
    canvas.scale(scale);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth / scale
      ..color = colors.t1.withValues(alpha: .88);
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = line.strokeWidth * .62
      ..color = line.color;
    final grooves = scale >= _grooveScale;

    void rect(double x, double y, double w, double h, double r, {Color? fill}) {
      final shape = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(r),
      );
      if (fill != null) canvas.drawRRect(shape, Paint()..color = fill);
      canvas.drawRRect(shape, line);
    }

    void vertical(double x, double top, double length) =>
        canvas.drawLine(Offset(x, top), Offset(x, top + length), fine);

    // Hot shoe and mode dial, behind the body's top edge.
    rect(82.2, 2.5, 57.3, 6, 1.5);
    rect(255.8, 1.5, 36.7, 8, 2);
    if (grooves) {
      for (var x = 259.0; x <= 287; x += 4) {
        vertical(x, 2.5, 6);
      }
    }

    rect(4, 8, 292, 164, 9, fill: colors.s2);

    // Screen.
    const screen = Rect.fromLTWH(7.5, 23.4, 206.3, 145);
    rect(
      screen.left,
      screen.top,
      screen.width,
      screen.height,
      4,
      fill: on ? _screenOn : _screenOff,
    );
    if (on) {
      final glare = Path()
        ..moveTo(screen.left + 8, screen.top + 6)
        ..lineTo(screen.left + 100, screen.top + 6)
        ..lineTo(screen.left + 40, screen.bottom - 6)
        ..lineTo(screen.left + 8, screen.bottom - 6)
        ..close();
      canvas.drawPath(
        glare,
        Paint()..color = Colors.white.withValues(alpha: .06),
      );
    }

    // ADJ thumbwheel.
    rect(226.1, 25.2, 29.7, 10.9, 2.5);
    if (grooves) {
      for (var x = 230.1; x <= 248; x += 3.5) {
        vertical(x, 27.2, 6.9);
      }
    }

    // +/− rocker.
    rect(280.7, 23.4, 10.8, 39.9, 5.4);
    canvas
      ..drawLine(const Offset(283.1, 31.4), const Offset(289.1, 31.4), fine)
      ..drawLine(const Offset(286.1, 28.4), const Offset(286.1, 34.4), fine)
      ..drawLine(const Offset(283.1, 55.3), const Offset(289.1, 55.3), fine)
      // Four-way pad and OK button.
      ..drawCircle(const Offset(243.5, 114), 23.6, line)
      ..drawCircle(const Offset(243.5, 114), 8.4, line);
  }

  @override
  bool shouldRepaint(_CameraPainter old) =>
      old.colors != colors || old.on != on || old.strokeWidth != strokeWidth;
}
