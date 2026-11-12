import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/library/library_screen.dart';

import 'support/test_app.dart';

void main() {
  testWidgets("when the app's window goes while live geotagging keeps the "
      "app running, the camera's pages close and its Wi-Fi is left; "
      'Bluetooth and geotagging carry on', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final location = FakePhoneLocation();
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true, storeLocationInfo: true),
        saveCamera: true,
        location: location,
        liveGeotagging: true,
      ),
    ))!;
    await app.pumpApp(tester);
    final connection = app.models.connection;

    await tapWhenReady(tester, find.byKey(const Key('camera-card-library')));
    await pumpUntilFound(tester, find.byType(LibraryScreen));
    await pumpUntil(
      tester,
      () => connection.status == ConnectionStatus.connected,
      reason: 'Wi-Fi joined',
    );
    await pumpUntil(tester, () => location.runHeld, reason: 'the run');

    // Android: the activity is destroyed, the engine lives on.
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await pumpUntil(
      tester,
      () => connection.status == ConnectionStatus.bluetooth,
      reason: 'the Wi-Fi left',
    );
    expect(connection.tab, isNull);
    expect(connection.foreground, isFalse);
    expect(connection.bleLinked, isTrue);
    expect(location.runHeld, isTrue);
    expect(app.models.geotag.status, GeotagStatus.waitingForLocation);

    // Opened again: the Cameras screen, as that left it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpUntil(
      tester,
      () => find.byType(LibraryScreen).evaluate().isEmpty,
      reason: 'the Library closed',
    );
    expect(find.byKey(const Key('cameras')), findsOneWidget);
    expect(connection.foreground, isTrue);
    expect(connection.status, ConnectionStatus.bluetooth);

    await app.dispose();
  });
}
