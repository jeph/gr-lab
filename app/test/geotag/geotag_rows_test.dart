import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/geotag/geotag_rows.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';

const _geotagSwitch = Key('camera-sheet-geotag-switch');
const _settings = Key('camera-sheet-geotag-settings');
const _turnOn = Key('camera-sheet-geotag-turn-on');
const _syncSwitch = Key('camera-sheet-sync-time-switch');

/// What the rows told their callbacks, oldest first.
final _calls = <String>[];

/// Pumps the two rows in a group as the camera sheet has them, on a
/// phone-sized screen.
Future<void> _pump(
  WidgetTester tester, {
  required bool live,
  GeotagStatus status = GeotagStatus.off,
  bool syncTime = true,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _calls.clear();
  await tester.pumpWidget(
    MaterialApp(
      theme: grTheme(GrColors.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: GroupBox(
            children: [
              GeotagRow(
                live: live,
                status: status,
                onChanged: (on) => _calls.add('live $on'),
                onOpenSettings: () => _calls.add('settings'),
                onTurnOnCamera: () => _calls.add('turn on'),
              ),
              SyncTimeRow(
                live: live,
                syncTime: syncTime,
                onChanged: (on) => _calls.add('sync $on'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const subtitles = {
    GeotagStatus.off: 'Off',
    GeotagStatus.unsupported: 'Not available on this camera',
    GeotagStatus.needsLocation: 'Allow location for GR Photo',
    GeotagStatus.needsPreciseLocation: 'Allow precise location for GR Photo',
    GeotagStatus.locationOff: 'Turn on location on this phone',
    GeotagStatus.waitingForCamera: 'Starts when the camera is on',
    GeotagStatus.offOnCamera: 'Store Location Info is off on the camera',
    GeotagStatus.needsApp: 'Starting…',
    GeotagStatus.stopped: 'Stopped',
    GeotagStatus.waitingForLocation: "Finding this phone's location…",
    GeotagStatus.sending: 'Sending location to the camera',
  };

  testWidgets('the Geotagging row says where live geotagging stands, with '
      'a button for what the user can put right', (tester) async {
    expect(subtitles.keys, GeotagStatus.values);
    for (final status in GeotagStatus.values) {
      await _pump(tester, live: true, status: status);
      expect(find.text('Geotagging'), findsOneWidget, reason: '$status');
      expect(find.text(subtitles[status]!), findsOneWidget, reason: '$status');
      expect(tester.widget<Switch>(find.byKey(_geotagSwitch)).value, isTrue);
      final settings = switch (status) {
        GeotagStatus.needsLocation ||
        GeotagStatus.needsPreciseLocation ||
        GeotagStatus.locationOff => true,
        _ => false,
      };
      expect(
        find.byKey(_settings),
        settings ? findsOneWidget : findsNothing,
        reason: '$status',
      );
      expect(
        find.byKey(_turnOn),
        status == GeotagStatus.offOnCamera ? findsOneWidget : findsNothing,
        reason: '$status',
      );
    }
  });

  testWidgets('while live geotagging is off the row says Off and has no '
      'button, whatever the status', (tester) async {
    for (final status in GeotagStatus.values) {
      await _pump(tester, live: false, status: status);
      expect(find.text('Off'), findsOneWidget, reason: '$status');
      expect(tester.widget<Switch>(find.byKey(_geotagSwitch)).value, isFalse);
      expect(find.byKey(_settings), findsNothing, reason: '$status');
      expect(find.byKey(_turnOn), findsNothing, reason: '$status');
    }
  });

  testWidgets('the Geotagging switch and buttons report to their callbacks', (
    tester,
  ) async {
    await _pump(tester, live: false);
    await tester.tap(find.byKey(_geotagSwitch));
    expect(_calls, ['live true']);

    await _pump(tester, live: true, status: GeotagStatus.needsLocation);
    await tester.tap(find.byKey(_geotagSwitch));
    await tester.tap(find.text('Settings'));
    expect(_calls, ['live false', 'settings']);

    await _pump(tester, live: true, status: GeotagStatus.offOnCamera);
    await tester.tap(find.text('Turn on'));
    expect(_calls, ['turn on']);
  });

  testWidgets('the Sync time switch is locked on while live geotagging is '
      'on', (tester) async {
    await _pump(
      tester,
      live: true,
      status: GeotagStatus.sending,
      syncTime: false,
    );
    final locked = tester.widget<Switch>(find.byKey(_syncSwitch));
    expect(locked.value, isTrue);
    expect(locked.onChanged, isNull);
    expect(find.text('Always on while Geotagging is on'), findsOneWidget);
    await tester.tap(find.byKey(_syncSwitch));
    await tester.tap(find.text('Sync time'));
    expect(_calls, isEmpty);
  });

  testWidgets('the Sync time switch shows and changes the choice while live '
      'geotagging is off', (tester) async {
    await _pump(tester, live: false, syncTime: false);
    expect(tester.widget<Switch>(find.byKey(_syncSwitch)).value, isFalse);
    expect(
      find.text("Sets the camera's clock from this phone"),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_syncSwitch));
    expect(_calls, ['sync true']);

    await _pump(tester, live: false);
    expect(tester.widget<Switch>(find.byKey(_syncSwitch)).value, isTrue);
    await tester.tap(find.byKey(_syncSwitch));
    expect(_calls, ['sync false']);
  });

  testWidgets('the rows fit at the largest text size', (tester) async {
    for (final status in GeotagStatus.values) {
      await _pump(tester, live: true, status: status, textScale: 3);
      expect(tester.takeException(), isNull, reason: '$status');
    }
  });
}
