import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../data/cameras.dart';

/// What the scan says about one paired camera.
enum Presence {
  /// Not advertising, or not since [CameraPresence.forgetAfter].
  away,

  /// Advertising; its power state is unknown.
  nearby,

  /// Advertising as switched off: Connect wakes it.
  nearbyOff,

  /// Advertising as switched on.
  nearbyOn,
}

/// Which paired cameras are nearby and switched on, from their Bluetooth
/// advertisements while the Cameras screen scans.
final class CameraPresence extends ChangeNotifier {
  CameraPresence(
    this._transport, {
    this.forgetAfter = const Duration(seconds: 10),
    this.settleAfter = const Duration(seconds: 4),
  });

  final BleTransport _transport;

  /// A camera that has not advertised for this long is away again.
  final Duration forgetAfter;

  /// How long a scan runs before a camera it has not seen counts as away
  /// rather than not looked for yet.
  final Duration settleAfter;

  /// Last advertisement per device id and per advertised serial.
  final Map<String, ({DateTime at, bool? powerOn})> _seen = {};
  StreamSubscription<BleAdvertisement>? _scan;
  Timer? _prune;
  Timer? _settle;
  bool _settled = false;
  Object? _error;
  bool _disposed = false;

  bool get scanning => _scan != null;

  /// The scan has run long enough that a camera it has not seen is away.
  bool get settled => _settled;

  /// Why the last scan stopped (Bluetooth off, platform error).
  Object? get error => _error;

  /// What the scan says about [camera]: matched by advertised serial, or
  /// by device id for packets that carry no Ricoh data.
  Presence of(SavedCamera camera) {
    final seen = _seen[camera.serial] ?? _seen[camera.paired.deviceId];
    if (seen == null) return Presence.away;
    return switch (seen.powerOn) {
      true => Presence.nearbyOn,
      false => Presence.nearbyOff,
      null => Presence.nearby,
    };
  }

  void start() {
    if (_scan != null || _disposed) return;
    _error = null;
    _scan = _transport.scan().listen(
      _onAdvertisement,
      onError: (Object e) {
        _error = e;
        unawaited(stop());
      },
      onDone: () => unawaited(stop()),
    );
    _prune = Timer.periodic(const Duration(seconds: 2), (_) => _forgetOld());
    _settle = Timer(settleAfter, () {
      _settled = true;
      _notify();
    });
    _notify();
  }

  /// Stops scanning, as connecting or another screen's scan needs. What
  /// was seen is kept until it is old.
  Future<void> stop() async {
    final cancelling = _scan?.cancel();
    _scan = null;
    _prune?.cancel();
    _prune = null;
    _settle?.cancel();
    _settle = null;
    _settled = false;
    _notify();
    await cancelling;
  }

  void _onAdvertisement(BleAdvertisement raw) {
    final ad = GrAdvertisement(raw);
    final now = DateTime.now();
    var changed = false;
    void see(String key) {
      final previous = _seen[key];
      // Scan responses often lack the Ricoh payload the primary had.
      final powerOn = ad.powerOn ?? ad.powerOnFromServices ?? previous?.powerOn;
      _seen[key] = (at: now, powerOn: powerOn);
      changed |= previous == null || previous.powerOn != powerOn;
    }

    see(ad.deviceId);
    if (ad.serialText case final serial?) see(serial);
    if (changed) _notify();
  }

  void _forgetOld() {
    final cutoff = DateTime.now().subtract(forgetAfter);
    final before = _seen.length;
    _seen.removeWhere((_, v) => v.at.isBefore(cutoff));
    if (_seen.length != before) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
