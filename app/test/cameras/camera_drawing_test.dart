import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/cameras/camera_drawing.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// What the drawing of [model] puts on a canvas [width] wide, in the
/// theme of [colors].
Future<List<Invocation>> _drawn(
  WidgetTester tester,
  GrModel? model, {
  GrColors colors = GrColors.dark,
  double width = 300,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // A new app for each theme: a change of theme within one is animated
      // and lands on blended colours.
      key: ValueKey(colors),
      theme: grTheme(colors),
      home: Center(
        child: CameraDrawing(body: CameraBody(model: model, firmware: null)),
      ),
    ),
  );
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(CameraDrawing),
      matching: find.byType(CustomPaint),
    ),
  );
  final canvas = TestRecordingCanvas();
  paint.painter!.paint(canvas, Size(width, width / 300 * 176));
  return [for (final recorded in canvas.invocations) recorded.invocation];
}

/// The radii of the circles drawn, in order: the lens's rings and glass
/// among them.
List<double> _circles(List<Invocation> drawn) => [
  for (final call in drawn)
    if (call.memberName == #drawCircle) call.positionalArguments[1] as double,
];

/// Every colour a shape is drawn in, outline or fill.
Set<Color> _colors(List<Invocation> drawn) => {
  for (final call in drawn)
    if (call.memberName == #drawRRect || call.memberName == #drawCircle)
      (call.positionalArguments.last as Paint).color,
};

/// How many pieces of text are drawn: the logo and the engraving's
/// letters.
int _letters(List<Invocation> drawn) =>
    drawn.where((call) => call.memberName == #drawParagraph).length;

void main() {
  testWidgets('an x body is drawn with the larger 40 mm lens', (tester) async {
    final standard = _circles(await _drawn(tester, GrModel.gr3));
    final long = _circles(await _drawn(tester, GrModel.gr3x));

    expect(long, hasLength(standard.length + 1), reason: 'extra barrel ring');
    expect(long.last, greaterThan(standard.last), reason: 'front element');
    for (final model in [GrModel.gr3xHdf, GrModel.gr4x]) {
      expect(_circles(await _drawn(tester, model)), long, reason: model.name);
    }
    for (final model in [
      GrModel.gr3Hdf,
      GrModel.gr4,
      GrModel.gr4Hdf,
      GrModel.gr4Monochrome,
    ]) {
      expect(
        _circles(await _drawn(tester, model)),
        standard,
        reason: model.name,
      );
    }
  });

  testWidgets('only an HDF body has a shutter button in another colour', (
    tester,
  ) async {
    for (final (plain, hdf) in [
      (GrModel.gr3, GrModel.gr3Hdf),
      (GrModel.gr3x, GrModel.gr3xHdf),
      (GrModel.gr4, GrModel.gr4Hdf),
    ]) {
      final plainColors = _colors(await _drawn(tester, plain));
      final hdfColors = _colors(await _drawn(tester, hdf));
      expect(hdfColors.difference(plainColors), hasLength(1), reason: hdf.name);
      expect(plainColors.difference(hdfColors), isEmpty, reason: hdf.name);
    }
  });

  testWidgets('the Monochrome is black in both themes', (tester) async {
    Future<Set<Color>> colors(GrModel model, GrColors theme) async =>
        _colors(await _drawn(tester, model, colors: theme));

    // A `Paint` keeps its colour in 32-bit floats, so a theme colour read
    // back from one is compared with a tolerance.
    final lightBody = isSameColorAs(GrColors.light.s2);
    final dark = await colors(GrModel.gr4Monochrome, GrColors.dark);
    final light = await colors(GrModel.gr4Monochrome, GrColors.light);
    expect(light, dark);
    expect(light, isNot(contains(lightBody)));

    // Every other body follows the theme.
    final standard = await colors(GrModel.gr4, GrColors.light);
    expect(standard, isNot(await colors(GrModel.gr4, GrColors.dark)));
    expect(standard, contains(lightBody));
  });

  testWidgets('a camera of unknown model has no focal length on its lens', (
    tester,
  ) async {
    final known = await _drawn(tester, GrModel.gr3);
    final unknown = await _drawn(tester, null);

    expect(_circles(unknown), _circles(known));
    expect(_colors(unknown), _colors(known));
    expect(_letters(unknown), lessThan(_letters(known)));
    expect(_letters(unknown), greaterThan(1), reason: 'still a GR lens');
  });

  testWidgets('a small drawing leaves out the grain and the engraving', (
    tester,
  ) async {
    final large = await _drawn(tester, GrModel.gr4);
    final small = await _drawn(tester, GrModel.gr4, width: 40);

    bool grain(Invocation call) => call.memberName == #drawPoints;
    expect(large.where(grain), isNotEmpty);
    expect(small.where(grain), isEmpty);
    expect(_letters(small), 1, reason: 'the logo alone');
    expect(_circles(small), _circles(large));
  });
}
