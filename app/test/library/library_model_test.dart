import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart' show GrHttpClient;
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/library/library_model.dart';
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
  Future<LibraryModel> model([String? current = serial]) async {
    final cameras = await CameraStore.load(await data.createTemp());
    if (current != null) await cameras.add(saved(current));
    final m = LibraryModel(
      cacheDir: cache,
      cameras: cameras,
      link: link,
      queue: queue,
      changeDebounce: const Duration(milliseconds: 10),
      saveDelay: Duration.zero,
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
}
