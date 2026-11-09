import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_camera/src/library/camera_images.dart' show isJpeg;
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart'
    show
        GrApiException,
        GrHttpClient,
        GrHttpStatusException,
        GrMalformedResponseException;

const serial = '1234567';
final _day1 = DateTime(2026, 11, 4, 9, 30);
final _day2 = DateTime(2026, 11, 5, 18, 2, 7);

List<FakePhoto> card() => [
  FakePhoto('100RICOH', 'R0000001.JPG', _day1, orientation: 6),
  FakePhoto('100RICOH', 'R0000001.DNG', _day1),
  FakePhoto(
    '100RICOH',
    'R0000002.MOV',
    _day2,
    videoLength: const Duration(seconds: 14),
  ),
  FakePhoto('100RICOH', 'R0000001.JPG', _day2, storage: GrStorageId.internal),
];

Future<void> until(
  bool Function() condition, {
  String reason = 'condition',
  Duration timeout = const Duration(seconds: 10),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('Timed out waiting for $reason');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late FakeGrCamera camera;
  late GrHttpClient http;
  late Directory cache;
  late ValueNotifier<CameraLibrary?> link;
  late RequestQueue queue;
  final trace = <TraceEvent>[];
  var requests = 0;
  // Faults for the next thumbnail requests: no answer until the test ends,
  // or bytes that are not a JPEG.
  var stallThumbs = 0;
  var junkThumbs = 0;
  var hang = Completer<void>();

  CameraLibrary connected({
    Stream<GrChangeEvent>? changes,
    List<String?> storages = const [GrStorageId.internal, GrStorageId.sd],
    Future<bool> Function()? checkWifi,
  }) => CameraLibrary.overHttp(
    http,
    serial: serial,
    storages: storages,
    changes: changes,
    checkWifi: checkWifi,
    trace: trace.add,
  );

  /// Session-channel decisions of [kind] recorded so far.
  List<Map<String, Object?>> events(String kind) => [
    for (final e in trace)
      if (e.channel == TraceChannel.session && e.kind == kind) e.fields,
  ];

  Future<void> restartCamera(
    FakeCameraConfig config,
    FakeMediaSource media,
  ) async {
    await camera.close();
    camera = FakeGrCamera(config: config, media: media);
    await camera.startHttp();
    http.close(force: true);
    http = camera.httpClient('127.0.0.1', null);
  }

  setUp(() async {
    HttpOverrides.global = null;
    trace.clear();
    requests = 0;
    stallThumbs = 0;
    junkThumbs = 0;
    hang = Completer<void>();
    final media = syntheticMedia(jpegBytes: 4096, rawBytes: 8192);
    camera = FakeGrCamera(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      media: (photo, size) async {
        requests++;
        if (size == GrImageSize.thumb && stallThumbs > 0) {
          stallThumbs--;
          await hang.future;
        }
        if (size == GrImageSize.thumb && junkThumbs > 0) {
          junkThumbs--;
          return Uint8List.fromList(utf8.encode('<html>busy</html>'));
        }
        return await media(photo, size);
      },
    );
    await camera.startHttp();
    http = camera.httpClient('127.0.0.1', null);
    cache = await Directory.systemTemp.createTemp('gr_camera_lib_');
    link = ValueNotifier(null);
    queue = RequestQueue();
  });

  tearDown(() async {
    if (!hang.isCompleted) hang.complete();
    link.dispose();
    http.close(force: true);
    await camera.close();
    await cache.delete(recursive: true);
  });

  group('CameraLibrary', () {
    test('lists every file of each storage, tracing why', () async {
      final files = await connected().listFiles(reason: 'connected');
      expect(files.map((f) => '$f'), [
        'in:100RICOH/R0000001.JPG',
        'sd1:100RICOH/R0000001.JPG',
        'sd1:100RICOH/R0000001.DNG',
        'sd1:100RICOH/R0000002.MOV',
      ]);
      expect(events('library.list'), [
        {
          'reason': 'connected',
          'storages': [GrStorageId.internal, GrStorageId.sd],
        },
      ]);
      expect(events('library.listed'), [
        {'reason': 'connected', 'files': 4},
      ]);
    });

    test('a storage that answers with an error is left out while another '
        'lists; alone, its error is thrown', () async {
      await restartCamera(
        FakeCameraConfig(
          httpLatency: Duration.zero,
          sdCard: false,
          photos: [
            FakePhoto(
              '100RICOH',
              'R0000001.JPG',
              _day1,
              storage: GrStorageId.internal,
            ),
          ],
        ),
        syntheticMedia(),
      );
      final files = await connected().listFiles();
      expect(files, [
        CameraFile(
          GrStorageId.internal,
          GrPhotoPath('100RICOH', 'R0000001.JPG'),
        ),
      ]);
      expect(
        events('library.storageSkipped').single['storage'],
        GrStorageId.sd,
      );

      await expectLater(
        connected(storages: const [GrStorageId.sd]).listFiles(),
        throwsA(isA<GrApiException>()),
      );
    });

    test("reads a file's /info", () async {
      final library = connected();
      final movie = await library.fileInfo(
        CameraFile(GrStorageId.sd, GrPhotoPath('100RICOH', 'R0000002.MOV')),
      );
      expect(movie.duration, const Duration(seconds: 14));
      expect(movie.taken, _day2);
      expect(movie.size, greaterThan(0));
      final jpeg = await library.fileInfo(
        CameraFile(GrStorageId.sd, GrPhotoPath('100RICOH', 'R0000001.JPG')),
      );
      expect(jpeg.orientation, 6);
      expect(jpeg.taken, _day1);
    });

    test(
      'storageChanges carries storage changes from /v1/changes only',
      () async {
        await expectLater(connected().storageChanges, emitsDone);
        final socket = http.changesSocket();
        await socket.connect();
        addTearDown(socket.close);
        var changes = 0;
        final sub = connected(changes: socket.events).storageChanges
            .listen((_) => changes++);
        addTearDown(sub.cancel);
        camera.addPhoto(FakePhoto('101RICOH', 'R0000003.JPG', _day2));
        await until(() => changes > 0, reason: 'storage change');
        expect(changes, 1);
      },
    );

    test('checkWifi asks the session and records why', () async {
      var answers = false;
      final library = connected(checkWifi: () async => answers);
      expect(await library.checkWifi(after: 'listing'), isFalse);
      answers = true;
      expect(await library.checkWifi(after: 'listing'), isTrue);
      expect(events('library.checkWifi'), [
        {'after': 'listing', 'answers': false},
        {'after': 'listing', 'answers': true},
      ]);
      expect(
        await connected().checkWifi(after: 'listing'),
        isTrue,
        reason: 'without a session the camera counts as answering',
      );
    });

    test('downloadFiles keeps a file finished before a stop and copies only '
        'the rest', () async {
      final files = [
        CameraFile(GrStorageId.sd, GrPhotoPath('100RICOH', 'R0000001.JPG')),
        CameraFile(GrStorageId.sd, GrPhotoPath('100RICOH', 'R0000001.DNG')),
      ];
      Future<List<int>> expected(CameraFile f) => camera.media(
        camera.photos.firstWhere(
          (p) => p.storage == f.storage && p.path == f.path,
        ),
        GrImageSize.full,
      );
      final dir = Directory('${cache.path}/job');
      final library = connected();
      var done = 0;
      await expectLater(
        library.downloadFiles(
          files,
          dir,
          onProgress: (_, _, _, _) {},
          afterFile: () {
            if (++done == 1) throw StateError('stop');
          },
        ),
        throwsStateError,
      );
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), [
        'R0000001.JPG',
      ]);

      final seen = <(int, int)>[];
      final local = await library.downloadFiles(
        files,
        dir,
        onProgress: (bytes, index, received, total) => seen.add((index, bytes)),
      );
      expect(local.map((f) => f.path), [
        '${dir.path}/R0000001.JPG',
        '${dir.path}/R0000001.DNG',
      ]);
      expect(seen.map((s) => s.$1).toSet(), {1}, reason: 'JPG kept');
      final jpeg = await expected(files[0]);
      expect(seen.last.$2, jpeg.length + (await expected(files[1])).length);
      expect(await local[0].readAsBytes(), jpeg);
      expect(await local[1].readAsBytes(), await expected(files[1]));
      expect(events('download.kept').single['file'], '${files[0]}');
    });

    test('tells broken links from refusals', () {
      const route = 'GET /v1/photos/100RICOH/R0000001.JPG';
      const refused = GrApiException(
        errCode: 404,
        route: route,
        httpStatus: 404,
        errMsg: 'Not Found',
      );
      const cut = GrMalformedResponseException(
        route: route,
        httpStatus: 200,
        issue: 'body ended',
      );
      expect(isConnectionError(const SocketException('reset')), isTrue);
      expect(isConnectionError(const HttpException('closed')), isTrue);
      expect(isConnectionError(TimeoutException('quiet')), isTrue);
      expect(isConnectionError(cut), isTrue);
      expect(isConnectionError(refused), isFalse);
      expect(isConnectionError(const FileSystemException('full')), isFalse);

      expect(
        describeTransferError(refused),
        'The camera refused the file (404 Not Found)',
      );
      expect(
        describeTransferError(
          const GrHttpStatusException(route: route, httpStatus: 503),
        ),
        'The camera answered HTTP 503',
      );
      expect(describeTransferError(cut), 'The transfer was cut off');
      expect(
        describeTransferError(const SocketException('reset')),
        'Lost the connection to the camera',
      );
      expect(
        describeTransferError(TimeoutException('quiet')),
        'The camera stopped sending',
      );
      expect(
        describeTransferError(const FileSystemException('No space')),
        'Could not write the file: No space',
      );
    });
  });

  group('CameraImages', () {
    CameraImages images() =>
        CameraImages(cacheDir: cache, link: link, queue: queue);
    final file = CameraFile(
      GrStorageId.sd,
      GrPhotoPath('100RICOH', 'R0000001.JPG'),
    );

    test(
      'fetches a thumbnail once, then serves it from disk offline',
      () async {
        link.value = connected();
        final first = images();
        final bytes = await first.load(serial, file, GrImageSize.thumb).future;
        expect(bytes, isNotNull);
        expect(requests, 1);
        expect(first.cached(serial, file, GrImageSize.thumb), bytes);
        expect(
          File('${cache.path}/$serial/thumbs/${file.fileStem}.jpg')
              .existsSync(),
          isTrue,
        );

        link.value = null;
        final again = await images()
            .load(serial, file, GrImageSize.thumb)
            .future;
        expect(again, bytes);
        expect(requests, 1);
      },
    );

    test('offline without a cached copy gives nothing', () async {
      final bytes = await images().load(serial, file, GrImageSize.view).future;
      expect(bytes, isNull);
      expect(requests, 0);
    });

    test('a request the camera never answers times out and frees its queue '
        'slot; the next load fetches the image', () async {
      link.value = connected();
      stallThumbs = 1;
      final loader = CameraImages(
        cacheDir: cache,
        link: link,
        queue: queue,
        timeouts: const {
          GrImageSize.thumb: Duration(milliseconds: 200),
          GrImageSize.xs: Duration(milliseconds: 200),
          GrImageSize.view: Duration(milliseconds: 200),
          GrImageSize.full: Duration(milliseconds: 200),
        },
      );
      final watch = Stopwatch()..start();
      await expectLater(
        loader.load(serial, file, GrImageSize.thumb).future,
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(queue.running, 0);
      final bytes = await loader.load(serial, file, GrImageSize.thumb).future;
      expect(bytes, isNotNull);
      expect(requests, 2);
    });

    test('a load cancelled while it waits for the queue does not fail the '
        'next load of the same image', () async {
      link.value = connected();
      final busy = RequestQueue(concurrency: 1);
      final gate = Completer<void>();
      busy.add(() => gate.future);
      final loader = CameraImages(cacheDir: cache, link: link, queue: busy);
      final first = loader.load(serial, file, GrImageSize.thumb);
      // Starts waiting on the queue in a later microtask.
      await Future<void>.delayed(Duration.zero);
      first.cancel();
      final second = loader.load(serial, file, GrImageSize.thumb);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expect(await first.future, isNull);
      expect(await second.future, isNotNull);
    });

    test('bytes that are not a JPEG fail the load and are not kept; a broken '
        'copy on disk is fetched again', () async {
      link.value = connected();
      junkThumbs = 1;
      final loader = images();
      await expectLater(
        loader.load(serial, file, GrImageSize.thumb).future,
        throwsA(isA<NotAnImageException>()),
      );
      final onDisk = CameraImages.diskFile(
        cache,
        serial,
        file,
        GrImageSize.thumb,
      );
      expect(onDisk.existsSync(), isFalse);

      await onDisk.parent.create(recursive: true);
      await onDisk.writeAsString('<html>busy</html>');
      final bytes = await images().load(serial, file, GrImageSize.thumb).future;
      expect(bytes, isNotNull);
      expect(isJpeg(bytes!), isTrue);
      expect(isJpeg(await onDisk.readAsBytes()), isTrue);
    });
  });

  group('MovieCache', () {
    final movie = CameraFile(
      GrStorageId.sd,
      GrPhotoPath('100RICOH', 'R0000002.MOV'),
    );

    test('copies a movie once with progress, then reuses the copy', () async {
      final movies = MovieCache(cacheDir: cache);
      expect(movies.cached(serial, movie), isNull);
      final download = movies.download(connected(), movie);
      final seen = <double?>[];
      download.progress.addListener(() => seen.add(download.progress.value));
      final file = await download.done;
      expect(file.path, endsWith('/$serial/movies/sd1_100RICOH_R0000002.MOV'));
      final expected = await camera.media(
        camera.photos.firstWhere((p) => p.file == 'R0000002.MOV'),
        GrImageSize.full,
      );
      expect(await file.readAsBytes(), expected);
      expect(seen.last, 1);
      expect(movies.cached(serial, movie)?.path, file.path);
    });

    test('cancelling leaves nothing cached', () async {
      await camera.close();
      camera = FakeGrCamera(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 64 * 1024,
        ),
        media: syntheticMedia(movieBytes: 256 * 1024),
      );
      await camera.startHttp();
      http.close(force: true);
      http = camera.httpClient('127.0.0.1', null);
      final movies = MovieCache(cacheDir: cache);
      final download = movies.download(connected(), movie);
      await until(
        () => (download.progress.value ?? 0) > 0,
        reason: 'copy started',
      );
      download.cancel();
      await expectLater(download.done, throwsA(isA<MovieDownloadCancelled>()));
      expect(movies.cached(serial, movie), isNull);
      expect(
        movies.fileFor(serial, movie).parent.listSync(),
        isEmpty,
        reason: 'no partial file left behind',
      );
    });
  });

  test(
    'MovieCache: cancel then immediate retry gives an intact copy',
    () async {
      await camera.close();
      camera = FakeGrCamera(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 256 * 1024,
        ),
        media: syntheticMedia(movieBytes: 192 * 1024),
      );
      await camera.startHttp();
      http.close(force: true);
      http = camera.httpClient('127.0.0.1', null);
      final movie = CameraFile(
        GrStorageId.sd,
        GrPhotoPath('100RICOH', 'R0000002.MOV'),
      );
      final movies = MovieCache(cacheDir: cache);
      final first = movies.download(connected(), movie);
      await until(
        () => (first.progress.value ?? 0) > 0,
        reason: 'first copy started',
      );
      first.cancel();
      final retry = movies.download(connected(), movie);
      await expectLater(first.done, throwsA(isA<MovieDownloadCancelled>()));
      final file = await retry.done;
      final expected = await camera.media(
        camera.photos.firstWhere((p) => p.file == 'R0000002.MOV'),
        GrImageSize.full,
      );
      expect(await file.readAsBytes(), expected);
      expect(file.parent.listSync().map((e) => e.uri.pathSegments.last), [
        file.uri.pathSegments.last,
      ], reason: 'no staging files left behind');
    },
  );
}
