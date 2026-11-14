import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
// Only to check the simulated camera's Operation Mode.
import 'package:gr_protocol/gr_protocol.dart' show BleOperationMode;
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/library/image_orientation.dart';
import 'package:grphoto/src/library/library_screen.dart';
import 'package:grphoto/src/library/shot_cell.dart';
import 'package:grphoto/src/library/viewer.dart';
import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/shoot/live_view_controller.dart';
import 'package:grphoto/src/shoot/shoot_screen.dart';
import 'package:grphoto/src/shoot/shoot_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/pressable.dart';

import '../support/duo_window.dart';
import '../support/test_app.dart';

/// Liveness probes would otherwise run every 5 s against a camera
/// answering in real time.
const _quietLiveness = GrSessionOptions(
  livenessInterval: Duration(hours: 1),
  livenessLossAfter: Duration(hours: 2),
);

/// The whole app with the fake GR IV paired, and Shoot opened from the
/// camera card.
Future<TestApp> _inShoot(
  WidgetTester tester, {
  FakeCameraConfig config = const FakeCameraConfig(bonded: true),
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: config,
      saveCamera: true,
      sessionOptions: _quietLiveness,
    ),
  ))!;
  await app.pumpApp(tester);
  await tapWhenReady(tester, find.byKey(const Key('camera-card-shoot')));
  await pumpUntilFound(tester, find.byKey(const Key('shoot-remote')));
  return app;
}

/// Waits until the shutter takes taps (camera on, in shooting mode).
Future<void> _untilReady(WidgetTester tester) => pumpUntil(
  tester,
  () =>
      tester.widget<Pressable>(find.byKey(const Key('shoot-shutter'))).onTap !=
      null,
  reason: 'shutter enabled',
);

/// Waits until [page] fills the test's window: its route has come in, and
/// a new size of the window has reached it.
Future<void> _untilFills(WidgetTester tester, Finder page) => pumpUntil(
  tester,
  () =>
      tester.getRect(page) ==
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
  reason: 'the page in its window',
);

/// The fold of an Android foldable at [bounds] of the window, flat or
/// [halfOpen].
DisplayFeature _fold(Rect bounds, {bool halfOpen = false}) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.fold,
  state: halfOpen
      ? DisplayFeatureState.postureHalfOpened
      : DisplayFeatureState.postureFlat,
);

String _stat(WidgetTester tester, String key) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
  );
  return texts.last.data!;
}

void main() {
  testWidgets('Shoot turns an off camera on for shooting and shows its '
      'mode, the shots left on each storage and its battery; the shutter '
      'takes a picture', (tester) async {
    final app = await _inShoot(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    await _untilReady(tester);
    expect(app.camera.poweredOn, isTrue);
    expect(app.camera.operationMode, BleOperationMode.capture);
    expect(app.camera.wlanOn, isFalse, reason: 'Remote needs no Wi-Fi');
    await pumpUntil(
      tester,
      () =>
          find.byKey(const Key('shoot-stat-shots-sd1')).evaluate().isNotEmpty &&
          _stat(tester, 'shoot-stat-mode') == 'Av',
      reason: 'shots left and mode',
    );
    expect(_stat(tester, 'shoot-stat-battery'), '82%');
    // The camera does not say which storage it saves to: both show, each
    // under its name.
    List<String?> line(String id) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(Key('shoot-stat-shots-$id')),
          matching: find.byType(Text),
        ),
      ))
        text.data,
    ];
    expect(line('sd1'), ['SD', '1,234']);
    expect(line('in'), ['Internal', '500']);
    expect(
      {
        for (final key in ['mode', 'shots', 'battery'])
          tester.getSize(find.byKey(Key('shoot-stat-$key'))).height,
      },
      hasLength(1),
      reason: 'two lines of shots left make all three readouts taller',
    );

    final before = app.camera.photos.length;
    await tester.tap(find.byKey(const Key('shoot-shutter')));
    await pumpUntil(
      tester,
      () => app.camera.photos.length == before + 1,
      reason: 'picture taken',
    );
    await pumpUntil(
      tester,
      () => _stat(tester, 'shoot-stat-shots-sd1') == '1,233',
      reason: 'shots left on the card after the picture',
    );
    expect(line('in'), ['Internal', '500']);
    await app.dispose();
  });

  testWidgets('the mode readout follows the mode dial', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    await pumpUntil(tester, () => _stat(tester, 'shoot-stat-mode') == 'Av');
    app.camera.setExposureMode(BleExposureMode.m);
    await pumpUntil(
      tester,
      () => _stat(tester, 'shoot-stat-mode') == 'M',
      reason: 'mode dial notification',
    );
    await app.dispose();
  });

  testWidgets('a 10 s self-timer counts down on the shutter, and tapping '
      'it cancels without a picture', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    await tester.tap(find.text('10 s'));
    await pumpUntil(
      tester,
      () => app.models.connection.cameraSession != null,
      reason: 'session',
    );
    final before = app.camera.photos.length;
    await pumpRounds(tester, 5);
    await tester.tap(find.byKey(const Key('shoot-shutter')));
    await pumpUntilFound(tester, find.byKey(const Key('shoot-countdown')));
    expect(find.text('10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shoot-shutter')));
    await pumpUntil(
      tester,
      () => find.byKey(const Key('shoot-countdown')).evaluate().isEmpty,
      reason: 'countdown cancelled',
    );
    await pumpRounds(tester, 20);
    expect(app.camera.photos, hasLength(before));
    await app.dispose();
  });

  testWidgets('a camera switched off while in Shoot offers to turn it on '
      'again', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    app.camera.poweredOn = false;
    await pumpUntilFound(tester, find.byKey(const Key('shoot-turn-on')));
    await tester.tap(find.byKey(const Key('shoot-turn-on')));
    await _untilReady(tester);
    expect(app.camera.poweredOn, isTrue);
    await app.dispose();
  });

  testWidgets('the tab bar switches to the Library, which joins the Wi-Fi, '
      'and back', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    await tester.tap(find.byKey(const Key('camera-tab-library')));
    await pumpUntil(
      tester,
      () => app.models.connection.status == ConnectionStatus.connected,
      reason: 'Wi-Fi joined',
    );
    expect(find.byType(LibraryScreen).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('camera-tab-shoot')));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('shoot-remote')).hitTestable(),
    );
    expect(app.models.connection.status, ConnectionStatus.connected);
    await app.dispose();
  });

  testWidgets('Shoot turns on a camera that dropped its link while off, '
      'which the session let go of', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestApp(
        config: const FakeCameraConfig(bonded: true, poweredOn: false),
        saveCamera: true,
        sessionOptions: _quietLiveness,
      ),
    ))!;
    await app.pumpApp(tester);
    final connection = app.models.connection;
    await pumpUntil(tester, () => connection.bleLinked, reason: 'linked');
    app.camera.dropBluetooth();
    await pumpUntil(tester, () => connection.parked, reason: 'let go of');

    await tapWhenReady(tester, find.byKey(const Key('camera-card-shoot')));
    await pumpUntilFound(tester, find.byKey(const Key('shoot-remote')));
    await _untilReady(tester);
    expect(app.camera.poweredOn, isTrue);
    expect(connection.parked, isFalse);
    await app.dispose();
  });

  testWidgets('leaving the camera pages turns a camera Shoot woke back off', (
    tester,
  ) async {
    final app = await _inShoot(
      tester,
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    await _untilReady(tester);
    await tester.tap(find.byKey(const Key('camera-back')));
    await pumpUntil(tester, () => !app.camera.poweredOn, reason: 'off');
    expect(app.models.connection.status, ConnectionStatus.bluetooth);
    await app.dispose();
  });

  testWidgets('a volume button fires the shutter on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final app = await _inShoot(tester);
    await _untilReady(tester);
    final before = app.camera.photos.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await pumpUntil(
      tester,
      () => app.camera.photos.length == before + 1,
      reason: 'picture taken',
    );
    debugDefaultTargetPlatformOverride = null;
    await app.dispose();
  });

  testWidgets('a phone on its side shows all of Remote at once, with the '
      'shutter at full size beside the readouts, the self-timer and the '
      'drive; upright it sits between them', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
    Future<void> resize(Size window) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      await pumpRounds(tester, 3);
      expect(tester.takeException(), isNull, reason: '$window');
    }

    for (final window in const [Size(915, 412), Size(844, 390)]) {
      await resize(window);
      final scrolling = tester.stateList<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('shoot-remote')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrolling.map((s) => s.position.maxScrollExtent), [
        0,
      ], reason: '$window');
      final shutter = rect('shoot-shutter');
      expect(shutter.height, 168, reason: '$window');
      for (final key in [
        'shoot-mode',
        'shoot-shutter',
        'shoot-stat-mode',
        'shoot-timer',
        'shoot-drive',
      ]) {
        expect(
          find.byKey(Key(key)).hitTestable(),
          findsOne,
          reason: '$key in $window',
        );
      }
      for (final key in ['shoot-stat-battery', 'shoot-timer', 'shoot-drive']) {
        expect(
          rect(key).right,
          lessThan(shutter.left),
          reason: '$key in $window',
        );
      }
    }

    // The narrowest window with the shutter beside the rest: Remote / Live
    // view shrinks in the top bar rather than crowd out the camera pill.
    await resize(const Size(600, 320));
    expect(rect('shoot-timer').right, lessThan(rect('shoot-shutter').left));
    for (final key in [
      'camera-back',
      'camera-pill',
      'shoot-mode',
      'camera-settings',
    ]) {
      expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
    }
    expect(
      rect('camera-pill').right,
      lessThanOrEqualTo(rect('shoot-mode').left),
    );

    // Text at 200 % needs twice that width for the two halves: the same
    // window stacks.
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await resize(const Size(600, 320));
    expect(rect('shoot-timer').top, greaterThan(rect('shoot-shutter').bottom));
    tester.platformDispatcher.clearTextScaleFactorTestValue();

    await resize(const Size(412, 915));
    final shutter = rect('shoot-shutter');
    expect(shutter.height, 168);
    expect(rect('shoot-stat-mode').bottom, lessThan(shutter.top));
    expect(rect('shoot-timer').top, greaterThan(shutter.bottom));
    await app.dispose();
  });

  testWidgets('on its side in a window too short for Remote, it scrolls '
      'behind the top bar, whose buttons stay over it', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    tester.view
      ..physicalSize = const Size(844, 200)
      ..devicePixelRatio = 1;
    final remote = find.byKey(const Key('shoot-remote'));
    // Its route is still sliding in.
    await pumpUntil(
      tester,
      () => tester.getRect(remote) == const Rect.fromLTRB(0, 0, 844, 200),
      reason: 'Shoot in the window on its side',
    );
    const bar = ['camera-back', 'camera-pill', 'shoot-mode', 'camera-settings'];
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
    final shutter = find.byKey(const Key('shoot-shutter'));
    final page = tester
        .state<ScrollableState>(
          find.descendant(of: remote, matching: find.byType(Scrollable)),
        )
        .position;
    final barAtRest = [for (final key in bar) rect(key)];
    // In the bar's row, between two of its buttons, over where the shutter
    // scrolls to.
    final inBar = Offset(
      tester.getCenter(shutter).dx,
      rect('camera-back').center.dy,
    );
    expect(
      inBar.dx,
      inExclusiveRange(rect('shoot-mode').right, rect('camera-settings').left),
    );
    expect(tapReaches(tester, inBar, shutter), isFalse);

    // Far enough to take the top of the shutter past there.
    final toBar = tester.getRect(shutter).top - inBar.dy + 10;
    expect(page.maxScrollExtent, greaterThan(toBar));
    page.jumpTo(toBar);
    await tester.pump();
    expect([for (final key in bar) rect(key)], barAtRest);
    for (final key in bar) {
      expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
    }
    expect(tapReaches(tester, inBar, shutter), isTrue);
    await app.dispose();
  });

  testWidgets('on a closed iPhone Duo, Back and Settings stand in the bar '
      'down its side, under the status, and Remote keeps to the rest of the '
      'window; open and upright, its top bar is beside the status in the '
      'band at the top, and Remote is still the same page', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    final remote = find.byKey(const Key('shoot-remote'));
    final page = tester.state(remote);
    final shutter = tester.state(find.byType(ShutterButton));
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
    Future<void> foldTo(DuoWindow window) async {
      setDuoWindow(tester, app.windowPose, window);
      await _untilFills(tester, remote);
      expect(tester.takeException(), isNull, reason: window.name);
    }

    await foldTo(DuoWindow.closed);
    // The bar's strip, under the status at its top.
    const strip = Rect.fromLTRB(382, 174, 466, 678);
    for (final key in ['camera-back', 'camera-settings']) {
      expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
      expect(strip.expandToInclude(rect(key)), strip, reason: key);
    }
    expect(
      rect('camera-back').bottom,
      lessThanOrEqualTo(rect('camera-settings').top),
    );
    for (final key in [
      'camera-pill',
      'shoot-mode',
      'shoot-stat-mode',
      'shoot-stat-battery',
      'shoot-shutter',
      'shoot-timer',
      'shoot-drive',
    ]) {
      expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
      expect(rect(key).right, lessThanOrEqualTo(strip.left), reason: key);
    }
    // The window has no inset at its top, where its corners are rounded.
    expect(rect('camera-pill').top, greaterThanOrEqualTo(14));

    await foldTo(DuoWindow.upright);
    // The band at the top, as far as the status in its last 144.
    const band = Rect.fromLTRB(0, 0, 525, 82);
    for (final key in ['camera-back', 'camera-pill', 'camera-settings']) {
      expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
      expect(band.expandToInclude(rect(key)), band, reason: key);
    }
    expect(
      rect('camera-back').right,
      lessThanOrEqualTo(rect('camera-pill').left),
    );
    expect(
      rect('camera-pill').right,
      lessThanOrEqualTo(rect('camera-settings').left),
    );
    expect(
      rect('shoot-mode').top,
      greaterThanOrEqualTo(rect('camera-back').bottom),
    );
    expect(tester.state(remote), same(page));
    expect(tester.state(find.byType(ShutterButton)), same(shutter));
    await app.dispose();
  });

  testWidgets("a phone keeps Remote's top bar under its status bar, and on "
      'its side between the insets of its camera cutout', (tester) async {
    final app = await _inShoot(tester);
    await _untilReady(tester);
    final remote = find.byKey(const Key('shoot-remote'));
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));

    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 59, bottom: 34);
    await _untilFills(tester, remote);
    expect(tester.takeException(), isNull);
    // Under the status bar and the bar's own margin of 6.
    expect(rect('camera-back').topLeft, const Offset(18, 65));
    expect(rect('camera-settings').right, 393 - 18);
    expect(rect('shoot-mode').top, greaterThan(rect('camera-back').bottom));

    tester.view
      ..physicalSize = const Size(956, 440)
      ..padding = const FakeViewPadding(left: 62, right: 62, bottom: 20);
    await _untilFills(tester, remote);
    expect(tester.takeException(), isNull);
    expect(rect('camera-back').left, 62 + 18);
    expect(rect('camera-settings').right, 956 - 62 - 18);
    // Remote / Live view is in the bar, the shutter beside the rest.
    expect(
      rect('shoot-mode').center.dy,
      closeTo(rect('camera-back').center.dy, .5),
    );
    expect(rect('shoot-mode').top, greaterThanOrEqualTo(6));
    expect(rect('shoot-timer').right, lessThan(rect('shoot-shutter').left));
    await app.dispose();
  });

  group('live view', () {
    Future<TestApp> inLiveView(
      WidgetTester tester, {
      FakeCameraConfig config = const FakeCameraConfig(bonded: true),
    }) async {
      final app = await _inShoot(tester, config: config);
      await _untilReady(tester);
      await tester.tap(find.byKey(const Key('shoot-mode-liveView')));
      await pumpUntilFound(tester, find.byKey(const Key('live-picture')));
      return app;
    }

    /// The readouts show a new value before the camera answers, so this
    /// asks the camera until it has [value] (or gives up).
    Future<void> expectCameraSetting(
      WidgetTester tester,
      TestApp app,
      String key,
      String value,
    ) async {
      // The camera's own answer, on a client of the test's.
      final http = app.camera.httpClient('', null);
      String? current;
      for (var i = 0; i < 50 && current != value; i++) {
        final props = (await tester.runAsync(http.props))!;
        current = props.setting(key)!.current;
        await tester.pump(const Duration(milliseconds: 20));
      }
      http.close();
      expect(current, value);
    }

    testWidgets('joins the Wi-Fi and shows the picture without the tab bar; '
        'tapping it focuses there', (tester) async {
      final app = await inLiveView(tester);
      expect(app.models.connection.status, ConnectionStatus.connected);
      expect(find.byKey(const Key('camera-tabs')), findsNothing);

      final picture = find.byKey(const Key('live-picture'));
      await tester.tapAt(tester.getTopLeft(picture) + const Offset(20, 20));
      await pumpUntilFound(tester, find.byKey(const Key('live-focus-focused')));
      await app.dispose();
    });

    testWidgets('is in the Dark theme while the chosen theme is light, and '
        'in the chosen theme while that is dark', (tester) async {
      final app = await inLiveView(tester);
      final settings = app.models.settings;
      for (final (chosen, shown) in [
        (AppTheme.system, GrColors.dark),
        (AppTheme.paper, GrColors.dark),
        (AppTheme.cyanotype, GrColors.cyanotype),
        (AppTheme.darkroom, GrColors.darkroom),
      ]) {
        settings.theme = chosen;
        // The app's change of theme is animated.
        await tester.pump();
        await tester.pump(kThemeAnimationDuration);
        expect(
          GrColors.of(tester.element(find.byKey(const Key('live-picture')))),
          shown,
          reason: chosen.name,
        );
      }
      await app.dispose();
    });

    testWidgets('the picture turns upright with the camera, and a tap '
        'focuses at that point of the frame as the camera sends it', (
      tester,
    ) async {
      final app = await inLiveView(tester);
      final level = tester.getRect(find.byKey(const Key('live-turned-0')));
      expect(level.width, greaterThan(level.height));

      app.camera.orientation = GrCameraOrientation.verticalRight;
      await pumpUntilFound(tester, find.byKey(const Key('live-turned-1')));
      final upright = tester.getRect(find.byKey(const Key('live-turned-1')));
      expect(upright.height, greaterThan(upright.width));

      // A quarter turn clockwise puts the frame's left edge at the top.
      await tester.tapAt(
        upright.topLeft + Offset(upright.width * .5, upright.height * .2),
      );
      await pumpUntil(
        tester,
        () => app.camera.focusPoints.isNotEmpty,
        reason: 'focus sent',
      );
      expect(app.camera.focusPoints.single, (20, 50));
      await app.dispose();
    });

    testWidgets('fits a narrow screen with large text and landscape screens, '
        'in Remote and in live view', (tester) async {
      final screens = [
        // A foldable's cover screen, text at 130 %.
        (const Size(904, 2316), 2.625, 1.3),
        (const Size(2316, 904), 2.625, 1.0),
        (const Size(2316, 904), 2.625, 1.3),
        (const Size(2532, 1170), 3.0, 1.0),
      ];
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Future<void> expectFits(Finder visible) async {
        for (final (size, ratio, text) in screens) {
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = ratio;
          tester.platformDispatcher.textScaleFactorTestValue = text;
          await pumpRounds(tester, 3);
          expect(tester.takeException(), isNull, reason: '$size × $text');
          expect(visible.hitTestable(), findsOneWidget, reason: '$size');
        }
      }

      final app = await _inShoot(tester);
      await _untilReady(tester);
      await expectFits(find.byKey(const Key('shoot-mode')));
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.tap(find.byKey(const Key('shoot-mode-liveView')));
      await pumpUntilFound(tester, find.byKey(const Key('live-picture')));
      await expectFits(find.byKey(const Key('live-picture')));
      expect(find.byKey(const Key('shoot-shutter')).hitTestable(), findsOne);
      await app.dispose();
    });

    testWidgets('the picture is as large as the window allows and in the '
        'middle of its width on phones, foldables and tablets, the camera '
        'level or upright, with the shutter, the readouts and × in reach', (
      tester,
    ) async {
      final app = await inLiveView(tester);
      const windows = [
        // A phone.
        Size(412, 915),
        Size(915, 412),
        // A foldable's cover screen.
        Size(344, 882),
        Size(882, 344),
        // A foldable opened.
        Size(707, 823),
        Size(823, 707),
        // A tablet.
        Size(800, 1280),
        Size(1280, 800),
      ];
      for (final orientation in [
        GrCameraOrientation.positive,
        GrCameraOrientation.verticalRight,
      ]) {
        app.camera.orientation = orientation;
        final turned = find.byKey(
          Key('live-turned-${orientation.quarterTurns}'),
        );
        await pumpUntilFound(tester, turned);
        for (final window in windows) {
          tester.view
            ..physicalSize = window
            ..devicePixelRatio = 1;
          await pumpRounds(tester, 3);
          final reason = '$window, ${orientation.name}';
          expect(tester.takeException(), isNull, reason: reason);
          final picture = tester.getRect(turned);
          expect(
            (picture.width - window.width).abs() < .5 ||
                (picture.height - window.height).abs() < .5,
            isTrue,
            reason: '${picture.size} in $reason',
          );
          expect(
            picture.center.dx,
            closeTo(window.width / 2, .5),
            reason: reason,
          );
          for (final key in [
            'shoot-shutter',
            'live-readout-av',
            'live-close',
          ]) {
            expect(
              find.byKey(Key(key)).hitTestable(),
              findsOne,
              reason: '$key in $reason',
            );
          }
        }
      }
      await app.dispose();
    });

    testWidgets('held upright on a phone the picture lies under the '
        'controls: the hint makes way, and a tap between the controls still '
        'focuses', (tester) async {
      final app = await inLiveView(tester);
      expect(find.byKey(const Key('live-hint')), findsOneWidget);

      app.camera.orientation = GrCameraOrientation.verticalRight;
      await pumpUntilFound(tester, find.byKey(const Key('live-turned-1')));
      expect(find.byKey(const Key('live-hint')), findsNothing);
      final picture = tester.getRect(find.byKey(const Key('live-turned-1')));
      final above = tester.getRect(find.byKey(const Key('live-top')));
      expect(above.bottom, greaterThan(picture.top + 8));
      // In the space under the chips.
      await tester.tapAt(Offset(picture.center.dx, above.bottom - 4));
      await pumpUntil(
        tester,
        () => app.camera.focusPoints.isNotEmpty,
        reason: 'focus sent',
      );
      await app.dispose();
    });

    testWidgets('a window as short as a phone on its side has a rail of '
        'controls on each side of the picture, the shutter between the '
        'readouts and the last shot; the dial opens along the bottom of '
        'the picture and moves none of them', (tester) async {
      final app = await inLiveView(tester);
      tester.view
        ..physicalSize = const Size(998, 448)
        ..devicePixelRatio = 1;
      await pumpRounds(tester, 3);
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
      final picture = rect('live-turned-0');
      expect(picture.height, 448);
      for (final key in [
        'live-close',
        'live-exposure',
        'camera-pill',
        'live-chip-drive',
        'live-chip-timer',
      ]) {
        expect(rect(key).right, lessThanOrEqualTo(picture.left), reason: key);
      }
      for (final key in [
        'live-readout-av',
        'live-readout-xv',
        'shoot-shutter',
        'live-last-shot',
      ]) {
        expect(
          rect(key).left,
          greaterThanOrEqualTo(picture.right),
          reason: key,
        );
      }
      final shutter = rect('shoot-shutter');
      expect(shutter.top, greaterThan(rect('live-readout-sv').bottom + 8));
      expect(shutter.bottom, lessThan(rect('live-last-shot').top - 8));
      // Too narrow for a row of each: the readouts go two to a row, the
      // chips one under the other, the camera's state under its name.
      expect(
        rect('live-readout-tv').center.dy,
        closeTo(rect('live-readout-av').center.dy, .5),
      );
      expect(
        rect('live-readout-sv').top,
        greaterThanOrEqualTo(rect('live-readout-av').bottom),
      );
      expect(
        rect('live-chip-timer').top,
        greaterThanOrEqualTo(rect('live-chip-drive').bottom),
      );
      final name = find.descendant(
        of: find.byKey(const Key('camera-pill')),
        matching: find.text('GR IV'),
      );
      expect(
        rect('camera-pill-state').top,
        greaterThanOrEqualTo(tester.getRect(name).bottom),
      );

      final controls = [
        for (final key in [
          'live-readout-av',
          'shoot-shutter',
          'live-chip-drive',
        ])
          rect(key),
      ];
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      expect(find.byKey(const Key('live-dial-av')).hitTestable(), findsOne);
      final dial = rect('live-dial-av');
      expect(dial.center.dx, closeTo(picture.center.dx, .5));
      expect(dial.left, greaterThan(picture.left));
      expect(dial.right, lessThan(picture.right));
      expect(dial.bottom, lessThan(picture.bottom));
      expect([
        for (final key in [
          'live-readout-av',
          'shoot-shutter',
          'live-chip-drive',
        ])
          rect(key),
      ], controls);
      await app.dispose();
    });

    testWidgets('a camera cutout at one side of a phone on its side leaves '
        'the picture in the middle of the screen, the rails as far in from '
        'one side as from the other', (tester) async {
      final app = await inLiveView(tester);
      tester.view
        ..physicalSize = const Size(998, 448)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(left: 50);
      await pumpRounds(tester, 3);
      Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
      expect(rect('live-turned-0').center.dx, closeTo(499, .5));
      expect(rect('live-rail-start').left, 50);
      expect(rect('live-rail-end').right, 948);
      await app.dispose();
    });

    testWidgets("where the rails lie over the picture's edges, a tap "
        'between the controls there still focuses', (tester) async {
      final app = await inLiveView(tester);
      tester.view
        ..physicalSize = const Size(800, 400)
        ..devicePixelRatio = 1;
      await pumpRounds(tester, 3);
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
      final picture = rect('live-turned-0');
      final start = rect('live-rail-start');
      final end = rect('live-rail-end');
      expect(start.right, greaterThan(picture.left + 40));
      expect(end.left, lessThan(picture.right - 40));

      // Under the readouts, above the shutter.
      final readouts = rect('live-readout-sv');
      final shutter = rect('shoot-shutter');
      expect(shutter.top - readouts.bottom, greaterThan(16));
      await tester.tapAt(
        Offset(end.left + 40, (readouts.bottom + shutter.top) / 2),
      );
      await pumpUntilFound(tester, find.byKey(const Key('live-focus-focused')));
      // Under the chips.
      await tester.tapAt(Offset(start.right - 40, start.bottom - 20));
      await pumpUntil(
        tester,
        () => app.camera.focusPoints.length == 2,
        reason: 'second focus sent',
      );
      await pumpUntilFound(tester, find.byKey(const Key('live-focus-focused')));
      expect(app.camera.focusPoints.map((p) => p.$1), [98, 2]);
      await app.dispose();
    });

    testWidgets('in a window too narrow for the dial between the rails, as '
        'half a phone in split screen, it runs across the window under '
        'them, with the shutter in reach', (tester) async {
      final app = await inLiveView(tester);
      tester.view
        ..physicalSize = const Size(360, 330)
        ..devicePixelRatio = 1;
      await pumpRounds(tester, 3);
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      expect(tester.takeException(), isNull);
      final dial = tester.getRect(find.byKey(const Key('live-dial-av')));
      expect(dial.width, greaterThan(300));
      for (final rail in ['live-rail-start', 'live-rail-end']) {
        expect(
          tester.getRect(find.byKey(Key(rail))).bottom,
          lessThanOrEqualTo(dial.top),
          reason: rail,
        );
      }
      for (final key in ['live-dial-av', 'shoot-shutter', 'live-close']) {
        expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
      }
      await app.dispose();
    });

    testWidgets('on its side, what the camera refuses is said above the '
        'open dial', (tester) async {
      final app = await inLiveView(
        tester,
        config: const FakeCameraConfig(bonded: true, remainingPictures: 0),
      );
      tester.view
        ..physicalSize = const Size(998, 448)
        ..devicePixelRatio = 1;
      await pumpRounds(tester, 3);
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      await tester.tap(find.byKey(const Key('shoot-shutter')));
      await pumpUntilFound(tester, find.byKey(const Key('toast-failed')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getRect(find.byKey(const Key('toast'))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('live-dial-av'))).top - 8,
        ),
      );
      await app.dispose();
    });

    testWidgets('on a closed iPhone Duo, × and the exposure mode stand in '
        'the bar down its side, under the status; the picture takes the '
        'width the bar leaves, with the other controls above and below it '
        'as on a phone', (tester) async {
      final app = await inLiveView(tester);
      setDuoWindow(tester, app.windowPose, DuoWindow.closed);
      await pumpUntilFound(tester, find.byKey(const Key('live-exposure')));
      await pumpRounds(tester, 3);
      expect(tester.takeException(), isNull);
      Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
      // The bar's strip, under the status at its top, and the bottom of
      // the window above the system's inset.
      const strip = Rect.fromLTRB(382, 174, 466, 678);
      const bottom = 678 - 34.0;
      for (final key in ['live-close', 'live-exposure']) {
        expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
        expect(strip.expandToInclude(rect(key)), strip, reason: key);
      }
      final picture = rect('live-turned-0');
      expect(picture.left, closeTo(0, .5));
      expect(picture.right, closeTo(strip.left, .5));
      for (final key in ['camera-pill', 'shoot-mode', 'live-chip-drive']) {
        final control = rect(key);
        expect(control.bottom, lessThanOrEqualTo(picture.top), reason: key);
        expect(control.right, lessThanOrEqualTo(strip.left), reason: key);
      }
      // The window has no inset at its top, where its corners are rounded.
      expect(rect('camera-pill').top, greaterThanOrEqualTo(14));
      for (final key in [
        'live-readout-av',
        'live-readout-xv',
        'live-last-shot',
        'shoot-shutter',
      ]) {
        final control = rect(key);
        expect(control.top, greaterThanOrEqualTo(picture.bottom), reason: key);
        expect(control.right, lessThanOrEqualTo(strip.left), reason: key);
        expect(control.bottom, lessThanOrEqualTo(bottom), reason: key);
      }
      expect(
        rect('shoot-shutter').top,
        greaterThanOrEqualTo(rect('live-readout-av').bottom),
      );
      expect(find.byKey(const Key('shoot-shutter')).hitTestable(), findsOne);
      await app.dispose();
    });

    testWidgets('on an open iPhone Duo held wide, the picture is as large '
        'as fits between a row of controls above it and one below it, with '
        'nothing over it, and the shutter and the last shot stand in the '
        'bar under × and the exposure mode; half-open like a book, only '
        'the picture crosses the fold', (tester) async {
      final app = await inLiveView(tester);
      setDuoWindow(tester, app.windowPose, DuoWindow.open);
      await pumpUntilFound(tester, find.byKey(const Key('live-exposure')));
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      await pumpRounds(tester, 3);
      expect(tester.takeException(), isNull);
      Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
      // The bar's strip, under the status at its top, and the bottom of
      // the window above the system's inset.
      const strip = Rect.fromLTRB(867, 124, 951, 669);
      const bottom = 669 - 34.0;
      const above = ['camera-pill', 'shoot-mode'];
      const readouts = [
        'live-readout-av',
        'live-readout-tv',
        'live-readout-sv',
        'live-readout-xv',
      ];
      const inBar = [
        'live-close',
        'live-exposure',
        'shoot-shutter',
        'live-last-shot',
      ];
      // The chips scroll in what their row leaves them.
      final chips = find
          .ancestor(
            of: find.byKey(const Key('live-chip-drive')),
            matching: find.byType(SingleChildScrollView),
          )
          .first;

      final picture = rect('live-turned-0');
      expect(picture.left, greaterThanOrEqualTo(0));
      expect(picture.right, lessThanOrEqualTo(strip.left));
      for (final (i, key) in inBar.indexed) {
        final control = rect(key);
        expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
        expect(strip.expandToInclude(control), strip, reason: key);
        expect(control.bottom, lessThanOrEqualTo(bottom), reason: key);
        if (i > 0) {
          expect(
            control.top,
            greaterThanOrEqualTo(rect(inBar[i - 1]).bottom),
            reason: key,
          );
        }
      }
      // Halfway down the bar, with a margin on either side of it.
      final shutter = rect('shoot-shutter');
      expect(shutter.center.dy, closeTo(strip.bottom / 2, .5));
      expect(shutter.left - strip.left, greaterThanOrEqualTo(8));
      expect(strip.right - shutter.right, greaterThanOrEqualTo(8));
      for (final key in above) {
        final control = rect(key);
        expect(control.bottom, lessThanOrEqualTo(picture.top), reason: key);
        expect(control.right, lessThanOrEqualTo(strip.left), reason: key);
      }
      for (final control in [
        for (final key in readouts) rect(key),
        tester.getRect(chips),
      ]) {
        expect(control.top, greaterThanOrEqualTo(picture.bottom));
        expect(control.right, lessThanOrEqualTo(strip.left));
        expect(control.bottom, lessThanOrEqualTo(bottom));
      }
      // The rows leave the picture all the room between them.
      expect(picture.top - rect('shoot-mode').bottom, lessThan(24));
      expect(rect('live-readout-av').top - picture.bottom, lessThan(24));

      // The dial opens in the row below the picture, in the chips' place:
      // it keeps off the picture too, and moves nothing.
      final readoutsAtRest = [for (final key in readouts) rect(key)];
      final dial = find.byKey(const Key('live-dial-av'));
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntilFound(tester, dial);
      // Risen into its place.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(dial.hitTestable(), findsOne);
      final open = tester.getRect(dial);
      expect(open.top, greaterThanOrEqualTo(picture.bottom));
      expect(open.left, greaterThanOrEqualTo(rect('live-readout-xv').right));
      expect(open.right, lessThanOrEqualTo(strip.left));
      expect(open.bottom, lessThanOrEqualTo(bottom));
      expect(rect('live-turned-0'), picture);
      expect([for (final key in readouts) rect(key)], readoutsAtRest);

      setDuoWindow(tester, app.windowPose, DuoWindow.book);
      await pumpRounds(tester, 3);
      expect(tester.takeException(), isNull);
      // The band the display folds along.
      const foldLeft = 455.5;
      const foldRight = 495.5;
      expect(rect('live-turned-0'), picture);
      expect(picture.left, lessThan(foldLeft));
      expect(picture.right, greaterThan(foldRight));
      for (final key in ['camera-pill', ...readouts]) {
        expect(rect(key).right, lessThanOrEqualTo(foldLeft), reason: key);
      }
      expect(rect('shoot-mode').left, greaterThanOrEqualTo(foldRight));
      expect(tester.getRect(dial).left, greaterThanOrEqualTo(foldRight));
      expect(tester.getRect(dial).right, lessThanOrEqualTo(strip.left));
      // Closed again, the chips are back in its place.
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntil(
        tester,
        () => dial.evaluate().isEmpty,
        reason: 'the dial closed',
      );
      expect(tester.getRect(chips).left, greaterThanOrEqualTo(foldRight));
      expect(rect('live-chip-drive').left, greaterThanOrEqualTo(foldRight));

      // What shows in the picture's place until frames come keeps to one
      // side of the fold.
      app.camera.poweredOn = false;
      final turnOn = find.byKey(const Key('shoot-turn-on'));
      await pumpUntilFound(tester, turnOn);
      expect(tester.takeException(), isNull);
      expect(turnOn.hitTestable(), findsOne);
      expect(tester.getRect(turnOn).right, lessThanOrEqualTo(foldLeft));
      await tester.tap(turnOn);
      await pumpUntilFound(tester, find.byKey(const Key('live-picture')));
      await app.dispose();
    });

    testWidgets('on an iPhone Duo half-open on a table, the picture fills '
        'the half that stands up, under the camera beside the status, and '
        'every control is in the half that lies flat, the open dial too; '
        'flat again, the controls are above and below the picture, × and '
        'the camera in the band beside the status', (tester) async {
      final app = await inLiveView(tester);
      setDuoWindow(tester, app.windowPose, DuoWindow.tabletop);
      await pumpUntilFound(tester, find.byKey(const Key('live-exposure')));
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      await pumpRounds(tester, 3);
      expect(tester.takeException(), isNull);
      Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
      // The band the display folds along, the band at the top as far as
      // the status in its last 144, and the bottom of the window above the
      // system's inset.
      const foldTop = 455.5;
      const foldBottom = 495.5;
      const band = Rect.fromLTRB(0, 0, 525, 82);
      const bottom = 951 - 34.0;
      const controls = [
        'shoot-mode',
        'live-close',
        'live-exposure',
        'live-chip-drive',
        'live-readout-av',
        'live-readout-xv',
        'live-last-shot',
        'shoot-shutter',
        'live-hint',
      ];
      List<Rect> placed() => [for (final key in controls) rect(key)];

      final picture = rect('live-turned-0');
      expect(picture.top, closeTo(band.bottom, .5));
      expect(picture.bottom, closeTo(foldTop, .5));
      expect(
        picture.bottom,
        lessThanOrEqualTo(foldTop + precisionErrorTolerance),
      );
      expect(band.expandToInclude(rect('camera-pill')), band);
      for (final key in controls) {
        final control = rect(key);
        expect(control.top, greaterThanOrEqualTo(foldBottom), reason: key);
        expect(control.bottom, lessThanOrEqualTo(bottom), reason: key);
      }
      for (final key in ['live-close', 'live-readout-av', 'shoot-shutter']) {
        expect(find.byKey(Key(key)).hitTestable(), findsOne, reason: key);
      }

      final atRest = placed();
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      // Risen into its place.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('live-dial-av')).hitTestable(), findsOne);
      final dial = rect('live-dial-av');
      expect(dial.top, greaterThanOrEqualTo(foldBottom));
      expect(dial.bottom, lessThanOrEqualTo(rect('live-readout-av').top));
      expect(placed(), atRest);
      expect(rect('live-turned-0'), picture);

      setDuoWindow(tester, app.windowPose, DuoWindow.upright);
      await pumpRounds(tester, 3);
      expect(tester.takeException(), isNull);
      final flat = rect('live-turned-0');
      expect(flat.width, closeTo(669, .5));
      expect(band.expandToInclude(rect('live-close')), band);
      expect(band.expandToInclude(rect('camera-pill')), band);
      expect(rect('live-close').bottom, lessThanOrEqualTo(flat.top));
      expect(rect('shoot-shutter').top, greaterThanOrEqualTo(flat.bottom));
      await app.dispose();
    });

    testWidgets('folding, unfolding and turning an iPhone Duo leaves live '
        'view as it is: the stream, the open dial and the picture on the '
        'screen', (tester) async {
      final app = await inLiveView(tester);
      setDuoWindow(tester, app.windowPose, DuoWindow.closed);
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      await pumpRounds(tester, 3);
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      final page = tester.state(find.byKey(const Key('shoot-live')));
      final shown = find.descendant(
        of: find.byKey(const Key('live-picture')),
        matching: find.byType(Image),
      );
      final image = tester.state(shown);
      for (final window in [
        DuoWindow.open,
        DuoWindow.tabletop,
        DuoWindow.upright,
        DuoWindow.book,
        DuoWindow.closed,
      ]) {
        setDuoWindow(tester, app.windowPose, window);
        await pumpRounds(tester, 3);
        final reason = window.name;
        expect(tester.takeException(), isNull, reason: reason);
        expect(
          tester.state(find.byKey(const Key('shoot-live'))),
          same(page),
          reason: reason,
        );
        expect(tester.state(shown), same(image), reason: reason);
        expect(
          find.byKey(const Key('live-dial-av')).hitTestable(),
          findsOne,
          reason: reason,
        );
        expect(app.camera.liveViewStreams, 1, reason: reason);
      }
      await app.dispose();
    });

    testWidgets('Remote / Live view stays where it is when it switches '
        'between them: on a phone, a foldable closed and open, a tablet, '
        'and an iPhone Duo closed, open, half-open like a book and upright', (
      tester,
    ) async {
      final app = await _inShoot(tester);
      await _untilReady(tester);
      final modeSwitch = find.byKey(const Key('shoot-mode'));
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> expectStill(String window) async {
        await settle();
        expect(tester.takeException(), isNull, reason: window);
        final inRemote = tester.getRect(modeSwitch);
        await tester.tap(find.byKey(const Key('shoot-mode-liveView')));
        await pumpUntilFound(tester, find.byKey(const Key('live-picture')));
        await settle();
        expect(tester.takeException(), isNull, reason: window);
        expect(tester.getRect(modeSwitch), inRemote, reason: window);
        await tester.tap(find.byKey(const Key('shoot-mode-remote')));
        await pumpUntilFound(tester, find.byKey(const Key('shoot-remote')));
      }

      for (final window in [
        DuoWindow.closed,
        DuoWindow.open,
        DuoWindow.book,
        DuoWindow.upright,
      ]) {
        setDuoWindow(tester, app.windowPose, window);
        await expectStill(window.name);
      }

      app.windowPose.value = WindowPose.none;
      for (final (window, fold) in [
        // A phone.
        (const Size(393, 852), null),
        // A foldable's cover screen.
        (const Size(344, 882), null),
        // A foldable open, held upright and turned, its fold flat and
        // half-open like a book.
        (const Size(707, 823), _fold(const Rect.fromLTWH(0, 411.5, 707, 0))),
        (
          const Size(823, 707),
          _fold(const Rect.fromLTWH(411.5, 0, 0, 707), halfOpen: true),
        ),
        // A tablet.
        (const Size(800, 1280), null),
      ]) {
        const insets = FakeViewPadding(top: 24, bottom: 24);
        tester.view
          ..physicalSize = window
          ..devicePixelRatio = 1
          ..padding = insets
          ..viewPadding = insets
          ..displayFeatures = [?fold];
        await expectStill('$window');
      }
      await app.dispose();
    });

    testWidgets('a phone on its side and an Android foldable keep their '
        'layouts, whether its fold is flat or half-open like a book; '
        'half-open on a table, the picture is above its fold and every '
        'control below it', (tester) async {
      final app = await inLiveView(tester);
      await pumpUntilFound(tester, find.byKey(const Key('live-exposure')));
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
      const controls = [
        'shoot-mode',
        'live-close',
        'live-exposure',
        'live-chip-drive',
        'live-readout-av',
        'live-readout-xv',
        'live-last-shot',
        'shoot-shutter',
      ];
      List<Rect> placed() => [
        for (final key in ['live-turned-0', 'camera-pill', ...controls])
          rect(key),
      ];
      Future<void> show(Size window, {DisplayFeature? fold}) async {
        tester.view
          ..physicalSize = window
          ..devicePixelRatio = 1
          ..displayFeatures = [?fold];
        await pumpRounds(tester, 3);
        expect(tester.takeException(), isNull, reason: '$window, $fold');
      }

      // A phone on its side: a rail on each side of the picture.
      await show(const Size(956, 440));
      final onItsSide = rect('live-turned-0');
      expect(onItsSide.height, 440);
      expect(onItsSide.center.dx, closeTo(956 / 2, .5));
      for (final key in ['live-close', 'live-exposure', 'camera-pill']) {
        expect(rect(key).right, lessThanOrEqualTo(onItsSide.left), reason: key);
      }
      for (final key in [
        'live-readout-av',
        'shoot-shutter',
        'live-last-shot',
      ]) {
        expect(
          rect(key).left,
          greaterThanOrEqualTo(onItsSide.right),
          reason: key,
        );
      }

      // A foldable open, its fold standing upright.
      await show(const Size(823, 707));
      final open = placed();
      for (final halfOpen in [false, true]) {
        await show(
          const Size(823, 707),
          fold: _fold(
            const Rect.fromLTWH(411.5, 0, 0, 707),
            halfOpen: halfOpen,
          ),
        );
        expect(placed(), open, reason: 'half-open: $halfOpen');
      }

      // Turned, its fold lies across the window.
      const foldAcross = Rect.fromLTWH(0, 411.5, 707, 0);
      await show(const Size(707, 823));
      final turned = placed();
      await show(const Size(707, 823), fold: _fold(foldAcross));
      expect(placed(), turned);

      await show(const Size(707, 823), fold: _fold(foldAcross, halfOpen: true));
      final picture = rect('live-turned-0');
      expect(
        picture.bottom,
        lessThanOrEqualTo(foldAcross.top + precisionErrorTolerance),
      );
      expect(picture.top, greaterThanOrEqualTo(rect('camera-pill').bottom));
      for (final key in [...controls, 'live-hint']) {
        expect(
          rect(key).top,
          greaterThanOrEqualTo(foldAcross.bottom),
          reason: key,
        );
      }

      await show(const Size(707, 823));
      expect(placed(), turned);
      await app.dispose();
    });

    testWidgets('quick taps run one focus at a time: the first, then the '
        'newest tap once it ends', (tester) async {
      final app = await inLiveView(tester);
      final picture = find.byKey(const Key('live-picture'));
      final box = tester.getRect(picture);
      for (final x in [.2, .4, .6, .8]) {
        await tester.tapAt(box.topLeft + Offset(box.width * x, box.height / 2));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await pumpUntilFound(tester, find.byKey(const Key('live-focus-focused')));
      await pumpUntil(
        tester,
        () => app.camera.focusPoints.length == 2,
        reason: 'the newest tap sent',
      );
      await pumpUntilFound(tester, find.byKey(const Key('live-focus-focused')));
      expect(app.camera.focusPoints.map((p) => p.$1), [20, 80]);
      await app.dispose();
    });

    testWidgets('a lens result that comes before the focus answer counts, '
        'and the next tap goes at once', (tester) async {
      final app = await inLiveView(
        tester,
        config: const FakeCameraConfig(
          bonded: true,
          lensBeforeFocusAnswer: true,
        ),
      );
      final box = tester.getRect(find.byKey(const Key('live-picture')));
      await tester.tapAt(box.topLeft + Offset(box.width * .2, box.height / 2));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tapAt(box.topLeft + Offset(box.width * .8, box.height / 2));
      final watch = Stopwatch()..start();
      await pumpUntil(
        tester,
        () => app.camera.focusPoints.length == 2,
        reason: 'the second tap sent',
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      await pumpUntilFound(tester, find.byKey(const Key('live-focus-focused')));
      await app.dispose();
    });

    testWidgets('changes the aperture on the dial', (tester) async {
      final app = await inLiveView(tester);
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      await tester.tap(find.byKey(const Key('live-readout-av')));
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      await tapWhenReady(tester, find.byKey(const Key('live-dial-option-4.0')));
      await pumpUntil(
        tester,
        () => find.text('f/4.0').evaluate().isNotEmpty,
        reason: 'new aperture',
      );
      await expectCameraSetting(tester, app, 'av', '4.0');
      await app.dispose();
    });

    testWidgets('opening the dial leaves the readouts and the picture where '
        'they are', (tester) async {
      final app = await inLiveView(tester);
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'aperture readout',
      );
      final readout = find.byKey(const Key('live-readout-av'));
      final picture = find.byKey(const Key('live-turned-0'));
      final readoutBefore = tester.getTopLeft(readout);
      final pictureBefore = tester.getRect(picture);
      await tester.tap(readout);
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      expect(tester.getTopLeft(readout), readoutBefore);
      expect(tester.getRect(picture), pictureBefore);
      await app.dispose();
    });

    testWidgets('a value the camera refuses comes back as its error code', (
      tester,
    ) async {
      final app = await inLiveView(tester);
      final live = tester
          .widget<ShootScreen>(find.byType(ShootScreen))
          .model
          .liveView;
      await pumpUntil(
        tester,
        () => live.props?.setting('av') != null,
        reason: 'aperture list',
      );
      final refusal = await tester.runAsync(() => live.setSetting('av', '99'));
      expect(
        refusal,
        isA<SettingRefusalByCamera>().having((r) => r.code, 'code', '400'),
      );
      await app.dispose();
    });

    testWidgets('turning the mode dial locks and frees the shutter speed '
        'without a Wi-Fi notice from the camera', (tester) async {
      final app = await inLiveView(
        tester,
        // Slow enough that a settings read cannot be in by the frame that
        // shows the new mode.
        config: const FakeCameraConfig(
          bonded: true,
          announcesDialChanges: false,
          httpLatency: Duration(milliseconds: 300),
        ),
      );
      bool editable(String key) =>
          tester
              .widget<Pressable>(find.byKey(Key('live-readout-$key')))
              .onTap !=
          null;
      await pumpUntil(
        tester,
        () => find.text('f/2.8').evaluate().isNotEmpty,
        reason: 'readouts',
      );
      expect(editable('tv'), isFalse, reason: 'Av sets the shutter speed');
      expect(editable('av'), isTrue);

      app.camera.setExposureMode(BleExposureMode.m);
      await pumpUntil(tester, () => editable('tv'), reason: 'M frees it');
      await tester.tap(find.byKey(const Key('live-readout-tv')));
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-tv')));

      app.camera.setExposureMode(BleExposureMode.av);
      await pumpUntil(
        tester,
        () => find
            .descendant(
              of: find.byKey(const Key('live-exposure')),
              matching: find.text('Av'),
            )
            .evaluate()
            .isNotEmpty,
        reason: 'mode label',
      );
      // Locked with the label, before the camera has said what Av allows.
      expect(editable('tv'), isFalse);
      expect(editable('av'), isFalse);
      expect(find.byKey(const Key('live-dial-tv')), findsNothing);
      await pumpUntil(tester, () => editable('av'), reason: 'Av frees it');
      expect(editable('tv'), isFalse);
      await app.dispose();
    });

    testWidgets('a locked readout follows the value the camera picks', (
      tester,
    ) async {
      final app = await inLiveView(tester);
      Finder tv(String text) => find.descendant(
        of: find.byKey(const Key('live-readout-tv')),
        matching: find.text(text),
      );
      await pumpUntilFound(tester, tv('1/250'));
      // In Av the camera sets the shutter speed and announces nothing.
      app.camera.cameraSets('tv', '1.1000');
      await pumpUntilFound(tester, tv('1/1000'));
      await app.dispose();
    });

    testWidgets('Image Control can be changed again after a change', (
      tester,
    ) async {
      final app = await inLiveView(tester);
      for (final effect in ['efc_monochrome', 'col_vivid']) {
        await tapWhenReady(tester, find.byKey(const Key('live-chip-effect')));
        await tapWhenReady(
          tester,
          find.byKey(Key('shoot-option-effect-$effect')),
        );
        await pumpUntil(
          tester,
          () => find
              .byKey(const Key('shoot-setting-sheet-effect'))
              .evaluate()
              .isEmpty,
          reason: 'picker closed',
        );
        await expectCameraSetting(tester, app, 'effect', effect);
      }
      await app.dispose();
    });

    testWidgets('the Image Control list names every one the camera offers', (
      tester,
    ) async {
      final app = await inLiveView(tester);
      final http = app.camera.httpClient('', null);
      final props = (await tester.runAsync(http.props))!;
      http.close();
      await tapWhenReady(tester, find.byKey(const Key('live-chip-effect')));
      final list = find.byKey(const Key('shoot-setting-sheet-effect'));
      // The sheet slides in from below; scrolling needs it on screen.
      await pumpUntilFound(tester, list.hitTestable());
      for (final effect in props.setting('effect')!.options!) {
        final option = find.byKey(Key('shoot-option-effect-$effect'));
        await tester.scrollUntilVisible(
          option,
          100,
          scrollable: find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          find.descendant(of: option, matching: find.text(effect)),
          findsNothing,
          reason: '$effect is shown as the camera sends it',
        );
      }
      await app.dispose();
    });

    testWidgets('stops while the app is hidden, as when the phone locks, and '
        'starts again on return with the Wi-Fi it kept', (tester) async {
      final app = await inLiveView(tester);
      final camera = app.camera;
      await pumpUntil(
        tester,
        () => camera.liveViewStreams == 1,
        reason: 'streaming',
      );

      // A system sheet over the app does not hide it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await pumpRounds(tester, 10);
      expect(camera.liveViewStreams, 1);

      [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpUntil(
        tester,
        () => camera.liveViewStreams == 0,
        reason: 'stopped',
      );
      expect(app.models.connection.status, ConnectionStatus.connected);
      expect(camera.wlanOn, isTrue);

      [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpUntil(
        tester,
        () => camera.liveViewStreams == 1,
        reason: 'streaming again',
      );
      await app.dispose();
    });

    testWidgets('× goes back to Remote and keeps the Wi-Fi up, with the '
        'camera still on', (tester) async {
      final app = await inLiveView(tester);
      await tester.tap(find.byKey(const Key('live-close')));
      await pumpUntilFound(tester, find.byKey(const Key('shoot-remote')));
      await pumpRounds(tester, 30);
      expect(app.models.connection.status, ConnectionStatus.connected);
      expect(app.camera.wlanOn, isTrue);
      expect(app.camera.poweredOn, isTrue);
      expect(find.byKey(const Key('camera-tabs')), findsOneWidget);

      // Live view again starts on the Wi-Fi that stayed.
      await tester.tap(find.byKey(const Key('shoot-mode-liveView')));
      await pumpUntilFound(tester, find.byKey(const Key('live-picture')));
      expect(app.models.connection.status, ConnectionStatus.connected);
      await app.dispose();
    });

    final lastShot = find.byKey(const Key('live-last-shot'));
    Finder inLastShot(Finder finder) =>
        find.descendant(of: lastShot, matching: finder);

    /// The files whose pictures the last shot holds, bottom to top.
    List<CameraFile> lastShotFiles(WidgetTester tester) => [
      for (final image in tester.widgetList<CameraImage>(
        inLastShot(find.byType(CameraImage)),
      ))
        image.file,
    ];

    CameraFile fileOf(FakePhoto photo) => CameraFile(photo.storage, photo.path);

    /// Presses the shutter and waits for the last shot to show the
    /// picture taken.
    Future<FakePhoto> shoot(WidgetTester tester, TestApp app) async {
      final before = app.camera.photos.length;
      await _untilReady(tester);
      await tester.tap(find.byKey(const Key('shoot-shutter')));
      await pumpUntil(
        tester,
        () => app.camera.photos.length == before + 1,
        reason: 'picture taken',
      );
      final photo = app.camera.photos.last;
      final picture = find.descendant(
        of: find.byKey(ValueKey(fileOf(photo))),
        matching: find.byType(Image),
      );
      await pumpUntilFound(tester, inLastShot(picture));
      return photo;
    }

    testWidgets('the last shot is the newest picture taken, as the Library '
        'shows it from the start: upright, and one picture for a RAW+JPEG '
        'pair', (tester) async {
      final app = await inLiveView(
        tester,
        config: FakeCameraConfig(
          bonded: true,
          // Held upright; the pictures taken are served as this one.
          photos: [
            FakePhoto(
              '100RICOH',
              'R0000001.JPG',
              DateTime(2026, 11, 5, 8),
              orientation: 6,
            ),
          ],
        ),
      );
      expect(inLastShot(find.byType(CameraImage)), findsNothing);

      final first = await shoot(tester, app);
      final image = tester.widget<CameraImage>(
        inLastShot(find.byType(CameraImage)),
      );
      expect(image.file, fileOf(first));
      // The grid's picture and no other: none follows it in the square.
      expect(image.size, GrImageSize.view);
      expect(image.sharper, isNull);
      expect(
        tester
            .widget<ExifOrientation>(inLastShot(find.byType(ExifOrientation)))
            .orientation,
        6,
      );

      // Its RAW half: still the one picture, which is not loaded again.
      final shown = tester.state(inLastShot(find.byType(CameraImage)));
      app.camera.addPhoto(
        FakePhoto(
          first.dir,
          '${first.baseName}.DNG',
          first.dateTime,
          orientation: 6,
        ),
      );
      await pumpUntil(
        tester,
        () => app.models.connection.cameraSession!.liveView.shots.length == 2,
        reason: 'the RAW half taken',
      );
      await pumpRounds(tester, 5);
      expect(lastShotFiles(tester), [fileOf(first)]);
      expect(tester.state(inLastShot(find.byType(CameraImage))), same(shown));

      // The picture before stays under the next one.
      final second = await shoot(tester, app);
      expect(lastShotFiles(tester), [fileOf(first), fileOf(second)]);
      await app.dispose();
    });

    testWidgets('a tap on the last shot opens the pictures taken since live '
        'view was opened, the newest first, and live view stops under the '
        'viewer; × forgets them', (tester) async {
      final app = await inLiveView(tester);
      final camera = app.camera;
      final listing = app.models.library.model;
      final viewer = find.byType(ShotViewer);
      Finder showing(FakePhoto photo) => find.descendant(
        of: viewer,
        matching: find.descendant(
          of: find.byType(AppBar),
          matching: find.text(photo.file),
        ),
      );
      int pages() => tester
          .widget<PageView>(
            find.descendant(of: viewer, matching: find.byType(PageView)),
          )
          .childrenDelegate
          .estimatedChildCount!;
      bool listed(FakePhoto photo) =>
          listing.shots!.any((s) => s.files.contains(fileOf(photo)));
      await pumpUntil(
        tester,
        () => camera.liveViewStreams == 1,
        reason: 'streaming',
      );

      final first = await shoot(tester, app);
      expect(
        listed(first),
        isFalse,
        reason: 'the picture shows before the listing is read again',
      );
      await tester.tap(lastShot);
      await pumpUntilFound(tester, showing(first));
      await pumpUntil(
        tester,
        () => camera.liveViewStreams == 0,
        reason: 'stopped under the viewer',
      );
      expect(app.models.connection.status, ConnectionStatus.connected);

      // It stays while no listing has it, and once one does.
      await pumpUntil(tester, () => listed(first), reason: 'listed');
      await pumpRounds(tester, 5);
      expect(showing(first), findsOneWidget);
      expect(camera.liveViewStreams, 0, reason: 'still stopped');
      expect(pages(), 1, reason: 'not the pictures taken before live view');

      // The volume buttons are the viewer's there, not the shutter's.
      final taken = camera.photos.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await pumpRounds(tester, 30);
      expect(camera.photos, hasLength(taken));

      await tapWhenReady(
        tester,
        find.descendant(of: viewer, matching: find.byType(BackButton)),
      );
      await pumpUntil(
        tester,
        () => viewer.evaluate().isEmpty,
        reason: 'viewer closed',
      );
      await pumpUntil(
        tester,
        () => camera.liveViewStreams == 1,
        reason: 'streaming again',
      );

      final second = await shoot(tester, app);
      await tester.tap(lastShot);
      await pumpUntilFound(tester, showing(second));
      expect(pages(), 2);
      await tapWhenReady(
        tester,
        find.descendant(of: viewer, matching: find.byType(BackButton)),
      );
      await pumpUntil(
        tester,
        () => viewer.evaluate().isEmpty,
        reason: 'viewer closed',
      );

      await tester.tap(find.byKey(const Key('live-close')));
      await pumpUntilFound(tester, find.byKey(const Key('shoot-remote')));
      await tester.tap(find.byKey(const Key('shoot-mode-liveView')));
      await pumpUntilFound(tester, find.byKey(const Key('live-picture')));
      await pumpRounds(tester, 5);
      expect(inLastShot(find.byType(CameraImage)), findsNothing);
      await app.dispose();
    });

    testWidgets('a picture deleted on the camera while the viewer is over '
        'live view is not the last shot afterwards, nor in the viewer when '
        'it opens again', (tester) async {
      final app = await inLiveView(tester);
      final camera = app.camera;
      final listing = app.models.library.model;
      final viewer = find.byType(ShotViewer);
      Finder showing(FakePhoto photo) => find.descendant(
        of: viewer,
        matching: find.descendant(
          of: find.byType(AppBar),
          matching: find.text(photo.file),
        ),
      );
      int pages() => tester
          .widget<PageView>(
            find.descendant(of: viewer, matching: find.byType(PageView)),
          )
          .childrenDelegate
          .estimatedChildCount!;

      final first = await shoot(tester, app);
      final second = await shoot(tester, app);
      await tester.tap(lastShot);
      await pumpUntilFound(tester, showing(second));
      await pumpUntil(
        tester,
        () => camera.liveViewStreams == 0,
        reason: 'stopped under the viewer',
      );
      await pumpUntil(
        tester,
        () => listing.shots!.any((s) => s.files.contains(fileOf(second))),
        reason: 'listed',
      );

      expect(camera.removePhoto(second.path, storage: second.storage), isTrue);
      await pumpUntilFound(tester, showing(first));
      expect(pages(), 1);
      await tapWhenReady(
        tester,
        find.descendant(of: viewer, matching: find.byType(BackButton)),
      );
      await pumpUntil(
        tester,
        () => viewer.evaluate().isEmpty,
        reason: 'viewer closed',
      );
      expect(lastShotFiles(tester), [fileOf(first)]);

      await tester.tap(lastShot);
      await pumpUntilFound(tester, showing(first));
      await pumpRounds(tester, 5);
      expect(pages(), 1);
      await app.dispose();
    });

    testWidgets('a camera switched off during live view is left off and '
        'offers to turn it on; turned on, the picture comes back', (
      tester,
    ) async {
      final app = await inLiveView(tester);
      app.camera.poweredOn = false;
      await pumpUntilFound(tester, find.byKey(const Key('shoot-turn-on')));
      // Long enough for the off camera to be linked again, where a wake
      // would reach it.
      await pumpRounds(tester, 300);
      expect(app.camera.poweredOn, isFalse);
      expect(app.camera.wlanOn, isFalse);
      expect(find.byKey(const Key('shoot-turn-on')), findsOneWidget);
      expect(find.byKey(const Key('live-picture')), findsNothing);

      await tester.tap(find.byKey(const Key('shoot-turn-on')));
      await pumpUntilFound(tester, find.byKey(const Key('live-picture')));
      expect(app.camera.poweredOn, isTrue);
      expect(app.models.connection.status, ConnectionStatus.connected);
      await app.dispose();
    });
  });
}
