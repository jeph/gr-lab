import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Collects a download in memory.
final class _Bytes implements StreamSink<List<int>> {
  final builder = BytesBuilder(copy: false);
  final _done = Completer<void>();

  @override
  void add(List<int> data) => builder.add(data);

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

void main() {
  late FakeGrCamera camera;
  late GrHttpClient http;

  Future<void> start(FakeCameraConfig config, {FakeMediaSource? media}) async {
    camera = await startCamera(config, media: media);
    http = camera.httpClient('192.168.0.1', null);
  }

  tearDown(() async {
    http.close(force: true);
    await camera.close();
  });

  test('props: identity, Wi-Fi credentials and both storages', () async {
    await start(fastConfig());
    final props = await http.props();
    expect(props.ok, isTrue);
    expect(props.model, 'RICOH GR IV');
    expect(props.serialNo, '1234567');
    expect(props.firmwareVersion, '1.20');
    expect(props.ssid, camera.config.ssid);
    expect(props.wifiKey, camera.config.passphrase);
    expect(props.bdName, camera.config.bluetoothName);
    expect(props.battery, camera.config.battery);
    expect(props.storages.map((s) => s.name), ['in', 'sd1']);
    final sd = props.storages.last;
    expect(sd.equipped, isTrue);
    expect(
      sd.fields.integer('numOfPhotos')! + sd.fields.integer('numOfMovies')!,
      camera.photos.length,
    );
    expect(
      verifyCameraProps(
        props,
        expectedSsid: camera.config.ssid,
        expectedSerial: '1234567',
        expectedModel: 'RICOH GR IV',
      ),
      isEmpty,
    );
    expect((await http.ping()).datetime, isNotNull);
  });

  test('paging returns every file exactly once, in camera order', () async {
    await start(fastConfig());
    final expected = camera.photos.map((p) => p.path).toSet();

    for (final limit in [1, 7, 58, 1000]) {
      final seen = <GrPhotoPath>[];
      await for (final page in http.photoPages(limit: limit)) {
        expect(page.fileCount, lessThanOrEqualTo(limit));
        seen.addAll(page.paths);
      }
      expect(seen.toSet(), expected, reason: 'limit $limit');
      expect(seen, hasLength(expected.length), reason: 'limit $limit');
    }

    final all = (await http.photos()).paths;
    expect(all, hasLength(expected.length));
    final i = all.indexOf(GrPhotoPath('100RICOH', 'R0000231.JPG'));
    expect(all[i + 1], GrPhotoPath('100RICOH', 'R0000231.DNG'));
    expect(all.first.dir, '100RICOH');
    expect(all.last.dir, '101RICOH');
  });

  test('pages follow the camera page size when no limit is sent', () async {
    final photos = [
      for (var i = 0; i < 25; i++)
        FakePhoto(
          '100RICOH',
          'R${(i + 1).toString().padLeft(7, '0')}.JPG',
          DateTime(2026, 11, 1, 12, i),
        ),
    ];
    await start(
      FakeCameraConfig(
        photos: photos,
        pageSize: 10,
        httpLatency: Duration.zero,
      ),
    );
    final first = await http.photos();
    expect(first.fileCount, 10);
    final next = await http.photos(after: first.last);
    expect(next.paths.first, photos[10].path);
    final past = await http.photos(after: photos.last.path);
    expect(past.fileCount, 0);
  });

  test('storages are separate; the same name may exist on both', () async {
    final at = DateTime(2026, 11, 1, 9);
    await start(
      fastConfig(
        photos: [
          FakePhoto('100RICOH', 'R0000001.JPG', at, size: 111),
          FakePhoto('100RICOH', 'R0000001.JPG', at, size: 222, storage: 'in'),
          FakePhoto('100RICOH', 'R0000002.JPG', at, storage: 'in'),
        ],
      ),
    );
    expect((await http.photos()).paths, [
      GrPhotoPath('100RICOH', 'R0000001.JPG'),
    ]);
    expect((await http.photos(storage: 'in')).fileCount, 2);
    final p = GrPhotoPath('100RICOH', 'R0000001.JPG');
    expect((await http.photoInfo(p)).size, 111);
    expect((await http.photoInfo(p, storage: 'in')).size, 222);
    expect((await http.photoInfo(p, storage: 'sd1')).size, 111);
  });

  test('without an SD card listings read internal memory', () async {
    await start(
      fastConfig(
        sdCard: false,
        photos: [
          FakePhoto('100RICOH', 'R0000001.JPG', DateTime(2026), storage: 'in'),
        ],
      ),
    );
    expect((await http.props()).storages.map((s) => s.name), ['in']);
    expect((await http.photos()).fileCount, 1);
  });

  test(
    'info: size matches the full download; movies report duration',
    () async {
      final media = syntheticMedia();
      await start(fastConfig(), media: media);
      final jpeg = camera.photos.firstWhere((p) => p.extension == 'JPG');
      final info = await http.photoInfo(jpeg.path);
      expect(info.ok, isTrue);
      expect(info.cameraModel, 'RICOH GR IV');
      expect(info.dir, jpeg.dir);
      expect(info.file, jpeg.file);
      expect(info.size, (await media(jpeg, GrImageSize.full)).length);
      expect(info.datetime, matches(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$'));
      expect(DateTime.parse(info.datetime!), jpeg.dateTime);
      expect(info.av, jpeg.av);
      expect(info.tv, jpeg.tv);

      final movie = camera.photos.firstWhere((p) => p.isVideo);
      final movieInfo = await http.photoInfo(movie.path);
      expect(movieInfo.duration, movie.videoLength!.inSeconds);
      expect(movieInfo.resolution, '1920x1080');
    },
  );

  test('full download: bytes and Content-Length match the source', () async {
    final media = syntheticMedia();
    await start(fastConfig(), media: media);
    for (final photo in [
      camera.photos.firstWhere((p) => p.extension == 'JPG'),
      camera.photos.firstWhere((p) => p.isRaw),
      camera.photos.firstWhere((p) => p.isVideo),
    ]) {
      final expected = await media(photo, GrImageSize.full);
      final sink = _Bytes();
      int? lastTotal;
      final result = await http.download(
        photo.path,
        sink,
        onProgress: (_, total) => lastTotal = total,
      );
      expect(sink.builder.takeBytes(), expected, reason: photo.file);
      expect(result.contentLength, expected.length);
      expect(result.bytes, expected.length);
      expect(lastTotal, expected.length);
    }
  });

  test(
    'thumb, view and xs are JPEGs; downloadToFile writes the file',
    () async {
      await start(fastConfig());
      final raw = camera.photos.firstWhere((p) => p.isRaw);
      for (final size in [
        GrImageSize.thumb,
        GrImageSize.view,
        GrImageSize.xs,
      ]) {
        final sink = _Bytes();
        final result = await http.download(raw.path, sink, size: size);
        expect(result.contentType, startsWith('image/jpeg'));
        expect(sink.builder.takeBytes().take(2), [0xFF, 0xD8]);
      }
      final dir = await Directory.systemTemp.createTemp('gr_fake_camera');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/${raw.file}');
      final result = await http.downloadToFile(raw.path, file);
      expect(await file.length(), result.bytes);
    },
  );

  test('missing file is 404; a failing media source is 500', () async {
    await start(
      fastConfig(),
      media: (photo, size) async => throw StateError('disk error'),
    );
    final missing = GrPhotoPath('100RICOH', 'R9999999.JPG');
    Matcher api(int code) => throwsA(
      isA<GrApiException>().having((e) => e.errCode, 'errCode', code),
    );
    await expectLater(http.photoInfo(missing), api(404));
    await expectLater(http.download(missing, _Bytes()), api(404));
    final photo = camera.photos.first;
    await expectLater(http.download(photo.path, _Bytes()), api(500));
    await expectLater(http.photoInfo(photo.path), api(500));
    // GR III/IV answer the unsupported /latest route with errCode 400.
    await expectLater(http.latestPhotoInfo(), api(400));
  });

  test('a transfer cut mid-stream is detected as truncated', () async {
    await start(fastConfig(cutDownloadsAfterBytes: 50000));
    final photo = camera.photos.first;
    final sink = _Bytes();
    await expectLater(
      http.download(photo.path, sink),
      throwsA(
        anyOf(
          isA<GrMalformedResponseException>(),
          isA<HttpException>(),
          isA<SocketException>(),
        ),
      ),
    );
    expect(sink.builder.length, lessThanOrEqualTo(50000));
    // Previews are not cut.
    await http.download(photo.path, _Bytes(), size: GrImageSize.thumb);
  });

  test('a client hanging up mid-download leaves the server serving', () async {
    await start(fastConfig(downloadBytesPerSecond: 200 * 1024));
    final photo = camera.photos.first;
    final raw = HttpClient();
    final request = await raw.getUrl(
      http.photoUri(photo.path, size: GrImageSize.full),
    );
    final response = await request.close();
    expect(response.contentLength, greaterThan(0));
    await response.first;
    raw.close(force: true);

    await Future<void>.delayed(ms(100));
    expect((await http.props()).ok, isTrue);
    final sink = _Bytes();
    final result = await http.download(
      photo.path,
      sink,
      size: GrImageSize.view,
    );
    expect(result.bytes, result.contentLength);
  });

  test('when the access point drops HTTP stops answering, and returns '
      'after WLAN-on', () async {
    await start(fastConfig(bonded: true));
    camera.dropWifi();
    await expectLater(http.props(), throwsA(anything));

    final link = await camera.transport.connect(
      camera.config.deviceId,
      timeout: const Duration(seconds: 1),
    );
    addTearDown(link.disconnect);
    final client = GrBleClient(link);
    await client.discover();
    await client.setWlan(true);
    await Future<void>.delayed(ms(60));
    expect((await http.props()).ok, isTrue);
  });

  test('removePhoto takes the file off listings', () async {
    await start(fastConfig());
    final photo = camera.photos.first;
    expect(camera.removePhoto(photo.path), isTrue);
    expect(camera.removePhoto(photo.path), isFalse);
    expect((await http.photos()).paths, isNot(contains(photo.path)));
    await expectLater(
      http.photoInfo(photo.path),
      throwsA(isA<GrApiException>()),
    );
  });
}
