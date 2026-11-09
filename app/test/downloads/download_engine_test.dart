import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart' show GrHttpClient;
import 'package:grlab/src/downloads/download_engine.dart';
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
  new _(this.camera, this.http, this.root, this.media, this.link);

  /// With [stall], the camera holds every full-size file (and every `/info`
  /// that needs its size) until `stall.stall` completes, completing
  /// `stall.stalled` when the first one waits.
  static Future<Harness> start({
    FakeCameraConfig config = const FakeCameraConfig(
      httpLatency: Duration.zero,
    ),
    Set<String>? failing,
    ({Completer<void> stall, Completer<void> stalled})? stall,
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
        if (size == GrImageSize.full && stall != null) {
          if (!stall.stalled.isCompleted) stall.stalled.complete();
          await stall.stall.future;
        }
        return await source(photo, size);
      },
    );
    await camera.startHttp();
    final http = camera.httpClient('127.0.0.1', null);
    final root = await Directory.systemTemp.createTemp('grlab_dl_');
    return Harness._(
      camera,
      http,
      root,
      RecordingMediaSaver(),
      ValueNotifier(null),
    )..connect();
  }

  final FakeGrCamera camera;
  final GrHttpClient http;
  final Directory root;
  final RecordingMediaSaver media;
  final ValueNotifier<CameraLibrary?> link;
  final List<DownloadEngine> _engines = [];

  Directory get data => Directory('${root.path}/data');
  Directory get cache => Directory('${root.path}/cache');

  /// A fresh link, as after every (re)connection.
  void connect() => link.value = CameraLibrary.overHttp(
    http,
    serial: serial,
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

  test('a pair with only its JPEG saved counts as downloaded for the grid '
      'but not for its RAW', () async {
    h = await Harness.start(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
    );
    final engine = h.engine();
    final pair = h.shot('R0000001');
    await engine.enqueue(serial, [pair], kinds: {FileKind.jpeg});
    await engine.whenIdle();
    expect(engine.isShotDownloaded(serial, pair), isTrue);
    expect(engine.areFilesDownloaded(serial, [pair.jpeg!]), isTrue);
    expect(engine.areFilesDownloaded(serial, [pair.raw!]), isFalse);
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
      h = (await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      ))..disconnect();
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

    test('a download keeps what the camera said of each file, across a '
        'restart, and goes when another file is at its path', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final first = h.engine();
      final jpeg = h.shot('R0000001').jpeg!;
      await first.enqueue(serial, [h.shot('R0000001')]);
      await first.whenIdle();
      await first.flush();

      final second = h.engine();
      await second.ready;
      final info = await h.link.value!.fileInfo(jpeg);
      // Even without the library's cached info to vouch for it.
      await second.checkFile(serial, jpeg, info, vouched: false);
      await second.fileStale(serial, jpeg);
      expect(second.isFileDownloaded(serial, jpeg), isTrue);
      await second.checkFile(
        serial,
        jpeg,
        FileInfo(taken: info.taken, size: info.size! + 1),
        vouched: true,
      );
      expect(second.isFileDownloaded(serial, jpeg), isFalse);
    });

    test("a record from before the camera's info was kept stays only where "
        'the library vouches for the file', () async {
      h = (await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      ))..disconnect();
      final pair = h.shot('R0000001');
      final jpeg = pair.jpeg!;
      final raw = pair.raw!;
      final single = h.shot('R0000002').jpeg!;
      await h.data.create(recursive: true);
      await File('${h.data.path}/downloads.json').writeAsString(
        jsonEncode({
          'version': 1,
          'jobs': <Object?>[],
          'downloaded': {
            serial: [jpeg.key, raw.key, single.key],
          },
        }),
      );
      final engine = h.engine();
      await engine.ready;
      expect(engine.areFilesDownloaded(serial, [jpeg, raw, single]), isTrue);

      final now = FileInfo(taken: _pair, size: 1000);
      await engine.checkFile(serial, jpeg, now, vouched: true);
      await engine.checkFile(serial, raw, now, vouched: false);
      await engine.fileStale(serial, single);
      expect(engine.isFileDownloaded(serial, jpeg), isTrue);
      expect(engine.isFileDownloaded(serial, raw), isFalse);
      expect(engine.isFileDownloaded(serial, single), isFalse);

      // The vouched record took the camera's info: it outlives the file
      // leaving the listing, and goes when another file is at its path.
      await engine.fileStale(serial, jpeg);
      expect(engine.isFileDownloaded(serial, jpeg), isTrue);
      await engine.checkFile(
        serial,
        jpeg,
        FileInfo(taken: _pair, size: 1001),
        vouched: true,
      );
      expect(engine.isFileDownloaded(serial, jpeg), isFalse);
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
      h = (await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      ))..disconnect();
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000002')]);
      expect(engine.waitingForCamera, isTrue);
      engine.cancel(engine.jobs.single);
      expect(engine.jobs, isEmpty);
      h.connect();
      await engine.whenIdle();
      expect(h.saved, isEmpty);
    });

    test('forgetting a camera while a shot of it is saved drops its queue '
        "and every record of it, that shot's included, keeping other "
        "cameras' records", () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final single = h.shot('R0000002').jpeg!;
      await h.data.create(recursive: true);
      await File('${h.data.path}/downloads.json').writeAsString(
        jsonEncode({
          'version': 2,
          'jobs': <Object?>[],
          'downloaded': {
            'other-camera': {single.key: null},
          },
        }),
      );
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000002')]);
      await engine.whenIdle();
      h.media.gate = Completer<void>();
      await engine.enqueue(serial, [h.shot('R0000003'), h.shot('R0000001')]);
      await until(() => h.media.held == 1, reason: 'saving');

      final forgotten = engine.forgetCamera(serial);
      h.media.gate!.complete();
      await forgotten;
      expect(h.saved, [
        ['R0000002.JPG'],
        ['R0000003.DNG'],
      ]);
      expect(engine.jobs, isEmpty);
      await engine.flush();
      final restarted = h.engine();
      await restarted.ready;
      for (final e in [engine, restarted]) {
        expect(e.jobs, isEmpty);
        for (final base in ['R0000001', 'R0000002', 'R0000003']) {
          expect(e.isShotDownloaded(serial, h.shot(base)), isFalse);
        }
        expect(e.isFileDownloaded('other-camera', single), isTrue);
      }
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
      expect(
        failed.failure,
        isA<DownloadTransferFailed>().having(
          (f) => f.reason,
          'reason',
          isA<TransferRefused>().having((r) => r.errCode, 'errCode', 500),
        ),
      );
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

    test('why a job failed survives a restart', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
        failing: {'R0000002.JPG'},
      );
      final first = h.engine();
      await first.enqueue(serial, [h.shot('R0000002')]);
      await first.whenIdle();
      await first.flush();
      first.dispose();
      h._engines.remove(first);

      final second = h.engine();
      await second.ready;
      final job = second.jobs.single;
      expect(job.state, DownloadState.failed);
      expect(
        job.failure,
        isA<DownloadTransferFailed>().having(
          (f) => f.reason,
          'reason',
          isA<TransferRefused>().having((r) => r.errCode, 'errCode', 500),
        ),
      );
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
      // The simulated camera closes the socket mid-body.
      expect(
        engine.jobs.single.failure,
        isA<DownloadTransferFailed>().having(
          (f) => f.reason,
          'reason',
          isA<TransferConnectionLost>(),
        ),
      );
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
      h.media.failWith = const MediaSaveException(
        MediaSaveFailure.failed,
        'disk full',
      );
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000002')]);
      await engine.whenIdle();
      expect(
        engine.jobs.single.failure,
        isA<DownloadSaveFailed>().having(
          (f) => f.reason,
          'reason',
          MediaSaveFailure.failed,
        ),
      );
      expect(engine.permissionProblem, isNull);
      // The save is known to have failed, so a restart says so.
      await engine.flush();
      final reopened = h.engine();
      await reopened.ready;
      expect(reopened.jobs.single.failure, isA<DownloadSaveFailed>());
      reopened.dispose();
      h._engines.remove(reopened);

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
          MediaSaveFailure.permissionDenied,
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

    test('a shot the photo library took just before the app stopped is not '
        'saved again on restart; its job asks instead', () async {
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      );
      final crashing = _StoppingSaver();
      final first = DownloadEngine(
        dataDir: h.data,
        cacheDir: h.cache,
        media: crashing,
        link: h.link,
        progressInterval: Duration.zero,
      );
      await first.enqueue(serial, [h.shot('R0000002')]);
      await crashing.saved.future;
      // The app stops here, before recording the save: a restart reads what
      // reached the disk so far.
      final restarted = Directory('${h.root.path}/restarted')..createSync();
      File('${h.data.path}/downloads.json')
          .copySync('${restarted.path}/downloads.json');
      first.dispose();

      final second = DownloadEngine(
        dataDir: restarted,
        cacheDir: h.cache,
        media: h.media,
        link: h.link,
        progressInterval: Duration.zero,
      );
      h._engines.add(second);
      await second.whenIdle();
      expect(h.saved, isEmpty, reason: 'not saved a second time');
      final job = second.jobs.single;
      expect(job.state, DownloadState.failed);
      expect(job.failure, isA<DownloadSaveInterrupted>());

      // The user can still save it again.
      second.retry(job);
      await until(() => h.saved.isNotEmpty, reason: 'retry');
      await second.whenIdle();
      expect(h.saved, [
        ['R0000002.JPG'],
      ]);
      expect(second.jobs, isEmpty);
    });

    test('a save the queue cannot record first is not made; the job fails '
        'and keeps its copy for a retry', () async {
      final stall = (stall: Completer<void>(), stalled: Completer<void>());
      h = await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
        stall: stall,
      );
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000002')]);
      await stall.stalled.future;
      await engine.flush();
      // A folder where downloads.json goes: no write can replace it.
      final queueFile = File('${h.data.path}/downloads.json');
      await queueFile.delete();
      final blocker = await Directory(queueFile.path).create();
      stall.stall.complete();
      await engine.whenIdle();
      expect(h.saved, isEmpty, reason: 'a save it could not record');
      final job = engine.jobs.single;
      expect(
        job.failure,
        isA<DownloadTransferFailed>().having(
          (f) => f.reason,
          'reason',
          isA<TransferWriteFailed>(),
        ),
      );
      expect(
        Directory('${h.cache.path}/downloads/${job.id}')
            .listSync(recursive: true)
            .whereType<File>(),
        isNotEmpty,
        reason: 'the copy stays for the retry',
      );

      await blocker.delete();
      engine.retry(job);
      await until(() => h.saved.isNotEmpty, reason: 'retry');
      await engine.whenIdle();
      expect(h.saved, [
        ['R0000002.JPG'],
      ]);
    });
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

    test("a shot's files copied before a lost connection are copied again, "
        'as their paths may hold other files by then', () async {
      h = await Harness.start(
        config: FakeCameraConfig(
          httpLatency: Duration.zero,
          photos: card(),
          downloadBytesPerSecond: 40 * 1024,
        ),
      );
      final engine = h.engine();
      await engine.enqueue(serial, [h.shot('R0000001')]);
      await until(
        () => engine.progress.value.fraction > 0.5,
        reason: 'JPEG copied, DNG started',
      );
      h.disconnect();
      await engine.whenIdle();
      expect(h.saved, isEmpty);

      // Another card, with another shot under the JPEG's name.
      final old = h.camera.photos.firstWhere(
        (p) => p.file == 'R0000001.JPG' && p.storage == GrStorageId.sd,
      );
      final replacement = FakePhoto(
        '100RICOH',
        'R0000001.JPG',
        _pair.add(const Duration(days: 1)),
      );
      expect(h.camera.removePhoto(old.path), isTrue);
      h.camera.addPhoto(replacement);
      final oldBytes = await h.camera.media(old, GrImageSize.full);
      final newBytes = await h.camera.media(replacement, GrImageSize.full);
      expect(newBytes.length, isNot(oldBytes.length));

      h.connect();
      await until(() => h.saved.isNotEmpty, reason: 'resume');
      expect(h.saved.single, ['R0000001.JPG', 'R0000001.DNG']);
      expect(h.media.shots.single.sizes.first, newBytes.length);
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

    for (final cancel in [false, true]) {
      test('${cancel ? 'cancelling' : 'pausing'} a stalled transfer closes '
          'its camera request at once', () async {
        final stall = (stall: Completer<void>(), stalled: Completer<void>());
        h = await Harness.start(
          config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
          stall: stall,
        );
        // The camera may answer once the test is over.
        addTearDown(stall.stall.complete);
        final engine = h.engine();
        await engine.enqueue(serial, [h.shot('R0000002')]);
        await stall.stalled.future;
        if (cancel) {
          engine.cancel(engine.current!);
        } else {
          engine.pause();
        }
        // Without closing the request, the engine would wait for its
        // 10-second HTTP deadline.
        await engine.whenIdle().timeout(const Duration(seconds: 5));
        expect(engine.current, isNull);
        expect(
          engine.jobs.map((j) => j.state),
          cancel ? isEmpty : [DownloadState.queued],
        );
        expect(h.saved, isEmpty);
      });
    }

    test('the queue survives a restart', () async {
      h = (await Harness.start(
        config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
      ))..disconnect();
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

  test('a failed queue write fails flush and reaches the debug log; later '
      'writes recover', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);
    h = (await Harness.start(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
    ))..disconnect();
    final engine = h.engine();
    await engine.ready;
    // A folder where downloads.json goes: the write cannot replace it.
    final blocker = await Directory('${h.data.path}/downloads.json')
        .create(recursive: true);
    await engine.enqueue(serial, [h.shot('R0000002')]);
    await expectLater(engine.flush(), throwsA(isA<FileSystemException>()));
    expect(printed, contains(startsWith('Saving downloads.json failed')));

    await blocker.delete();
    await engine.enqueue(serial, [h.shot('R0000003')]);
    await engine.flush();
    final reopened = h.engine();
    await reopened.ready;
    expect(reopened.jobs.map((j) => j.shot.base), ['R0000002', 'R0000003']);
    expect(h.data.listSync().map((e) => e.uri.pathSegments.last), [
      'downloads.json',
    ]);
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
    h = (await Harness.start(
      config: FakeCameraConfig(httpLatency: Duration.zero, photos: card()),
    ))..disconnect();
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

/// A photo library that takes the shot and then never answers, as when the
/// app is stopped right after the save.
final class _StoppingSaver implements MediaSaver {
  final saved = Completer<void>();

  @override
  Future<void> saveShot(List<File> files, {required String album}) {
    if (!saved.isCompleted) saved.complete();
    return Completer<void>().future;
  }
}
