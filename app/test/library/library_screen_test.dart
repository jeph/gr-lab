import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/camera/camera_top_bar.dart';
import 'package:grphoto/src/library/library_screen.dart';
import 'package:grphoto/src/library/shot.dart' show Shot;
import 'package:grphoto/src/library/shot_cell.dart';
import 'package:grphoto/src/library/viewer.dart';
import 'package:grphoto/src/services.dart';
import 'package:grphoto/src/widgets/group.dart';
import 'package:grphoto/src/widgets/toast.dart';

import '../support/duo_window.dart';
import '../support/test_app.dart';

/// Pictures the grid has loaded, keyed `image:view:<file key>`
/// ([Shot.gridSize] of a photo).
final Finder _thumbs = find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('image:view:'),
);

Finder _cell(String key) => find.byKey(ValueKey(key));

Finder _downloadedBadge(String key) =>
    find.descendant(of: _cell(key), matching: find.byIcon(Icons.check_rounded));

Finder _inViewer(String key) => find.descendant(
  of: find.byType(ShotViewer),
  matching: find.byKey(ValueKey(key)),
);

/// Quarter turns and mirroring the image found by [image] is shown with.
(int, bool) _shownAs(WidgetTester tester, Finder image) {
  final turns = tester
      .widget<RotatedBox>(
        find.descendant(of: image, matching: find.byType(RotatedBox)),
      )
      .quarterTurns;
  final flip = tester.widget<Transform>(
    find.descendant(of: image, matching: find.byType(Transform)),
  );
  return (turns, flip.transform.storage[0] < 0);
}

String _detail(WidgetTester tester, String kind) =>
    tester.widget<Text>(find.byKey(ValueKey('selection-detail:$kind'))).data!;

/// [pumpUntil] with longer steps of fake time, for retry pauses of seconds.
Future<void> _pumpSecondsUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 30)) {
      fail('Timed out waiting for $reason');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
}

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

/// The key of the shot of [_nameOf] [n].
String _shotOf(int n) => 'sd1|100RICOH/R${n.toString().padLeft(7, '0')}';

/// The name of the [n]th file of [_libraryOf].
String _nameOf(int n) => 'R${n.toString().padLeft(7, '0')}.JPG';

/// The Library of a camera holding [count] JPEGs taken on one day, a
/// minute apart: `R0000001.JPG` first and `R<count>.JPG` last, which the
/// grid starts with. Every date is known, so the grid is one day's.
Future<TestApp> _libraryOf(WidgetTester tester, int count) async {
  final app = (await tester.runAsync(
    () => createTestApp(
      config: FakeCameraConfig(
        bonded: true,
        httpLatency: Duration.zero,
        photos: [
          for (var n = 1; n <= count; n++)
            FakePhoto('100RICOH', _nameOf(n), DateTime(2026, 11, 5, 12, n)),
        ],
      ),
      saveCamera: true,
    ),
  ))!;
  await app.pumpApp(tester);
  await _openLibrary(tester);
  final model = app.models.library.model;
  await pumpUntil(tester, () => model.shots != null, reason: 'listing');
  for (final s in model.shots!) {
    unawaited(model.ensureInfo(s.primary));
  }
  await pumpUntil(
    tester,
    () => model.shots!.every((s) => model.info(s.primary) != null),
    reason: 'every date',
  );
  await pumpUntilFound(tester, _cell(_shotOf(count)));
  return app;
}

/// Gives the app the window of an iPhone Duo in [window], and time to lay
/// its pages out for it.
Future<void> _toDuo(WidgetTester tester, TestApp app, DuoWindow window) async {
  setDuoWindow(tester, app.windowPose, window);
  await pumpRounds(tester, 15);
  expect(tester.takeException(), isNull, reason: window.name);
}

/// The fold of a foldable at [bounds] of the window, flat.
DisplayFeature _fold(Rect bounds) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);

/// The Library's page, which scrolls.
final Finder _page = find.descendant(
  of: find.byType(LibraryScreen),
  matching: find.byType(CustomScrollView),
);

/// What scrolls [_page], and how far.
ScrollableState _pageScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(of: _page, matching: find.byType(Scrollable)).first,
    );

/// The text of the Library's title.
final Finder _title = find
    .descendant(of: find.byType(PageTitle), matching: find.byType(Text))
    .first;

/// The bar for the shots chosen with a long press.
final Finder _selectionBar = find.ancestor(
  of: find.byKey(const ValueKey('selection-download:jpeg')),
  matching: find.byType(ToastFloor),
);

/// The outline of the cell whose shot shows beside the grid.
final Finder _shownMark = find.byKey(const Key('shot-cell-shown'));

/// Where every cell the grid has built is.
List<Rect> _cellRects(WidgetTester tester) {
  final cells = find.byType(ShotCell);
  return [
    for (var i = 0; i < cells.evaluate().length; i++)
      tester.getRect(cells.at(i)),
  ];
}

/// How many shots the grid's first line has: the [newest] of
/// [_libraryOf] and those before it.
int _firstLineCount(WidgetTester tester, int newest) {
  final top = tester.getTopLeft(_cell(_shotOf(newest))).dy;
  var count = 1;
  while (count < newest) {
    final next = _cell(_shotOf(newest - count));
    if (next.evaluate().isEmpty || tester.getTopLeft(next).dy != top) break;
    count++;
  }
  return count;
}

/// The cell of the grid whose centre is nearest to [point].
Finder _cellNearest(WidgetTester tester, Offset point) {
  final cells = find.byType(ShotCell);
  double distance(int i) => (tester.getCenter(cells.at(i)) - point).distance;
  var nearest = 0;
  for (var i = 1; i < cells.evaluate().length; i++) {
    if (distance(i) < distance(nearest)) nearest = i;
  }
  return find.byKey(tester.widget(cells.at(nearest)).key!);
}

void main() {
  testWidgets('grid shows thumbnails and tags; JPEG and RAW download '
      'separately, and downloaded shots download again', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);

    await pumpUntilFound(tester, _thumbs);
    // The default card ends with a JPEG (R0000270), a DNG (R0000269) and a
    // RAW+JPEG pair (R0000268), newest first.
    const jpeg = 'sd1|101RICOH/R0000270';
    const pair = 'sd1|101RICOH/R0000268';
    await pumpUntilFound(
      tester,
      find.descendant(of: _cell(jpeg), matching: _thumbs),
    );
    expect(
      find.descendant(of: _cell(jpeg), matching: find.text('JPEG')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _cell('sd1|101RICOH/R0000269'),
        matching: find.text('RAW'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _cell(pair), matching: find.text('RAW+JPEG')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chip:notDownloaded')), findsOneWidget);
    expect(_downloadedBadge(jpeg), findsNothing);

    await tester.longPress(_cell(jpeg));
    await tester.pump();
    await tester.tap(_cell(pair));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    // The pair counts for both actions; there is no movie to offer.
    await pumpUntil(
      tester,
      () =>
          _detail(tester, 'jpeg').contains(' · ') &&
          _detail(tester, 'raw').contains(' · '),
      reason: 'selection sizes',
    );
    expect(_detail(tester, 'jpeg'), startsWith('2 files · '));
    expect(_detail(tester, 'raw'), startsWith('1 file · '));
    expect(
      find.byKey(const ValueKey('selection-download:movie')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('selection-download:raw')));
    await tester.pump();
    expect(find.text('2 selected'), findsNothing);
    await pumpUntil(
      tester,
      () => app.media.shots.isNotEmpty,
      reason: 'RAW saved',
    );
    await pumpUntilFound(tester, _downloadedBadge(pair));
    expect(app.media.shots.single.names, ['R0000268.DNG']);
    expect(_downloadedBadge(jpeg), findsNothing);
    expect(_downloadedBadge('sd1|101RICOH/R0000269'), findsNothing);

    // A downloaded shot stays selectable, and its RAW is offered again: it
    // may have been deleted from the phone.
    await tester.longPress(_cell(pair));
    await tester.pump();
    await tester.tap(_cell(jpeg));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(_detail(tester, 'raw'), startsWith('1 file · '));
    await tester.tap(find.byKey(const ValueKey('selection-download:jpeg')));
    await tester.pump();
    await pumpUntil(
      tester,
      () => app.media.shots.length == 3,
      reason: 'JPEGs saved',
    );
    await tester.longPress(_cell(pair));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('selection-download:raw')));
    await tester.pump();
    await pumpUntil(
      tester,
      () => app.media.shots.length == 4,
      reason: 'RAW saved again',
    );
    expect(
      [for (final s in app.media.shots) s.names],
      unorderedEquals([
        ['R0000268.DNG'],
        ['R0000270.JPG'],
        ['R0000268.JPG'],
        ['R0000268.DNG'],
      ]),
    );
    await pumpUntilFound(tester, _downloadedBadge(jpeg));

    // The viewer's Download asks which half of the pair, again. Info
    // shows the pair's details.
    await tester.tap(_cell(pair));
    await pumpUntilFound(tester, find.text('R0000268.JPG'));
    await tapWhenReady(tester, _inViewer('viewer-info'));
    expect(
      find.descendant(
        of: find.byType(ShotViewer),
        matching: find.text('RAW+JPEG'),
      ),
      findsOneWidget,
    );
    expect(find.text('R0000268.JPG + R0000268.DNG'), findsOneWidget);
    await pumpUntilFound(tester, find.byTooltip('Download again'));
    await tapWhenReady(tester, find.byTooltip('Download again'));
    await tapWhenReady(
      tester,
      find.byKey(const Key('viewer-download-choice:raw')),
    );
    await pumpUntil(
      tester,
      () => app.media.shots.length == 5,
      reason: 'RAW saved from the viewer',
    );
    expect(app.media.shots.last.names, ['R0000268.DNG']);
    await pumpUntilFound(
      tester,
      _inViewer('image:view:sd1|101RICOH/R0000268.JPG'),
    );
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find.text('R0000268.JPG + R0000268.DNG').evaluate().isEmpty,
      reason: 'viewer closed',
    );

    await app.dispose();
  });

  testWidgets('a long card builds only the days near the screen: a day far '
      'below has no label and no cell until it is scrolled to', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Thirty days of three shots, the oldest on 30 September.
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          httpLatency: Duration.zero,
          photos: [
            for (var day = 0; day < 30; day++)
              for (var n = 1; n <= 3; n++)
                FakePhoto(
                  '100RICOH',
                  'R${(day * 3 + n).toString().padLeft(7, '0')}.JPG',
                  DateTime(2026, 9, 30 + day, 12, n),
                ),
          ],
        ),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    final model = app.models.library.model;
    await pumpUntil(tester, () => model.shots != null, reason: 'listing');
    // Every date is known, as on a card looked through before.
    for (final s in model.shots!) {
      unawaited(model.ensureInfo(s.primary));
    }
    await pumpUntil(
      tester,
      () => model.shots!.every((s) => model.info(s.primary) != null),
      reason: 'every date',
    );

    const newest = 'sd1|100RICOH/R0000090';
    const oldest = 'sd1|100RICOH/R0000003';
    final oldestDay = find.textContaining('Sep 30', skipOffstage: false);
    expect(_cell(newest), findsOneWidget);
    expect(
      find.byKey(const ValueKey(oldest), skipOffstage: false),
      findsNothing,
    );
    expect(oldestDay, findsNothing);

    await tester.scrollUntilVisible(
      _cell(oldest),
      600,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 200,
    );
    expect(oldestDay, findsOneWidget);
    expect(
      find.byKey(const ValueKey(newest), skipOffstage: false),
      findsNothing,
    );

    await app.dispose();
  });

  testWidgets('a window made wider puts more shots on a row', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          photos: [
            for (var n = 1; n <= 5; n++)
              FakePhoto(
                '100RICOH',
                'R000000$n.JPG',
                DateTime(2026, 11, 5, 12, n),
              ),
          ],
        ),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    final cells = [
      for (var n = 5; n >= 1; n--) _cell('sd1|100RICOH/R000000$n'),
    ];
    await pumpUntilFound(tester, cells.last);
    List<double> tops() => [for (final c in cells) tester.getTopLeft(c).dy];

    final narrow = tops();
    expect(narrow.sublist(0, 3).toSet(), hasLength(1));
    expect(narrow[3], greaterThan(narrow[0]));
    expect(narrow[4], narrow[3]);

    // Unfolded, or turned on its side: five columns from 600 wide.
    tester.view.physicalSize = const Size(1800, 2532);
    await tester.pump();
    expect(tops().toSet(), hasLength(1));

    await app.dispose();
  });

  testWidgets('Not downloaded counts a shot out and drops it from the grid '
      'once it is saved', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    await pumpUntilFound(tester, _thumbs);

    const jpeg = 'sd1|101RICOH/R0000270';
    final chip = find.byKey(const ValueKey('chip:notDownloaded'));
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    expect(tester.widget<GrChip>(chip).count, 40);
    expect(_cell(jpeg), findsOneWidget);

    await tester.longPress(_cell(jpeg));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('selection-download:jpeg')));
    await tester.pump();
    await pumpUntil(
      tester,
      () => _cell(jpeg).evaluate().isEmpty,
      reason: 'the saved shot to leave Not downloaded',
    );
    expect(tester.widget<GrChip>(chip).count, 39);
    expect(app.media.shots.single.names, ['R0000270.JPG']);

    await app.dispose();
  });

  testWidgets('a photo-library save still running when the camera pages '
      'close saves once, and the queue and history carry on when they '
      'open again', (tester) async {
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    final gate = app.media.gate = Completer<void>();
    await app.pumpApp(tester);
    await _openLibrary(tester);
    const jpeg = 'sd1|101RICOH/R0000270';
    const raw = 'sd1|101RICOH/R0000269';
    await pumpUntilFound(tester, _cell(jpeg));
    await tester.longPress(_cell(jpeg));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('selection-download:jpeg')));
    await tester.pump();
    await pumpUntil(tester, () => app.media.held == 1, reason: 'save held');

    await tapWhenReady(tester, find.byKey(const Key('camera-back')));
    await pumpUntil(
      tester,
      () => find.byType(LibraryScreen).evaluate().isEmpty,
      reason: 'camera pages closed',
    );
    await _openLibrary(tester);
    await pumpUntilFound(tester, _cell(raw));
    // The shared listing shows at once, while the route still slides in.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.longPress(_cell(raw));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('selection-download:raw')));
    await tester.pump();

    app.media.gate = null;
    gate.complete();
    await pumpUntil(
      tester,
      () => app.media.shots.any((s) => s.names.contains('R0000269.DNG')),
      reason: 'RAW saved',
    );
    expect(
      [for (final s in app.media.shots) s.names],
      [
        ['R0000270.JPG'],
        ['R0000269.DNG'],
      ],
    );
    final manifest = File('${app.models.services.dataDir.path}/downloads.json');
    await pumpUntil(tester, () {
      final json = jsonDecode(manifest.readAsStringSync()) as Map;
      final downloaded = (json['downloaded'] as Map).values.expand(
        (records) => (records as Map).keys,
      );
      return (json['jobs'] as List).isEmpty &&
          downloaded.contains('$jpeg.JPG') &&
          downloaded.contains('$raw.DNG');
    }, reason: 'queue and history on disk');
    await pumpUntilFound(tester, _downloadedBadge(jpeg));
    await pumpUntilFound(tester, _downloadedBadge(raw));

    await app.dispose();
  });

  testWidgets('a failed download says why in the queue and downloads on '
      'retry', (tester) async {
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    app.media.failWith = const MediaSaveException(
      MediaSaveFailure.failed,
      'disk full',
    );
    await app.pumpApp(tester);
    await _openLibrary(tester);
    const jpeg = 'sd1|101RICOH/R0000270';
    await pumpUntilFound(tester, _cell(jpeg));
    await tester.longPress(_cell(jpeg));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('selection-download:jpeg')));
    await tester.pump();
    await pumpUntilFound(tester, find.text('1 download failed'));
    expect(find.text('Tap to see why'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('download-bar')));
    await pumpUntilFound(
      tester,
      find.text("JPEG · SD · Couldn't save to the photo library"),
    );

    app.media.failWith = null;
    await tapWhenReady(tester, find.text('Retry failed'));
    await pumpUntil(
      tester,
      () => app.media.shots.isNotEmpty,
      reason: 'saved on retry',
    );
    expect(app.media.shots.single.names, ['R0000270.JPG']);
    await pumpUntilFound(tester, find.text('Nothing to download'));

    await app.dispose();
  });

  testWidgets('a file the phone cannot write fails with a message of its '
      "own, never the platform's English", (tester) async {
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    // A file where the downloads folder goes: creating it fails with the
    // platform's own description ("Not a directory" or similar).
    final blocker = File('${app.models.services.cacheDir.path}/downloads');
    await tester.runAsync(() => blocker.writeAsString(''));
    await app.pumpApp(tester);
    await _openLibrary(tester);
    const jpeg = 'sd1|101RICOH/R0000270';
    await pumpUntilFound(tester, _cell(jpeg));
    await tester.longPress(_cell(jpeg));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('selection-download:jpeg')));
    await tester.pump();
    await pumpUntilFound(tester, find.text('1 download failed'));

    await tester.tap(find.byKey(const ValueKey('download-bar')));
    await pumpUntilFound(
      tester,
      find.text('JPEG · SD · Could not write the file'),
    );
    expect(find.textContaining('directory'), findsNothing);
    expect(find.textContaining('FileSystemException'), findsNothing);

    await app.dispose();
  });

  testWidgets('portrait shots appear upright in the grid and the viewer, '
      'never on their side first; grid cells never swap in a smaller '
      'stand-in, and the viewer sharpens to the full JPEG', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final at = DateTime(2026, 11, 5, 10);
    // Previews are unrotated landscape JPEGs without EXIF, as a GR serves
    // them; only /info says how each shot was held.
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          photos: [
            FakePhoto('100RICOH', 'R0000001.JPG', at),
            FakePhoto('100RICOH', 'R0000002.JPG', at, orientation: 6),
            FakePhoto('100RICOH', 'R0000003.JPG', at, orientation: 8),
            FakePhoto('100RICOH', 'R0000004.JPG', at, orientation: 3),
            FakePhoto('100RICOH', 'R0000005.JPG', at, orientation: null),
          ],
        ),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    Finder image(String size, int n) =>
        find.byKey(ValueKey('image:$size:sd1|100RICOH/R000000$n.JPG'));
    const expected = {
      1: (0, false),
      2: (1, false),
      3: (3, false),
      4: (2, false),
      5: (0, false),
    };
    // Checked on every frame: a picture never shows before its turn is
    // known, and a cell never shows a smaller stand-in it later swaps out.
    bool allShown() {
      for (final n in expected.keys) {
        expect(image('thumb', n), findsNothing, reason: '$n thumbnail');
        if (image('view', n).evaluate().isNotEmpty) {
          expect(_shownAs(tester, image('view', n)), expected[n], reason: '$n');
        }
      }
      return expected.keys.every((n) => image('view', n).evaluate().isNotEmpty);
    }

    await pumpUntil(tester, allShown, reason: 'grid previews upright');

    await tester.tap(_cell('sd1|100RICOH/R0000002'));
    final view = _inViewer('image:view:sd1|100RICOH/R0000002.JPG');
    await pumpUntilFound(tester, view);
    final raw = find.descendant(of: view, matching: find.byType(RawImage));
    await pumpUntil(
      tester,
      () => tester.widget<RawImage>(raw).image != null,
      reason: 'preview decoded',
    );
    expect(_shownAs(tester, view), (1, false));
    // The stored 24×16 frame is laid out in the viewer's box turned on its
    // side, so it shows taller than wide at its own aspect ratio.
    final stored = tester.widget<RawImage>(raw).image!;
    expect((stored.width, stored.height), (24, 16));
    final box = tester.getSize(view);
    expect(tester.getSize(raw), Size(box.height, box.width));

    // The preview is smaller than the screen, so the full JPEG follows. It
    // carries its own Orientation tag, which the decoder applies. Until it
    // shows, a mark in the top corner of the photo (16×24 upright, fitted
    // to its page) says so.
    final sharpening = _inViewer('viewer-sharpening');
    await pumpUntilFound(tester, sharpening);
    final page = tester.getRect(
      find.descendant(
        of: find.byType(ShotViewer),
        matching: find.byType(PageView),
      ),
    );
    final photo = Alignment.center.inscribe(
      applyBoxFit(BoxFit.contain, const Size(16, 24), page.size).destination,
      page,
    );
    expect(photo.size, isNot(page.size), reason: 'bands beside the photo');
    final mark = tester.getRect(sharpening);
    expect(mark.right, closeTo(photo.right - 12, .01));
    expect(mark.top, closeTo(photo.top + 12, .01));
    final full = _inViewer('image:full:sd1|100RICOH/R0000002.JPG');
    await pumpUntilFound(tester, full);
    final fullRaw = find.descendant(of: full, matching: find.byType(RawImage));
    await pumpUntil(
      tester,
      () => tester.widget<RawImage>(fullRaw).image != null,
      reason: 'full image decoded',
    );
    expect(_shownAs(tester, full), (0, false));
    final decoded = tester.widget<RawImage>(fullRaw).image!;
    expect((decoded.width, decoded.height), (16, 24));
    await pumpUntil(
      tester,
      () => sharpening.evaluate().isEmpty,
      reason: 'the mark gone once the full photo shows',
    );

    await app.dispose();
  });

  testWidgets('a thumbnail whose first request fails loads on a retry', (
    tester,
  ) async {
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          previewFailures: 1,
          photos: [
            FakePhoto('100RICOH', 'R0000001.JPG', DateTime(2026, 11, 5)),
          ],
        ),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    await _pumpSecondsUntil(
      tester,
      () => _thumbs.evaluate().isNotEmpty,
      reason: 'thumbnail after a retry',
    );

    await app.dispose();
  });

  testWidgets('after repeated failures a thumbnail offers a retry, which '
      'loads it', (tester) async {
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          previewFailures: 4,
          photos: [
            FakePhoto('100RICOH', 'R0000001.JPG', DateTime(2026, 11, 5)),
          ],
        ),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    final retry = find.byKey(
      const ValueKey('image-retry:view:sd1|100RICOH/R0000001.JPG'),
    );
    await _pumpSecondsUntil(
      tester,
      () => retry.evaluate().isNotEmpty,
      reason: 'retry button',
    );
    expect(_thumbs, findsNothing);
    await tester.tap(retry);
    await tester.pump();
    await pumpUntilFound(tester, _thumbs);
    expect(retry, findsNothing);

    await app.dispose();
  });

  testWidgets('a thumbnail that arrives but never decodes stops retrying '
      'and offers a retry', (tester) async {
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          // One answer per automatic attempt: a retry loop that never ends
          // would never show the button.
          brokenPreviews: 4,
          photos: [
            FakePhoto('100RICOH', 'R0000001.JPG', DateTime(2026, 11, 5)),
          ],
        ),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    final retry = find.byKey(
      const ValueKey('image-retry:view:sd1|100RICOH/R0000001.JPG'),
    );
    await _pumpSecondsUntil(
      tester,
      () => retry.evaluate().isNotEmpty,
      reason: 'retry button',
    );
    expect(_thumbs, findsNothing);
    await tester.tap(retry);
    await tester.pump();
    await _pumpSecondsUntil(
      tester,
      () => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((r) => r.image != null),
      reason: 'decoded thumbnail',
    );
    expect(retry, findsNothing);

    await app.dispose();
  });

  testWidgets('a shot replaced at its path while the Wi-Fi was down shows '
      'the new picture and loses its downloaded mark', (tester) async {
    final taken = DateTime(2026, 11, 5, 8);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          photos: [FakePhoto('100RICOH', 'R0000001.JPG', taken)],
        ),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    const shot = 'sd1|100RICOH/R0000001';
    final picture = find.byKey(const ValueKey('image:view:$shot.JPG'));
    String shown() => latin1.decode(
      (tester.widget<Image>(picture).image as MemoryImage).bytes,
    );
    await pumpUntilFound(tester, picture);
    expect(shown(), contains(taken.toIso8601String()));
    await tester.longPress(_cell(shot));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('selection-download:jpeg')));
    await tester.pump();
    await pumpUntilFound(tester, _downloadedBadge(shot));

    // Another card, with another shot under the same name, while the
    // Wi-Fi is down.
    app.camera.dropWifi();
    await pumpUntil(
      tester,
      () => app.models.library.link.value == null,
      reason: 'link lost',
    );
    final old = app.camera.photos.single;
    final again = taken.add(const Duration(days: 1));
    app.camera
      ..removePhoto(old.path)
      ..addPhoto(FakePhoto('100RICOH', 'R0000001.JPG', again));

    await pumpUntil(
      tester,
      () =>
          picture.evaluate().isNotEmpty &&
          shown().contains(again.toIso8601String()),
      reason: 'the new picture',
    );
    await pumpUntil(
      tester,
      () => _downloadedBadge(shot).evaluate().isEmpty,
      reason: 'downloaded mark gone',
    );

    await app.dispose();
  });

  testWidgets('Updating… and Connecting… show beside the Library title and '
      'leave the photos where they are', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    await pumpUntilFound(tester, _thumbs);
    final progress = find.byKey(const Key('library-progress'));
    final chips = find.byKey(const ValueKey('chip:all'));
    await pumpUntil(
      tester,
      () => progress.evaluate().isEmpty,
      reason: 'the first update to end',
    );
    final settled = tester.getTopLeft(chips);

    void expectBesideTitle(String text) {
      expect(
        find.descendant(of: progress, matching: find.text(text)),
        findsOneWidget,
      );
      final title = tester.getRect(
        find.descendant(
          of: find.byType(PageTitle),
          matching: find.text('Library'),
        ),
      );
      final shown = tester.getRect(progress);
      expect(shown.left, greaterThan(title.right));
      expect(shown.center.dy, inInclusiveRange(title.top, title.bottom));
      expect(tester.getTopLeft(chips), settled);
    }

    unawaited(app.models.library.model.refresh());
    await tester.pump();
    expectBesideTitle('Updating…');
    await pumpUntil(
      tester,
      () => progress.evaluate().isEmpty,
      reason: 'the update to end',
    );
    expect(tester.getTopLeft(chips), settled);

    app.camera.dropWifi();
    await pumpUntil(
      tester,
      () => app.models.library.link.value == null,
      reason: 'link lost',
    );
    await tester.pump();
    expectBesideTitle('Connecting…');

    await app.dispose();
  });

  testWidgets('with text so large that the Library title fills its row, '
      'Updating… keeps its spinner and leaves the photos where they are', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    await pumpUntilFound(tester, _thumbs);
    final progress = find.byKey(const Key('library-progress'));
    final chips = find.byKey(const ValueKey('chip:all'));
    await pumpUntil(
      tester,
      () => progress.evaluate().isEmpty,
      reason: 'the first update to end',
    );
    final settled = tester.getTopLeft(chips);

    unawaited(app.models.library.model.refresh());
    await tester.pump();
    final spinner = tester.getRect(
      find.descendant(
        of: progress,
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    final title = tester.getRect(
      find.descendant(
        of: find.byType(PageTitle),
        matching: find.text('Library'),
      ),
    );
    final row = tester.getRect(
      find.ancestor(of: find.text('Library'), matching: find.byType(PageTitle)),
    );
    expect(spinner.size, const Size(12, 12));
    expect(spinner.left, greaterThan(title.right));
    expect(spinner.right, lessThan(row.right));
    expect(tester.getTopLeft(chips), settled);

    await pumpUntil(
      tester,
      () => progress.evaluate().isEmpty,
      reason: 'the update to end',
    );
    await app.dispose();
  });

  testWidgets('the top bar, with Settings in it, leaves as the Library '
      'scrolls down and comes back over the photos when it scrolls up', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
      ),
    ))!;
    await app.pumpApp(tester);
    await _openLibrary(tester);
    await pumpUntilFound(tester, _thumbs);
    const bar = ['camera-back', 'camera-pill', 'camera-settings'];
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
    void expectBar({required bool shown}) {
      for (final key in bar) {
        expect(
          find.byKey(Key(key)).hitTestable(),
          shown ? findsOne : findsNothing,
          reason: key,
        );
      }
    }

    final title = find.descendant(
      of: find.byType(PageTitle),
      matching: find.text('Library'),
    );
    final page = find.descendant(
      of: find.byType(LibraryScreen),
      matching: find.byType(CustomScrollView),
    );
    final scrolled = tester
        .state<ScrollableState>(
          find.descendant(of: page, matching: find.byType(Scrollable)).first,
        )
        .position;
    Future<void> scroll(double dy) async {
      await tester.drag(page, Offset(0, dy));
      // The bar finishes sliding once the finger is up.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expectBar(shown: true);
    expect(rect('camera-settings').center.dy, rect('camera-back').center.dy);
    expect(
      rect('camera-settings').left,
      greaterThan(rect('camera-pill').right),
    );
    expect(rect('camera-back').bottom, lessThan(tester.getRect(title).top));

    await scroll(-400);
    expectBar(shown: false);

    await scroll(60);
    expectBar(shown: true);
    expect(rect('camera-back').top, greaterThan(0));
    // Only the bar came back: the page is still where it was scrolled to.
    expect(scrolled.pixels, greaterThan(300));
    expect(title.hitTestable(), findsNothing);
    // The bar has no background: the photos it came back over show
    // between its buttons, and take a tap there.
    final betweenButtons = Offset(
      (rect('camera-pill').right + rect('camera-settings').left) / 2,
      rect('camera-back').center.dy,
    );
    expect(tapReaches(tester, betweenButtons, find.byType(ShotCell)), isTrue);

    await scroll(-60);
    expectBar(shown: false);

    await app.dispose();
  });

  testWidgets('Play cannot be tapped again while the camera confirms the '
      'movie', (tester) async {
    final app = (await tester.runAsync(
      () => createTestApp(
        config: FakeCameraConfig(
          bonded: true,
          photos: [
            FakePhoto(
              '100RICOH',
              'R0000001.MOV',
              DateTime(2026, 11, 5, 8),
              videoLength: const Duration(seconds: 5),
            ),
          ],
        ),
        saveCamera: true,
      ),
    ))!;
    final gate = app.camera.infoGate = Completer<void>();
    await app.pumpApp(tester);
    await _openLibrary(tester);
    await tapWhenReady(tester, _cell('sd1|100RICOH/R0000001.MOV'));
    final play = _inViewer('viewer-play');
    await tapWhenReady(tester, play);
    expect(play, findsNothing);
    expect(
      find.descendant(
        of: find.byType(ShotViewer),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    gate.complete();
    app.camera.infoGate = null;
    await pumpUntil(
      tester,
      () => find.textContaining('Copying').evaluate().isNotEmpty,
      reason: 'the copy starts once the camera answers',
    );

    await app.dispose();
  });

  testWidgets('on a closed iPhone Duo, Back and Settings stand in the bar '
      'down its side, under the status; the Library keeps to the rest of '
      'the window, three shots to a line, and is the same page, scrolled '
      'as far, in a window without the bar', (tester) async {
    final app = await _libraryOf(tester, 40);
    final page = _pageScroll(tester);
    await _toDuo(tester, app, DuoWindow.closed);
    Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
    // The bar's strip, under the status at its top, and the bottom of the
    // window above the system's inset.
    const strip = Rect.fromLTRB(382, 174, 466, 678);
    const bottom = 678 - 34.0;
    for (final key in ['camera-back', 'camera-settings']) {
      expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
      expect(strip.expandToInclude(rect(key)), strip, reason: key);
    }
    expect(
      rect('camera-back').bottom,
      lessThanOrEqualTo(rect('camera-settings').top),
    );
    // The window has no inset at its top, where its corners are rounded.
    expect(rect('camera-pill').top, greaterThanOrEqualTo(14));
    expect(rect('camera-pill').right, lessThanOrEqualTo(strip.left));
    final title = tester.getRect(_title);
    final chip = rect('chip:all');
    expect(title.right, lessThanOrEqualTo(strip.left));
    expect(chip.top, greaterThanOrEqualTo(title.bottom));
    expect(chip.right, lessThanOrEqualTo(strip.left));

    expect(_firstLineCount(tester, 40), 3);
    expect(tester.getRect(_cell(_shotOf(40))).left, 0);
    expect(tester.getRect(_cell(_shotOf(38))).right, closeTo(strip.left, .5));
    for (final cell in _cellRects(tester)) {
      expect(cell.right, lessThanOrEqualTo(strip.left + .5));
    }
    // Nothing of the page takes a tap under the bar.
    final besideCells = Offset(
      strip.center.dx,
      tester.getCenter(_cell(_shotOf(38))).dy,
    );
    expect(tapReaches(tester, besideCells, find.byType(ShotCell)), isFalse);
    final besideChips = Offset(strip.center.dx, chip.center.dy);
    expect(tapReaches(tester, besideChips, find.byType(GrChip)), isFalse);

    await tester.longPress(_cell(_shotOf(40)));
    await tester.pump();
    final selection = tester.getRect(_selectionBar);
    expect(selection.right, lessThanOrEqualTo(strip.left));
    expect(selection.bottom, lessThanOrEqualTo(bottom));
    await tester.binding.handlePopRoute();
    await pumpUntil(
      tester,
      () => _selectionBar.evaluate().isEmpty,
      reason: 'no shots chosen',
    );

    await tester.drag(_page, const Offset(0, -300));
    await pumpRounds(tester, 20);
    final scrolled = page.position.pixels;
    expect(scrolled, greaterThan(200));
    await _toDuo(tester, app, DuoWindow.upright);
    expect(_pageScroll(tester), same(page));
    expect(page.position.pixels, closeTo(scrolled, 1));
    await _toDuo(tester, app, DuoWindow.closed);
    expect(_pageScroll(tester), same(page));
    expect(page.position.pixels, closeTo(scrolled, 1));

    await app.dispose();
  });

  for (final window in [DuoWindow.open, DuoWindow.book]) {
    testWidgets('on an iPhone Duo held wide (${window.name}) the Library '
        'keeps the first page, three shots to a line under the filters, and '
        'the second asks for a shot; half-open, nothing of it is on the '
        'fold', (tester) async {
      final app = await _libraryOf(tester, 40);
      await _toDuo(tester, app, window);
      Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
      // The bar's strip, under the status at its top.
      const strip = Rect.fromLTRB(867, 124, 951, 669);
      for (final key in ['camera-back', 'camera-settings']) {
        expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
        expect(strip.expandToInclude(rect(key)), strip, reason: key);
      }
      expect(rect('camera-pill').top, greaterThanOrEqualTo(14));

      // Flat, the pages meet in the middle of the fold.
      final fold = window.pose.fold!;
      final firstEnd = window.pose.halfOpen ? fold.left : fold.center.dx;
      final secondStart = window.pose.halfOpen ? fold.right : fold.center.dx;
      expect(_firstLineCount(tester, 40), 3);
      for (final cell in _cellRects(tester)) {
        expect(cell.right, lessThanOrEqualTo(firstEnd + .5));
      }
      expect(
        tester.getRect(find.byType(PageTitle)).right,
        lessThanOrEqualTo(firstEnd + .5),
      );
      expect(
        rect('chip:all').top,
        greaterThanOrEqualTo(tester.getRect(_title).bottom),
      );
      final asks = rect('shot-pane-empty');
      expect(asks.left, greaterThanOrEqualTo(secondStart));
      expect(asks.right, lessThanOrEqualTo(strip.left));
      expect(find.byType(ShotPane), findsNothing);

      await tester.longPress(_cell(_shotOf(40)));
      await tester.pump();
      expect(tester.getRect(_selectionBar).right, lessThanOrEqualTo(firstEnd));

      await app.dispose();
    });
  }

  testWidgets('on an open iPhone Duo a tap on a shot shows it on the second '
      'page and leaves the Library on the first as it was; another shot '
      'tapped or swiped to shows instead, a tap on the photo opens the '
      'viewer, and the shot the viewer ended on shows after it; Back ends '
      'choosing shots, then leaves', (tester) async {
    final app = await _libraryOf(tester, 40);
    await _toDuo(tester, app, DuoWindow.open);
    final page = _pageScroll(tester);
    final pane = find.byType(ShotPane);
    final viewer = find.byType(ShotViewer);
    Finder inPane(Finder finder) => find.descendant(of: pane, matching: finder);
    Finder inViewer(Finder finder) =>
        find.descendant(of: viewer, matching: finder);
    Finder markOf(int n) =>
        find.descendant(of: _cell(_shotOf(n)), matching: _shownMark);
    // Where the display folds, and where the bar's strip starts.
    const fold = 475.5;
    const strip = 867.0;
    final cellsBefore = _cellRects(tester);
    final scrolledBefore = page.position.pixels;

    await tester.tap(_cell(_shotOf(40)));
    await pumpUntilFound(tester, inPane(find.text(_nameOf(40))));
    await pumpRounds(tester, 15);
    expect(tester.takeException(), isNull);
    expect(viewer, findsNothing);
    expect(find.byKey(const Key('shot-pane-empty')), findsNothing);
    expect(_pageScroll(tester), same(page));
    // The Library's first page has not moved.
    expect(_cellRects(tester), cellsBefore);
    expect(page.position.pixels, scrolledBefore);
    // The Library has the first page, laid out as on a phone.
    expect(_firstLineCount(tester, 40), 3);
    expect(
      tester.getRect(find.byType(PageTitle)).right,
      lessThanOrEqualTo(fold + .5),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('chip:all'))).top,
      greaterThanOrEqualTo(tester.getRect(_title).bottom),
    );
    expect(markOf(40), findsOne);
    // The shot has the second: the photo across its top, then its name
    // with Download, then its details.
    expect(tester.getRect(pane).left, closeTo(fold, .5));
    expect(tester.getRect(pane).right, closeTo(strip, .5));
    final photo = tester.getRect(inPane(find.byType(PageView)));
    expect(photo.top, 0);
    expect(photo.left, closeTo(fold, .5));
    expect(photo.right, closeTo(strip, .5));
    final download = tester.getRect(
      inPane(find.byKey(const ValueKey('pane-download'))),
    );
    final details = tester.getRect(inPane(find.byType(GroupBox)));
    expect(download.top, greaterThanOrEqualTo(photo.bottom));
    expect(download.right, lessThanOrEqualTo(strip));
    expect(details.top, greaterThanOrEqualTo(download.bottom));
    expect(details.left, greaterThanOrEqualTo(fold));
    expect(details.right, lessThanOrEqualTo(strip));

    await tester.tap(_cell(_shotOf(38)));
    await pumpUntilFound(tester, inPane(find.text(_nameOf(38))));
    await pumpRounds(tester, 15);
    expect(inPane(find.text(_nameOf(40))), findsNothing);
    expect(_shownMark, findsOne);
    expect(markOf(38), findsOne);

    await tester.fling(
      inPane(find.byType(PageView)),
      const Offset(-300, 0),
      1000,
    );
    await pumpUntilFound(tester, inPane(find.text(_nameOf(37))));
    // The pages take no tap until they have come to rest.
    final swipe = tester
        .widget<PageView>(inPane(find.byType(PageView)))
        .controller!
        .position
        .isScrollingNotifier;
    await pumpUntil(tester, () => !swipe.value, reason: 'the swipe ended');
    await pumpRounds(tester, 15);
    expect(_shownMark, findsOne);
    expect(markOf(37), findsOne);

    await tester.tap(inPane(find.byType(PageView)));
    await pumpUntilFound(tester, inViewer(find.text(_nameOf(37))));
    // The route has finished sliding in.
    await pumpRounds(tester, 30);
    await tester.fling(
      inViewer(find.byType(PageView)),
      const Offset(-600, 0),
      1000,
    );
    await pumpUntilFound(tester, inViewer(find.text(_nameOf(36))));
    await pumpRounds(tester, 30);
    await tester.binding.handlePopRoute();
    await pumpUntil(
      tester,
      () => viewer.evaluate().isEmpty,
      reason: 'viewer closed',
    );
    await pumpUntilFound(tester, inPane(find.text(_nameOf(36))));
    await pumpRounds(tester, 15);
    expect(_shownMark, findsOne);
    expect(markOf(36), findsOne);

    await tester.longPress(_cell(_shotOf(39)));
    await tester.pump();
    expect(tester.getRect(_selectionBar).right, lessThanOrEqualTo(fold));
    expect(pane, findsOne);
    await tester.binding.handlePopRoute();
    await pumpUntil(
      tester,
      () => _selectionBar.evaluate().isEmpty,
      reason: 'no shots chosen',
    );
    expect(pane, findsOne);
    // The bar's Back, as the system's, leaves the Library.
    await tester.tap(find.byKey(const Key('camera-back')));
    await pumpUntil(
      tester,
      () => find.byType(LibraryScreen).evaluate().isEmpty,
      reason: 'the Library left',
    );

    await app.dispose();
  });

  testWidgets('closing an iPhone Duo, or turning it upright, puts the shot '
      'beside the Library away and leaves the Library scrolled to where it '
      'was', (tester) async {
    final app = await _libraryOf(tester, 40);
    await _toDuo(tester, app, DuoWindow.open);
    final page = _pageScroll(tester);
    final pane = find.byType(ShotPane);
    await tester.tap(_cell(_shotOf(40)));
    await pumpUntilFound(tester, pane);
    await tester.drag(_page, const Offset(0, -300));
    await pumpRounds(tester, 20);
    // A shot in the middle of the first page: the closed phone's window,
    // scrolled as far, has it in view too.
    final cell = _cellNearest(tester, tester.getCenter(_page));
    await tester.tap(cell);
    await pumpRounds(tester, 20);
    expect(find.descendant(of: cell, matching: _shownMark), findsOne);
    final scrolled = page.position.pixels;
    expect(scrolled, greaterThan(200));

    await _toDuo(tester, app, DuoWindow.closed);
    expect(pane, findsNothing);
    expect(_shownMark, findsNothing);
    expect(_pageScroll(tester), same(page));
    expect(page.position.pixels, closeTo(scrolled, 1));
    expect(cell.hitTestable(), findsOne);
    for (final built in _cellRects(tester)) {
      expect(built.right, lessThanOrEqualTo(382.5));
    }

    // Opened again, the second page asks for a shot.
    await _toDuo(tester, app, DuoWindow.open);
    expect(pane, findsNothing);
    expect(find.byKey(const Key('shot-pane-empty')), findsOne);
    await tapWhenReady(tester, cell);
    await pumpUntilFound(tester, pane);
    await _toDuo(tester, app, DuoWindow.upright);
    expect(pane, findsNothing);
    expect(_pageScroll(tester), same(page));
    expect(find.byType(ShotViewer), findsNothing);

    await app.dispose();
  });

  testWidgets('a phone on its side, and a foldable whose fold lies across '
      'its window, keep five shots to a line, Back and Settings in the top '
      'bar and the filters under the title, and open a shot in the '
      'viewer', (tester) async {
    final app = await _libraryOf(tester, 12);
    addTearDown(tester.view.reset);
    Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
    final viewer = find.byType(ShotViewer);
    Future<void> expectAsBefore(String window) async {
      await pumpRounds(tester, 15);
      expect(tester.takeException(), isNull, reason: window);
      expect(_firstLineCount(tester, 12), 5, reason: window);
      final title = tester.getRect(_title);
      expect(rect('camera-back').bottom, lessThanOrEqualTo(title.top));
      expect(rect('camera-settings').center.dy, rect('camera-back').center.dy);
      expect(rect('chip:all').top, greaterThanOrEqualTo(title.bottom));
      await tester.tap(_cell(_shotOf(12)));
      await pumpUntilFound(tester, viewer);
      expect(find.byType(ShotPane), findsNothing, reason: window);
      // The route has finished sliding in.
      await pumpRounds(tester, 30);
      await tester.binding.handlePopRoute();
      await pumpUntil(
        tester,
        () => viewer.evaluate().isEmpty,
        reason: 'viewer closed',
      );
    }

    tester.view
      ..physicalSize = const Size(2868, 1320)
      ..devicePixelRatio = 3;
    await expectAsBefore('a phone on its side');

    tester.view
      ..physicalSize = const Size(750, 830)
      ..devicePixelRatio = 1
      ..displayFeatures = [_fold(const Rect.fromLTWH(0, 405, 750, 20))];
    await expectAsBefore('a fold across the window');

    await app.dispose();
  });

  testWidgets('an unfolded foldable with its hinge upright has the '
      "Library's two pages, three shots to a line before the hinge under a "
      'top bar with Back and Settings, and a shot that is tapped on the '
      'second page; Back leaves', (tester) async {
    final app = await _libraryOf(tester, 12);
    const hinge = Rect.fromLTWH(365, 0, 20, 830);
    tester.view
      ..physicalSize = const Size(750, 830)
      ..devicePixelRatio = 1
      ..displayFeatures = [_fold(hinge)];
    addTearDown(tester.view.reset);
    await pumpRounds(tester, 15);
    expect(tester.takeException(), isNull);
    final pane = find.byType(ShotPane);

    expect(_firstLineCount(tester, 12), 3);
    for (final cell in _cellRects(tester)) {
      expect(cell.right, lessThanOrEqualTo(hinge.left + .5));
    }
    expect(
      tester.getRect(find.byKey(const Key('camera-back'))).bottom,
      lessThanOrEqualTo(tester.getRect(_title).top),
    );
    expect(
      tester.getRect(find.byKey(const Key('shot-pane-empty'))).left,
      greaterThanOrEqualTo(hinge.right),
    );
    final cellsBefore = _cellRects(tester);

    await tester.tap(_cell(_shotOf(12)));
    await pumpUntilFound(tester, pane);
    await pumpRounds(tester, 15);
    expect(tester.takeException(), isNull);
    expect(find.byType(ShotViewer), findsNothing);
    expect(tester.getRect(pane).left, closeTo(hinge.right, .5));
    expect(tester.getRect(pane).right, closeTo(750, .5));
    expect(_cellRects(tester), cellsBefore);

    await tester.binding.handlePopRoute();
    await pumpUntil(
      tester,
      () => find.byType(LibraryScreen).evaluate().isEmpty,
      reason: 'the Library left',
    );

    await app.dispose();
  });
}
