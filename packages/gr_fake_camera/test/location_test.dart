import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

/// Long enough for one GATT exchange with the simulated camera.
const _exchange = Duration(milliseconds: 50);

/// Runs [future] to its end in fake time and returns its value.
T _done<T>(FakeAsync async, Future<T> future) {
  T? value;
  Object? error;
  unawaited(
    future.then<void>(
      (v) {
        value = v;
      },
      onError: (Object e) {
        error = e;
      },
    ),
  );
  async.elapse(_exchange);
  expect(error, isNull);
  return value as T;
}

/// Runs [exchange] to its end in fake time and returns the error it failed
/// with; null when it did not fail.
Object? _failure(FakeAsync async, Future<void> Function() exchange) {
  Object? error;
  unawaited(
    Future.sync(exchange).then<void>(
      (_) {},
      onError: (Object e) {
        error = e;
      },
    ),
  );
  async.elapse(_exchange);
  return error;
}

/// A made-up position; [time] is its fix time.
BleGpsInformation _position({
  double latitude = 35,
  double longitude = 139,
  double altitude = 40,
  DateTime? time,
}) => BleGpsInformation.at(
  latitude: latitude,
  longitude: longitude,
  altitude: altitude,
  time: time ?? DateTime.utc(2026, 11, 12, 1, 2, 3),
);

final Matcher _refused = isA<BleException>().having(
  (e) => e.code,
  'code',
  BleErrorCode.gatt,
);

/// The simulated camera's location and clock rules, as the firmware has
/// them (research/protocol/geotagging.md §1), in fake time.
void main() {
  /// Runs [body] in fake time with a camera set up by [config] and a
  /// client linked to it.
  void withCamera(
    FakeCameraConfig config,
    void Function(FakeAsync async, FakeGrCamera camera, GrBleClient ble) body,
  ) {
    fakeAsync((async) {
      final camera = FakeGrCamera(config: config, media: syntheticMedia());
      final link = _done(
        async,
        camera.transport.connect(
          config.deviceId,
          timeout: const Duration(seconds: 5),
        ),
      );
      final ble = GrBleClient(link);
      _done(async, ble.discover());
      body(async, camera, ble);
      unawaited(camera.close());
      async.flushMicrotasks();
    }, initialTime: DateTime(2026, 11, 12, 10));
  }

  const on = FakeCameraConfig(
    bonded: true,
    connectDelay: Duration.zero,
    storeLocationInfo: true,
  );

  test('Store Location Info is off as the camera ships, and a position is '
      'refused until it is on', () {
    withCamera(
      const FakeCameraConfig(bonded: true, connectDelay: Duration.zero),
      (async, camera, ble) {
        expect(camera.storeLocationInfo, isFalse);
        expect(_done(async, ble.read(GrBleCatalog.geoTag)).value, isFalse);
        expect(_failure(async, () => ble.sendGps(_position())), _refused);
        expect(camera.location, isNull);
        expect(camera.locationWrites, isEmpty);
        expect(camera.refusedLocationWrites, 1);

        _done(async, ble.setGeoTag(enabled: true));
        expect(camera.storeLocationInfo, isTrue);
        expect(_done(async, ble.read(GrBleCatalog.geoTag)).value, isTrue);
        expect(_failure(async, () => ble.sendGps(_position())), isNull);
        expect(camera.refusedLocationWrites, 1);
        final held = camera.location!;
        expect(
          (held.latitude, held.longitude, held.altitude),
          (35.0, 139.0, 40.0),
        );
        expect(held.fixTime, DateTime.utc(2026, 11, 12, 1, 2, 3));
        expect(camera.locationWrites, [held]);
      },
    );
  });

  test('a camera that is off refuses a position', () {
    withCamera(
      const FakeCameraConfig(
        bonded: true,
        poweredOn: false,
        connectDelay: Duration.zero,
        storeLocationInfo: true,
      ),
      (async, camera, ble) {
        expect(_failure(async, () => ble.sendGps(_position())), _refused);
        expect(camera.location, isNull);
        expect(camera.refusedLocationWrites, 1);
      },
    );
  });

  test('a camera that takes no position now refuses it', () {
    withCamera(on, (async, camera, ble) {
      camera.locationLocked = true;
      expect(_failure(async, () => ble.sendGps(_position())), _refused);
      expect(camera.location, isNull);
      camera.locationLocked = false;
      expect(_failure(async, () => ble.sendGps(_position())), isNull);
      expect(camera.location, isNotNull);
    });
  });

  test('a position is range-checked: latitude, longitude, altitude and a '
      'real calendar date', () {
    withCamera(on, (async, camera, ble) {
      // The codec refuses most of these itself, so they are sent raw.
      Object? raw(void Function(Uint8List bytes, ByteData data) change) {
        final bytes = GrBleCatalog.gpsInformation.codec.encode(_position());
        change(bytes, ByteData.sublistView(bytes));
        return _failure(
          async,
          () => ble.writeRaw(GrBleCatalog.gpsInformation, bytes),
        );
      }

      expect(raw((_, d) => d.setFloat64(0, 90.5)), _refused);
      expect(raw((_, d) => d.setFloat64(0, -90.5)), _refused);
      expect(raw((_, d) => d.setFloat64(8, 180.5)), _refused);
      expect(raw((_, d) => d.setFloat64(8, -180.5)), _refused);
      expect(raw((_, d) => d.setFloat64(16, 10000)), _refused);
      expect(raw((_, d) => d.setFloat64(16, -10000)), _refused);
      // 30 February, month 13, 24 h, minute 60, second 60.
      expect(raw((b, _) => b.setRange(26, 28, [2, 30])), _refused);
      expect(raw((b, _) => b[26] = 13), _refused);
      expect(raw((b, _) => b[28] = 24), _refused);
      expect(raw((b, _) => b[29] = 60), _refused);
      expect(raw((b, _) => b[30] = 60), _refused);
      // A record cut short.
      expect(
        _failure(
          async,
          () => ble.writeRaw(GrBleCatalog.gpsInformation, Uint8List(31)),
        ),
        _refused,
      );
      expect(camera.location, isNull);
      expect(camera.locationWrites, isEmpty);
      expect(camera.refusedLocationWrites, 12);

      // The ends of each range are taken.
      for (final record in [
        _position(latitude: 90, longitude: -180, altitude: -9999),
        _position(latitude: -90, longitude: 180, altitude: 9999),
        _position(time: DateTime.utc(2028, 2, 29, 23, 59, 59)),
      ]) {
        expect(_failure(async, () => ble.sendGps(record)), isNull);
      }
      expect(camera.locationWrites, hasLength(3));
      expect(camera.location!.fixTime, DateTime.utc(2028, 2, 29, 23, 59, 59));
    });
  });

  test("a position is valid for 600 s from receipt by the camera's clock", () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.sendGps(_position()));
      final receivedAt = camera.location!.receivedAt;
      expect(
        camera.clockTime.difference(receivedAt),
        lessThanOrEqualTo(_exchange),
      );

      async.elapse(const Duration(seconds: 599));
      expect(camera.location, isNotNull);
      async.elapse(const Duration(seconds: 1));
      expect(camera.location, isNull);
      expect(camera.locationWrites, hasLength(1));
    });
  });

  test('each accepted write restarts the 600 s; a refused one does not', () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.sendGps(_position()));
      async.elapse(const Duration(seconds: 400));
      _done(async, ble.sendGps(_position(latitude: 36)));
      async.elapse(const Duration(seconds: 400));
      expect(camera.location?.latitude, 36);

      camera.locationLocked = true;
      expect(_failure(async, () => ble.sendGps(_position())), _refused);
      async.elapse(const Duration(seconds: 200));
      expect(camera.location, isNull, reason: '600 s after the second write');
    });
  });

  test('turning Store Location Info off clears the location at once, over '
      'Bluetooth or in the menu', () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.sendGps(_position()));
      _done(async, ble.setGeoTag(enabled: false));
      expect(camera.location, isNull);
      _done(async, ble.setGeoTag(enabled: true));
      expect(camera.location, isNull, reason: 'not brought back');

      _done(async, ble.sendGps(_position()));
      expect(camera.location, isNotNull);
      camera.storeLocationInfo = false;
      expect(camera.location, isNull);
      expect(_failure(async, () => ble.sendGps(_position())), _refused);
    });
  });

  test('a menu change of Store Location Info notifies GEO Tag', () {
    withCamera(on, (async, camera, ble) {
      final notified = <bool?>[];
      final watch = ble
          .watch(GrBleCatalog.geoTag)
          .listen((n) => notified.add(n.decoded.value));
      async.elapse(_exchange);

      camera.storeLocationInfo = false;
      async.elapse(_exchange);
      expect(notified, [false]);
      camera.storeLocationInfo = true;
      async.elapse(_exchange);
      expect(notified, [false, true]);
      camera.storeLocationInfo = true;
      async.elapse(_exchange);
      expect(notified, [false, true], reason: 'no change, no notification');

      unawaited(watch.cancel());
    });
  });

  test('GEO Tag takes only 00 and 01', () {
    withCamera(on, (async, camera, ble) {
      for (final bytes in [
        [2],
        [0, 0],
        <int>[],
      ]) {
        expect(
          _failure(
            async,
            () => ble.writeRaw(GrBleCatalog.geoTag, Uint8List.fromList(bytes)),
          ),
          _refused,
        );
      }
      expect(camera.storeLocationInfo, isTrue);
    });
  });

  test("Date Time reads the camera's clock, which runs at an offset from the "
      "phone's", () {
    withCamera(
      const FakeCameraConfig(
        bonded: true,
        connectDelay: Duration.zero,
        clockOffset: Duration(seconds: 90),
      ),
      (async, camera, ble) {
        expect(camera.clockOffset, const Duration(seconds: 90));
        expect(camera.clockTime, clock.now().add(const Duration(seconds: 90)));
        final read = _done(async, ble.read(GrBleCatalog.dateTime)).value!;
        final expected = clock.now().add(const Duration(seconds: 90));
        expect(
          read.toLocalDateTime()!.difference(expected).abs(),
          lessThanOrEqualTo(const Duration(seconds: 1)),
        );

        camera.clockOffset = const Duration(hours: -2);
        final later = _done(async, ble.read(GrBleCatalog.dateTime)).value!;
        expect(
          later
              .toLocalDateTime()!
              .difference(clock.now().subtract(const Duration(hours: 2)))
              .abs(),
          lessThanOrEqualTo(const Duration(seconds: 1)),
        );
      },
    );
  });

  test('a Date Time write sets the clock', () {
    withCamera(on, (async, camera, ble) {
      final time = DateTime(2020, 1, 2, 3, 4, 5);
      _done(async, ble.syncDateTime(time));
      expect(camera.clockWrites, [time]);
      async.elapse(const Duration(seconds: 10));
      final read = _done(async, ble.read(GrBleCatalog.dateTime)).value!;
      expect(read.toLocalDateTime(), DateTime(2020, 1, 2, 3, 4, 15));
      expect(
        camera.clockTime.difference(DateTime(2020, 1, 2, 3, 4, 15)).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    });
  });

  test('a GR IV clears its location 1 s after a Date Time write that '
      'changes the clock', () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.sendGps(_position()));
      _done(async, ble.syncDateTime(clock.now().add(const Duration(hours: 1))));
      async.elapse(const Duration(milliseconds: 900));
      expect(camera.location, isNotNull, reason: 'not before the second ends');
      async.elapse(const Duration(milliseconds: 100));
      expect(camera.location, isNull);
    });
  });

  test('a position written inside that second is cleared with it; one '
      'written after stays', () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.syncDateTime(clock.now().add(const Duration(hours: 1))));
      _done(async, ble.sendGps(_position()));
      expect(camera.location, isNotNull);
      async.elapse(const Duration(seconds: 1));
      expect(camera.location, isNull);

      _done(async, ble.sendGps(_position()));
      async.elapse(const Duration(seconds: 5));
      expect(camera.location, isNotNull);
    });
  });

  test('a Date Time write of the second the clock shows clears nothing', () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.sendGps(_position()));
      // Away from the end of the second, so the write lands inside it.
      async.elapse(Duration(milliseconds: 1200 - camera.clockTime.millisecond));
      _done(async, ble.syncDateTime(camera.clockTime));
      expect(camera.clockWrites, hasLength(1));
      async.elapse(const Duration(seconds: 5));
      expect(camera.location, isNotNull);
    });
  });

  test("a change of the clock in the camera's menu clears the location "
      'too', () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.sendGps(_position()));
      camera.clockOffset = const Duration(minutes: 5);
      expect(camera.clockWrites, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(camera.location, isNull);
    });
  });

  test('a GR III keeps its location over a clock change, until it next '
      'starts up', () {
    withCamera(
      const FakeCameraConfig(
        model: 'RICOH GR III',
        bonded: true,
        connectDelay: Duration.zero,
        storeLocationInfo: true,
      ),
      (async, camera, ble) {
        _done(async, ble.sendGps(_position()));
        _done(
          async,
          ble.syncDateTime(clock.now().add(const Duration(hours: 1))),
        );
        async.elapse(const Duration(seconds: 5));
        expect(camera.location, isNotNull, reason: 'the timer still runs');

        // At start-up the time of receipt is compared with the clock,
        // which now says an hour has passed.
        camera.poweredOn = false;
        async.elapse(const Duration(seconds: 5));
        camera.poweredOn = true;
        expect(camera.location, isNull);
      },
    );
  });

  test('the location is kept across power off and on inside the 600 s', () {
    withCamera(on, (async, camera, ble) {
      _done(async, ble.sendGps(_position()));
      camera.poweredOn = false;
      async.elapse(const Duration(seconds: 100));
      expect(camera.linkCount, 0);
      camera.poweredOn = true;
      async.elapse(const Duration(seconds: 100));
      expect(camera.location, isNotNull);
      expect(camera.storeLocationInfo, isTrue);

      async.elapse(const Duration(seconds: 400));
      expect(camera.location, isNull, reason: '600 s after the write');
    });
  });

  test('a camera set up without GPS Information does not have it', () {
    withCamera(
      const FakeCameraConfig(
        bonded: true,
        connectDelay: Duration.zero,
        storeLocationInfo: true,
        absent: {'gps', 'geotag'},
      ),
      (async, camera, ble) {
        expect(ble.isPresent(GrBleCatalog.gpsInformation), isFalse);
        expect(ble.isPresent(GrBleCatalog.geoTag), isFalse);
        expect(ble.isPresent(GrBleCatalog.dateTime), isTrue);
        final notFound = isA<BleException>().having(
          (e) => e.code,
          'code',
          BleErrorCode.notFound,
        );
        expect(_failure(async, () => ble.sendGps(_position())), notFound);
        expect(
          _failure(
            async,
            () => ble.writeUuid(
              GrBleCatalog.gpsInformation.service.uuid,
              GrBleCatalog.gpsInformation.uuid,
              GrBleCatalog.gpsInformation.codec.encode(_position()),
            ),
          ),
          notFound,
        );
        expect(camera.refusedLocationWrites, 0);
      },
    );
  });

  test('a camera switched on with its links kept reports Camera Power on '
      'over them', () {
    withCamera(
      const FakeCameraConfig(
        bonded: true,
        poweredOn: false,
        connectDelay: Duration.zero,
      ),
      (async, camera, ble) {
        final power = <BleCameraPower?>[];
        final watch = ble
            .watch(GrBleCatalog.cameraPower)
            .listen((n) => power.add(n.decoded.value?.known));
        async.elapse(_exchange);

        camera.powerOnKeepingLinks();
        async.elapse(_exchange);
        expect(camera.poweredOn, isTrue);
        expect(camera.linkCount, 1);
        expect(power, [BleCameraPower.on]);
        expect(
          _done(async, ble.read(GrBleCatalog.operationMode)).value?.known,
          BleOperationMode.capture,
        );

        unawaited(watch.cancel());
      },
    );
  });
}
