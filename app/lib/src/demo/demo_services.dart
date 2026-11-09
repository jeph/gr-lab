import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/platform/app_dirs.dart';
import 'package:grlab/src/platform/media_saver.dart';
import 'package:grlab/src/services.dart';

/// Services backed by a simulated GR IV, for the emulator/simulator and for
/// trying the app without a camera (`--dart-define=GR_DEMO=true`).
///
/// The camera starts off, so connecting shows the wake step. On the first
/// run nothing is paired: when the pairing screen scans, the simulated user
/// turns the camera on and opens Execute Pairing, and presses OK two
/// seconds into the bonding. Later runs find the bond in place (a phone
/// keeps it across launches). Demo data lives in its own `demo/` folders
/// so demo and real cameras never mix.
Future<AppServices> buildDemoServices() async {
  final dirs = await appDirectories();
  final data = Directory('${dirs.data.path}/demo');
  final cache = Directory('${dirs.cache.path}/demo');
  await data.create(recursive: true);
  await cache.create(recursive: true);

  final deviceId = const FakeCameraConfig().deviceId;
  final saved = await CameraStore.load(data);
  final bonded = saved.cameras.any((c) => c.paired.deviceId == deviceId);
  final now = DateTime.now();

  final camera = FakeGrCamera(
    config: FakeCameraConfig(
      poweredOn: false,
      bonded: bonded,
      openExecutePairingOnScan: true,
      autoConfirmPairing: const Duration(seconds: 2),
      photos: FakePhoto.defaultCard(
        lastDay: DateTime(now.year, now.month, now.day - 1),
        videoLengths: const [_clipLength],
      ),
      advertisingInterval: const Duration(milliseconds: 200),
      connectDelay: const Duration(milliseconds: 400),
      bleLatency: const Duration(milliseconds: 25),
      wakeDelay: const Duration(seconds: 3),
      wlanOnDelay: const Duration(seconds: 2),
      joinDelay: const Duration(milliseconds: 2500),
      httpLatency: const Duration(milliseconds: 120),
      downloadBytesPerSecond: 400 * 1024,
    ),
    media: _bundledMedia(rootBundle),
  );
  await camera.startHttp();

  final trace = TraceRelay();
  return AppServices(
    camera: GrCameraEnvironment(
      ble: camera.transport,
      wifi: camera.wifi,
      trace: trace.call,
      httpFactory: camera.httpClient,
    ),
    trace: trace,
    media: PlatformMediaSaver(),
    clientName: 'GR Lab',
    dataDir: data,
    cacheDir: cache,
    debugLogDir: Directory('${data.path}/debug-log'),
    // As with a real camera, so the demo shows the same first join.
    askBeforeWifiJoin: Platform.isAndroid,
    isDemo: true,
  );
}

/// Length of `assets/demo/clip.mov`, which every demo movie plays.
const _clipLength = Duration(seconds: 3);

/// Twelve scenes (nine landscape, three portrait), each as a ~160 px
/// thumbnail, a ~1280 px view and a ~2000 px full JPEG, plus one movie.
/// Both halves of a RAW+JPEG pair map to the same scene.
///
/// Portrait scenes are stored as a GR stores them (see
/// [FakePhoto.orientation]): landscape pixels, with the Orientation tag
/// only in the full JPEG. `tall01` and `tall02` are held for orientation 6,
/// `tall03` for orientation 8.
FakeMediaSource _bundledMedia(AssetBundle bundle) {
  final loaded = <String, Future<Uint8List>>{};
  Future<Uint8List> load(String name) => loaded[name] ??= bundle
      .load('assets/demo/$name')
      .then((d) => d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));

  return (photo, size) {
    final variant = switch (size) {
      GrImageSize.thumb => 'thumb',
      GrImageSize.full => 'full',
      GrImageSize.view || GrImageSize.xs => 'view',
    };
    if (photo.isVideo) {
      return load(variant == 'full' ? 'clip.mov' : 'clip_$variant.jpg');
    }
    final number =
        int.tryParse(photo.baseName.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final scene = switch (photo.orientation) {
      6 => 'tall${(number % 2 + 1).toString().padLeft(2, '0')}',
      8 => 'tall03',
      _ => 'land${(number % 9 + 1).toString().padLeft(2, '0')}',
    };
    // Demo only: a DNG's full download is its scene's JPEG bytes. A real
    // DNG is a 20+ MB raw file that no bundled asset should stand in for.
    return load('${scene}_$variant.jpg');
  };
}
