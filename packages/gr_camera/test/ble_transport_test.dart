import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/src/platform/ble_transport.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

/// Records scan start/stop, connects, MTU requests, disconnects and
/// notification switches; every other platform call is unexpected. Set
/// [stopGate] to hold `stopScan`, [connectGate], [mtuGate] or
/// [notifyGate] to hold those calls until the gate completes.
final class _FakePlatform extends UniversalBlePlatform {
  int starts = 0;
  int stops = 0;
  final calls = <String>[];

  /// The services and Android scan mode of every scan started.
  final filters = <List<String>>[];
  final modes = <AndroidScanMode?>[];

  /// While set, the next `startScan` fails with it.
  Error? startError;
  Completer<void>? stopGate;
  Completer<void>? connectGate;
  Completer<void>? mtuGate;
  Completer<void>? notifyGate;
  final _connected = <String>{};

  /// Whether notifications are on, per characteristic.
  final notifying = <String, bool>{};

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    final error = startError;
    if (error != null) {
      startError = null;
      throw error;
    }
    starts++;
    calls.add('start');
    filters.add(scanFilter?.withServices ?? const []);
    modes.add(platformConfig?.android?.scanMode);
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
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    calls.add('connect');
    await connectGate?.future;
    _connected.add(deviceId);
    updateConnection(deviceId, true);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    calls.add('mtu');
    await mtuGate?.future;
    return expectedMtu;
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      _connected.contains(deviceId)
      ? BleConnectionState.connected
      : BleConnectionState.disconnected;

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect');
    _connected.remove(deviceId);
    updateConnection(deviceId, false);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    await notifyGate?.future;
    final on = bleInputProperty != BleInputProperty.disabled;
    calls.add(on ? 'notify on' : 'notify off');
    notifying[characteristic] = on;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _device = '00:00:5e:00:53:01';
const _service = '9a5ed1c5-74cc-4c50-b5b6-66a48e7ccff1';
const _characteristic = 'b29e6de3-1aec-48c1-9d05-02cea57ce664';
const _timeout = Duration(seconds: 5);

void main() {
  late _FakePlatform platform;
  late UniversalBleTransport transport;

  setUp(() {
    platform = _FakePlatform();
    UniversalBle.setInstance(platform);
    transport = UniversalBleTransport();
  });

  BleDevice device(String id) => BleDevice(deviceId: id, name: 'GR_$id');

  BleDevice advertising(String id, String service) =>
      BleDevice(deviceId: id, name: 'GR_$id', services: [service]);

  test('a second scan shares the platform scan of the first, and the '
      'platform scan stops with the last of them', () async {
    final seenA = <String>[];
    final seenB = <String>[];
    final subA = transport.scan().listen((a) => seenA.add(a.deviceId));
    await pumpEventQueue();
    final subB = transport.scan().listen((a) => seenB.add(a.deviceId));
    await pumpEventQueue();
    expect(platform.starts, 1);

    platform.updateScanResult(device('a1'));
    await pumpEventQueue();
    expect(seenA, ['a1']);
    expect(seenB, ['a1']);

    await subA.cancel();
    await pumpEventQueue();
    expect(platform.stops, 0, reason: 'scan B still listens');
    platform.updateScanResult(device('a2'));
    await pumpEventQueue();
    expect(seenA, ['a1']);
    expect(seenB, ['a1', 'a2']);

    await subB.cancel();
    await pumpEventQueue();
    expect(platform.stops, 1);
  });

  test('a scan for a service is filtered by the platform at low power '
      'while it is alone, and by the transport next to an unfiltered '
      'scan', () async {
    const other = '0f291746-0c80-4726-87a7-3c501fd3b4b6';
    final watched = <String>[];
    final watch = transport
        .scan(serviceUuids: [_service])
        .listen((a) => watched.add(a.deviceId));
    await pumpEventQueue();
    expect(platform.filters.single, [canonicalUuid(_service)]);
    expect(platform.modes.single, AndroidScanMode.lowPower);

    // A search starts: the platform scan is started again without a
    // filter, at full rate, and the watch still gets only its service.
    final found = <String>[];
    final search = transport.scan().listen((a) => found.add(a.deviceId));
    await pumpEventQueue();
    expect(platform.calls, ['start', 'stop', 'stopped', 'start']);
    expect(platform.filters.last, isEmpty);
    expect(platform.modes.last, AndroidScanMode.lowLatency);
    platform
      ..updateScanResult(advertising('on', _service))
      ..updateScanResult(advertising('off', other));
    await pumpEventQueue();
    expect(found, ['on', 'off']);
    expect(watched, ['on']);

    // The search ends: the watch is alone again, filtered by the platform.
    await search.cancel();
    await pumpEventQueue();
    expect(platform.filters.last, [canonicalUuid(_service)]);
    expect(platform.modes.last, AndroidScanMode.lowPower);
    expect(await platform.isScanning(), isTrue);

    await watch.cancel();
    await pumpEventQueue();
    expect(await platform.isScanning(), isFalse);
  });

  test('a watch says how much of the time the platform listens, and one '
      'started in its place changes that in a single restart', () async {
    final fast = transport
        .scan(serviceUuids: [_service], rate: BleScanRate.full)
        .listen((_) {});
    await pumpEventQueue();
    expect(platform.filters.single, [canonicalUuid(_service)]);
    expect(platform.modes.single, AndroidScanMode.lowLatency);

    final steady = transport
        .scan(serviceUuids: [_service], rate: BleScanRate.balanced)
        .listen((_) {});
    unawaited(fast.cancel());
    await pumpEventQueue();
    expect(platform.calls, ['start', 'stop', 'stopped', 'start']);
    expect(platform.filters.last, [canonicalUuid(_service)]);
    expect(platform.modes.last, AndroidScanMode.balanced);

    // Next to a watch at low power, the platform listens for the one that
    // asks for more.
    final slow = transport.scan(serviceUuids: [_service]).listen((_) {});
    await pumpEventQueue();
    expect(platform.starts, 2);
    await steady.cancel();
    await pumpEventQueue();
    expect(platform.modes.last, AndroidScanMode.lowPower);
    await slow.cancel();
  });

  test('a watch replaced by one that asks for the same leaves the platform '
      'scan running; one started after the first has ended starts it anew, '
      'as a platform that reports a camera once per scan needs', () async {
    Stream<BleAdvertisement> watch() =>
        transport.scan(serviceUuids: [_service], rate: BleScanRate.full);
    final first = watch().listen((_) {});
    await pumpEventQueue();
    expect(platform.calls, ['start']);

    final second = watch().listen((_) {});
    unawaited(first.cancel());
    await pumpEventQueue();
    expect(platform.calls, ['start']);

    await second.cancel();
    final third = watch().listen((_) {});
    await pumpEventQueue();
    expect(platform.calls, ['start', 'stop', 'stopped', 'start']);
    await third.cancel();
  });

  test('a scan the platform refuses to start ends with its error, and the '
      'next one starts', () async {
    platform.startError = StateError('Bluetooth is off');
    final errors = <Object>[];
    final done = Completer<void>();
    transport.scan().listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future;
    expect(errors.single, isA<StateError>());
    expect(platform.starts, 0);

    final sub = transport.scan().listen((_) {});
    await pumpEventQueue();
    expect(platform.starts, 1);
    await sub.cancel();
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
    // starts its own a moment later.
    unawaited(subA.cancel());
    await pumpEventQueue();
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

  test('a scan requested as the previous one is cancelled takes over the '
      'platform scan without a stop', () async {
    final subA = transport.scan().listen((_) {});
    await pumpEventQueue();
    unawaited(subA.cancel());
    final seenB = <String>[];
    final subB = transport.scan().listen((a) => seenB.add(a.deviceId));
    await pumpEventQueue();
    expect(platform.calls, ['start']);
    platform.updateScanResult(device('b1'));
    await pumpEventQueue();
    expect(seenB, ['b1']);
    await subB.cancel();
    await pumpEventQueue();
    expect(platform.calls, ['start', 'stop', 'stopped']);
  });

  group('a connect still running when another owner connects', () {
    // As when a pairing run is cancelled while connecting and the session
    // to the previous camera, or the next run, connects straight away: the
    // cancelled run drops its link once its connect returns.
    Future<void> expectEarlierOwnerCannotDrop(
      Future<BleConnection> first,
      Future<BleConnection> second,
    ) async {
      final earlier = await first;
      final newer = await second;
      var newerDropped = false;
      unawaited(newer.disconnected.then((_) => newerDropped = true));

      await earlier.disconnect();
      await pumpEventQueue();
      expect(platform.calls, isNot(contains('disconnect')));
      expect(newerDropped, isFalse);
      expect((await earlier.disconnected).requested, isTrue);
      await expectLater(earlier.discover(), throwsA(isA<BleException>()));

      await newer.disconnect();
      expect(platform.calls.where((c) => c == 'disconnect'), hasLength(1));
      expect((await newer.disconnected).requested, isTrue);
    }

    test('waits for the native connect, and the earlier owner cannot drop '
        'the newer one', () async {
      platform.connectGate = Completer();
      final first = transport.connect(_device, timeout: _timeout);
      await pumpEventQueue();
      final second = transport.connect(_device, timeout: _timeout);
      await pumpEventQueue();
      expect(platform.calls, ['connect'], reason: 'one native connect');

      platform.connectGate!.complete();
      await expectEarlierOwnerCannotDrop(first, second);
      expect(platform.calls.where((c) => c == 'connect'), hasLength(1));
    });

    test('waits for the MTU request, and the earlier owner cannot drop the '
        'newer one', () async {
      platform.mtuGate = Completer();
      final first = transport.connect(_device, timeout: _timeout);
      await pumpEventQueue();
      expect(platform.calls, ['connect', 'mtu']);
      var secondDone = false;
      final second = transport.connect(_device, timeout: _timeout)
        ..then((_) => secondDone = true, onError: (Object _) {}).ignore();
      await pumpEventQueue();
      expect(secondDone, isFalse, reason: 'the link is still being set up');

      platform.mtuGate!.complete();
      await expectEarlierOwnerCannotDrop(first, second);
    });
  });

  test(
    'a connect after the newest owner disconnected opens a new link',
    () async {
      final first = await transport.connect(_device, timeout: _timeout);
      await first.disconnect();
      await transport.connect(_device, timeout: _timeout);
      expect(platform.calls, [
        'connect',
        'mtu',
        'disconnect',
        'connect',
        'mtu',
      ]);
    },
  );

  test('a watcher replaced right after it was cancelled keeps the '
      "camera's notifications on", () async {
    final connection = await transport.connect(_device, timeout: _timeout);
    final old = connection.subscribe(_service, _characteristic).listen((_) {});
    await pumpEventQueue();
    expect(platform.notifying.values.single, isTrue);

    // As CameraRemote does when watching goes off and on quickly: the old
    // stream's cancel is not awaited before the new one listens.
    platform.notifyGate = Completer();
    unawaited(old.cancel());
    final values = <Uint8List>[];
    final replacement = connection
        .subscribe(_service, _characteristic)
        .listen(values.add);
    await pumpEventQueue();
    platform.notifyGate!.complete();
    await pumpEventQueue();
    expect(platform.notifying.values.single, isTrue);

    platform.updateCharacteristicValue(
      _device,
      _characteristic,
      Uint8List.fromList([1]),
      null,
    );
    await pumpEventQueue();
    expect(values, hasLength(1));

    await replacement.cancel();
    await pumpEventQueue();
    expect(platform.notifying.values.single, isFalse, reason: 'nobody left');
  });
}
