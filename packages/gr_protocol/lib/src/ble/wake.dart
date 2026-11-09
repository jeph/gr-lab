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
