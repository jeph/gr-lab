import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/settings/settings_screen.dart';

import '../support/test_app.dart';

const _delete = Key('setting-location-history-delete');
const _serial = '1234567';

Future<void> _tap(WidgetTester tester, Key key) =>
    tapWhenReady(tester, find.byKey(key));

/// Waits for [future], which runs on files and so on real time, while
/// pumping.
Future<T> _pumped<T>(WidgetTester tester, Future<T> future) async {
  late T result;
  var done = false;
  unawaited(
    future.then((value) {
      result = value;
      done = true;
    }),
  );
  await pumpUntil(tester, () => done, reason: 'the location history');
  return result;
}

void main() {
  testWidgets('Delete location history, in Settings for every camera, asks '
      'first, then deletes what was recorded and leaves background '
      'geotagging on', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final location = FakePhoneLocation(access: FakePhoneLocation.always);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true),
        saveCamera: true,
        location: location,
        backgroundGeotagging: true,
      ),
    ))!;
    await app.pumpWithin(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.byKey(_delete), 200);
    expect(find.text('LOCATION'), findsOneWidget);

    final history = app.models.geotag.history;
    await _pumped(
      tester,
      history.add([
        LocationFix(
          latitude: 35,
          longitude: 139,
          accuracy: 20,
          time: clock.now().toUtc(),
        ),
      ]),
    );
    expect(await _pumped(tester, history.isEmpty), isFalse);

    await _tap(tester, _delete);
    await pumpUntilFound(tester, find.text('Delete location history?'));
    await tapWhenReady(tester, find.text('Cancel'));
    await pumpUntil(
      tester,
      () => find.text('Delete location history?').evaluate().isEmpty,
      reason: 'the question closed',
    );
    expect(await _pumped(tester, history.isEmpty), isFalse);

    await _tap(tester, _delete);
    await _tap(tester, const Key('location-history-delete-confirm'));
    await pumpUntilFound(tester, find.text('Location history deleted'));
    expect(await _pumped(tester, history.isEmpty), isTrue);
    final camera = app.models.cameras.cameras.singleWhere(
      (c) => c.serial == _serial,
    );
    expect(camera.backgroundGeotagging, isTrue);
    expect(location.historyEnabled, isTrue);

    await app.dispose();
  });
}
