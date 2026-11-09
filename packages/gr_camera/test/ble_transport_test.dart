import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/src/platform/ble_transport.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

/// Records scan start/stop; every other platform call is unexpected. Set
/// [stopGate] to hold `stopScan` until it completes.
final class _FakePlatform extends UniversalBlePlatform {
  int starts = 0;
  int stops = 0;
  final calls = <String>[];
  Completer<void>? stopGate;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    starts++;
    calls.add('start');
  }

  @override
  Future<void> stopScan() async {
    calls.add('stop');
    await stopGate?.future;
    stops++;
    calls.add('stopped');
  }

  @override
  Future<bool> isScanning() async => starts > stops;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late _FakePlatform platform;
  late UniversalBleTransport transport;

  setUp(() {
    platform = _FakePlatform();
    UniversalBle.setInstance(platform);
    transport = UniversalBleTransport();
  });

  BleDevice device(String id) => BleDevice(deviceId: id, name: 'GR_$id');

  test('a rejected second scan leaves the first scan running', () async {
    final seenA = <String>[];
    final subA = transport.scan().listen((a) => seenA.add(a.deviceId));
    await pumpEventQueue();
    expect(platform.starts, 1);

    final errorsB = <Object>[];
    final doneB = Completer<void>();
    transport.scan().listen(
      (_) {},
      onError: errorsB.add,
      onDone: doneB.complete,
    );
    await doneB.future;
    await pumpEventQueue();

    expect(errorsB.single, isA<BleException>());
    expect(platform.stops, 0, reason: 'scan B must not stop scan A');

    platform.updateScanResult(device('a1'));
    await pumpEventQueue();
    expect(seenA, ['a1']);

    await subA.cancel();
    await pumpEventQueue();
    expect(platform.stops, 1);
  });

  test('a new scan can start after the previous one is cancelled', () async {
    final subA = transport.scan().listen((_) {});
    await pumpEventQueue();
    await subA.cancel();
    await pumpEventQueue();

    final errorsB = <Object>[];
    final subB = transport.scan().listen((_) {}, onError: errorsB.add);
    await pumpEventQueue();
    expect(errorsB, isEmpty);
    expect(platform.starts, 2);

    await transport.close();
    await pumpEventQueue();
    expect(platform.stops, 2);
    await subB.cancel();
    await pumpEventQueue();
    expect(platform.stops, 2, reason: 'close already stopped scan B');
  });

  test('a scan requested while the previous one is stopping starts after '
      'the stop', () async {
    final subA = transport.scan().listen((_) {});
    await pumpEventQueue();
    platform.stopGate = Completer();

    // As when the Cameras screen stops its nearby scan and a connection
    // starts its own straight away.
    unawaited(subA.cancel());
    final errorsB = <Object>[];
    final subB = transport.scan().listen((_) {}, onError: errorsB.add);
    await pumpEventQueue();
    expect(platform.calls, ['start', 'stop'], reason: 'B waits for A');

    platform.stopGate!.complete();
    await pumpEventQueue();
    expect(errorsB, isEmpty);
    expect(platform.calls, ['start', 'stop', 'stopped', 'start']);
    expect(await platform.isScanning(), isTrue);

    await subB.cancel();
  });
}
