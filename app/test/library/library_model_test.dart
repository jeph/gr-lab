import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/library/camera_images.dart';
import 'package:grlab/src/library/camera_link.dart';
import 'package:grlab/src/library/library_model.dart';
import 'package:grlab/src/library/movie_cache.dart';
import 'package:grlab/src/library/request_queue.dart';
import 'package:grlab/src/library/shot.dart';

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
  late ValueNotifier<CameraLink?> link;
  late RequestQueue queue;
  final models = <LibraryModel>[];
  var requests = 0;
  // Faults for the next thumbnail requests: no answer until the test ends,
  // or bytes that are not a JPEG.
  var stallThumbs = 0;
  var junkThumbs = 0;
  var hang = Completer<void>();

  CameraLink connected({Stream<GrChangeEvent>? changes}) => CameraLink(
    serial: serial,
    http: http,
    storages: const [GrStorageId.internal, GrStorageId.sd],
    changes: changes,
  );

  LibraryModel model() {
    final m = LibraryModel(
      cacheDir: cache,
      link: link,
      queue: queue,
      changeDebounce: const Duration(milliseconds: 10),
      saveDelay: Duration.zero,
    );
    models.add(m);
    return m;
  }

  setUp(() async {
    HttpOverrides.global = null;
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
        return media(photo, size);
      },
    );
    await camera.startHttp();
    http = camera.httpClient('127.0.0.1', null);
    cache = await Directory.systemTemp.createTemp('grlab_lib_');
    link = ValueNotifier(null);
    queue = RequestQueue();
  });

  tearDown(() async {
    if (!hang.isCompleted) hang.complete();
    for (final m in models) {
      // A refresh started by the last link change saves when it ends; the
      // cache directory cannot go while it writes.
      await until(() => !m.refreshing, reason: 'refresh to end');
      await m.flush();
      m.dispose();
    }
    models.clear();
    link.dispose();
    http.close(force: true);
    await camera.close();
    await cache.delete(recursive: true);
  });

  test('lists both storages when the camera connects', () async {
    final m = model();
    await m.setCamera(serial);
    expect(m.shots, isNull);
    link.value = connected();
    await until(() => m.shots != null && !m.refreshing, reason: 'listing');
    expect(m.connected, isTrue);
    expect(m.shots!.map((s) => (s.storage, s.base, s.format)), [
      (GrStorageId.sd, 'R0000002', ShotFormat.video),
      (GrStorageId.internal, 'R0000001', ShotFormat.jpeg),
      (GrStorageId.sd, 'R0000001', ShotFormat.rawJpeg),
    ]);
    expect(m.listedAt, isNotNull);
    expect(m.error, isNull);
  });

  test('a failed refresh asks whether the Wi-Fi still works and shows the '
      'error only while the camera answers', () async {
    var checks = 0;
    var answers = false;
    final m = model();
    await m.setCamera(serial);
    link.value = CameraLink(
      serial: serial,
      http: http,
      checkWifi: () async {
        checks++;
        return answers;
      },
    );
    await until(() => m.shots != null && !m.refreshing, reason: 'listing');
    expect(checks, 0);

    // The camera's HTTP server stops answering.
    http.close(force: true);
    await m.refresh();
    expect(checks, 1);
    expect(m.error, isNull, reason: 'the app leaves the Library instead');

    answers = true;
    await m.refresh();
    expect(checks, 2);
    expect(m.error, isNotNull);
  });

  test('keeps the listing per camera for offline use', () async {
    final first = model();
    await first.setCamera(serial);
    link.value = connected();
    await until(() => first.shots != null && !first.refreshing);
    final movie = first.shots!.firstWhere((s) => s.isVideo);
    final info = await first.ensureInfo(movie.primary);
    expect(info?.duration, const Duration(seconds: 14));
    expect(info?.taken, _day2);
    expect(info?.size, greaterThan(0));
    await first.flush();

    link.value = null;
    final offline = model();
    await offline.setCamera(serial);
    expect(offline.connected, isFalse);
    expect(offline.shots, first.shots);
    expect(offline.info(movie.primary)?.duration, const Duration(seconds: 14));
    expect(offline.listedAt, isNotNull);

    await offline.setCamera('another');
    expect(offline.shots, isNull);
  });

  test('keeps the orientation /info reports; info cached before it was '
      'kept is fetched again', () async {
    final first = model();
    await first.setCamera(serial);
    link.value = connected();
    await until(() => first.shots != null && !first.refreshing);
    final held = first.shots!.firstWhere((s) => s.isPair).primary;
    final movie = first.shots!.firstWhere((s) => s.isVideo).primary;
    expect((await first.ensureInfo(held))?.orientation, 6);
    expect((await first.ensureInfo(movie))?.orientation, 1);
    await first.flush();

    link.value = null;
    final offline = model();
    await offline.setCamera(serial);
    expect(offline.info(held)?.orientation, 6);
    expect(offline.info(movie)?.orientation, 1);
    await offline.setCamera(null);

    // A version 1 cache: same listing, info without orientation.
    final file = File('${cache.path}/$serial/library.json');
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final info = json['info']! as Map<String, Object?>;
    for (final v in info.values) {
      (v! as Map<String, Object?>).remove('o');
    }
    await file.writeAsString(jsonEncode({...json, 'version': 1}));
    final old = model();
    await old.setCamera(serial);
    expect(old.shots, first.shots);
    expect(old.info(held), isNull);
    link.value = connected();
    expect((await old.ensureInfo(held))?.orientation, 6);
  });

  test('refreshes on a storage change from /v1/changes', () async {
    final socket = http.changesSocket();
    await socket.connect();
    addTearDown(socket.close);
    final m = model();
    await m.setCamera(serial);
    link.value = connected(changes: socket.events);
    await until(() => m.shots != null && !m.refreshing);
    expect(m.shots, hasLength(3));

    camera.addPhoto(FakePhoto('101RICOH', 'R0000003.JPG', _day2));
    await until(
      () => m.shots!.any((s) => s.base == 'R0000003'),
      reason: 'refresh after storage event',
    );
    expect(m.shots!.first.dir, '101RICOH');
  });

  test('switching cameras while a listing is pending does not block later '
      'refreshes', () async {
    link.value = connected();
    final m = model();
    await m.setCamera(serial);
    expect(m.refreshing, isTrue, reason: 'listing still in flight');

    await m.setCamera('another');
    expect(m.refreshing, isFalse);
    expect(m.shots, isNull);

    await m.setCamera(serial);
    await until(
      () => m.shots != null && !m.refreshing,
      reason: 'listing after switching back',
    );
    expect(m.shots, hasLength(3));

    // The superseded listing must not leave the model refusing refreshes.
    camera.addPhoto(FakePhoto('101RICOH', 'R0000003.JPG', _day2));
    await m.refresh();
    expect(m.shots!.first.base, 'R0000003');
  });

  test('ignores a link to another camera', () async {
    final m = model();
    await m.setCamera('another');
    link.value = connected();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(m.shots, isNull);
    expect(m.connected, isFalse);
    expect(
      await m.ensureInfo(CameraFile(null, GrPhotoPath.parse('a/b.JPG'))),
      isNull,
    );
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

  group('RequestQueue', () {
    test('runs at most its concurrency, newest first', () async {
      final q = RequestQueue();
      var running = 0;
      var peak = 0;
      final order = <int>[];
      final gate = Completer<void>();
      Future<int> task(int i) async {
        running++;
        peak = running > peak ? running : peak;
        order.add(i);
        await gate.future;
        running--;
        return i;
      }

      final requests = [for (var i = 0; i < 6; i++) q.add(() => task(i))];
      await Future<void>.delayed(Duration.zero);
      expect(q.running, 3);
      expect(order, [0, 1, 2]);
      gate.complete();
      expect(await Future.wait([for (final r in requests) r.future]), [
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(peak, 3);
      expect(order.sublist(3), [5, 4, 3]);
    });

    test('a request cancelled before it starts never runs', () async {
      final q = RequestQueue(concurrency: 1);
      final gate = Completer<void>();
      var ran = false;
      final first = q.add(() => gate.future);
      final second = q.add(() async => ran = true);
      second.cancel();
      gate.complete();
      await first.future;
      await expectLater(second.future, throwsA(isA<RequestCancelled>()));
      expect(ran, isFalse);
    });

    test('background requests wait for every foreground one; a promoted one '
        'runs with them', () async {
      final q = RequestQueue(concurrency: 1);
      final gate = Completer<void>();
      final order = <String>[];
      Future<void> task(String name) async => order.add(name);
      final first = q.add(() => gate.future);
      q.add(() => task('sharper A'), background: true);
      final b = q.add(() => task('sharper B'), background: true);
      q.add(() => task('thumb 1'));
      q.add(() => task('thumb 2'));
      b.promote();
      gate.complete();
      await first.future;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(order, ['sharper B', 'thumb 2', 'thumb 1', 'sharper A']);
    });
  });

  group('SharedRequests', () {
    test('callers share one run; it leaves the queue when all cancel before '
        'it starts', () async {
      final q = RequestQueue(concurrency: 1);
      final shared = SharedRequests<int>(q);
      final gate = Completer<void>();
      final blocker = q.add(() => gate.future);
      var runs = 0;
      Future<int> task(RequestSignal _) async => ++runs;
      const timeout = Duration(seconds: 5);
      final owner = Object();
      final a = shared.join('k', owner, task, timeout: timeout);
      final b = shared.join('k', owner, task, timeout: timeout);
      a.cancel();
      b.cancel();
      expect(q.pending, 0);
      final c = shared.join('k', owner, task, timeout: timeout);
      final d = shared.join('k', owner, task, timeout: timeout);
      gate.complete();
      await blocker.future;
      expect(await c.future, 1);
      expect(await d.future, 1);
      expect(runs, 1);
      await expectLater(a.future, throwsA(isA<RequestCancelled>()));
    });

    test('a request made on an earlier connection is not joined', () async {
      final shared = SharedRequests<int>(RequestQueue());
      final stuck = Completer<int>();
      const timeout = Duration(seconds: 5);
      final old = shared.join(
        'k',
        Object(),
        (_) => stuck.future,
        timeout: timeout,
      );
      final fresh = shared.join(
        'k',
        Object(),
        (_) async => 2,
        timeout: timeout,
      );
      expect(await fresh.future, 2);
      stuck.complete(1);
      expect(await old.future, 1);
    });
  });
}
