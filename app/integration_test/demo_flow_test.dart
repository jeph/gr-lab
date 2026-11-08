import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/main.dart' as app;
import 'package:grlab/src/library/shot_cell.dart';
import 'package:grlab/src/platform/app_dirs.dart';
import 'package:integration_test/integration_test.dart';

/// The whole app on a device or simulator against the demo camera:
/// first-run pairing, connecting, the Library grid, and downloading two
/// shots into the photo library.
///
/// Run with `flutter test integration_test --dart-define=GR_DEMO=true`.
/// On the iOS simulator grant Photos access first:
/// `xcrun simctl privacy booted grant photos-add io.jeph.grlab`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pair, connect, browse and download', (tester) async {
    expect(
      const bool.fromEnvironment('GR_DEMO'),
      isTrue,
      reason: 'run with --dart-define=GR_DEMO=true',
    );
    // Start from a first run: no saved camera, downloads or caches.
    final dirs = await appDirectories();
    for (final d in [dirs.data, dirs.cache]) {
      final demo = Directory('${d.path}/demo');
      if (demo.existsSync()) await demo.delete(recursive: true);
    }

    await app.main();
    await _pumpUntilFound(tester, find.byKey(const Key('pair-add-1234567')));
    await tester.tap(find.byKey(const Key('pair-add-1234567')));
    await _pumpUntilFound(tester, find.byKey(const Key('pair-start')));
    await tester.tap(find.byKey(const Key('pair-start')));

    await _pumpUntilFound(
      tester,
      find.byKey(const Key('pairing-done-button')),
      timeout: const Duration(seconds: 30),
    );
    await tester.tap(find.byKey(const Key('pairing-done-button')));

    final pillState = find.byKey(const Key('camera-pill-state'));
    await _pumpUntil(
      tester,
      () =>
          pillState.evaluate().isNotEmpty &&
          tester.widget<Text>(pillState).data == 'Wi-Fi',
      timeout: const Duration(seconds: 60),
      reason: 'the camera pill to show the Wi-Fi link',
    );
    await _pumpUntilFound(tester, find.byType(ShotCell));

    final cells = find.byType(ShotCell);
    await tester.longPress(cells.at(0));
    await tester.pumpAndSettle();
    await tester.tap(cells.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-download')));

    await _pumpUntil(
      tester,
      () =>
          tester
              .widgetList<ShotCell>(find.byType(ShotCell))
              .where((c) => c.mark == CellMark.downloaded)
              .length ==
          2,
      timeout: const Duration(seconds: 90),
      reason: 'both selected shots saved to the photo library',
    );
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) => _pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
  reason: '$finder',
);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required Duration timeout,
  required String reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $reason');
    await tester.pump(const Duration(milliseconds: 100));
  }
}
