import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/library/image_orientation.dart';
import 'package:grphoto/src/library/library_screen.dart';
import 'package:grphoto/src/library/viewer.dart';
import 'package:grphoto/src/looks/looks_store.dart';
import 'package:grphoto/src/map/photo_map.dart';
import 'package:grphoto/src/services.dart';
import 'package:grphoto/src/widgets/group.dart';
import 'package:image/image.dart' as img;

import '../support/duo_window.dart';
import '../support/test_app.dart';

/// The viewer, or the shot beside the Library on two pages at a fold,
/// which takes the whole window there, laid out as the viewer is.
final Finder _viewer = find.byWidgetPredicate(
  (w) => w is ShotViewer || w is ShotPane,
  description: 'the viewer or the shot beside the Library',
);

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
/// shot keyed [shot], with the shot's details when [info] is set: Info in
/// the viewer's header shows them. The camera has background geotagging on
/// when [backgroundGeotagging] is set, and the phone's location history
/// holds [history].
Future<TestApp> _openViewer(
  WidgetTester tester,
  List<FakePhoto> photos,
  String shot, {
  FakeMediaSource? media,
  bool info = false,
  bool backgroundGeotagging = false,
  List<LocationFix> history = const [],
}) async {
  final app = (await tester.runAsync(() async {
    final app = await createTestApp(
      config: FakeCameraConfig(bonded: true, photos: photos),
      saveCamera: true,
      media: media,
      backgroundGeotagging: backgroundGeotagging,
    );
    // Where the phone has been, as background geotagging recorded it.
    await app.models.geotag.history.add(history);
    return app;
  }))!;
  await app.pumpApp(tester);
  await _openLibrary(tester);
  await tapWhenReady(tester, find.byKey(ValueKey(shot)));
  await pumpUntilFound(tester, _viewer);
  if (info) {
    await tapWhenReady(tester, _inViewer(find.byKey(const Key('viewer-info'))));
  }
  return app;
}

/// Opens the Library of a camera holding `R0000001.JPG` to `R0000003.JPG`
/// on an iPhone Duo in [window], and the viewer on the last of them. Open
/// and held wide, the Library shows the shot beside its grid instead, and
/// Full screen there gives it the whole window.
Future<TestApp> _openViewerOnDuo(WidgetTester tester, DuoWindow window) async {
  final app = (await tester.runAsync(
    () => createTestApp(
      config: FakeCameraConfig(
        bonded: true,
        photos: [
          for (var n = 1; n <= 3; n++)
            FakePhoto('100RICOH', 'R000000$n.JPG', _taken(n)),
        ],
      ),
      saveCamera: true,
    ),
  ))!;
  await app.pumpApp(tester);
  await _openLibrary(tester);
  setDuoWindow(tester, app.windowPose, window);
  await tapWhenReady(
    tester,
    find.byKey(const ValueKey('sd1|100RICOH/R0000003')),
  );
  final route = find.byType(ShotViewer);
  final fullScreen = find.byKey(const Key('pane-full-screen'));
  await pumpUntil(
    tester,
    () => route.evaluate().isNotEmpty || fullScreen.evaluate().isNotEmpty,
    reason: 'the shot in the viewer or beside the Library',
  );
  if (route.evaluate().isEmpty) await tapWhenReady(tester, fullScreen);
  // The route has finished sliding in, or the shot has grown to the whole
  // window.
  await pumpRounds(tester, 30);
  expect(tester.takeException(), isNull, reason: window.name);
  return app;
}

/// The fold of a foldable at [bounds] of the window, flat.
DisplayFeature _fold(Rect bounds) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);

/// The pair `R0000001` loses [deleted]; the viewer shows the shot left,
/// whose Download no longer asks which files and downloads only [kept].
Future<void> _pairLoses(
  WidgetTester tester, {
  required String deleted,
  required String kept,
}) async {
  final app = await _openViewer(
    tester,
    [
      FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
      FakePhoto('100RICOH', 'R0000001.DNG', _taken(1)),
    ],
    'sd1|100RICOH/R0000001',
    info: true,
  );
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

  testWidgets("after a pair's JPEG fails, Download still asks and choosing "
      'the RAW downloads the RAW only', (tester) async {
    final app = await _openViewer(tester, [
      FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
      FakePhoto('100RICOH', 'R0000001.DNG', _taken(1)),
    ], 'sd1|100RICOH/R0000001');
    final download = _inViewer(find.byKey(const ValueKey('viewer-download')));
    Finder choice(String name) =>
        find.byKey(Key('viewer-download-choice:$name'));
    app.media.failWith = const MediaSaveException(
      MediaSaveFailure.failed,
      'disk full',
    );

    await tapWhenReady(tester, download);
    await tapWhenReady(tester, choice('jpeg'));
    await pumpUntilFound(tester, _inViewer(find.byTooltip('Retry download')));

    app.media.failWith = null;
    await tapWhenReady(tester, download);
    await tapWhenReady(tester, choice('raw'));
    await pumpUntil(
      tester,
      () => app.media.shots.isNotEmpty,
      reason: 'the RAW saved',
    );
    await pumpUntil(
      tester,
      () => app.models.library.engine.jobs.isEmpty,
      reason: 'the job done',
    );
    expect(
      [for (final s in app.media.shots) s.names],
      [
        ['R0000001.DNG'],
      ],
    );

    await app.dispose();
  });

  testWidgets("a photo's look that is already saved is not saved again: a "
      'dialog says so, and Save look can be used again', (tester) async {
    final app = await _openViewer(
      tester,
      [
        FakePhoto(
          '100RICOH',
          'R0000001.JPG',
          _taken(1),
          imageControl: FakeLook.presets[0].data,
        ),
      ],
      'sd1|100RICOH/R0000001',
      info: true,
    );
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
      info: true,
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
    final app = await _openViewer(
      tester,
      [
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
      ],
      'sd1|100RICOH/R0000003',
      info: true,
    );
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

  testWidgets('the details show the whole date and time of a shot from '
      'another year, on a narrow phone at large text too', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await _openViewer(
      tester,
      [
        FakePhoto('100RICOH', 'R0000001.JPG', DateTime(2020, 10, 10, 1, 1)),
        FakePhoto('100RICOH', 'R0000001.DNG', DateTime(2020, 10, 10, 1, 1)),
      ],
      'sd1|100RICOH/R0000001',
      info: true,
    );
    // The card, inside the margin around it.
    final details = _inViewer(
      find.descendant(
        of: find.byType(GroupBox),
        matching: find.byType(Material),
      ),
    ).first;
    final taken = find.descendant(
      of: details,
      matching: find.textContaining('2020'),
    );
    await pumpUntilFound(tester, taken);

    /// Every letter of the date is laid out, inside the details.
    void expectWholeDate(String reason) {
      expect(tester.takeException(), isNull, reason: reason);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: taken, matching: find.byType(RichText)),
      );
      final text = paragraph.text.toPlainText();
      expect(text, allOf(contains('Oct 10, 2020'), contains('1:01')));
      final origin = paragraph.localToGlobal(Offset.zero);
      final card = tester.getRect(details);
      for (var i = 0; i < text.length; i++) {
        if (text[i].trim().isEmpty) continue;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
        );
        expect(boxes, isNotEmpty, reason: '$reason: "${text[i]}" at $i');
        final letter = boxes.single.toRect().shift(origin);
        expect(
          card.expandToInclude(letter),
          card,
          reason: '$reason: "${text[i]}" at $i',
        );
      }
    }

    expectWholeDate('a phone');

    tester.view
      ..physicalSize = const Size(320, 800)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await pumpRounds(tester, 3);
    expectWholeDate('a narrow phone at large text');

    await app.dispose();
  });

  testWidgets('a photo opens with the whole screen under the header; a tap '
      'puts the header away and the next one brings it back, and a pinch '
      'zooms the photo in and back out; Info shows the details below the '
      'photo, and Info again or a tap on the photo puts them away; Back '
      'closes the viewer', (tester) async {
    final modes = <Object?>[];
    // How the status bar's icons were last asked for.
    Object? statusIcons;
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
          final style = call.arguments as Map<Object?, Object?>;
          statusIcons = style['statusBarIconBrightness'];
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
    final back = _inViewer(find.byType(BackButton));
    final info = _inViewer(find.byKey(const Key('viewer-info')));
    final download = _inViewer(find.byKey(const ValueKey('viewer-download')));
    final details = _inViewer(find.byType(GroupBox));
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

    // The height of the pages part of the way through a change, and once
    // it is done.
    Future<(double, double)> slide() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final onTheWay = tester.getSize(pages).height;
      await pumpRounds(tester, 30);
      return (onTheWay, tester.getSize(pages).height);
    }

    // The route has finished sliding in.
    await pumpUntilFound(tester, download.hitTestable());
    await pumpRounds(tester, 30);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getSize(pages), screen);
    expect(back.hitTestable(), findsOneWidget);
    expect(info.hitTestable(), findsOneWidget);
    expect(details, findsNothing);
    expect(modes, isEmpty);
    expect(statusIcons, 'Brightness.light', reason: 'white over the photo');

    await tester.tap(pages);
    await pumpRounds(tester, 30);
    expect(bar, findsNothing);
    expect(tester.getSize(pages), screen);
    expect(modes, ['SystemUiMode.immersiveSticky']);

    // A pinch is not a tap: the header stays away.
    await pinch(10);
    expect(zoom(), greaterThan(2));
    expect(tester.widget<PageView>(pages).controller!.page, 0);
    await pinch(-10);
    expect(zoom(), 1);
    expect(bar, findsNothing);

    await tester.tap(pages);
    await pumpRounds(tester, 30);
    expect(back.hitTestable(), findsOneWidget);
    expect(download.hitTestable(), findsOneWidget);
    expect(tester.getSize(pages), screen);
    expect(modes, ['SystemUiMode.immersiveSticky', 'SystemUiMode.edgeToEdge']);

    // The details slide in below the photo, they don't jump; the photo
    // lies between the header and them.
    await tester.tap(info);
    final (opening, withDetails) = await slide();
    expect(withDetails, lessThan(screen.height));
    expect(opening, inExclusiveRange(withDetails, screen.height));
    expect(tester.getRect(pages).top, tester.getRect(bar).bottom);
    expect(tester.getRect(details).top, greaterThan(tester.getRect(pages).top));
    expect(tester.getRect(details).bottom, lessThanOrEqualTo(screen.height));
    expect(download.hitTestable(), findsOneWidget);

    // A tap on the photo puts them away and leaves the header.
    await tester.tap(pages);
    final (closing, _) = await slide();
    expect(closing, inExclusiveRange(withDetails, screen.height));
    expect(details, findsNothing);
    expect(tester.getSize(pages), screen);
    expect(back.hitTestable(), findsOneWidget);

    await tester.tap(info);
    await pumpRounds(tester, 30);
    expect(tester.getSize(pages).height, withDetails);
    await tester.tap(info);
    await pumpRounds(tester, 30);
    expect(details, findsNothing);
    expect(tester.getSize(pages), screen);
    expect(modes, hasLength(2));

    // Back closes the viewer, with the details and without the header
    // too, and brings the system's bars back.
    await tester.tap(pages);
    await pumpRounds(tester, 30);
    expect(bar, findsNothing);
    expect(modes.last, 'SystemUiMode.immersiveSticky');
    await tester.binding.handlePopRoute();
    await pumpUntil(
      tester,
      () => _viewer.evaluate().isEmpty,
      reason: 'viewer closed',
    );
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(modes.last, 'SystemUiMode.edgeToEdge');
    await tester.pump();
    expect(statusIcons, 'Brightness.dark', reason: 'as the light theme has');

    await tapWhenReady(
      tester,
      find.byKey(const ValueKey('sd1|100RICOH/R0000002')),
    );
    await tapWhenReady(tester, info);
    await pumpUntilFound(tester, details);
    await tester.binding.handlePopRoute();
    await pumpUntil(
      tester,
      () => _viewer.evaluate().isEmpty,
      reason: 'viewer closed from the details',
    );

    await app.dispose();
  });

  testWidgets('a swipe to a movie brings the header back: its page takes '
      'taps for playback', (tester) async {
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
    // Newest first: the photo, then the movie.
    final app = await _openViewer(tester, [
      FakePhoto(
        '100RICOH',
        'R0000001.MOV',
        _taken(1),
        videoLength: const Duration(seconds: 5),
      ),
      FakePhoto('100RICOH', 'R0000002.JPG', _taken(2)),
    ], 'sd1|100RICOH/R0000002');
    final pages = _inViewer(find.byType(PageView));
    final bar = _inViewer(find.byType(AppBar));
    final back = _inViewer(find.byType(BackButton));
    await pumpUntilFound(tester, back.hitTestable());
    await pumpRounds(tester, 30);

    await tester.tap(pages);
    await pumpRounds(tester, 30);
    expect(bar, findsNothing);

    await tester.fling(pages, const Offset(-600, 0), 1000);
    await pumpUntilFound(tester, _showing('R0000001.MOV'));
    await pumpRounds(tester, 30);
    expect(back.hitTestable(), findsOneWidget);
    expect(modes, ['SystemUiMode.immersiveSticky', 'SystemUiMode.edgeToEdge']);
    // The movie has the whole screen too.
    expect(
      tester.getSize(pages),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );

    await app.dispose();
  });

  testWidgets('the header and the details come and go at once when the '
      'phone asks for less motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final app = await _openViewer(tester, [
      FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
    ], 'sd1|100RICOH/R0000001');
    final pages = _inViewer(find.byType(PageView));
    final bar = _inViewer(find.byType(AppBar));
    final details = _inViewer(find.byType(GroupBox));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    await pumpUntilFound(
      tester,
      _inViewer(find.byKey(const ValueKey('viewer-download'))).hitTestable(),
    );
    await pumpRounds(tester, 30);

    await tester.tap(pages);
    await tester.pump();
    expect(bar, findsNothing);
    await tester.tap(pages);
    await tester.pump();
    expect(bar, findsOneWidget);

    // On the way in, the details would reach below the screen.
    await tester.tap(_inViewer(find.byKey(const Key('viewer-info'))));
    await tester.pump();
    expect(tester.getRect(details).bottom, lessThanOrEqualTo(screen.height));
    expect(tester.getRect(pages).bottom, lessThan(screen.height));
    await tester.tap(pages);
    await tester.pump();
    expect(details, findsNothing);
    expect(tester.getSize(pages), screen);

    await app.dispose();
  });

  testWidgets('the mark of a photo still loading keeps below the header '
      'while the header lies over its corner', (tester) async {
    final rest = syntheticMedia();
    // The full JPEG stays on its way until the test lets it through. The
    // photo's size is given, so the camera's `/info` doesn't wait for it.
    final full = Completer<void>();
    final app = await _openViewer(
      tester,
      [FakePhoto('100RICOH', 'R0000001.JPG', _taken(1), size: 4000)],
      'sd1|100RICOH/R0000001',
      media: (photo, size) async {
        if (size == GrImageSize.full) await full.future;
        return await rest(photo, size);
      },
    );
    final pages = _inViewer(find.byType(PageView));
    final bar = _inViewer(find.byType(AppBar));
    final sharpening = _inViewer(find.byKey(const Key('viewer-sharpening')));
    // The photo, 24 by 16, as it lies fitted to its page.
    Rect photo() {
      final page = tester.getRect(pages);
      return Alignment.center.inscribe(
        applyBoxFit(BoxFit.contain, const Size(24, 16), page.size).destination,
        page,
      );
    }

    double markTop() => tester.getRect(sharpening).top;
    await pumpUntilFound(tester, sharpening);
    // The route has finished sliding in.
    await pumpUntilFound(tester, bar.hitTestable());
    await pumpRounds(tester, 30);

    // The test's screen is wider than tall: the photo reaches under the
    // header.
    final header = tester.getRect(bar);
    expect(photo().top, lessThan(header.bottom));
    expect(markTop(), closeTo(header.bottom + 12, .01));

    await tester.tap(pages);
    await pumpRounds(tester, 30);
    expect(bar, findsNothing);
    expect(markTop(), closeTo(photo().top + 12, .01));

    await tester.tap(pages);
    await pumpRounds(tester, 30);
    expect(markTop(), closeTo(header.bottom + 12, .01));

    // With the details, the page begins below the header.
    await tester.tap(_inViewer(find.byKey(const Key('viewer-info'))));
    await pumpRounds(tester, 30);
    expect(tester.getRect(pages).top, header.bottom);
    expect(markTop(), closeTo(photo().top + 12, .01));

    full.complete();
    await pumpUntil(
      tester,
      () => sharpening.evaluate().isEmpty,
      reason: 'the mark gone once the full photo shows',
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

  group('the map below the details', () {
    final map = _inViewer(find.byKey(const Key('viewer-map')));
    final scroll = _inViewer(find.byKey(const Key('viewer-scroll')));
    const lisbon = FakePhotoLocation(38.7075, -9.1364, altitude: 12);

    // The place and zoom of the map shown.
    (GrPhotoLocation, double) shown(WidgetTester tester) {
      final photoMap = tester.widget<PhotoMap>(
        find.descendant(of: map, matching: find.byType(PhotoMap)),
      );
      return (photoMap.place, photoMap.zoom);
    }

    double scrollable(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position
        .maxScrollExtent;

    testWidgets('a photo the camera saved a location with has a map of it '
        'below its details: only the top of the map shows, the photo keeps '
        'the room above, and scrolling brings the rest up; Info again puts '
        'the map away with the details', (tester) async {
      final app = await _openViewer(
        tester,
        [FakePhoto('100RICOH', 'R0000001.JPG', _taken(1), location: lisbon)],
        'sd1|100RICOH/R0000001',
        info: true,
      );
      await pumpUntilFound(tester, map);
      await pumpRounds(tester, 30);

      expect(shown(tester), (const GrPhotoLocation(38.7075, -9.1364), 14.0));
      final screen = tester.getRect(_viewer);
      final card = tester.getRect(map);
      final details = tester.getRect(_inViewer(find.byType(GroupBox)).first);
      expect(details.bottom, lessThanOrEqualTo(card.top));
      // The top of the map is on screen, most of it is not.
      expect(card.top, lessThan(screen.bottom - 40));
      expect(card.top, greaterThan(screen.bottom - 120));
      expect(card.bottom, greaterThan(screen.bottom + 150));
      // The photo has the screen down to its details.
      final pages = tester.getRect(_inViewer(find.byType(PageView)));
      expect(pages.bottom, moreOrLessEquals(details.top, epsilon: 20));
      expect(pages.height, greaterThan(screen.height * 0.4));

      await tester.drag(scroll, const Offset(0, -400));
      await pumpRounds(tester, 30);
      final raised = tester.getRect(map);
      expect(raised.bottom, lessThanOrEqualTo(screen.bottom));
      expect(raised.height, card.height);

      await tester.tap(_inViewer(find.byKey(const Key('viewer-info'))));
      await pumpRounds(tester, 40);
      expect(map, findsNothing);
      expect(scrollable(tester), 0);
      await app.dispose();
    });

    testWidgets('a photo with no location has no map, and nothing scrolls; '
        'the half of a pair that has one gives the pair its map', (
      tester,
    ) async {
      final app = await _openViewer(
        tester,
        [
          FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
          FakePhoto('100RICOH', 'R0000002.JPG', _taken(2)),
          FakePhoto('100RICOH', 'R0000002.DNG', _taken(2), location: lisbon),
        ],
        'sd1|100RICOH/R0000001',
        info: true,
      );
      await pumpRounds(tester, 40);
      expect(map, findsNothing);
      expect(scrollable(tester), 0);
      final pages = _inViewer(find.byType(PageView));
      final before = tester.getRect(pages);
      await tester.drag(scroll, const Offset(0, -300));
      await pumpRounds(tester, 20);
      expect(tester.getRect(pages), before);

      // Newest first: the pair is the page before.
      await tester.fling(pages, const Offset(300, 0), 1000);
      await pumpUntilFound(tester, _showing('R0000002.JPG'));
      await pumpUntilFound(tester, map);
      expect(shown(tester).$1, const GrPhotoLocation(38.7075, -9.1364));
      await app.dispose();
    });

    // The history keeps 90 days, so these photos were taken yesterday.
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 8, 1);
    // The phone was here two minutes before them.
    final recorded = [
      LocationFix(
        latitude: 41.1407,
        longitude: -8.613,
        accuracy: 30,
        time: yesterday.subtract(const Duration(minutes: 2)).toUtc(),
      ),
    ];

    testWidgets('with background geotagging on, a photo with no location '
        'shows the place the phone was at when it was taken, from further '
        'out; a location the camera saved comes first, and a movie has no '
        'map', (tester) async {
      final app = await _openViewer(
        tester,
        [
          FakePhoto('100RICOH', 'R0000001.JPG', yesterday),
          FakePhoto(
            '100RICOH',
            'R0000002.JPG',
            yesterday.add(const Duration(minutes: 1)),
            location: lisbon,
          ),
          FakePhoto(
            '100RICOH',
            'R0000003.MOV',
            yesterday.add(const Duration(minutes: 2)),
            videoLength: const Duration(seconds: 4),
          ),
        ],
        'sd1|100RICOH/R0000001',
        info: true,
        backgroundGeotagging: true,
        history: recorded,
      );
      await pumpUntilFound(tester, map);
      expect(shown(tester), (const GrPhotoLocation(41.1407, -8.613), 12.0));

      // Newest first: the pages before are the later shots.
      final pages = _inViewer(find.byType(PageView));
      await tester.fling(pages, const Offset(300, 0), 1000);
      await pumpUntilFound(tester, _showing('R0000002.JPG'));
      await pumpUntil(
        tester,
        () => map.evaluate().isNotEmpty && shown(tester).$2 == 14,
        reason: "the map of the camera's own location",
      );
      expect(shown(tester).$1, const GrPhotoLocation(38.7075, -9.1364));
      await pumpRounds(tester, 30);

      await tester.fling(pages, const Offset(300, 0), 1000);
      await pumpUntilFound(tester, _showing('R0000003.MOV'));
      await pumpRounds(tester, 40);
      expect(map, findsNothing);
      await app.dispose();
    });

    testWidgets('with background geotagging off, the location history gives '
        'a photo no map', (tester) async {
      final app = await _openViewer(
        tester,
        [FakePhoto('100RICOH', 'R0000001.JPG', yesterday)],
        'sd1|100RICOH/R0000001',
        info: true,
        history: recorded,
      );
      await pumpRounds(tester, 40);
      expect(map, findsNothing);
      await app.dispose();
    });
  });

  group('on an iPhone Duo', () {
    final pages = _inViewer(find.byType(PageView));
    final header = _inViewer(find.byType(AppBar));
    final details = _inViewer(find.byType(GroupBox));
    Finder button(String key) => find.byKey(ValueKey(key));

    // Back, or Exit full screen where it is the way back ([leave]), Info
    // and Download stand in [strip], the window's bar under the status,
    // one under the other, and the header has none of them.
    void expectButtonsInBar(
      WidgetTester tester,
      Rect strip, {
      String leave = 'viewer-back',
    }) {
      final buttons = [leave, 'viewer-info', 'viewer-download'];
      for (final key in buttons) {
        expect(button(key).hitTestable(), findsOne, reason: key);
        final rect = tester.getRect(button(key));
        expect(strip.expandToInclude(rect), strip, reason: key);
        expect(
          find.descendant(of: header, matching: button(key)),
          findsNothing,
          reason: key,
        );
      }
      expect(
        tester.getRect(button(buttons[0])).bottom,
        lessThanOrEqualTo(tester.getRect(button(buttons[1])).top),
      );
      expect(
        tester.getRect(button(buttons[1])).bottom,
        lessThanOrEqualTo(tester.getRect(button(buttons[2])).top),
      );
      expect(_inViewer(find.byType(BackButton)), findsNothing);
    }

    testWidgets('closed, the viewer opens with the details below the '
        'photo, beside the bar down its side, where Back, Info and '
        'Download stand; Info puts the details away and brings them '
        'back', (tester) async {
      final app = await _openViewerOnDuo(tester, DuoWindow.closed);
      // The bar's strip, under the status at its top.
      const strip = Rect.fromLTRB(382, 174, 466, 678);
      expectButtonsInBar(tester, strip);
      final name = tester.getRect(_showing('R0000003.JPG'));
      // The window has no inset at its top, where its corners are rounded.
      expect(name.top, greaterThanOrEqualTo(14));
      expect(name.right, lessThanOrEqualTo(strip.left));
      expect(tester.getRect(header).right, lessThanOrEqualTo(strip.left));

      Rect photo() => tester.getRect(pages);
      expect(photo().left, 0);
      expect(photo().right, closeTo(strip.left, .5));
      expect(photo().top, closeTo(tester.getRect(header).bottom, .5));
      final withDetails = photo().height;
      // Room for a photo of the sensor's shape, as wide as the window.
      expect(withDetails, greaterThanOrEqualTo(strip.left * 2 / 3));
      expect(tester.getRect(details).top, greaterThanOrEqualTo(photo().bottom));
      expect(tester.getRect(details).right, lessThanOrEqualTo(strip.left));
      expect(tester.getRect(details).bottom, lessThanOrEqualTo(678));

      await tester.tap(button('viewer-info'));
      await pumpRounds(tester, 30);
      expect(tester.takeException(), isNull);
      expect(details, findsNothing);
      expect(photo(), const Rect.fromLTRB(0, 0, 382, 678));
      expectButtonsInBar(tester, strip);

      await tester.tap(button('viewer-info'));
      await pumpRounds(tester, 30);
      expect(details, findsOneWidget);
      expect(photo().height, withDetails);

      await app.dispose();
    });

    for (final window in [DuoWindow.open, DuoWindow.book]) {
      testWidgets('held wide (${window.name}), Full screen gives the shot '
          'beside the Library the photo across the window beside the bar, '
          'with Exit full screen, Info and Download there; Info shows the '
          'details as the second page, with the photo on the first, and a '
          'tap on the photo puts them away', (tester) async {
        final app = await _openViewerOnDuo(tester, window);
        // The bar's strip, under the status at its top, and the pages
        // either side of the fold: one line when flat.
        const strip = Rect.fromLTRB(867, 124, 951, 669);
        final fold = window.pose.fold!;
        final firstPageEnd = window.pose.halfOpen ? fold.left : fold.center.dx;
        final secondPageStart = window.pose.halfOpen
            ? fold.right
            : fold.center.dx;
        expectButtonsInBar(tester, strip, leave: 'viewer-exit-full-screen');
        expect(details, findsNothing);
        expect(tester.getRect(pages), const Rect.fromLTRB(0, 0, 867, 669));

        await tester.tap(button('viewer-info'));
        await pumpRounds(tester, 30);
        expect(tester.takeException(), isNull);
        final photo = tester.getRect(pages);
        final headerBottom = tester.getRect(header).bottom;
        expect(photo.left, 0);
        expect(photo.right, closeTo(firstPageEnd, .5));
        expect(photo.top, closeTo(headerBottom, .5));
        expect(photo.bottom, 669);
        final beside = tester.getRect(details);
        expect(beside.left, greaterThanOrEqualTo(secondPageStart));
        expect(beside.right, lessThanOrEqualTo(strip.left));
        expect(beside.top, greaterThanOrEqualTo(headerBottom));
        expectButtonsInBar(tester, strip, leave: 'viewer-exit-full-screen');

        await tester.tap(pages);
        await pumpRounds(tester, 30);
        expect(details, findsNothing);
        expect(tester.getRect(pages), const Rect.fromLTRB(0, 0, 867, 669));

        await app.dispose();
      });
    }

    testWidgets('the viewer keeps its shot and the page that shows it as '
        'the phone opens, turns upright and closes; in a window without '
        'the bar its buttons are in its header, under the band at the '
        'top', (tester) async {
      final app = await _openViewerOnDuo(tester, DuoWindow.closed);
      await tester.fling(pages, const Offset(-300, 0), 1000);
      await pumpUntilFound(tester, _showing('R0000002.JPG'));
      await pumpRounds(tester, 30);
      final viewer = tester.state(_viewer);
      final shown = tester.state(pages);
      for (final window in [
        DuoWindow.open,
        DuoWindow.upright,
        DuoWindow.book,
        DuoWindow.tabletop,
        DuoWindow.closed,
      ]) {
        setDuoWindow(tester, app.windowPose, window);
        await pumpRounds(tester, 15);
        expect(tester.takeException(), isNull, reason: window.name);
        expect(tester.state(_viewer), same(viewer), reason: window.name);
        expect(tester.state(pages), same(shown), reason: window.name);
        expect(_showing('R0000002.JPG'), findsOneWidget, reason: window.name);
        if (window.pose.barSide != null) {
          final strip = window == DuoWindow.closed
              ? const Rect.fromLTRB(382, 174, 466, 678)
              : const Rect.fromLTRB(867, 124, 951, 669);
          expectButtonsInBar(tester, strip);
          continue;
        }
        final back = _inViewer(find.byType(BackButton));
        expect(back.hitTestable(), findsOne, reason: window.name);
        expect(
          tester.getRect(back).top,
          greaterThanOrEqualTo(window.insets.top),
          reason: window.name,
        );
        for (final key in ['viewer-info', 'viewer-download']) {
          expect(
            find.descendant(of: header, matching: button(key)).hitTestable(),
            findsOne,
            reason: '$key, ${window.name}',
          );
        }
      }

      await app.dispose();
    });
  });

  testWidgets('without a vertical bar the viewer is as on a phone, also on '
      'a phone on its side and on a foldable with its hinge upright: its '
      'buttons in the header, the photo across the window and the details '
      'below it', (tester) async {
    final app = await _openViewer(tester, [
      FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
    ], 'sd1|100RICOH/R0000001');
    addTearDown(tester.view.reset);
    final pages = _inViewer(find.byType(PageView));
    final header = _inViewer(find.byType(AppBar));
    final details = _inViewer(find.byType(GroupBox));
    final info = find.byKey(const Key('viewer-info'));
    Future<void> expectAsOnAPhone(Size window) async {
      await pumpRounds(tester, 30);
      expect(tester.takeException(), isNull, reason: '$window');
      for (final button in [
        find.byType(BackButton),
        info,
        find.byKey(const ValueKey('viewer-download')),
      ]) {
        expect(
          find.descendant(of: header, matching: button).hitTestable(),
          findsOne,
          reason: '$window',
        );
      }
      expect(details, findsNothing, reason: '$window');
      expect(tester.getSize(pages), window);
    }

    tester.view
      ..physicalSize = const Size(2868, 1320)
      ..devicePixelRatio = 3;
    await expectAsOnAPhone(const Size(956, 440));

    const window = Size(750, 830);
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1
      ..displayFeatures = [_fold(const Rect.fromLTWH(365, 0, 20, 830))];
    await expectAsOnAPhone(window);
    await tester.tap(info);
    await pumpRounds(tester, 30);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(pages).top, tester.getRect(header).bottom);
    expect(tester.getRect(pages).width, window.width);
    expect(
      tester.getRect(details).top,
      greaterThanOrEqualTo(tester.getRect(pages).bottom),
    );
    expect(tester.getRect(details).width, lessThanOrEqualTo(window.width));

    await app.dispose();
  });
}
