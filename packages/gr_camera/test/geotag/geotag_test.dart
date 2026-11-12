import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show LocationMode, LocationStartFailure;

import '../shoot/rig.dart' show until;

const _waiting = LocationNotice(
  title: 'waiting',
  text: 'for the camera',
  stopLabel: 'Stop',
  channelName: 'Geotagging',
);
const _sending = LocationNotice(
  title: 'sending',
  text: 'to the camera',
  stopLabel: 'Stop',
  channelName: 'Geotagging',
);

/// A fix at made-up coordinates, [north] metres north of the first one and
/// [age] old.
PhoneFix _fix({
  double north = 0,
  double accuracy = 8,
  Duration age = Duration.zero,
}) => PhoneFix(
  latitude: 35 + north / 111320,
  longitude: 135,
  altitude: 40,
  accuracy: accuracy,
  time: DateTime.now().toUtc().subtract(age),
);

/// One simulated camera and phone, an environment over them and the trace
/// of everything the layer did.
final class _Rig {
  new({
    FakeCameraConfig config = const FakeCameraConfig(bonded: true),
    GeotagOptions options = const GeotagOptions(
      minimumGap: Duration(milliseconds: 50),
      clockClearDelay: Duration(milliseconds: 80),
    ),
    LocationAccess access = LocationAccess.precise,
  }) : camera = FakeGrCamera(config: config, media: syntheticMedia()),
       phone = FakePhoneLocation(access: access) {
    // flutter_test blocks real HTTP; the simulated camera serves it on
    // loopback.
    HttpOverrides.global = null;
    environment = GrCameraEnvironment(
      ble: camera.transport,
      wifi: camera.wifi,
      trace: trace.add,
      location: phone,
      httpFactory: camera.httpClient,
      geotagOptions: options,
    );
  }

  final FakeGrCamera camera;
  final FakePhoneLocation phone;
  final trace = <TraceEvent>[];
  late final GrCameraEnvironment environment;
  CameraSession? session;

  CameraGeotagging get geotagging => environment.geotagging;

  /// Decisions of [kind] on the session channel so far.
  List<Map<String, Object?>> events(String kind) => [
    for (final e in trace)
      if (e.channel == TraceChannel.session && e.kind == kind) e.fields,
  ];

  void configure({bool enabled = true}) => geotagging.configure(
    enabled: enabled,
    waitingNotice: _waiting,
    sendingNotice: _sending,
  );

  Future<CameraSession> connect() async {
    final opened = session = CameraSession(
      environment,
      consent: WifiConsent(
        ask: (_) async => true,
        askAgain: (_) async => false,
        cameraApproved: () => true,
        joined: () async {},
      ),
    );
    await opened.connectBluetooth(
      deviceId: camera.config.deviceId,
      serial: camera.config.serial,
    );
    return opened;
  }

  Future<void> status(GeotagStatus status) =>
      until(() => geotagging.status == status, reason: '$status');

  Future<void> close() async {
    await session?.close();
    await camera.close();
    phone.dispose();
  }
}

void main() {
  late _Rig rig;

  tearDown(() => rig.close());

  test('turned on, it turns Store Location Info on, locates the phone and '
      'sends the first fix', () async {
    rig = _Rig()..configure(enabled: false);
    await rig.connect();
    expect(rig.geotagging.status, GeotagStatus.off);
    expect(rig.phone.running, isFalse);

    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    expect(rig.camera.storeLocationInfo, isTrue);
    expect(rig.phone.mode, LocationMode.precise);
    expect(rig.phone.notice, _sending);

    rig.phone.emit(_fix());
    await rig.status(GeotagStatus.sending);
    final record = rig.camera.location!;
    expect(record.latitude, 35);
    expect(record.longitude, 135);
    expect(record.altitude, 40);
    expect(rig.geotagging.lastSentAt, isNotNull);
  });

  test('the fix time goes to the camera in UTC', () async {
    rig = _Rig()..configure();
    await rig.connect();
    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    final fix = _fix(age: const Duration(seconds: 3));

    rig.phone.emit(fix);
    await rig.status(GeotagStatus.sending);

    final record = rig.camera.location!;
    expect(
      DateTime.utc(
        record.year,
        record.month,
        record.day,
        record.hour,
        record.minute,
        record.second,
      ),
      DateTime.utc(
        fix.time.year,
        fix.time.month,
        fix.time.day,
        fix.time.hour,
        fix.time.minute,
        fix.time.second,
      ),
    );
  });

  test('a camera that is off is linked without the phone being located, '
      'and located once it is on', () async {
    rig = _Rig(
      config: const FakeCameraConfig(
        bonded: true,
        poweredOn: false,
        storeLocationInfo: true,
        wakeDelay: Duration(milliseconds: 50),
      ),
    )..configure();
    final session = await rig.connect();
    await rig.status(GeotagStatus.waitingForCamera);
    // The run is under way so that the camera coming on can start the
    // location with the app not in front; nothing is located yet.
    await until(() => rig.phone.running, reason: 'idle run');
    expect(rig.phone.mode, LocationMode.idle);
    expect(rig.phone.notice, _waiting);
    expect(rig.geotagging.keepsLooking, isTrue);
    rig.phone.emit(_fix());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rig.camera.acceptedLocations, isEmpty);

    await session.powerOn();
    await rig.status(GeotagStatus.waitingForLocation);
    expect(rig.phone.mode, LocationMode.precise);
    rig.phone.emit(_fix());
    await rig.status(GeotagStatus.sending);

    // Off again: the phone stops being located, the run stays.
    rig.camera.poweredOn = false;
    await rig.status(GeotagStatus.waitingForCamera);
    await until(() => rig.phone.mode == LocationMode.idle, reason: 'idle');
    expect(rig.phone.running, isTrue);
  });

  test('a fix that is old or inaccurate is not sent', () async {
    rig = _Rig()..configure();
    await rig.connect();
    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);

    rig.phone
      ..emit(_fix(age: const Duration(seconds: 61)))
      ..emit(_fix(accuracy: 101));
    await until(
      () => rig.events('geotag.skipped').length == 2,
      reason: 'both skipped',
    );
    expect(
      [for (final e in rig.events('geotag.skipped')) e['why']],
      ['old', 'inaccurate'],
    );
    expect(rig.camera.acceptedLocations, isEmpty);
    expect(rig.geotagging.status, GeotagStatus.waitingForLocation);
  });

  test('a phone that has not moved writes again only at the keep-alive, '
      'and one that moved writes at once', () async {
    rig = _Rig(
      options: const GeotagOptions(
        minimumGap: Duration(milliseconds: 50),
        keepAlive: Duration(milliseconds: 400),
      ),
    )..configure();
    await rig.connect();
    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    rig.phone.emit(_fix());
    await rig.status(GeotagStatus.sending);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    // 4 m is inside the fix's own 8 m accuracy: not a move.
    rig.phone.emit(_fix(north: 4));
    await until(
      () => rig.events('geotag.skipped').any((e) => e['why'] == 'notMoved'),
      reason: 'not moved',
    );
    expect(rig.camera.acceptedLocations, hasLength(1));

    rig.phone.emit(_fix(north: 30));
    await until(
      () => rig.camera.acceptedLocations.length == 2,
      reason: 'moved',
    );

    await Future<void>.delayed(const Duration(milliseconds: 450));
    rig.phone.emit(_fix(north: 30));
    await until(
      () => rig.camera.acceptedLocations.length == 3,
      reason: 'keep-alive',
    );
  });

  test('fixes closer together than the minimum gap are not all '
      'written', () async {
    rig = _Rig(options: const GeotagOptions(minimumGap: Duration(seconds: 30)))
      ..configure();
    await rig.connect();
    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    rig.phone.emit(_fix());
    await rig.status(GeotagStatus.sending);

    rig.phone.emit(_fix(north: 200));
    await until(
      () => rig.events('geotag.skipped').any((e) => e['why'] == 'tooSoon'),
      reason: 'too soon',
    );
    expect(rig.camera.acceptedLocations, hasLength(1));
  });

  test('at the keep-alive a coarser fix that agrees with the one sent '
      'keeps the better position, with the new time', () async {
    rig = _Rig(
      options: const GeotagOptions(
        minimumGap: Duration(milliseconds: 20),
        keepAlive: Duration(milliseconds: 100),
      ),
    )..configure();
    await rig.connect();
    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    rig.phone.emit(_fix());
    await rig.status(GeotagStatus.sending);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    rig.phone.emit(_fix(north: 20, accuracy: 60));
    await until(
      () => rig.camera.acceptedLocations.length == 2,
      reason: 'keep-alive',
    );
    expect(rig.camera.acceptedLocations.last.latitude, 35);
  });

  test('Store Location Info turned off on the camera stops the location '
      'until it is on again, and is not turned back on', () async {
    rig = _Rig()..configure();
    await rig.connect();
    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    rig.phone.emit(_fix());
    await rig.status(GeotagStatus.sending);

    rig.camera.storeLocationInfo = false;
    await rig.status(GeotagStatus.offOnCamera);
    await until(() => rig.phone.mode == LocationMode.idle, reason: 'idle');
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.geotagging.lastSentAt, isNull);

    rig.camera.storeLocationInfo = true;
    await rig.status(GeotagStatus.waitingForLocation);
    expect(rig.phone.mode, LocationMode.precise);
  });

  test('a camera found with Store Location Info off is left so, until the '
      'user turns geotagging on again', () async {
    rig = _Rig()..configure();
    await rig.connect();
    await rig.status(GeotagStatus.offOnCamera);
    expect(rig.camera.storeLocationInfo, isFalse);

    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    expect(rig.camera.storeLocationInfo, isTrue);
  });

  test('turned off, it turns Store Location Info off, which clears the '
      "camera's location, and ends the run", () async {
    rig = _Rig()..configure();
    await rig.connect();
    await rig.geotagging.setEnabled(enabled: true);
    await rig.status(GeotagStatus.waitingForLocation);
    rig.phone.emit(_fix());
    await rig.status(GeotagStatus.sending);

    await rig.geotagging.setEnabled(enabled: false);
    await rig.status(GeotagStatus.off);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.camera.location, isNull);
    await until(() => !rig.phone.running, reason: 'run ended');
    expect(rig.geotagging.keepsLooking, isFalse);
  });

  test('without precise location nothing runs, and a change of the '
      "phone's answer starts it", () async {
    rig = _Rig(
      config: const FakeCameraConfig(bonded: true, storeLocationInfo: true),
      access: LocationAccess.approximate,
    )..configure();
    await rig.connect();
    await rig.status(GeotagStatus.needsPreciseLocation);
    expect(rig.phone.running, isFalse);

    rig.phone.currentAccess = LocationAccess.precise;
    await rig.geotagging.appResumed();
    await rig.status(GeotagStatus.waitingForLocation);

    rig.phone.changeAccess(LocationAccess.off);
    await rig.status(GeotagStatus.locationOff);
    await until(() => !rig.phone.running, reason: 'run ended');
  });

  test('a run the system refuses in the background waits for the '
      'app', () async {
    rig = _Rig(
      config: const FakeCameraConfig(bonded: true, storeLocationInfo: true),
    )..configure();
    rig.phone.startFailure = LocationStartFailure.background;
    await rig.connect();
    await rig.status(GeotagStatus.needsApp);
    expect(rig.geotagging.keepsLooking, isFalse);

    rig.phone.startFailure = null;
    await rig.geotagging.appResumed();
    await rig.status(GeotagStatus.waitingForLocation);
  });

  test("the notification's Stop ends it until the app is opened", () async {
    rig = _Rig(
      config: const FakeCameraConfig(bonded: true, storeLocationInfo: true),
    )..configure();
    await rig.connect();
    await rig.status(GeotagStatus.waitingForLocation);

    rig.phone.tapStop();
    await rig.status(GeotagStatus.stopped);
    expect(rig.phone.running, isFalse);
    rig.phone.emit(_fix());
    expect(rig.camera.acceptedLocations, isEmpty);

    await rig.geotagging.appResumed();
    await rig.status(GeotagStatus.waitingForLocation);
    expect(rig.phone.running, isTrue);
  });

  test('the run outlives the session and ends when no camera was on for '
      'the idle limit', () async {
    rig = _Rig(
      config: const FakeCameraConfig(bonded: true, storeLocationInfo: true),
      options: const GeotagOptions(idleLimit: Duration(milliseconds: 300)),
    )..configure();
    final session = await rig.connect();
    await rig.status(GeotagStatus.waitingForLocation);

    await session.close();
    rig.session = null;
    await rig.status(GeotagStatus.waitingForCamera);
    expect(rig.phone.running, isTrue);
    expect(rig.phone.mode, LocationMode.idle);
    expect(rig.geotagging.keepsLooking, isTrue);

    await until(() => !rig.phone.running, reason: 'idle limit');
    expect(rig.geotagging.keepsLooking, isFalse);
    expect(rig.events('geotag.runEnded').last['reason'], 'idleLimit');
  });

  test('a phone that cannot be located runs nothing and leaves the '
      "camera's setting alone", () async {
    rig = _Rig(access: LocationAccess.unsupported)..configure();
    await rig.connect();
    await rig.status(GeotagStatus.unsupported);
    expect(rig.phone.running, isFalse);
    expect(rig.camera.storeLocationInfo, isFalse);
    expect(rig.geotagging.keepsLooking, isFalse);
  });

  group('clock', () {
    test('a camera whose clock is off is set, and the location is sent '
        'again after the write clears it', () async {
      rig = _Rig(
        config: const FakeCameraConfig(
          bonded: true,
          storeLocationInfo: true,
          clockOffset: Duration(minutes: 5),
          clockChangeClearsAfter: Duration(milliseconds: 30),
        ),
      )..configure();
      await rig.connect();
      await rig.status(GeotagStatus.waitingForLocation);
      rig.phone.emit(_fix());

      await until(() => rig.camera.clockWrites == 1, reason: 'clock set');
      expect(
        rig.camera.clock.difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 2)),
      );
      expect(rig.events('clock.compared').single['inStep'], isFalse);
      // The camera cleared its location; the next fix goes out though the
      // phone has not moved.
      await until(() => rig.camera.location == null, reason: 'cleared');
      await rig.status(GeotagStatus.waitingForLocation);
      rig.phone.emit(_fix());
      await until(() => rig.camera.location != null, reason: 'sent again');
    });

    test('a clock in step is not written', () async {
      rig = _Rig()..configure(enabled: false);
      final session = await rig.connect();
      session.clock.enabled = true;
      await until(
        () => rig.events('clock.compared').isNotEmpty,
        reason: 'compared',
      );
      expect(rig.events('clock.compared').single['inStep'], isTrue);
      // A write would follow as the next second begins.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(rig.camera.clockWrites, 0);
    });

    test('with the option off and geotagging off, the clock is left '
        'alone', () async {
      rig = _Rig(
        config: const FakeCameraConfig(
          bonded: true,
          clockOffset: Duration(minutes: 5),
        ),
      )..configure(enabled: false);
      final session = await rig.connect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(rig.events('clock.compared'), isEmpty);

      session.clock.enabled = true;
      await until(() => rig.camera.clockWrites == 1, reason: 'clock set');
    });

    test('a camera that stays linked is compared again', () async {
      rig = _Rig(
        options: const GeotagOptions(
          clockWatch: Duration(milliseconds: 40),
          clockRecheck: Duration(milliseconds: 120),
        ),
      )..configure(enabled: false);
      final session = await rig.connect();
      session.clock.enabled = true;
      await until(
        () => rig.events('clock.compared').length >= 2,
        reason: 'compared again',
      );
      expect(rig.events('clock.compared')[1]['reason'], 'recheck');
    });

    test('the clock of a camera that is off is not touched', () async {
      rig = _Rig(
        config: const FakeCameraConfig(
          bonded: true,
          poweredOn: false,
          clockOffset: Duration(minutes: 5),
        ),
      )..configure(enabled: false);
      final session = await rig.connect();
      session.clock.enabled = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(rig.events('clock.compared'), isEmpty);
      expect(rig.events('clock.failed'), isEmpty);
    });
  });
}
