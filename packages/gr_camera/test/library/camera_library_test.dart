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
        GrBackoffReconnect,
        GrChangesSocket,
        GrHttpClient,
        GrHttpStatusException,
        GrMalformedResponseException,
        GrSocketState;

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
  // Faults for the next thumbnail requests: no answer until the test ends
  // (or [hang] completes), or bytes that are not a JPEG.
  var stallThumbs = 0;
  var junkThumbs = 0;
  // The next full-size requests (movies included) wait for [hang] too.
  var stallFull = 0;
  var hang = Completer<void>();

  CameraLibrary connected({
    GrChangesSocket? changes,
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
    stallFull = 0;
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
        if (size == GrImageSize.full && stallFull > 0) {
          stallFull--;
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
      final listing = await connected().listFiles(reason: 'connected');
      expect(listing.files.map((f) => '$f'), [
        'in:100RICOH/R0000001.JPG',
        'sd1:100RICOH/R0000001.JPG',
        'sd1:100RICOH/R0000001.DNG',
        'sd1:100RICOH/R0000002.MOV',
      ]);
      expect(listing.failed, isEmpty);
      expect(events('library.list'), [
        {
          'reason': 'connected',
          'storages': [GrStorageId.internal, GrStorageId.sd],
        },
      ]);
      expect(events('library.listed'), [
        {'reason': 'connected', 'files': 4, 'failed': <String?>[]},
      ]);
    });

    test('a storage that answers with an error is left out and named while '
        'another lists; alone, its error is thrown', () async {
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
      final listing = await connected().listFiles();
      expect(listing.files, [
        CameraFile(
          GrStorageId.internal,
          GrPhotoPath('100RICOH', 'R0000001.JPG'),
        ),
      ]);
      expect(listing.failed, {GrStorageId.sd});
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

    test('listingChanges carries storage changes from /v1/changes only, '
        'until the socket closes', () async {
      await expectLater(connected().listingChanges, emitsDone);
      final socket = http.changesSocket();
      await socket.connect();
      addTearDown(socket.close);
      var changes = 0;
      var done = false;
      final sub = connected(changes: socket).listingChanges
          .listen((_) => changes++, onDone: () => done = true);
      addTearDown(sub.cancel);
      camera
        ..battery = 50
        ..addPhoto(FakePhoto('101RICOH', 'R0000003.JPG', _day2));
      await until(() => changes > 0, reason: 'storage change');
      expect(changes, 1);
      await socket.close();
      await until(() => done, reason: 'done with the socket');
    });

    test('listingChanges emits when the socket opens again, as the camera '
        'does not send again what changed while it was closed', () async {
      final socket = http.changesSocket(
        reconnect: const GrBackoffReconnect(
          delays: [Duration(milliseconds: 20)],
        ),
      );
      await socket.connect();
      addTearDown(socket.close);
      var changes = 0;
      final sub = connected(changes: socket).listingChanges
          .listen((_) => changes++);
      addTearDown(sub.cancel);
      camera.dropChangeSockets();
      await until(
        () => socket.status.state != GrSocketState.open,
        reason: 'socket dropped',
      );
      expect(
        camera.removePhoto(GrPhotoPath('100RICOH', 'R0000001.DNG')),
        isTrue,
      );
      await until(() => changes > 0, reason: 'socket reopened');
      expect(changes, 1);
      expect(events('library.changesReopened'), hasLength(1));
    });

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
      final folder = Directory('${dir.path}/sd1_100RICOH');
      expect(folder.listSync().map((e) => e.uri.pathSegments.last), [
        'R0000001.JPG',
      ]);

      final seen = <(int, int)>[];
      final local = await library.downloadFiles(
        files,
        dir,
        onProgress: (bytes, index, received, total) => seen.add((index, bytes)),
      );
      expect(local.map((f) => f.path), [
        '${folder.path}/R0000001.JPG',
        '${folder.path}/R0000001.DNG',
      ]);
      expect(seen.map((s) => s.$1).toSet(), {1}, reason: 'JPG kept');
      final jpeg = await expected(files[0]);
      expect(seen.last.$2, jpeg.length + (await expected(files[1])).length);
      expect(await local[0].readAsBytes(), jpeg);
      expect(await local[1].readAsBytes(), await expected(files[1]));
      expect(events('download.kept').single['file'], '${files[0]}');
    });

    test('downloadFiles copies same-named files from different storages '
        'and folders to their own copies', () async {
      await restartCamera(
        FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: [...card(), FakePhoto('101RICOH', 'R0000001.JPG', _day2)],
        ),
        syntheticMedia(jpegBytes: 4096),
      );
      final files = [
        CameraFile(
          GrStorageId.internal,
          GrPhotoPath('100RICOH', 'R0000001.JPG'),
        ),
        CameraFile(GrStorageId.sd, GrPhotoPath('100RICOH', 'R0000001.JPG')),
        CameraFile(GrStorageId.sd, GrPhotoPath('101RICOH', 'R0000001.JPG')),
      ];
      final dir = Directory('${cache.path}/job');
      final local = await connected().downloadFiles(
        files,
        dir,
        onProgress: (_, _, _, _) {},
      );
      expect(local.map((f) => f.path).toSet(), hasLength(3));
      expect(local.map((f) => f.uri.pathSegments.last).toSet(), {
        'R0000001.JPG',
      }, reason: 'each copy keeps its camera name');
      final contents = [
        for (final f in files)
          await camera.media(
            camera.photos.firstWhere(
              (p) => p.storage == f.storage && p.path == f.path,
            ),
            GrImageSize.full,
          ),
      ];
      expect(contents.map(String.fromCharCodes).toSet(), hasLength(3));
      for (var i = 0; i < files.length; i++) {
        expect(
          await local[i].readAsBytes(),
          contents[i],
          reason: '${files[i]}',
        );
      }
      expect(events('download.kept'), isEmpty);
    });

    test('downloadFiles closes a stalled copy at once when aborted and '
        'keeps nothing of it', () async {
      final body = Uint8List.fromList(List.filled(4096, 7));
      final stalling = await _StallingCamera.start(body);
      addTearDown(stalling.close);
      final stalledHttp = GrHttpClient('127.0.0.1', port: stalling.port);
      addTearDown(() => stalledHttp.close(force: true));
      final dir = Directory('${cache.path}/job');
      final abort = Completer<Object>();
      final started = Completer<void>();
      final copy = CameraLibrary.overHttp(stalledHttp, serial: serial)
          .downloadFiles(
            [
              CameraFile(
                GrStorageId.sd,
                GrPhotoPath('100RICOH', 'R0000001.JPG'),
              ),
            ],
            dir,
            onProgress: (_, _, received, _) {
              if (received > 0 && !started.isCompleted) started.complete();
            },
            abort: abort.future,
          );
      await started.future;
      abort.complete(const _Stopped());
      const guard = Duration(seconds: 5);
      await expectLater(copy.timeout(guard), throwsA(isA<_Stopped>()));
      await stalling.closed.single.future.timeout(guard);
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
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
        TransferFailure.of(refused),
        isA<TransferRefused>()
            .having((f) => f.errCode, 'errCode', 404)
            .having((f) => f.errMsg, 'errMsg', 'Not Found'),
      );
      expect(
        TransferFailure.of(
          const GrHttpStatusException(route: route, httpStatus: 503),
        ),
        isA<TransferHttpStatus>().having((f) => f.httpStatus, 'status', 503),
      );
      expect(TransferFailure.of(cut), isA<TransferCutOff>());
      expect(
        TransferFailure.of(const SocketException('reset')),
        isA<TransferConnectionLost>(),
      );
      expect(
        TransferFailure.of(const HttpException('closed')),
        isA<TransferConnectionLost>(),
      );
      expect(
        TransferFailure.of(TimeoutException('quiet')),
        isA<TransferStalled>(),
      );
      expect(
        TransferFailure.of(
          const FileSystemException('write failed', null, OSError('No space')),
        ),
        isA<TransferWriteFailed>(),
      );
      expect(TransferFailure.of(StateError('odd')), isA<TransferOtherError>());
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

    test('a request past its deadline is closed before its queue slot runs '
        'the next one', () async {
      final thumb = await syntheticMedia()(card().first, GrImageSize.thumb);
      final stalling = await _StallingCamera.start(thumb);
      addTearDown(stalling.close);
      final stalledHttp = GrHttpClient('127.0.0.1', port: stalling.port);
      addTearDown(() => stalledHttp.close(force: true));
      link.value = CameraLibrary.overHttp(stalledHttp, serial: serial);
      const deadline = Duration(milliseconds: 200);
      final loader = CameraImages(
        cacheDir: cache,
        link: link,
        queue: RequestQueue(concurrency: 1),
        timeouts: const {
          GrImageSize.thumb: deadline,
          GrImageSize.xs: deadline,
          GrImageSize.view: deadline,
          GrImageSize.full: deadline,
        },
      );
      await expectLater(
        loader.load(serial, file, GrImageSize.thumb).future,
        throwsA(isA<TimeoutException>()),
      );
      final other = CameraFile(
        GrStorageId.sd,
        GrPhotoPath('100RICOH', 'R0000001.DNG'),
      );
      expect(await loader.load(serial, other, GrImageSize.thumb).future, thumb);
      expect(stalling.earlierClosed, [
        true,
        true,
      ], reason: 'the stalled request was closed before the next one began');
    });

    test('keeps the images on disk within their budget, sparing those in '
        'memory, and fetches an evicted one again', () async {
      link.value = connected();
      final thumb = await syntheticMedia()(card().first, GrImageSize.thumb);
      final a = file;
      final b = CameraFile(
        GrStorageId.sd,
        GrPhotoPath('100RICOH', 'R0000001.DNG'),
      );
      final c = CameraFile(
        GrStorageId.internal,
        GrPhotoPath('100RICOH', 'R0000001.JPG'),
      );
      File onDisk(CameraFile f) =>
          CameraImages.diskFile(cache, serial, f, GrImageSize.thumb);
      List<bool> kept(List<CameraFile> files) => [
        for (final f in files) onDisk(f).existsSync(),
      ];

      // Room in memory for two thumbnails, on disk for one.
      final loader = CameraImages(
        cacheDir: cache,
        link: link,
        queue: queue,
        memoryThumbs: 2,
        diskBytes: thumb.length,
      );
      for (final f in [a, b]) {
        await loader.load(serial, f, GrImageSize.thumb).future;
      }
      await loader.diskSettled;
      expect(kept([a, b]), [true, true], reason: 'both are in memory');
      await loader.load(serial, c, GrImageSize.thumb).future;
      await loader.diskSettled;
      expect(kept([a, b, c]), [false, true, true], reason: 'a left memory');

      // At start, the least recently used go first, with staging files
      // left over by a stopped app; a fresh one belongs to a write.
      onDisk(b).setLastModifiedSync(DateTime(2001));
      final leftover = File('${onDisk(c).path}.1.tmp')
        ..writeAsBytesSync(thumb)
        ..setLastModifiedSync(DateTime(2000));
      final writing = File('${onDisk(c).path}.2.tmp')..writeAsBytesSync(thumb);
      final next = CameraImages(
        cacheDir: cache,
        link: link,
        queue: queue,
        diskBytes: thumb.length,
      );
      await next.diskSettled;
      expect(kept([b, c]), [false, true]);
      expect(leftover.existsSync(), isFalse);
      expect(writing.existsSync(), isTrue);

      final asked = requests;
      expect(await next.load(serial, a, GrImageSize.thumb).future, thumb);
      expect(requests, asked + 1, reason: 'fetched again');
      await next.diskSettled;
      expect(kept([a, c]), [true, false]);
    });

    test('forgetting a camera deletes its folder and its images in memory, '
        'keeps an image fetched meanwhile off disk, and leaves other '
        "cameras' images and the camera's cache once paired again", () async {
      link.value = connected();
      final loader = images();
      final thumb = await loader.load(serial, file, GrImageSize.thumb).future;
      final listing = File('${cache.path}/$serial/library.json')
        ..writeAsStringSync('{}');
      final other = CameraImages.diskFile(
        cache,
        '1111111',
        file,
        GrImageSize.thumb,
      );
      await other.parent.create(recursive: true);
      await other.writeAsBytes(thumb!);
      final raw = CameraFile(
        GrStorageId.sd,
        GrPhotoPath('100RICOH', 'R0000001.DNG'),
      );
      stallThumbs = 1;
      final inFlight = loader.load(serial, raw, GrImageSize.thumb);
      await until(() => requests == 2, reason: 'second thumbnail asked');

      await loader.forgetCamera(serial);
      expect(Directory('${cache.path}/$serial').existsSync(), isFalse);
      expect(listing.existsSync(), isFalse);
      expect(loader.cached(serial, file, GrImageSize.thumb), isNull);
      // Paired again: its listing is cached anew.
      listing
        ..parent.createSync()
        ..writeAsStringSync('{}');
      hang.complete();
      expect(await inFlight.future, isNotNull, reason: 'still shown');
      await loader.diskSettled;
      expect(Directory('${cache.path}/$serial/thumbs').existsSync(), isFalse);
      expect(listing.existsSync(), isTrue);
      expect(loader.cached(serial, raw, GrImageSize.thumb), isNull);
      expect(other.existsSync(), isTrue);
    });

    test('an image the camera sends after its file was forgotten reaches '
        'the caller but is kept neither on disk nor in memory', () async {
      final library = connected();
      link.value = library;
      final loader = images();
      stallThumbs = 1;
      final inFlight = loader.load(serial, file, GrImageSize.thumb);
      await until(() => requests == 1, reason: 'thumbnail asked');

      // Deleted on the camera while the camera was answering.
      loader.forget(serial, file);
      hang.complete();
      expect(await inFlight.future, isNotNull, reason: 'the caller asked');
      await loader.diskSettled;
      final onDisk = CameraImages.diskFile(
        cache,
        serial,
        file,
        GrImageSize.thumb,
      );
      expect(onDisk.existsSync(), isFalse);
      expect(
        onDisk.parent.existsSync()
            ? onDisk.parent.listSync()
            : const <FileSystemEntity>[],
        isEmpty,
        reason: 'no staging file left behind',
      );
      expect(loader.cached(serial, file, GrImageSize.thumb), isNull);
      expect(loader.isLocal(serial, file, GrImageSize.thumb), isFalse);
      expect(
        loader.forgetUnlessFrom(library, file),
        isFalse,
        reason: 'nothing kept that the same link could vouch for',
      );
      expect(events('images.forgottenMeanwhile'), hasLength(1));

      final asked = requests;
      await loader.load(serial, file, GrImageSize.thumb).future;
      expect(requests, asked + 1, reason: 'the next load asks the camera');
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

    test('a copy running while its camera is forgotten is not kept, and '
        "leaves the camera's cache once paired again", () async {
      await camera.close();
      camera = FakeGrCamera(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 64 * 1024,
        ),
        media: syntheticMedia(movieBytes: 128 * 1024),
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

      await movies.forgetCamera(serial);
      expect(Directory('${cache.path}/$serial').existsSync(), isFalse);
      // Paired again: a listing and another movie are cached anew.
      final listing = File('${cache.path}/$serial/library.json');
      final otherMovie = File('${cache.path}/$serial/movies/other.MOV');
      otherMovie.parent.createSync(recursive: true);
      listing.writeAsStringSync('{}');
      otherMovie.writeAsBytesSync([1, 2, 3]);

      await expectLater(download.done, throwsA(isA<MovieDownloadCancelled>()));
      // Lets anything the copy left to do once settled run.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await movies.diskSettled;
      expect(movies.fileFor(serial, movie).existsSync(), isFalse);
      expect(
        Directory('${cache.path}/$serial/movies').listSync().map((e) => e.path),
        [otherMovie.path],
        reason: 'nothing of the forgotten copy',
      );
      expect(listing.existsSync(), isTrue);
    });

    test('a copy running while its movie is forgotten ends as cancelled and '
        'leaves nothing on disk', () async {
      final movies = MovieCache(cacheDir: cache);
      final library = connected();
      stallFull = 1;
      final download = movies.download(library, movie);
      await until(() => requests == 1, reason: 'movie asked');

      // Deleted on the camera while the camera was sending it.
      movies.forget(serial, movie);
      hang.complete();
      await expectLater(download.done, throwsA(isA<MovieDownloadCancelled>()));
      await movies.diskSettled;
      expect(movies.cached(serial, movie), isNull);
      expect(movies.forgetUnlessFrom(library, movie), isFalse);
      expect(
        movies.fileFor(serial, movie).parent.listSync(),
        isEmpty,
        reason: 'neither the copy nor its staging file left behind',
      );
      expect(events('movies.forgottenMeanwhile'), hasLength(1));

      final again = await movies.download(library, movie).done;
      expect(again.existsSync(), isTrue, reason: 'a later copy is kept');
    });

    test('cancelling a stalled copy closes its connection at once', () async {
      final body = await camera.media(
        camera.photos.firstWhere((p) => p.file == 'R0000002.MOV'),
        GrImageSize.full,
      );
      final stalling = await _StallingCamera.start(body);
      addTearDown(stalling.close);
      final stalledHttp = GrHttpClient('127.0.0.1', port: stalling.port);
      addTearDown(() => stalledHttp.close(force: true));
      final movies = MovieCache(cacheDir: cache);
      final download = movies.download(
        CameraLibrary.overHttp(stalledHttp, serial: serial),
        movie,
      );
      final started = Completer<void>();
      download.progress.addListener(() {
        if ((download.progress.value ?? 0) > 0 && !started.isCompleted) {
          started.complete();
        }
      });
      await started.future;
      download.cancel();
      const guard = Duration(seconds: 5);
      await expectLater(
        download.done.timeout(guard),
        throwsA(isA<MovieDownloadCancelled>()),
      );
      await stalling.closed.single.future.timeout(guard);
      expect(movies.fileFor(serial, movie).parent.listSync(), isEmpty);
    });

    group('budget', () {
      FakePhoto movieAt(String name) => FakePhoto(
        '100RICOH',
        name,
        _day2,
        videoLength: const Duration(seconds: 3),
      );
      final all = [
        for (final name in [
          'R0000002.MOV',
          'R0000003.MOV',
          'R0000004.MOV',
          'R0000005.MOV',
        ])
          CameraFile(GrStorageId.sd, GrPhotoPath('100RICOH', name)),
      ];
      Future<List<int>> expected(CameraFile f) => camera.media(
        camera.photos.firstWhere(
          (p) => p.storage == f.storage && p.path == f.path,
        ),
        GrImageSize.full,
      );
      List<bool> kept(MovieCache movies, [List<CameraFile>? files]) => [
        for (final f in files ?? all) movies.fileFor(serial, f).existsSync(),
      ];

      setUp(
        () => restartCamera(
          FakeCameraConfig(
            httpLatency: Duration.zero,
            photos: [...card(), for (final f in all.skip(1)) movieAt(f.name)],
          ),
          syntheticMedia(movieBytes: 16 * 1024),
        ),
      );

      test('keeps copies within their budget, sparing held copies and '
          'copies in progress', () async {
        final three = all.take(3).toList();
        final movies = MovieCache(cacheDir: cache, maxBytes: 1);
        final library = connected();
        // One plays, one is on the page next to it.
        final holds = [
          movies.hold(serial, three[1]),
          movies.hold(serial, three[2]),
        ];
        for (final f in three) {
          await movies.download(library, f).done;
        }
        await movies.diskSettled;
        expect(kept(movies, three), [false, true, true]);

        // At start, only the most recently played copy fits; a staging file
        // being written stays, one left over by a stopped app goes.
        for (final hold in holds) {
          hold.release();
        }
        await movies.diskSettled;
        expect(kept(movies, three), [false, false, false]);
        final roomy = MovieCache(cacheDir: cache);
        for (final f in three.skip(1)) {
          await roomy.download(library, f).done;
        }
        final last = movies.fileFor(serial, three[2]);
        movies.fileFor(serial, three[1]).setLastModifiedSync(DateTime(2001));
        final leftover = File('${last.path}.0.download.part')
          ..writeAsBytesSync([1, 2, 3])
          ..setLastModifiedSync(DateTime(2000));
        final writing = File('${last.path}.1.download.part')
          ..writeAsBytesSync([1, 2, 3]);
        final next = MovieCache(cacheDir: cache, maxBytes: last.lengthSync());
        await next.diskSettled;
        expect(kept(next, three), [false, false, true]);
        expect(leftover.existsSync(), isFalse);
        expect(writing.existsSync(), isTrue);
        writing.deleteSync();

        expect(next.cached(serial, three[0]), isNull);
        // The last copy plays while the first is copied again.
        final playing = next.hold(serial, three[2]);
        final shown = next.hold(serial, three[0]);
        expect(next.cached(serial, three[2]), isNotNull);
        final again = await next.download(library, three[0]).done;
        expect(await again.readAsBytes(), await expected(three[0]));
        await next.diskSettled;
        expect(kept(next, three), [true, false, true], reason: 'both held');
        playing.release();
        shown.release();
      });

      test('a movie held while it plays stays however many movies are '
          'played after it, until released', () async {
        final movies = MovieCache(cacheDir: cache, maxBytes: 1);
        final library = connected();
        final playing = movies.hold(serial, all[0]);
        await movies.download(library, all[0]).done;
        // The player reads the file and asks the cache nothing more, while
        // the user pages through the other movies.
        for (final f in all.skip(1)) {
          final shown = movies.hold(serial, f);
          await movies.download(library, f).done;
          shown.release();
        }
        await movies.diskSettled;
        expect(kept(movies), [true, false, false, false]);

        // A cache opened again over the same folder spares it too.
        final reopened = MovieCache(cacheDir: cache, maxBytes: 1);
        await reopened.diskSettled;
        expect(kept(reopened), [true, false, false, false]);

        playing
          ..release()
          // A second release changes nothing.
          ..release();
        await movies.diskSettled;
        expect(kept(movies), [false, false, false, false]);
      });
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

/// A camera whose first answer stops a few bytes into [body] and keeps its
/// connection open; every later request gets [body] in full.
final class _StallingCamera {
  new _(this._server, this.body) {
    _server.listen((socket) {
      _sockets.add(socket);
      final closed = Completer<void>();
      final index = this.closed.length;
      this.closed.add(closed);
      void done() {
        if (!closed.isCompleted) closed.complete();
        socket.destroy();
      }

      var answered = false;
      socket.listen(
        (data) {
          if (answered || !latin1.decode(data).contains('\r\n\r\n')) return;
          answered = true;
          earlierClosed.add(
            this.closed.take(index).every((c) => c.isCompleted),
          );
          socket
            ..add(
              latin1.encode(
                'HTTP/1.1 200 OK\r\n'
                'Content-Length: ${body.length}\r\n'
                'Connection: close\r\n\r\n',
              ),
            )
            ..add(index == 0 ? body.sublist(0, 4) : body);
        },
        onDone: done,
        onError: (Object _) => done(),
      );
    });
  }

  static Future<_StallingCamera> start(Uint8List body) async =>
      _StallingCamera._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        body,
      );

  final ServerSocket _server;
  final Uint8List body;
  final _sockets = <Socket>[];

  /// Per connection, completes when the client has closed it.
  final closed = <Completer<void>>[];

  /// Per request, whether every earlier connection was already closed
  /// when it arrived.
  final earlierClosed = <bool>[];

  int get port => _server.port;

  Future<void> close() async {
    await _server.close();
    for (final s in _sockets) {
      s.destroy();
    }
  }
}

final class _Stopped implements Exception {
  const new();
}
