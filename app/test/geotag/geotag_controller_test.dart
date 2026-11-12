import 'dart:async';
import 'dart:ui' show Locale;

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';

import '../support/test_app.dart';

// No widget is built in this file: the controller runs on its listeners
// and streams alone, as it does when Android starts the app with no
// screen.

const _serial = '1234567';
final String _deviceId = const FakeCameraConfig().deviceId;

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
  FakePowerOnWatch? watch,
  bool live = false,
}) async {
  final app = await createTestApp(
    config: config,
    saveCamera: true,
    location: location,
    powerOnWatch: watch,
    liveGeotagging: live,
  );
  addTearDown(app.dispose);
  // The notice is worded in the app's language, whatever the machine's.
  app.models.settings.language = const Locale('en');
  return app;
}

/// The paired camera as the file on disk has it.
Future<SavedCamera> _onDisk(TestApp app) async =>
    (await CameraStore.load(app.models.services.dataDir)).current!;

/// Pairs [_other] as well, with live geotagging on, and leaves [current]
/// the current camera.
Future<void> _addOther(TestApp app, {required String current}) async {
  final cameras = app.models.cameras;
  await cameras.add(
    SavedCamera(
      paired: _other,
      name: 'Street',
      pairedAt: DateTime(2026),
      liveGeotagging: true,
      geotagOffered: true,
    ),
  );
  await cameras.select(current);
  expect(cameras.current!.serial, current);
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
      expect(saved.geotagOffered, isTrue);
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
            "Sending this phone's location to the camera",
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

      await geotag.turnOnStoreLocationInfo();
      expect(app.camera.storeLocationInfo, isTrue);
      await _until(() => geotag.status == GeotagStatus.waitingForLocation);
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

    test("the camera's clock is put on the phone's time when it is linked, "
        'unless Sync camera clock is off', () async {
      const late = FakeCameraConfig(
        bonded: true,
        clockOffset: Duration(minutes: 5),
      );
      final synced = await _app(config: late);
      await synced.models.connection.connect();
      await _until(() => synced.camera.clockWrites.isNotEmpty);

      final left = await _app(config: late);
      await left.models.geotag.setSyncClock(_serial, on: false);
      expect((await _onDisk(left)).syncClock, isFalse);
      await left.models.connection.connect();
      await _settle();
      expect(left.camera.clockWrites, isEmpty);
    });
  });

  group('automatic start', () {
    test('the phone watches for the cameras with live geotagging on, and '
        'for none without', () async {
      final watch = FakePowerOnWatch();
      final app = await _app(watch: watch);
      final geotag = app.models.geotag;
      expect(geotag.autoStartSupported, isTrue);
      expect(watch.watched, isEmpty);

      expect(await geotag.turnLiveOn(_serial), isNull);
      await _until(() => watch.watched.isNotEmpty);
      expect(watch.watched.single.deviceId, _deviceId);
      expect(watch.watched.single.name, 'GR IV');

      await geotag.turnLiveOff(_serial);
      await _until(() => watch.watched.isEmpty);
    });

    test('setting it up asks for location at all times, then for the '
        "phone's link to the camera", () async {
      final location = FakePhoneLocation()
        ..alwaysAnswer = FakePhoneLocation.always;
      final watch = FakePowerOnWatch(needsAssociation: true);
      final app = await _app(location: location, watch: watch, live: true);
      final geotag = app.models.geotag;
      final camera = app.models.cameras.current!;
      expect(geotag.autoStartReady(camera), isFalse);
      expect(geotag.linkedToPhone(camera), isFalse);

      expect(await geotag.setUpAutoStart(_serial), isNull);
      expect(location.alwaysRequests, 1);
      expect(watch.associateRequests.single.deviceId, _deviceId);
      expect(watch.associateRequests.single.name, 'GR IV');
      expect(geotag.locationAlways, isTrue);
      expect(geotag.linkedToPhone(camera), isTrue);
      expect(geotag.autoStartReady(camera), isTrue);
    });

    test('location not allowed at all times: nothing is linked, and the '
        'result says so', () async {
      final location = FakePhoneLocation();
      final watch = FakePowerOnWatch(needsAssociation: true);
      final app = await _app(location: location, watch: watch, live: true);
      final geotag = app.models.geotag;

      expect(await geotag.setUpAutoStart(_serial), GeotagNeed.always);
      expect(location.alwaysRequests, 1);
      expect(watch.associateRequests, isEmpty);
      expect(geotag.autoStartReady(app.models.cameras.current!), isFalse);
    });

    test("the phone's link refused: the result says so", () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final watch = FakePowerOnWatch(needsAssociation: true)
        ..associateAnswer = false;
      final app = await _app(location: location, watch: watch, live: true);
      final geotag = app.models.geotag;

      expect(await geotag.setUpAutoStart(_serial), GeotagNeed.cameraLink);
      // Already allowed, so the phone is not asked again.
      expect(location.alwaysRequests, 0);
      expect(watch.associateRequests, hasLength(1));
      expect(geotag.autoStartReady(app.models.cameras.current!), isFalse);
    });

    test('a phone that cannot watch for cameras is not asked to', () async {
      final watch = FakePowerOnWatch(supported: false);
      final app = await _app(watch: watch, live: true);
      final geotag = app.models.geotag;
      expect(geotag.autoStartSupported, isFalse);
      expect(geotag.autoStartReady(app.models.cameras.current!), isFalse);
      expect(watch.watchCalls, isEmpty);
    });
  });

  group('a camera seen switched on', () {
    test('is connected when nothing is linked', () async {
      final watch = FakePowerOnWatch();
      final app = await _app(watch: watch, live: true);
      final connection = app.models.connection;
      expect(connection.status, ConnectionStatus.offline);
      expect(watch.watched.single.deviceId, _deviceId);

      watch.sight(_deviceId);
      await _until(() => connection.status == ConnectionStatus.bluetooth);
      expect(connection.bleLinked, isTrue);
      expect(connection.cameraOff, isFalse);
    });

    test('is left alone when its live geotagging is off', () async {
      final watch = FakePowerOnWatch()..launchSightings.add(_deviceId);
      final app = await _app(watch: watch);
      await _settle();
      expect(watch.launchSightings, isEmpty);
      expect(app.models.connection.status, ConnectionStatus.offline);
      expect(app.ble.connects, 0);
    });

    test('that started the app is connected at start-up', () async {
      final watch = FakePowerOnWatch()..launchSightings.add(_deviceId);
      final app = await _app(watch: watch, live: true);
      final connection = app.models.connection;
      await _until(() => connection.status == ConnectionStatus.bluetooth);
      expect(watch.launchSightings, isEmpty);
      expect(connection.camera!.serial, _serial);
    });

    test('becomes the current camera and is connected while the current '
        'one is not linked', () async {
      final watch = FakePowerOnWatch();
      final app = await _app(watch: watch, live: true);
      await _addOther(app, current: _other.serialNumber);
      await _until(() => watch.watched.length == 2);
      final connection = app.models.connection;

      watch.sight(_deviceId);
      await _until(() => connection.status == ConnectionStatus.bluetooth);
      expect(app.models.cameras.current!.serial, _serial);
      expect(app.ble.connected, everyElement(_deviceId));
    });

    test('is ignored while another camera is on and linked', () async {
      final watch = FakePowerOnWatch();
      final app = await _app(watch: watch, live: true);
      await _addOther(app, current: _serial);
      await _until(() => watch.watched.length == 2);
      final connection = app.models.connection;
      await connection.connect();
      expect(connection.bleLinked, isTrue);

      watch.sight(_other.deviceId);
      await _settle();
      expect(app.models.cameras.current!.serial, _serial);
      expect(connection.status, ConnectionStatus.bluetooth);
      expect(connection.bleLinked, isTrue);
      expect(app.ble.connected, everyElement(_deviceId));
    });

    test('that the session had let go of while it was off is linked at '
        'once, and the phone was told to watch for it afresh', () async {
      final watch = FakePowerOnWatch();
      final app = await _app(
        config: const FakeCameraConfig(bonded: true, poweredOn: false),
        watch: watch,
        live: true,
      );
      final connection = app.models.connection;
      await connection.connect();
      expect(connection.cameraOff, isTrue);
      final watches = watch.watchCalls.length;

      // An off camera drops its link after a while; the session then only
      // reads its advertisements.
      app.camera.dropBluetooth();
      await _until(() => connection.parked);
      expect(app.models.geotag.status, GeotagStatus.waitingForCamera);
      await _until(() => watch.watchCalls.length > watches);
      expect(watch.watched.single.deviceId, _deviceId);

      // The camera still advertises that it is off, so only the phone's
      // sighting can have linked it.
      final connects = app.ble.connects;
      watch.sight(_deviceId);
      await _until(() => connection.bleLinked);
      expect(connection.parked, isFalse);
      expect(app.ble.connects, connects + 1);
    });

    test('is watched for afresh after it was on and linked and then went '
        'off', () async {
      final watch = FakePowerOnWatch();
      final app = await _app(config: _storing, watch: watch, live: true);
      final connection = app.models.connection;
      await connection.connect();
      expect(connection.cameraOff, isFalse);
      final watches = watch.watchCalls.length;

      app.camera.poweredOn = false;
      await _until(() => watch.watchCalls.length > watches);
      expect(watch.watched.single.deviceId, _deviceId);
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
      final settings = app.models.settings;
      expect(settings.backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);

      expect(await geotag.turnBackgroundOn(), isNull);
      expect(location.whileInUseRequests, 1);
      expect(location.alwaysRequests, 1);
      expect(settings.backgroundGeotagging, isTrue);
      expect(location.historyEnabled, isTrue);
      expect(geotag.backgroundPausedBy, isNull);

      await geotag.turnBackgroundOff();
      expect(settings.backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);
    });

    test('refused while in use: location at all times is not asked '
        'for', () async {
      final location = FakePhoneLocation(access: _denied);
      final app = await _app(location: location);
      final geotag = app.models.geotag;

      expect(await geotag.turnBackgroundOn(), GeotagNeed.permission);
      expect(location.whileInUseRequests, 1);
      expect(location.alwaysRequests, 0);
      expect(app.models.settings.backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);
    });

    test('allowed only while in use: it stays off', () async {
      final location = FakePhoneLocation();
      final app = await _app(location: location);

      expect(await app.models.geotag.turnBackgroundOn(), GeotagNeed.always);
      expect(location.alwaysRequests, 1);
      expect(app.models.settings.backgroundGeotagging, isFalse);
      expect(location.historyEnabled, isFalse);
    });

    test('a permission reduced later leaves it on and paused, and it '
        'resumes by itself when the permission is back', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      final settings = app.models.settings;
      expect(await geotag.turnBackgroundOn(), isNull);
      expect(location.alwaysRequests, 0);

      for (final (access, need) in [
        (FakePhoneLocation.whileInUse, GeotagNeed.always),
        (_denied, GeotagNeed.permission),
        (_phoneOff, GeotagNeed.phoneLocation),
      ]) {
        location.setAccess(access);
        await _until(() => geotag.backgroundPausedBy == need);
        expect(settings.backgroundGeotagging, isTrue);
      }

      location.setAccess(FakePhoneLocation.always);
      await _until(() => geotag.backgroundPausedBy == null);
      expect(settings.backgroundGeotagging, isTrue);
      expect(location.historyEnabled, isTrue);
      // What the phone recorded is taken over again.
      location.recordHistory(_fix());
      await _until(() => location.pendingHistory.isEmpty);
      await _until(() async => !await geotag.history.isEmpty);
    });

    test('at start-up the phone is told to record when the setting is on, '
        'whatever it did before', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(location: location);
      final models = app.models;
      // As after a restore that brought back the settings file alone.
      models.settings.backgroundGeotagging = true;
      expect(location.historyEnabled, isFalse);

      final started = await GeotagController.open(
        services: models.services,
        connection: models.connection,
        cameras: models.cameras,
        settings: models.settings,
      );
      addTearDown(started.dispose);
      await started.start();
      expect(location.historyEnabled, isTrue);
      expect(started.backgroundPausedBy, isNull);
    });

    test("the phone's own recording is moved into the history, and Delete "
        'empties both', () async {
      final location = FakePhoneLocation(access: FakePhoneLocation.always);
      final app = await _app(location: location);
      final geotag = app.models.geotag;
      expect(await geotag.turnBackgroundOn(), isNull);
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
      expect(app.models.settings.backgroundGeotagging, isTrue);
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

      expect(await geotag.turnBackgroundOn(), isNull);
      await _until(() async {
        location.emitFix(_fix(latitude: 35.5, longitude: 139.5));
        return !await geotag.history.isEmpty;
      });
      final nearest = await geotag.history.nearest(clock.now());
      expect(nearest!.latitude, closeTo(35.5, 1e-3));
      expect(nearest.longitude, closeTo(139.5, 1e-3));

      await geotag.turnBackgroundOff();
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
      expect(await geotag.turnBackgroundOn(), isNull);

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
