import 'dart:async';

import 'package:clock/clock.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_camera/src/nearby.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// One attempt to pair [target], a camera on Execute Pairing picked from a
/// [NearbyScanner]. Create the run, then [start] it; [cancel] stops it at
/// whatever stage it is in, and the user can start a new run.
///
/// Pairing never retries by itself: camera firmware deletes the entry of a
/// device that requests pairing outside Execute Pairing
/// (research/protocol/firmware-bonding.md §2). A new run waits until
/// [bondInterval] has passed since this phone's last bond attempt with the
/// same camera ([nextAttemptAt]).
final class PairingRun {
  /// A run pairing [target] over [camera]'s Bluetooth as [clientName].
  new(
    GrCameraEnvironment camera, {
    required this.target,
    required this.clientName,
  }) : _camera = camera,
       _transport = _CancellableTransport(
         camera.ble,
         // Without a serial, pairCamera would match any GR nearby.
         onlyDeviceId: target.serial == null ? target.deviceId : null,
       );

  /// The shortest time between two bond attempts with one camera. A GR IV
  /// answered attempts 3 s apart with SMP Pairing Failed reason 9
  /// (Repeated Attempts) and then refused pairing; attempts 15 s apart
  /// paired (research/protocol/ble.md, "Camera-side pairing and reconnect
  /// rules"; GR IV HDF fw 1.20, 2026-11-07).
  static const bondInterval = Duration(seconds: 15);

  /// When each camera, by device id, last had a bond attempt from this
  /// phone: the confirmation stage starting, and again when the run that
  /// reached it ended.
  static final _bondAttempts = Expando<Map<String, DateTime>>();

  /// When a run may next ask [target] to pair, [bondInterval] after the
  /// last bond attempt with it through [camera]; null when one may start
  /// now. A run started earlier waits until then before it scans.
  static DateTime? nextAttemptAt(
    GrCameraEnvironment camera,
    NearbyCamera target,
  ) {
    final last = _bondAttempts[camera]?[target.deviceId];
    if (last == null) return null;
    final next = last.add(bondInterval);
    return next.isAfter(clock.now()) ? next : null;
  }

  /// Camera to pair, as the scan saw it.
  final NearbyCamera target;

  /// Written to the camera's Paired Devices list.
  final String clientName;
  final GrCameraEnvironment _camera;
  final _CancellableTransport _transport;
  bool _started = false;

  /// [cancel] was called.
  bool get cancelled => _transport.cancelled;

  /// Pairs and returns what to save; reports progress to [onStage]. The
  /// pairing link is closed before this completes, so a session can open
  /// its own. Throws [GrPairingException] (or a Bluetooth error) when
  /// pairing fails, and an error when the run was cancelled.
  Future<GrPairedCamera> start({
    void Function(GrPairingStage stage)? onStage,
  }) async {
    if (_started) throw StateError('PairingRun.start called twice');
    _started = true;
    await _waitForBondInterval();
    var bonding = false;
    try {
      final pairing = await pairCamera(
        _transport,
        clientName: clientName,
        serial: target.serial,
        onStage: (stage) {
          // pairCamera requests the bond right after this stage starts.
          if (stage == GrPairingStage.awaitingConfirmation) {
            bonding = true;
            _recordBondAttempt();
          }
          onStage?.call(stage);
        },
        trace: _camera.trace,
      );
      // A session opens its own link; the camera may not accept a second
      // one while this stays open.
      try {
        await pairing.client.connection.disconnect();
      } on Object {
        // Already dropped.
      }
      return pairing.camera;
    } finally {
      // The camera counts from the end of a failed attempt as well.
      if (bonding) _recordBondAttempt();
    }
  }

  /// Fails the run's scan and drops every link it opened.
  Future<void> cancel() => _transport.cancel();

  void _recordBondAttempt() {
    (_bondAttempts[_camera] ??= {})[target.deviceId] = clock.now();
  }

  /// Waits until [nextAttemptAt]; [cancel] ends the wait and the run.
  Future<void> _waitForBondInterval() async {
    final at = nextAttemptAt(_camera, target);
    if (at == null) return;
    final wait = at.difference(clock.now());
    _camera.event('pair.bondWait', {
      'deviceId': target.deviceId,
      'waitMs': wait.inMilliseconds,
    });
    final waited = Completer<void>();
    final timer = Timer(wait, waited.complete);
    await Future.any([waited.future, _transport.whenCancelled]);
    timer.cancel();
    if (cancelled) throw _CancellableTransport._cancelledError;
  }
}

/// Wraps the shared transport for one `pairCamera` run so the user can
/// cancel it: `pairCamera` has no cancellation of its own, so [cancel]
/// fails the scan and drops every link the run opened, which makes the run
/// end with an error at whatever stage it is in.
///
/// [onlyDeviceId] restricts the run's scan to one peripheral, for a camera
/// picked from an advertisement without a serial number (which
/// `pairCamera` would otherwise match against any GR nearby).
final class _CancellableTransport implements BleTransport {
  new(this._inner, {this.onlyDeviceId});

  final BleTransport _inner;
  final String? onlyDeviceId;
  final List<StreamController<BleAdvertisement>> _scans = [];
  final List<BleConnection> _connections = [];
  final Completer<void> _cancel = Completer();

  bool get cancelled => _cancel.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancel.future;

  static const _cancelledError = BleException(
    BleErrorCode.transport,
    'pairing cancelled',
  );

  @override
  Future<BleAdapterState> adapterState() => _inner.adapterState();

  @override
  Stream<BleAdvertisement> scan({
    List<String> serviceUuids = const [],
    BleScanRate? rate,
  }) {
    if (cancelled) return Stream.error(_cancelledError);
    StreamSubscription<BleAdvertisement>? upstream;
    late final StreamController<BleAdvertisement> controller;
    controller = StreamController<BleAdvertisement>(
      onListen: () {
        upstream = _inner
            .scan(serviceUuids: serviceUuids, rate: rate)
            .listen(
              (ad) {
                final only = onlyDeviceId;
                if (only == null || ad.deviceId == only) controller.add(ad);
              },
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () async {
        _scans.remove(controller);
        await upstream?.cancel();
      },
    );
    _scans.add(controller);
    return controller.stream;
  }

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    if (cancelled) throw _cancelledError;
    final connection = await _inner.connect(deviceId, timeout: timeout);
    if (cancelled) {
      // Closes the link only if nobody was handed it since: a retry or the
      // session restored after cancelling may already be using it
      // (`UniversalBleTransport.connect`).
      await connection.disconnect();
      throw _cancelledError;
    }
    _connections.add(connection);
    return connection;
  }

  /// The shared transport outlives a pairing run.
  @override
  Future<void> close() async {}

  Future<void> cancel() async {
    if (cancelled) return;
    _cancel.complete();
    for (final scan in List.of(_scans)) {
      scan.addError(_cancelledError);
    }
    for (final connection in _connections) {
      try {
        await connection.disconnect();
      } on Object {
        // The link may already be gone; dropping it is all cancel needs.
      }
    }
  }
}

/// [name] as GR WORLD writes a phone's name to the camera's Paired Devices
/// list: U+0020..U+007E and U+3000 kept, other characters replaced with
/// `?`, at most 32 characters, trimmed; "Unknown" when nothing is left.
String pairedDeviceName(String name) =>
    GrBleClient.sanitizePairedDeviceName(name);
