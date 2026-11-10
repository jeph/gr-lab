import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/debug/debug_log.dart';
import 'package:grlab/src/settings/debug_log_group.dart';
import 'package:grlab/src/theme/tokens.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('debug_log_group_test');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<DebugLog> open(WidgetTester tester, ShareLogFiles share) async =>
      (await tester.runAsync(() async {
        final settings = await SettingsController.load(temp);
        return await DebugLog.open(
          dir: Directory('${temp.path}/debug-log'),
          defaultEnabled: true,
          settings: settings,
          share: share,
        );
      }))!;

  Future<void> pumpGroup(WidgetTester tester, DebugLog log) =>
      tester.pumpWidget(
        MaterialApp(
          theme: grTheme(GrColors.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(children: [DebugLogGroup(log: log)]),
          ),
        ),
      );

  // The log's file work is real I/O, so let real time pass between frames.
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 500 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(finder, findsOneWidget);
  }

  testWidgets('a failing share says so instead of throwing', (tester) async {
    final log = await open(
      tester,
      (files, origin) async =>
          throw const FileSystemException('share sheet unavailable'),
    );
    // Recorded in real time: the writes are real I/O.
    await tester.runAsync(() {
      log.sink(
        TraceEvent(
          channel: TraceChannel.ble,
          direction: TraceDirection.inbound,
          kind: 'read',
        ),
      );
      return log.flush();
    });
    await pumpGroup(tester, log);

    await tester.tap(find.byKey(const Key('setting-debug-log-export')));
    await pumpUntilFound(
      tester,
      find.text("Couldn't export the log. Try again."),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exporting an empty log says so without sharing', (tester) async {
    var shared = false;
    final log = await open(tester, (files, origin) async => shared = true);
    await pumpGroup(tester, log);

    await tester.tap(find.byKey(const Key('setting-debug-log-export')));
    await pumpUntilFound(
      tester,
      find.text('The log is empty. Nothing to export.'),
    );
    expect(shared, isFalse);
  });

  testWidgets('a log that could not open says logging is unavailable', (
    tester,
  ) async {
    final logDir = File('${temp.path}/debug-log');
    await tester.runAsync(() => logDir.writeAsString(''));
    final log = await open(tester, (files, origin) async {});
    await pumpGroup(tester, log);

    expect(
      find.text(
        "Logging unavailable: couldn't open the log folder. Restart the app "
        'to try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Keeps app and camera logs for bug reports'),
      findsNothing,
    );
  });

  test('sizes read in plain units, formatted for the locale', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(formatLogSize(en, 512), '512 B');
    expect(formatLogSize(en, 20 * 1024), '20 KB');
    expect(formatLogSize(en, 1234567), '1.2 MB');
    expect(formatLogSize(en, 1536 * 1024 * 1024), '1,536.0 MB');
  });
}
