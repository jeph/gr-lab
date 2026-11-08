import 'dart:async';
import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:gr_protocol/src/trace.dart';
import 'package:test/test.dart';

BleAdvertisement advert(String id, {required int serial, required int power}) =>
    BleAdvertisement(
      deviceId: id,
      rssi: -50,
      manufacturerData: {
        grRicohCompanyId: Uint8List.fromList([
          0xda,
          0x01,
          0x08,
          0x02,
          serial & 0xff,
          (serial >> 8) & 0xff,
          (serial >> 16) & 0xff,
          (serial >> 24) & 0xff,
          0x03,
          power,
        ]),
      },
    );

Duration ms(int v) => Duration(milliseconds: v);

/// Each `scan()` call plays the next script: adverts at given delays.
final class ScriptedTransport implements BleTransport {
  ScriptedTransport(this.scripts, {this.dropAfter, this.failConnect = false});

  final List<List<(Duration, BleAdvertisement)>> scripts;
  final Duration? dropAfter;
  final bool failConnect;
  var scanCalls = 0;
  final connections = <ScriptedConnection>[];

  @override
  Future<BleAdapterState> adapterState() async => BleAdapterState.poweredOn;

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    final script = scanCalls < scripts.length
        ? scripts[scanCalls]
        : const <(Duration, BleAdvertisement)>[];
    scanCalls++;
    final timers = <Timer>[];
    late final StreamController<BleAdvertisement> controller;
    controller = StreamController<BleAdvertisement>(
      onListen: () {
        for (final (delay, ad) in script) {
          timers.add(Timer(delay, () => controller.add(ad)));
        }
      },
      onCancel: () {
        for (final t in timers) {
          t.cancel();
        }
        unawaited(controller.close());
      },
    );
    return controller.stream;
  }

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    if (failConnect) {
      throw const BleException(BleErrorCode.timeout, 'no answer');
    }
    final c = ScriptedConnection(deviceId, dropAfter);
    connections.add(c);
    return c;
  }

  @override
  Future<void> close() async {}
}

final class ScriptedConnection implements BleConnection {
  ScriptedConnection(this.deviceId, Duration? dropAfter) {
    if (dropAfter != null) {
      _timer = Timer(dropAfter, () {
        if (!_drop.isCompleted) {
          _drop.complete(
            const BleDisconnect(requested: false, reason: 'remote'),
          );
        }
      });
    }
  }

  @override
  final String deviceId;
  final _drop = Completer<BleDisconnect>();
  Timer? _timer;
  var disconnectCalls = 0;

  /// Any GATT operation: the wake connection must stay bare.
  var gattCalls = 0;

  @override
  int? get maximumWriteLength => null;

  @override
  Future<BleDisconnect> get disconnected => _drop.future;

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _timer?.cancel();
    if (!_drop.isCompleted) {
      _drop.complete(const BleDisconnect(requested: true));
    }
  }

  @override
  Future<List<BleServiceInfo>> discover() async {
    gattCalls++;
    return const [];
  }

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    gattCalls++;
    return Uint8List(0);
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    gattCalls++;
  }

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {
    gattCalls++;
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) {
    gattCalls++;
    return const Stream.empty();
  }
}

void main() {
  test('already on: no connection', () async {
    final t = ScriptedTransport([
      [(ms(5), advert('a', serial: 42, power: 1))],
    ]);
    final r = await wakeCamera(t, findTimeout: ms(500));
    expect(r.outcome, GrWakeOutcome.alreadyOn);
    expect(r.succeeded, isTrue);
    expect(r.deviceId, 'a');
    expect(t.connections, isEmpty);
  });

  test('wakes: bare connect, link drop, power-on advert by serial', () async {
    final events = <TraceEvent>[];
    final t = ScriptedTransport([
      [
        (ms(5), advert('other', serial: 7, power: 0)),
        (ms(10), advert('a', serial: 42, power: 0)),
      ],
      [
        (ms(20), advert('other', serial: 7, power: 1)),
        (ms(80), advert('b', serial: 42, power: 1)),
      ],
    ], dropAfter: ms(40));
    final r = await wakeCamera(
      t,
      serial: 'GR 0000042',
      findTimeout: ms(500),
      dropTimeout: ms(500),
      powerOnTimeout: ms(500),
      trace: events.add,
    );
    expect(r.outcome, GrWakeOutcome.wokeUp);
    expect(r.offAdvertisement!.deviceId, 'a');
    expect(r.deviceId, 'b');
    expect(r.dropTimedOut, isFalse);
    expect(r.dropReason, 'remote');
    expect(r.linkDroppedAfter, isNotNull);
    expect(r.onAdvertisementAfter! >= r.linkDroppedAfter!, isTrue);
    expect(t.connections.single.deviceId, 'a');
    expect(t.connections.single.gattCalls, 0);
    expect(r.notes, isEmpty);
    expect(
      events.map((e) => e.kind),
      containsAllInOrder([
        'wake.start',
        'wake.advertisement',
        'wake.connect',
        'wake.connected',
        'wake.linkDropped',
        'wake.powerOnAdvertisement',
        'wake.done',
      ]),
    );
  });

  test('drop timeout: disconnects, keeps scanning and says so', () async {
    final t = ScriptedTransport([
      [(ms(5), advert('a', serial: 42, power: 0))],
      [(ms(120), advert('a', serial: 42, power: 1))],
    ]);
    final r = await wakeCamera(
      t,
      findTimeout: ms(500),
      dropTimeout: ms(50),
      powerOnTimeout: ms(500),
    );
    expect(r.outcome, GrWakeOutcome.wokeUp);
    expect(r.dropTimedOut, isTrue);
    expect(r.linkDroppedAfter, isNull);
    expect(t.connections.single.disconnectCalls, 1);
    expect(r.notes.single, contains('kept the link'));
  });

  test('not found, connect failure, no power-on advert', () async {
    final none = await wakeCamera(ScriptedTransport([[]]), findTimeout: ms(30));
    expect(none.outcome, GrWakeOutcome.notFound);

    final failed = await wakeCamera(
      ScriptedTransport([
        [(ms(5), advert('a', serial: 1, power: 0))],
      ], failConnect: true),
      findTimeout: ms(500),
    );
    expect(failed.outcome, GrWakeOutcome.connectFailed);
    expect(failed.error, contains('no answer'));

    final silent = await wakeCamera(
      ScriptedTransport([
        [(ms(5), advert('a', serial: 1, power: 0))],
      ], dropAfter: ms(10)),
      findTimeout: ms(500),
      dropTimeout: ms(500),
      powerOnTimeout: ms(60),
    );
    expect(silent.outcome, GrWakeOutcome.noPowerOnAdvertisement);
    expect(silent.succeeded, isFalse);
  });

  test('grSerialMatches compares digits only', () {
    expect(grSerialMatches('0012345', 12345), isTrue);
    expect(grSerialMatches('No. 12345', 12345), isTrue);
    expect(grSerialMatches('12346', 12345), isFalse);
    expect(grSerialMatches('abc', 0), isFalse);
    expect(grSerialMatches('1', null), isFalse);
  });

  test('waitAfterPowerOff waits only for the remainder of 6 s', () async {
    final past = DateTime.now().subtract(const Duration(seconds: 10));
    expect(await waitAfterPowerOff(past), Duration.zero);
    final recent = DateTime.now();
    final waited = await waitAfterPowerOff(recent, guard: ms(30));
    expect(waited > Duration.zero && waited <= ms(30), isTrue);
    expect(grWorldPowerOffReconnectGuard, const Duration(seconds: 6));
  });
}
