import 'dart:async';
import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

const _service = '9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1';
const _char = 'B29E6DE3-1AEC-48C1-9D05-02CEA57CE664';

final class _Transport implements BleTransport {
  final ads = StreamController<BleAdvertisement>.broadcast();
  final link = _Link();

  @override
  Future<BleAdapterState> adapterState() async => BleAdapterState.poweredOn;

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) =>
      ads.stream;

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async => link;

  @override
  Future<void> close() async {
    await ads.close();
    await link.disconnect();
  }
}

final class _Link implements BleConnection {
  final written = <Uint8List>[];
  final notifications = StreamController<Uint8List>.broadcast();
  final dropped = Completer<BleDisconnect>();

  @override
  String get deviceId => 'AA:BB';

  @override
  int? get maximumWriteLength => 509;

  @override
  Future<List<BleServiceInfo>> discover() async => const [];

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async => Uint8List.fromList([0x01, 0xfe]);

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async => written.add(value);

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) =>
      notifications.stream;

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {}

  @override
  Future<BleDisconnect> get disconnected => dropped.future;

  @override
  Future<void> disconnect() => notifications.close();
}

void main() {
  late _Transport inner;
  late TracingBleTransport transport;
  late List<TraceEvent> trace;

  setUp(() {
    inner = _Transport();
    trace = [];
    transport = TracingBleTransport(inner, trace.add);
  });

  tearDown(() => inner.close());

  TraceEvent only(String kind) =>
      trace.singleWhere((e) => e.kind == 'transport.$kind');

  test('records every advertisement with its manufacturer data', () async {
    final seen = <BleAdvertisement>[];
    final sub = transport.scan().listen(seen.add);
    inner.ads.add(
      BleAdvertisement(
        deviceId: 'AA:BB',
        name: 'GR_123456',
        rssi: -61,
        serviceUuids: const [_service],
        manufacturerData: {
          0x065f: Uint8List.fromList([0x01, 0x0a, 0xff]),
        },
      ),
    );
    await pumpEventQueue();
    await sub.cancel();

    expect(seen, hasLength(1));
    final ad = only('scan.advertisement');
    expect(ad.channel, TraceChannel.ble);
    expect(ad.direction, TraceDirection.inbound);
    expect(ad.fields, {
      'deviceId': 'AA:BB',
      'name': 'GR_123456',
      'rssi': -61,
      'connectable': null,
      'serviceUuids': [_service],
      'manufacturerData': {'${0x065f}': '010aff'},
    });
    expect(trace.map((e) => e.kind), [
      'transport.scan.start',
      'transport.scan.advertisement',
      'transport.scan.stop',
    ]);
  });

  test('records the exact bytes written, read and notified', () async {
    final link = await transport.connect(
      'AA:BB',
      timeout: const Duration(seconds: 5),
    );
    expect(only('connect.done').fields['maximumWriteLength'], 509);

    final value = Uint8List.fromList([0x00, 0x7f, 0x80, 0xff]);
    await link.write(_service, _char, value, withResponse: false);
    final write = only('write');
    expect(write.direction, TraceDirection.outbound);
    expect(write.bytes, value);
    expect(write.fields, {
      'deviceId': 'AA:BB',
      'service': _service,
      'characteristic': _char,
      'withResponse': false,
      'timeoutMs': null,
    });
    expect(inner.link.written.single, value);

    await link.read(_service, _char);
    expect(only('read.value').bytes, [0x01, 0xfe]);

    final notified = <Uint8List>[];
    final sub = link.subscribe(_service, _char).listen(notified.add);
    inner.link.notifications.add(Uint8List.fromList([0x02, 0x03]));
    await pumpEventQueue();
    await sub.cancel();
    expect(notified.single, [0x02, 0x03]);
    expect(only('notification').bytes, [0x02, 0x03]);
    expect(only('unsubscribe').fields['characteristic'], _char);

    inner.link.dropped.complete(
      const BleDisconnect(requested: false, reason: 'link loss'),
    );
    await pumpEventQueue();
    expect(only('disconnected').fields, {
      'deviceId': 'AA:BB',
      'requested': false,
      'reason': 'link loss',
      'bondRejected': false,
    });
  });
}
