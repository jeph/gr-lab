import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

/// A bonded camera reached by device id. [operationMode] is what Operation
/// Mode reads (`02` = off, BT-only); writes to it are recorded.
final class BondedCamera implements BleTransport {
  new({
    this.operationMode = 1,
    this.connectError,
    this.bonded = true,
    this.dropLinks = 0,
    this.security = 2,
  });

  int operationMode;
  final BleException? connectError;
  final bool bonded;

  /// WLAN security byte: 0 WPA2, 1 WPA3, 2 transition (the GR IV's).
  final int security;

  /// Links whose discovery fails as if the camera dropped them (waking).
  int dropLinks;
  int scans = 0;
  final ops = <String>[];

  /// While set, a connect waits for it before the link opens.
  Completer<void>? holdConnect;

  /// While set, an Operation Mode write waits for it before it lands.
  Completer<void>? holdModeWrite;

  /// While set, a WLAN write waits for it before it lands.
  Completer<void>? holdWlanWrite;

  /// What a scan delivers; no advertisements when null.
  StreamController<BleAdvertisement>? advertising;
  final _links = <_Link>[];

  /// Links that have not dropped or been disconnected.
  int get openLinks => _links.where((l) => !l._drop.isCompleted).length;

  /// Drops every open link from the camera side.
  void dropAll() {
    for (final l in _links) {
      if (!l._drop.isCompleted) {
        l._drop.complete(const BleDisconnect(requested: false));
      }
    }
  }

  @override
  Future<BleAdapterState> adapterState() async => BleAdapterState.poweredOn;

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) {
    scans++;
    return advertising?.stream ?? const Stream.empty();
  }

  @override
  Future<BleConnection> connect(
    String deviceId, {
    required Duration timeout,
  }) async {
    ops.add('connect $deviceId');
    final e = connectError;
    if (e != null) throw e;
    await holdConnect?.future;
    final link = _Link(this, deviceId);
    _links.add(link);
    return link;
  }

  @override
  Future<void> close() async {}
}

final class _Link implements BleConnection {
  new(this.camera, this.deviceId);

  final BondedCamera camera;
  @override
  final String deviceId;
  final _drop = Completer<BleDisconnect>();

  @override
  int? get maximumWriteLength => null;

  @override
  Future<BleDisconnect> get disconnected => _drop.future;

  @override
  Future<void> disconnect() async {
    camera.ops.add('disconnect');
    if (!_drop.isCompleted) {
      _drop.complete(const BleDisconnect(requested: true));
    }
  }

  @override
  Future<List<BleServiceInfo>> discover() async {
    if (camera.dropLinks > 0) {
      camera.dropLinks--;
      camera.ops.add('dropped');
      throw const BleException(BleErrorCode.notFound, 'Unknown deviceId');
    }
    final byService = <String, List<BleCharacteristicInfo>>{};
    for (final c in GrBleCatalog.all) {
      (byService[c.service.uuid] ??= []).add(
        BleCharacteristicInfo(uuid: c.uuid, properties: c.properties),
      );
    }
    return [
      for (final e in byService.entries)
        BleServiceInfo(uuid: e.key, characteristics: e.value),
    ];
  }

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {}

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    final uuid = canonicalUuid(characteristicUuid);
    if (uuid == GrBleCatalog.operationMode.uuid) {
      camera.ops.add('read mode');
      return Uint8List.fromList([camera.operationMode]);
    }
    if (uuid == GrBleCatalog.serialNumber.uuid) camera.ops.add('read serial');
    if (!camera.bonded) {
      throw const BleException(
        BleErrorCode.unauthorized,
        'Authentication is insufficient.',
      );
    }
    if (uuid == GrBleCatalog.wlanSecurity.uuid) {
      return Uint8List.fromList([camera.security]);
    }
    final values = {
      GrBleCatalog.serialNumber.uuid: '1234567',
      GrBleCatalog.modelName.uuid: 'RICOH GR IV HDF',
      GrBleCatalog.ssid.uuid: 'GR_H0053A8',
      GrBleCatalog.passphrase.uuid: 'abcdefgh',
    };
    return Uint8List.fromList(utf8.encode(values[uuid] ?? '1'));
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    final uuid = canonicalUuid(characteristicUuid);
    if (uuid == GrBleCatalog.operationMode.uuid) {
      await camera.holdModeWrite?.future;
    }
    if (uuid == GrBleCatalog.networkType.uuid) {
      await camera.holdWlanWrite?.future;
    }
    // A write in flight when the link drops fails with it.
    if (_drop.isCompleted) {
      throw const BleException(BleErrorCode.notConnected, 'link dropped');
    }
    if (uuid == GrBleCatalog.operationMode.uuid) {
      camera.ops.add('write mode ${value.single}');
      camera.operationMode = value.single;
    }
    if (uuid == GrBleCatalog.networkType.uuid) {
      camera.ops.add('write wlan ${value.single}');
    }
    if (uuid == GrBleCatalog.cameraPower.uuid) {
      camera.ops.add('write power ${value.single}');
    }
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) =>
      const Stream.empty();
}

/// Ends every session at the join, after the BLE part under test.
final class FailingWifi implements WifiNetworkControl {
  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async => throw StateError('no Wi-Fi in this test');

  @override
  Future<String?> currentSsid() async => null;

  @override
  Future<void> leave() async {}

  @override
  Stream<void> get lost => const Stream.empty();
}

/// Records the security of every join and fails each one, the first with
/// [first] when given.
final class RecordingWifi implements WifiNetworkControl {
  new({this.first});

  final Exception? first;
  final joins = <WifiSecurity>[];

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    joins.add(security);
    final error = first;
    if (joins.length == 1 && error != null) throw error;
    throw StateError('no camera network yet');
  }

  @override
  Future<String?> currentSsid() async => null;

  @override
  Future<void> leave() async {}

  @override
  Stream<void> get lost => const Stream.empty();
}

/// Looks for the camera network until the join times out or [leave] cuts
/// it short.
final class SearchingWifi implements WifiNetworkControl {
  Completer<void> _left = Completer<void>();

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    _left = Completer<void>();
    await Future.any([Future<void>.delayed(timeout), _left.future]);
    throw StateError('no camera network yet');
  }

  @override
  Future<String?> currentSsid() async => null;

  @override
  Future<void> leave() async {
    if (!_left.isCompleted) _left.complete();
  }

  @override
  Stream<void> get lost => const Stream.empty();
}

/// Joins the camera network at once, or when [holdJoin] completes. [leave]
/// cuts a held join short, as the platforms do, unless [leaveMissesJoin]
/// (a join that completes although it was released). Records joins and
/// leaves; [loseNetwork] reports the network gone.
final class JoiningWifi implements WifiNetworkControl {
  int joins = 0;
  int leaves = 0;
  bool joined = false;
  Completer<void>? holdJoin;
  bool leaveMissesJoin = false;

  /// Completes when the first join starts.
  final joinStarted = Completer<void>();
  Completer<void> _left = Completer<void>();
  final _lost = StreamController<void>.broadcast();

  void loseNetwork() => _lost.add(null);

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    joins++;
    if (!joinStarted.isCompleted) joinStarted.complete();
    _left = Completer<void>();
    final hold = holdJoin;
    if (hold != null) {
      await Future.any([hold.future, if (!leaveMissesJoin) _left.future]);
      if (_left.isCompleted && !leaveMissesJoin) {
        throw StateError('join cancelled');
      }
    }
    joined = true;
  }

  @override
  Future<String?> currentSsid() async => null;

  @override
  Future<void> leave() async {
    leaves++;
    joined = false;
    if (!_left.isCompleted) _left.complete();
  }

  @override
  Stream<void> get lost => _lost.stream;
}

/// `/v1/props` of the camera [BondedCamera] links to.
const Map<String, Object?> cameraProps = {
  'errCode': 200,
  'errMsg': 'OK',
  'model': 'RICOH GR IV HDF',
  'serialNo': '1234567',
  'ssid': 'GR_H0053A8',
  'firmwareVersion': '1.20',
};

/// The camera's HTTP side on a loopback port: `/v1/props` answers [props]
/// (HTTP 503 while null), and `/v1/changes` upgrades wait for
/// [holdUpgrade] and are refused (HTTP 503) while [refuseUpgrades] > 0.
final class CameraServer {
  new(this._server) {
    _server.listen(_handle);
  }

  static Future<CameraServer> start() async {
    final server = CameraServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(server.close);
    return server;
  }

  final HttpServer _server;
  Map<String, Object?>? props = cameraProps;
  int propsRequests = 0;
  int upgradeRequests = 0;
  int refuseUpgrades = 0;
  Completer<void>? holdUpgrade;
  final sockets = <WebSocket>[];
  final _upgradeRequested = StreamController<void>.broadcast();

  /// One event per `/v1/changes` upgrade request, before it is held.
  Stream<void> get upgradeRequested => _upgradeRequested.stream;

  /// The session's HTTP client factory, pointed at this server.
  GrHttpClient client(String host, TraceSink? trace) =>
      GrHttpClient('127.0.0.1', port: _server.port, trace: trace);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    switch (request.uri.path) {
      case '/v1/props':
        propsRequests++;
        final body = props;
        if (body == null) {
          response.statusCode = HttpStatus.serviceUnavailable;
        } else {
          response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(body));
        }
      case '/v1/changes' when WebSocketTransformer.isUpgradeRequest(request):
        upgradeRequests++;
        _upgradeRequested.add(null);
        await holdUpgrade?.future;
        if (refuseUpgrades == 0) {
          final ws = await WebSocketTransformer.upgrade(request);
          sockets.add(ws);
          ws.listen((_) {});
          return;
        }
        refuseUpgrades--;
        response.statusCode = HttpStatus.serviceUnavailable;
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  Future<void> close() async {
    for (final ws in sockets) {
      await ws.close();
    }
    await _server.close(force: true);
  }
}

/// A session over [camera], [wifi] and [server] with quick retries.
GrSession wifiSession(
  BondedCamera camera,
  JoiningWifi wifi,
  CameraServer server, {
  Duration verifyTimeout = const Duration(seconds: 5),
  TraceSink? trace,
}) => GrSession(
  transport: camera,
  wifi: wifi,
  httpFactory: server.client,
  trace: trace,
  options: GrSessionOptions(
    joinTimeout: const Duration(seconds: 5),
    joinRetryDelay: const Duration(milliseconds: 1),
    wakeSettle: const Duration(milliseconds: 20),
    verifyTimeout: verifyTimeout,
    wifiRecoveryDelays: const [Duration.zero],
    bleReconnectDelays: const [Duration.zero],
  ),
);

GrSession session(BondedCamera camera) => GrSession(
  transport: camera,
  wifi: FailingWifi(),
  options: const GrSessionOptions(
    joinTimeout: Duration(milliseconds: 10),
    joinRetryDelay: Duration(milliseconds: 1),
    wakeSettle: Duration(milliseconds: 20),
  ),
);

void main() {
  test(
    'off camera: linked without a write; the Wi-Fi start writes playback '
    'and then WLAN-on at once, without waiting for the link to settle',
    () async {
      final camera = BondedCamera(operationMode: 2);
      final s = GrSession(
        transport: camera,
        wifi: FailingWifi(),
        options: const GrSessionOptions(
          joinTimeout: Duration(milliseconds: 10),
          joinRetryDelay: Duration(milliseconds: 1),
          wakeSettle: Duration(minutes: 1),
        ),
      );
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));

      final watch = Stopwatch()..start();
      await expectLater(
        s.connect(deviceId: 'cam'),
        throwsA(
          isA<GrSessionException>().having(
            (e) => e.phase,
            'phase',
            GrSessionPhase.joining,
          ),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(camera.scans, 0);
      expect(camera.ops.take(3), ['connect cam', 'read mode', 'read serial']);
      final wake = camera.ops.indexOf('write mode 1');
      expect(wake, greaterThan(2));
      expect(
        camera.ops.indexWhere((o) => o.startsWith('write wlan')),
        greaterThan(wake),
      );
      expect(camera.ops.where((o) => o.startsWith('connect')), hasLength(1));
      expect(
        kinds,
        containsAllInOrder(['bluetooth', 'power.on', 'wlan.on', 'wifi.join']),
      );
      expect(kinds, isNot(contains('power.onLinked')));
      await s.close();
    },
  );

  test('after a wake, WLAN-on is written once more while the join is still '
      'looking for the camera network', () async {
    final camera = BondedCamera(operationMode: 2);
    final s = GrSession(
      transport: camera,
      wifi: SearchingWifi(),
      options: const GrSessionOptions(
        joinTimeout: Duration(milliseconds: 300),
        joinRetryDelay: Duration(milliseconds: 1),
        wakeSettle: Duration(milliseconds: 50),
      ),
    );
    final kinds = <String>[];
    s.events.listen((e) => kinds.add(e.kind));

    await expectLater(
      s.connect(deviceId: 'cam'),
      throwsA(isA<GrSessionException>()),
    );
    expect(camera.ops.where((o) => o == 'write wlan 1'), hasLength(2));
    expect(
      kinds,
      containsAllInOrder(['power.on', 'wlan.on', 'wifi.join', 'wlan.again']),
    );
    await s.close();
  });

  group('a relink after a wake still opening', () {
    Future<void> until(bool Function() condition) async {
      final watch = Stopwatch()..start();
      while (!condition()) {
        if (watch.elapsed > const Duration(seconds: 5)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    /// The wake's early WLAN-on goes through and the join is looking for
    /// the network; then the link drops and the relink waits on the camera.
    Future<(BondedCamera, GrSession, Future<void>)> relinking() async {
      final camera = BondedCamera(operationMode: 2);
      final s = GrSession(
        transport: camera,
        wifi: SearchingWifi(),
        options: const GrSessionOptions(
          joinTimeout: Duration(seconds: 2),
          joinRetryDelay: Duration(milliseconds: 1),
          wakeSettle: Duration(seconds: 20),
        ),
      );
      final ended = s
          .connect(deviceId: 'cam')
          .then<void>((_) {}, onError: (_) {});
      await until(() => s.phase == GrSessionPhase.joining);
      camera
        ..holdConnect = Completer<void>()
        ..dropAll();
      await until(
        () => camera.ops.where((o) => o == 'connect cam').length == 2,
      );
      return (camera, s, ended);
    }

    test('close leaves no link open once the relink completes', () async {
      final (camera, s, ended) = await relinking();
      await s.close();
      await ended;
      camera.holdConnect!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(camera.openLinks, 0);
    });

    test('stopWifi waits for it and writes WLAN-off on the new link', () async {
      final (camera, s, ended) = await relinking();
      final stopped = s.stopWifi();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      camera.holdConnect!.complete();
      await stopped;
      await ended;
      final relink = camera.ops.lastIndexOf('connect cam');
      expect(camera.ops.indexOf('write wlan 0', relink), greaterThan(relink));
      expect(s.phase, GrSessionPhase.bluetooth);
      await s.close();
      expect(camera.openLinks, 0);
    });
  });

  test('close while a wake write is in flight turns the camera back off once '
      'it lands', () async {
    final camera = BondedCamera(operationMode: 2)
      ..holdModeWrite = Completer<void>();
    final s = GrSession(
      transport: camera,
      wifi: FailingWifi(),
      options: const GrSessionOptions(wakeSettle: Duration(seconds: 20)),
    );
    await s.connectBluetooth(deviceId: 'cam');
    final waking = s.events.firstWhere((e) => e.kind == 'power.on');
    final started = s.startWifi().then<void>((_) {}, onError: (_) {});
    await waking;
    final closed = s.close(powerOffIfWoken: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    camera.holdModeWrite!.complete();
    final watch = Stopwatch()..start();
    await closed;
    await started;
    // The wake's 20 s drop watch is not waited out.
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(
      camera.ops.indexOf('write power 0'),
      greaterThan(camera.ops.indexOf('write mode 1')),
    );
    expect(camera.ops.where((o) => o.startsWith('write wlan 1')), isEmpty);
    expect(camera.openLinks, 0);
  });

  test(
    'close during the pause between connect attempts opens no new link',
    () async {
      final camera = BondedCamera(dropLinks: 1);
      final s = GrSession(
        transport: camera,
        wifi: FailingWifi(),
        options: const GrSessionOptions(
          bleConnectRetryDelay: Duration(milliseconds: 200),
        ),
      );
      final retried = s.events.firstWhere((e) => e.kind == 'ble.connectRetry');
      final ended = s
          .connect(deviceId: 'cam')
          .then<void>((_) {}, onError: (_) {});
      await retried;
      await s.close();
      await ended;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(camera.ops.where((o) => o == 'connect cam'), hasLength(1));
      expect(camera.openLinks, 0);
    },
  );

  test('camera already on: no operation mode write', () async {
    final camera = BondedCamera();
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(isA<GrSessionException>()),
    );
    expect(camera.ops.where((o) => o.startsWith('write mode')), isEmpty);
  });

  test(
    'connectBluetooth: an off camera keeps its BLE link and is left off',
    () async {
      final camera = BondedCamera(operationMode: 2);
      final s = session(camera);
      await s.connectBluetooth(deviceId: 'cam');
      expect(camera.ops.where((o) => o.startsWith('write mode')), isEmpty);
      expect(camera.ops.where((o) => o.startsWith('write wlan')), isEmpty);
      expect(camera.ops, isNot(contains('disconnect')));
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(s.cameraOff, isTrue);
      await s.close();
    },
  );

  test('bond rejected at connect: needsPairing', () async {
    final camera = BondedCamera(
      connectError: const BleException(
        BleErrorCode.bondRejected,
        'Peer removed pairing information',
      ),
    );
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.needsPairing,
          'needsPairing',
          isTrue,
        ),
      ),
    );
  });

  test('encrypted read refused on a bonded link: needsPairing, and the '
      'link is disconnected', () async {
    final camera = BondedCamera(bonded: false);
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.needsPairing,
          'needsPairing',
          isTrue,
        ),
      ),
    );
    expect(camera.ops.last, 'disconnect');
  });

  test('close(powerOff) writes Camera Power 00 before disconnecting, '
      'without WLAN-off', () async {
    final camera = BondedCamera();
    final s = session(camera);
    await expectLater(
      s.connect(deviceId: 'cam'),
      throwsA(isA<GrSessionException>()),
    );
    await s.close(wlanOff: true, powerOff: true);
    expect(camera.ops.where((o) => o == 'write wlan 0'), isEmpty);
    expect(camera.ops.skipWhile((o) => !o.startsWith('write power')), [
      'write power 0',
      'disconnect',
    ]);
  });

  test('first link drops while the off camera wakes: reconnects and '
      'powers on, as GR WORLD', () async {
    final camera = BondedCamera(operationMode: 2, dropLinks: 1);
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.phase,
          'phase',
          GrSessionPhase.joining,
        ),
      ),
    );
    expect(camera.ops.take(5), [
      'connect cam',
      'dropped',
      'disconnect',
      'connect cam',
      'read mode',
    ]);
    expect(camera.ops, contains('write mode 1'));
  });

  test('gives up after three dropped links', () async {
    final camera = BondedCamera(dropLinks: 5);
    await expectLater(
      session(camera).connect(deviceId: 'cam'),
      throwsA(
        isA<GrSessionException>().having(
          (e) => e.phase,
          'phase',
          GrSessionPhase.bleConnecting,
        ),
      ),
    );
    expect(camera.ops.where((o) => o == 'connect cam'), hasLength(3));
  });

  group('Wi-Fi join', () {
    GrSession withWifi(BondedCamera camera, RecordingWifi wifi) => GrSession(
      transport: camera,
      wifi: wifi,
      options: const GrSessionOptions(
        joinTimeout: Duration(milliseconds: 200),
        joinRetryDelay: Duration(milliseconds: 1),
      ),
    );

    test('a transition-mode camera is joined with WPA2 on every attempt, '
        'so Android asks for approval once', () async {
      final wifi = RecordingWifi();
      await expectLater(
        withWifi(BondedCamera(), wifi).connect(deviceId: 'cam'),
        throwsA(isA<GrSessionException>()),
      );
      expect(wifi.joins.length, greaterThan(1));
      expect(wifi.joins, everyElement(WifiSecurity.wpa2));
    });

    test('a WPA3-only camera is joined with WPA3', () async {
      final wifi = RecordingWifi();
      await expectLater(
        withWifi(BondedCamera(security: 1), wifi).connect(deviceId: 'cam'),
        throwsA(isA<GrSessionException>()),
      );
      expect(wifi.joins, isNotEmpty);
      expect(wifi.joins, everyElement(WifiSecurity.wpa3));
    });

    test('a declined join is not retried, although time is left', () async {
      final wifi = RecordingWifi(first: const WifiJoinDeclined());
      await expectLater(
        withWifi(BondedCamera(), wifi).connect(deviceId: 'cam'),
        throwsA(
          isA<GrSessionException>()
              .having((e) => e.wifiDeclined, 'wifiDeclined', isTrue)
              .having((e) => e.needsPairing, 'needsPairing', isFalse),
        ),
      );
      expect(wifi.joins, hasLength(1));
    });
  });

  group('wake', () {
    Future<void> until(bool Function() condition) async {
      final watch = Stopwatch()..start();
      while (!condition()) {
        if (watch.elapsed > const Duration(seconds: 5)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    GrSession withSettle(
      BondedCamera camera,
      Duration settle, {
      WifiNetworkControl? wifi,
    }) => GrSession(
      transport: camera,
      wifi: wifi ?? FailingWifi(),
      options: GrSessionOptions(
        joinTimeout: const Duration(seconds: 2),
        joinRetryDelay: const Duration(milliseconds: 1),
        wakeSettle: settle,
      ),
    );

    Iterable<String> modeWrites(BondedCamera camera) =>
        camera.ops.where((o) => o.startsWith('write mode'));

    test('an off camera that drops the link while it boots is linked '
        'again, and the mode is checked on the new link', () async {
      final camera = BondedCamera(operationMode: 2);
      final s = withSettle(camera, const Duration(seconds: 5));
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: 'cam');
      expect(s.cameraOff, isTrue);

      final watch = Stopwatch()..start();
      final woke = s.wake(BleOperationMode.capture);
      await until(() => camera.ops.contains('write mode 0'));
      expect(s.phase, GrSessionPhase.waking);
      camera.dropAll();
      await woke;
      await Future<void>.delayed(Duration.zero);
      // The drop ends the watch; the 5 s settle is not waited out.
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(modeWrites(camera), ['write mode 0']);
      final relink = camera.ops.lastIndexOf('connect cam');
      expect(relink, greaterThan(camera.ops.indexOf('write mode 0')));
      expect(camera.ops.indexOf('read mode', relink), greaterThan(relink));
      expect(
        kinds,
        containsAllInOrder(['power.on', 'power.relink', 'ble.ready']),
      );
      expect(kinds.last, 'wake.done');
      expect(kinds, isNot(contains('power.onLinked')));
      expect(kinds, isNot(contains('ble.lost')));
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(s.cameraOff, isFalse);
      expect(s.wokeCamera, isTrue);
      expect(s.ble, isNotNull);
      await s.close();
    });

    test('an off camera that keeps the link is on once the settle time has '
        'passed, without a second write or read', () async {
      final camera = BondedCamera(operationMode: 2);
      final s = withSettle(camera, const Duration(milliseconds: 30));
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: 'cam');

      await s.wake(BleOperationMode.capture);
      await Future<void>.delayed(Duration.zero);
      expect(modeWrites(camera), ['write mode 0']);
      expect(
        camera.ops.skipWhile((o) => o != 'write mode 0'),
        isNot(contains('read mode')),
      );
      expect(camera.ops.where((o) => o == 'connect cam'), hasLength(1));
      expect(
        kinds,
        containsAllInOrder(['power.on', 'power.onLinked', 'wake.done']),
      );
      expect(kinds, isNot(contains('power.relink')));
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(s.cameraOff, isFalse);
      expect(s.wokeCamera, isTrue);
      await s.close();
    });

    for (final (from, writes) in [
      (BleOperationMode.playback, ['write mode 0']),
      (BleOperationMode.capture, <String>[]),
      (BleOperationMode.other, <String>[]),
    ]) {
      test('a camera that is on in ${from.name}: GR WORLD ensure-mode '
          '${writes.isEmpty ? 'leaves it' : 'writes capture'}', () async {
        final camera = BondedCamera(operationMode: from.wire);
        final s = withSettle(camera, const Duration(milliseconds: 30));
        final kinds = <String>[];
        s.events.listen((e) => kinds.add(e.kind));
        await s.connectBluetooth(deviceId: 'cam');
        final reads = camera.ops.where((o) => o == 'read mode').length;

        await s.wake(BleOperationMode.capture);
        await Future<void>.delayed(Duration.zero);
        expect(camera.ops.where((o) => o == 'read mode'), hasLength(reads + 1));
        expect(modeWrites(camera), writes);
        expect(kinds.contains('mode.set'), writes.isNotEmpty);
        expect(kinds, isNot(contains('power.on')));
        expect(s.phase, GrSessionPhase.bluetooth);
        expect(s.wokeCamera, isFalse);
        await s.close();
      });
    }

    test('powerOffIfWoken turns a camera the wake turned on back off; '
        'one that was on is left on', () async {
      final woken = BondedCamera(operationMode: 2);
      final s = withSettle(woken, const Duration(milliseconds: 30));
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: 'cam');
      await s.wake(BleOperationMode.capture);
      await s.powerOffIfWoken();
      await Future<void>.delayed(Duration.zero);
      expect(woken.ops.last, 'write power 0');
      expect(kinds, contains('power.off'));
      expect(s.wokeCamera, isFalse);
      expect(s.cameraOff, isTrue);
      expect(s.phase, GrSessionPhase.bluetooth);
      await s.close();

      final on = BondedCamera();
      final t = withSettle(on, const Duration(milliseconds: 30));
      await t.connectBluetooth(deviceId: 'cam');
      await t.wake(BleOperationMode.capture);
      await t.powerOffIfWoken();
      expect(on.ops.where((o) => o.startsWith('write power')), isEmpty);
      await t.close();
    });

    test('powerOffIfWoken cuts a wake short and turns the camera off once '
        'its write lands', () async {
      final camera = BondedCamera(operationMode: 2)
        ..holdModeWrite = Completer<void>();
      final s = withSettle(camera, const Duration(seconds: 20));
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: 'cam');
      final woke = expectLater(
        s.wake(BleOperationMode.capture),
        throwsA(isA<GrSessionException>()),
      );
      await until(() => kinds.contains('power.on'));
      final watch = Stopwatch()..start();
      final off = s.powerOffIfWoken();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      camera.holdModeWrite!.complete();
      await off;
      await woke;
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
        camera.ops.indexOf('write power 0'),
        greaterThan(camera.ops.indexOf('write mode 0')),
      );
      expect(s.wokeCamera, isFalse);
      expect(s.phase, GrSessionPhase.bluetooth);
      await s.close();
    });

    test('wokeCamera survives stopWifi, so the camera can be turned off '
        'later', () async {
      final camera = BondedCamera(operationMode: 2);
      final s = withSettle(
        camera,
        const Duration(milliseconds: 30),
        wifi: SearchingWifi(),
      );
      await s.connectBluetooth(deviceId: 'cam');
      final started = s.startWifi().then<void>((_) {}, onError: (_) {});
      await until(() => s.phase == GrSessionPhase.joining);
      await s.stopWifi();
      await started;
      expect(camera.ops, contains('write wlan 0'));
      expect(camera.ops.where((o) => o.startsWith('write power')), isEmpty);
      expect(s.wokeCamera, isTrue);

      await s.powerOffIfWoken();
      expect(camera.ops.last, 'write power 0');
      expect(s.wokeCamera, isFalse);
      await s.close();
    });

    test("a wake during a Wi-Fi start waits for the start's own wake and "
        'its watch over the link, then ensures the mode', () async {
      final camera = BondedCamera(operationMode: 2)
        ..holdModeWrite = Completer<void>();
      final s = withSettle(
        camera,
        const Duration(milliseconds: 50),
        wifi: SearchingWifi(),
      );
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: 'cam');
      final started = s.startWifi().then<void>((_) {}, onError: (_) {});
      await until(() => kinds.contains('power.on'));
      final woke = s.wake(BleOperationMode.capture);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(modeWrites(camera), isEmpty);
      camera.holdModeWrite!.complete();
      await woke;
      expect(modeWrites(camera), ['write mode 1', 'write mode 0']);
      expect(kinds.where((k) => k == 'power.on'), hasLength(1));
      // The start's second WLAN-on after its settle came first.
      expect(
        camera.ops.lastIndexOf('write wlan 1'),
        lessThan(camera.ops.indexOf('write mode 0')),
      );
      expect(camera.ops.where((o) => o == 'write wlan 1'), hasLength(2));
      expect(s.phase, GrSessionPhase.joining);
      await s.stopWifi();
      await started;
      expect(s.wokeCamera, isTrue);
      await s.close();
    });

    test('startWifi during a wake from bluetooth waits for it, then joins '
        'without a second wake write', () async {
      final camera = BondedCamera(operationMode: 2)
        ..holdModeWrite = Completer<void>();
      final s = withSettle(
        camera,
        const Duration(milliseconds: 50),
        wifi: SearchingWifi(),
      );
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: 'cam');
      final woke = s.wake(BleOperationMode.capture);
      await until(() => kinds.contains('power.on'));
      expect(s.phase, GrSessionPhase.waking);
      final started = s.startWifi().then<void>((_) {}, onError: (_) {});
      camera.holdModeWrite!.complete();
      await woke;
      await until(() => s.phase == GrSessionPhase.joining);
      expect(modeWrites(camera), ['write mode 0']);
      expect(kinds.where((k) => k == 'power.on'), hasLength(1));
      expect(
        camera.ops.indexOf('write wlan 1'),
        greaterThan(camera.ops.indexOf('write mode 0')),
      );
      expect(kinds.indexOf('wlan.on'), greaterThan(kinds.indexOf('wake.done')));
      await s.stopWifi();
      await started;
      expect(s.wokeCamera, isTrue);
      await s.close();
    });

    test('stopWifi while startWifi waits for a wake ends both; nothing is '
        'written to WLAN', () async {
      final camera = BondedCamera(operationMode: 2)
        ..holdModeWrite = Completer<void>();
      final s = withSettle(
        camera,
        const Duration(seconds: 20),
        wifi: SearchingWifi(),
      );
      final kinds = <String>[];
      s.events.listen((e) => kinds.add(e.kind));
      await s.connectBluetooth(deviceId: 'cam');
      final woke = expectLater(
        s.wake(BleOperationMode.capture),
        throwsA(isA<GrSessionException>()),
      );
      await until(() => kinds.contains('power.on'));
      final started = expectLater(
        s.startWifi(),
        throwsA(isA<GrSessionException>()),
      );
      final stopped = s.stopWifi();
      camera.holdModeWrite!.complete();
      await stopped;
      await woke;
      await started;
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(camera.ops.where((o) => o == 'write wlan 1'), isEmpty);
      expect(modeWrites(camera), ['write mode 0']);
      expect(s.wokeCamera, isTrue);
      await s.close();
    });

    test('wake is not allowed before Bluetooth is linked; powerOffIfWoken '
        'does nothing then, nor while a Wi-Fi start runs', () async {
      final camera = BondedCamera(operationMode: 2);
      final s = withSettle(
        camera,
        const Duration(milliseconds: 30),
        wifi: SearchingWifi(),
      );
      expect(() => s.wake(BleOperationMode.capture), throwsStateError);
      await s.powerOffIfWoken();

      await s.connectBluetooth(deviceId: 'cam');
      final started = s.startWifi().then<void>((_) {}, onError: (_) {});
      await until(() => s.phase == GrSessionPhase.joining);
      expect(s.wokeCamera, isTrue);
      await s.powerOffIfWoken();
      expect(camera.ops.where((o) => o.startsWith('write power')), isEmpty);
      expect(s.phase, GrSessionPhase.joining);
      await s.stopWifi();
      await started;
      await s.close();
    });
  });

  Future<GrSessionEvent> next(GrSession s, String kind) =>
      s.events.firstWhere((e) => e.kind == kind);

  group("the phone's Wi-Fi join", () {
    for (final (problem, props, verifyTimeout) in [
      (
        'meets a different camera',
        {...cameraProps, 'serialNo': '9999999'},
        const Duration(seconds: 5),
      ),
      ('gets no answer from the camera', null, Duration.zero),
    ]) {
      test('a start that joins but $problem releases the join, and a later '
          'start connects', () async {
        final camera = BondedCamera();
        final wifi = JoiningWifi();
        final server = await CameraServer.start()
          ..props = props;
        final s = wifiSession(
          camera,
          wifi,
          server,
          verifyTimeout: verifyTimeout,
        );
        await s.connectBluetooth(deviceId: 'cam');
        await expectLater(
          s.startWifi(),
          throwsA(
            isA<GrSessionException>().having(
              (e) => e.phase,
              'phase',
              GrSessionPhase.verifying,
            ),
          ),
        );
        expect(wifi.joins, 1);
        expect(wifi.joined, isFalse);
        expect(s.phase, GrSessionPhase.bluetooth);
        expect(s.http, isNull);
        expect(s.changes, isNull);
        expect(s.liveness, isNull);

        server.props = cameraProps;
        await s.startWifi();
        expect(s.phase, GrSessionPhase.connected);
        expect(wifi.joins, 2);
        expect(wifi.joined, isTrue);
        await s.close();
      });
    }

    test('close with default arguments releases the join of a connected '
        'session', () async {
      final camera = BondedCamera();
      final wifi = JoiningWifi();
      final s = wifiSession(camera, wifi, await CameraServer.start());
      await s.connect(deviceId: 'cam');
      expect(wifi.joined, isTrue);
      await s.close();
      expect(wifi.leaves, 1);
      expect(wifi.joined, isFalse);
      expect(camera.ops.where((o) => o == 'write wlan 0'), isEmpty);
    });

    test('close with default arguments releases a pending join, and again '
        'when that join completes all the same', () async {
      final camera = BondedCamera();
      final wifi = JoiningWifi()
        ..holdJoin = Completer<void>()
        ..leaveMissesJoin = true;
      final s = wifiSession(camera, wifi, await CameraServer.start());
      await s.connectBluetooth(deviceId: 'cam');
      final started = expectLater(
        s.startWifi(),
        throwsA(isA<GrSessionException>()),
      );
      await wifi.joinStarted.future;
      await s.close();
      expect(wifi.leaves, 1);

      wifi.holdJoin!.complete();
      await started;
      expect(wifi.joined, isFalse);
      expect(wifi.leaves, 2);
      expect(s.phase, GrSessionPhase.closed);
    });
  });

  group('a Bluetooth drop', () {
    GrSession dropSession(BondedCamera camera, {TraceSink? trace}) => GrSession(
      transport: camera,
      wifi: FailingWifi(),
      trace: trace,
      options: const GrSessionOptions(
        joinTimeout: Duration(milliseconds: 10),
        joinRetryDelay: Duration(milliseconds: 1),
        wakeSettle: Duration(seconds: 20),
        bleReconnectDelays: [Duration.zero],
      ),
    );

    for (final viaStart in [false, true]) {
      test('while the wake write of ${viaStart ? 'a Wi-Fi start' : 'wake'} '
          'is in flight, which then fails, leaves no dead link', () async {
        final camera = BondedCamera(operationMode: 2)
          ..holdModeWrite = Completer<void>();
        final s = dropSession(camera);
        await s.connectBluetooth(deviceId: 'cam');
        final old = s.ble;
        final poweringOn = next(s, 'power.on');
        final restored = next(s, 'ble.restored');
        final woke = expectLater(
          viaStart ? s.startWifi() : s.wake(BleOperationMode.capture),
          throwsA(isA<GrSessionException>()),
        );
        await poweringOn;
        camera
          ..dropAll()
          ..holdModeWrite!.complete();
        await woke;
        expect(s.ble, isNot(same(old)));
        await restored;
        expect(s.ble, allOf(isNotNull, isNot(same(old))));
        expect(camera.openLinks, 1);
        expect(s.phase, GrSessionPhase.bluetooth);
        await s.close();
      }, timeout: const Timeout(Duration(seconds: 10)));
    }

    test(
      'of a link the reconnect just restored is reconnected again',
      () async {
        final camera = BondedCamera();
        var restores = 0;
        final s = dropSession(
          camera,
          trace: (e) {
            // The restored link drops the moment the reconnect reports it,
            // before that reconnect has ended.
            if (e.kind == 'session.ble.restored' && ++restores == 1) {
              camera.dropAll();
            }
          },
        );
        await s.connectBluetooth(deviceId: 'cam');
        final restored = s.events
            .where((e) => e.kind == 'ble.restored')
            .take(2)
            .toList();
        camera.dropAll();
        await restored;
        expect(restores, 2);
        expect(s.ble, isNotNull);
        expect(camera.openLinks, 1);
        await s.close();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('close is final', () {
    test('a change socket handshake still running at close starts nothing '
        'and changes no phase', () async {
      final wifi = JoiningWifi();
      final server = await CameraServer.start()
        ..holdUpgrade = Completer<void>();
      final s = wifiSession(BondedCamera(), wifi, server);
      await s.connectBluetooth(deviceId: 'cam');
      final upgrading = server.upgradeRequested.first;
      final started = expectLater(
        s.startWifi(),
        throwsA(isA<GrSessionException>()),
      );
      await upgrading;
      await s.close();
      final probes = server.propsRequests;

      server.holdUpgrade!.complete();
      await started;
      await pumpEventQueue();
      expect(s.phase, GrSessionPhase.closed);
      expect(s.liveness, isNull);
      expect(s.changes, isNull);
      expect(s.http, isNull);
      expect(wifi.joined, isFalse);
      expect(server.propsRequests, probes);
    });

    test('a recovery whose change socket handshake is still running at '
        'close starts nothing', () async {
      final wifi = JoiningWifi();
      final server = await CameraServer.start();
      final opens = StreamController<String>.broadcast();
      final s = wifiSession(
        BondedCamera(),
        wifi,
        server,
        trace: (e) {
          if (e.kind case 'session.changes.open' || 'session.changes.failed') {
            opens.add(e.kind);
          }
        },
      );
      await s.connect(deviceId: 'cam');
      server.holdUpgrade = Completer<void>();
      final upgrading = server.upgradeRequested.first;
      final recoveryOpen = opens.stream.first;
      wifi.loseNetwork();
      await upgrading;
      await s.close();

      server.holdUpgrade!.complete();
      await recoveryOpen;
      await pumpEventQueue();
      expect(s.phase, GrSessionPhase.closed);
      expect(s.liveness, isNull);
      expect(s.changes, isNull);
      expect(wifi.joined, isFalse);
    });

    test('close ends a scan at once; an advertisement after it changes '
        'nothing', () async {
      final ads = StreamController<BleAdvertisement>();
      final camera = BondedCamera()..advertising = ads;
      final s = session(camera);
      final connecting = expectLater(
        s.connectBluetooth(serial: '1234567'),
        throwsA(isA<GrSessionException>()),
      );
      expect(ads.hasListener, isTrue);
      await s.close();
      await pumpEventQueue();
      expect(ads.hasListener, isFalse);
      await connecting;

      ads.add(
        BleAdvertisement(
          deviceId: 'cam',
          rssi: -58,
          manufacturerData: {
            grRicohCompanyId: Uint8List.fromList([
              grAdvertisingMarker,
              0x01,
              GrModel.gr4Hdf.code,
              0x02,
              for (var shift = 0; shift < 32; shift += 8)
                (1234567 >> shift) & 0xFF,
            ]),
          },
        ),
      );
      await pumpEventQueue();
      expect(s.phase, GrSessionPhase.closed);
      expect(camera.ops, isEmpty);
    });
  });

  group('one Wi-Fi start at a time', () {
    test('two starts at once share one hand-off', () async {
      final camera = BondedCamera();
      final wifi = JoiningWifi();
      final server = await CameraServer.start();
      final s = wifiSession(camera, wifi, server);
      await s.connectBluetooth(deviceId: 'cam');
      await Future.wait([s.startWifi(), s.startWifi()]);
      expect(s.phase, GrSessionPhase.connected);
      expect(wifi.joins, 1);
      expect(server.upgradeRequests, 1);
      expect(camera.ops.where((o) => o == 'write wlan 1'), hasLength(1));
      await s.close();
    });

    test('two starts while a wake runs share one hand-off', () async {
      final camera = BondedCamera(operationMode: 2)
        ..holdModeWrite = Completer<void>();
      final wifi = JoiningWifi();
      final server = await CameraServer.start();
      final s = wifiSession(camera, wifi, server);
      await s.connectBluetooth(deviceId: 'cam');
      final poweringOn = next(s, 'power.on');
      final woke = s.wake(BleOperationMode.capture);
      await poweringOn;
      final starts = Future.wait([s.startWifi(), s.startWifi()]);
      camera.holdModeWrite!.complete();
      await woke;
      await starts;
      expect(s.phase, GrSessionPhase.connected);
      expect(wifi.joins, 1);
      expect(server.upgradeRequests, 1);
      expect(camera.ops.where((o) => o.startsWith('write mode')), [
        'write mode 0',
      ]);
      expect(camera.ops.where((o) => o == 'write wlan 1'), hasLength(1));
      await s.close();
    });

    test('a start while stopWifi is still ending Wi-Fi is refused; one '
        'after it connects', () async {
      final camera = BondedCamera();
      final wifi = JoiningWifi()..holdJoin = Completer<void>();
      final s = wifiSession(camera, wifi, await CameraServer.start());
      await s.connectBluetooth(deviceId: 'cam');
      final started = expectLater(
        s.startWifi(),
        throwsA(isA<GrSessionException>()),
      );
      await wifi.joinStarted.future;
      camera.holdWlanWrite = Completer<void>();
      final stopped = s.stopWifi();
      await started;
      // The stop is at its WLAN-off write, after the start ended.
      await pumpEventQueue();
      expect(s.phase, GrSessionPhase.bluetooth);
      expect(s.startWifi, throwsStateError);

      camera.holdWlanWrite!.complete();
      await stopped;
      expect(camera.ops.last, 'write wlan 0');
      wifi.holdJoin = null;
      await s.startWifi();
      expect(s.phase, GrSessionPhase.connected);
      await s.close();
    });
  });

  group('cancelling while Bluetooth reconnects', () {
    /// A linked camera whose link dropped; the reconnect's connect waits
    /// for [BondedCamera.holdConnect].
    Future<(BondedCamera, GrSession)> reconnecting() async {
      final camera = BondedCamera();
      final s = GrSession(
        transport: camera,
        wifi: FailingWifi(),
        options: const GrSessionOptions(
          joinTimeout: Duration(milliseconds: 10),
          joinRetryDelay: Duration(milliseconds: 1),
          bleReconnectDelays: [Duration.zero],
        ),
      );
      await s.connectBluetooth(deviceId: 'cam');
      final reconnect = next(s, 'ble.reconnect');
      camera
        ..holdConnect = Completer<void>()
        ..dropAll();
      await reconnect;
      return (camera, s);
    }

    test('stopWifi ends a start waiting for it at once; the reconnect goes '
        'on, and nothing is written', () async {
      final (camera, s) = await reconnecting();
      final started = expectLater(
        s.startWifi(),
        throwsA(isA<GrSessionException>()),
      );
      // The start is waiting for the reconnect.
      await pumpEventQueue();
      await s.stopWifi();
      await started;
      expect(s.phase, GrSessionPhase.bluetooth);

      final restored = next(s, 'ble.restored');
      camera.holdConnect!.complete();
      await restored;
      await pumpEventQueue();
      expect(s.ble, isNotNull);
      expect(camera.ops.where((o) => o.startsWith('write')), isEmpty);
      await s.close();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('powerOffIfWoken ends a wake waiting for it at once; the reconnect '
        'goes on, and no mode is written', () async {
      final (camera, s) = await reconnecting();
      final woke = expectLater(
        s.wake(BleOperationMode.capture),
        throwsA(isA<GrSessionException>()),
      );
      await s.powerOffIfWoken();
      await woke;

      final restored = next(s, 'ble.restored');
      camera.holdConnect!.complete();
      await restored;
      await pumpEventQueue();
      expect(s.ble, isNotNull);
      expect(camera.ops.where((o) => o.startsWith('write')), isEmpty);
      await s.close();
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  test('a refused first change socket open is retried while HTTP polling '
      'runs, without rejoining Wi-Fi', () async {
    final camera = BondedCamera();
    final wifi = JoiningWifi();
    final server = await CameraServer.start()
      ..refuseUpgrades = 1;
    final s = wifiSession(camera, wifi, server);
    await s.connect(deviceId: 'cam');
    final changes = s.changes!;
    expect(changes.status.state, GrSocketState.reconnectWaiting);

    await changes.statuses
        .firstWhere((status) => status.state == GrSocketState.open)
        .timeout(const Duration(seconds: 5));
    final event = changes.events.first;
    server.sockets.single.add('{"changed":"battery"}');
    expect((await event).changed, 'battery');
    expect(server.upgradeRequests, 2);
    expect(s.phase, GrSessionPhase.connected);
    expect(wifi.joins, 1);
    expect(wifi.leaves, 0);
    expect(camera.ops.where((o) => o == 'write wlan 0'), isEmpty);
    await s.close();
  });
}
