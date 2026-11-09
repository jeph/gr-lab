import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// What the last advertisements said about one camera.
@immutable
final class CameraSighting {
  /// A sighting with the advertised power state.
  const new({required this.powerOn});

  /// Camera is on, per the advertised power tag; null when the
  /// advertisements do not say.
  final bool? powerOn;
}

/// Which paired cameras are nearby and switched on, from their Bluetooth
/// advertisements while it scans.
final class PresenceScanner extends ChangeNotifier {
  /// A scanner on [camera]'s Bluetooth.
  new(
    GrCameraEnvironment camera, {
    this.forgetAfter = const Duration(seconds: 15),
    this.settleAfter = const Duration(seconds: 8),
  }) : _transport = camera.ble;

  final BleTransport _transport;

  /// A camera that has not advertised for this long is away again.
  final Duration forgetAfter;

  /// How long a scan runs before a camera it has not seen counts as away
  /// rather than not looked for yet.
  final Duration settleAfter;

  /// Last advertisement per device id, with the serial a Ricoh payload of
  /// that device carried.
  final Map<String, ({DateTime at, bool? powerOn, int? serial})> _seen = {};
  StreamSubscription<BleAdvertisement>? _scan;
  Timer? _prune;
  Timer? _settle;
  bool _settled = false;
  Object? _error;
  bool _disposed = false;

  /// A scan is running.
  bool get scanning => _scan != null;

  /// The scan has run long enough that a camera it has not seen is away.
  bool get settled => _settled;

  /// Why the last scan stopped (Bluetooth off, platform error).
  Object? get error => _error;

  /// The camera paired as [deviceId] with [serial], when it advertised
  /// lately: matched by device id or by advertised serial (compared as a
  /// number, as the session does: the paired serial is the camera's text,
  /// the advert carries an integer).
  CameraSighting? sighting({required String deviceId, required String serial}) {
    final seen =
        _seen[deviceId] ??
        _seen.values
            .where((s) => grSerialMatches(serial, s.serial))
            .firstOrNull;
    return seen == null ? null : CameraSighting(powerOn: seen.powerOn);
  }

  /// Starts scanning, clearing [error]; does nothing while scanning or
  /// after dispose.
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
    final previous = _seen[ad.deviceId];
    // Scan responses often lack the Ricoh payload the primary had.
    final powerOn = ad.powerOn ?? ad.powerOnFromServices ?? previous?.powerOn;
    final serial = ad.serialNumber ?? previous?.serial;
    _seen[ad.deviceId] = (at: DateTime.now(), powerOn: powerOn, serial: serial);
    if (previous == null ||
        previous.powerOn != powerOn ||
        previous.serial != serial) {
      _notify();
    }
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
