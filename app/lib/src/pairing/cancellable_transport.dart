import 'dart:async';

import 'package:gr_protocol/gr_protocol.dart';

/// Wraps the app's transport for one `pairCamera` run so the user can
/// cancel it: `pairCamera` has no cancellation of its own, so [cancel]
/// fails the scan and drops every link the run opened, which makes the run
/// end with an error at whatever stage it is in.
///
/// [onlyDeviceId] restricts the run's scan to one peripheral, for a camera
/// picked from an advertisement without a serial number (which
/// `pairCamera` would otherwise match against any GR nearby).
final class CancellableTransport implements BleTransport {
  CancellableTransport(this._inner, {this.onlyDeviceId});

  final BleTransport _inner;
  final String? onlyDeviceId;
  final List<StreamController<BleAdvertisement>> _scans = [];
  final List<BleConnection> _connections = [];
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  static const _cancelledError = BleException(
    BleErrorCode.transport,
    'pairing cancelled',
  );

  @override
  Future<BleAdapterState> adapterState() => _inner.adapterState();

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    if (_cancelled) return Stream.error(_cancelledError);
    StreamSubscription<BleAdvertisement>? upstream;
    late final StreamController<BleAdvertisement> controller;
    controller = StreamController<BleAdvertisement>(
      onListen: () {
        upstream = _inner
            .scan(serviceUuids: serviceUuids)
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
    if (_cancelled) throw _cancelledError;
    final connection = await _inner.connect(deviceId, timeout: timeout);
    if (_cancelled) {
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
    if (_cancelled) return;
    _cancelled = true;
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
