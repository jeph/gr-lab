import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/looks/look_compare.dart';
import 'package:grlab/src/looks/look_preview.dart';
import 'package:grlab/src/looks/look_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';

import '../support/test_app.dart';

const List<int> _red = [200, 40, 40, 255];
const List<int> _blue = [40, 40, 200, 255];

final LookRenderer _renderer = lookRendererFor(CameraBody.unknown);
final Look _standard = Look.onBase(LookBase.standard);
final Look _monotone = Look.onBase(LookBase.monotone);

void main() {
  const boundary = Key('boundary');
  final compare = find.byType(LookCompare);

  /// A Standard photo of [width] by [height] pixels as stored, whose left
  /// half is [_red] and whose right half is [_blue], which [orientation]
  /// shows upright.
  Future<PreviewPhoto> photoOf(
    WidgetTester tester, {
    int width = 12,
    int height = 8,
    int? orientation,
  }) async => PreviewPhoto(
    image: MemoryImage(
      (await tester.runAsync(() async {
        final done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          Uint8List.fromList([
            for (var y = 0; y < height; y++)
              for (var x = 0; x < width; x++) ...(x < width / 2 ? _red : _blue),
          ]),
          width,
          height,
          ui.PixelFormat.rgba8888,
          done.complete,
        );
        final picture = await done.future;
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        return png!.buffer.asUint8List();
      }))!,
    ),
    rerender: LookRerender(_renderer, source: _standard),
    orientation: orientation,
  );

  /// Shows [photo] under [look] in a box of [width] by [height], and waits
  /// for the picture under the look to be drawn.
  Future<void> show(
    WidgetTester tester,
    PreviewPhoto photo, {
    required LookCompareMode mode,
    Look? look,
    double width = 120,
    double height = 120,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: grTheme(GrColors.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: width,
              height: height,
              child: LookCompare(
                photo: photo,
                look: look ?? _standard,
                mode: mode,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(LookPreview),
        matching: find.byType(CustomPaint),
      ),
    );
  }

  /// The colour drawn [across] and [down] the box, each 0..1.
  Future<List<int>> colourAt(
    WidgetTester tester, {
    required double across,
    required double down,
  }) async {
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    return (await tester.runAsync(() async {
      final shot = await render.toImage();
      final bytes = await shot.toByteData();
      final x = (across * (shot.width - 1)).round();
      final y = (down * (shot.height - 1)).round();
      final at = (y * shot.width + x) * 4;
      return bytes!.buffer.asUint8List().sublist(at, at + 4);
    }))!;
  }

  Matcher near(List<int> colour) => pairwiseCompare<int, int>(
    colour,
    (wanted, actual) => (wanted - actual).abs() <= 6,
    'within 6 of',
  );

  /// A grey: what a black-and-white look makes of a colour.
  final grey = predicate<List<int>>(
    (c) => (c[0] - c[1]).abs() <= 3 && (c[1] - c[2]).abs() <= 3 && c[3] == 255,
    'a grey',
  );

  /// Nothing of the photo: the box's own ground.
  final empty = predicate<List<int>>(
    (c) => c[0] < 30 && c[1] < 30 && c[2] < 30,
    'none of the photo',
  );

  group('a photo is shown whole and upright:', () {
    testWidgets('one stored as it was held keeps its shape', (tester) async {
      await show(tester, await photoOf(tester), mode: LookCompareMode.single);
      // 120 by 80 in the middle of a box of 120 by 120.
      expect(await colourAt(tester, across: .25, down: .5), near(_red));
      expect(await colourAt(tester, across: .75, down: .5), near(_blue));
      expect(await colourAt(tester, across: .5, down: .08), empty);
      expect(await colourAt(tester, across: .5, down: .92), empty);
    });

    testWidgets('one held on its side is turned the way its orientation '
        'says and takes the upright shape', (tester) async {
      // Orientation 6 turns the stored picture clockwise: its left is the
      // top.
      await show(
        tester,
        await photoOf(tester, orientation: 6),
        mode: LookCompareMode.single,
      );
      expect(await colourAt(tester, across: .5, down: .25), near(_red));
      expect(await colourAt(tester, across: .5, down: .75), near(_blue));
      expect(await colourAt(tester, across: .08, down: .5), empty);
      expect(await colourAt(tester, across: .92, down: .5), empty);

      // Orientation 8 turns it the other way: its left is the bottom.
      await show(
        tester,
        await photoOf(tester, orientation: 8),
        mode: LookCompareMode.single,
      );
      expect(await colourAt(tester, across: .5, down: .25), near(_blue));
      expect(await colourAt(tester, across: .5, down: .75), near(_red));
    });

    testWidgets('the photo as it is is turned with it', (tester) async {
      await show(
        tester,
        await photoOf(tester, orientation: 6),
        mode: LookCompareMode.single,
      );
      await tester.tap(find.byKey(const Key('look-compare-single')));
      await tester.pump();
      expect(find.text('BEFORE'), findsOneWidget);
      expect(await colourAt(tester, across: .5, down: .25), near(_red));
      expect(await colourAt(tester, across: .5, down: .75), near(_blue));
      expect(await colourAt(tester, across: .08, down: .5), empty);
    });
  });

  testWidgets('sliding shows the photo as it is left of the divider and '
      'under the look right of it, wherever the divider is put', (
    tester,
  ) async {
    final slide = find.byKey(const Key('look-compare-slide'));
    await show(
      tester,
      await photoOf(tester),
      mode: LookCompareMode.slide,
      look: _monotone,
      height: 80,
    );
    expect(find.text('BEFORE'), findsOneWidget);
    expect(find.text('APPROXIMATE'), findsOneWidget);
    // The divider starts in the middle.
    expect(await colourAt(tester, across: .25, down: .15), near(_red));
    expect(await colourAt(tester, across: .75, down: .15), grey);

    final box = tester.getRect(slide);
    Offset at(double across) =>
        box.topLeft + Offset(box.width * across, box.height * .15);
    await tester.dragFrom(at(.5), Offset(box.width * .4, 0));
    await tester.pump();
    expect(await colourAt(tester, across: .85, down: .15), near(_blue));
    expect(await colourAt(tester, across: .97, down: .15), grey);

    await tester.tapAt(at(.1));
    await tester.pump();
    expect(await colourAt(tester, across: .04, down: .15), near(_red));
    expect(await colourAt(tester, across: .25, down: .15), grey);

    // Past the picture's edge the divider stops at it.
    await tester.dragFrom(at(.1), Offset(-box.width, 0));
    await tester.pump();
    expect(await colourAt(tester, across: .02, down: .15), grey);
    await tester.dragFrom(at(.05), Offset(box.width * 2, 0));
    await tester.pump();
    expect(await colourAt(tester, across: .98, down: .15), near(_blue));
  });

  testWidgets('one at a time shows the photo under the look, and a tap '
      'swaps it with the photo as it is', (tester) async {
    final single = find.byKey(const Key('look-compare-single'));
    await show(
      tester,
      await photoOf(tester),
      mode: LookCompareMode.single,
      look: _monotone,
      height: 80,
    );
    expect(find.text('APPROXIMATE'), findsOneWidget);
    expect(find.text('BEFORE'), findsNothing);
    expect(await colourAt(tester, across: .25, down: .3), grey);

    await tester.tap(single);
    await tester.pump();
    expect(find.text('BEFORE'), findsOneWidget);
    expect(find.text('APPROXIMATE'), findsNothing);
    expect(await colourAt(tester, across: .25, down: .3), near(_red));
    expect(await colourAt(tester, across: .75, down: .3), near(_blue));

    await tester.tap(single);
    await tester.pump();
    expect(find.text('APPROXIMATE'), findsOneWidget);
    expect(await colourAt(tester, across: .25, down: .3), grey);
  });

  testWidgets('one at a time: its tag swaps the pictures, from a little '
      'around it too', (tester) async {
    final swap = find.byKey(const Key('look-compare-swap'));
    await show(
      tester,
      await photoOf(tester),
      mode: LookCompareMode.single,
      look: _monotone,
      height: 80,
    );
    expect(find.text('APPROXIMATE'), findsOneWidget);
    expect(
      tester.getSemantics(swap),
      isSemantics(
        isButton: true,
        hint: 'Swaps between before and the look',
        hasTapAction: true,
      ),
    );

    await tester.tap(find.text('APPROXIMATE'));
    await tester.pump();
    expect(find.text('BEFORE'), findsOneWidget);
    expect(await colourAt(tester, across: .25, down: .3), near(_red));

    final tag = tester.getRect(find.byType(PhotoTag));
    expect(tag.height, lessThan(30), reason: 'small enough to miss');
    await tester.tapAt(tag.topRight + const Offset(10, -10));
    await tester.pump();
    expect(find.text('APPROXIMATE'), findsOneWidget);
    expect(await colourAt(tester, across: .25, down: .3), grey);
  });

  testWidgets('without a look the photo is shown alone as it is, whole and '
      'upright, whichever way of comparing is picked', (tester) async {
    final asTaken = find.byKey(const Key('look-compare-as-taken'));
    // Stored 12 by 8 and turned a quarter: 8 by 12 upright.
    final photo = await photoOf(tester, orientation: 6);
    for (final mode in LookCompareMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: grTheme(GrColors.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 80,
                height: 120,
                child: LookCompare(photo: photo, look: null, mode: mode),
              ),
            ),
          ),
        ),
      );
      await pumpUntilFound(tester, asTaken);
      await pumpUntilFound(
        tester,
        find.descendant(of: asTaken, matching: find.byType(RawImage)),
      );
      expect(find.byType(LookPreview), findsNothing, reason: mode.name);
      expect(find.text('BEFORE'), findsNothing, reason: mode.name);
      expect(find.text('APPROXIMATE'), findsNothing, reason: mode.name);
      // The stored left half is the top once upright.
      expect(await colourAt(tester, across: .5, down: .2), near(_red));
      expect(await colourAt(tester, across: .5, down: .8), near(_blue));
    }
  });

  testWidgets('side by side shows both whole, next to each other or one '
      'above the other, whichever shows them larger', (tester) async {
    final before = find.byKey(const Key('look-compare-before'));
    final look = find.byKey(const Key('look-compare-look'));

    // A wide photo in a tall box: one above the other.
    final wide = await photoOf(tester);
    await show(
      tester,
      wide,
      mode: LookCompareMode.sideBySide,
      look: _monotone,
      height: 300,
    );
    expect(tester.getSize(before), const Size(120, 80));
    expect(tester.getSize(look), const Size(120, 80));
    expect(tester.getRect(before).bottom, lessThan(tester.getRect(look).top));
    expect(tester.getRect(before).left, tester.getRect(look).left);
    // Together in the middle of the box.
    expect(
      tester.getRect(before).top - tester.getRect(compare).top,
      closeTo(tester.getRect(compare).bottom - tester.getRect(look).bottom, 1),
    );

    // The same photo in a wide box: next to each other.
    await show(
      tester,
      wide,
      mode: LookCompareMode.sideBySide,
      look: _monotone,
      width: 302,
      height: 100,
    );
    expect(tester.getSize(before), const Size(150, 100));
    expect(tester.getSize(look), const Size(150, 100));
    expect(tester.getRect(before).right, lessThan(tester.getRect(look).left));
    expect(await colourAt(tester, across: .1, down: .3), near(_red));
    expect(await colourAt(tester, across: .4, down: .3), near(_blue));
    expect(await colourAt(tester, across: .6, down: .3), grey);

    // A photo held on its side in a box of the first one's shape: next to
    // each other, since upright it is tall.
    await show(
      tester,
      await photoOf(tester, orientation: 6),
      mode: LookCompareMode.sideBySide,
      width: 162,
    );
    expect(tester.getSize(before), const Size(80, 120));
    expect(tester.getRect(before).right, lessThan(tester.getRect(look).left));
  });

  testWidgets('a photo with a look to be compared from is shown under it as '
      'the before picture, and as it is where it cannot be shown under the '
      'look it is compared with', (tester) async {
    final plain = await photoOf(tester);
    final photo = PreviewPhoto(
      image: plain.image,
      rerender: plain.rerender,
      before: _monotone,
    );

    await show(
      tester,
      photo,
      mode: LookCompareMode.sideBySide,
      width: 302,
      height: 100,
    );
    await pumpRounds(tester, 5);
    expect(await colourAt(tester, across: .1, down: .3), grey);
    expect(await colourAt(tester, across: .4, down: .3), grey);
    expect(await colourAt(tester, across: .6, down: .3), near(_red));
    expect(await colourAt(tester, across: .9, down: .3), near(_blue));

    // The divider is in the middle: before on its left.
    await show(tester, photo, mode: LookCompareMode.slide, height: 80);
    await pumpRounds(tester, 5);
    expect(await colourAt(tester, across: .25, down: .3), grey);
    expect(await colourAt(tester, across: .75, down: .3), near(_blue));

    // A base image GR Lab does not know: the look's picture is the photo
    // as it is, and so is the one before.
    await show(
      tester,
      photo,
      mode: LookCompareMode.sideBySide,
      look: Look.fromBytes(Uint8List.fromList([1, 0, 0x7f, 0])),
      width: 302,
      height: 100,
    );
    await pumpRounds(tester, 5);
    expect(await colourAt(tester, across: .1, down: .3), near(_red));
    expect(await colourAt(tester, across: .4, down: .3), near(_blue));
    expect(await colourAt(tester, across: .6, down: .3), near(_red));
    expect(await colourAt(tester, across: .9, down: .3), near(_blue));
  });

  testWidgets('another way of comparing keeps the picture already worked '
      'out, and another photo of another shape takes its own', (tester) async {
    final preview = find.byType(LookPreview);
    final wide = await photoOf(tester);
    await show(tester, wide, mode: LookCompareMode.slide, look: _monotone);
    final state = tester.state(preview);
    for (final mode in [
      LookCompareMode.sideBySide,
      LookCompareMode.single,
      LookCompareMode.slide,
    ]) {
      await show(tester, wide, mode: mode, look: _monotone);
      expect(tester.state(preview), same(state), reason: mode.name);
    }
    expect(tester.getSize(preview), const Size(120, 80));

    final tall = await photoOf(tester, width: 8, height: 12);
    await show(tester, tall, mode: LookCompareMode.slide, look: _monotone);
    expect(tester.getSize(preview), const Size(80, 120));
  });

  testWidgets('the ways of comparing are told apart for assistive '
      'technology and report the one tapped', (tester) async {
    final tapped = <LookCompareMode>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: grTheme(GrColors.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: LookCompareModeSwitch(
            selected: LookCompareMode.slide,
            onSelect: tapped.add,
          ),
        ),
      ),
    );
    for (final (mode, name) in [
      (LookCompareMode.sideBySide, 'Side by side'),
      (LookCompareMode.single, 'One at a time'),
      (LookCompareMode.slide, 'Slide to compare'),
    ]) {
      expect(find.byTooltip(name), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('look-compare:${mode.name}')));
    }
    expect(tapped, [
      LookCompareMode.sideBySide,
      LookCompareMode.single,
      LookCompareMode.slide,
    ]);
  });

  testWidgets('a photo is picked by its small picture', (tester) async {
    final picked = <int>[];
    final photos = [
      await photoOf(tester, orientation: 6),
      await photoOf(tester),
      await photoOf(tester),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: grTheme(GrColors.light),
        home: Center(
          child: PreviewPhotoSwitch(
            photos: photos,
            labels: const ['Own', 'Sample', 'Other'],
            selected: 0,
            onSelect: picked.add,
          ),
        ),
      ),
    );
    for (var i = 0; i < photos.length; i++) {
      await tester.tap(find.byKey(ValueKey('look-photo:$i')));
    }
    expect(picked, [0, 1, 2]);
    expect(find.byTooltip('Sample'), findsOneWidget);
  });
}
