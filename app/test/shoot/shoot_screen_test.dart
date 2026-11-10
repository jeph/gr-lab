import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
// Only to check the simulated camera's Operation Mode.
import 'package:gr_protocol/gr_protocol.dart' show BleOperationMode;
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/library/library_screen.dart';
import 'package:grlab/src/shoot/live_view_controller.dart';
import 'package:grlab/src/shoot/shoot_screen.dart';
import 'package:grlab/src/theme/tokens.dart';

import '../support/test_app.dart';

/// Liveness probes would otherwise run every 500 ms against a camera
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
      tester
          .widget<GestureDetector>(find.byKey(const Key('shoot-shutter')))
          .onTap !=
      null,
  reason: 'shutter enabled',
);

String _stat(WidgetTester tester, String key) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
  );
  return texts.last.data!;
}

void main() {
  testWidgets('Shoot turns an off camera on for shooting and shows its '
      'mode, shots left and battery; the shutter takes a picture', (
    tester,
  ) async {
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
          _stat(tester, 'shoot-stat-shots') == '1,234' &&
          _stat(tester, 'shoot-stat-mode') == 'Av',
      reason: 'shots left and mode',
    );
    expect(_stat(tester, 'shoot-stat-battery'), '82%');

    final before = app.camera.photos.length;
    await tester.tap(find.byKey(const Key('shoot-shutter')));
    await pumpUntil(
      tester,
      () => app.camera.photos.length == before + 1,
      reason: 'picture taken',
    );
    await pumpUntil(
      tester,
      () => _stat(tester, 'shoot-stat-shots') == '1,233',
      reason: 'shots left after the picture',
    );
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

    testWidgets('the picture is as large as the window allows on phones, '
        'foldables and tablets, the camera level or upright, with the '
        'shutter, the readouts and × in reach', (tester) async {
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
          final picture = tester.getSize(turned);
          expect(
            (picture.width - window.width).abs() < .5 ||
                (picture.height - window.height).abs() < .5,
            isTrue,
            reason: '$picture in $reason',
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

    testWidgets('a window as short as a phone on its side has the controls '
        "beside the picture, where the dial opens in the chips' place", (
      tester,
    ) async {
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
      final picture = tester.getRect(find.byKey(const Key('live-turned-0')));
      final panel = tester.getRect(find.byKey(const Key('live-panel')));
      expect(picture.height, 448);
      expect(panel.left, greaterThanOrEqualTo(picture.right));

      final readout = find.byKey(const Key('live-readout-av'));
      final before = tester.getTopLeft(readout);
      expect(find.byKey(const Key('live-chip-drive')), findsOneWidget);
      await tester.tap(readout);
      await pumpUntilFound(tester, find.byKey(const Key('live-dial-av')));
      expect(find.byKey(const Key('live-chip-drive')), findsNothing);
      expect(find.byKey(const Key('live-dial-av')).hitTestable(), findsOne);
      expect(tester.getTopLeft(readout), before);
      await app.dispose();
    });

    testWidgets('where the panel beside the picture lies over its edge, a '
        'tap between the controls there still focuses', (tester) async {
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
      final picture = tester.getRect(find.byKey(const Key('live-turned-0')));
      final panel = tester.getRect(find.byKey(const Key('live-panel')));
      final chips = tester.getRect(find.byKey(const Key('live-chip-drive')));
      final readouts = tester.getRect(find.byKey(const Key('live-readout-av')));
      final gap = Offset(panel.left + 40, (chips.bottom + readouts.top) / 2);
      expect(picture.contains(gap), isTrue);
      expect(readouts.top - chips.bottom, greaterThan(16));

      await tester.tapAt(gap);
      await pumpUntil(
        tester,
        () => app.camera.focusPoints.isNotEmpty,
        reason: 'focus sent',
      );
      expect(app.camera.focusPoints.single.$1, 90);
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
              .widget<GestureDetector>(find.byKey(Key('live-readout-$key')))
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

    testWidgets('× goes back to Remote and leaves the Wi-Fi with the camera '
        'still on', (tester) async {
      final app = await inLiveView(tester);
      await tester.tap(find.byKey(const Key('live-close')));
      await pumpUntilFound(tester, find.byKey(const Key('shoot-remote')));
      await pumpUntil(tester, () => !app.camera.wlanOn, reason: 'WLAN off');
      expect(app.models.connection.status, ConnectionStatus.bluetooth);
      expect(app.camera.poweredOn, isTrue);
      expect(find.byKey(const Key('camera-tabs')), findsOneWidget);
      await app.dispose();
    });
  });
}
