import 'dart:async';
import 'dart:io';

import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

typedef _Status = (BleCapturing?, BleCountdown?);

const (BleCapturing, BleCountdown) _capturing = (
  BleCapturing.capturing,
  BleCountdown.none,
);
const (BleCapturing, BleCountdown) _idle = (
  BleCapturing.idle,
  BleCountdown.none,
);
const (BleCapturing, BleCountdown) _counting = (
  BleCapturing.idle,
  BleCountdown.selfTimer,
);

void main() {
  late FakeGrCamera camera;
  GrSession? session;
  GrHttpClient? http;
  GrChangesSocket? changes;
  late List<GrChangeEvent> events;
  late List<_Status> statuses;

  setUp(() {
    events = [];
    statuses = [];
  });

  tearDown(() async {
    await changes?.close();
    changes = null;
    http?.close(force: true);
    http = null;
    await session?.close();
    session = null;
    await camera.close();
  });

  /// Linked over BLE, the camera put into capture mode with
  /// [GrSession.wake], Capture Status watched and the change socket open.
  Future<GrBleClient> remote([
    FakeCameraConfig? config,
    FakeMediaSource? media,
  ]) async {
    camera = await startCamera(
      config ?? fastConfig(bonded: true),
      media: media,
    );
    final s = session = sessionFor(camera);
    await s.connectBluetooth(deviceId: camera.config.deviceId);
    await s.wake(BleOperationMode.capture);
    final h = http = camera.httpClient('192.168.0.1', null);
    final c = changes = h.changesSocket();
    c.events.listen(events.add);
    await c.connect();
    final ble = s.ble!;
    ble.watch(GrBleCatalog.captureStatus).listen((n) {
      final v = n.decoded.value!;
      statuses.add((v.capturing.known, v.countdown.known));
    });
    return ble;
  }

  BleStorageEntry sdEntry(BleStorageInformation info) =>
      info.entries.singleWhere((e) => e.type.known == BleStorageType.sdSlot1);

  group('BLE shutter', () {
    test('without a self-timer: capturing, then a new photo on the card, one '
        'picture fewer, and storage and capture changes', () async {
      final ble = await remote();
      expect(camera.operationMode, BleOperationMode.capture);
      final left = <int>[];
      ble
          .watch(GrBleCatalog.storageInformation)
          .listen((n) => left.add(sdEntry(n.decoded.value!).remainingPictures));
      final before = camera.photos.length;

      await ble.shutter();
      await until(() => statuses.length >= 2);
      expect(statuses, [_capturing, _idle]);
      expect(camera.photos, hasLength(before + 1));
      final photo = camera.photos.last;
      expect(photo.path, GrPhotoPath('101RICOH', 'R0000271.JPG'));
      expect(camera.remainingPictures, 1233);
      expect(left, [1233]);
      final read = await ble.read(GrBleCatalog.storageInformation);
      expect(sdEntry(read.value!).remainingPictures, 1233);

      await until(() => events.whereType<GrCaptureChange>().isNotEmpty);
      final added = events.whereType<GrStorageChange>().single;
      expect(added.action, 'add');
      expect(added.path, photo.path);
      expect(
        added.captureId,
        events.whereType<GrCaptureChange>().single.captureId,
      );
      expect(
        events.whereType<GrCameraDirectChange>().last.stillCaptureComplete,
        isTrue,
      );

      final props = await http!.props();
      expect(props.storages.last.remain, 1233);
      final info = await http!.photoInfo(photo.path);
      expect(info.av, '2.8');
    });

    test('a second capture serves the bytes of a photo the media source '
        'knows, not of the first capture', () async {
      final card = FakePhoto.defaultCard();
      final known = Set<FakePhoto>.identity()..addAll(card);
      final synthetic = syntheticMedia();
      final ble = await remote(
        fastConfig(bonded: true, photos: card),
        (photo, size) => known.contains(photo)
            ? synthetic(photo, size)
            : throw StateError('not on the source card: $photo'),
      );
      for (var shot = 1; shot <= 2; shot++) {
        await ble.shutter();
        await until(() => camera.photos.length == card.length + shot);
        await until(() => statuses.length == 2 * shot);
      }
      for (final photo in camera.photos.skip(card.length)) {
        final info = await http!.photoInfo(photo.path);
        expect(info.ok, isTrue, reason: '$photo');
      }
    });

    test('with the 2 s self-timer: the countdown first, then the '
        'capture', () async {
      final ble = await remote();
      await ble.setDriveMode(BleDriveMode.selfTimer2s);
      expect(camera.driveMode, BleDriveMode.selfTimer2s);
      expect(
        (await ble.read(GrBleCatalog.driveMode)).value!.known,
        BleDriveMode.selfTimer2s,
      );
      final before = camera.photos.length;

      await ble.shutter();
      await until(() => statuses.length >= 3);
      expect(statuses, [_counting, _capturing, _idle]);
      expect(camera.photos, hasLength(before + 1));
      await until(() => events.whereType<GrStorageChange>().isNotEmpty);
      expect(
        events.whereType<GrCameraDirectChange>().first.countDown,
        'busy2s',
      );
    });

    for (final format in BleSelfTimerCancelFormat.values) {
      test('Self Timer (${format.name}) cancels a 10 s countdown: no '
          'picture', () async {
        final ble = await remote(
          fastConfig(bonded: true, selfTimerScale: 0.05),
        );
        await ble.setDriveMode(BleDriveMode.selfTimer10s);
        final before = camera.photos.length;

        await ble.shutter();
        await until(() => statuses.isNotEmpty);
        expect(statuses, [_counting]);
        await ble.cancelSelfTimer(format);
        await until(() => statuses.length >= 2);
        // Past the 500 ms the countdown would have run.
        await Future<void>.delayed(ms(700));
        expect(statuses, [_counting, _idle]);
        expect(camera.photos, hasLength(before));
        expect(camera.remainingPictures, 1234);
        expect(events.whereType<GrStorageChange>(), isEmpty);
      });
    }

    test('refused in playback and while the camera is off', () async {
      camera = await startCamera(fastConfig(bonded: true));
      final s = session = sessionFor(camera);
      await s.connectBluetooth(deviceId: camera.config.deviceId);
      expect(camera.operationMode, BleOperationMode.playback);
      await expectLater(s.ble!.shutter(), throwsA(isA<BleException>()));
      await s.close();
      await camera.close();

      camera = await startCamera(fastConfig(bonded: true, poweredOn: false));
      final t = session = sessionFor(camera);
      await t.connectBluetooth(deviceId: camera.config.deviceId);
      expect(t.cameraOff, isTrue);
      await expectLater(t.ble!.shutter(), throwsA(isA<BleException>()));
      expect(camera.photos, hasLength(FakePhoto.defaultCard().length));
    });

    test('readouts: drive mode, mode dial, battery and storage, with '
        'notifications as the dial turns', () async {
      final ble = await remote();
      expect(
        (await ble.read(GrBleCatalog.driveMode)).value!.known,
        BleDriveMode.single,
      );
      final mode = (await ble.read(GrBleCatalog.shootingMode)).value!;
      expect(mode.mode.known, BleExposureMode.av);
      expect(mode.userMode.known, BleUserMode.none);
      expect((await ble.read(GrBleCatalog.batteryLevel)).value!.level, 82);
      final storage = (await ble.read(GrBleCatalog.storageInformation)).value!;
      expect(storage.entrySize, 14);
      expect(storage.entries.map((e) => e.type.known), [
        BleStorageType.internalMemory,
        BleStorageType.sdSlot1,
      ], reason: 'storage-id order, as GR IV firmware sends them');
      expect(sdEntry(storage).remainingPictures, 1234);

      final dial = <BleShootingMode>[];
      ble
          .watch(GrBleCatalog.shootingMode)
          .listen((n) => dial.add(n.decoded.value!));
      await Future<void>.delayed(Duration.zero);
      camera
        ..setExposureMode(BleExposureMode.m)
        ..setExposureMode(BleExposureMode.av, userMode: BleUserMode.u1);
      await until(() => dial.length >= 2);
      expect(dial.map((m) => (m.mode.known, m.userMode.known)), [
        (BleExposureMode.m, BleUserMode.none),
        (BleExposureMode.av, BleUserMode.u1),
      ]);
      expect((await http!.props()).exposureMode, 'U1');
      camera.setExposureMode(BleExposureMode.m);
      expect((await http!.props()).exposureMode, 'M');
    });
  });

  group('HTTP', () {
    Future<GrHttpClient> httpOnly([FakeCameraConfig? config]) async {
      camera = await startCamera(config ?? fastConfig());
      return http = camera.httpClient('192.168.0.1', null);
    }

    test('live view: MJPEG as the firmware sends it, at most maxfps, until '
        'the access point goes down', () async {
      final h = await httpOnly();
      final view = await h.openLiveView(maxFps: 5);
      expect(
        view.headers['content-type'],
        'multipart/x-mixed-replace; boundary=--boundary',
      );
      expect(view.headers.containsKey('content-length'), isFalse);
      expect(view.headers.containsKey('transfer-encoding'), isFalse);
      final frames = <LiveViewFrame>[];
      final sub = view.frames.listen(frames.add);
      await until(() => frames.length >= 3);
      for (final f in frames) {
        expect(f.jpeg.take(2), [0xFF, 0xD8]);
        expect(f.jpeg.skip(f.jpeg.length - 2), [0xFF, 0xD9]);
        expect(f.dimensions, isNotNull);
      }
      // 5 fps: 200 ms apart.
      expect(
        frames[2].sinceOpen - frames[0].sinceOpen,
        greaterThanOrEqualTo(ms(300)),
      );
      expect(view.stats.interrupted, 0);

      camera.dropWifi();
      await view.done.timeout(const Duration(seconds: 2));
      await sub.cancel();
    });

    test('live view: a client that closes ends the stream; a non-digit '
        'maxfps is a bad request', () async {
      final h = await httpOnly();
      final view = await h.openLiveView();
      await view.frames.first;
      await view.close();

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.get(
        InternetAddress.loopbackIPv4.address,
        camera.httpPort!,
        '/v1/liveview?maxfps=fast',
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 400);
    });

    test('props offer each setting with its list', () async {
      final h = await httpOnly();
      final props = await h.props();
      for (final key in [
        'av',
        'tv',
        'sv',
        'xv',
        'meteringMode',
        'effect',
        'shootMode',
        'exposureMode',
        'captureMode',
        'operationMode',
      ]) {
        final setting = props.setting(key)!;
        expect(setting.options, isNotEmpty, reason: key);
        expect(setting.offers(setting.current!), isTrue, reason: key);
      }
      expect(props.setting('shootMode')!.current, 'single');
      expect(props.exposureMode, 'AV');
      expect(props.state, 'idle');
      expect(props.focusEffectiveArea, [78, 75]);
      expect(props.storages.map((s) => s.remain), [500, 1234]);
    });

    test('PUT params/camera: listed values are set, and drive mode follows '
        'shootMode; any unlisted value changes nothing', () async {
      final h = await httpOnly();
      final props = await h.setCameraParams({
        'av': '5.6',
        'xv': '+0.7',
        'shootMode': 'self2s',
      });
      expect(props.setting('av')!.current, '5.6');
      expect(props.setting('xv')!.current, '+0.7');
      expect(props.setting('shootMode')!.current, 'self2s');
      expect(camera.driveMode, BleDriveMode.selfTimer2s);
      expect((await h.props()).setting('av')!.current, '5.6');

      for (final bad in [
        {'av': '1.4'},
        {'exposureMode': 'M'},
        {'av': '8.0', 'tv': 'fast'},
      ]) {
        await expectLater(
          h.setCameraParams(bad),
          throwsA(
            isA<GrApiException>().having((e) => e.errCode, 'errCode', 400),
          ),
          reason: '$bad',
        );
      }
      final after = await h.props();
      expect(after.setting('av')!.current, '5.6');
      expect(after.setting('tv')!.current, '1.250');
      expect(after.exposureMode, 'AV');
    });

    test(
      'the mode dial decides which of aperture and shutter speed can be '
      'set: the other lists only its current value and refuses others',
      () async {
        final h = await httpOnly();
        Future<void> refused(Map<String, String> params) => expectLater(
          h.setCameraParams(params),
          throwsA(
            isA<GrApiException>().having((e) => e.errCode, 'errCode', 400),
          ),
          reason: '$params in ${camera.exposureMode.name}',
        );

        var props = await h.props();
        expect(props.setting('av')!.options!.length, greaterThan(1));
        expect(props.setting('tv')!.options, ['1.250']);
        await refused({'tv': '1.1000'});

        camera.setExposureMode(BleExposureMode.m);
        props = await h.setCameraParams({'tv': '1.1000', 'av': '4.0'});
        expect(props.setting('tv')!.current, '1.1000');
        expect(
          (await h.props()).setting('tv')!.options!.length,
          greaterThan(1),
        );

        camera.setExposureMode(BleExposureMode.tv);
        props = await h.props();
        expect(props.setting('av')!.options, ['4.0']);
        expect(props.setting('tv')!.options!.length, greaterThan(1));
        await refused({'av': '5.6'});

        camera.setExposureMode(BleExposureMode.p);
        props = await h.props();
        expect(props.setting('av')!.options, ['4.0']);
        expect(props.setting('tv')!.options, ['1.1000']);
        await refused({'tv': '1.250'});
      },
    );

    test('focus: answered with a captureId only, then a lens change with '
        'it; a second focus waits for the first', () async {
      await remote();
      final at = await http!.focus(pos: GrFocusPoint(30, 40));
      expect(at.ok, isTrue);
      expect(at.focused, isNull);
      expect(at.focusRunning, isNull);
      expect(at.captureId, isNotEmpty);
      final watch = Stopwatch()..start();
      final centre = await http!.focus();
      expect(events.whereType<GrLensChange>().map((e) => e.captureId), [
        at.captureId,
      ], reason: 'answered after the first focus ended');
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 100)));
      await until(() => events.whereType<GrLensChange>().length == 2);
      final lens = events.whereType<GrLensChange>().last;
      expect(lens.captureId, centre.captureId);
      expect(lens.focused, isTrue);
      expect(camera.focusPoints, [(30, 40), (50, 50)]);
    });

    test('shoot: a picture with the current settings; the captureId comes '
        'back in the change events', () async {
      final ble = await remote();
      camera.setExposureMode(BleExposureMode.m);
      await http!.setCameraParams({'tv': '1.1000', 'sv': '800'});
      final before = camera.photos.length;
      final shot = await http!.shoot(
        af: GrShootAf.on,
        pos: GrFocusPoint(50, 50),
      );
      expect(shot.ok, isTrue);
      await until(
        () => events.whereType<GrStorageChange>().any(
          (e) => e.captureId == shot.captureId,
        ),
      );
      expect(camera.photos, hasLength(before + 1));
      final info = await http!.photoInfo(camera.photos.last.path);
      expect(info.fields.string('tv'), '1.1000');
      expect(info.fields.string('sv'), '800');
      expect(statuses, [_capturing, _idle]);
      expect(ble.connection.deviceId, camera.config.deviceId);
    });

    test('shoot cancel ends a self-timer countdown without a '
        'picture', () async {
      await remote(fastConfig(bonded: true, selfTimerScale: 0.05));
      await http!.setCameraParams({'shootMode': 'self10s'});
      final before = camera.photos.length;
      await http!.shoot();
      await until(() => statuses.isNotEmpty);
      expect(
        events.whereType<GrCameraDirectChange>().last.countDown,
        'busy10s',
      );
      final cancelled = await http!.cancelShootTimer();
      expect(cancelled.ok, isTrue);
      await Future<void>.delayed(ms(700));
      expect(statuses, [_counting, _idle]);
      expect(camera.photos, hasLength(before));
      expect(events.whereType<GrCameraDirectChange>().last.countDown, 'idle');
    });

    test('shoot is refused in playback (400) and with a full card '
        '(412)', () async {
      final h = await httpOnly();
      expect(camera.operationMode, BleOperationMode.playback);
      await expectLater(
        h.shoot(),
        throwsA(isA<GrApiException>().having((e) => e.errCode, 'code', 400)),
      );
      h.close(force: true);
      http = null;
      await camera.close();

      await remote(fastConfig(bonded: true, remainingPictures: 0));
      await expectLater(
        http!.shoot(),
        throwsA(isA<GrApiException>().having((e) => e.errCode, 'code', 412)),
      );
      await expectLater(session!.ble!.shutter(), throwsA(isA<BleException>()));
      expect(camera.photos, hasLength(FakePhoto.defaultCard().length));
    });
  });
}
