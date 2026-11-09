import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

void main() {
  late FakeGrCamera camera;
  late CameraSession session;

  setUp(() async {
    HttpOverrides.global = null;
    camera = FakeGrCamera(
      config: const FakeCameraConfig(bonded: true, httpLatency: Duration.zero),
      media: syntheticMedia(),
    );
    await camera.startHttp();
    session = CameraSession(
      GrCameraEnvironment(
        ble: camera.transport,
        wifi: camera.wifi,
        trace: (_) {},
        httpFactory: camera.httpClient,
      ),
      consent: WifiConsent(
        ask: (_) async => true,
        askAgain: (_) async => true,
        cameraApproved: () => true,
        joined: () async {},
      ),
    );
  });

  tearDown(() async {
    await session.close();
    await camera.close();
  });

  test('the library is there while Wi-Fi is verified, one per join', () async {
    await session.connectBluetooth(
      deviceId: camera.config.deviceId,
      serial: camera.config.serial,
    );
    expect(session.library, isNull, reason: 'Bluetooth only');

    await session.startWifi();
    final first = session.library!;
    expect(first.serial, camera.config.serial);
    expect(first.storages, [GrStorageId.internal, GrStorageId.sd]);
    expect(identical(session.library, first), isTrue);
    final listing = await first.listFiles();
    expect(listing.files, hasLength(camera.photos.length));

    await session.stopWifi();
    expect(session.library, isNull);

    await session.startWifi();
    final second = session.library!;
    expect(identical(second, first), isFalse, reason: 'a new link');
    var changes = 0;
    final sub = second.listingChanges.listen((_) => changes++);
    addTearDown(sub.cancel);
    camera.addPhoto(
      FakePhoto('101RICOH', 'R0000100.JPG', DateTime(2026, 11, 8, 10)),
    );
    final watch = Stopwatch()..start();
    while (changes == 0 && watch.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(changes, 1);
    await expectLater(
      first.listingChanges,
      emitsDone,
      reason: "the first link's socket is gone",
    );
  });

  test('a Wi-Fi link the session recovers by itself gives a new library, '
      'and the old one never hears the new socket', () async {
    await session.connectBluetooth(
      deviceId: camera.config.deviceId,
      serial: camera.config.serial,
    );
    await session.startWifi();
    final first = session.library!;

    camera.dropWifi();
    await until(() => session.phase != GrSessionPhase.connected, 'loss');
    expect(session.library, isNull);
    await until(() => session.library != null, 'recovery');
    final second = session.library!;
    expect(identical(second, first), isFalse, reason: 'a new link');
    expect(identical(session.library, second), isTrue);

    await expectLater(
      first.listingChanges,
      emitsDone,
      reason: 'the old library must not subscribe to the new socket',
    );
    var changes = 0;
    final sub = second.listingChanges.listen((_) => changes++);
    addTearDown(sub.cancel);
    camera.addPhoto(
      FakePhoto('101RICOH', 'R0000101.JPG', DateTime(2026, 11, 8, 11)),
    );
    await until(() => changes > 0, 'storage change');
    expect(changes, 1);
  });
}

Future<void> until(bool Function() condition, String reason) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 15)) {
      fail('Timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
