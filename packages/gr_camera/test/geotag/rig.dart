import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

/// Metres in one degree of latitude.
const metresPerDegree = 111195.08;

/// A paired GR IV that is on, with Store Location Info on.
const cameraOn = FakeCameraConfig(bonded: true, storeLocationInfo: true);

/// A paired GR IV that is off, with Store Location Info on. A link to it
/// stays up until the test drops it.
const cameraOff = FakeCameraConfig(
  bonded: true,
  poweredOn: false,
  storeLocationInfo: true,
);

/// A [CameraSession] with a simulated GR IV and a simulated phone's
/// location service, in the test binding's fake time, which `clock`
/// follows. Some stream cancellations complete in the real event loop, so
/// [advance] lets that run between fake steps.
final class GeotagRig {
  new _(this._tester, this.camera, this.phone, this.session, this.trace);

  /// A session with [config]'s camera, linked over Bluetooth unless
  /// [link] is false, on a phone whose location may be used as [access]
  /// says.
  static Future<GeotagRig> start(
    WidgetTester tester, {
    FakeCameraConfig config = cameraOn,
    LocationAccess access = FakePhoneLocation.whileInUse,
    bool link = true,
  }) async {
    final camera = FakeGrCamera(config: config, media: syntheticMedia());
    final phone = FakePhoneLocation(access: access);
    final trace = <TraceEvent>[];
    final session = CameraSession(
      GrCameraEnvironment(
        ble: camera.transport,
        wifi: camera.wifi,
        trace: trace.add,
        location: phone,
      ),
      consent: WifiConsent(
        ask: (_) async => true,
        askAgain: (_) async => false,
        cameraApproved: () => true,
        joined: () async {},
      ),
    );
    final rig = GeotagRig._(tester, camera, phone, session, trace);
    rig._events = session.events.listen((e) => rig.sessionEvents.add(e.kind));
    rig.geotagging.addListener(rig._onChanged);
    rig._fixes = rig.geotagging.fixes.listen(rig.fixes.add);
    rig._written = rig.geotagging.storeLocationInfoWritten.listen(
      rig.settingWritten.add,
    );
    if (link) await rig.link();
    return rig;
  }

  final WidgetTester _tester;

  /// The simulated camera.
  final FakeGrCamera camera;

  /// The simulated phone's location service, under the environment's
  /// tracing.
  final FakePhoneLocation phone;

  /// The session under test.
  final CameraSession session;

  /// Everything the camera layer traced.
  final List<TraceEvent> trace;

  /// The kind of every session event, in order.
  final sessionEvents = <String>[];

  /// Every status [geotagging] notified, in order, without repeats.
  final statuses = <GeotagStatus>[];

  /// How often [geotagging] notified its listeners.
  int notifications = 0;

  /// How often a Stop on the notice was handed to the default handler of
  /// [apply].
  int stops = 0;

  /// Every position [CameraGeotagging.fixes] emitted.
  final fixes = <LocationFix>[];

  /// Every value [CameraGeotagging.storeLocationInfoWritten] emitted.
  final settingWritten = <bool>[];

  late final StreamSubscription<GrSessionEvent> _events;
  late final StreamSubscription<LocationFix> _fixes;
  late final StreamSubscription<bool> _written;

  /// The session's live geotagging.
  CameraGeotagging get geotagging => session.geotagging;

  /// What live geotagging is doing now.
  GeotagStatus get status => geotagging.status;

  /// Every position the camera accepted.
  List<FakeCameraLocation> get writes => camera.locationWrites;

  void _onChanged() {
    notifications++;
    if (statuses.lastOrNull != status) statuses.add(status);
  }

  /// Links the camera over Bluetooth and lets the first readings finish.
  Future<void> link() async {
    unawaited(
      session.connectBluetooth(
        deviceId: camera.config.deviceId,
        serial: camera.config.serial,
      ),
    );
    await until(() => session.bleLinked, reason: 'the Bluetooth link');
    await advance(const Duration(seconds: 1));
  }

  /// Gives the session's geotagging its settings, with a notice whose
  /// text is the status's name, and lets what follows finish.
  Future<void> configure({
    bool live = true,
    bool syncClock = true,
    bool? pending,
    Future<void> Function()? onStopped,
  }) async {
    apply(
      live: live,
      syncClock: syncClock,
      pending: pending,
      onStopped: onStopped,
    );
    await advance(const Duration(seconds: 1));
  }

  /// [configure] without letting time pass, as the app does from inside a
  /// callback. Without [onStopped] a Stop on the notice only counts in
  /// [stops]: the setting stays as it is.
  void apply({
    bool live = true,
    bool syncClock = true,
    bool? pending,
    Future<void> Function()? onStopped,
  }) => geotagging.configure(
    GeotagSettings(
      live: live,
      syncClock: syncClock,
      storeLocationInfoPending: pending,
    ),
    notice: (status) => LocationRunNotice(
      run: '1234567',
      title: 'GR IV',
      text: status.name,
      stopLabel: 'Stop',
      channel: 'Geotagging',
    ),
    onStopped: onStopped ?? () async => stops++,
  );

  /// A position taken now, less [age], [north] metres north of the
  /// made-up place the tests are at.
  LocationFix fix({
    double north = 0,
    double accuracy = 10,
    Duration age = Duration.zero,
    double? altitude,
  }) => LocationFix(
    latitude: 35 + north / metresPerDegree,
    longitude: 139,
    accuracy: accuracy,
    time: clock.now().subtract(age),
    altitude: altitude,
  );

  /// The phone takes [fix]; lets a write of it finish.
  Future<void> emit(LocationFix fix) async {
    phone.emitFix(fix);
    await advance(const Duration(milliseconds: 300));
  }

  /// Lets [duration] of fake time pass, in steps of [step].
  Future<void> advance(
    Duration duration, {
    Duration step = const Duration(milliseconds: 100),
  }) async {
    for (var t = Duration.zero; t < duration; t += step) {
      await _tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _tester.pump(step);
    }
  }

  /// Lets fake time pass until it is [time], in steps of [step].
  Future<void> advanceTo(
    DateTime time, {
    Duration step = const Duration(milliseconds: 100),
  }) => advance(time.difference(clock.now()), step: step);

  /// Lets fake time pass until [condition] holds; fails after [timeout].
  Future<void> until(
    bool Function() condition, {
    String reason = 'the condition',
    Duration timeout = const Duration(minutes: 2),
  }) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; !condition(); t += step) {
      if (t >= timeout) fail('Timed out waiting for $reason');
      await advance(step);
    }
  }

  /// Lets fake time pass until [future] ends; returns its value.
  Future<T> wait<T>(Future<T> future) async {
    var done = false;
    // Its error is the caller's, once the wait is over.
    final outcome = future.whenComplete(() => done = true)..ignore();
    await until(() => done, reason: 'the call to end');
    return await outcome;
  }

  /// The fields of every `geotag.…` or `clock.…` decision traced as
  /// [kind].
  List<Map<String, Object?>> decisions(String kind) => [
    for (final e in trace)
      if (e.channel == TraceChannel.session && e.kind == kind) e.fields,
  ];

  /// Why each position that was not written was skipped, in order.
  List<Object?> get skips => [
    for (final fields in decisions('geotag.skipped')) fields['reason'],
  ];

  /// The kind of every `geotag.…` and `clock.…` decision traced, in
  /// order.
  List<String> get steps => [
    for (final e in trace)
      if (e.channel == TraceChannel.session &&
          (e.kind.startsWith('geotag.') || e.kind.startsWith('clock.')))
        e.kind,
  ];

  /// How many Bluetooth links the session has made.
  int get links => sessionEvents.where((kind) => kind == 'ble.ready').length;

  /// The catalog key of every characteristic written over Bluetooth, in
  /// order.
  List<Object?> get gattWrites => [
    for (final e in trace)
      if (e.channel == TraceChannel.ble && e.kind == 'gatt.write')
        e.fields['key'],
  ];

  /// Every read and write of GEO Tag (`geotag`), GPS Information (`gps`)
  /// and Date Time (`date-time`) on the Bluetooth link, in order, as
  /// `read geotag`, `write gps` and so on.
  List<String> get asked => [
    for (final e in trace)
      if (e.channel == TraceChannel.ble &&
          const {'gatt.read', 'gatt.write'}.contains(e.kind) &&
          const {'geotag', 'gps', 'date-time'}.contains(e.fields['key']))
        '${e.kind.substring(5)} ${e.fields['key']}',
  ];

  /// Ends the session and the camera and lets their timers run out.
  Future<void> close() async {
    var closed = false;
    unawaited(session.close().whenComplete(() => closed = true));
    await until(() => closed, reason: 'the session to close');
    geotagging.removeListener(_onChanged);
    unawaited(_events.cancel());
    unawaited(_fixes.cancel());
    unawaited(_written.cancel());
    await _tester.runAsync(camera.close);
    unawaited(phone.close());
    await advance(const Duration(minutes: 2), step: const Duration(seconds: 1));
  }
}
