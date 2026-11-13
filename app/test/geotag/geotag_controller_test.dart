import 'dart:async';
import 'dart:ui' show Locale;

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';

import '../support/test_app.dart';

// No widget is built in this file: the controller runs on its listeners
// and streams alone, as it does while live geotagging carries on with the
// app not on screen.

const _serial = '1234567';

/// A camera that accepts this phone, with Store Location Info off as a
/// camera ships.
const _bonded = FakeCameraConfig(bonded: true);

/// The same with Store Location Info on already.
const _storing = FakeCameraConfig(bonded: true, storeLocationInfo: true);

/// Location on for the phone, and GR Photo not allowed to use it.
const _denied = LocationAccess(
  permission: LocationPermission.denied,
  precise: false,
  serviceOn: true,
);

/// Allowed while in use, but only approximately.
const _approximate = LocationAccess(
  permission: LocationPermission.whileInUse,
  precise: false,
  serviceOn: true,
);

/// Allowed, with location off for the whole phone.
const _phoneOff = LocationAccess(
  permission: LocationPermission.whileInUse,
  precise: true,
  serviceOn: false,
);

/// The GR IV paired second, which is not around.
const _other = GrPairedCamera(
  deviceId: '00:00:5E:00:53:01',
  serialNumber: '1111111',
  modelName: 'RICOH GR IV',
  firmwareRevision: '1.20',
);

/// A made-up position the phone takes now.
LocationFix _fix({
  double latitude = 35,
  double longitude = 139,
  DateTime? time,
}) => LocationFix(
  latitude: latitude,
  longitude: longitude,
  accuracy: 8,
  time: time ?? clock.now().toUtc(),
);

Future<TestApp> _app({
  FakeCameraConfig config = _bonded,
  FakePhoneLocation? location,
  bool live = false,
  bool background = false,
}) async {
  final app = await createTestApp(
    config: config,
    saveCamera: true,
    location: location,
    liveGeotagging: live,
    backgroundGeotagging: background,
  );
  addTearDown(app.dispose);
  // The notice is worded in the app's language, whatever the machine's.
  app.models.settings.language = const Locale('en');
  return app;
}

/// The paired camera as the file on disk has it.
Future<SavedCamera> _onDisk(TestApp app) async =>
    (await CameraStore.load(app.models.services.dataDir)).current!;

/// The saved camera with [serial].
SavedCamera _saved(TestApp app, [String serial = _serial]) =>
    app.models.cameras.cameras.singleWhere((c) => c.serial == serial);

/// Pairs [_other] as well and leaves the first camera the current one.
Future<void> _addOther(TestApp app) async {
  final cameras = app.models.cameras;
  await cameras.add(
    SavedCamera(paired: _other, name: 'Street', pairedAt: DateTime(2026)),
  );
  await cameras.select(_serial);
  expect(cameras.current!.serial, _serial);
}

Future<void> _until(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > timeout) fail('timed out after $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Lets what a change set off run, where nothing is expected to happen.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  test('with both kinds off, as for a camera just paired, the phone is '
      'asked nothing and located by nothing, also once the camera is '
      'linked', () async {
    final location = FakePhoneLocation(access: _denied);
    final app = await _app(location: location);
    expect(_saved(app).liveGeotagging, isFalse);
    expect(_saved(app).backgroundGeotagging, isFalse);

    await app.models.connection.connect();
    await _settle();
    expect(location.whileInUseRequests, 0);
    expect(location.alwaysRequests, 0);
    expect(location.locating, isFalse);
    expect(location.currentRequests, 0);
    expect(location.runHolds, isEmpty);
    expect(location.historyEnabled, isFalse);
    expect(app.models.geotag.status, GeotagStatus.off);
    expect(app.camera.storeLocationInfo, isFalse);
  });

  group('live geotagging', () {
    test('turning it on asks for the location while in use, and with it '
        'allowed saves the choice with the Store Location Info the camera '
        'is owed', () async {
      final location = FakePhoneLocation(access: _denied)
        ..whileInUseAnswer = FakePhoneLocation.whileInUse;
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      expect(geotag.access, _denied);
      expect(geotag.status, GeotagStatus.off);
      var notified = 0;
      geotag.addListener(() => notified++);

      expect(await geotag.turnLiveOn(_serial), isNull);
      expect(location.whileInUseRequests, 1);
      expect(location.alwaysRequests, 0);
      expect(geotag.access, FakePhoneLocation.whileInUse);
      expect(notified, greaterThan(0));
      final saved = await _onDisk(app);
      expect(saved.liveGeotagging, isTrue);
      expect(saved.backgroundGeotagging, isFalse);
      expect(saved.storeLocationInfoPending, isTrue);
      // Nothing is linked: it starts when the camera is.
      expect(geotag.status, GeotagStatus.waitingForCamera);
    });

    for (final (answer, need, page) in [
      (_denied, GeotagNeed.permission, LocationSettingsPage.app),
      (_approximate, GeotagNeed.precise, LocationSettingsPage.app),
      (_phoneOff, GeotagNeed.phoneLocation, LocationSettingsPage.phone),
    ]) {
      test('refused (${need.name}): it stays off, the result says what '
          'is missing and its settings page opens', () async {
        final location = FakePhoneLocation(access: _denied)
          ..whileInUseAnswer = answer;
        final app = await _app(location: location);
        final geotag = app.models.geotag;

        expect(await geotag.turnLiveOn(_serial), need);
        expect(location.whileInUseRequests, 1);
        final saved = await _onDisk(app);
        expect(saved.liveGeotagging, isFalse);
        expect(saved.storeLocationInfoPending, isNull);
        expect(geotag.status, GeotagStatus.off);

        await geotag.openSettings(need);
        expect(location.settingsOpened, [page]);
      });
    }

    test("the camera's Store Location Info is turned on when the camera is "
        'next linked, and what was owed is forgotten once it is written; '
        'turning live off turns it off again, which clears the '
        'location', () async {
      final location = FakePhoneLocation();
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      final cameras = app.models.cameras;

      expect(await geotag.turnLiveOn(_serial), isNull);
      expect(app.camera.storeLocationInfo, isFalse);
      expect((await _onDisk(app)).storeLocationInfoPending, isTrue);

      await app.models.connection.connect();
      await _until(() => app.camera.storeLocationInfo);
      await _until(
        () async => (await _onDisk(app)).storeLocationInfoPending == null,
      );
      expect(cameras.current!.liveGeotagging, isTrue);

      await _until(() => location.locating);
      await _until(() {
        location.emitFix(_fix());
        return app.camera.location != null;
      });
      expect(app.camera.location!.latitude, closeTo(35, 1e-4));
      expect(app.camera.location!.longitude, closeTo(139, 1e-4));
      await _until(() => geotag.status == GeotagStatus.sending);
      // What the phone shows while it runs off screen, in the app's
      // language and with the camera's name.
      await _until(
        () =>
            location.runNotice?.text ==
            "Geotagging using this phone's location",
      );
      expect(location.runNotice!.title, 'Geotagging: GR IV');
      expect(location.runNotice!.stopLabel, 'Stop');
      expect(location.runNotice!.channel, 'Geotagging');

      await geotag.turnLiveOff(_serial);
      expect(cameras.current!.liveGeotagging, isFalse);
      await _until(() => !app.camera.storeLocationInfo);
      await _until(
        () async => (await _onDisk(app)).storeLocationInfoPending == null,
      );
      expect(app.camera.location, isNull);
      await _until(() => !location.runHeld);
      expect(geotag.status, GeotagStatus.off);
    });

    test('a camera whose Store Location Info was turned off in its menu is '
        'not turned on again until the user asks', () async {
      final location = FakePhoneLocation();
      final app = await _app(location: location, live: true);
      final geotag = app.models.geotag;

      await app.models.connection.connect();
      await _until(() => geotag.status == GeotagStatus.offOnCamera);
      await _settle();
      expect(app.camera.storeLocationInfo, isFalse);
      expect(
        location.runNotice!.text,
        'Please enable Store Location Info on the camera to enable '
        'geotagging',
      );

      await geotag.turnOnStoreLocationInfo();
      expect(app.camera.storeLocationInfo, isTrue);
      await _until(() => geotag.status == GeotagStatus.waitingForLocation);
      // Waiting for the phone's position reads as running.
      await _until(
        () =>
            location.runNotice?.text ==
            "Geotagging using this phone's location",
      );
    });

    test('without a session the status says what the phone lacks, and '
        'follows the access as it changes', () async {
      final location = FakePhoneLocation();
      final app = await _app(location: location, live: true);
      final geotag = app.models.geotag;
      expect(geotag.status, GeotagStatus.waitingForCamera);

      for (final (access, status) in [
        (_denied, GeotagStatus.permissionDenied),
        (_approximate, GeotagStatus.preciseNeeded),
        (_phoneOff, GeotagStatus.locationOff),
        (FakePhoneLocation.whileInUse, GeotagStatus.waitingForCamera),
      ]) {
        location.setAccess(access);
        await _until(() => geotag.status == status);
      }
    });

    test('it starts again by itself when a camera that went off, and that '
        'the session let go of, says it is on', () async {
      final location = FakePhoneLocation();
      final app = await _app(config: _storing, location: location, live: true);
      final geotag = app.models.geotag;
      final connection = app.models.connection;
      await connection.connect();
      await _until(() => location.locating);

      // Switched off, the camera drops its link; the session links it once
      // more, in its off state.
      app.camera.poweredOn = false;
      await _until(() => connection.cameraOff && connection.bleLinked);
      // An off camera drops that link after a while; the session then only
      // reads its advertisements.
      app.camera.dropBluetooth();
      await _until(() => connection.parked);
      expect(geotag.status, GeotagStatus.waitingForCamera);
      // Still located, for a camera switched on again soon.
      expect(location.locating, isTrue);

      app.camera.poweredOn = true;
      await _until(() => connection.bleLinked && !connection.cameraOff);
      await _until(() => location.locating);
      final before = app.camera.location;
      await _until(() {
        location.emitFix(_fix(latitude: 36));
        return app.camera.location != before && app.camera.location != null;
      });
      expect(app.camera.location!.latitude, closeTo(36, 1e-4));
    });
  });

  group("the camera's clock", () {
    const late = FakeCameraConfig(
      bonded: true,
      clockOffset: Duration(minutes: 5),
    );

    test("is put on the phone's time when the camera is linked, by "
        'default and without live geotagging', () async {
      final app = await _app(config: late);
      expect(_saved(app).liveGeotagging, isFalse);
      await app.models.connection.connect();
      await _until(() => app.camera.clockWrites.isNotEmpty);
    });

    test('is left alone with Sync camera clock off, also while live '
        'geotagging is on', () async {
      final location = FakePhoneLocation();
      final app = await _app(
        config: const FakeCameraConfig(
          bonded: true,
          storeLocationInfo: true,
          clockOffset: Duration(minutes: 5),
        ),
        location: location,
        live: true,
      );
      await app.models.geotag.setSyncClock(_serial, on: false);
      expect((await _onDisk(app)).syncClock, isFalse);

      await app.models.connection.connect();
      await _until(() => location.locating);
      await _until(() {
        location.emitFix(_fix());
        return app.camera.location != null;
      });
      await _settle();
      expect(app.camera.clockWrites, isEmpty);
    });

    test('is kept in sync while background geotagging is on for the '
        'camera, whatever Sync camera clock says, and left alone again '
        'once that is off', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(config: late, location: location);
      final geotag = app.models.geotag;
      await geotag.setSyncClock(_serial, on: false);
      await app.models.connection.connect();
      await _settle();
      expect(app.camera.clockWrites, isEmpty);

      expect(await geotag.turnBackgroundOn(_serial), isNull);
      expect(_saved(app).syncClock, isFalse);
      expect(_saved(app).keepsClock, isTrue);
      await _until(() => app.camera.clockWrites.isNotEmpty);

      await geotag.turnBackgroundOff(_serial);
      expect(_saved(app).keepsClock, isFalse);
      final writes = app.camera.clockWrites.length;
      app.camera.clockOffset = const Duration(minutes: 5);
      await _settle();
      expect(app.camera.clockWrites, hasLength(writes));
    });
  });

  group('background geotagging', () {
    test('turning it on asks for location while in use, then at all times, '
        'and only that turns it on', () async {
      final location = FakePhoneLocation(access: _denied)
        ..whileInUseAnswer = FakePhoneLocation.whileInUse
        ..alwaysAnswer = FakePhoneLocation.always;
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      expect(_saved(app).backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);

      expect(await geotag.turnBackgroundOn(_serial), isNull);
      expect(location.whileInUseRequests, 1);
      expect(location.alwaysRequests, 1);
      expect((await _onDisk(app)).backgroundGeotagging, isTrue);
      // Live geotagging is another switch.
      expect(_saved(app).liveGeotagging, isFalse);
      expect(_saved(app).storeLocationInfoPending, isNull);
      expect(location.historyEnabled, isTrue);
      expect(geotag.backgroundPausedBy(_saved(app)), isNull);

      await geotag.turnBackgroundOff(_serial);
      expect((await _onDisk(app)).backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);
    });

    test('refused while in use: location at all times is not asked '
        'for', () async {
      final location = FakePhoneLocation(access: _denied);
      final app = await _app(location: location);
      final geotag = app.models.geotag;

      expect(await geotag.turnBackgroundOn(_serial), GeotagNeed.permission);
      expect(location.whileInUseRequests, 1);
      expect(location.alwaysRequests, 0);
      expect(_saved(app).backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);
    });

    test('allowed only while in use: it stays off', () async {
      final location = FakePhoneLocation();
      final app = await _app(location: location);

      expect(
        await app.models.geotag.turnBackgroundOn(_serial),
        GeotagNeed.always,
      );
      expect(location.alwaysRequests, 1);
      expect(_saved(app).backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);
    });

    test('a permission reduced later leaves it on and paused, and it '
        'resumes by itself when the permission is back', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      expect(await geotag.turnBackgroundOn(_serial), isNull);
      expect(location.alwaysRequests, 0);

      for (final (access, need) in [
        (FakePhoneLocation.whileInUse, GeotagNeed.always),
        (_denied, GeotagNeed.permission),
        (_phoneOff, GeotagNeed.phoneLocation),
      ]) {
        location.setAccess(access);
        await _until(() => geotag.backgroundPausedBy(_saved(app)) == need);
        expect(_saved(app).backgroundGeotagging, isTrue);
      }

      location.setAccess(FakePhoneLocation.always);
      await _until(() => geotag.backgroundPausedBy(_saved(app)) == null);
      expect(_saved(app).backgroundGeotagging, isTrue);
      expect(location.historyEnabled, isTrue);
      // What the phone recorded is taken over again.
      location.recordHistory(_fix());
      await _until(() => location.pendingHistory.isEmpty);
      await _until(() async => !await geotag.history.isEmpty);
    });

    test('at start-up the phone is told to record when a camera has it on '
        'and to stop when none has, whatever it did before', () async {
      // As after a restore that brought back the cameras file alone.
      final silent = FakePhoneLocation(access: FakePhoneLocation.always);
      expect(silent.historyEnabled, isFalse);
      final on = await _app(location: silent, background: true);
      expect(silent.historyEnabled, isTrue);
      expect(on.models.geotag.backgroundPausedBy(_saved(on)), isNull);

      // And the other way round: the phone still records, for no camera.
      final recording = FakePhoneLocation(access: FakePhoneLocation.always);
      await recording.setHistory(enabled: true);
      await _app(location: recording);
      expect(recording.historyEnabled, isFalse);
    });

    test('the phone records while any camera has it on, and only the '
        'photos of a camera that has it on get a location', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      await _addOther(app);
      const other = '1111111';

      expect(await geotag.turnBackgroundOn(other), isNull);
      expect(location.historyEnabled, isTrue);
      expect(_saved(app, other).backgroundGeotagging, isTrue);
      expect(_saved(app).backgroundGeotagging, isFalse);
      expect(geotag.geotagger.enabled(other), isTrue);
      expect(geotag.geotagger.enabled(_serial), isFalse);
      // Not a paired camera at all.
      expect(geotag.geotagger.enabled('2222222'), isFalse);
      // Paused is said of the camera that has it on only.
      location.setAccess(FakePhoneLocation.whileInUse);
      await _until(() => geotag.backgroundPausedBy(_saved(app, other)) != null);
      expect(geotag.backgroundPausedBy(_saved(app)), isNull);
      location.setAccess(FakePhoneLocation.always);
      await _until(() => geotag.backgroundPausedBy(_saved(app, other)) == null);

      expect(await geotag.turnBackgroundOn(_serial), isNull);
      await geotag.turnBackgroundOff(other);
      // The first camera still has it on.
      expect(location.historyEnabled, isTrue);
      expect(geotag.geotagger.enabled(other), isFalse);
      await geotag.turnBackgroundOff(_serial);
      expect(location.historyEnabled, isFalse);
    });

    test('forgetting the only camera that has it on stops the '
        'recording', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      await _addOther(app);
      expect(await geotag.turnBackgroundOn('1111111'), isNull);
      expect(location.historyEnabled, isTrue);

      await app.models.cameras.remove('1111111');
      await _until(() => !location.historyEnabled);
    });

    test("the phone's own recording is moved into the history, and Delete "
        'empties both', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      expect(await geotag.turnBackgroundOn(_serial), isNull);
      expect(await geotag.history.isEmpty, isTrue);

      location.recordHistory(_fix(latitude: 35.5, longitude: 139.5));
      await _until(() => location.pendingHistory.isEmpty);
      await _until(() async => !await geotag.history.isEmpty);
      final nearest = await geotag.history.nearest(clock.now());
      expect(nearest!.latitude, closeTo(35.5, 1e-3));
      expect(nearest.longitude, closeTo(139.5, 1e-3));

      expect(await geotag.deleteHistory(), isTrue);
      expect(await geotag.history.isEmpty, isTrue);
      expect(location.pendingHistory, isEmpty);
      // Deleting does not turn it off.
      expect(_saved(app).backgroundGeotagging, isTrue);
      expect(location.historyEnabled, isTrue);
    });

    test('the positions live geotagging takes are kept in the history only '
        'while background geotagging is on', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(config: _storing, location: location, live: true);
      final geotag = app.models.geotag;
      await app.models.connection.connect();
      await _until(() => location.locating);

      await _until(() {
        location.emitFix(_fix());
        return app.camera.location != null;
      });
      await _settle();
      expect(await geotag.history.isEmpty, isTrue);

      expect(await geotag.turnBackgroundOn(_serial), isNull);
      await _until(() async {
        location.emitFix(_fix(latitude: 35.5, longitude: 139.5));
        return !await geotag.history.isEmpty;
      });
      final nearest = await geotag.history.nearest(clock.now());
      expect(nearest!.latitude, closeTo(35.5, 1e-3));
      expect(nearest.longitude, closeTo(139.5, 1e-3));

      await geotag.turnBackgroundOff(_serial);
      expect(await geotag.deleteHistory(), isTrue);
      location.emitFix(_fix(latitude: 36, longitude: 140));
      await _settle();
      expect(await geotag.history.isEmpty, isTrue);
    });

    test('of the positions live geotagging takes, the history keeps one '
        'every 15 seconds', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(config: _storing, location: location, live: true);
      final geotag = app.models.geotag;
      await app.models.connection.connect();
      await _until(() => location.locating);
      expect(await geotag.turnBackgroundOn(_serial), isNull);

      final start = clock.now().toUtc().subtract(const Duration(seconds: 40));
      DateTime at(int seconds) => start.add(Duration(seconds: seconds));
      location
        ..emitFix(_fix(latitude: 35.5, time: at(0)))
        ..emitFix(_fix(latitude: 36, time: at(5)))
        ..emitFix(_fix(latitude: 36.5, time: at(14)))
        ..emitFix(_fix(latitude: 37, time: at(20)));
      await _until(
        () async => (await geotag.history.nearest(at(20)))?.latitude == 37,
      );
      // The ones 5 and 14 seconds after the first were not kept.
      expect((await geotag.history.nearest(at(5)))!.latitude, 35.5);
      expect((await geotag.history.nearest(at(12)))!.latitude, 37);
    });
  });
}
