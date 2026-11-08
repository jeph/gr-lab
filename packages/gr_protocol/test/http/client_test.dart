import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gr_protocol/src/http/http.dart';
import 'package:gr_protocol/src/trace.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// A request as the loopback server saw it.
typedef Seen = ({String method, String uri, String? contentType, String body});

void main() {
  late HttpServer server;
  late GrHttpClient client;
  late List<Seen> seen;
  late Future<void> Function(HttpRequest request) handler;
  late List<TraceEvent> trace;

  setUp(() async {
    seen = [];
    trace = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.add((
        method: request.method,
        uri: request.uri.toString(),
        contentType: request.headers.value(HttpHeaders.contentTypeHeader),
        body: body,
      ));
      await handler(request);
    });
    client = GrHttpClient('127.0.0.1', port: server.port, trace: trace.add);
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  void respond(String json, {int status = 200}) {
    handler = (request) async {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(json);
      await request.response.close();
    };
  }

  test('props round trip with quirk, typed fields and trace', () async {
    respond(
      '{"errCode":200,"errMsg":"OK","model":"RICOH GR IV HDF","serialNo":"1234",'
      '"bdName":"GR_1","battery":4294967295,"svList":["auto","100"],"sv":"auto"}',
    );
    final props = await client.props();
    expect(seen.single.method, 'GET');
    expect(seen.single.uri, '/v1/props');
    expect(props.model, 'RICOH GR IV HDF');
    expect(props.battery, -2147483648);
    expect(props.offers('sv', '100'), isTrue);
    expect(trace.map((e) => (e.channel, e.direction, e.kind)), [
      (TraceChannel.http, TraceDirection.outbound, 'request'),
      (TraceChannel.http, TraceDirection.inbound, 'response'),
    ]);
    expect(trace.last.fields['status'], 200);
    expect(jsonEncode(trace.last.fields), contains('RICOH GR IV HDF'));
  });

  test(
    'errCode ≠ 200 raises GrApiException regardless of HTTP status',
    () async {
      respond('{"errCode":412,"errMsg":"Precondition Failed"}');
      await expectLater(
        client.shoot(af: GrShootAf.on),
        throwsA(
          isA<GrApiException>()
              .having((e) => e.errCode, 'errCode', 412)
              .having((e) => e.httpStatus, 'httpStatus', 200)
              .having((e) => e.route, 'route', 'POST /v1/camera/shoot'),
        ),
      );
    },
  );

  test('non-JSON error status raises GrHttpStatusException', () async {
    handler = (request) async {
      request.response
        ..statusCode = 404
        ..write('404 Not Found');
      await request.response.close();
    };
    await expectLater(
      client.photoInfo(GrPhotoPath('100RICOH', 'R1.JPG')),
      throwsA(
        isA<GrHttpStatusException>()
            .having((e) => e.httpStatus, 'httpStatus', 404)
            .having((e) => e.bodyText, 'bodyText', '404 Not Found'),
      ),
    );
  });

  test('camera params are sent as text/plain without URL-encoding', () async {
    respond('{"errCode":200,"xv":"+0.3"}');
    final props = await client.setCameraParams({
      'xv': '+0.3',
      'WBMode': 'daylight',
    });
    expect(props.fields.string('xv'), '+0.3');
    expect(seen.single, (
      method: 'PUT',
      uri: '/v1/params/camera',
      contentType: 'text/plain; charset=utf-8',
      body: 'xv=+0.3&WBMode=daylight',
    ));
  });

  test('request bodies match each app exactly', () async {
    respond('{"errCode":200}');
    final p = GrPhotoPath('100RICOH', 'R0000001.JPG');
    await client.markTransferred(p, storage: 'sd1');
    await client.markTransferred(
      p,
      style: GrTransferMarkStyle.imageSync,
      storage: 'sd1',
    );
    await client.setGr2WifiSettings(ssid: 'GR_1', key: 'pa+ss');
    await client.focus(pos: GrFocusPoint(50, 40));
    await client.powerOff();
    await client.prepareFirmware(1234);
    await client.uploadEndScreen(
      2,
      jpeg: Uint8List.fromList(ascii.encode('abc')),
    );
    expect(seen, [
      (
        method: 'PUT',
        uri: '/v1/photos/100RICOH/R0000001.JPG/transfer',
        contentType: 'application/json',
        body: 'storage=sd1',
      ),
      (
        method: 'PUT',
        uri: '/v1/photos/100RICOH/R0000001.JPG/transfer',
        contentType: 'text/plain; charset=utf-8',
        body: 'status=transferred&storage=sd1',
      ),
      (
        method: 'PUT',
        uri: '/v1/params/device',
        contentType: 'application/json',
        body: 'channel=0&ssid=GR_1&key=pa+ss',
      ),
      (
        method: 'POST',
        uri: '/v1/lens/focus',
        contentType: 'text/plain; charset=utf-8',
        body: 'pos=50,40',
      ),
      (method: 'POST', uri: '/v1/device/finish', contentType: null, body: ''),
      (
        method: 'POST',
        uri: '/v1/configs/firmware/prepare',
        contentType: 'application/x-www-form-urlencoded',
        body: 'filesize=1234',
      ),
      (
        method: 'PUT',
        uri: '/v1/device/image/endscreen?index=2&sha256=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        contentType: 'image/jpeg',
        body: 'abc',
      ),
    ]);
  });

  test('query strings keep the apps parameter order', () async {
    respond('{"errCode":200,"dirs":[],"transfers":[]}');
    await client.photos(
      storage: 'sd1',
      limit: 10,
      after: GrPhotoPath('100RICOH', 'R5.JPG'),
    );
    await client.transfers(storage: 'in');
    expect(seen.map((s) => s.uri), [
      '/v1/photos?storage=sd1&limit=10&after=100RICOH/R5.JPG',
      '/v1/transfers?status=untransferred&storage=in',
    ]);
    expect(
      client
          .photoUri(
            GrPhotoPath('100RICOH', 'R1.JPG'),
            size: GrImageSize.xs,
            storage: 'sd1',
          )
          .toString(),
      'http://127.0.0.1:${server.port}/v1/photos/100RICOH/R1.JPG?size=xs&storage=sd1',
    );
  });

  test('photoPages follows the after cursor until a short page', () async {
    var page = 0;
    handler = (request) async {
      page++;
      final files = page == 1 ? '"R1.JPG","R2.JPG"' : '"R3.JPG"';
      request.response.write(
        '{"errCode":200,"dirs":[{"name":"100RICOH","files":[$files]}]}',
      );
      await request.response.close();
    };
    final pages = await client.photoPages(limit: 2).toList();
    expect(pages.map((p) => p.fileCount), [2, 1]);
    expect(seen.last.uri, '/v1/photos?limit=2&after=100RICOH/R2.JPG');
  });

  test('download streams bytes and detects a JSON error body', () async {
    final image = jpeg();
    handler = (request) async {
      if (request.uri.queryParameters['size'] == 'full') {
        request.response
          ..headers.contentType = ContentType('image', 'jpeg')
          ..contentLength = image.length
          ..add(image);
      } else {
        request.response.write('{"errCode":404,"errMsg":"Not Found"}');
      }
      await request.response.close();
    };
    final p = GrPhotoPath('100RICOH', 'R1.JPG');
    final sink = _CollectingSink();
    final progress = <int>[];
    final result = await client.download(
      p,
      sink,
      onProgress: (n, _) => progress.add(n),
    );
    await sink.close();
    expect(sink.bytes, image);
    expect(result.bytes, image.length);
    expect(result.contentLength, image.length);
    expect(progress.last, image.length);
    await expectLater(
      client.download(p, _CollectingSink(), size: GrImageSize.view),
      throwsA(isA<GrApiException>().having((e) => e.errCode, 'errCode', 404)),
    );
  });

  group('live view', () {
    test('HttpServer chunked multipart stream yields frames', () async {
      final frames = [jpeg(), jpeg(width: 640, height: 360), jpeg()];
      handler = (request) async {
        expect(request.uri.toString(), '/v1/liveview?maxfps=7&reso=720x480');
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'multipart/x-mixed-replace; boundary=--boundary',
        );
        for (final f in frames) {
          request.response
            ..add(partHeader)
            ..add(f)
            ..add(ascii.encode('\r\n'));
          await request.response.flush();
        }
        await request.response.close();
      };
      final lv = await client.openLiveView(maxFps: 7, reso: '720x480');
      expect(lv.statusCode, 200);
      expect(lv.headers['transfer-encoding'], 'chunked');
      final got = await lv.frames.toList();
      expect(got.map((f) => f.jpeg), frames);
      expect(got.map((f) => f.sequence), [1, 2, 3]);
      expect(got[1].dimensions.toString(), '640x360');
      expect(lv.stats.frames, 3);
      expect(lv.stats.resolutions, {'720x480', '640x360'});
    });

    test(
      'raw firmware-style stream; close() drops the socket at once',
      () async {
        final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(raw.close);
        final peerClosed = Completer<void>();
        raw.listen((socket) {
          var sent = false;
          socket.listen(
            (data) {
              if (sent || !latin1.decode(data).contains('\r\n\r\n')) return;
              sent = true;
              socket
                ..add(responseHead)
                ..add(partHeader)
                ..add(jpeg().sublist(0, 40));
              // Second write completes frame one and adds frame two, so the
              // client sees frames split across reads.
              Timer(const Duration(milliseconds: 20), () {
                socket
                  ..add(jpeg().sublist(40))
                  ..add(partHeader)
                  ..add(jpeg());
              });
            },
            onDone: () {
              socket.destroy();
              if (!peerClosed.isCompleted) peerClosed.complete();
            },
            onError: (Object _) {
              if (!peerClosed.isCompleted) peerClosed.complete();
            },
          );
        });
        final lv = await LiveViewStream.open('127.0.0.1', port: raw.port);
        expect(
          lv.headers['content-type'],
          'multipart/x-mixed-replace; boundary=--boundary',
        );
        final first2 = await lv.frames.take(2).toList();
        expect(first2.map((f) => f.jpeg), [jpeg(), jpeg()]);
        await lv.close();
        await peerClosed.future.timeout(const Duration(seconds: 5));
      },
    );

    test('a JSON error response raises GrApiException', () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      raw.listen((socket) {
        var answered = false;
        socket.listen((_) {
          if (answered) return;
          answered = true;
          const body = '{"errCode":400,"errMsg":"Bad Request"}';
          socket
            ..write(
              'HTTP/1.1 400 Bad Request\r\nContent-Length: ${body.length}\r\n\r\n$body',
            )
            ..close().ignore();
        });
      });
      await expectLater(
        LiveViewStream.open('127.0.0.1', port: raw.port),
        throwsA(isA<GrApiException>().having((e) => e.errCode, 'errCode', 400)),
      );
    });

    test('maxfps outside the firmware range is rejected', () {
      expect(
        () => LiveViewStream.liveViewUri('h', maxFps: 0),
        throwsArgumentError,
      );
      expect(
        () => LiveViewStream.liveViewUri('h', maxFps: 91),
        throwsArgumentError,
      );
      expect(
        LiveViewStream.liveViewUri('h').toString(),
        'http://h/v1/liveview',
      );
    });
  });
}

final class _CollectingSink implements StreamSink<List<int>> {
  final BytesBuilder _b = BytesBuilder();
  final Completer<void> _done = Completer();

  Uint8List get bytes => _b.toBytes();

  @override
  void add(List<int> data) => _b.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
