import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// A GR camera seen in the scan, merged across its advertisements.
@immutable
final class NearbyCamera {
  const NearbyCamera({
    required this.deviceId,
    required this.model,
    required this.serial,
    required this.bluetoothName,
    required this.powerOn,
  });

  final String deviceId;
  final GrModel model;

  /// Seven-digit serial as printed on the camera, when advertised.
  final String? serial;

  /// Advertised local name (`GR_XXXXXX`), when a packet carried it.
  final String? bluetoothName;

  /// Null when the advertisement does not say.
  final bool? powerOn;

  String get key => serial ?? deviceId;
}

/// Lists GR cameras advertising nearby. The model, serial and power state
/// come from the Ricoh manufacturer data, so nobody picks a model by hand.
final class NearbyScanner extends ChangeNotifier {
  NearbyScanner(this._transport);

  final BleTransport _transport;
  final Map<String, NearbyCamera> _cameras = {};
  StreamSubscription<BleAdvertisement>? _scan;
  Object? _error;
  bool _disposed = false;

  /// In the order they were first seen, so rows do not jump around.
  List<NearbyCamera> get cameras => List.unmodifiable(_cameras.values);

  /// Why the scan stopped (Bluetooth turned off, platform error).
  Object? get error => _error;
  bool get scanning => _scan != null;

  void start() {
    if (_scan != null) return;
    _error = null;
    _scan = _transport.scan().listen(
      _onAdvertisement,
      onError: (Object e) {
        _error = e;
        unawaited(stop());
      },
      onDone: () => unawaited(stop()),
    );
    notifyListeners();
  }

  Future<void> stop() async {
    final cancelling = _scan?.cancel();
    _scan = null;
    if (!_disposed) notifyListeners();
    await cancelling;
  }

  void _onAdvertisement(BleAdvertisement raw) {
    final ad = GrAdvertisement(raw);
    final model = ad.model;
    if (model == null) return;
    final serial = ad.serialText;
    final key = serial ?? ad.deviceId;
    final previous = _cameras[key];
    final next = NearbyCamera(
      deviceId: ad.deviceId,
      model: model,
      serial: serial,
      // Scan responses often omit the name the primary packet carried.
      bluetoothName: ad.name ?? previous?.bluetoothName,
      powerOn: ad.powerOn ?? ad.powerOnFromServices ?? previous?.powerOn,
    );
    if (previous != null &&
        previous.deviceId == next.deviceId &&
        previous.bluetoothName == next.bluetoothName &&
        previous.powerOn == next.powerOn) {
      return;
    }
    _cameras[key] = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
