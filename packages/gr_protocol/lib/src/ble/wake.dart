import 'dart:async';

import 'package:gr_protocol/src/ble/advertising.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:gr_protocol/src/trace.dart';

/// GR WORLD never reconnects within 6 s of seeing the camera power off
/// (ble.md §Turning the camera's Wi-Fi on, path B, 0xd2f2c0).
const grWorldPowerOffReconnectGuard = Duration(seconds: 6);

/// Waits until [guard] has passed since [poweredOffAt]; returns how long it
/// waited (zero when the guard had already elapsed).
Future<Duration> waitAfterPowerOff(
  DateTime poweredOffAt, {
  Duration guard = grWorldPowerOffReconnectGuard,
  TraceSink? trace,
}) async {
  final remaining = guard - DateTime.now().difference(poweredOffAt);
  final wait = remaining > Duration.zero ? remaining : Duration.zero;
  trace?.call(
    TraceEvent(
      channel: TraceChannel.ble,
      direction: TraceDirection.internal,
      kind: 'powerOffGuard',
      fields: {
        'poweredOffAt': poweredOffAt.toUtc().toIso8601String(),
        'guardMs': guard.inMilliseconds,
        'waitMs': wait.inMilliseconds,
      },
    ),
  );
  if (wait > Duration.zero) await Future<void>.delayed(wait);
  return wait;
}

/// True when [wanted] (a serial string as printed on the camera or by
/// `scan`) names the advertised tag-02 serial. The advert carries the
/// serial's digits as an integer (research/camera-models.md §4.1), so only
/// the digits of [wanted] are compared.
bool grSerialMatches(String wanted, int? advertised) {
  if (advertised == null) return false;
  final digits = wanted.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return false;
  return int.tryParse(digits) == advertised;
}

/// Scans until an advertisement satisfies [where] or [timeout] passes
/// (null). The scan stops before this returns.
Future<GrAdvertisement?> findGrAdvertisement(
  BleTransport transport, {
  required bool Function(GrAdvertisement ad) where,
  required Duration timeout,
  List<String> serviceUuids = const [],
}) async {
  final found = Completer<GrAdvertisement?>();
  final timer = Timer(timeout, () {
    if (!found.isCompleted) found.complete(null);
  });
  final sub = transport
      .scan(serviceUuids: serviceUuids)
      .listen(
        (ad) {
          if (found.isCompleted) return;
          final g = GrAdvertisement(ad);
          if (where(g)) found.complete(g);
        },
        onError: (Object e, StackTrace st) {
          if (!found.isCompleted) found.completeError(e, st);
        },
      );
  try {
    return await found.future;
  } finally {
    timer.cancel();
    await sub.cancel();
  }
}

/// How [wakeCamera] ended.
enum GrWakeOutcome {
  /// The camera already advertised power on (tag 03 = 1); nothing was done.
  alreadyOn,

  /// After the wake connection, the camera advertised power on.
  wokeUp,

  /// No matching camera advertisement with a power tag was found.
  notFound,

  /// The wake connection itself failed.
  connectFailed,

  /// The wake connection succeeded but no power-on advertisement followed.
  noPowerOnAdvertisement,
}

/// Observed wake sequence with timings relative to the start.
final class GrWakeResult {
  /// Creates a result; [wakeCamera] fills it as the sequence runs.
  const new({
    required this.outcome,
    required this.startedAt,
    required this.notes,
    this.offAdvertisement,
    this.onAdvertisement,
    this.offAdvertisementAfter,
    this.connectedAfter,
    this.linkDroppedAfter,
    this.dropTimedOut = false,
    this.dropReason,
    this.onAdvertisementAfter,
    this.error,
  });

  /// How the wake ended.
  final GrWakeOutcome outcome;

  /// Local time the wake started; every duration is relative to it.
  final DateTime startedAt;

  /// First advertisement found with tag 03 = 0 (power off), if any.
  final GrAdvertisement? offAdvertisement;

  /// Advertisement with tag 03 = 1 (power on), seen at the start or after
  /// the wake connection.
  final GrAdvertisement? onAdvertisement;

  /// When the first matching advertisement was seen: [offAdvertisement],
  /// or [onAdvertisement] when the camera was already on.
  final Duration? offAdvertisementAfter;

  /// When the bare wake connection was established; null if it was not.
  final Duration? connectedAfter;

  /// When the camera dropped the wake link; null if it did not.
  final Duration? linkDroppedAfter;

  /// The camera kept the link for the whole drop timeout; the wake
  /// continued anyway, as Image Sync does.
  final bool dropTimedOut;

  /// Disconnect reason the platform reported for the drop, if any.
  final String? dropReason;

  /// When the power-on advertisement after the wake connection was seen.
  final Duration? onAdvertisementAfter;

  /// Wake connection or power-on scan failure, if any.
  final String? error;

  /// Human-readable remarks on what happened at each step.
  final List<String> notes;

  /// True when the camera is on now ([GrWakeOutcome.alreadyOn] or
  /// [GrWakeOutcome.wokeUp]).
  bool get succeeded =>
      outcome == GrWakeOutcome.alreadyOn || outcome == GrWakeOutcome.wokeUp;

  /// Device to connect to now (the power-on advertiser).
  String? get deviceId =>
      onAdvertisement?.deviceId ?? offAdvertisement?.deviceId;

  /// Diagnostic JSON with every field; durations in milliseconds.
  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'offAdvertisement': offAdvertisement?.toJson(),
    'onAdvertisement': onAdvertisement?.toJson(),
    'offAdvertisementAfterMs': offAdvertisementAfter?.inMilliseconds,
    'connectedAfterMs': connectedAfter?.inMilliseconds,
    'linkDroppedAfterMs': linkDroppedAfter?.inMilliseconds,
    'dropTimedOut': dropTimedOut,
    'dropReason': dropReason,
    'onAdvertisementAfterMs': onAdvertisementAfter?.inMilliseconds,
    'error': error,
    'notes': notes,
  };
}

/// Powers a camera on from its BT-only "off" state the way Image Sync does
/// (research/protocol/ble-imagesync.md §2), with continuous rescanning instead
/// of Image Sync's 10 s polling:
///
/// 1. Scan for a GR advertisement (matching [serial] or [deviceId] when
///    given) that carries the power tag. Tag 03 = 1 →
///    [GrWakeOutcome.alreadyOn].
/// 2. Tag 03 = 0: open a bare GATT connection (no discovery, bonding or
///    writes) with [connectTimeout] (Image Sync: 10 s).
/// 3. Wait up to [dropTimeout] (Image Sync: 30 s) for the camera to drop
///    the link. On timeout, note it, disconnect, and continue.
/// 4. Meanwhile scan continuously for tag 03 = 1 from the same serial (or
///    the same device id when the off advert had no serial), up to
///    [powerOnTimeout] after the connection.
///
/// Whether GR IV wakes this way is unconfirmed (ble.md §Camera power off).
/// Every step is traced as `wake.*` events.
Future<GrWakeResult> wakeCamera(
  BleTransport transport, {
  String? serial,
  String? deviceId,
  Duration findTimeout = const Duration(seconds: 20),
  Duration connectTimeout = const Duration(seconds: 10),
  Duration dropTimeout = const Duration(seconds: 30),
  Duration powerOnTimeout = const Duration(seconds: 60),
  TraceSink? trace,
}) async {
  final startedAt = DateTime.now();
  final clock = Stopwatch()..start();
  final notes = <String>[];

  void step(String kind, [Map<String, Object?> fields = const {}]) {
    trace?.call(
      TraceEvent(
        channel: TraceChannel.ble,
        direction: TraceDirection.internal,
        kind: 'wake.$kind',
        fields: {'elapsedMs': clock.elapsedMilliseconds, ...fields},
      ),
    );
  }

  bool target(GrAdvertisement a) {
    if (!a.isGrCamera || a.powerOn == null) return false;
    if (deviceId != null && a.deviceId != deviceId) return false;
    if (serial != null && !grSerialMatches(serial, a.serialNumber)) {
      return false;
    }
    return true;
  }

  step('start', {
    'serial': serial,
    'deviceId': deviceId,
    'findTimeoutMs': findTimeout.inMilliseconds,
    'connectTimeoutMs': connectTimeout.inMilliseconds,
    'dropTimeoutMs': dropTimeout.inMilliseconds,
    'powerOnTimeoutMs': powerOnTimeout.inMilliseconds,
  });

  final off = await findGrAdvertisement(
    transport,
    where: target,
    timeout: findTimeout,
  );
  if (off == null) {
    step('notFound');
    return GrWakeResult(
      outcome: GrWakeOutcome.notFound,
      startedAt: startedAt,
      notes: notes,
    );
  }
  final offAfter = clock.elapsed;
  step('advertisement', off.toJson());
  if (off.powerOn == true) {
    step('alreadyOn');
    return GrWakeResult(
      outcome: GrWakeOutcome.alreadyOn,
      startedAt: startedAt,
      notes: notes,
      onAdvertisement: off,
      offAdvertisementAfter: offAfter,
    );
  }

  final offSerial = off.serialNumber;
  bool poweredOn(GrAdvertisement a) {
    if (!a.isGrCamera || a.powerOn != true) return false;
    return offSerial != null
        ? a.serialNumber == offSerial
        : a.deviceId == off.deviceId;
  }

  step('connect', {'deviceId': off.deviceId});
  final BleConnection connection;
  try {
    connection = await transport.connect(off.deviceId, timeout: connectTimeout);
  } on BleException catch (e) {
    step('connectFailed', {'error': '$e'});
    return GrWakeResult(
      outcome: GrWakeOutcome.connectFailed,
      startedAt: startedAt,
      notes: notes,
      offAdvertisement: off,
      offAdvertisementAfter: offAfter,
      error: '$e',
    );
  }
  final connectedAfter = clock.elapsed;
  step('connected');

  Duration? onAfter;
  final onSearch =
      findGrAdvertisement(
        transport,
        where: poweredOn,
        timeout: powerOnTimeout,
      ).then<({GrAdvertisement? ad, Object? error})>((ad) {
        if (ad != null) {
          onAfter = clock.elapsed;
          step('powerOnAdvertisement', ad.toJson());
        }
        return (ad: ad, error: null);
      }, onError: (Object e) => (ad: null, error: e));

  Duration? droppedAfter;
  String? dropReason;
  var dropTimedOut = false;
  try {
    final drop = await connection.disconnected.timeout(dropTimeout);
    droppedAfter = clock.elapsed;
    dropReason = drop.reason;
    step('linkDropped', {'requested': drop.requested, 'reason': drop.reason});
  } on TimeoutException {
    dropTimedOut = true;
    notes.add(
      'camera kept the link for ${dropTimeout.inSeconds} s; disconnected '
      'and kept scanning, as Image Sync continues after its 30 s wait',
    );
    step('dropTimeout');
    try {
      await connection.disconnect();
    } on BleException catch (e) {
      notes.add('disconnect after drop timeout failed: $e');
    }
  }

  final on = await onSearch;
  if (on.error != null) notes.add('power-on scan failed: ${on.error}');
  final outcome = on.ad == null
      ? GrWakeOutcome.noPowerOnAdvertisement
      : GrWakeOutcome.wokeUp;
  final onAt = onAfter;
  final dropAt = droppedAfter;
  if (onAt != null && dropAt != null && onAt < dropAt) {
    notes.add('power-on advertisement arrived before the link dropped');
  }
  step('done', {'outcome': outcome.name});
  return GrWakeResult(
    outcome: outcome,
    startedAt: startedAt,
    notes: notes,
    offAdvertisement: off,
    onAdvertisement: on.ad,
    offAdvertisementAfter: offAfter,
    connectedAfter: connectedAfter,
    linkDroppedAfter: droppedAfter,
    dropTimedOut: dropTimedOut,
    dropReason: dropReason,
    onAdvertisementAfter: onAfter,
    error: on.error?.toString(),
  );
}
