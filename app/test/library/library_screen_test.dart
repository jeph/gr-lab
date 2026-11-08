import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/library/viewer.dart';

import '../support/test_app.dart';

/// Thumbnails the grid has loaded, keyed `image:thumb:<file key>`.
final _thumbs = find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('image:thumb:'),
);

Finder _cell(String key) => find.byKey(ValueKey(key));

Finder _downloadedBadge(String key) =>
    find.descendant(of: _cell(key), matching: find.byIcon(Icons.check_rounded));

/// Quarter turns and mirroring the image keyed [key] is shown with.
(int, bool) _shownAs(WidgetTester tester, String key) {
  final image = find.byKey(ValueKey(key));
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

void main() {
  testWidgets('grid shows thumbnails and tags; selected shots download and '
      'get badges', (tester) async {
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
    // The Cameras screen connects to the nearby camera, then the Library
    // replaces it.
    await pumpUntilFound(tester, find.byType(LibraryScreen));

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
    // RAW+JPEG defaults to Both: the JPEG plus both halves of the pair.
    await pumpUntil(
      tester,
      () => tester
          .widget<Text>(find.byKey(const ValueKey('selection-detail')))
          .data!
          .contains('MB'),
      reason: 'selection size',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('selection-detail'))).data,
      startsWith('3 files · '),
    );

    await tester.tap(find.byKey(const ValueKey('selection-download')));
    await tester.pump();
    expect(find.text('2 selected'), findsNothing);

    await pumpUntil(
      tester,
      () => app.media.shots.length == 2,
      reason: 'two shots saved',
    );
    expect(
      [for (final s in app.media.shots) s.names],
      unorderedEquals([
        ['R0000270.JPG'],
        ['R0000268.JPG', 'R0000268.DNG'],
      ]),
    );
    // Records land after each save; the pair is saved last.
    await pumpUntilFound(tester, _downloadedBadge(jpeg));
    await pumpUntilFound(tester, _downloadedBadge(pair));
    expect(_downloadedBadge('sd1|101RICOH/R0000269'), findsNothing);

    // The viewer shows the shot and that it is already on the phone.
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
    await pumpUntilFound(tester, find.text('Downloaded'));
    await pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('image:view:sd1|101RICOH/R0000268.JPG'))
          .evaluate()
          .isNotEmpty,
      reason: 'preview',
    );
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find.text('R0000268.JPG + R0000268.DNG').evaluate().isEmpty,
      reason: 'viewer closed',
    );

    await app.dispose();
  });

  testWidgets('portrait shots show upright in the grid and the viewer, '
      'from the orientation /info reports', (tester) async {
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
    String thumb(int n) => 'image:thumb:sd1|100RICOH/R000000$n.JPG';
    const expected = {
      1: (0, false),
      2: (1, false),
      3: (3, false),
      4: (2, false),
      5: (0, false),
    };
    await pumpUntil(
      tester,
      () => expected.keys.every(
        (n) =>
            find.byKey(ValueKey(thumb(n))).evaluate().isNotEmpty &&
            _shownAs(tester, thumb(n)) == expected[n],
      ),
      reason: 'grid thumbnails upright',
    );
    // Decode size follows the shown width: the stored height of a turned
    // thumbnail.
    final cell = (1170 / 3).round();
    ResizeImage resize(int n) =>
        tester.widget<Image>(find.byKey(ValueKey(thumb(n)))).image
            as ResizeImage;
    expect((resize(1).width, resize(1).height), (cell, null));
    expect((resize(2).width, resize(2).height), (null, cell));

    await tester.tap(_cell('sd1|100RICOH/R0000002'));
    const view = 'image:view:sd1|100RICOH/R0000002.JPG';
    await pumpUntilFound(tester, find.byKey(const ValueKey(view)));
    final raw = find.descendant(
      of: find.byKey(const ValueKey(view)),
      matching: find.byType(RawImage),
    );
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
    final box = tester.getSize(find.byKey(const ValueKey(view)));
    expect(tester.getSize(raw), Size(box.height, box.width));

    await app.dispose();
  });
}
