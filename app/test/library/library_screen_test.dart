import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/library/shot.dart' show Shot;
import 'package:grlab/src/library/viewer.dart';

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

    // The viewer offers each half of the pair, again.
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
    await pumpUntilFound(tester, find.text('Download JPEG again'));
    expect(find.text('Download RAW again'), findsOneWidget);
    await tapWhenReady(tester, find.text('Download RAW again'));
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
    // carries its own Orientation tag, which the decoder applies.
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
}
