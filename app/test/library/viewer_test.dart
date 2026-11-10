import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/library/image_orientation.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/library/viewer.dart';
import 'package:grlab/src/looks/looks_store.dart';
import 'package:grlab/src/widgets/group.dart';
import 'package:image/image.dart' as img;

import '../support/test_app.dart';

final Finder _viewer = find.byType(ShotViewer);

Finder _inViewer(Finder finder) =>
    find.descendant(of: _viewer, matching: finder);

/// The viewer shows the shot whose primary file is [name]: its title.
Finder _showing(String name) => _inViewer(
  find.descendant(of: find.byType(AppBar), matching: find.text(name)),
);

/// How many shots the viewer's pages swipe between.
int _pageCount(WidgetTester tester) => tester
    .widget<PageView>(_inViewer(find.byType(PageView)))
    .childrenDelegate
    .estimatedChildCount!;

DateTime _taken(int n) => DateTime(2026, 11, 5, 8, n);

/// Waits for the Library, tapping Library on the camera card when the app
/// stops there instead of opening it by itself.
Future<void> _openLibrary(WidgetTester tester) async {
  final library = find.byType(LibraryScreen);
  final button = find.byKey(const Key('camera-card-library'));
  await pumpUntil(
    tester,
    () =>
        library.evaluate().isNotEmpty ||
        button.hitTestable().evaluate().isNotEmpty,
    reason: 'the Library or its button on the camera card',
  );
  if (library.evaluate().isEmpty) await tapWhenReady(tester, button);
  await pumpUntilFound(tester, library);
}

/// Deletes [file] on the camera, which tells the app with a `storage`
/// `delete` change.
void _delete(TestApp app, String file) {
  final photo = app.camera.photos.singleWhere((p) => p.file == file);
  expect(app.camera.removePhoto(photo.path), isTrue);
}

/// Opens the Library on a camera holding [photos] and the viewer on the
/// shot keyed [shot].
Future<TestApp> _openViewer(
  WidgetTester tester,
  List<FakePhoto> photos,
  String shot, {
  FakeMediaSource? media,
}) async {
  final app = (await tester.runAsync(
    () => createTestApp(
      config: FakeCameraConfig(bonded: true, photos: photos),
      saveCamera: true,
      media: media,
    ),
  ))!;
  await app.pumpApp(tester);
  await _openLibrary(tester);
  await tapWhenReady(tester, find.byKey(ValueKey(shot)));
  await pumpUntilFound(tester, _viewer);
  return app;
}

/// The pair `R0000001` loses [deleted]; the viewer shows the shot left,
/// whose Download no longer asks which files and downloads only [kept].
Future<void> _pairLoses(
  WidgetTester tester, {
  required String deleted,
  required String kept,
}) async {
  final app = await _openViewer(tester, [
    FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
    FakePhoto('100RICOH', 'R0000001.DNG', _taken(1)),
  ], 'sd1|100RICOH/R0000001');
  final download = _inViewer(find.byKey(const ValueKey('viewer-download')));
  final pairFormat = _inViewer(find.text('RAW+JPEG'));
  await pumpUntilFound(tester, pairFormat);
  expect(download, findsOneWidget);

  _delete(app, deleted);
  await pumpUntil(
    tester,
    () => pairFormat.evaluate().isEmpty,
    reason: 'the viewer shows a single file',
  );
  expect(_showing(kept), findsOneWidget);

  await tapWhenReady(tester, download);
  await pumpUntil(
    tester,
    () => app.media.shots.isNotEmpty,
    reason: 'the shot left saved',
  );
  expect(find.byKey(const Key('viewer-download-sheet')), findsNothing);
  expect(app.media.shots.single.names, [kept]);

  await app.dispose();
}

void main() {
  testWidgets('a shot deleted on the camera leaves the viewer, which shows '
      'its neighbour and closes once none is left', (tester) async {
    // Newest first: R0000003 (A), R0000002 (B), R0000001 (C).
    final app = await _openViewer(tester, [
      for (var n = 1; n <= 3; n++)
        FakePhoto('100RICOH', 'R000000$n.JPG', _taken(n)),
    ], 'sd1|100RICOH/R0000002');
    await pumpUntilFound(tester, _showing('R0000002.JPG'));
    expect(_pageCount(tester), 3);

    _delete(app, 'R0000002.JPG');
    await pumpUntilFound(tester, _showing('R0000001.JPG'));
    expect(_pageCount(tester), 2);

    // A is one page back; nothing follows C.
    await tester.fling(
      _inViewer(find.byType(PageView)),
      const Offset(600, 0),
      1000,
    );
    await pumpUntilFound(tester, _showing('R0000003.JPG'));
    await tester.fling(
      _inViewer(find.byType(PageView)),
      const Offset(-600, 0),
      1000,
    );
    await pumpUntilFound(tester, _showing('R0000001.JPG'));
    await tester.fling(
      _inViewer(find.byType(PageView)),
      const Offset(-600, 0),
      1000,
    );
    await pumpRounds(tester, 30);
    expect(_showing('R0000001.JPG'), findsOneWidget);

    _delete(app, 'R0000001.JPG');
    _delete(app, 'R0000003.JPG');
    await pumpUntil(
      tester,
      () => _viewer.evaluate().isEmpty,
      reason: 'viewer closed',
    );
    expect(find.byType(LibraryScreen), findsOneWidget);

    await app.dispose();
  });

  testWidgets('a shot deleted during a swipe away from it ends the swipe on '
      'its neighbour', (tester) async {
    // Newest first: R0000004 (A), R0000003 (B), R0000002 (C), R0000001 (D).
    final app = await _openViewer(tester, [
      for (var n = 1; n <= 4; n++)
        FakePhoto('100RICOH', 'R000000$n.JPG', _taken(n)),
    ], 'sd1|100RICOH/R0000003');
    await pumpUntilFound(tester, _showing('R0000003.JPG'));
    final pages = _inViewer(find.byType(PageView));
    double page() => tester.widget<PageView>(pages).controller!.page!;
    final width = tester.getSize(pages).width;
    // The route has finished sliding in.
    await pumpUntilFound(tester, pages.hitTestable());
    await pumpRounds(tester, 30);

    // A third of the way from B towards C, still held.
    final swipe = await tester.startGesture(tester.getCenter(pages));
    for (var i = 0; i < 10; i++) {
      await swipe.moveBy(Offset(-width / 30, 0));
      await tester.pump();
    }
    expect(page(), greaterThan(1.2));

    _delete(app, 'R0000003.JPG');
    await pumpUntilFound(tester, _showing('R0000002.JPG'));
    expect(page(), 1);

    // The rest of the swipe, measured against the old pages, would carry C
    // past halfway towards D.
    for (var i = 0; i < 10; i++) {
      await swipe.moveBy(Offset(-width / 30, 0));
      await tester.pump();
    }
    await swipe.up();
    await pumpRounds(tester, 50);
    expect(page(), 1);
    expect(_showing('R0000002.JPG'), findsOneWidget);
    expect(_pageCount(tester), 3);

    await app.dispose();
  });

  testWidgets(
    'a pair whose JPEG is deleted shows and downloads its RAW',
    (tester) =>
        _pairLoses(tester, deleted: 'R0000001.JPG', kept: 'R0000001.DNG'),
  );

  testWidgets(
    'a pair whose RAW is deleted shows and downloads its JPEG',
    (tester) =>
        _pairLoses(tester, deleted: 'R0000001.DNG', kept: 'R0000001.JPG'),
  );

  testWidgets("a pair's Download asks for its JPEG, its RAW or both and "
      'downloads only what was chosen', (tester) async {
    final app = await _openViewer(tester, [
      FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
      FakePhoto('100RICOH', 'R0000001.DNG', _taken(1)),
    ], 'sd1|100RICOH/R0000001');
    final download = _inViewer(find.byKey(const ValueKey('viewer-download')));
    Finder choice(String name) =>
        find.byKey(Key('viewer-download-choice:$name'));

    await tapWhenReady(tester, download);
    await pumpUntilFound(tester, choice('both'));
    expect(choice('jpeg'), findsOneWidget);
    await tapWhenReady(tester, choice('raw'));
    await pumpUntil(
      tester,
      () => app.media.shots.isNotEmpty,
      reason: 'the RAW saved',
    );
    expect(app.media.shots.single.names, ['R0000001.DNG']);

    await tapWhenReady(tester, download);
    await tapWhenReady(tester, choice('both'));
    await pumpUntil(
      tester,
      () => app.media.shots.length == 2,
      reason: 'both saved',
    );
    expect(app.media.shots.last.names, ['R0000001.JPG', 'R0000001.DNG']);

    await app.dispose();
  });

  testWidgets("a photo's look that is already saved is not saved again: a "
      'dialog says so, and Save look can be used again', (tester) async {
    final app = await _openViewer(tester, [
      FakePhoto(
        '100RICOH',
        'R0000001.JPG',
        _taken(1),
        imageControl: FakeLook.presets[0].data,
      ),
    ], 'sd1|100RICOH/R0000001');
    final looks = app.models.looks;
    final save = _inViewer(find.byKey(const Key('viewer-save-look')));
    final nameField = find.byKey(const Key('looks-name-field'));
    Future<void> dismiss(String said) async {
      await pumpUntilFound(tester, find.text(said));
      await tapWhenReady(tester, find.byKey(const Key('looks-conflict-ok')));
      await pumpUntil(tester, () => find.text(said).evaluate().isEmpty);
    }

    await tapWhenReady(tester, save);
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await pumpUntilFound(tester, find.text('Saved Positive Film'));
    final saved = looks.looks.single;
    expect(saved.source, 'R0000001.JPG');

    await tapWhenReady(tester, save);
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await pumpUntilFound(tester, find.text('This look already exists'));
    await dismiss('Positive Film is already saved with the same settings.');
    expect(looks.looks.single.id, saved.id);
    expect(tester.widget<OutlinedButton>(save).onPressed, isNotNull);

    await tapWhenReady(tester, save);
    await pumpUntilFound(tester, nameField);
    await tester.enterText(nameField, 'Shinjuku');
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await dismiss(
      "Another look, Positive Film, has the same settings. Two looks can't "
      'have the same settings.',
    );
    expect(looks.looks.single.id, saved.id);
    expect(tester.widget<OutlinedButton>(save).onPressed, isNotNull);

    await app.dispose();
  });

  testWidgets("a look saved from a photo keeps the photo's JPEG, made as "
      "small as a look's preview is worked out on and upright; a RAW file "
      "alone, or a JPEG too small to shrink, is kept as the camera's "
      'preview or as it is, with how to turn it upright', (tester) async {
    // 3000 by 2000 as stored, left half red; held upside down, so the
    // left is the right once upright.
    final large = img.Image(width: 3000, height: 2000);
    for (final pixel in large) {
      if (pixel.x < 1500) {
        pixel.setRgb(200, 40, 40);
      } else {
        pixel.setRgb(40, 40, 200);
      }
    }
    final largeJpeg = withExifOrientation(img.encodeJpg(large), 3);
    final rest = syntheticMedia();
    // Each photo has a look of its own: a look already saved is not saved
    // again.
    final app = await _openViewer(
      tester,
      [
        FakePhoto(
          '100RICOH',
          'R0000001.JPG',
          _taken(1),
          imageControl: FakeLook.presets[1].data,
        ),
        FakePhoto(
          '100RICOH',
          'R0000002.DNG',
          _taken(2),
          orientation: 6,
          imageControl: FakeLook.presets[2].data,
        ),
        FakePhoto(
          '100RICOH',
          'R0000003.JPG',
          _taken(3),
          orientation: 6,
          imageControl: FakeLook.presets[0].data,
        ),
        FakePhoto(
          '100RICOH',
          'R0000004.JPG',
          _taken(4),
          orientation: 3,
          imageControl: FakeLook.presets[4].data,
        ),
      ],
      'sd1|100RICOH/R0000004',
      media: (photo, size) async =>
          size == GrImageSize.full && photo.file == 'R0000004.JPG'
          ? largeJpeg
          : await rest(photo, size),
    );
    final looks = app.models.looks;
    final save = _inViewer(find.byKey(const Key('viewer-save-look')));
    Future<(SavedLook, Uint8List)> saveLook(String from) async {
      await pumpUntilFound(tester, _showing(from));
      final before = looks.looks.length;
      await tapWhenReady(tester, save);
      await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
      await pumpUntil(
        tester,
        () => looks.looks.length > before,
        reason: 'the look saved',
      );
      final saved = looks.looks.first;
      await pumpUntilFound(tester, find.text('Saved ${saved.name}'));
      expect(saved.source, from);
      return (saved, looks.photoOf(saved)!.readAsBytesSync());
    }

    Future<void> next() async {
      await tester.fling(
        _inViewer(find.byType(PageView)),
        const Offset(-300, 0),
        1000,
      );
    }

    final (shrunk, shrunkPhoto) = await saveLook('R0000004.JPG');
    final picture = img.decodeJpg(shrunkPhoto)!;
    expect((picture.width, picture.height), (1548, 1032));
    expect(readJpegLayout(shrunkPhoto)!.exifOrientation, isNull);
    expect(shrunk.photoOrientation, 1);
    expect(picture.getPixel(1200, 500).r, greaterThan(150), reason: 'red');
    expect(picture.getPixel(300, 500).b, greaterThan(150), reason: 'blue');
    expect(shrunkPhoto.length, lessThan(largeJpeg.length));

    // The fake camera's own full JPEG is 24 by 16: kept whole, with the
    // tag that turns it.
    await next();
    final (small, smallPhoto) = await saveLook('R0000003.JPG');
    expect(readJpegLayout(smallPhoto)!.exifOrientation, 6);
    expect(small.photoOrientation, 1);

    // The preview is in the sensor's layout; how the camera was held is
    // in the shot's info.
    await next();
    final (raw, rawPhoto) = await saveLook('R0000002.DNG');
    final preview = readJpegLayout(rawPhoto)!;
    expect((preview.width, preview.height), (24, 16));
    expect(preview.exifOrientation, isNull);
    expect(raw.photoOrientation, 6);

    await next();
    final (level, _) = await saveLook('R0000001.JPG');
    expect(level.photoOrientation, 1);

    await app.dispose();
  });

  testWidgets('the Image Control row is a skeleton of its own height while '
      'the camera is asked, and goes for a photo without one', (tester) async {
    // A phone, widened until the row's title fits one line in the test
    // font, whose letters are as wide as they are tall.
    tester.view
      ..physicalSize = const Size(1500, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Newest first: R0000003 (a summary of two lines), R0000002 (one
    // line), R0000001 (no Image Control).
    final app = await _openViewer(tester, [
      FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
      FakePhoto(
        '100RICOH',
        'R0000002.JPG',
        _taken(2),
        imageControl: FakeLook.presets[4].data,
      ),
      FakePhoto(
        '100RICOH',
        'R0000003.JPG',
        _taken(3),
        imageControl: FakeLook.presets[0].data,
      ),
    ], 'sd1|100RICOH/R0000003');
    final skeleton = _inViewer(
      find.byKey(const Key('viewer-image-control-loading')),
    );
    final save = _inViewer(find.byKey(const Key('viewer-save-look')));
    final details = _inViewer(find.byType(GroupBox));
    Future<void> next(String name) async {
      await tester.fling(
        _inViewer(find.byType(PageView)),
        const Offset(-300, 0),
        1000,
      );
      await pumpUntilFound(tester, _showing(name));
    }

    expect(skeleton, findsOneWidget);
    expect(save, findsNothing);
    final height = tester.getSize(details).height;
    await pumpUntilFound(tester, save);
    expect(skeleton, findsNothing);
    expect(find.textContaining('Grain'), findsOneWidget);
    expect(tester.getSize(details).height, height);
    // The route has finished sliding in.
    await pumpUntilFound(tester, save.hitTestable());
    await pumpRounds(tester, 30);

    await next('R0000002.JPG');
    expect(skeleton, findsOneWidget);
    expect(tester.getSize(details).height, height);
    await pumpUntilFound(tester, save);
    expect(_inViewer(find.text('Standard')), findsOneWidget);
    expect(tester.getSize(details).height, height);

    await next('R0000001.JPG');
    expect(skeleton, findsOneWidget);
    await pumpUntil(
      tester,
      () => skeleton.evaluate().isEmpty,
      reason: 'the skeleton gone',
    );
    expect(save, findsNothing);

    await app.dispose();
  });

  testWidgets('a tap gives a photo the whole screen, where a pinch zooms it '
      'in and back out; there a tap shows the way out, and it or Back brings '
      'the bars and details back', (tester) async {
    final modes = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final app = await _openViewer(tester, [
      for (var n = 1; n <= 2; n++)
        FakePhoto('100RICOH', 'R000000$n.JPG', _taken(n)),
    ], 'sd1|100RICOH/R0000002');
    final pages = _inViewer(find.byType(PageView));
    final bar = _inViewer(find.byType(AppBar));
    final download = _inViewer(find.byKey(const ValueKey('viewer-download')));
    double zoom() => tester
        .widget<InteractiveViewer>(
          _inViewer(find.byType(InteractiveViewer)).first,
        )
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    // Two fingers on a horizontal line, each moved by [step] ten times:
    // the direction the pages swipe in.
    Future<void> pinch(double step) async {
      final centre = tester.getCenter(pages);
      final spread = step > 0 ? 20.0 : 20 + 10 * step.abs();
      final left = await tester.startGesture(
        centre - Offset(spread, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        centre + Offset(spread, 0),
        pointer: 2,
      );
      for (var i = 0; i < 10; i++) {
        await left.moveBy(Offset(-step, 0));
        await right.moveBy(Offset(step, 0));
        await tester.pump();
      }
      await left.up();
      await right.up();
      await pumpRounds(tester, 30);
    }

    // The route has finished sliding in.
    await pumpUntilFound(tester, download.hitTestable());
    await pumpRounds(tester, 30);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final withBars = tester.getSize(pages).height;
    expect(withBars, lessThan(screen.height));
    final exit = _inViewer(find.byKey(const Key('viewer-exit-fullscreen')))
        .hitTestable();
    // Part of the way between its two sizes: the bars slide, they don't
    // jump.
    Future<void> expectSliding() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.getSize(pages).height,
        inExclusiveRange(withBars, screen.height),
      );
      await pumpRounds(tester, 30);
    }

    await tester.tap(pages);
    await expectSliding();
    expect(bar, findsNothing);
    expect(download.hitTestable(), findsNothing);
    expect(tester.getSize(pages), screen);
    expect(modes, ['SystemUiMode.immersiveSticky']);
    expect(exit, findsNothing);

    await pinch(10);
    expect(zoom(), greaterThan(2));
    expect(tester.widget<PageView>(pages).controller!.page, 0);
    await pinch(-10);
    expect(zoom(), 1);

    // A tap shows the way out and the next one puts it away; the photo
    // keeps the screen.
    await tester.tap(pages);
    await tester.pump();
    expect(exit, findsOneWidget);
    await tester.tap(pages);
    await tester.pump();
    expect(exit, findsNothing);
    expect(tester.getSize(pages), screen);
    expect(modes, ['SystemUiMode.immersiveSticky']);

    await tester.tap(pages);
    await tester.pump();
    await tester.tap(exit);
    await expectSliding();
    expect(bar, findsOneWidget);
    expect(download.hitTestable(), findsOneWidget);
    expect(tester.getSize(pages).height, withBars);
    expect(exit, findsNothing);
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    await tester.tap(pages);
    await pumpRounds(tester, 30);
    expect(bar, findsNothing);
    await tester.binding.handlePopRoute();
    await pumpRounds(tester, 30);
    expect(_showing('R0000002.JPG'), findsOneWidget);
    expect(download.hitTestable(), findsOneWidget);
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    await app.dispose();
  });

  testWidgets('full screen comes at once when the phone asks for less '
      'motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final app = await _openViewer(tester, [
      FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
    ], 'sd1|100RICOH/R0000001');
    final pages = _inViewer(find.byType(PageView));
    await pumpUntilFound(
      tester,
      _inViewer(find.byKey(const ValueKey('viewer-download'))).hitTestable(),
    );
    await pumpRounds(tester, 30);

    await tester.tap(pages);
    await tester.pump();
    expect(
      tester.getSize(pages),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );

    await app.dispose();
  });

  testWidgets('a pinch zooms a photo and a drag moves a zoomed one from '
      'their first movement, and one finger still swipes to the next photo', (
    tester,
  ) async {
    final app = await _openViewer(tester, [
      for (var n = 1; n <= 2; n++)
        FakePhoto('100RICOH', 'R000000$n.JPG', _taken(n)),
    ], 'sd1|100RICOH/R0000002');
    final pages = _inViewer(find.byType(PageView));
    final download = _inViewer(find.byKey(const ValueKey('viewer-download')));
    Matrix4 transform() => tester
        .widget<InteractiveViewer>(
          _inViewer(find.byType(InteractiveViewer)).first,
        )
        .transformationController!
        .value;
    await pumpUntilFound(tester, download.hitTestable());
    await pumpRounds(tester, 30);
    final centre = tester.getCenter(pages);

    // Each movement is shorter than a gesture has to be to win against a
    // tap or a swipe between pages.
    final left = await tester.startGesture(
      centre - const Offset(40, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      centre + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();
    await left.moveBy(const Offset(-4, 0));
    await right.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(transform().getMaxScaleOnAxis(), closeTo(1.1, .01));
    for (var i = 0; i < 10; i++) {
      await left.moveBy(const Offset(-8, 0));
      await right.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await left.up();
    await right.up();
    await pumpRounds(tester, 30);
    expect(transform().getMaxScaleOnAxis(), greaterThan(2));

    final before = transform().getTranslation().y;
    final finger = await tester.startGesture(centre);
    await finger.moveBy(const Offset(0, 6));
    await tester.pump();
    expect(transform().getTranslation().y - before, closeTo(6, .01));
    // Far enough not to be a tap.
    await finger.moveBy(const Offset(0, 30));
    await finger.up();
    await pumpRounds(tester, 30);
    expect(tester.widget<PageView>(pages).controller!.page, 0);
    expect(download.hitTestable(), findsOneWidget);

    // Back at the fitted photo, pages swipe again.
    final pinchLeft = await tester.startGesture(
      centre - const Offset(140, 0),
      pointer: 1,
    );
    final pinchRight = await tester.startGesture(
      centre + const Offset(140, 0),
      pointer: 2,
    );
    for (var i = 0; i < 10; i++) {
      await pinchLeft.moveBy(const Offset(12, 0));
      await pinchRight.moveBy(const Offset(-12, 0));
      await tester.pump();
    }
    await pinchLeft.up();
    await pinchRight.up();
    await pumpRounds(tester, 30);
    expect(transform().getMaxScaleOnAxis(), 1);
    await tester.fling(pages, const Offset(-600, 0), 1000);
    await pumpUntilFound(tester, _showing('R0000001.JPG'));

    await app.dispose();
  });
}
