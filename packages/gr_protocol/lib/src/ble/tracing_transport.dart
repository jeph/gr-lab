import 'dart:async';
import 'dart:typed_data';

import 'package:gr_protocol/src/ble/bytes.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:gr_protocol/src/trace.dart';

/// A [BleTransport] that reports everything crossing the platform Bluetooth
/// boundary to a [TraceSink] on [TraceChannel.ble]: adapter state, scans and
/// every advertisement, connects, discovery, every read, write,
/// subscription and notification with its bytes, pairing, disconnects and
/// every error.
///
/// Sits below `GrBleClient`'s own decoded trace, so a log shows what the
/// phone's stack actually sent and received even where the client gave up
/// or never decoded the value. Kinds are prefixed `transport.`; bytes go in
/// [TraceEvent.bytes].
final class TracingBleTransport implements BleTransport {
  /// Wraps [_inner], reporting everything it does to [_trace].
  new(this._inner, this._trace);

  final BleTransport _inner;
  final TraceSink _trace;

  @override
  Future<BleAdapterState> adapterState() async {
    try {
      final state = await _inner.adapterState();
      _emit(TraceDirection.inbound, 'adapterState', {'state': state.name});
      return state;
    } catch (e) {
      _error('adapterState', e);
      rethrow;
    }
  }

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    StreamSubscription<BleAdvertisement>? upstream;
    late final StreamController<BleAdvertisement> controller;
    controller = StreamController<BleAdvertisement>(
      onListen: () {
        _emit(TraceDirection.outbound, 'scan.start', {
          'serviceUuids': serviceUuids,
        });
        upstream = _inner
            .scan(serviceUuids: serviceUuids)
            .listen(
              (ad) {
                _emit(
                  TraceDirection.inbound,
                  'scan.advertisement',
                  advertisementFields(ad),
                );
                controller.add(ad);
              },
              onError: (Object e, StackTrace s) {
                _error('scan', e);
                controller.addError(e, s);
              },
              onDone: () {
                _emit(TraceDirection.internal, 'scan.done', const {});
                unawaited(controller.close());
              },
            );
      },
      onCancel: () {
        _emit(TraceDirection.outbound, 'scan.stop', const {});
        return upstream?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    _emit(TraceDirection.outbound, 'connect', {
      'deviceId': deviceId,
      'timeoutMs': timeout.inMilliseconds,
    });
    final BleConnection connection;
    try {
      connection = await _inner.connect(deviceId, timeout: timeout);
    } catch (e) {
      _error('connect', e, deviceId: deviceId);
      rethrow;
    }
    _emit(TraceDirection.inbound, 'connect.done', {
      'deviceId': deviceId,
      // The write limit the negotiated MTU allows, when the platform says.
      'maximumWriteLength': connection.maximumWriteLength,
    });
    return _TracingConnection(connection, this);
  }

  @override
  Future<void> close() async {
    _emit(TraceDirection.outbound, 'close', const {});
    try {
      await _inner.close();
    } catch (e) {
      _error('close', e);
      rethrow;
    }
  }

  /// Everything an advertisement carried; manufacturer payloads as hex,
  /// keyed by company ID.
  static Map<String, Object?> advertisementFields(BleAdvertisement ad) => {
    'deviceId': ad.deviceId,
    'name': ad.name,
    'rssi': ad.rssi,
    'connectable': ad.connectable,
    'serviceUuids': ad.serviceUuids,
    'manufacturerData': {
      for (final e in ad.manufacturerData.entries)
        '${e.key}': BleBytes.toHex(e.value),
    },
  };

  void _emit(
    TraceDirection direction,
    String kind,
    Map<String, Object?> fields, [
    Uint8List? bytes,
  ]) => _trace(
    TraceEvent(
      channel: TraceChannel.ble,
      direction: direction,
      kind: 'transport.$kind',
      fields: fields,
      bytes: bytes,
    ),
  );

  void _error(
    String operation,
    Object error, {
    String? deviceId,
    Map<String, Object?> fields = const {},
  }) => _emit(TraceDirection.internal, '$operation.error', {
    'deviceId': ?deviceId,
    ...fields,
    'error': '$error',
  });
}

final class _TracingConnection implements BleConnection {
  new(this._inner, this._transport) {
    unawaited(
      _inner.disconnected.then(
        (d) => _emit(TraceDirection.inbound, 'disconnected', {
          'requested': d.requested,
          'reason': d.reason,
          'bondRejected': d.bondRejected,
        }),
      ),
    );
  }

  final BleConnection _inner;
  final TracingBleTransport _transport;

  @override
  String get deviceId => _inner.deviceId;

  @override
  int? get maximumWriteLength => _inner.maximumWriteLength;

  @override
  Future<BleDisconnect> get disconnected => _inner.disconnected;

  @override
  Future<List<BleServiceInfo>> discover() async {
    _emit(TraceDirection.outbound, 'discover', const {});
    final List<BleServiceInfo> services;
    try {
      services = await _inner.discover();
    } catch (e) {
      _error('discover', e);
      rethrow;
    }
    _emit(TraceDirection.inbound, 'discover.done', {
      'services': [
        for (final s in services)
          {
            'uuid': s.uuid,
            'characteristics': [
              for (final c in s.characteristics)
                {
                  'uuid': c.uuid,
                  'properties': [for (final p in c.properties) p.name],
                },
            ],
          },
      ],
    });
    return services;
  }

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    final where = _where(serviceUuid, characteristicUuid);
    _emit(TraceDirection.outbound, 'read', {
      ...where,
      'timeoutMs': timeout?.inMilliseconds,
    });
    final Uint8List value;
    try {
      value = await _inner.read(
        serviceUuid,
        characteristicUuid,
        timeout: timeout,
      );
    } catch (e) {
      _error('read', e, where);
      rethrow;
    }
    _emit(TraceDirection.inbound, 'read.value', where, value);
    return value;
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    final where = _where(serviceUuid, characteristicUuid);
    _emit(TraceDirection.outbound, 'write', {
      ...where,
      'withResponse': withResponse,
      'timeoutMs': timeout?.inMilliseconds,
    }, value);
    try {
      await _inner.write(
        serviceUuid,
        characteristicUuid,
        value,
        withResponse: withResponse,
        timeout: timeout,
      );
    } catch (e) {
      _error('write', e, where);
      rethrow;
    }
    _emit(TraceDirection.inbound, 'write.done', where);
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) {
    final where = _where(serviceUuid, characteristicUuid);
    StreamSubscription<Uint8List>? upstream;
    late final StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>(
      onListen: () {
        _emit(TraceDirection.outbound, 'subscribe', where);
        upstream = _inner
            .subscribe(serviceUuid, characteristicUuid)
            .listen(
              (value) {
                _emit(TraceDirection.inbound, 'notification', where, value);
                controller.add(value);
              },
              onError: (Object e, StackTrace s) {
                _error('subscribe', e, where);
                controller.addError(e, s);
              },
              onDone: () {
                _emit(TraceDirection.internal, 'subscribe.done', where);
                unawaited(controller.close());
              },
            );
      },
      onCancel: () {
        _emit(TraceDirection.outbound, 'unsubscribe', where);
        return upstream?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {
    final where = _where(probeServiceUuid, probeCharacteristicUuid);
    _emit(TraceDirection.outbound, 'pair', {
      ...where,
      'timeoutMs': timeout.inMilliseconds,
    });
    try {
      await _inner.pair(
        probeServiceUuid: probeServiceUuid,
        probeCharacteristicUuid: probeCharacteristicUuid,
        timeout: timeout,
      );
    } catch (e) {
      _error('pair', e, where);
      rethrow;
    }
    _emit(TraceDirection.inbound, 'pair.done', where);
  }

  @override
  Future<void> disconnect() async {
    _emit(TraceDirection.outbound, 'disconnect', const {});
    try {
      await _inner.disconnect();
    } catch (e) {
      _error('disconnect', e);
      rethrow;
    }
  }

  static Map<String, Object?> _where(String service, String characteristic) => {
    'service': service,
    'characteristic': characteristic,
  };

  void _emit(
    TraceDirection direction,
    String kind,
    Map<String, Object?> fields, [
    Uint8List? bytes,
  ]) => _transport._emit(direction, kind, {
    'deviceId': deviceId,
    ...fields,
  }, bytes);

  void _error(
    String operation,
    Object error, [
    Map<String, Object?> fields = const {},
  ]) => _transport._error(operation, error, deviceId: deviceId, fields: fields);
}
