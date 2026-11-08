import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/app.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/services.dart';
import 'package:grlab/src/theme/tokens.dart';

/// The app wired to a [FakeGrCamera], with its data in a temporary
/// directory.
///
/// Widget tests run app code in a fake-time zone while the camera's HTTP
/// server uses real sockets, so:
/// - create it outside fake time: `(await tester.runAsync(createTestApp))!`
///   or in `setUp`;
/// - wait with [pumpUntil] / [pumpUntilFound], which alternate real time
///   (for sockets) and fake time (for timers), never `pumpAndSettle`;
/// - finish every test with `await app.dispose()`, which tears the app
///   down and leaves no timers pending.
final class TestApp {
  TestApp._({
    required this.models,
    required this.camera,
    required this.ble,
    required this.media,
    required this._permission,
    required this._root,
  });

  final AppModels models;
  final FakeGrCamera camera;

  /// The transport the app uses: the camera's, with call counts.
  final CountingTransport ble;
  final RecordingMediaSaver media;
  final _Permission _permission;
  final Directory _root;
  WidgetTester? _tester;

  /// What `AppServices.ensureBluetoothPermission` answers (default true).
  bool get bluetoothPermission => _permission.granted;
  set bluetoothPermission(bool granted) => _permission.granted = granted;

  /// Pumps the whole app ([GrLabApp]), as `main` runs it.
  Future<void> pumpApp(WidgetTester tester) async {
    _tester = tester;
    await tester.pumpWidget(GrLabApp(models: models));
    await tester.pump();
  }

  /// Pumps [home] with the app's scope and theme, without [RootScreen] (so
  /// nothing connects by itself).
  Future<void> pumpWithin(
    WidgetTester tester,
    Widget home, {
    Brightness brightness = Brightness.light,
  }) async {
    _tester = tester;
    await tester.pumpWidget(
      AppScope(
        models: models,
        child: MaterialApp(theme: grTheme(brightness), home: home),
      ),
    );
    await tester.pump();
  }

  /// Unmounts the app, ends the session, stops the camera and removes the
  /// temporary data.
  Future<void> dispose() async {
    final tester = _tester;
    if (tester != null) {
      await tester.pumpWidget(const SizedBox.shrink());
      var closed = false;
      unawaited(
        models.connection.disconnect().whenComplete(() => closed = true),
      );
      await pumpUntil(tester, () => closed, reason: 'session close');
      models.connection.dispose();
      await tester.runAsync(camera.close);
      // Lets timers the camera or session started run out.
      await tester.pump(const Duration(minutes: 2));
      await tester.runAsync(_deleteRoot);
    } else {
      await models.connection.disconnect();
      models.connection.dispose();
      await camera.close();
      await _deleteRoot();
    }
  }

  Future<void> _deleteRoot() async {
    try {
      await _root.delete(recursive: true);
    } on FileSystemException {
      // A settings write still in flight; the OS cleans the temp dir.
    }
  }
}

/// Starts a [FakeGrCamera] with [config] and builds [AppModels] around it.
///
/// [saveCamera] stores the camera as already paired (use with
/// `FakeCameraConfig(bonded: true)` for a camera that accepts this phone,
/// or without it for one that needs pairing again). [sessionOptions]
/// shortens session timeouts for failure tests. [transport] wraps the
/// camera's BLE transport, e.g. to add a second camera.
/// [askBeforeWifiJoin] and [redialDelays] are passed to [AppServices].
Future<TestApp> createTestApp({
  FakeCameraConfig config = const FakeCameraConfig(),
  bool saveCamera = false,
  GrSessionOptions sessionOptions = const GrSessionOptions(),
  BleTransport Function(BleTransport camera)? transport,
  bool askBeforeWifiJoin = false,
  List<Duration> redialDelays = const [Duration(milliseconds: 20)],
}) async {
  // flutter_test answers every dart:io HttpClient request with 400; the
  // fake camera serves real HTTP on loopback.
  HttpOverrides.global = null;
  final root = await Directory.systemTemp.createTemp('grlab_test_');
  final data = await Directory('${root.path}/data').create();
  final cache = await Directory('${root.path}/cache').create();
  final camera = FakeGrCamera(config: config, media: syntheticMedia());
  await camera.startHttp();
  if (saveCamera) {
    final paired = GrPairedCamera(
      deviceId: config.deviceId,
      serialNumber: config.serial,
      modelName: config.model,
      firmwareRevision: config.firmware,
      bluetoothDeviceName: config.bluetoothName,
    );
    final store = await CameraStore.load(data);
    await store.add(
      SavedCamera(
        paired: paired,
        name: SavedCamera.defaultName(paired),
        pairedAt: DateTime(2026, 11, 7, 9, 41),
      ),
    );
  }
  final permission = _Permission();
  final ble = CountingTransport(
    transport == null ? camera.transport : transport(camera.transport),
  );
  final media = RecordingMediaSaver();
  final services = AppServices(
    ble: ble,
    wifi: camera.wifi,
    media: media,
    clientName: 'GR Lab',
    dataDir: data,
    cacheDir: cache,
    ensureBluetoothPermission: () async => permission.granted,
    httpFactory: camera.httpClient,
    sessionOptions: sessionOptions,
    askBeforeWifiJoin: askBeforeWifiJoin,
    redialDelays: redialDelays,
  );
  return TestApp._(
    models: await AppModels.load(services),
    camera: camera,
    ble: ble,
    media: media,
    permission: permission,
    root: root,
  );
}

/// Pumps until [condition] holds, letting real time pass for sockets and
/// fake time for timers on every round. Fails after [timeout] of real time.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String reason = 'condition',
  Duration timeout = const Duration(seconds: 30),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('Timed out waiting for $reason');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// [pumpUntil] [finder] matches at least one widget.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  reason: '$finder',
  timeout: timeout,
);

/// Taps [finder] once it can receive the tap: route and sheet transitions
/// leave a freshly built widget off-screen for a few frames, so this
/// scrolls it into view and waits until a hit test at its centre reaches
/// it.
Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
  await pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder);
  await pumpUntilFound(tester, finder.hitTestable());
  await tester.tap(finder);
  await tester.pump();
}

/// Pumps [rounds] of [pumpUntil]'s real/fake time steps.
Future<void> pumpRounds(WidgetTester tester, int rounds) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Forwards to the camera's transport, counting scans and connects.
final class CountingTransport implements BleTransport {
  CountingTransport(this._inner);

  final BleTransport _inner;
  int scans = 0;
  int connects = 0;

  /// Device ids passed to [connect], in order.
  final List<String> connected = [];

  @override
  Future<BleAdapterState> adapterState() => _inner.adapterState();

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    scans++;
    return _inner.scan(serviceUuids: serviceUuids);
  }

  @override
  Future<BleConnection> connect(String deviceId, {required Duration timeout}) {
    connects++;
    connected.add(deviceId);
    return _inner.connect(deviceId, timeout: timeout);
  }

  @override
  Future<void> close() => _inner.close();
}

/// One `MediaSaver.saveShot` call.
typedef SavedShot = ({List<String> names, List<int> sizes, String album});

/// Records saved shots instead of writing to the photo library. Set
/// [failWith] to make the next saves throw.
final class RecordingMediaSaver implements MediaSaver {
  final List<SavedShot> shots = [];
  MediaSaveException? failWith;

  @override
  Future<void> saveShot(List<File> files, {required String album}) async {
    final failure = failWith;
    if (failure != null) throw failure;
    shots.add((
      names: [for (final f in files) f.uri.pathSegments.last],
      // Synchronous: async file I/O would wait for real time in a widget
      // test.
      sizes: [for (final f in files) f.lengthSync()],
      album: album,
    ));
  }
}

final class _Permission {
  bool granted = true;
}
