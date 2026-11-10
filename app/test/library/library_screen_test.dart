import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/library/shot.dart' show Shot;
import 'package:grlab/src/library/viewer.dart';
import 'package:grlab/src/services.dart';
import 'package:grlab/src/widgets/group.dart';

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

    // The viewer's Download asks which half of the pair, again.
    await tester.tap(_cell(pair));
    await pumpUntilFound(tester, find.text('R0000268.JPG'));
    expect(
      find.descendant(
        of: find.byType(ShotViewer),
        matching: find.text('RAW+JPEG'),
      ),
      findsOneWidget,
    );
    expect(find.text('R0000268.JPG + R0000268.DNG'), findsOneWidget);
    await pumpUntilFound(tester, find.text('Download again'));
    await tapWhenReady(tester, find.text('Download again'));
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
}
