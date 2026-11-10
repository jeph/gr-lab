import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/library/viewer.dart';
import 'package:grlab/src/widgets/group.dart';

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
  String shot,
) async {
  final app = (await tester.runAsync(
    () => createTestApp(
      config: FakeCameraConfig(bonded: true, photos: photos),
      saveCamera: true,
    ),
  ))!;
  await app.pumpApp(tester);
  await _openLibrary(tester);
  await tapWhenReady(tester, find.byKey(ValueKey(shot)));
  await pumpUntilFound(tester, _viewer);
  return app;
}

/// The pair `R0000001` loses [deleted]; the viewer shows the shot left,
/// which offers one Download in place of the pair's two and downloads only
/// [kept].
Future<void> _pairLoses(
  WidgetTester tester, {
  required String deleted,
  required String kept,
}) async {
  final app = await _openViewer(tester, [
    FakePhoto('100RICOH', 'R0000001.JPG', _taken(1)),
    FakePhoto('100RICOH', 'R0000001.DNG', _taken(1)),
  ], 'sd1|100RICOH/R0000001');
  Finder action(String key) => _inViewer(find.byKey(ValueKey(key)));
  await pumpUntilFound(tester, action('viewer-download:raw'));
  expect(action('viewer-download:jpeg'), findsOneWidget);

  _delete(app, deleted);
  final download = action('viewer-download');
  await pumpUntilFound(tester, download);
  expect(_showing(kept), findsOneWidget);
  expect(action('viewer-download:jpeg'), findsNothing);
  expect(action('viewer-download:raw'), findsNothing);

  await tapWhenReady(tester, download);
  await pumpUntil(
    tester,
    () => app.media.shots.isNotEmpty,
    reason: 'the shot left saved',
  );
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
      'in and back out; a tap or Back brings the bars and details back', (
    tester,
  ) async {
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
    expect(tester.getSize(pages).height, lessThan(screen.height));

    await tester.tap(pages);
    await tester.pump();
    expect(bar, findsNothing);
    expect(download.hitTestable(), findsNothing);
    expect(tester.getSize(pages), screen);
    expect(modes, ['SystemUiMode.immersiveSticky']);

    await pinch(10);
    expect(zoom(), greaterThan(2));
    expect(tester.widget<PageView>(pages).controller!.page, 0);
    await pinch(-10);
    expect(zoom(), 1);

    await tester.tap(pages);
    await tester.pump();
    expect(bar, findsOneWidget);
    expect(download.hitTestable(), findsOneWidget);
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    await tester.tap(pages);
    await tester.pump();
    expect(bar, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_showing('R0000002.JPG'), findsOneWidget);
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    await app.dispose();
  });
}
