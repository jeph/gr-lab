import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show
        BleAdapterState,
        BleAdvertisement,
        BleConnection,
        BleScanRate,
        BleTransport,
        WifiNetworkControl;
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/services.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/toast.dart';
import 'package:grphoto/src/widgets/window_layout.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

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
    required this.background,
    required this.cameraWifi,
    required this.location,
    required this.windowPose,
    required this.phone,
    required this._permission,
    required this._root,
  });

  final AppModels models;
  final FakeGrCamera camera;

  /// The transport the app uses: the camera's, with call counts.
  final CountingTransport ble;
  final RecordingMediaSaver media;

  /// What the app asked the platform to show of its downloads.
  final RecordingBackgroundDownloads background;

  /// What the app asked of the platform's camera Wi-Fi service.
  final RecordingCameraWifiService cameraWifi;

  /// The phone's location service as the app sees it: its access, fixes,
  /// run notice and recorded history are scripted here.
  final FakePhoneLocation location;

  /// What a foldable iPhone says of the app's window: its vertical bar and
  /// its fold. [WindowPose.none], as on any other phone, until a test sets
  /// it (`setDuoWindow` sets it with the window's size and insets).
  final ValueNotifier<WindowPose> windowPose;

  /// The background time the camera layer asked of the OS, and the
  /// leftover camera networks it removed.
  final FakePhoneOs phone;
  final _Permission _permission;
  final Directory _root;
  WidgetTester? _tester;

  /// What the camera environment's Bluetooth permission request answers
  /// (default true).
  bool get bluetoothPermission => _permission.granted;
  set bluetoothPermission(bool granted) => _permission.granted = granted;

  /// Pumps the whole app ([GrPhotoApp]), as `main` runs it.
  Future<void> pumpApp(WidgetTester tester) async {
    _tester = tester;
    await tester.pumpWidget(GrPhotoApp(models: models));
    await tester.pump();
  }

  /// Pumps [home] with the app's scope and theme, without [RootScreen] (so
  /// nothing connects by itself).
  Future<void> pumpWithin(
    WidgetTester tester,
    Widget home, {
    GrColors colors = GrColors.light,
  }) async {
    _tester = tester;
    await tester.pumpWidget(
      AppScope(
        models: models,
        child: MaterialApp(
          theme: grTheme(colors),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => WindowPoseScope(
            pose: windowPose,
            child: ToastHost(child: child!),
          ),
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
      models.geotag.dispose();
      models.connection.dispose();
      await tester.runAsync(camera.close);
      await tester.runAsync(_closePhone);
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
      models.geotag.dispose();
      models.connection.dispose();
      await camera.close();
      await _closePhone();
      await models.debugLog.close();
      await _deleteRoot();
    }
  }

  Future<void> _closePhone() => location.close();

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
/// log cannot open. [saveModel] false saves the camera without its model,
/// as when pairing could not read it.
///
/// [wifiOutlivesApp] makes the phone behave as an iPhone does: the camera
/// network outlives the app, which asks for background time ([FakePhoneOs],
/// giving [backgroundTime]; null for no limit) and removes leftover
/// networks at start-up.
///
/// [location] stands for the phone's location service (by default location
/// is allowed while the app is in use). The saved camera has live and
/// background geotagging as [liveGeotagging] and [backgroundGeotagging]
/// say.
Future<TestApp> createTestApp({
  FakeCameraConfig config = const FakeCameraConfig(),
  bool saveCamera = false,
  bool saveModel = true,
  GrSessionOptions sessionOptions = const GrSessionOptions(),
  BleTransport Function(BleTransport camera)? transport,
  WifiNetworkControl Function(WifiNetworkControl camera)? wifi,
  bool askBeforeWifiJoin = false,
  Stream<void> wifiApprovalShown = const Stream.empty(),
  List<Duration> redialDelays = const [Duration(milliseconds: 20)],
  bool debugLogBlocked = false,
  FakeMediaSource? media,
  FakePhoneLocation? location,
  bool liveGeotagging = false,
  bool backgroundGeotagging = false,
  bool wifiOutlivesApp = false,
  Duration? backgroundTime = const Duration(seconds: 30),
}) async {
  // flutter_test answers every dart:io HttpClient request with 400; the
  // fake camera serves real HTTP on loopback.
  HttpOverrides.global = null;
  MapLibrePlatform.createInstance = _NoMap.new;
  final root = await Directory.systemTemp.createTemp('grphoto_test_');
  final data = await Directory('${root.path}/data').create();
  final cache = await Directory('${root.path}/cache').create();
  final debugLogDir = Directory('${data.path}/debug-log');
  if (debugLogBlocked) await File(debugLogDir.path).writeAsString('');
  final camera = FakeGrCamera(config: config, media: media ?? syntheticMedia());
  await camera.startHttp();
  if (saveCamera) {
    final paired = GrPairedCamera(
      deviceId: config.deviceId,
      serialNumber: config.serial,
      modelName: saveModel ? config.model : null,
      firmwareRevision: config.firmware,
      bluetoothDeviceName: config.bluetoothName,
    );
    final store = await CameraStore.load(data);
    await store.add(
      SavedCamera(
        paired: paired,
        name: SavedCamera.defaultName(paired),
        pairedAt: DateTime(2026, 11, 7, 9, 41),
        liveGeotagging: liveGeotagging,
        backgroundGeotagging: backgroundGeotagging,
      ),
    );
  }
  final permission = _Permission();
  final ble = CountingTransport(
    transport == null ? camera.transport : transport(camera.transport),
  );
  final saver = RecordingMediaSaver();
  final background = RecordingBackgroundDownloads();
  final cameraWifi = RecordingCameraWifiService();
  final phone = location ?? FakePhoneLocation();
  final trace = TraceRelay();
  final windowPose = ValueNotifier(WindowPose.none);
  final os = FakePhoneOs(backgroundTime: backgroundTime);
  final services = AppServices(
    windowPose: windowPose,
    camera: GrCameraEnvironment(
      ble: ble,
      wifi: wifi == null ? camera.wifi : wifi(camera.wifi),
      trace: trace.call,
      httpFactory: camera.httpClient,
      sessionOptions: sessionOptions,
      wifiApprovalShown: wifiApprovalShown,
      ensureBluetoothPermission: () async => permission.granted,
      location: phone,
      wifiOutlivesApp: wifiOutlivesApp,
      beginBackgroundTime: os.beginBackgroundTime,
      forgetLeftoverWifi: os.forgetLeftovers,
    ),
    trace: trace,
    media: saver,
    background: background,
    cameraWifi: cameraWifi,
    clientName: 'GR Photo',
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
    media: saver,
    background: background,
    cameraWifi: cameraWifi,
    location: phone,
    windowPose: windowPose,
    phone: os,
    permission: permission,
    root: root,
  );
}

/// What the camera layer asks of the phone's OS outside Bluetooth and
/// Wi-Fi: background time ([BackgroundTime]) and the removal of camera
/// networks an earlier run left joined.
final class FakePhoneOs {
  new({this.backgroundTime});

  /// What each grant says is left; null for no limit.
  final Duration? backgroundTime;

  /// Grants not yet ended.
  int held = 0;

  /// Grants asked for, ended or not.
  int granted = 0;

  /// Times the leftover networks were removed.
  int leftoverRemovals = 0;

  Future<BackgroundTime> beginBackgroundTime() async {
    granted++;
    held++;
    return BackgroundTime(remaining: backgroundTime, end: () async => held--);
  }

  Future<List<String>> forgetLeftovers() async {
    leftoverRemovals++;
    return const [];
  }
}

/// MapLibre with no native side, which a test does not have: a map is an
/// empty box that is never created, so the app shows what it draws around
/// and over one.
class _NoMap extends MapLibrePlatform {
  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) => const SizedBox.expand();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('A map in a test is never created');
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
  // Not '$finder': that lists what the finder last matched, which for a
  // finder shared between tests are the elements of a test that ended.
  reason: finder.describeMatch(Plurality.many),
  timeout: timeout,
);

/// Taps [finder] once it can receive the tap: route and sheet transitions
/// leave a freshly built widget off-screen for a few frames, and what
/// holds it may still be growing to fit it, so this scrolls it into view
/// on every round until a hit test at its centre reaches it.
Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
  await pumpUntilFound(tester, finder);
  final reachable = finder.hitTestable();
  final watch = Stopwatch()..start();
  while (true) {
    // A route on its way out may still hold another one.
    if (finder.evaluate().length == 1) await tester.ensureVisible(finder);
    await tester.pump();
    if (reachable.evaluate().isNotEmpty) break;
    if (watch.elapsed > const Duration(seconds: 30)) {
      fail('Timed out waiting for $reachable');
    }
    await pumpRounds(tester, 1);
  }
  await tester.tap(finder);
  await tester.pump();
}

/// Whether a tap at [point] reaches a widget [finder] matches: the widget
/// is there, nothing in front of it takes the tap and nothing cuts it off.
bool tapReaches(WidgetTester tester, Offset point, Finder finder) {
  final found = {for (final element in finder.evaluate()) element.renderObject};
  return tester.hitTestOnBinding(point).path.any((entry) {
    for (HitTestTarget? o = entry.target; o is RenderObject; o = o.parent) {
      if (found.contains(o)) return true;
    }
    return false;
  });
}

/// The app leaves the screen (another app in front, or the phone
/// locked), until [comeBackOnScreen] or the end of the test.
void goOffScreen(WidgetTester tester) {
  [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ].forEach(tester.binding.handleAppLifecycleStateChanged);
  addTearDown(() => comeBackOnScreen(tester));
}

/// The app is in front again after [goOffScreen].
void comeBackOnScreen(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.resumed) return;
  [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ].forEach(tester.binding.handleAppLifecycleStateChanged);
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
  Stream<BleAdvertisement> scan({
    List<String> serviceUuids = const [],
    BleScanRate? rate,
  }) {
    scans++;
    StreamSubscription<BleAdvertisement>? sub;
    late final StreamController<BleAdvertisement> controller;
    controller = StreamController<BleAdvertisement>(
      onListen: () {
        scanning++;
        sub = _inner
            .scan(serviceUuids: serviceUuids, rate: rate)
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

/// Records what the app asks of the platform's camera Wi-Fi service instead
/// of asking it; [pressDisconnect] stands for the notification's button.
final class RecordingCameraWifiService implements CameraWifiService {
  final _disconnects = StreamController<void>.broadcast(sync: true);

  /// What the service shows while held; null when it is not.
  CameraWifiNotice? held;

  /// How long the phone is kept awake, as last asked.
  Duration awake = Duration.zero;

  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  Future<void> hold(CameraWifiNotice notice) async => held = notice;

  @override
  Future<void> keepAwake(Duration duration) async => awake = duration;

  @override
  Future<void> release() async {
    held = null;
    awake = Duration.zero;
  }

  void pressDisconnect() => _disconnects.add(null);
}

/// Records what the app shows of its downloads outside itself instead of
/// asking the platform; [press] stands for a button there.
final class RecordingBackgroundDownloads implements BackgroundDownloads {
  final _actions = StreamController<BackgroundDownloadAction>.broadcast(
    sync: true,
  );

  /// Every status shown, oldest first.
  final List<BackgroundDownloadStatus> shown = [];

  /// What the platform shows now; null when nothing.
  BackgroundDownloadStatus? current;

  /// Runs when the background work ends ([hide], or [show] paused), before
  /// it is recorded.
  VoidCallback? onEnd;

  /// The `finished` of every [hide], oldest first.
  final List<bool> hides = [];

  /// Whether iOS's continued processing task runs, as a test sets it.
  final ValueNotifier<bool> continuedTask = ValueNotifier(false);

  @override
  Stream<BackgroundDownloadAction> get actions => _actions.stream;

  @override
  ValueListenable<bool> get continued => continuedTask;

  /// The user presses [action] on the platform's display.
  void press(BackgroundDownloadAction action) => _actions.add(action);

  @override
  Future<void> show(BackgroundDownloadStatus status) async {
    if (status.paused) onEnd?.call();
    shown.add(status);
    current = status;
  }

  @override
  Future<void> hide({required bool finished}) async {
    onEnd?.call();
    hides.add(finished);
    current = null;
  }
}

final class _Permission {
  bool granted = true;
}
