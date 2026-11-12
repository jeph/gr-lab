import 'dart:typed_data';

import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A bonded camera with quick links. The location's validity stays at the
/// firmware's 600 s unless a test shortens it.
FakeCameraConfig _config({
  GrModel model = GrModel.gr4,
  bool poweredOn = true,
  bool storeLocationInfo = false,
  Duration locationValidity = const Duration(seconds: 600),
  Duration clockOffset = Duration.zero,
  Duration clockChangeClearsAfter = const Duration(milliseconds: 40),
}) => FakeCameraConfig(
  model: model.modelString,
  poweredOn: poweredOn,
  bonded: true,
  storeLocationInfo: storeLocationInfo,
  locationValidity: locationValidity,
  clockOffset: clockOffset,
  clockChangeClearsAfter: clockChangeClearsAfter,
  advertisingInterval: ms(5),
  connectDelay: Duration.zero,
  bleLatency: Duration.zero,
);

/// A GPS Information record of a made-up position as it goes over the
/// link, built by hand so that values the codec will not encode can be
/// written.
Uint8List _gps({
  double latitude = 12.5,
  double longitude = -34.25,
  double altitude = 56,
  int year = 2026,
  int month = 11,
  int day = 12,
  int hour = 10,
  int minute = 30,
  int second = 15,
  int datum = 0,
}) {
  final bytes = Uint8List(32);
  ByteData.sublistView(bytes)
    ..setFloat64(0, latitude)
    ..setFloat64(8, longitude)
    ..setFloat64(16, altitude)
    ..setInt16(24, year, Endian.little);
  return bytes
    ..[26] = month
    ..[27] = day
    ..[28] = hour
    ..[29] = minute
    ..[30] = second
    ..[31] = datum;
}

/// A Date Time value as it goes over the link, built by hand for the same
/// reason.
Uint8List _dateTime({
  int year = 2026,
  int month = 11,
  int day = 12,
  int hour = 10,
  int minute = 30,
  int second = 15,
}) => Uint8List.fromList([
  year & 0xff,
  year >> 8,
  month,
  day,
  hour,
  minute,
  second,
]);

/// The calendar fields of [t] as a UTC time: two wall-clock readings then
/// compare without the time zone of the machine in the way.
DateTime _wall(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

DateTime _wallOf(BleDateTime t) =>
    DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

/// Within two seconds of [expected]: the time a test takes to read a clock.
Matcher _near(DateTime expected) => isA<DateTime>().having(
  (t) => t.difference(expected).abs(),
  'distance from $expected',
  lessThan(const Duration(seconds: 2)),
);

final Matcher _refused = throwsA(
  isA<BleException>().having((e) => e.code, 'code', BleErrorCode.gatt),
);

Matcher _startFails(LocationStartFailure failure) => throwsA(
  isA<LocationStartException>().having((e) => e.failure, 'failure', failure),
);

const _notice = LocationNotice(
  title: 'Sending location to MY GR IV',
  text: 'Tap to open GR Photo',
  stopLabel: 'Stop',
  channelName: 'Location',
);

final _fix = PhoneFix(
  latitude: 12.5,
  longitude: -34.25,
  accuracy: 8,
  time: DateTime.utc(2026, 11, 12, 10, 30, 15),
);

void main() {
  group('camera:', () {
    late FakeGrCamera camera;

    tearDown(() => camera.close());

    /// A camera built from [config] and a client on a link to it.
    Future<GrBleClient> link(FakeCameraConfig config) async {
      camera = FakeGrCamera(config: config, media: syntheticMedia());
      final connection = await camera.transport.connect(
        camera.config.deviceId,
        timeout: const Duration(seconds: 1),
      );
      addTearDown(connection.disconnect);
      final client = GrBleClient(connection);
      await client.discover();
      return client;
    }

    Future<void> sendGps(GrBleClient ble, [Uint8List? record]) =>
        ble.writeRaw(GrBleCatalog.gpsInformation, record ?? _gps());

    group('Store Location Info (GEO Tag)', () {
      test('is off unless the config turns it on, and GEO Tag reads '
          'it', () async {
        var ble = await link(_config());
        expect(camera.storeLocationInfo, isFalse);
        expect(await ble.readRaw(GrBleCatalog.geoTag), [0]);
        await camera.close();

        ble = await link(_config(storeLocationInfo: true));
        expect(camera.storeLocationInfo, isTrue);
        expect(await ble.readRaw(GrBleCatalog.geoTag), [1]);
      });

      test('a write of 01 or 00 sets it, and only a change '
          'notifies', () async {
        final ble = await link(_config());
        final notified = <bool>[];
        ble
            .watch(GrBleCatalog.geoTag)
            .listen((n) => notified.add(n.decoded.value!));

        await ble.setGeoTag(enabled: true);
        await pumpEventQueue();
        expect(camera.storeLocationInfo, isTrue);
        expect(await ble.readRaw(GrBleCatalog.geoTag), [1]);
        expect(notified, [true]);

        await ble.setGeoTag(enabled: true);
        await pumpEventQueue();
        expect(notified, [true]);

        await ble.setGeoTag(enabled: false);
        await pumpEventQueue();
        expect(camera.storeLocationInfo, isFalse);
        expect(await ble.readRaw(GrBleCatalog.geoTag), [0]);
        expect(notified, [true, false]);
      });

      test('the camera menu (the setter) changes it and notifies the '
          'same way', () async {
        final ble = await link(_config());
        final notified = <bool>[];
        ble
            .watch(GrBleCatalog.geoTag)
            .listen((n) => notified.add(n.decoded.value!));
        // The subscription is in place once an exchange has gone through.
        await ble.readRaw(GrBleCatalog.geoTag);

        camera.storeLocationInfo = true;
        await pumpEventQueue();
        expect(camera.storeLocationInfo, isTrue);
        expect(await ble.readRaw(GrBleCatalog.geoTag), [1]);
        expect(notified, [true]);

        camera.storeLocationInfo = true;
        await pumpEventQueue();
        expect(notified, [true]);

        camera.storeLocationInfo = false;
        await pumpEventQueue();
        expect(camera.storeLocationInfo, isFalse);
        expect(notified, [true, false]);
      });

      const refusedValues = <String, List<int>>{
        'no bytes': [],
        '02': [0x02],
        'FF': [0xff],
        '00 00': [0x00, 0x00],
        '01 01': [0x01, 0x01],
      };
      for (final MapEntry(key: name, value: bytes) in refusedValues.entries) {
        test('a write of $name is refused and changes nothing', () async {
          final ble = await link(_config(storeLocationInfo: true));
          final notified = <bool>[];
          ble
              .watch(GrBleCatalog.geoTag)
              .listen((n) => notified.add(n.decoded.value!));

          await expectLater(
            ble.writeRaw(GrBleCatalog.geoTag, Uint8List.fromList(bytes)),
            _refused,
          );
          await pumpEventQueue();
          expect(camera.storeLocationInfo, isTrue);
          expect(notified, isEmpty);
        });
      }
    });

    group('GPS Information', () {
      test('is refused while Store Location Info is off; with it on the '
          "record is the camera's location", () async {
        final ble = await link(_config());
        expect(camera.location, isNull);
        await expectLater(sendGps(ble), _refused);
        expect(camera.location, isNull);
        expect(camera.acceptedLocations, isEmpty);

        await ble.setGeoTag(enabled: true);
        await ble.sendGps(
          BleGpsInformation.at(
            latitude: 12.5,
            longitude: -34.25,
            altitude: 56,
            time: DateTime.utc(2026, 11, 12, 10, 30, 15),
          ),
        );
        final location = camera.location!;
        expect(location.latitude, 12.5);
        expect(location.longitude, -34.25);
        expect(location.altitude, 56);
        expect([location.year, location.month, location.day], [2026, 11, 12]);
        expect([location.hour, location.minute, location.second], [10, 30, 15]);
        expect(camera.acceptedLocations, [same(location)]);
      });

      test('every accepted record is kept, oldest first, in a list that '
          'cannot be changed', () async {
        final ble = await link(_config(storeLocationInfo: true));
        await sendGps(ble);
        await sendGps(ble, _gps(latitude: 13.5));
        await expectLater(sendGps(ble, _gps(latitude: 95)), _refused);
        await sendGps(ble, _gps(latitude: 14.5));

        final accepted = camera.acceptedLocations;
        expect(accepted.map((r) => r.latitude), [12.5, 13.5, 14.5]);
        expect(camera.location, same(accepted.last));
        expect(accepted.clear, throwsUnsupportedError);
      });

      final refusedRecords = <String, Uint8List>{
        'one byte short': Uint8List.sublistView(_gps(), 0, 31),
        'with a latitude above 90': _gps(latitude: 90.5),
        'with a latitude below -90': _gps(latitude: -90.5),
        'with a latitude that is not a number': _gps(latitude: double.nan),
        'with a longitude above 180': _gps(longitude: 180.5),
        'with a longitude below -180': _gps(longitude: -180.5),
        'with an altitude above 9999': _gps(altitude: 9999.5),
        'with an altitude below -9999': _gps(altitude: -9999.5),
        'in month 13': _gps(month: 13),
        'in month 0': _gps(month: 0),
        'on day 0': _gps(day: 0),
        'on 31 April': _gps(month: 4, day: 31),
        'on 29 February of a year without one': _gps(month: 2, day: 29),
        'at hour 24': _gps(hour: 24),
        'at minute 60': _gps(minute: 60),
        'at second 60': _gps(second: 60),
      };
      for (final MapEntry(key: name, value: record) in refusedRecords.entries) {
        test('a record $name is refused and the location stays', () async {
          final ble = await link(_config(storeLocationInfo: true));
          await sendGps(ble);
          final before = camera.location;

          await expectLater(sendGps(ble, record), _refused);
          expect(camera.location, same(before));
          expect(camera.acceptedLocations, hasLength(1));
        });
      }

      test('the limits themselves, a leap day, any year, another datum and '
          'a trailing byte are accepted', () async {
        final ble = await link(_config(storeLocationInfo: true));
        final records = [
          _gps(latitude: 90, longitude: 180, altitude: 9999),
          _gps(latitude: -90, longitude: -180, altitude: -9999),
          _gps(year: 2028, month: 2, day: 29),
          // The firmware's bound on the year hangs on a base year that is
          // unknown (geotagging.md §1.2), so the fake has none.
          _gps(year: 1970),
          _gps(year: 2200),
          // `bled` never reads the datum and takes a record of another
          // length (geotagging.md §1.1).
          _gps(datum: 7),
          Uint8List.fromList([..._gps(), 0]),
        ];
        for (final record in records) {
          await sendGps(ble, record);
        }
        expect(camera.acceptedLocations, hasLength(records.length));
      });

      test('is refused while the camera is off', () async {
        final ble = await link(
          _config(poweredOn: false, storeLocationInfo: true),
        );
        await expectLater(sendGps(ble), _refused);
        expect(camera.location, isNull);
        expect(camera.acceptedLocations, isEmpty);
      });

      test('the location is cleared when its validity runs out, and not '
          'before', () async {
        final ble = await link(
          _config(storeLocationInfo: true, locationValidity: ms(150)),
        );
        final sinceWrite = Stopwatch()..start();
        await sendGps(ble);
        expect(camera.location, isNotNull);

        await until(() => camera.location == null);
        expect(sinceWrite.elapsed, greaterThan(ms(100)));
        expect(camera.acceptedLocations, hasLength(1));
      });

      test('a second record starts the validity again', () async {
        final ble = await link(
          _config(storeLocationInfo: true, locationValidity: ms(300)),
        );
        await sendGps(ble);
        await Future<void>.delayed(ms(200));
        await sendGps(ble, _gps(latitude: 13.5));

        // Past the first record's 300 ms, inside the second's.
        await Future<void>.delayed(ms(200));
        expect(camera.location?.latitude, 13.5);
        await until(() => camera.location == null);
      });

      test('a GEO Tag write of 00 clears the location at once, and turning '
          'it on again does not bring it back', () async {
        final ble = await link(_config(storeLocationInfo: true));
        await sendGps(ble);
        expect(camera.location, isNotNull);

        await ble.setGeoTag(enabled: false);
        expect(camera.location, isNull);
        await ble.setGeoTag(enabled: true);
        expect(camera.location, isNull);
        expect(camera.acceptedLocations, hasLength(1));
      });

      test('turning Store Location Info off in the camera menu clears the '
          'location at once', () async {
        final ble = await link(_config(storeLocationInfo: true));
        await sendGps(ble);
        expect(camera.location, isNotNull);

        camera.storeLocationInfo = false;
        expect(camera.location, isNull);
        await expectLater(sendGps(ble), _refused);
      });

      test('a Bluetooth drop and a power cycle leave the location alone, '
          'and its validity still runs out', () async {
        final ble = await link(
          _config(storeLocationInfo: true, locationValidity: ms(300)),
        );
        await sendGps(ble);

        camera.dropBluetooth();
        await ble.connection.disconnected;
        expect(camera.linkCount, 0);
        expect(camera.location, isNotNull);

        camera
          ..poweredOn = false
          ..poweredOn = true;
        expect(camera.location, isNotNull);
        expect(camera.storeLocationInfo, isTrue);

        await until(() => camera.location == null);
      });

      test('the validity runs out while the camera is off: turning it off '
          'neither clears the location nor holds or restarts its '
          'time', () async {
        final ble = await link(
          _config(storeLocationInfo: true, locationValidity: ms(400)),
        );
        await sendGps(ble);
        await Future<void>.delayed(ms(200));

        camera.poweredOn = false;
        expect(camera.location, isNotNull);

        // 500 ms after the record: past its 400 ms, and short of the 600 ms
        // a time held or started again at power-off would give it.
        await Future<void>.delayed(ms(300));
        expect(camera.poweredOn, isFalse);
        expect(camera.location, isNull);

        camera.poweredOn = true;
        expect(camera.location, isNull);
      });

      test('turned back on inside the validity the camera still has the '
          'location, for what is left of that time', () async {
        final ble = await link(
          _config(storeLocationInfo: true, locationValidity: ms(400)),
        );
        await sendGps(ble);
        camera.poweredOn = false;
        await Future<void>.delayed(ms(200));

        camera.poweredOn = true;
        expect(camera.location, isNotNull);

        // 500 ms after the record: short of the 600 ms a time held while
        // off, or started again at power-on, would give it.
        await Future<void>.delayed(ms(300));
        expect(camera.location, isNull);
      });
    });

    group('Date Time', () {
      test("a read gives the camera's clock: the phone's time plus the "
          'configured offset', () async {
        const offset = Duration(days: 3, hours: 2, minutes: 5);
        final ble = await link(_config(clockOffset: offset));

        final read = (await ble.read(GrBleCatalog.dateTime)).value!;
        final expected = _wall(DateTime.now().add(offset));
        expect(_wallOf(read), _near(expected));
        expect(_wall(camera.clock), _near(expected));
        expect(camera.clockWrites, 0);
      });

      test('a write sets the clock to what was written and is '
          'counted', () async {
        final ble = await link(_config());
        final first = DateTime(2031, 4, 5, 6, 7, 8);
        await ble.syncDateTime(first);
        expect(camera.clockWrites, 1);
        expect(_wall(camera.clock), _near(_wall(first)));
        final read = (await ble.read(GrBleCatalog.dateTime)).value!;
        expect(_wallOf(read), _near(_wall(first)));

        final second = DateTime(2019, 12, 31, 23, 59, 50);
        await ble.syncDateTime(second);
        expect(camera.clockWrites, 2);
        expect(_wall(camera.clock), _near(_wall(second)));
      });

      final refusedTimes = <String, Uint8List>{
        'one byte short': Uint8List.sublistView(_dateTime(), 0, 6),
        'in month 13': _dateTime(month: 13),
        'in month 0': _dateTime(month: 0),
        'on day 0': _dateTime(day: 0),
        'on 31 April': _dateTime(month: 4, day: 31),
        'on 29 February of a year without one': _dateTime(month: 2, day: 29),
        'at hour 24': _dateTime(hour: 24),
        'at minute 60': _dateTime(minute: 60),
        'at second 60': _dateTime(second: 60),
      };
      for (final MapEntry(key: name, value: bytes) in refusedTimes.entries) {
        test('a write $name is refused and the clock stays', () async {
          final ble = await link(_config());
          await expectLater(
            ble.writeRaw(GrBleCatalog.dateTime, bytes),
            _refused,
          );
          expect(camera.clockWrites, 0);
          expect(_wall(camera.clock), _near(_wall(DateTime.now())));
        });
      }

      test('reads and writes are refused while the camera is off', () async {
        final ble = await link(_config(poweredOn: false));
        await expectLater(ble.readRaw(GrBleCatalog.dateTime), _refused);
        await expectLater(
          ble.syncDateTime(DateTime(2031, 4, 5, 6, 7, 8)),
          _refused,
        );
        expect(camera.clockWrites, 0);
        expect(_wall(camera.clock), _near(_wall(DateTime.now())));
      });

      test('GR IV: a clock write clears the location a moment later, not '
          'at once, and a record written afterwards stays', () async {
        final ble = await link(
          _config(storeLocationInfo: true, clockChangeClearsAfter: ms(150)),
        );
        await sendGps(ble);
        final sinceWrite = Stopwatch()..start();
        await ble.syncDateTime();
        expect(camera.location, isNotNull);

        await until(() => camera.location == null);
        expect(sinceWrite.elapsed, greaterThan(ms(100)));

        await sendGps(ble);
        await Future<void>.delayed(ms(300));
        expect(camera.location, isNotNull);
      });

      test('GR IV: a refused clock write clears nothing', () async {
        final ble = await link(_config(storeLocationInfo: true));
        await sendGps(ble);
        await expectLater(
          ble.writeRaw(GrBleCatalog.dateTime, _dateTime(month: 13)),
          _refused,
        );
        await Future<void>.delayed(ms(150));
        expect(camera.location, isNotNull);
      });

      test('GR III: a clock write leaves the location alone', () async {
        final ble = await link(
          _config(model: GrModel.gr3, storeLocationInfo: true),
        );
        await sendGps(ble);
        await ble.syncDateTime();
        expect(camera.clockWrites, 1);

        await Future<void>.delayed(ms(150));
        expect(camera.location, isNotNull);
      });
    });
  });

  group('FakePhoneLocation', () {
    FakePhoneLocation phoneWith({
      LocationAccess access = LocationAccess.precise,
      LocationAccess? accessAfterRequest,
      PhoneFix Function(DateTime now)? source,
    }) {
      final phone = FakePhoneLocation(
        access: access,
        accessAfterRequest: accessAfterRequest,
        source: source,
      );
      addTearDown(phone.dispose);
      return phone;
    }

    Future<void> start(FakePhoneLocation phone, {Duration? interval}) =>
        phone.start(notice: _notice, interval: interval ?? ms(30));

    test('allows precise location unless told otherwise, and its streams '
        'are broadcast', () async {
      final phone = phoneWith();
      expect(await phone.access(), LocationAccess.precise);
      expect(phone.running, isFalse);
      expect(phone.mode, LocationMode.idle);
      expect(phone.notice, isNull);
      expect(phone.interval, isNull);
      expect(phone.fixes.isBroadcast, isTrue);
      expect(phone.stopRequests.isBroadcast, isTrue);
      expect(phone.accessChanges.isBroadcast, isTrue);
    });

    test('a request changes the access to what the script says, or leaves '
        'it, and is counted', () async {
      final phone = phoneWith(
        access: LocationAccess.undetermined,
        accessAfterRequest: LocationAccess.approximate,
      );
      expect(await phone.access(), LocationAccess.undetermined);
      expect(phone.requests, 0);

      expect(await phone.requestAccess(), LocationAccess.approximate);
      expect(await phone.access(), LocationAccess.approximate);
      expect(phone.requests, 1);

      phone
        ..currentAccess = LocationAccess.blocked
        ..accessAfterRequest = null;
      expect(await phone.access(), LocationAccess.blocked);
      expect(await phone.requestAccess(), LocationAccess.blocked);
      expect(phone.requests, 2);
    });

    test('opening the settings is counted', () async {
      final phone = phoneWith();
      await phone.openSettings();
      await phone.openSettings();
      expect(phone.settingsOpened, 2);
    });

    for (final access in LocationAccess.values) {
      final allowed =
          access == LocationAccess.precise ||
          access == LocationAccess.approximate;
      test('with ${access.name} access a run '
          '${allowed ? 'begins' : 'is denied'}', () async {
        final phone = phoneWith(access: access);
        if (allowed) {
          await start(phone);
        } else {
          await expectLater(
            start(phone),
            _startFails(LocationStartFailure.denied),
          );
        }
        expect(phone.running, allowed);
        expect(phone.starts, allowed ? 1 : 0);
      });
    }

    test('a scripted start failure is thrown until it is taken '
        'away', () async {
      final phone = phoneWith()..startFailure = LocationStartFailure.background;
      await expectLater(
        start(phone),
        _startFails(LocationStartFailure.background),
      );
      expect(phone.running, isFalse);
      expect(phone.starts, 0);

      phone.startFailure = null;
      await start(phone);
      expect(phone.running, isTrue);
    });

    test('a run begins idle; a second start changes its notice and '
        'interval; stop ends it, once', () async {
      final phone = phoneWith();
      await start(phone);
      expect(phone.running, isTrue);
      expect(phone.mode, LocationMode.idle);
      expect(phone.notice, _notice);
      expect(phone.interval, ms(30));
      expect(phone.starts, 1);

      await phone.setMode(LocationMode.precise);
      expect(phone.mode, LocationMode.precise);

      const renamed = LocationNotice(
        title: 'Sending location to STREET',
        text: 'Tap to open GR Photo',
        stopLabel: 'Stop',
        channelName: 'Location',
      );
      await phone.start(notice: renamed, interval: ms(70));
      expect(phone.notice, renamed);
      expect(phone.interval, ms(70));
      expect(phone.mode, LocationMode.precise);
      expect(phone.starts, 1);

      await phone.stop();
      expect(phone.running, isFalse);
      expect(phone.mode, LocationMode.idle);
      expect(phone.notice, isNull);
      expect(phone.interval, isNull);
      expect(phone.stops, 1);

      await phone.stop();
      expect(phone.stops, 1);

      await start(phone);
      expect(phone.mode, LocationMode.idle);
      expect(phone.starts, 2);
    });

    test('a mode set outside a run fails', () async {
      final phone = phoneWith();
      await expectLater(
        phone.setMode(LocationMode.precise),
        _startFails(LocationStartFailure.failed),
      );
      await start(phone);
      await phone.stop();
      await expectLater(
        phone.setMode(LocationMode.idle),
        _startFails(LocationStartFailure.failed),
      );
      expect(phone.mode, LocationMode.idle);
    });

    test('emit delivers a fix during a run, in either mode, and not '
        'outside one', () async {
      final phone = phoneWith();
      final fixes = <PhoneFix>[];
      phone.fixes.listen(fixes.add);

      phone.emit(_fix);
      await pumpEventQueue();
      expect(fixes, isEmpty);

      await start(phone);
      phone.emit(_fix);
      await pumpEventQueue();
      expect(fixes, [same(_fix)]);

      await phone.setMode(LocationMode.precise);
      phone.emit(_fix);
      await pumpEventQueue();
      expect(fixes, hasLength(2));

      await phone.stop();
      phone.emit(_fix);
      await pumpEventQueue();
      expect(fixes, hasLength(2));
    });

    test('tapping stop ends the run and says so; outside a run it does '
        'nothing', () async {
      final phone = phoneWith();
      var stopRequests = 0;
      phone.stopRequests.listen((_) => stopRequests++);

      phone.tapStop();
      await pumpEventQueue();
      expect(stopRequests, 0);

      await start(phone);
      await phone.setMode(LocationMode.precise);
      phone.tapStop();
      await pumpEventQueue();
      expect(stopRequests, 1);
      expect(phone.running, isFalse);
      expect(phone.mode, LocationMode.idle);
      expect(phone.notice, isNull);

      // The run is over already: stopping it again is safe and no stop.
      await phone.stop();
      expect(phone.stops, 0);
    });

    test('an access change is reported during a run only, and the run '
        'goes on', () async {
      final phone = phoneWith();
      final changes = <LocationAccess>[];
      phone.accessChanges.listen(changes.add);

      phone.changeAccess(LocationAccess.approximate);
      await pumpEventQueue();
      expect(await phone.access(), LocationAccess.approximate);
      expect(changes, isEmpty);

      await start(phone);
      phone.changeAccess(LocationAccess.off);
      await pumpEventQueue();
      expect(await phone.access(), LocationAccess.off);
      expect(changes, [LocationAccess.off]);
      expect(phone.running, isTrue);
    });

    group('with a source', () {
      late int made;
      PhoneFix make(DateTime now) {
        made++;
        return PhoneFix(
          latitude: 12.5,
          longitude: -34.25,
          accuracy: 8,
          time: now,
        );
      }

      setUp(() => made = 0);

      test('makes a fix at once on entering precise and one every '
          'interval, and none in idle or after stop', () async {
        final phone = phoneWith(source: make);
        final fixes = <PhoneFix>[];
        phone.fixes.listen(fixes.add);

        await start(phone);
        await Future<void>.delayed(ms(100));
        expect(made, 0);

        final before = DateTime.now().toUtc();
        await phone.setMode(LocationMode.precise);
        expect(made, greaterThan(0));
        await until(() => fixes.length >= 3);
        expect(fixes.first.time.isUtc, isTrue);
        expect(fixes.first.time.isBefore(before), isFalse);
        expect(fixes.first.latitude, 12.5);

        await phone.setMode(LocationMode.idle);
        var count = made;
        await Future<void>.delayed(ms(100));
        expect(made, count);

        await phone.setMode(LocationMode.precise);
        expect(made, greaterThan(count));
        await until(() => made >= count + 3);

        await phone.stop();
        count = made;
        await Future<void>.delayed(ms(100));
        expect(made, count);
        await pumpEventQueue();
        expect(fixes, hasLength(count));
      });

      test('stops making fixes when the user taps stop', () async {
        final phone = phoneWith(source: make);
        await start(phone);
        await phone.setMode(LocationMode.precise);
        phone.tapStop();
        final count = made;
        await Future<void>.delayed(ms(100));
        expect(made, count);
      });

      test('dispose ends the run, the fixes and the streams', () async {
        final phone = phoneWith(source: make);
        var done = 0;
        phone.fixes.listen((_) {}, onDone: () => done++);
        phone.stopRequests.listen((_) {}, onDone: () => done++);
        phone.accessChanges.listen((_) {}, onDone: () => done++);
        await start(phone);
        await phone.setMode(LocationMode.precise);

        phone.dispose();
        final count = made;
        await Future<void>.delayed(ms(100));
        expect(phone.running, isFalse);
        expect(made, count);
        expect(done, 3);
      });
    });
  });
}
