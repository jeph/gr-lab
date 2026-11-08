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
    expect(find.byType(LibraryScreen), findsOneWidget);

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
}
