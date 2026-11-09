import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show
        BleAdapterState,
        BleAdvertisement,
        BleConnection,
        BleTransport,
        WifiNetworkControl;
import 'package:grlab/l10n/l10n.dart';
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
  new _({
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

  /// What the camera environment's Bluetooth permission request answers
  /// (default true).
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
        child: MaterialApp(
          theme: grTheme(brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  /// Unmounts the app, ends the session, stops the camera, closes the debug
  /// log and removes the temporary data.
  Future<void> dispose() async {
    final tester = _tester;
    if (tester != null) {
      await tester.pumpWidget(const SizedBox.shrink());
      var closed = false;
      unawaited(
        models.connection.disconnect().whenComplete(() => closed = true),
      );
      await pumpUntil(tester, () => closed, reason: 'session close');
      var flushed = false;
      unawaited(_flushLibrary().whenComplete(() => flushed = true));
      await pumpUntil(tester, () => flushed, reason: 'library flush');
      models.library.dispose();
      models.idle.dispose();
      models.connection.dispose();
      await tester.runAsync(camera.close);
      // Lets timers the camera or session started run out.
      await tester.pump(const Duration(minutes: 2));
      // Its writes were queued in the test's fake-time zone, so they need
      // pumping too.
      var logClosed = false;
      unawaited(models.debugLog.close().whenComplete(() => logClosed = true));
      await pumpUntil(tester, () => logClosed, reason: 'debug log close');
      await tester.runAsync(_deleteRoot);
    } else {
      await models.connection.disconnect();
      await _flushLibrary();
      models.library.dispose();
      models.idle.dispose();
      models.connection.dispose();
      await camera.close();
      await models.debugLog.close();
      await _deleteRoot();
    }
  }

  /// Waits until the library's listing and download records are on disk.
  Future<void> _flushLibrary() async {
    await models.library.model.flush();
    await models.library.engine.flush();
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
/// camera's BLE transport, e.g. to add a second camera; [wifi] wraps its
/// Wi-Fi control. [wifiApprovalShown] goes to the [GrCameraEnvironment],
/// [askBeforeWifiJoin] and [redialDelays] to [AppServices].
/// [debugLogBlocked] puts a file where the debug log's folder goes, so the
/// log cannot open.
Future<TestApp> createTestApp({
  FakeCameraConfig config = const FakeCameraConfig(),
  bool saveCamera = false,
  GrSessionOptions sessionOptions = const GrSessionOptions(),
  BleTransport Function(BleTransport camera)? transport,
  WifiNetworkControl Function(WifiNetworkControl camera)? wifi,
  bool askBeforeWifiJoin = false,
  Stream<void> wifiApprovalShown = const Stream.empty(),
  List<Duration> redialDelays = const [Duration(milliseconds: 20)],
  bool debugLogBlocked = false,
}) async {
  // flutter_test answers every dart:io HttpClient request with 400; the
  // fake camera serves real HTTP on loopback.
  HttpOverrides.global = null;
  final root = await Directory.systemTemp.createTemp('grlab_test_');
  final data = await Directory('${root.path}/data').create();
  final cache = await Directory('${root.path}/cache').create();
  final debugLogDir = Directory('${data.path}/debug-log');
  if (debugLogBlocked) await File(debugLogDir.path).writeAsString('');
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
  final trace = TraceRelay();
  final services = AppServices(
    camera: GrCameraEnvironment(
      ble: ble,
      wifi: wifi == null ? camera.wifi : wifi(camera.wifi),
      trace: trace.call,
      httpFactory: camera.httpClient,
      sessionOptions: sessionOptions,
      wifiApprovalShown: wifiApprovalShown,
      ensureBluetoothPermission: () async => permission.granted,
    ),
    trace: trace,
    media: media,
    clientName: 'GR Lab',
    dataDir: data,
    cacheDir: cache,
    debugLogDir: debugLogDir,
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
  new(this._inner);

  final BleTransport _inner;
  int scans = 0;

  /// Scans listened to and not yet cancelled or done.
  int scanning = 0;
  int connects = 0;

  /// Device ids passed to [connect], in order.
  final List<String> connected = [];

  @override
  Future<BleAdapterState> adapterState() => _inner.adapterState();

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    scans++;
    StreamSubscription<BleAdvertisement>? sub;
    late final StreamController<BleAdvertisement> controller;
    controller = StreamController<BleAdvertisement>(
      onListen: () {
        scanning++;
        sub = _inner
            .scan(serviceUuids: serviceUuids)
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () {
        scanning--;
        return sub?.cancel();
      },
    );
    return controller.stream;
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
/// [failWith] to make the next saves throw, [gate] to hold them.
final class RecordingMediaSaver implements MediaSaver {
  final List<SavedShot> shots = [];
  MediaSaveException? failWith;

  /// While set, saves wait for it to complete.
  Completer<void>? gate;

  /// Saves waiting for [gate].
  int held = 0;

  @override
  Future<void> saveShot(List<File> files, {required String album}) async {
    if (gate case final gate?) {
      held++;
      await gate.future;
      held--;
    }
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
