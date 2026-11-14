import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart' show GrBleCatalog, GrImageSize;
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/library/shot_cell.dart';
import 'package:grphoto/src/platform/app_dirs.dart';
import 'package:grphoto/src/platform/background_downloads.dart';
import 'package:grphoto/src/platform/camera_wifi_service.dart';
import 'package:grphoto/src/platform/media_saver.dart';
import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/services.dart';
import 'package:integration_test/integration_test.dart';

/// Where the host waits for screenshot requests: a simulator app reads and
/// writes the Mac's own file system.
late final String _shotDir;

/// The photos of the simulated card, which `tool/store_screenshots/run.sh`
/// downloads: `scenes.json` and `sNN_{thumb,view,full,live}.jpg`.
late final String _mediaDir;

/// Reads [_shotDir] and [_mediaDir] from `store-screenshots.json`, which the
/// host puts into the app's data folder before it starts the app: an app
/// started on a simulator gets no arguments or environment from the host.
Future<void> _readFolders() async {
  final dirs = await appDirectories();
  final folders = jsonDecode(
    File('${dirs.data.path}/store-screenshots.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  _shotDir = folders['shots'] as String;
  _mediaDir = folders['media'] as String;
}

typedef _P = LookParameter;

/// The looks the screenshots show, each with the scene its saved look is
/// taken from. The first three are in the camera's Custom slots.
final _looks = <({String name, Look look, int scene})>[
  (
    name: 'Lisbon Sun',
    look: Look.onBase(LookBase.positiveFilm)
        .withValue(_P.saturation, 1)
        .withValue(_P.key, 1)
        .withValue(_P.contrast, 1),
    scene: 0,
  ),
  (
    name: 'Neon Nights',
    look: Look.onBase(LookBase.cineGreen)
        .withValue(_P.toningCinema, 2)
        .withValue(_P.key, -1)
        .withValue(_P.contrast, 2)
        .withValue(_P.clarity, 1),
    scene: 9,
  ),
  (
    name: 'Soft Summer',
    look: Look.onBase(LookBase.negativeFilm)
        .withValue(_P.saturation, -1)
        .withValue(_P.hue, 1)
        .withValue(_P.key, 1),
    scene: 1,
  ),
  (
    name: 'Island Colour',
    look: Look.onBase(LookBase.vivid)
        .withValue(_P.saturation, 2)
        .withValue(_P.contrast, 1)
        .withValue(_P.contrastHigh, -1)
        .withValue(_P.clarity, 2),
    scene: 2,
  ),
  (
    name: 'Faded Film',
    look: Look.onBase(LookBase.retro)
        .withValue(_P.key, 1)
        .withValue(_P.contrast, -1)
        .withValue(_P.shading, -2),
    scene: 4,
  ),
  (
    name: 'Golden Hour',
    look: Look.onBase(LookBase.cineYellow)
        .withValue(_P.toningCinema, 1)
        .withValue(_P.saturation, 1)
        .withValue(_P.key, 1),
    scene: 8,
  ),
];

/// The look the load screenshot puts into a slot, and the one the editor
/// screenshot opens.
const _featured = 'Island Colour';

/// Well-known public places, one for each day of the card.
const _places = [
  (38.707500, -9.136400),
  (35.659500, 139.700500),
  (41.140700, -8.613000),
  (38.691600, -9.216000),
  (40.208900, -8.426500),
  (38.797900, -9.390600),
];

/// One photo of the card: a scene, the day it was shot on (0 is the
/// newest) and whether the camera was held upright.
typedef _Scene = ({int number, int day, bool portrait});

/// The scenes of `scenes.json`, newest first, [perDay] to a day: as many as
/// fill whole rows of the Library's grid, so no day ends in a gap.
List<_Scene> _readScenes({required int perDay}) => [
  for (final s in (jsonDecode(
    File('$_mediaDir/scenes.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>())
    (
      number: s['scene']! as int,
      day: (s['scene']! as int) ~/ perDay,
      portrait: s['portrait']! as bool,
    ),
];

String _baseName(int scene, int scenes) =>
    'R${(231 + scenes - 1 - scene).toString().padLeft(7, '0')}';

/// A card that has been shot on for six days: the scenes newest first, as
/// RAW+JPEG pairs, single JPEGs and DNGs and two movies, each with the look
/// of [_looks] its scene belongs to, or one of them in turn.
List<FakePhoto> _card(List<_Scene> scenes, DateTime lastDay) {
  // P = RAW+JPEG, J = JPEG only, D = DNG only, M = movie.
  const kinds = 'PPPPPJPPJPJPPDPJPPPJPPJPDPPJPMPPJPPJPPDPJPPJPPJMPJPPDP';
  const startHour = [16, 21, 11, 9, 14, 18];
  const avs = ['2.8', '4.0', '5.6', '8.0', '3.5'];
  const tvs = ['1.250', '1.125', '1.500', '1.60', '1.1000', '1.30'];
  const svs = ['200', '400', '800', '1600', '3200', '100'];
  const xvs = ['0.0', '-0.3', '-0.7', '+0.3', '0.0', '-1.0'];

  final photos = <FakePhoto>[];
  final shotOfDay = <int, int>{};
  for (final scene in scenes.reversed) {
    final i = scene.number;
    final nth = shotOfDay.update(scene.day, (n) => n + 1, ifAbsent: () => 0);
    final place = _places[scene.day];
    final kind = kinds[i % kinds.length];
    final look = _looks.where((l) => l.scene == i).firstOrNull;
    FakePhoto make(String extension, {Duration? length}) => FakePhoto(
      i < 30 ? '101RICOH' : '100RICOH',
      '${_baseName(i, scenes.length)}.$extension',
      DateTime(
        lastDay.year,
        lastDay.month,
        lastDay.day - scene.day,
        startHour[scene.day],
        4 + nth * 7,
        11 + nth * 13 % 40,
      ),
      videoLength: length,
      orientation: scene.portrait ? 6 : 1,
      av: avs[i % avs.length],
      tv: tvs[i % tvs.length],
      sv: svs[i % svs.length],
      xv: xvs[i % xvs.length],
      imageControl: kind == 'M'
          ? null
          : (look ?? _looks[i % _looks.length]).look.toBytes(),
      location: kind == 'M'
          ? null
          : FakePhotoLocation(
              place.$1 + nth * 0.0007,
              place.$2 - nth * 0.0011,
              altitude: 12.0 + nth,
            ),
    );
    switch (kind) {
      case 'P':
        photos
          ..add(make('JPG'))
          ..add(make('DNG'));
      case 'J':
        photos.add(make('JPG'));
      case 'D':
        photos.add(make('DNG'));
      default:
        photos.add(make('MOV', length: const Duration(seconds: 24)));
    }
  }
  return photos;
}

/// Whether the walk is in live view. The simulated camera streams the views
/// of its newest stills, and the app drops frames over 1 MiB, which the
/// views are: they then come in the smaller size of a live view frame.
var _inLiveView = false;

/// Serves every file of the card from [_mediaDir] by its scene; a movie
/// plays the demo's clip.
FakeMediaSource _media(int scenes) => (photo, size) async {
  if (photo.isVideo && size == GrImageSize.full) {
    final clip = await rootBundle.load('assets/demo/clip.mov');
    return clip.buffer.asUint8List(clip.offsetInBytes, clip.lengthInBytes);
  }
  final number = int.parse(photo.baseName.substring(1));
  final scene = (scenes - 1 - (number - 231)).toString().padLeft(2, '0');
  final variant = switch (size) {
    GrImageSize.thumb => 'thumb',
    GrImageSize.full => 'full',
    GrImageSize.view || GrImageSize.xs => _inLiveView ? 'live' : 'view',
  };
  return await File('$_mediaDir/s${scene}_$variant.jpg').readAsBytes();
};

/// The demo's services (`buildDemoServices`) with a card and looks that
/// look used, a camera that already stores locations and no data from an
/// earlier run.
Future<AppServices> _services(
  List<_Scene> scenes,
  PlatformWindowPose pose,
) async {
  final dirs = await appDirectories();
  final data = Directory('${dirs.data.path}/store-screenshots');
  final cache = Directory('${dirs.cache.path}/store-screenshots');
  for (final d in [data, cache]) {
    if (d.existsSync()) await d.delete(recursive: true);
    await d.create(recursive: true);
  }

  final now = DateTime.now();
  final slotCodec = GrBleCatalog.imageControl1Data.codec;
  final camera = FakeGrCamera(
    config: FakeCameraConfig(
      poweredOn: false,
      openExecutePairingOnScan: true,
      autoConfirmPairing: const Duration(seconds: 1),
      photos: _card(scenes, DateTime(now.year, now.month, now.day - 1)),
      lookSlots: [
        for (final l in _looks.take(3))
          FakeLook(l.name, slotCodec.decode(l.look.toBytes()).value!),
      ],
      storeLocationInfo: true,
    ),
    media: _media(scenes.length),
  );
  await camera.startHttp();

  final trace = TraceRelay();
  return AppServices(
    camera: GrCameraEnvironment(
      ble: camera.transport,
      wifi: camera.wifi,
      trace: trace.call,
      httpFactory: camera.httpClient,
      location: devicePhoneLocation(trace: trace.call),
    ),
    trace: trace,
    media: PlatformMediaSaver(),
    background: PlatformBackgroundDownloads(),
    cameraWifi: PlatformCameraWifiService(),
    clientName: 'GR Photo',
    dataDir: data,
    cacheDir: cache,
    debugLogDir: Directory('${data.path}/debug-log'),
    windowPose: pose,
    isDemo: true,
  );
}

/// Walks the app through the screens of the App Store screenshots against
/// a simulated camera whose card and looks look used. At each screen it
/// writes `<name>.request` into [_shotDir] and waits for the host
/// (`tool/store_screenshots/run.sh`) to take the simulator's screenshot and
/// delete the request. The last request, `cmd-lock`, has the host lock the
/// simulator for the Lock Screen with the geotagging Live Activity and end
/// the run: a locked app no longer runs the test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('store screens', (tester) async {
    await _readFolders();
    try {
      await _walk(tester);
    } on Object catch (error, stack) {
      // Why the walk stopped and what was on screen: the host ends the app
      // before the test can report it.
      File('$_shotDir/failure.txt').writeAsStringSync('$error\n$stack');
      await _snap(tester, 'failure', settle: 0);
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<void> _walk(WidgetTester tester) async {
  // An open iPhone Duo held wide, which lays most pages out as two at its
  // fold. The runner says so shortly after the window is up.
  final pose = PlatformWindowPose();
  await _pumpFor(tester, 2);
  final fold = pose.value.fold;
  final twoPages = fold != null && fold.height > fold.width;
  // The grid has three columns on a phone and on the first of two pages,
  // and five on a tablet.
  final wide = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final scenes = _readScenes(perDay: twoPages || wide < 600 ? 9 : 10);
  final models = await AppModels.load(await _services(scenes, pose));
  runApp(GrPhotoApp(models: models));

  for (final key in ['cameras-add', 'pair-add-1234567', 'pair-start']) {
    await _tapKey(tester, key);
  }
  await _tapKey(tester, 'pairing-done-button', seconds: 30);
  await _waitKey(tester, 'camera-card-library', seconds: 30);

  // Live geotagging, which shows the Live Activity for the rest of the
  // run. The host has allowed the location: iOS would ask over the screens
  // otherwise, where no test can answer.
  await _tapKey(tester, 'camera-card-geotag-switch');
  await _snap(tester, 'cameras', settle: 8);

  await _tapKey(tester, 'camera-card-library');
  final pillState = find.byKey(const Key('camera-pill-state'));
  await _pumpUntil(
    tester,
    () =>
        pillState.evaluate().isNotEmpty &&
        tester.widget<Text>(pillState).data ==
            tester.element(pillState).l10n.connectionPillWifi,
    seconds: 60,
    reason: 'the Wi-Fi link',
  );
  await _pumpUntil(
    tester,
    () => find.byType(ShotCell).evaluate().isNotEmpty,
    seconds: 30,
    reason: 'the Library grid',
  );
  await _snap(tester, 'library', settle: 10);

  // The viewer on a photo that fills the window, an upright one unless the
  // window is two pages wide, then with its details. On two pages the
  // photo first shows beside the grid, and Full screen there gives it the
  // whole window.
  final viewed = twoPages
      ? scenes.where((s) => !s.portrait).elementAt(3).number
      : scenes.firstWhere((s) => s.portrait).number;
  await tester.tap(_cell(viewed, scenes.length));
  if (twoPages) {
    await _waitKey(tester, 'shot-pane-scroll');
    await _snap(tester, 'library-shot', settle: 10);
    await _tapKey(tester, 'pane-full-screen');
  }
  await _waitKey(tester, 'viewer-info');
  await _snap(tester, 'viewer', settle: 8);
  await _tapKey(tester, 'viewer-info');
  await _waitKey(tester, 'viewer-save-look', seconds: 15);
  await _snap(tester, 'viewer-details', settle: 5);
  // The map of where the photo was taken, below the details.
  await Scrollable.ensureVisible(
    tester.element(find.byKey(const Key('viewer-map'))),
    alignment: 1,
    duration: const Duration(milliseconds: 300),
  );
  await _snap(tester, 'viewer-map', settle: 10);
  await _back(tester);

  // Saved newest first, so the featured look ends on top.
  final saved = [
    ..._looks.where((l) => l.name != _featured).toList().reversed,
    _looks.firstWhere((l) => l.name == _featured),
  ];
  final grid = find
      .ancestor(
        of: find.byType(ShotCell).first,
        matching: find.byType(Scrollable),
      )
      .first;
  for (final look in saved) {
    final cell = _cell(look.scene, scenes.length);
    // From the top: a cell the grid has scrolled past is not built, and
    // scrolling on would never find it.
    tester.state<ScrollableState>(grid).position.jumpTo(0);
    await _pumpFor(tester, 1);
    await tester.scrollUntilVisible(cell, 200, scrollable: grid);
    await _pumpFor(tester, 1);
    await tester.tap(cell);
    // Beside the grid a shot has its details in place, once it has taken
    // the place of the shot before it.
    if (twoPages) {
      await _pumpFor(tester, 2);
    } else {
      await _tapKey(tester, 'viewer-info');
    }
    await _tapKey(tester, 'viewer-save-look', seconds: 15);
    await _waitKey(tester, 'looks-name-field');
    await tester.enterText(
      find.byKey(const Key('looks-name-field')),
      look.name,
    );
    await _tapKey(tester, 'looks-name-ok');
    await _pumpFor(tester, 4);
    if (!twoPages) await _back(tester);
  }

  await _tapKey(tester, 'camera-tab-looks');
  await _waitKey(tester, 'looks-slot-1', seconds: 30);
  await _snap(tester, 'looks', settle: 5);

  final featured = models.looks.looks.firstWhere((l) => l.name == _featured);
  await _tapKey(tester, 'look-menu:${featured.id}');
  await _snap(tester, 'looks-menu', settle: 2);
  final l10n = tester.element(find.byKey(const Key('looks-slot-1'))).l10n;
  final loadInto = find.text(l10n.looksLoadInto(2)).hitTestable();
  await _pumpUntil(
    tester,
    () => loadInto.evaluate().isNotEmpty,
    seconds: 10,
    reason: 'Load into C2',
  );
  await tester.tap(loadInto);
  await _waitKey(tester, 'looks-load-confirm');
  await _snap(tester, 'looks-load-confirm', settle: 2);
  await _tapKey(tester, 'looks-load-confirm');
  await _snap(tester, 'looks-loaded', settle: 2);
  await _pumpFor(tester, 5);

  await _tapKey(tester, 'look:${featured.id}');
  await _waitKey(tester, 'look-editor', seconds: 30);
  await _snap(tester, 'look-editor', settle: 6);
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('look-groups')),
      matching: find.text(l10n.looksGroupColour),
    ),
  );
  await _snap(tester, 'look-editor-colour');
  await _back(tester);

  await _tapKey(tester, 'camera-tab-shoot');
  await _waitKey(tester, 'shoot-shutter', seconds: 30);
  _inLiveView = true;
  await _tapKey(tester, 'shoot-mode-liveView');
  await _waitKey(tester, 'live-picture', seconds: 60);
  await _pumpFor(tester, 3);
  await _tapKey(tester, 'shoot-shutter');
  await _snap(tester, 'live-view', settle: 6);
  // Out of live view, so the simulator is not busy with its frames when
  // the host locks it.
  await _tapKey(tester, 'shoot-mode-remote');
  await _pumpFor(tester, 3);

  await _snap(tester, 'cmd-lock', settle: 0);
}

Finder _cell(int scene, int scenes) {
  final base = _baseName(scene, scenes);
  return find.byWidgetPredicate(
    (w) => w is ShotCell && w.shot.primary.name.startsWith(base),
  );
}

/// Goes back from the page on top. A window with a vertical bar has the
/// page's own button there instead of a [BackButton]; a shot beside the
/// Library that has the whole window has Exit full screen.
Future<void> _back(WidgetTester tester) async {
  final inBar = [
    for (final key in [
      'viewer-back',
      'viewer-exit-full-screen',
      'look-editor-back',
      'camera-back',
    ])
      find.byKey(Key(key)).hitTestable(),
  ].where((button) => button.evaluate().isNotEmpty);
  await tester.tap(inBar.isEmpty ? find.byType(BackButton).last : inBar.first);
  await _pumpFor(tester, 2);
}

Future<void> _snap(WidgetTester tester, String name, {int settle = 3}) async {
  await _pumpFor(tester, settle);
  final request = File('$_shotDir/$name.request')..writeAsStringSync('');
  await _pumpUntil(
    tester,
    () => !request.existsSync(),
    seconds: 60,
    reason: 'the host to take $name',
  );
}

Future<void> _tapKey(
  WidgetTester tester,
  String key, {
  int seconds = 20,
}) async {
  await _waitKey(tester, key, seconds: seconds);
  await tester.tap(find.byKey(Key(key)).hitTestable());
}

Future<void> _waitKey(WidgetTester tester, String key, {int seconds = 20}) =>
    _pumpUntil(
      tester,
      () => find.byKey(Key(key)).hitTestable().evaluate().isNotEmpty,
      seconds: seconds,
      reason: key,
    );

Future<void> _pumpFor(WidgetTester tester, int seconds) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required int seconds,
  required String reason,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      final keys = tester.allWidgets
          .map((w) => w.key)
          .whereType<ValueKey<String>>()
          .map((k) => k.value)
          .toSet();
      fail('timed out waiting for $reason; keys on screen: $keys');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
