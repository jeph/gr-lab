import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/camera_link.dart';
import 'package:grlab/src/library/shot.dart';
import 'package:grlab/src/services.dart';

import '../support/test_app.dart';

const serial = '1234567';

final _pair = DateTime(2026, 11, 5, 10);

/// A small card: a pair, a JPEG, a DNG and a movie in 100RICOH on the SD
/// card, plus a JPEG with the pair's name in internal memory.
List<FakePhoto> card() => [
  FakePhoto('100RICOH', 'R0000001.JPG', _pair),
  FakePhoto('100RICOH', 'R0000001.DNG', _pair),
  FakePhoto('100RICOH', 'R0000002.JPG', _pair),
  FakePhoto('100RICOH', 'R0000003.DNG', _pair),
  FakePhoto(
    '100RICOH',
    'R0000004.MOV',
    _pair,
    videoLength: const Duration(seconds: 12),
  ),
  FakePhoto('100RICOH', 'R0000001.JPG', _pair, storage: GrStorageId.internal),
];

/// Polls [condition] in real time.
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

final class Harness {
  Harness._(this.camera, this.http, this.root, this.media, this.link);

  static Future<Harness> start({
    FakeCameraConfig config = const FakeCameraConfig(
      httpLatency: Duration.zero,
    ),
    Set<String>? failing,
  }) async {
    HttpOverrides.global = null;
    final source = syntheticMedia(
      jpegBytes: 20 * 1024,
      rawBytes: 40 * 1024,
      movieBytes: 60 * 1024,
    );
    final camera = FakeGrCamera(
      config: config,
      media: (photo, size) async {
        if (size == GrImageSize.full &&
            (failing?.contains(photo.file) ?? false)) {
          throw StateError('card read error');
        }
        return source(photo, size);
      },
    );
    await camera.startHttp();
    final http = camera.httpClient('127.0.0.1', null);
    final root = await Directory.systemTemp.createTemp('grlab_dl_');
    final h = Harness._(
      camera,
      http,
      root,
      RecordingMediaSaver(),
      ValueNotifier(null),
    );
    h.connect();
    return h;
  }

  final FakeGrCamera camera;
  final GrHttpClient http;
  final Directory root;
  final RecordingMediaSaver media;
  final ValueNotifier<CameraLink?> link;
  final List<DownloadEngine> _engines = [];

  Directory get data => Directory('${root.path}/data');
  Directory get cache => Directory('${root.path}/cache');

  /// A fresh link, as after every (re)connection.
  void connect() => link.value = CameraLink(
    serial: serial,
    http: http,
    storages: const [GrStorageId.internal, GrStorageId.sd],
  );

  void disconnect() => link.value = null;

  DownloadEngine engine({Duration transportGrace = Duration.zero}) {
    final e = DownloadEngine(
      dataDir: data,
      cacheDir: cache,
      media: media,
      link: link,
      transportGrace: transportGrace,
      progressInterval: Duration.zero,
    );
    _engines.add(e);
    return e;
  }

  List<Shot> get shots => groupShots([
    for (final p in camera.photos) CameraFile(p.storage, p.path),
  ]);

  Shot shot(String base, {String storage = GrStorageId.sd}) =>
      shots.firstWhere((s) => s.base == base && s.storage == storage);

  List<List<String>> get saved => [for (final s in media.shots) s.names];

  Future<void> close() async {
    for (final e in _engines) {
      await e.flush();
      e.dispose();
    }
    link.dispose();
    http.close(force: true);
    await camera.close();
    await root.delete(recursive: true);
  }
}

void main() {
  late Harness h;

  tearDown(() => h.close());

  group('file kinds', () {
    for (final (kind, expected) in [
      (FileKind.jpeg, ['R0000001.JPG']),
      (FileKind.raw, ['R0000001.DNG']),
    ]) {
      test('the ${kind.name} action takes only its half of a RAW+JPEG '
          'pair', () async {
        h = await Harness.start(
          config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
        );
        final engine = h.engine();
        final pair = h.shot('R0000001');
        expect(engine.filesToDownload(serial, pair, kind), [
          pair.filesOf(kind).single,
        ]);
        expect(await engine.enqueue(serial, [pair], kinds: {kind}), 1);
        await engine.whenIdle();
        expect(h.saved, [expected]);
        expect(h.media.shots.single.album, 'GR');
        expect(engine.jobs, isEmpty);
        expect(engine.isShotDownloaded(serial, pair), isTrue);
      });
    }

    test('each action takes single files of its own kind only', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final engine = h.engine();
      final shots = [h.shot('R0000002'), h.shot('R0000003')];
      expect(engine.filesToDownload(serial, shots[0], FileKind.raw), isEmpty);
      expect(engine.filesToDownload(serial, shots[1], FileKind.jpeg), isEmpty);
      expect(await engine.enqueue(serial, shots, kinds: {FileKind.raw}), 1);
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000003.DNG'],
      ]);
    });

    test('every file by default, movies included', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final engine = h.engine();
      await engine.enqueue(serial, [
        h.shot('R0000001'),
        h.shot('R0000002'),
        h.shot('R0000003'),
        h.shot('R0000004'),
      ]);
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000001.JPG', 'R0000001.DNG'],
        ['R0000002.JPG'],
        ['R0000003.DNG'],
        ['R0000004.MOV'],
      ]);
      final full = h.media.shots.last.sizes.single;
      expect(full, greaterThan(60 * 1024 - 1));
    });

    test('same name on two storages downloads both files', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final engine = h.engine();
      final sd = h.shot('R0000001');
      final internal = h.shot('R0000001', storage: GrStorageId.internal);
      await engine.enqueue(serial, [sd, internal], kinds: {FileKind.jpeg});
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000001.JPG'],
        ['R0000001.JPG'],
      ]);
      expect(engine.isShotDownloaded(serial, internal), isTrue);
    });
  });

  group('duplicates', () {
    test('downloaded files download again when asked', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final engine = h.engine();
      final pair = h.shot('R0000001');
      await engine.enqueue(serial, [pair], kinds: {FileKind.jpeg});
      await engine.whenIdle();
      expect(engine.isShotDownloaded(serial, pair), isTrue);
      // Whatever was saved may since have been deleted from the phone.
      expect(engine.filesToDownload(serial, pair, FileKind.jpeg), [pair.jpeg]);

      expect(await engine.enqueue(serial, [pair]), 2);
      await engine.whenIdle();
      expect(await engine.enqueueFiles(serial, pair, [pair.raw!]), 1);
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000001.JPG'],
        ['R0000001.JPG', 'R0000001.DNG'],
        ['R0000001.DNG'],
      ]);
      expect(engine.jobs, isEmpty);
    });

    test('queueing the same shot twice saves it once', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      h.disconnect();
      final engine = h.engine();
      final shot = h.shot('R0000002');
      expect(await engine.enqueue(serial, [shot]), 1);
      expect(await engine.enqueue(serial, [shot]), 0);
      expect(engine.filesToDownload(serial, shot, FileKind.jpeg), isEmpty);
      expect(engine.jobs, hasLength(1));
      h.connect();
      await until(() => h.saved.isNotEmpty, reason: 'save');
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000002.JPG'],
      ]);
    });

    test('downloaded records survive a restart', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final first = h.engine();
      final pair = h.shot('R0000001');
      await first.enqueue(serial, [pair]);
      await first.whenIdle();
      await first.flush();

      final second = h.engine();
      await second.ready;
      expect(second.isShotDownloaded(serial, pair), isTrue);
      expect(second.isFileDownloaded('other-camera', pair.jpeg!), isFalse);
    });
  });

  group('cancel', () {
    test('cancelling the running transfer saves nothing', () async {
      h = await Harness.start(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 40 * 1024,
        ),
      );
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000003'), h.shot('R0000002')]);
      await until(
        () => engine.progress.value.received > 0,
        reason: 'transfer start',
      );
      final running = engine.current!;
      expect(running.shot.base, 'R0000003');
      engine.cancel(running);
      await until(
        () => engine.jobs.every((j) => j.shot.base != 'R0000003'),
        reason: 'cancel',
      );
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000002.JPG'],
      ]);
      final temp = Directory('${h.cache.path}/downloads');
      expect(
        temp.existsSync() ? temp.listSync() : const <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('cancel all empties the queue', () async {
      h = await Harness.start(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 40 * 1024,
        ),
      );
      final engine = h.engine();
      await engine.enqueue(serial, h.shots);
      await until(() => engine.current != null, reason: 'transfer start');
      engine.cancelAll();
      await engine.whenIdle();
      expect(engine.jobs, isEmpty);
      expect(h.saved, isEmpty);
    });

    test('a waiting job is removed at once', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      h.disconnect();
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000002')]);
      expect(engine.waitingForCamera, isTrue);
      engine.cancel(engine.jobs.single);
      expect(engine.jobs, isEmpty);
      h.connect();
      await engine.whenIdle();
      expect(h.saved, isEmpty);
    });
  });

  group('failure', () {
    test('a refused file fails its job; retry downloads it', () async {
      final failing = {'R0000002.JPG'};
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
        failing: failing,
      );
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000002'), h.shot('R0000003')]);
      await engine.whenIdle();
      final failed = engine.jobs.single;
      expect(failed.state, DownloadState.failed);
      expect(failed.shot.base, 'R0000002');
      expect(failed.error, contains('500'));
      expect(h.saved, [
        ['R0000003.DNG'],
      ]);

      failing.clear();
      engine.retry(failed);
      await until(() => h.saved.length == 2, reason: 'retry');
      await engine.whenIdle();
      expect(h.saved.last, ['R0000002.JPG']);
      expect(engine.jobs, isEmpty);
    });

    test('a transfer cut off while still connected fails after the grace '
        'period', () async {
      h = await Harness.start(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          cutDownloadsAfterBytes: 1000,
        ),
      );
      final engine = h.engine(transportGrace: const Duration(milliseconds: 50));
      await engine.enqueue(serial, [h.shot('R0000002')]);
      await engine.whenIdle();
      expect(engine.jobs.single.state, DownloadState.failed);
      expect(engine.jobs.single.error, isNotNull);
      expect(h.saved, isEmpty);
      expect(engine.failedCount, 1);
    });

    test('cancelling during the grace period after a network error removes '
        'the job for good', () async {
      h = await Harness.start(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          cutDownloadsAfterBytes: 1000,
        ),
      );
      final engine = h.engine(transportGrace: const Duration(seconds: 1));
      await engine.enqueue(serial, [h.shot('R0000002')]);
      await until(
        () => engine.progress.value.received >= 1000,
        reason: 'transfer cut',
      );
      // The cut has surfaced; the engine is waiting out the grace period.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.current, isNotNull);
      engine.cancel(engine.current!);
      await engine.whenIdle();
      expect(engine.jobs, isEmpty);

      h.connect();
      await engine.whenIdle();
      expect(engine.jobs, isEmpty);
      expect(h.saved, isEmpty);
    });

    test('a failed save keeps the job for retry', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      h.media.failWith = const MediaSaveException('failed', 'disk full');
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000002')]);
      await engine.whenIdle();
      expect(engine.jobs.single.error, 'disk full');
      expect(engine.permissionProblem, isNull);

      h.media.failWith = null;
      engine.retryFailed();
      await until(() => h.saved.isNotEmpty, reason: 'retry');
      expect(h.saved, [
        ['R0000002.JPG'],
      ]);
    });

    test(
      'permission denied fails the whole queue and is reported once',
      () async {
        h = await Harness.start(
          config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
        );
        h.media.failWith = const MediaSaveException(
          'permissionDenied',
          'Photos access denied',
        );
        final engine = h.engine();
        await engine.enqueue(serial, [
          h.shot('R0000002'),
          h.shot('R0000003'),
          h.shot('R0000004'),
        ]);
        await engine.whenIdle();
        expect(engine.permissionProblem?.permissionDenied, isTrue);
        expect(engine.jobs, hasLength(3));
        expect(
          engine.jobs.map((j) => j.state),
          everyElement(DownloadState.failed),
        );
        expect(h.saved, isEmpty);

        engine.dismissPermissionProblem();
        expect(engine.permissionProblem, isNull);
        h.media.failWith = null;
        engine.retryFailed();
        await until(() => h.saved.length == 3, reason: 'retry all');
        await engine.whenIdle();
        expect(engine.jobs, isEmpty);
      },
    );
  });

  group('connection', () {
    test('pauses when disconnected and restarts the file when connected '
        'again', () async {
      h = await Harness.start(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 40 * 1024,
        ),
      );
      final engine = h.engine();
      final shot = h.shot('R0000003');
      await engine.enqueue(serial, [shot]);
      await until(
        () => engine.progress.value.received > 0,
        reason: 'transfer start',
      );
      h.disconnect();
      await engine.whenIdle();
      expect(engine.jobs.single.state, DownloadState.queued);
      expect(engine.waitingForCamera, isTrue);
      expect(h.saved, isEmpty);

      h.connect();
      await until(() => h.saved.isNotEmpty, reason: 'resume');
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000003.DNG'],
      ]);
      final expected = await h.camera.media(
        h.camera.photos.firstWhere((p) => p.file == 'R0000003.DNG'),
        GrImageSize.full,
      );
      expect(h.media.shots.single.sizes, [expected.length]);
      expect(engine.jobs, isEmpty);
    });

    test('queued jobs wait for their own camera', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final engine = h.engine();
      await engine.enqueue('another-serial', [h.shot('R0000002')]);
      await engine.whenIdle();
      expect(engine.jobs.single.state, DownloadState.queued);
      expect(h.saved, isEmpty);
    });

    test('pause and resume by the user', () async {
      h = await Harness.start(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 40 * 1024,
        ),
      );
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000003')]);
      await until(
        () => engine.progress.value.received > 0,
        reason: 'transfer start',
      );
      engine.pause();
      await engine.whenIdle();
      expect(engine.paused, isTrue);
      expect(engine.jobs.single.state, DownloadState.queued);
      expect(h.saved, isEmpty);

      engine.resume();
      await until(() => h.saved.isNotEmpty, reason: 'resume');
      expect(h.saved, [
        ['R0000003.DNG'],
      ]);
    });

    test('the queue survives a restart', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      h.disconnect();
      final first = h.engine();
      await first.enqueue(serial, [h.shot('R0000001')]);
      await first.flush();

      final second = h.engine();
      await second.ready;
      expect(second.jobs.single.files.map((f) => f.name), [
        'R0000001.JPG',
        'R0000001.DNG',
      ]);
      // Only the reloaded engine runs: the first one is gone with its app.
      first.dispose();
      h._engines.remove(first);
      h.connect();
      await until(() => h.saved.isNotEmpty, reason: 'resume after restart');
      await second.whenIdle();
      expect(h.saved, [
        ['R0000001.JPG', 'R0000001.DNG'],
      ]);
    });
  });

  test('records loaded from disk reach listeners', () async {
    h = await Harness.start(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
    );
    final pair = h.shot('R0000001');
    final single = h.shot('R0000002');
    h.disconnect();
    final first = h.engine();
    await first.enqueue(serial, [pair]);
    await first.flush();
    first.dispose();
    h._engines.remove(first);
    // Records from an earlier run must also reach listeners after loading.
    final seeded = h.engine();
    h.connect();
    await seeded.enqueue(serial, [single]);
    await until(() => h.saved.length == 2, reason: 'seed downloads');
    await seeded.whenIdle();
    await seeded.flush();
    seeded.dispose();
    h._engines.remove(seeded);
    expect(h.saved, [
      ['R0000001.JPG', 'R0000001.DNG'],
      ['R0000002.JPG'],
    ]);

    // Reopen with the link already up: nothing changes on the link.
    h.media.shots.clear();
    final reopened = h.engine();
    var notified = 0;
    reopened.addListener(() => notified++);
    await reopened.ready;
    await Future<void>.delayed(Duration.zero);
    expect(notified, greaterThan(0));
    expect(reopened.isShotDownloaded(serial, single), isTrue);
    expect(reopened.jobs, isEmpty);
  });

  test('a queue reopened while connected runs without a link change', () async {
    h = await Harness.start(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
    );
    h.disconnect();
    final first = h.engine();
    await first.enqueue(serial, [h.shot('R0000001')]);
    await first.flush();
    first.dispose();
    h._engines.remove(first);

    h.connect();
    final reopened = h.engine();
    await until(() => h.saved.isNotEmpty, reason: 'restored job runs');
    await reopened.whenIdle();
    expect(h.saved, [
      ['R0000001.JPG', 'R0000001.DNG'],
    ]);
    expect(reopened.jobs, isEmpty);
  });

  test('progress reports bytes and a rate', () async {
    h = await Harness.start(
      config: FakeCameraConfig(
        httpLatency: Duration.zero,
        photos: card(),
        downloadBytesPerSecond: 80 * 1024,
      ),
    );
    final engine = h.engine();
    final seen = <DownloadProgress>[];
    engine.progress.addListener(() => seen.add(engine.progress.value));
    await engine.enqueue(serial, [h.shot('R0000001')]);
    await until(() => h.saved.isNotEmpty, reason: 'download');
    final moving = seen.where((p) => p.received > 0).toList();
    expect(moving, isNotEmpty);
    expect(moving.map((p) => p.fraction), everyElement(inInclusiveRange(0, 1)));
    expect(moving.any((p) => p.fraction > .5), isTrue);
    expect(moving.any((p) => p.bytesPerSecond > 0), isTrue);
  });
}
