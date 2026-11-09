import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart' show GrHttpClient;
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/library_model.dart';
import 'package:grlab/src/library/library_scope.dart';
import 'package:grlab/src/library/shot.dart';

import '../support/test_app.dart' show RecordingMediaSaver;

const serial = '1234567';
final _day1 = DateTime(2026, 11, 4, 9, 30);
final _day2 = DateTime(2026, 11, 5, 18, 2, 7);
final _day3 = DateTime(2026, 11, 6, 7, 45, 12);

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

SavedCamera saved(String serial) => SavedCamera(
  paired: GrPairedCamera(
    deviceId: 'AA:BB:$serial',
    serialNumber: serial,
    modelName: 'RICOH GR IV',
  ),
  name: 'GR IV',
  pairedAt: DateTime(2026, 11, 7),
);

void main() {
  late FakeGrCamera camera;
  late GrHttpClient http;
  late Directory cache;

  /// Each model's paired cameras are kept in a directory of their own here.
  late Directory data;
  late ValueNotifier<CameraLibrary?> link;
  late RequestQueue queue;
  final models = <LibraryModel>[];

  CameraLibrary connected({Stream<GrChangeEvent>? changes}) =>
      CameraLibrary.overHttp(
        http,
        serial: serial,
        storages: const [GrStorageId.internal, GrStorageId.sd],
        changes: changes,
      );

  /// A model whose current camera is [current] (none for null), once it
  /// has read that camera's cached listing.
  Future<LibraryModel> model([
    String? current = serial,
    Duration infoTimeout = const Duration(seconds: 10),
    FileCopies? copies,
  ]) async {
    final cameras = await CameraStore.load(await data.createTemp());
    if (current != null) await cameras.add(saved(current));
    final m = LibraryModel(
      cacheDir: cache,
      cameras: cameras,
      link: link,
      queue: queue,
      copies: copies,
      changeDebounce: const Duration(milliseconds: 10),
      saveDelay: Duration.zero,
      infoTimeout: infoTimeout,
    );
    models.add(m);
    await m.switched;
    return m;
  }

  /// Makes [current] [m]'s current camera (none for null) and waits until
  /// the model has switched to it.
  Future<void> pick(LibraryModel m, String? current) async {
    final cameras = m.cameras;
    if (current == null) {
      for (final c in cameras.cameras) {
        await cameras.remove(c.serial);
      }
    } else {
      await cameras.add(saved(current));
    }
    await m.switched;
  }

  setUp(() async {
    HttpOverrides.global = null;
    camera = FakeGrCamera(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      media: syntheticMedia(jpegBytes: 4096, rawBytes: 8192),
    );
    await camera.startHttp();
    http = camera.httpClient('127.0.0.1', null);
    cache = await Directory.systemTemp.createTemp('grlab_lib_');
    data = await Directory.systemTemp.createTemp('grlab_lib_data_');
    link = ValueNotifier(null);
    queue = RequestQueue();
  });

  tearDown(() async {
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
    await data.delete(recursive: true);
  });

  test('lists both storages when the camera connects', () async {
    final m = await model();
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
    final m = await model();
    link.value = CameraLibrary.overHttp(
      http,
      serial: serial,
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
    final first = await model();
    link.value = connected();
    await until(() => first.shots != null && !first.refreshing);
    final movie = first.shots!.firstWhere((s) => s.isVideo);
    final info = await first.ensureInfo(movie.primary);
    expect(info?.duration, const Duration(seconds: 14));
    expect(info?.taken, _day2);
    expect(info?.size, greaterThan(0));
    await first.flush();

    link.value = null;
    final offline = await model();
    expect(offline.connected, isFalse);
    expect(offline.shots, first.shots);
    expect(offline.info(movie.primary)?.duration, const Duration(seconds: 14));
    expect(offline.listedAt, isNotNull);

    await pick(offline, 'another');
    expect(offline.shots, isNull);
  });

  test('keeps the orientation /info reports; info cached before it was '
      'kept is fetched again', () async {
    final first = await model();
    link.value = connected();
    await until(() => first.shots != null && !first.refreshing);
    final held = first.shots!.firstWhere((s) => s.isPair).primary;
    final movie = first.shots!.firstWhere((s) => s.isVideo).primary;
    expect((await first.ensureInfo(held))?.orientation, 6);
    expect((await first.ensureInfo(movie))?.orientation, 1);
    await first.flush();

    link.value = null;
    final offline = await model();
    expect(offline.info(held)?.orientation, 6);
    expect(offline.info(movie)?.orientation, 1);
    await pick(offline, null);

    // A version 1 cache: same listing, info without orientation.
    final file = File('${cache.path}/$serial/library.json');
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final info = json['info']! as Map<String, Object?>;
    for (final v in info.values) {
      (v! as Map<String, Object?>).remove('o');
    }
    await file.writeAsString(jsonEncode({...json, 'version': 1}));
    final old = await model();
    expect(old.shots, first.shots);
    expect(old.info(held), isNull);
    link.value = connected();
    expect((await old.ensureInfo(held))?.orientation, 6);
  });

  test('refreshes on a storage change from /v1/changes', () async {
    final socket = http.changesSocket();
    await socket.connect();
    addTearDown(socket.close);
    final m = await model();
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
    final m = await model();
    expect(m.refreshing, isTrue, reason: 'listing still in flight');

    await pick(m, 'another');
    expect(m.refreshing, isFalse);
    expect(m.shots, isNull);

    await pick(m, serial);
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
    final m = await model('another');
    link.value = connected();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(m.shots, isNull);
    expect(m.connected, isFalse);
    expect(
      await m.ensureInfo(CameraFile(null, GrPhotoPath.parse('a/b.JPG'))),
      isNull,
    );
  });

  test('ends on the camera picked last when the pick changes during a '
      'switch', () async {
    final m = await model();
    link.value = connected();
    await until(() => m.shots != null && !m.refreshing, reason: 'listing');

    // Another camera, and this one again before that switch saved the
    // listing.
    unawaited(m.cameras.add(saved('another')));
    await pick(m, serial);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(m.serial, serial);
    expect(m.connected, isTrue);
    expect(m.shots, hasLength(3));
  });

  test('an /info request past its deadline closes at once and frees its '
      'queue slot', () async {
    final stalling = await _InfoStallingCamera.start();
    addTearDown(stalling.close);
    final stalledHttp = GrHttpClient('127.0.0.1', port: stalling.port);
    addTearDown(() => stalledHttp.close(force: true));
    final m = await model(serial, const Duration(milliseconds: 100));
    link.value = CameraLibrary.overHttp(stalledHttp, serial: serial);
    final ticket = m.requestInfo(
      CameraFile(null, GrPhotoPath('100RICOH', 'R0000001.JPG')),
    )!;
    await expectLater(ticket.future, throwsA(isA<TimeoutException>()));
    // Without closing it, the request would hold its slot until the HTTP
    // client's own 15-second deadline.
    await stalling.closed.future.timeout(const Duration(seconds: 5));
    await until(() => queue.running == 0, reason: 'slot freed');
  });

  group('a path that comes back with another file', () {
    late DownloadEngine downloads;
    late CameraImages images;
    late MovieCache movies;

    setUp(() async {
      downloads = DownloadEngine(
        dataDir: await data.createTemp(),
        cacheDir: cache,
        media: RecordingMediaSaver(),
        link: link,
        transportGrace: Duration.zero,
      );
      images = CameraImages(cacheDir: cache, link: link, queue: queue);
      movies = MovieCache(cacheDir: cache);
    });

    tearDown(() async {
      await downloads.whenIdle();
      await downloads.flush();
      downloads.dispose();
      await images.diskSettled;
      await movies.diskSettled;
    });

    /// A model whose checks reach the caches, as in the app.
    Future<LibraryModel> checked() => model(
      serial,
      const Duration(seconds: 10),
      LibraryCopies(images: images, movies: movies, downloads: downloads),
    );

    Future<LibraryModel> listed() async {
      final m = await checked();
      link.value = connected();
      await until(() => m.shots != null && !m.refreshing, reason: 'listing');
      return m;
    }

    /// When the shot [f]'s cached thumbnail shows was taken.
    Future<String> thumbOf(CameraFile f) async => latin1.decode(
      (await images.load(serial, f, GrImageSize.thumb).future)!,
    );

    /// Puts another shot, taken at [taken], at [file]'s path.
    void replace(
      String file,
      DateTime taken, {
      String storage = GrStorageId.sd,
      Duration? videoLength,
    }) {
      expect(
        camera.removePhoto(GrPhotoPath('100RICOH', file), storage: storage),
        isTrue,
      );
      camera.addPhoto(
        FakePhoto(
          '100RICOH',
          file,
          taken,
          storage: storage,
          videoLength: videoLength,
        ),
      );
    }

    test('after a card swap offline, the thumbnail, movie and download mark '
        'follow the new files once connected again', () async {
      final m = await listed();
      final pair = m.shots!.firstWhere((s) => s.isPair);
      final jpeg = pair.jpeg!;
      final movie = m.shots!.firstWhere((s) => s.isVideo).primary;
      // As the grid and the viewer do.
      for (final f in [...pair.files, movie]) {
        await m.ensureInfo(f);
      }
      expect(await thumbOf(jpeg), contains(_day1.toIso8601String()));
      final oldMovie = await (await movies.download(link.value!, movie).done)
          .readAsBytes();
      await downloads.enqueue(serial, [pair]);
      await downloads.whenIdle();
      expect(downloads.areFilesDownloaded(serial, pair.files), isTrue);
      await m.flush();

      // Another card holds other shots under the JPEG's and the movie's
      // names; the DNG is the same file.
      link.value = null;
      replace('R0000001.JPG', _day3);
      replace('R0000002.MOV', _day3, videoLength: const Duration(seconds: 9));
      // Offline, what is cached still shows.
      expect(await thumbOf(jpeg), contains(_day1.toIso8601String()));
      expect(movies.cached(serial, movie), isNotNull);
      expect(downloads.isFileDownloaded(serial, jpeg), isTrue);

      link.value = connected();
      await until(
        () => m.revision(jpeg) > 0 && m.revision(movie) > 0,
        reason: 'background checks',
      );
      expect(m.revision(pair.raw!), 0);
      expect(m.info(jpeg)?.taken, _day3);
      expect(await thumbOf(jpeg), contains(_day3.toIso8601String()));
      expect(movies.cached(serial, movie), isNull);
      final newMovie = await (await movies.download(link.value!, movie).done)
          .readAsBytes();
      expect(newMovie, isNot(oldMovie));
      await until(
        () => !downloads.isFileDownloaded(serial, jpeg),
        reason: 'JPEG mark dropped',
      );
      await until(() => m.info(pair.raw!) != null, reason: 'DNG checked');
      await pumpEventQueue();
      expect(downloads.isFileDownloaded(serial, pair.raw!), isTrue);
    });

    test('copies made on an earlier link of a file whose info never came '
        'go when its first info arrives', () async {
      final m = await listed();
      final pair = m.shots!.firstWhere((s) => s.isPair);
      final jpeg = pair.jpeg!;
      final movie = m.shots!.firstWhere((s) => s.isVideo).primary;
      // Cached while the file's /info is never asked for (or fails).
      expect(await thumbOf(jpeg), contains(_day1.toIso8601String()));
      await movies.download(link.value!, movie).done;
      expect(m.info(jpeg), isNull);

      link.value = null;
      replace('R0000001.JPG', _day3);
      replace('R0000002.MOV', _day3, videoLength: const Duration(seconds: 9));
      final listedBefore = m.listedAt;
      link.value = connected();
      await until(() => m.listedAt != listedBefore, reason: 'listing');
      // Fetched on this link before its first info: kept.
      expect(await thumbOf(pair.raw!), contains(_day1.toIso8601String()));

      expect((await m.ensureInfo(jpeg))?.taken, _day3);
      expect(m.revision(jpeg), 1);
      expect(await thumbOf(jpeg), contains(_day3.toIso8601String()));
      await m.ensureInfo(movie);
      expect(m.revision(movie), 1);
      expect(movies.cached(serial, movie), isNull);
      await m.ensureInfo(pair.raw!);
      expect(m.revision(pair.raw!), 0);
    });

    test('a file deleted and shot again drops its thumbnail and download '
        'mark', () async {
      final m = await listed();
      final shot = m.shots!.firstWhere(
        (s) => s.storage == GrStorageId.internal,
      );
      final f = shot.primary;
      await m.ensureInfo(f);
      expect(await thumbOf(f), contains(_day2.toIso8601String()));
      await downloads.enqueue(serial, [shot]);
      await downloads.whenIdle();
      expect(downloads.isFileDownloaded(serial, f), isTrue);

      expect(camera.removePhoto(f.path, storage: GrStorageId.internal), isTrue);
      await m.refresh();
      expect(m.shots!.map((s) => s.key), isNot(contains(shot.key)));
      expect(m.revision(f), 1);

      camera.addPhoto(
        FakePhoto(
          '100RICOH',
          'R0000001.JPG',
          _day3,
          storage: GrStorageId.internal,
        ),
      );
      await m.refresh();
      expect(m.shots!.map((s) => s.key), contains(shot.key));
      expect(await thumbOf(f), contains(_day3.toIso8601String()));
      await until(
        () => !downloads.isFileDownloaded(serial, f),
        reason: 'mark dropped',
      );
    });

    test('download marks stay for a card taken out and put back, and after '
        'the cached listing is cleared', () async {
      final m = await listed();
      final shot = m.shots!.firstWhere(
        (s) => s.storage == GrStorageId.internal,
      );
      final f = shot.primary;
      final photo = camera.photos.firstWhere(
        (p) => p.storage == GrStorageId.internal,
      );
      await downloads.enqueue(serial, [shot]);
      await downloads.whenIdle();

      camera.removePhoto(f.path, storage: GrStorageId.internal);
      await m.refresh();
      camera.addPhoto(photo);
      await m.refresh();
      await until(() => m.info(f) != null, reason: 'check');
      await pumpEventQueue();
      expect(downloads.isFileDownloaded(serial, f), isTrue);
      await m.flush();

      // The phone clears the app's cache; the record of downloads stays.
      link.value = null;
      await File('${cache.path}/$serial/library.json').delete();
      final fresh = await checked();
      expect(fresh.shots, isNull);
      link.value = connected();
      await until(() => fresh.info(f) != null, reason: 'recorded file checked');
      await pumpEventQueue();
      expect(downloads.isFileDownloaded(serial, f), isTrue);
    });
  });
}

/// A camera that lists an empty card and never answers `/info`.
final class _InfoStallingCamera {
  new _(this._server) {
    _server.listen((socket) {
      _sockets.add(socket);
      socket.done.ignore();
      var answered = false;
      var stalled = false;
      socket.listen(
        (data) {
          final text = latin1.decode(data);
          if (answered || !text.contains('\r\n\r\n')) return;
          answered = true;
          stalled = text.contains('/info');
          if (stalled) return;
          const body = '{"errCode":200,"dirs":[]}';
          socket.add(
            latin1.encode(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: application/json\r\n'
              'Content-Length: ${body.length}\r\n'
              'Connection: close\r\n\r\n'
              '$body',
            ),
          );
          unawaited(socket.close());
        },
        onDone: () {
          if (stalled && !closed.isCompleted) closed.complete();
          socket.destroy();
        },
        onError: (Object _) => socket.destroy(),
      );
    });
  }

  static Future<_InfoStallingCamera> start() async => _InfoStallingCamera._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final ServerSocket _server;
  final _sockets = <Socket>[];

  /// Completes when the client closed a connection it had asked on.
  final closed = Completer<void>();

  int get port => _server.port;

  Future<void> close() async {
    await _server.close();
    for (final s in _sockets) {
      s.destroy();
    }
  }
}
