import 'dart:convert';
import 'dart:io';

import 'package:gr_protocol/src/http/http.dart';
import 'package:gr_protocol/src/trace.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 11, 7);
  GrChangeEvent parse(Object? m) => GrChangeEvent.parse(m, receivedAt: at);

  group('GrChangeEvent.parse', () {
    test('GR WORLD kinds', () {
      expect(
        parse('{"errCode":200,"changed":"storage"}'),
        isA<GrStorageChange>(),
      );
      expect(
        parse('{"errCode":200,"changed":"battery"}'),
        isA<GrBatteryChange>(),
      );
      final camera = parse('{"errCode":200,"changed":"camera"}');
      expect(camera, isA<GrCameraChange>());
      expect(camera.ok, isTrue);
      expect(camera.receivedAt, at);
    });

    test('storage add with filepath and captureId', () {
      final e = parse(
        '{"errCode":200,"changed":"storage","action":"add",'
        '"filepath":"100RICOH/R0000010.JPG","storage":"sd1","captureId":"7"}',
      ) as GrStorageChange;
      expect((e.action, e.storage, e.captureId), ('add', 'sd1', '7'));
      expect(e.path, GrPhotoPath('100RICOH', 'R0000010.JPG'));
    });

    test('cameraDirect fields and Image Sync completion rule', () {
      GrCameraDirectChange cd(
        String still,
        String countDown, {
        required bool capturing,
      }) => parse(
        jsonEncode({
          'errCode': 200,
          'changed': 'cameraDirect',
          'stateStill': still,
          'stateMovie': 'idle',
          'countDown': countDown,
          'capturing': capturing,
          'shotsCurrent': 1,
          'shotsTotal': 3,
        }),
      ) as GrCameraDirectChange;
      final done = cd('idle', 'idle', capturing: false);
      expect((done.shotsCurrent, done.shotsTotal), (1, 3));
      expect(done.stillCaptureComplete, isTrue);
      expect(
        cd('continuous', 'idle', capturing: false).stillCaptureComplete,
        isTrue,
      );
      expect(
        cd('busy', 'idle', capturing: false).stillCaptureComplete,
        isFalse,
      );
      expect(
        cd('idle', 'busy10s', capturing: false).stillCaptureComplete,
        isFalse,
      );
      expect(cd('idle', 'idle', capturing: true).stillCaptureComplete, isFalse);
      expect(done.movieCaptureComplete, isTrue);
    });

    test('cameraDirect orientation: the turns Image Sync shows each one '
        'with; other text is no orientation', () {
      GrCameraOrientation? held(Object? value) => (parse(
        jsonEncode({
          'errCode': 200,
          'changed': 'cameraDirect',
          'cameraOrientation': value,
        }),
      ) as GrCameraDirectChange).cameraOrientation;
      expect(
        {
          for (final wire in [
            'none',
            'positive',
            'vertical_right',
            'reverse',
            'vertical_left',
          ])
            wire: held(wire)?.quarterTurns,
        },
        {
          'none': 0,
          'positive': 0,
          'vertical_right': 1,
          'reverse': 2,
          'vertical_left': 3,
        },
      );
      expect(held('sideways'), isNull);
      expect(held(1), isNull);
      expect(held(null), isNull);
    });

    test('lens, capture and transfer payloads', () {
      final lens = parse(
        '{"errCode":200,"changed":"lens","captureId":5,"focused":true}',
      ) as GrLensChange;
      expect((lens.captureId, lens.focused), ('5', true));
      final cap = parse(
        '{"errCode":200,"changed":"capture","captureId":"5"}',
      ) as GrCaptureChange;
      expect(cap.captureId, '5');
      final t = parse(
        '{"errCode":200,"changed":"transfer","action":"state","storage":"in",'
        '"index":4,"filepath":"100RICOH/R1.JPG?xs","size":"xs","state":"transferred"}',
      ) as GrTransferChange;
      expect(
        (t.action, t.index, t.size, t.state),
        ('state', 4, 'xs', 'transferred'),
      );
    });

    test('uses the change alias when changed is absent', () {
      final e = parse('{"errCode":200,"change":"lens","captureId":"1"}');
      expect(e, isA<GrLensChange>());
      expect(e.changed, 'lens');
    });

    test('unknown kinds and error codes are kept raw', () {
      final e = parse('{"errCode":500,"changed":"zoom","x":1}');
      expect(e, isA<GrUnknownChange>());
      expect(e.ok, isFalse);
      expect(e.raw['x'], 1);
      expect(parse('{"errCode":200}'), isA<GrUnknownChange>());
    });

    test('bytes messages and non-JSON never throw', () {
      expect(
        parse(utf8.encode('{"changed":"battery"}')),
        isA<GrBatteryChange>(),
      );
      final bad = parse('not json') as GrUnparsedChange;
      expect(bad.text, 'not json');
      expect(bad.issue, startsWith('not JSON'));
      expect(parse('[1,2]'), isA<GrUnparsedChange>());
      expect(parse(null), isA<GrUnparsedChange>());
    });
  });

  group('reconnect policies', () {
    test('GR WORLD never, Image Sync immediately', () {
      expect(const GrNoReconnect().delayBefore(1), isNull);
      expect(const GrImmediateReconnect().delayBefore(1000), Duration.zero);
    });

    test('backoff is capped and bounded', () {
      const p = GrBackoffReconnect(
        delays: [Duration(seconds: 1), Duration(seconds: 3)],
        maxAttempts: 3,
      );
      expect(
        [for (var i = 1; i <= 4; i++) p.delayBefore(i)],
        [
          const Duration(seconds: 1),
          const Duration(seconds: 3),
          const Duration(seconds: 3),
          null,
        ],
      );
      expect(
        const GrBackoffReconnect(maxAttempts: null).delayBefore(1000),
        const Duration(seconds: 10),
      );
    });
  });

  test('GrChangesSocket receives events from a loopback server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/v1/changes');
      final ws = await WebSocketTransformer.upgrade(request)
        ..add('{"errCode":200,"changed":"battery"}')
        ..add(
          '{"errCode":200,"changed":"lens","captureId":"9","focused":false}',
        );
      await ws.close();
    });
    final socket = GrChangesSocket(
      '127.0.0.1',
      port: server.port,
      reconnect: const GrNoReconnect(),
    );
    final events = <GrChangeEvent>[];
    final sub = socket.events.listen(events.add);
    final disconnected = socket.statuses.firstWhere(
      (s) => s.state == GrSocketState.disconnected,
    );
    await socket.connect();
    expect(socket.status.state, GrSocketState.open);
    await disconnected.timeout(const Duration(seconds: 5));
    expect(events.map((e) => e.changed), ['battery', 'lens']);
    expect((events.last as GrLensChange).focused, isFalse);
    await sub.cancel();
    await socket.close();
    expect(socket.status.state, GrSocketState.closed);
  });

  test('waitFor answers null once the socket closes without a match', () async {
    final socket = GrChangesSocket(
      '127.0.0.1',
      port: 9,
      reconnect: const GrNoReconnect(),
    );
    final lens = socket.waitFor<GrLensChange>(
      (_) => true,
      timeout: const Duration(minutes: 1),
    );
    await socket.close();
    expect(await lens.timeout(const Duration(seconds: 5)), isNull);
  });

  group('GrChangesSocket opens', () {
    /// A loopback `/v1/changes` whose first [refuse] upgrades answer HTTP
    /// 503 and whose first socket is closed at once with [dropFirst]; the
    /// sockets it keeps send one `battery` change. Returns the server and
    /// its upgrade request count.
    Future<(HttpServer, int Function())> serve({
      int refuse = 0,
      bool dropFirst = false,
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        final n = ++requests;
        if (n <= refuse) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(request);
        if (dropFirst && n == 1) return await ws.close();
        ws
          ..add('{"errCode":200,"changed":"battery"}')
          ..listen((_) {});
      });
      return (server, () => requests);
    }

    test('a refused first open is retried by the reconnect policy', () async {
      final (server, requests) = await serve(refuse: 1);
      final socket = GrChangesSocket(
        '127.0.0.1',
        port: server.port,
        reconnect: const GrBackoffReconnect(delays: [Duration.zero]),
      );
      addTearDown(socket.close);
      final open = socket.statuses.firstWhere(
        (s) => s.state == GrSocketState.open,
      );
      final event = socket.events.first;
      await expectLater(socket.connect(), throwsA(isA<WebSocketException>()));
      await open.timeout(const Duration(seconds: 5));
      expect((await event).changed, 'battery');
      expect(requests(), 2);
    });

    test('a refused open without reconnects ends disconnected', () async {
      final (server, _) = await serve(refuse: 1);
      final socket = GrChangesSocket(
        '127.0.0.1',
        port: server.port,
        reconnect: const GrNoReconnect(),
      );
      addTearDown(socket.close);
      await expectLater(socket.connect(), throwsA(isA<WebSocketException>()));
      expect(socket.status.state, GrSocketState.disconnected);
    });

    test('two connects at once share one open', () async {
      final (server, requests) = await serve();
      final opens = <TraceEvent>[];
      final socket = GrChangesSocket(
        '127.0.0.1',
        port: server.port,
        trace: (e) {
          if (e.kind == 'connect') opens.add(e);
        },
      );
      addTearDown(socket.close);
      await Future.wait([socket.connect(), socket.connect()]);
      expect(opens, hasLength(1));
      expect(requests(), 1);
      expect(socket.status.state, GrSocketState.open);
    });

    test('a connect while a reconnect waits takes its place', () async {
      final (server, requests) = await serve(dropFirst: true);
      final opens = <TraceEvent>[];
      final socket = GrChangesSocket(
        '127.0.0.1',
        port: server.port,
        reconnect: const GrImmediateReconnect(),
        trace: (e) {
          if (e.kind == 'connect') opens.add(e);
        },
      );
      addTearDown(socket.close);
      final waiting = socket.statuses.firstWhere(
        (s) => s.state == GrSocketState.reconnectWaiting,
      );
      await socket.connect();
      await waiting;
      // Status events arrive before the reconnect's zero-delay timer runs.
      await socket.connect();
      // A timer due before this one has run by now.
      await Future<void>.delayed(Duration.zero);
      expect(opens, hasLength(2));
      expect(requests(), 2);
      expect(socket.status.state, GrSocketState.open);
    });
  });
}
