import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'package:grphoto/src/camera/camera_pages.dart';
import 'package:grphoto/src/camera/camera_top_bar.dart';
import 'package:grphoto/src/library/image_orientation.dart';
import 'package:grphoto/src/looks/look_compare.dart';
import 'package:grphoto/src/looks/look_preview.dart';
import 'package:grphoto/src/looks/looks_store.dart';
import 'package:grphoto/src/sample_photos.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';
import 'package:grphoto/src/widgets/skeleton.dart';

import '../support/duo_window.dart';
import '../support/test_app.dart';

const _quietLiveness = GrSessionOptions(
  livenessInterval: Duration(hours: 1),
  livenessLossAfter: Duration(hours: 2),
);

/// The whole app with the fake camera ([model], a GR IV by default, on
/// [firmware]) off, paired unless [saveCamera] is false. [saveModel] false
/// saves it without its model; the camera fails reads of the [unreadable]
/// characteristics.
Future<TestApp> _start(
  WidgetTester tester, {
  String model = 'RICOH GR IV',
  String firmware = '1.20',
  bool saveCamera = true,
  bool saveModel = true,
  Set<String> unreadable = const {},
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = (await tester.runAsync(
    () => createTestApp(
      config: FakeCameraConfig(
        bonded: true,
        poweredOn: false,
        model: model,
        firmware: firmware,
        unreadable: unreadable,
      ),
      saveCamera: saveCamera,
      saveModel: saveModel,
      sessionOptions: _quietLiveness,
    ),
  ))!;
  await app.pumpApp(tester);
  return app;
}

/// [_start], on the camera's Looks tab.
Future<TestApp> _inLooks(
  WidgetTester tester, {
  String model = 'RICOH GR IV',
  String firmware = '1.20',
  bool saveModel = true,
  Set<String> unreadable = const {},
}) async {
  final app = await _start(
    tester,
    model: model,
    firmware: firmware,
    saveModel: saveModel,
    unreadable: unreadable,
  );
  await tapWhenReady(tester, find.byKey(const Key('camera-card-shoot')));
  await tapWhenReady(tester, find.byKey(const Key('camera-tab-looks')));
  await pumpUntilFound(tester, find.byKey(const Key('looks')));
  return app;
}

Finder _inSlot(int number, String text) => find.descendant(
  of: find.byKey(Key('looks-slot-$number')),
  matching: find.text(text),
);

/// The look editor has slid in and shows its photo under the look.
Future<void> _editorOpen(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byType(LookPreview));
  await pumpUntilFound(
    tester,
    find.byKey(const Key('look-save')).hitTestable(),
  );
  await pumpRounds(tester, 30);
}

/// Opens the editor's list of base images.
Future<void> _openBases(WidgetTester tester) async {
  await tapWhenReady(tester, find.byKey(const Key('look-base-name')));
  await pumpUntilFound(tester, find.byKey(const Key('look-base-list')));
}

/// Picks [base] from the editor's list of base images, and waits for the
/// list to close.
Future<void> _pickBase(WidgetTester tester, LookBase base) async {
  await _openBases(tester);
  await tapWhenReady(tester, find.byKey(ValueKey('look-base:${base.name}')));
  await pumpUntil(
    tester,
    () => find.byKey(const Key('look-base-list')).evaluate().isEmpty,
    reason: 'the list of base images closed',
  );
}

/// [text] in the editor's field for the base image.
Finder _inBases(String text) => find.descendant(
  of: find.byKey(const Key('look-bases')),
  matching: find.text(text),
);

/// The fold of a foldable at [bounds] of the window, flat unless
/// [halfOpen].
DisplayFeature _fold(Rect bounds, {bool halfOpen = false}) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.fold,
  state: halfOpen
      ? DisplayFeatureState.postureHalfOpened
      : DisplayFeatureState.postureFlat,
);

/// The small picture of each photo the editor can preview on.
List<Rect> _smallPictures(WidgetTester tester, int count) => [
  for (var i = 0; i < count; i++)
    tester.getRect(find.byKey(ValueKey('look-photo:$i'))),
];

Look _slotLook(TestApp app, int number) =>
    Look.fromBytes(Uint8List.fromList(app.camera.lookSlot(number).data))!;

/// A look saved on the phone as Plain: what C1 holds, moved to Vivid.
Future<SavedLook> _savePlain(WidgetTester tester, TestApp app) async {
  final saved = await tester.runAsync(
    () => app.models.looks.add(
      name: 'Plain',
      data: _slotLook(app, 1).withBase(LookBase.vivid).toBytes(),
    ),
  );
  return saved!;
}

/// Gives the app [window] of an iPhone Duo, as closing, unfolding or
/// turning one does, and lets the app lay itself out in it.
Future<void> _toDuo(WidgetTester tester, TestApp app, DuoWindow window) async {
  setDuoWindow(tester, app.windowPose, window);
  await pumpRounds(tester, 3);
}

/// The vertical bar of an iPhone Duo under the system's status, where the
/// app's buttons stand: closed, and open and held wide.
const _closedBar = Rect.fromLTRB(382, 174, 466, 678);
const _wideBar = Rect.fromLTRB(867, 124, 951, 669);

/// The buttons with [keys] stand in [bar], one under the other in that
/// order, each 36 pt across.
void _expectInBar(WidgetTester tester, Rect bar, List<String> keys) {
  Rect? above;
  for (final key in keys) {
    final button = tester.getRect(find.byKey(Key(key)));
    expect(bar.expandToInclude(button), bar, reason: key);
    expect(button.size, const Size(36, 36), reason: key);
    if (above != null) {
      expect(button.top, greaterThan(above.bottom), reason: key);
    }
    above = button;
  }
}

/// The two pages of [window], an iPhone Duo's held wide: what its insets
/// leave on either side of its fold, which is a line down the middle of
/// its band while the display lies flat.
({Rect first, Rect second}) _pagesOf(DuoWindow window) {
  final band = window.pose.fold!;
  final fold = window.pose.halfOpen
      ? band
      : Rect.fromLTRB(band.center.dx, band.top, band.center.dx, band.bottom);
  final inside = window.insets.deflateRect(Offset.zero & window.size);
  return (
    first: Rect.fromLTRB(inside.left, 0, fold.left, window.size.height),
    second: Rect.fromLTRB(fold.right, 0, inside.right, window.size.height),
  );
}

/// The editor's parameters that are built, in the order it lists them.
Finder _parameters() => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('look-param:'),
    _ => false,
  },
);

void main() {
  testWidgets('Looks turns the camera on and shows what C1-C3 hold', (
    tester,
  ) async {
    final app = await _inLooks(tester);
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    expect(app.camera.poweredOn, isTrue);
    expect(_inSlot(1, 'Positive Film'), findsOneWidget);
    expect(_inSlot(2, 'Daido'), findsOneWidget);
    expect(_inSlot(2, 'Hi-Contrast B&W'), findsOneWidget);
    expect(_inSlot(3, 'Soft Summer'), findsOneWidget);
    await app.dispose();
  });

  testWidgets('C1-C3 are skeletons of their cards, without a spinner, until '
      'the camera has been read', (tester) async {
    final app = await _inLooks(tester);
    final card = find.byKey(const Key('looks-slot-1'));
    Finder inCard(Type type) =>
        find.descendant(of: card, matching: find.byType(type));
    await pumpUntilFound(tester, card);
    expect(inCard(Skeleton), findsWidgets);
    expect(inCard(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    final size = tester.getSize(card);

    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    expect(inCard(Skeleton), findsNothing);
    expect(tester.getSize(card), size);
    await app.dispose();
  });

  testWidgets('a slot edited to a new base and toning loads back into the '
      'camera under its name', (tester) async {
    final app = await _inLooks(tester);
    await tapWhenReady(tester, _inSlot(1, 'Tokyo Night'));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));

    // Positive Film is the 7th of the camera's 14 base images, and Bleach
    // Bypass the one after it.
    expect(_inBases('Positive Film'), findsOneWidget);
    expect(_inBases('7 of 14'), findsOneWidget);
    await tapWhenReady(tester, find.byKey(const Key('look-base-next')));
    expect(_inBases('Bleach Bypass'), findsOneWidget);
    expect(_inBases('8 of 14'), findsOneWidget);
    await tapWhenReady(
      tester,
      find.descendant(
        of: find.byKey(const Key('look-groups')),
        matching: find.text('Colour'),
      ),
    );
    await tapWhenReady(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('look-param:toningBleachBypass')),
        matching: find.text('Warm'),
      ),
    );

    await tapWhenReady(tester, find.byKey(const Key('look-load')));
    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Tokyo Night into C1'));

    final look = _slotLook(app, 1);
    expect(look.base, LookBase.bleachBypass);
    expect(look.valueOf(LookParameter.toningBleachBypass), 3);
    expect(look.valueOf(LookParameter.saturation), 1);
    expect(look.valueOf(LookParameter.grain), isNull);
    expect(app.camera.lookSlot(1).name, 'Tokyo Night');
    expect(app.camera.lookSlot(2).name, 'Daido', reason: 'C2 untouched');
    await app.dispose();
  });

  testWidgets('a look on a base the camera does not offer cannot be loaded '
      'until it is moved to one it does', (tester) async {
    final app = await _inLooks(tester, model: 'RICOH GR IV Monochrome');
    final held = app.camera.lookSlot(1).data;
    await tapWhenReady(tester, _inSlot(1, 'Tokyo Night'));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));

    final load = find.byKey(const Key('look-load'));
    expect(tester.widget<ButtonStyleButton>(load).onPressed, isNull);
    expect(
      find.text(
        "The camera doesn't offer Positive Film, so this look can't be "
        'loaded into it.',
      ),
      findsOneWidget,
    );
    expect(_inBases('Positive Film'), findsOneWidget);
    expect(_inBases('1 of 7'), findsNothing, reason: 'not one of the 7');
    await _openBases(tester);
    expect(
      find.byKey(const ValueKey('look-base:positiveFilm')),
      findsNothing,
      reason: 'the editor offers the monochrome bases only',
    );

    await tapWhenReady(
      tester,
      find.byKey(const ValueKey('look-base:standardMono')),
    );
    await pumpUntil(
      tester,
      () => find.byKey(const Key('look-not-offered')).evaluate().isEmpty,
      reason: 'a base the camera offers',
    );
    expect(find.byKey(const Key('look-not-offered')), findsNothing);
    await tapWhenReady(tester, load);
    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Tokyo Night into C1'));
    expect(_slotLook(app, 1).base, LookBase.standardMono);
    expect(app.camera.lookSlot(1).data, isNot(held));
    await app.dispose();
  });

  testWidgets("a GR III's card and pages offer no Looks, so it is not turned "
      'on for them', (tester) async {
    final app = await _start(tester, model: 'RICOH GR III');
    await pumpUntilFound(tester, find.byKey(const Key('camera-card-shoot')));
    expect(find.byKey(const Key('camera-card-looks')), findsNothing);

    await tapWhenReady(tester, find.byKey(const Key('camera-card-shoot')));
    await pumpUntilFound(tester, find.byKey(const Key('camera-tabs')));
    expect(find.byKey(const Key('camera-tab-shoot')), findsOneWidget);
    expect(find.byKey(const Key('camera-tab-looks')), findsNothing);
    await pumpUntil(
      tester,
      () => app.models.connection.bleLinked,
      reason: 'linked',
    );
    expect(app.camera.poweredOn, isFalse);
    await app.dispose();
  });

  testWidgets('Looks turns on a camera that dropped its link while off, '
      'which the session let go of', (tester) async {
    final app = await _start(tester);
    final connection = app.models.connection;
    await pumpUntil(tester, () => connection.bleLinked, reason: 'linked');
    app.camera.dropBluetooth();
    await pumpUntil(tester, () => connection.parked, reason: 'let go of');

    await tapWhenReady(tester, find.byKey(const Key('camera-card-looks')));
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    expect(app.camera.poweredOn, isTrue);
    expect(connection.parked, isFalse);
    await app.dispose();
  });

  testWidgets('a camera saved without its model shows its slots once it '
      'reports the model', (tester) async {
    final app = await _inLooks(tester, saveModel: false);
    expect(app.models.cameras.current!.body.model, isNull);
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    await app.dispose();
  });

  testWidgets("a link that can't read the model or firmware keeps the saved "
      'ones for the slots', (tester) async {
    final app = await _inLooks(
      tester,
      unreadable: const {'model-name', 'firmware-revision'},
    );
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    await app.dispose();
  });

  testWidgets("a GR IV Monochrome whose model a link can't read still takes "
      'a monochrome look', (tester) async {
    final app = await _inLooks(
      tester,
      model: 'RICOH GR IV Monochrome',
      unreadable: const {'model-name'},
    );
    await tapWhenReady(tester, _inSlot(1, 'Tokyo Night'));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    // Positive Film is not one of this camera's base images: the arrow
    // forward goes to the first of them.
    await tapWhenReady(tester, find.byKey(const Key('look-base-next')));
    expect(_inBases('1 of 7'), findsOneWidget);
    await tapWhenReady(tester, find.byKey(const Key('look-load')));
    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Tokyo Night into C1'));
    expect(_slotLook(app, 1).base, LookBase.standardMono);
    await app.dispose();
  });

  group('on a GR IV Monochrome', () {
    Finder inGroups(String name) => find.descendant(
      of: find.byKey(const Key('look-groups')),
      matching: find.text(name),
    );
    Finder inRow(LookParameter parameter, String text) => find.descendant(
      of: find.byKey(ValueKey('look-param:${parameter.name}')),
      matching: find.text(text),
    );

    /// The editor on the look in C1, moved to [base].
    Future<TestApp> editingOn(WidgetTester tester, LookBase base) async {
      final app = await _inLooks(tester, model: 'RICOH GR IV Monochrome');
      await tapWhenReady(tester, _inSlot(1, 'Tokyo Night'));
      await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
      await _pickBase(tester, base);
      return app;
    }

    Future<void> load(WidgetTester tester) async {
      await tapWhenReady(tester, find.byKey(const Key('look-load')));
      await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
      await pumpUntilFound(tester, find.text('Loaded Tokyo Night into C1'));
    }

    testWidgets('a look moved to Solarized Effect offers the three '
        'Solarization Types and loads with the one picked', (tester) async {
      final app = await editingOn(tester, LookBase.solarization);
      const type = LookParameter.solarizationType;
      await tapWhenReady(tester, inGroups('Effects'));
      // The look's grain comes first, and the type a scroll below it.
      final grain = find.byKey(const ValueKey('look-param:grain'));
      await pumpUntilFound(tester, grain);
      await tester.dragUntilVisible(
        inRow(type, 'Type3'),
        grain,
        const Offset(0, -80),
      );
      await tester.pump();
      expect(inRow(type, 'Type1'), findsNWidgets(2), reason: 'the value too');

      await tapWhenReady(tester, inRow(type, 'Type2'));
      await load(tester);
      expect(_slotLook(app, 1).base, LookBase.solarization);
      expect(_slotLook(app, 1).valueOf(type), 2);
      await app.dispose();
    });

    testWidgets("HDR Tone's toning offers Off and Sepia, without the Black "
        '& White the camera refuses on it', (tester) async {
      final app = await editingOn(tester, LookBase.hdrMono);
      const toning = LookParameter.toningHdr;
      await tapWhenReady(tester, inGroups('Colour'));
      await pumpUntilFound(tester, inRow(toning, 'Sepia'));
      expect(inRow(toning, 'B&W'), findsNothing);

      await tapWhenReady(tester, inRow(toning, 'Sepia'));
      await load(tester);
      expect(_slotLook(app, 1).base, LookBase.hdrMono);
      expect(_slotLook(app, 1).valueOf(toning), 2);
      await app.dispose();
    });
  });

  testWidgets('a GR IV on firmware older than 1.04 asks for an update and '
      'is not turned on for its slots', (tester) async {
    final app = await _inLooks(tester, firmware: '1.03');
    await pumpUntilFound(
      tester,
      find.text(
        'Update this camera to firmware 1.04 or later to load looks into its '
        'Custom slots.',
      ),
    );
    await pumpUntil(
      tester,
      () => app.models.connection.bleLinked,
      reason: 'linked',
    );
    expect(app.camera.poweredOn, isFalse);
    await app.dispose();
  });

  testWidgets('looks saved from a camera stay on the phone once it is '
      "forgotten, on the home dock's Looks", (tester) async {
    final app = await _inLooks(tester);
    final looks = app.models.looks;
    await tapWhenReady(tester, _inSlot(2, 'Daido'));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    await tapWhenReady(tester, find.byKey(const Key('look-save')));
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await pumpUntilFound(tester, find.text('Saved Daido'));
    final street = (await tester.runAsync(
      () => looks.add(
        name: 'Street',
        data: Uint8List.fromList(app.camera.lookSlot(1).data),
        source: 'R0001234.JPG',
        photo: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      ),
    ))!;

    await tester.pageBack();
    await tapWhenReady(tester, find.byKey(const Key('camera-back')));
    await pumpUntil(
      tester,
      () => find.byType(CameraPages, skipOffstage: false).evaluate().isEmpty,
      reason: 'camera pages closed',
    );
    await tapWhenReady(tester, find.byKey(const Key('camera-card-more')));
    // Below the fold: the details are taller than this screen.
    await tapWhenReady(
      tester,
      find.byKey(const Key('camera-forget'), skipOffstage: false),
    );
    await tapWhenReady(tester, find.byKey(const Key('camera-forget-confirm')));
    await pumpUntilFound(tester, find.byKey(const Key('cameras-welcome')));

    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await pumpUntilFound(tester, find.text('From C2'));
    expect(find.text('From R0001234.JPG'), findsOneWidget);
    expect(looks.looks.map((l) => l.name), ['Street', 'Daido']);
    expect(looks.photoOf(street), isNotNull);
    await app.dispose();
  });

  testWidgets("the camera's Looks has Settings in its top bar, which leaves "
      'as the page scrolls down and comes back when it scrolls up; the '
      "phone's Looks keeps Settings beside its title", (tester) async {
    final app = await _inLooks(tester);
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    // Short enough for the page to scroll.
    tester.view.physicalSize = const Size(1170, 900);
    await tester.pump();
    const bar = ['camera-back', 'camera-pill', 'camera-settings'];
    Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
    void expectBar({required bool shown}) {
      for (final key in bar) {
        expect(
          find.byKey(Key(key)).hitTestable(),
          shown ? findsOne : findsNothing,
          reason: key,
        );
      }
    }

    final title = find.descendant(
      of: find.byType(PageTitle),
      matching: find.text('Looks'),
    );
    final page = find.byKey(const Key('looks'));
    final scrolled = tester
        .state<ScrollableState>(
          find.descendant(of: page, matching: find.byType(Scrollable)).first,
        )
        .position;
    Future<void> scroll(double dy) async {
      await tester.drag(page, Offset(0, dy));
      // The bar finishes sliding once the finger is up.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expectBar(shown: true);
    expect(rect('camera-settings').center.dy, rect('camera-back').center.dy);
    expect(
      rect('camera-settings').left,
      greaterThan(rect('camera-pill').right),
    );
    expect(rect('camera-back').bottom, lessThan(tester.getRect(title).top));
    expect(rect('looks-new').center.dy, tester.getRect(title).center.dy);

    await scroll(-250);
    expectBar(shown: false);

    await scroll(60);
    expectBar(shown: true);
    // Only the bar came back: the page is still where it was scrolled to.
    expect(scrolled.pixels, greaterThan(150));
    expect(title.hitTestable(), findsNothing);

    await scroll(-60);
    expectBar(shown: false);

    await scroll(60);
    await tapWhenReady(tester, find.byKey(const Key('camera-back')));
    await pumpUntil(
      tester,
      () => find.byType(CameraPages, skipOffstage: false).evaluate().isEmpty,
      reason: 'camera pages closed',
    );
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await pumpUntilFound(tester, title);
    expect(find.byKey(const Key('camera-back')), findsNothing);
    expect(
      rect('camera-settings').center.dy,
      moreOrLessEquals(tester.getRect(title).center.dy, epsilon: 1),
    );
    expect(rect('camera-settings').left, greaterThan(rect('looks-new').right));
    await app.dispose();
  });

  testWidgets('on a closed iPhone Duo Back, Settings and New look stand in '
      'the vertical bar under the status, the title has no button beside '
      'it, and the page keeps clear of the bar', (tester) async {
    final app = await _inLooks(tester);
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    final saved = await _savePlain(tester, app);
    await _toDuo(tester, app, DuoWindow.closed);
    final row = find.byKey(ValueKey('look:${saved.id}'));
    await pumpUntilFound(tester, row);
    expect(tester.takeException(), isNull);

    const buttons = ['camera-back', 'camera-settings', 'looks-new'];
    _expectInBar(tester, _closedBar, buttons);
    final page = find.byKey(const Key('looks'));
    final title = find.descendant(of: page, matching: find.byType(PageTitle));
    expect(
      find.descendant(of: title, matching: find.byType(RoundIconButton)),
      findsNothing,
    );
    final pill = find.byKey(const Key('camera-pill'));
    // The window has no inset at the top here: the page keeps clear of the
    // display's rounded corner itself.
    expect(tester.getRect(pill).top, greaterThanOrEqualTo(14));
    final slots = [
      for (var n = 1; n <= 3; n++) find.byKey(Key('looks-slot-$n')),
    ];
    // The chips scroll sideways: what shows of them is their row.
    final chips = find
        .ancestor(
          of: find.byKey(const ValueKey('looks-chip:colour')),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final part in [pill, title, ...slots, chips, row]) {
      expect(
        tester.getRect(part).right,
        lessThanOrEqualTo(_closedBar.left),
        reason: part.describeMatch(Plurality.one),
      );
    }
    // As on a phone, the slots are side by side above the saved looks.
    expect(
      tester.getRect(slots[1]).left,
      greaterThan(tester.getRect(slots.first).right),
    );
    expect(
      tester.getRect(row).top,
      greaterThan(tester.getRect(slots.first).bottom),
    );
    await app.dispose();
  });

  testWidgets("on a closed iPhone Duo the phone's Looks has Settings and "
      'New look in the vertical bar; opened and turned upright, where no '
      'such bar is, they are beside the title again, under the band the '
      'status is in, and the page is as it was left', (tester) async {
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    final page = find.byKey(const Key('looks'));
    final title = find.descendant(of: page, matching: find.byType(PageTitle));
    await pumpUntilFound(tester, title);
    await _toDuo(tester, app, DuoWindow.closed);
    expect(tester.takeException(), isNull);

    final besideTitle = find.descendant(
      of: title,
      matching: find.byType(RoundIconButton),
    );
    _expectInBar(tester, _closedBar, ['camera-settings', 'looks-new']);
    expect(besideTitle, findsNothing);
    // The window has no inset at the top here: the page keeps clear of the
    // display's rounded corner itself.
    expect(tester.getRect(title).top, greaterThanOrEqualTo(14));
    expect(tester.getRect(title).right, lessThanOrEqualTo(_closedBar.left));

    final mono = find.byKey(const ValueKey('looks-chip:mono'));
    await tapWhenReady(tester, mono);
    expect(tester.widget<GrChip>(mono).selected, isTrue);
    final state = tester.state(page);

    await _toDuo(tester, app, DuoWindow.upright);
    expect(tester.takeException(), isNull);
    expect(tester.state(page), same(state));
    expect(tester.widget<GrChip>(mono).selected, isTrue);
    expect(besideTitle, findsNWidgets(2));
    expect(
      tester.getRect(title).top,
      greaterThanOrEqualTo(DuoWindow.upright.insets.top),
    );
    await app.dispose();
  });

  for (final window in [DuoWindow.open, DuoWindow.book]) {
    testWidgets('on an iPhone Duo held wide (${window.name}) the camera '
        'has the page before the fold, with its top bar, the title and '
        'its slots as rows, and the saved looks have the page after it; '
        'nothing lies across the fold', (tester) async {
      final app = await _inLooks(tester);
      await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
      final saved = await _savePlain(tester, app);
      await _toDuo(tester, app, window);
      final row = find.byKey(ValueKey('look:${saved.id}'));
      await pumpUntilFound(tester, row);
      expect(tester.takeException(), isNull);

      final pages = _pagesOf(window);
      final page = find.byKey(const Key('looks'));
      final title = find.descendant(of: page, matching: find.byType(PageTitle));
      final slots = [
        for (var n = 1; n <= 3; n++) find.byKey(Key('looks-slot-$n')),
      ];
      final beforeFold = [
        find.byKey(const Key('camera-pill')),
        find.descendant(of: title, matching: find.text('Looks')),
        ...slots,
        for (var n = 1; n <= 3; n++) find.byKey(Key('looks-slot-menu-$n')),
      ];
      final afterFold = [
        // The chips scroll sideways: what shows of them is their row.
        find
            .ancestor(
              of: find.byKey(const ValueKey('looks-chip:all')),
              matching: find.byType(Scrollable),
            )
            .first,
        row,
        find.byKey(Key('look-menu:${saved.id}')),
      ];
      for (final (onPage, parts) in [
        (pages.first, beforeFold),
        (pages.second, afterFold),
      ]) {
        for (final part in parts) {
          expect(
            onPage.expandToInclude(tester.getRect(part)),
            onPage,
            reason: part.describeMatch(Plurality.one),
          );
        }
      }
      // The slots are rows, one under the other, most of the page wide.
      final rows = [for (final slot in slots) tester.getRect(slot)];
      for (final (i, slotRow) in rows.indexed.skip(1)) {
        expect(slotRow.top, greaterThan(rows[i - 1].bottom));
        expect(slotRow.left, rows.first.left);
      }
      expect(rows.first.width, greaterThan(pages.first.width * .7));
      expect(_inSlot(1, 'Positive Film'), findsOneWidget);

      const buttons = ['camera-back', 'camera-settings', 'looks-new'];
      _expectInBar(tester, _wideBar, buttons);
      expect(
        find.descendant(of: title, matching: find.byType(RoundIconButton)),
        findsNothing,
      );
      await app.dispose();
    });
  }

  testWidgets('on an iPhone Duo half-open like a book a saved look held '
      'and dragged across the fold onto a slot is loaded into it, and the '
      'accent colour outlines the slot under it', (tester) async {
    final app = await _inLooks(tester);
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    final saved = await _savePlain(tester, app);
    await _toDuo(tester, app, DuoWindow.book);
    final row = find.byKey(ValueKey('look:${saved.id}'));
    await pumpUntilFound(tester, row);
    final slot = find.byKey(const Key('looks-slot-3'));
    final outline = find.ancestor(
      of: slot,
      matching: find.byType(AnimatedContainer),
    );
    Color outlineColor() {
      final frame = tester.widget<AnimatedContainer>(outline.first);
      return (frame.decoration! as BoxDecoration).border!.top.color;
    }

    final accent = GrColors.of(tester.element(slot)).accent;
    expect(outlineColor(), isNot(accent));

    final drag = await tester.startGesture(tester.getCenter(row));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await drag.moveTo(tester.getCenter(slot));
    await tester.pump();
    expect(outlineColor(), accent);
    await drag.up();
    await tester.pump();
    expect(outlineColor(), isNot(accent));

    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Plain into C3'));
    expect(_slotLook(app, 3).base, LookBase.vivid);
    expect(app.camera.lookSlot(3).name, 'Plain');
    expect(app.camera.lookSlot(1).name, 'Tokyo Night', reason: 'C1 untouched');
    await app.dispose();
  });

  testWidgets("on an iPhone Duo open and held upright the camera's top bar "
      'is in the band at the top, beside the status, and the title and '
      'the page come under it in one column', (tester) async {
    final app = await _inLooks(tester);
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    await _toDuo(tester, app, DuoWindow.upright);
    expect(tester.takeException(), isNull);

    final band = DuoWindow.upright.insets.top;
    final status = DuoWindow.upright.pose.occlusions.single;
    final topBar = [
      for (final key in ['camera-back', 'camera-pill', 'camera-settings'])
        tester.getRect(find.byKey(Key(key))),
    ];
    for (final button in topBar) {
      expect(button.top, greaterThanOrEqualTo(0));
      expect(button.bottom, lessThanOrEqualTo(band));
      expect(button.right, lessThanOrEqualTo(status.left));
    }
    final page = find.byKey(const Key('looks'));
    final title = find.descendant(of: page, matching: find.byType(PageTitle));
    final titleText = find.descendant(of: title, matching: find.text('Looks'));
    expect(
      tester.getRect(titleText).top,
      greaterThanOrEqualTo(topBar.first.bottom),
    );
    // No vertical bar here: New look is beside the title.
    expect(
      find.descendant(of: title, matching: find.byKey(const Key('looks-new'))),
      findsOneWidget,
    );
    // The fold lies across the window: the page stays one column.
    Rect slot(int n) => tester.getRect(find.byKey(Key('looks-slot-$n')));
    expect(slot(2).left, greaterThan(slot(1).right));
    expect(slot(2).top, slot(1).top);
    await app.dispose();
  });

  testWidgets('an Android foldable unfolded with its hinge upright gives '
      "the camera's slots and the saved looks a page each, with the "
      'buttons where a phone has them; with the hinge lying across, and '
      'on a phone held on its side, the page is one column', (tester) async {
    final app = await _inLooks(tester);
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    final saved = await _savePlain(tester, app);
    final row = find.byKey(ValueKey('look:${saved.id}'));
    final page = find.byKey(const Key('looks'));
    final title = find.descendant(of: page, matching: find.byType(PageTitle));
    final newLook = find.descendant(
      of: title,
      matching: find.byKey(const Key('looks-new')),
    );
    Rect slot(int n) => tester.getRect(find.byKey(Key('looks-slot-$n')));
    void expectOneColumn() {
      expect(tester.takeException(), isNull);
      expect(slot(2).left, greaterThan(slot(1).right));
      expect(slot(3).left, greaterThan(slot(2).right));
      expect(slot(2).top, slot(1).top);
      expect(tester.getRect(row).top, greaterThan(slot(1).bottom));
      expect(tester.getRect(row).left, lessThan(slot(1).right));
      expect(find.byKey(const Key('looks-slot-menu-1')), findsNothing);
      expect(newLook, findsOneWidget);
    }

    tester.view
      ..physicalSize = const Size(750, 830)
      ..devicePixelRatio = 1
      ..displayFeatures = [_fold(const Rect.fromLTWH(365, 0, 20, 830))];
    await pumpRounds(tester, 3);
    await pumpUntilFound(tester, row);
    expect(tester.takeException(), isNull);
    final beforeHinge = [
      for (final key in ['camera-back', 'camera-pill', 'camera-settings'])
        tester.getRect(find.byKey(Key(key))),
      tester.getRect(newLook),
      for (var n = 1; n <= 3; n++) slot(n),
    ];
    for (final part in beforeHinge) {
      expect(part.right, lessThanOrEqualTo(365));
    }
    expect(slot(2).top, greaterThan(slot(1).bottom));
    expect(
      tester.getRect(find.byKey(const ValueKey('looks-chip:all'))).left,
      greaterThanOrEqualTo(385),
    );
    expect(tester.getRect(row).left, greaterThanOrEqualTo(385));
    expect(tester.getRect(row).right, lessThanOrEqualTo(750));

    tester.view.displayFeatures = [_fold(const Rect.fromLTWH(0, 405, 750, 20))];
    await pumpRounds(tester, 3);
    expectOneColumn();

    tester.view
      ..physicalSize = const Size(956, 440)
      ..displayFeatures = const [];
    await pumpRounds(tester, 3);
    expectOneColumn();
    await app.dispose();
  });

  testWidgets("the phone's Looks edits a look with no camera: no slots or "
      'loading, and the bases of its own kind', (tester) async {
    final app = await _start(tester, saveCamera: false);
    final looks = app.models.looks;
    final mono = Look.fromBytes(
      Uint8List.fromList(app.camera.lookSlot(2).data),
    )!.withBase(LookBase.solid);
    final saved = (await tester.runAsync(
      () => looks.add(name: 'Solid', data: mono.toBytes()),
    ))!;

    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await pumpUntilFound(tester, find.byKey(ValueKey('look:${saved.id}')));
    expect(find.byKey(const Key('looks-slot-1')), findsNothing);
    expect(find.text('Saved'), findsNothing, reason: 'no slots to tag');

    await tapWhenReady(tester, find.byKey(Key('look-menu:${saved.id}')));
    await pumpUntilFound(tester, find.text('Rename'));
    expect(find.text('Load into C1'), findsNothing);
    await tester.tapAt(Offset.zero);
    await pumpUntil(tester, () => find.text('Rename').evaluate().isEmpty);

    await tapWhenReady(tester, find.byKey(ValueKey('look:${saved.id}')));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    expect(find.byKey(const Key('look-load')), findsNothing);
    expect(find.byKey(const Key('look-not-offered')), findsNothing);
    await _openBases(tester);
    expect(find.byKey(const ValueKey('look-base:vivid')), findsNothing);
    await tapWhenReady(
      tester,
      find.byKey(const ValueKey('look-base:standardMono')),
    );
    await tapWhenReady(tester, find.byKey(const Key('look-save')));
    await pumpUntilFound(tester, find.text('Saved Solid'));
    expect(looks.looks.single.look!.base, LookBase.standardMono);

    await tester.pageBack();
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    await _openBases(tester);
    expect(
      find.byKey(const ValueKey('look-base:standardMono')),
      findsOneWidget,
      reason: 'a new look starts on the bases of the look it copies',
    );
    await app.dispose();
  });

  testWidgets("the phone's Looks makes a new look with no camera and no "
      'saved look to copy', (tester) async {
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    await tapWhenReady(tester, find.byKey(const Key('look-save')));
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await pumpUntilFound(tester, find.text('Saved Standard'));
    final saved = app.models.looks.looks.single;
    expect(saved.look!.base, LookBase.standard);
    expect(saved.data.take(2), [1, 0], reason: "GR WORLD's fallback header");
    await app.dispose();
  });

  testWidgets('the editor previews a look on the photo it was saved from '
      "when that photo's own look can be undone or is not known, and "
      'starts on the first sample photo when it can only be undone roughly '
      'or not at all; any photo can be picked, and a photo with nothing to '
      'offer the look is shown as it was taken', (tester) async {
    final app = await _start(tester, saveCamera: false);
    final looks = app.models.looks;
    final jpeg = File(samplePhotos.first.asset).readAsBytesSync();
    final (plain, grey, older) = (await tester.runAsync(() async {
      final plain = await looks.add(
        name: 'Plain',
        data: Look.onBase(LookBase.standard).toBytes(),
        photo: jpeg,
      );
      final grey = await looks.add(
        name: 'Grey',
        data: Uint8List.fromList(app.camera.lookSlot(2).data),
        photo: jpeg,
      );
      final added = await looks.add(
        name: 'Older',
        data: Uint8List.fromList(app.camera.lookSlot(3).data),
        photo: jpeg,
      );
      // As a look saved before GR Photo kept the photo's own look.
      final older = SavedLook(
        id: added.id,
        name: added.name,
        data: added.data,
        created: added.created,
      );
      await looks.update(older);
      return (plain, grey, older);
    }))!;
    expect(grey.look!.base, LookBase.highContrast);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));

    final note = find.byKey(const Key('look-preview-note'));
    Finder noteSaying(String text) =>
        find.descendant(of: note, matching: find.text(text));
    // The picture under the look, then the one it is compared with when
    // that is the photo under a look too rather than as it is.
    List<LookPreview> previews() =>
        tester.widgetList<LookPreview>(find.byType(LookPreview)).toList();
    LookPreview preview() => previews().first;
    // The photo itself, under the size the preview asks for it in; null
    // while a photo just picked is still loading.
    ImageProvider? previewed() => switch (tester
        .widgetList<LookPreview>(find.byType(LookPreview))
        .firstOrNull
        ?.image) {
      ResizeImage(:final imageProvider) => imageProvider,
      final other => other,
    };
    Future<void> open(SavedLook look) async {
      await tapWhenReady(tester, find.byKey(ValueKey('look:${look.id}')));
      await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
      await pumpUntilFound(tester, find.byType(LookPreview));
    }

    Future<void> close() async {
      await tester.pageBack();
      await pumpUntil(
        tester,
        () => find.byKey(const Key('look-editor')).evaluate().isEmpty,
        reason: 'editor closed',
      );
    }

    final ownPhoto = find.byKey(const ValueKey('look-photo:0'));
    final samplePhoto = find.byKey(const ValueKey('look-photo:1'));

    await open(plain);
    expect(note, findsNothing);
    expect(previewed(), isNot(isA<AssetImage>()));
    // Its own photo is the first of them, and is marked as its own.
    expect(
      tester
          .getRect(ownPhoto)
          .inflate(5)
          .contains(tester.getCenter(find.byKey(const Key('look-photo-own')))),
      isTrue,
    );
    await _pickBase(tester, LookBase.vivid);
    expect(note, findsNothing, reason: 'a Standard photo suits every look');
    expect(preview().look.base, LookBase.vivid);
    expect(previews(), hasLength(1), reason: 'before: the photo as taken');
    expect(
      preview().rerender.source?.settings,
      Look.onBase(LookBase.standard).settings,
    );
    // The sample photo can be picked in its place, and the look's own
    // photo again.
    await tapWhenReady(tester, samplePhoto);
    await pumpUntil(
      tester,
      () => preview().image is ResizeImage && previewed() is AssetImage,
      reason: 'the preview on the sample photo',
    );
    expect(preview().look.base, LookBase.vivid);
    // A sample was developed with a look of its own, so what Vivid is
    // compared with is the sample under Standard, not as it is.
    expect(previews(), hasLength(2));
    expect(
      previews().last.look.settings,
      Look.onBase(LookBase.standard).settings,
    );
    expect(previews().last.rerender, same(preview().rerender));
    expect(note, findsNothing);
    await tapWhenReady(tester, ownPhoto);
    await pumpUntil(
      tester,
      () => previewed() is! AssetImage,
      reason: "the preview on the look's own photo",
    );
    await close();

    // A photo whose own look undoes only roughly: the editor starts on
    // the sample photo and says why.
    const startsOnSample =
        "The look your photo was taken with can't be undone exactly, so the "
        'preview starts on a sample photo. You can still switch to your '
        'photo.';
    final asTaken = find.byKey(const Key('look-compare-as-taken'));
    await open(grey);
    expect(noteSaying(startsOnSample), findsOneWidget);
    expect(previewed(), isA<AssetImage>());
    // The user's own photo can still be picked, with what to know of it.
    await tapWhenReady(tester, ownPhoto);
    await pumpUntilFound(
      tester,
      noteSaying(
        "This photo's own look can't be undone exactly, so the preview is "
        'rougher than usual.',
      ),
    );
    await pumpUntil(
      tester,
      () => previewed() is FileImage,
      reason: "the preview on the look's own photo",
    );
    expect(asTaken, findsNothing);
    // Under a look it has nothing to offer, it is shown as it was taken.
    await _pickBase(tester, LookBase.vivid);
    await pumpUntilFound(
      tester,
      noteSaying(
        "This photo's own look can't be undone for this look, so the photo "
        'is shown as it was taken.',
      ),
    );
    expect(asTaken, findsOneWidget);
    expect(find.byType(LookPreview), findsNothing);
    final shown = tester.widget<Image>(
      find.descendant(of: asTaken, matching: find.byType(Image)),
    );
    expect(switch (shown.image) {
      ResizeImage(:final imageProvider) => imageProvider,
      final other => other,
    }, isNot(isA<AssetImage>()));
    // On the sample the user picked, nothing needs saying.
    await tapWhenReady(tester, samplePhoto);
    await pumpUntilFound(tester, find.byType(LookPreview));
    expect(previewed(), isA<AssetImage>());
    expect(preview().look.base, LookBase.vivid);
    expect(note, findsNothing);
    await close();

    // The same photo under a colour look from the start: the sample too.
    await open(grey);
    await _pickBase(tester, LookBase.vivid);
    await pumpRounds(tester, 3);
    expect(noteSaying(startsOnSample), findsOneWidget);
    expect(previewed(), isA<AssetImage>());
    await close();

    await open(older);
    expect(
      noteSaying(
        "GR Photo doesn't know which look this photo was taken with, so the "
        'preview treats it as Standard.',
      ),
      findsOneWidget,
    );
    expect(previewed(), isNot(isA<AssetImage>()));
    await app.dispose();
  });

  testWidgets('a look with no photo of its own is previewed on the first '
      'sample photo, and on any other sample that is picked, each with the '
      'look it was taken with', (tester) async {
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await pumpUntilFound(tester, find.byType(LookPreview));
    final note = find.byKey(const Key('look-preview-note'));
    // The picture under the look, then the one it is compared with when
    // that is the photo under a look too rather than as it is.
    List<LookPreview> previews() =>
        tester.widgetList<LookPreview>(find.byType(LookPreview)).toList();
    LookPreview preview() => previews().first;
    // Null while a photo just picked is still loading.
    String? previewed() => switch (tester
        .widgetList<LookPreview>(find.byType(LookPreview))
        .firstOrNull
        ?.image) {
      ResizeImage(imageProvider: AssetImage(:final assetName)) => assetName,
      _ => null,
    };
    Future<void> pick(int sample) async {
      await tapWhenReady(tester, find.byKey(ValueKey('look-photo:$sample')));
      await pumpUntil(
        tester,
        () => previewed() == samplePhotos[sample].asset,
        reason: 'the preview on sample ${sample + 1}',
      );
    }

    expect(previewed(), samplePhotos.first.asset);
    expect(preview().rerender.source?.base, samplePhotos.first.base);
    expect(note, findsNothing);
    for (var n = 1; n <= samplePhotos.length; n++) {
      expect(find.byTooltip('Sample photo $n'), findsOneWidget);
    }

    final negative = samplePhotos.indexWhere(
      (p) => p.base == LookBase.negativeFilm,
    );
    await pick(negative);
    expect(preview().rerender.source?.base, LookBase.negativeFilm);
    expect(previews(), hasLength(2), reason: 'before: its look undone');
    expect(previews().last.look.base, LookBase.standard);
    expect(note, findsNothing);

    // The last sample is scrolled to.
    final last = samplePhotos.length - 1;
    await pick(last);
    expect(preview().rerender.source?.base, samplePhotos[last].base);
    expect(previews(), hasLength(2), reason: 'before: its look undone');
    expect(note, findsNothing);
    await app.dispose();
  });

  testWidgets('a look saved from a photo held on its side shows that photo '
      'upright, in the list and in the editor', (tester) async {
    final app = await _start(tester, saveCamera: false);
    final looks = app.models.looks;
    // The first sample is two wide by three tall as stored; orientation 6
    // lays it on its side, so upright it is wider than tall.
    final jpeg = File(samplePhotos.first.asset).readAsBytesSync();
    final (turned, asStored) = (await tester.runAsync(() async {
      final turned = await looks.add(
        name: 'Turned',
        data: Look.onBase(LookBase.standard).toBytes(),
        photo: jpeg,
        photoOrientation: 6,
      );
      final asStored = await looks.add(
        name: 'As stored',
        data: Look.onBase(LookBase.vivid).toBytes(),
        photo: jpeg,
      );
      return (turned, asStored);
    }))!;
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));

    int orientationIn(Finder finder) => tester
        .widget<ExifOrientation>(
          find.descendant(of: finder, matching: find.byType(ExifOrientation)),
        )
        .orientation;
    final turnedRow = find.byKey(ValueKey('look:${turned.id}'));
    final storedRow = find.byKey(ValueKey('look:${asStored.id}'));
    await pumpUntilFound(tester, turnedRow);
    expect(orientationIn(turnedRow), 6);
    expect(orientationIn(storedRow), 1);

    await tapWhenReady(tester, turnedRow);
    await pumpUntilFound(tester, find.byType(LookPreview));
    final picture = find.ancestor(
      of: find.byType(LookPreview),
      matching: find.byType(ExifOrientation),
    );
    expect(tester.widget<ExifOrientation>(picture).orientation, 6);
    expect(tester.getSize(picture).aspectRatio, closeTo(3 / 2, .01));
    expect(orientationIn(find.byKey(const ValueKey('look-photo:0'))), 6);
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find.byKey(const Key('look-editor')).evaluate().isEmpty,
      reason: 'editor closed',
    );

    await tapWhenReady(tester, storedRow);
    await pumpUntilFound(tester, find.byType(LookPreview));
    expect(tester.getSize(picture).aspectRatio, closeTo(2 / 3, .01));
    await app.dispose();
  });

  testWidgets("a camera's slot that holds a saved look shows that look's "
      'photo upright', (tester) async {
    final app = await _inLooks(tester);
    final saved = (await tester.runAsync(
      () => app.models.looks.add(
        name: 'Turned',
        data: Uint8List.fromList(app.camera.lookSlot(2).data),
        photo: File(samplePhotos.first.asset).readAsBytesSync(),
        photoOrientation: 6,
      ),
    ))!;
    final slot = find.byKey(const Key('looks-slot-2'));
    final picture = find.descendant(
      of: slot,
      matching: find.byType(ExifOrientation),
    );
    await pumpUntilFound(tester, picture);
    expect(tester.widget<ExifOrientation>(picture).orientation, 6);
    expect(saved.photoOrientation, 6);
    await app.dispose();
  });

  for (final (name, size) in const [
    ('a phone held upright', Size(390, 844)),
    ('a small phone', Size(320, 568)),
    ('a tablet held upright', Size(820, 1180)),
  ]) {
    testWidgets('on $name the editor puts the preview above the controls, '
        'all of it on screen', (tester) async {
      final app = await _start(tester, saveCamera: false);
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
      await tapWhenReady(tester, find.byKey(const Key('looks-new')));
      await _editorOpen(tester);
      final screen = Offset.zero & size;
      final preview = tester.getRect(find.byType(LookCompare));
      final save = tester.getRect(find.byKey(const Key('look-save')));
      final list = tester.getRect(find.byType(ListView));
      expect(preview.width, closeTo(size.width, .01));
      expect(preview.height, greaterThan(60));
      expect(preview.bottom, lessThanOrEqualTo(list.top));
      // Every photo to preview on is in view under the picture, none
      // smaller than a finger needs, and the picture's two controls lie
      // over its place.
      final strip = tester.getRect(find.byType(PreviewPhotoSwitch));
      expect(strip.top, greaterThanOrEqualTo(preview.bottom));
      expect(strip.bottom, lessThanOrEqualTo(list.top));
      for (final photo in _smallPictures(tester, samplePhotos.length)) {
        expect(screen.expandToInclude(photo), screen);
        expect(photo.width, greaterThanOrEqualTo(40));
      }
      for (final control in [
        find.byType(LookCompareModeSwitch),
        find.byKey(const Key('look-preview-fullscreen')),
      ]) {
        expect(preview.expandToInclude(tester.getRect(control)), preview);
        expect(control.hitTestable(), findsOneWidget);
      }
      expect(
        find.byKey(const Key('look-photo-own')),
        findsNothing,
        reason: 'a new look has no photo of its own',
      );
      expect(list.height, greaterThan(60), reason: 'room for a parameter');
      expect(screen.contains(save.topLeft), isTrue);
      expect(screen.contains(save.bottomRight - const Offset(1, 1)), isTrue);
      for (final mode in LookCompareMode.values) {
        await tapWhenReady(
          tester,
          find.byKey(ValueKey('look-compare:${mode.name}')),
        );
        final picture = tester.getRect(find.byType(LookPreview).first);
        expect(picture.size.aspectRatio, closeTo(2 / 3, .02));
        expect(preview.expandToInclude(picture), preview, reason: mode.name);
      }
      await app.dispose();
    });
  }

  for (final (name, size, photosAtSide) in const [
    ('a small phone', Size(320, 568), false),
    ('half a phone, as in split screen', Size(360, 330), false),
    ('a phone held on its side', Size(844, 390), true),
  ]) {
    testWidgets("on $name the preview's button grows it to the whole screen, "
        'with the choice of photo and of comparison and nothing else, and '
        'a tap on its pictures does not; its button or Back brings the '
        'editor back as it was', (tester) async {
      final modes = <Object?>[];
      final messenger = tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments);
          }
          return null;
        });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final app = await _start(tester, saveCamera: false);
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      final jpeg = File(samplePhotos.first.asset).readAsBytesSync();
      final saved = (await tester.runAsync(
        () => app.models.looks.add(
          name: 'Plain',
          data: Look.onBase(LookBase.standard).toBytes(),
          photo: jpeg,
        ),
      ))!;
      await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
      await tapWhenReady(tester, find.byKey(ValueKey('look:${saved.id}')));
      await _editorOpen(tester);

      final editor = find.byKey(const Key('look-editor'));
      final compare = find.byType(LookCompare);
      final save = find.byKey(const Key('look-save'));
      final button = find.byKey(const Key('look-preview-fullscreen'));
      final list = find.byType(ListView);
      ScrollPosition scroll() => tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      LookCompare shown() => tester.widget<LookCompare>(compare);
      // Lets the preview get to the whole screen or back to its place.
      Future<void> arrive() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
      }

      // Not so far that the preview's button, at its top, is under the app
      // bar where the preview scrolls with the controls.
      await tester.drag(list, const Offset(0, -40));
      await tester.pump();
      final scrolled = scroll().pixels;
      expect(scrolled, greaterThan(0));
      final state = tester.state(compare);
      final inEditor = tester.getRect(compare);
      expect(find.byTooltip('Full screen'), findsOneWidget);
      expect(modes, isEmpty);

      // Where the picture is: half the preview is scrolled away on the
      // shortest screen. A tap there is the comparison's own.
      await tester.tapAt(inEditor.bottomCenter - const Offset(40, 40));
      await tester.pump();
      expect(modes, isEmpty);
      expect(find.byType(AppBar), findsOneWidget);
      expect(tester.getRect(compare), inEditor);

      await tester.tap(button);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(modes, ['SystemUiMode.immersiveSticky']);
      expect(
        tester.getRect(compare),
        rectMoreOrLessEquals(inEditor),
        reason: 'it sets off from its place',
      );
      await tester.pump(const Duration(milliseconds: 150));
      final midway = tester.getSize(compare).height;
      expect(midway, greaterThan(inEditor.height), reason: 'it grows');
      expect(find.byType(AppBar), findsOneWidget, reason: 'over the editor');
      await arrive();
      expect(tester.takeException(), isNull);
      expect(find.byType(AppBar), findsNothing);
      expect(save.hitTestable(), findsNothing);
      expect(tester.state(compare), same(state), reason: 'its picture kept');
      // The photos lie under the picture, or stand at its side in a window
      // that is short and wide.
      final strip = tester.getRect(find.byType(PreviewPhotoSwitch));
      if (photosAtSide) {
        expect(strip.right, lessThanOrEqualTo(tester.getRect(compare).left));
        expect(tester.getSize(compare).width, greaterThan(size.width - 80));
      } else {
        expect(strip.top, greaterThanOrEqualTo(tester.getRect(compare).bottom));
        expect(tester.getSize(compare).width, size.width);
      }
      expect(tester.getSize(compare).height, greaterThan(midway));
      expect(tester.getSize(compare).height, greaterThan(size.height - 100));
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      expect(find.byTooltip('Full screen'), findsNothing);
      // Every photo is in reach: the look's own and the samples.
      for (var i = 0; i <= samplePhotos.length; i++) {
        expect(
          find.byKey(ValueKey('look-photo:$i')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(find.byType(LookCompareModeSwitch).hitTestable(), findsOneWidget);

      // There too a tap on the picture is the comparison's own.
      await tester.tap(find.byKey(const ValueKey('look-compare:single')));
      await tester.pump();
      expect(find.text('APPROXIMATE'), findsOneWidget);
      await tester.tap(compare);
      await tester.pump();
      expect(find.text('BEFORE'), findsOneWidget);
      expect(modes, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('look-photo:1')));
      await tester.pump();
      expect(shown().photo.image, isA<ResizeImage>());
      final sample = shown().photo;

      await tester.tap(button);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(modes, [
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.edgeToEdge',
      ]);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Full screen'), findsOneWidget);
      await arrive();
      expect(tester.state(compare), same(state));
      expect(tester.getRect(compare), inEditor);
      expect(shown().mode, LookCompareMode.single);
      expect(shown().photo, same(sample));
      expect(scroll().pixels, scrolled, reason: 'the controls where they were');

      await tester.tap(button);
      await arrive();
      expect(find.byType(AppBar), findsNothing);
      expect(modes.last, 'SystemUiMode.immersiveSticky');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(editor, findsOneWidget, reason: 'Back leaves full screen first');
      expect(find.byType(AppBar), findsOneWidget);
      expect(modes, hasLength(4));
      expect(modes.last, 'SystemUiMode.edgeToEdge');

      await tester.binding.handlePopRoute();
      await pumpUntil(
        tester,
        () => editor.evaluate().isEmpty,
        reason: 'editor closed',
      );
      expect(modes, hasLength(4));
      await app.dispose();
    });
  }

  testWidgets('an editor that goes away while its preview has the whole '
      "screen brings the system's bars back", (tester) async {
    final modes = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments);
        }
        return null;
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await _editorOpen(tester);
    await tester.tap(find.byKey(const Key('look-preview-fullscreen')));
    await tester.pump();
    expect(modes, ['SystemUiMode.immersiveSticky']);
    expect(find.byType(LookCompareModeSwitch).hitTestable(), findsOneWidget);
    await app.dispose();
    expect(modes, ['SystemUiMode.immersiveSticky', 'SystemUiMode.edgeToEdge']);
  });

  testWidgets('where the phone asks for less motion the preview has the '
      'whole screen, and is back in its place, at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await _editorOpen(tester);
    final compare = find.byType(LookCompare);
    final button = find.byKey(const Key('look-preview-fullscreen'));
    final inEditor = tester.getRect(compare);

    await tester.tap(button);
    await tester.pump();
    expect(find.byType(AppBar), findsNothing);
    expect(tester.getSize(compare).height, greaterThan(inEditor.height));
    await tester.tap(button);
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.getRect(compare), inEditor);
    await app.dispose();
  });

  // The second is as tall as a screen can be before the preview stays in
  // place.
  for (final size in const [Size(360, 330), Size(360, 450)]) {
    testWidgets('on half a phone, as in split screen (${size.height} high), '
        'the preview is large enough to judge and scrolls away with the '
        'controls, which follow it and stay in reach', (tester) async {
      final app = await _start(tester, saveCamera: false);
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
      await tapWhenReady(tester, find.byKey(const Key('looks-new')));
      await _editorOpen(tester);
      final screen = Offset.zero & size;
      final list = find.byType(ListView);
      final compare = find.byType(LookCompare);
      expect(find.descendant(of: list, matching: compare), findsOneWidget);
      expect(tester.getSize(compare).height, greaterThan(150));
      expect(tester.getSize(compare).width, closeTo(size.width, .01));
      expect(
        Scrollable.of(tester.element(compare)).position.pixels,
        0,
        reason:
            'the editor opens with the preview at the top, not scrolled '
            "to the look's base",
      );
      expect(
        tester.getRect(compare).top,
        greaterThanOrEqualTo(tester.getRect(list).top),
      );
      // The base images come after it, on screen or a scroll away.
      expect(
        tester
            .getRect(find.byKey(const Key('look-bases'), skipOffstage: false))
            .top,
        greaterThanOrEqualTo(tester.getRect(compare).bottom),
      );
      final save = tester.getRect(find.byKey(const Key('look-save')));
      expect(screen.contains(save.topLeft), isTrue);
      expect(screen.contains(save.bottomRight - const Offset(1, 1)), isTrue);

      final contrast = find.byKey(const ValueKey('look-param:contrast'));
      await tester.dragUntilVisible(contrast, list, const Offset(0, -80));
      await tester.pump();
      expect(contrast.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await app.dispose();
    });
  }

  for (final (name, size, photosAtSide) in const [
    ('a phone held on its side', Size(844, 390), true),
    ('a tablet held on its side', Size(1180, 820), false),
  ]) {
    testWidgets('on $name the editor puts the preview beside the controls, '
        'and turning the screen keeps what the editor holds', (tester) async {
      final app = await _start(tester, saveCamera: false);
      // The system's bar along the bottom edge.
      const bar = 24.0;
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(bottom: bar)
        ..viewPadding = const FakeViewPadding(bottom: bar);
      await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
      await tapWhenReady(tester, find.byKey(const Key('looks-new')));
      await _editorOpen(tester);
      final compare = find.byType(LookCompare);
      final bases = find.byKey(const Key('look-bases'));
      final save = find.byKey(const Key('look-save'));
      final strip = find.byType(PreviewPhotoSwitch);
      expect(
        tester.getRect(strip).bottom,
        lessThanOrEqualTo(size.height - bar),
        reason: "the photos keep clear of the system's bar",
      );
      // In a short and wide window the photos stand at the picture's
      // side, where they cost it no height; otherwise they lie under it.
      if (photosAtSide) {
        expect(
          tester.getRect(strip).right,
          lessThanOrEqualTo(tester.getRect(compare).left),
        );
        expect(tester.getRect(compare).bottom, closeTo(size.height - bar, .01));
      } else {
        expect(
          tester.getRect(strip).top,
          greaterThanOrEqualTo(tester.getRect(compare).bottom),
        );
      }
      for (final photo in _smallPictures(tester, samplePhotos.length)) {
        expect((Offset.zero & size).expandToInclude(photo), Offset.zero & size);
        expect(photo.shortestSide, greaterThanOrEqualTo(36));
      }
      expect(
        tester.getRect(compare).right,
        lessThanOrEqualTo(tester.getRect(bases).left),
      );
      expect(tester.getRect(compare).width, greaterThan(size.width * .4));
      expect(tester.getRect(save).left, tester.getRect(bases).left);
      expect((Offset.zero & size).contains(tester.getRect(save).center), true);

      await tapWhenReady(
        tester,
        find.byKey(const ValueKey('look-compare:sideBySide')),
      );
      await _pickBase(tester, LookBase.vivid);
      final state = tester.state(compare);
      tester.view.physicalSize = size.flipped;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(compare).bottom,
        lessThanOrEqualTo(tester.getRect(bases).top),
      );
      expect(tester.state(compare), same(state));
      expect(
        tester.getRect(strip).top,
        greaterThanOrEqualTo(tester.getRect(compare).bottom),
        reason: 'upright, the photos lie under the picture',
      );
      expect(
        tester.widget<LookCompare>(compare).mode,
        LookCompareMode.sideBySide,
      );
      expect(tester.widget<LookCompare>(compare).look?.base, LookBase.vivid);
      await app.dispose();
    });
  }

  testWidgets('on a foldable unfolded with its hinge upright the preview '
      'has one side of the hinge and the controls the other, though the '
      'window is taller than it is wide; without a hinge such a window '
      'keeps the preview above the controls', (tester) async {
    const size = Size(750, 830);
    final app = await _start(tester, saveCamera: false);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..displayFeatures = [_fold(const Rect.fromLTWH(365, 0, 20, 830))];
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await _editorOpen(tester);
    final compare = find.byType(LookCompare);
    final strip = find.byType(PreviewPhotoSwitch);
    final bases = find.byKey(const Key('look-bases'));
    final save = find.byKey(const Key('look-save'));
    expect(tester.getRect(compare).left, 0);
    expect(tester.getRect(compare).right, 365);
    expect(tester.getRect(strip).right, lessThanOrEqualTo(365));
    expect(
      tester.getRect(strip).top,
      greaterThanOrEqualTo(tester.getRect(compare).bottom),
    );
    expect(tester.getRect(bases).left, greaterThanOrEqualTo(385));
    expect(tester.getRect(save).left, greaterThanOrEqualTo(385));
    expect((Offset.zero & size).contains(tester.getRect(save).center), true);

    final state = tester.state(compare);
    tester.view.displayFeatures = const [];
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(compare).width, size.width);
    expect(
      tester.getRect(compare).bottom,
      lessThanOrEqualTo(tester.getRect(bases).top),
    );
    expect(tester.state(compare), same(state));
    await app.dispose();
  });

  testWidgets('at an upright hinge the photos are a grid only where that '
      'leaves the picture the height a photo wider than tall needs: what '
      'the preview has to say takes of that height, and with it the '
      'photos stay a strip', (tester) async {
    const page = 395.0;
    final app = await _start(tester, saveCamera: false);
    final looks = app.models.looks;
    final jpeg = File(samplePhotos.first.asset).readAsBytesSync();
    final (plain, older) = (await tester.runAsync(() async {
      final plain = await looks.add(
        name: 'Plain',
        data: Look.onBase(LookBase.standard).toBytes(),
        photo: jpeg,
      );
      final added = await looks.add(
        name: 'Older',
        data: Uint8List.fromList(app.camera.lookSlot(3).data),
        photo: jpeg,
      );
      // As a look saved before GR Photo kept the photo's own look, which
      // the preview says it does not know.
      final older = SavedLook(
        id: added.id,
        name: added.name,
        data: added.data,
        created: added.created,
      );
      await looks.update(older);
      return (plain, older);
    }))!;
    // Without a note the grid leaves the picture 12 pt more than it needs.
    tester.view
      ..physicalSize = const Size(2 * page + 20, 480)
      ..devicePixelRatio = 1
      ..displayFeatures = [_fold(const Rect.fromLTWH(page, 0, 20, 480))];
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    final compare = find.byType(LookCompare);
    final note = find.byKey(const Key('look-preview-note'));
    Future<void> open(SavedLook look) async {
      await tapWhenReady(tester, find.byKey(ValueKey('look:${look.id}')));
      await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
      await pumpUntilFound(tester, find.byType(LookPreview));
      await pumpRounds(tester, 30);
      expect(tester.takeException(), isNull);
    }

    void expectPictureHasRoom() {
      final picture = tester.getRect(compare);
      expect(picture.width, closeTo(page, .01));
      expect(picture.height, greaterThanOrEqualTo(page * 2 / 3 - .01));
    }

    // Its own photo, then the samples.
    const count = 7;
    await open(plain);
    expect(note, findsNothing);
    final inGrid = _smallPictures(tester, count);
    expect(inGrid[4].top, greaterThan(inGrid.first.bottom));
    expect(inGrid.first.width, greaterThan(70));
    expectPictureHasRoom();
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find.byKey(const Key('look-editor')).evaluate().isEmpty,
      reason: 'editor closed',
    );

    await open(older);
    expect(note, findsOneWidget);
    final inStrip = _smallPictures(tester, count);
    for (final picture in inStrip) {
      expect(picture.top, inStrip.first.top);
    }
    expect(
      tester.getRect(note).top,
      greaterThanOrEqualTo(tester.getRect(compare).bottom),
    );
    expect(
      inStrip.first.top,
      greaterThanOrEqualTo(tester.getRect(note).bottom),
    );
    expectPictureHasRoom();
    await app.dispose();
  });

  testWidgets('on a foldable half-open on a table the picture and its two '
      'controls have the upright half, and the photos and every other '
      'control the flat half, in two columns; full screen keeps to the '
      'halves, and opened flat the editor is as on any wide screen', (
    tester,
  ) async {
    const size = Size(830, 750);
    const fold = Rect.fromLTWH(0, 375, 830, 0);
    final app = await _start(tester, saveCamera: false);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..displayFeatures = [_fold(fold, halfOpen: true)];
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await _editorOpen(tester);
    final compare = find.byType(LookCompare);
    final strip = find.byType(PreviewPhotoSwitch);
    final bases = find.byKey(const Key('look-bases'));
    final groups = find.byKey(const Key('look-groups'));
    final save = find.byKey(const Key('look-save'));
    final button = find.byKey(const Key('look-preview-fullscreen'));
    final bar = tester.getRect(find.byType(AppBar));

    final upright = Rect.fromLTRB(0, bar.bottom, size.width, fold.top);
    expect(tester.getRect(compare), upright);
    for (final control in [find.byType(LookCompareModeSwitch), button]) {
      expect(upright.expandToInclude(tester.getRect(control)), upright);
    }
    expect(tester.getRect(strip).top, greaterThanOrEqualTo(fold.bottom));
    expect(
      tester.getRect(bases).top,
      greaterThanOrEqualTo(tester.getRect(strip).bottom),
    );
    expect(
      tester.getRect(groups).left,
      greaterThanOrEqualTo(tester.getRect(bases).right),
      reason: 'the groups and their parameters in a column of their own',
    );
    expect(tester.getRect(groups).top, greaterThanOrEqualTo(fold.bottom));
    expect(
      find.byKey(const ValueKey('look-param:contrast')).hitTestable(),
      findsOneWidget,
      reason: 'more than one parameter in view',
    );
    expect(tester.getRect(save).right, lessThan(tester.getRect(groups).left));
    expect((Offset.zero & size).contains(tester.getRect(save).center), true);
    expect(tester.getRect(save).top, greaterThan(fold.bottom));

    // Another photo is picked on the flat half.
    final state = tester.state(compare);
    final first = tester.widget<LookCompare>(compare).photo;
    await tester.tap(find.byKey(const ValueKey('look-photo:1')));
    await tester.pump();
    expect(tester.widget<LookCompare>(compare).photo, isNot(same(first)));
    expect(tester.state(compare), same(state));

    // Full screen: the picture has all of the upright half, and the
    // photos are still on the flat one.
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppBar), findsNothing);
    expect(save.hitTestable(), findsNothing);
    expect(tester.getRect(compare), Rect.fromLTRB(0, 0, size.width, fold.top));
    expect(tester.state(compare), same(state));
    final firstPhoto = find.byKey(const ValueKey('look-photo:0')).hitTestable();
    expect(firstPhoto, findsOneWidget);
    expect(tester.getRect(firstPhoto).top, greaterThanOrEqualTo(fold.bottom));
    await tester.tap(firstPhoto);
    await tester.pump();
    expect(tester.widget<LookCompare>(compare).photo, same(first));
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(tester.getRect(compare), upright);

    // Opened flat, the fold no longer divides the editor.
    tester.view.displayFeatures = [_fold(fold)];
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.state(compare), same(state));
    expect(
      tester.getRect(compare).right,
      lessThanOrEqualTo(tester.getRect(bases).left),
    );
    expect(tester.getRect(compare).bottom, greaterThan(fold.bottom));
    expect(
      tester.getRect(strip).top,
      greaterThanOrEqualTo(tester.getRect(compare).bottom),
    );
    await app.dispose();
  });

  testWidgets('a flip phone half-open on a table has the photos and the '
      'controls in one column on its flat half, and a window with too '
      'little on either side of the fold is not divided at it', (tester) async {
    const size = Size(360, 800);
    final app = await _start(tester, saveCamera: false);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..displayFeatures = [
        _fold(const Rect.fromLTWH(0, 400, 360, 0), halfOpen: true),
      ];
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await _editorOpen(tester);
    final compare = find.byType(LookCompare);
    final strip = find.byType(PreviewPhotoSwitch);
    final bases = find.byKey(const Key('look-bases'));
    final save = find.byKey(const Key('look-save'));
    expect(tester.getRect(compare).bottom, 400);
    expect(tester.getRect(compare).width, size.width);
    expect(tester.getRect(strip).top, greaterThanOrEqualTo(400));
    expect(
      tester.getRect(bases).top,
      greaterThanOrEqualTo(tester.getRect(strip).bottom),
    );
    expect(tester.getRect(bases).width, greaterThan(300));
    expect((Offset.zero & size).contains(tester.getRect(save).center), true);

    // Half a phone's height: 124 pt under the app bar is no place for a
    // picture.
    tester.view
      ..physicalSize = const Size(360, 360)
      ..displayFeatures = [
        _fold(const Rect.fromLTWH(0, 180, 360, 0), halfOpen: true),
      ];
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: find.byType(ListView), matching: compare),
      findsOneWidget,
      reason: 'the preview scrolls with the controls, as without a fold',
    );
    expect(
      tester.getRect(strip).top,
      greaterThanOrEqualTo(tester.getRect(compare).bottom),
    );
    await app.dispose();
  });

  testWidgets('on a closed iPhone Duo the editor has Back and its menu in '
      "the vertical bar under the status and the look's name alone "
      'across the top; the menu opens and Back leaves', (tester) async {
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await _editorOpen(tester);
    await _toDuo(tester, app, DuoWindow.closed);
    expect(tester.takeException(), isNull);

    final back = find.byKey(const Key('look-editor-back'));
    final menu = find.byKey(const Key('look-editor-menu'));
    _expectInBar(tester, _closedBar, ['look-editor-back', 'look-editor-menu']);
    final bar = find.byType(AppBar);
    expect(find.byType(BackButton), findsNothing);
    expect(find.descendant(of: bar, matching: menu), findsNothing);
    final name = find.descendant(of: bar, matching: find.text('Standard'));
    // The window has no inset at the top here: the name keeps clear of the
    // display's rounded corner itself.
    expect(tester.getRect(name).top, greaterThanOrEqualTo(14));
    for (final part in [
      name,
      find.byType(LookCompare),
      find.byType(PreviewPhotoSwitch),
      find.byKey(const Key('look-save')),
    ]) {
      expect(
        tester.getRect(part).right,
        lessThanOrEqualTo(_closedBar.left),
        reason: part.describeMatch(Plurality.one),
      );
    }

    await tapWhenReady(tester, menu);
    await pumpUntilFound(tester, find.text('Rename'));
    await tester.tapAt(Offset.zero);
    await pumpUntil(tester, () => find.text('Rename').evaluate().isEmpty);

    await tapWhenReady(tester, back);
    await pumpUntil(
      tester,
      () => find.byKey(const Key('look-editor')).evaluate().isEmpty,
      reason: 'the editor closed',
    );
    await app.dispose();
  });

  for (final window in [DuoWindow.open, DuoWindow.book]) {
    testWidgets('on an iPhone Duo held wide (${window.name}) the editor '
        'has the pictures on the page before the fold, under the name and '
        'with the photos in a grid, and the controls on the page after '
        'it, a whole group of parameters in view', (tester) async {
      final app = await _start(tester, saveCamera: false);
      await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
      await tapWhenReady(tester, find.byKey(const Key('looks-new')));
      await _editorOpen(tester);
      await _toDuo(tester, app, window);
      expect(tester.takeException(), isNull);

      final pages = _pagesOf(window);
      final bar = find.byType(AppBar);
      final name = tester.getRect(
        find.descendant(of: bar, matching: find.text('Standard')),
      );
      final compare = tester.getRect(find.byType(LookCompare));
      final photos = _smallPictures(tester, samplePhotos.length);
      for (final part in [name, compare, ...photos]) {
        expect(pages.first.expandToInclude(part), pages.first);
      }
      expect(name.top, greaterThanOrEqualTo(14));
      expect(compare.top, greaterThanOrEqualTo(name.bottom));
      expect(compare.width, closeTo(pages.first.width, .01));
      // Room for a photo wider than tall to fill the page's width.
      expect(compare.height, greaterThanOrEqualTo(compare.width * 2 / 3));
      // The photos are a grid under the picture: two rows of three, each
      // far larger than in a strip, clear of the system's bar along the
      // bottom edge.
      expect(photos.first.top, greaterThanOrEqualTo(compare.bottom));
      expect(photos.first.width, greaterThan(100));
      expect(photos[2].top, photos.first.top);
      expect(photos[3].top, greaterThan(photos.first.bottom));
      expect(photos[3].left, photos.first.left);
      final aboveSystemBar = window.size.height - window.insets.bottom;
      expect(photos.last.bottom, lessThanOrEqualTo(aboveSystemBar));

      final bases = tester.getRect(find.byKey(const Key('look-bases')));
      final groups = tester.getRect(find.byKey(const Key('look-groups')));
      final save = tester.getRect(find.byKey(const Key('look-save')));
      for (final part in [bases, groups, save]) {
        expect(pages.second.expandToInclude(part), pages.second);
      }
      expect(save.bottom, lessThanOrEqualTo(aboveSystemBar));
      // The controls have the whole height of their page: they start
      // beside the name, above the picture.
      expect(bases.top, lessThan(compare.top));
      final parameters = _parameters();
      final count = parameters.evaluate().length;
      expect(count, greaterThanOrEqualTo(2));
      for (var i = 0; i < count && i < 6; i++) {
        final parameter = tester.getRect(parameters.at(i));
        expect(parameter.top, greaterThanOrEqualTo(groups.bottom));
        expect(parameter.bottom, lessThanOrEqualTo(save.top));
      }

      _expectInBar(tester, _wideBar, ['look-editor-back', 'look-editor-menu']);
      expect(find.byType(BackButton), findsNothing);
      await app.dispose();
    });
  }

  testWidgets('on an iPhone Duo half-open on a table the picture has the '
      'upright half under the bar across the top, and the photos and '
      'every control the flat half; opened flat, the editor is as on any '
      'upright screen and keeps what it holds', (tester) async {
    const window = DuoWindow.tabletop;
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await _editorOpen(tester);
    await _toDuo(tester, app, window);
    expect(tester.takeException(), isNull);

    final fold = window.pose.fold!;
    final compare = find.byType(LookCompare);
    final strip = find.byType(PreviewPhotoSwitch);
    final bases = find.byKey(const Key('look-bases'));
    final groups = find.byKey(const Key('look-groups'));
    final save = find.byKey(const Key('look-save'));
    final bar = tester.getRect(find.byType(AppBar));
    // No vertical bar here: Back and the menu are in the bar across the
    // top, under the band the status is in.
    for (final button in [
      find.byType(BackButton),
      find.byKey(const Key('look-editor-menu')),
    ]) {
      final inBar = tester.getRect(button);
      expect(inBar.top, greaterThanOrEqualTo(window.insets.top));
      expect(inBar.bottom, lessThanOrEqualTo(bar.bottom));
    }
    expect(
      tester.getRect(compare),
      rectMoreOrLessEquals(
        Rect.fromLTRB(0, bar.bottom, window.size.width, fold.top),
        epsilon: .01,
      ),
    );
    expect(tester.getRect(strip).top, greaterThanOrEqualTo(fold.bottom));
    expect(
      tester.getRect(bases).top,
      greaterThanOrEqualTo(tester.getRect(strip).bottom),
    );
    expect(
      tester.getRect(groups).left,
      greaterThanOrEqualTo(tester.getRect(bases).right),
    );
    expect(tester.getRect(groups).top, greaterThanOrEqualTo(fold.bottom));
    expect(tester.getRect(save).top, greaterThan(fold.bottom));
    expect(
      tester.getRect(save).bottom,
      lessThanOrEqualTo(window.size.height - window.insets.bottom),
    );

    final state = tester.state(compare);
    await _toDuo(tester, app, DuoWindow.upright);
    expect(tester.takeException(), isNull);
    expect(tester.state(compare), same(state));
    expect(tester.getRect(compare).width, closeTo(window.size.width, .01));
    expect(
      tester.getRect(compare).bottom,
      lessThanOrEqualTo(tester.getRect(bases).top),
    );
    await app.dispose();
  });

  testWidgets("the look's base image is stepped through with the arrows, "
      'as far as the first and the last; their list marks it, and closing '
      'the list without picking leaves it', (tester) async {
    final app = await _inLooks(tester);
    await tapWhenReady(tester, _inSlot(3, 'Soft Summer'));
    await _editorOpen(tester);
    final next = find.byKey(const Key('look-base-next'));
    final list = find.byKey(const Key('look-base-list'));
    expect(_inBases('Negative Film'), findsOneWidget);
    expect(_inBases('11 of 14'), findsOneWidget);

    await _openBases(tester);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('look-base:negativeFilm'))),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('look-base:retro'))),
      isSemantics(isSelected: false),
    );
    // Above the list.
    await tester.tapAt(const Offset(20, 20));
    await pumpUntil(
      tester,
      () => list.evaluate().isEmpty,
      reason: 'the list of base images closed',
    );
    expect(_inBases('Negative Film'), findsOneWidget);

    await tapWhenReady(tester, find.byKey(const Key('look-base-previous')));
    expect(_inBases('HDR Tone'), findsOneWidget);
    expect(_inBases('10 of 14'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tapWhenReady(tester, next);
    }
    expect(_inBases('Cross Processing'), findsOneWidget);
    expect(_inBases('14 of 14'), findsOneWidget);
    // No base image comes after the last.
    await tapWhenReady(tester, next);
    expect(_inBases('Cross Processing'), findsOneWidget);
    await app.dispose();
  });

  testWidgets('on a camera a look opened from the library has Save alone, '
      'and its menu loads it into any slot; opened from a slot it loads '
      'into that slot', (tester) async {
    final app = await _inLooks(tester);
    // The slots have been read: a look can be loaded.
    await pumpUntilFound(tester, _inSlot(1, 'Tokyo Night'));
    final saved = (await tester.runAsync(
      () => app.models.looks.add(
        name: 'Plain',
        data: _slotLook(app, 1).withBase(LookBase.vivid).toBytes(),
      ),
    ))!;
    await tapWhenReady(tester, find.byKey(ValueKey('look:${saved.id}')));
    await _editorOpen(tester);
    expect(find.byKey(const Key('look-load')), findsNothing);
    await tapWhenReady(tester, find.byKey(const Key('look-editor-menu')));
    await tapWhenReady(tester, find.text('Load into C3'));
    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Plain into C3'));
    expect(_slotLook(app, 3).base, LookBase.vivid);

    await tester.pageBack();
    await tapWhenReady(tester, _inSlot(2, 'Daido'));
    final load = find.byKey(const Key('look-load'));
    await pumpUntilFound(tester, load);
    expect(
      find.descendant(of: load, matching: find.text('Load into C2')),
      findsOneWidget,
    );
    await tapWhenReady(tester, load);
    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Daido into C2'));
    await app.dispose();
  });

  testWidgets('a slot saved from the editor joins the library, from C2 and '
      'tagged as in C2', (tester) async {
    final app = await _inLooks(tester);
    await tapWhenReady(tester, _inSlot(2, 'Daido'));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    await tapWhenReady(tester, find.byKey(const Key('look-save')));
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await pumpUntilFound(tester, find.text('Saved Daido'));
    await tester.pageBack();
    await pumpUntilFound(tester, find.text('From C2'));
    expect(find.text('In C2'), findsOneWidget);

    final saved = app.models.looks.looks.single;
    expect(saved.name, 'Daido');
    expect(saved.data, app.camera.lookSlot(2).data);
    await app.dispose();
  });

  testWidgets('a save the phone cannot store says so, and saving again '
      'stores the look once', (tester) async {
    final app = await _inLooks(tester);
    final dataDir = app.models.services.dataDir.path;
    // `looks.json` is replaced by renaming a temporary file over it, which
    // fails while a non-empty directory has its name.
    final block = Directory('$dataDir/looks.json')..createSync();
    File('${block.path}/keep').writeAsStringSync('');

    await tapWhenReady(tester, _inSlot(2, 'Daido'));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    await tapWhenReady(tester, find.byKey(const Key('look-save')));
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await pumpUntilFound(
      tester,
      find.text("Couldn't save Daido on this phone."),
    );
    expect(app.models.looks.looks, isEmpty);

    block.deleteSync(recursive: true);
    await tapWhenReady(tester, find.byKey(const Key('look-save')));
    await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    await pumpUntilFound(tester, find.text('Saved Daido'));
    expect(app.models.looks.looks.single.name, 'Daido');
    await app.dispose();
  });

  testWidgets('a look with the name or the settings of a saved look is not '
      'saved or renamed, and a dialog names the look in the way', (
    tester,
  ) async {
    final app = await _start(tester, saveCamera: false);
    final looks = app.models.looks;
    Future<void> nameIt(String name) async {
      final field = find.byKey(const Key('looks-name-field'));
      await pumpUntilFound(tester, field);
      await tester.enterText(field, name);
      await tapWhenReady(tester, find.byKey(const Key('looks-name-ok')));
    }

    Future<void> saveAs(String name) async {
      await tapWhenReady(tester, find.byKey(const Key('look-save')));
      await nameIt(name);
    }

    Future<void> dismiss(String said) async {
      await pumpUntilFound(tester, find.text(said));
      await tapWhenReady(tester, find.byKey(const Key('looks-conflict-ok')));
      await pumpUntil(tester, () => find.text(said).evaluate().isEmpty);
    }

    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    await saveAs('Plain');
    await pumpUntilFound(tester, find.text('Saved Plain'));
    await tester.pageBack();

    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    await saveAs('Plain');
    await pumpUntilFound(tester, find.text('This look already exists'));
    await dismiss('Plain is already saved with the same settings.');
    await saveAs('Other');
    await dismiss(
      "Another look, Plain, has the same settings. Two looks can't have the "
      'same settings.',
    );
    await _pickBase(tester, LookBase.vivid);
    await saveAs('Plain');
    await dismiss(
      'Another look is already named Plain. Give this look a different name.',
    );
    expect(looks.looks.map((l) => l.name), ['Plain']);

    await saveAs('Bright');
    await pumpUntilFound(tester, find.text('Saved Bright'));
    final bright = looks.looks.first;
    await tester.pageBack();
    await tapWhenReady(tester, find.byKey(Key('look-menu:${bright.id}')));
    await tapWhenReady(tester, find.text('Rename'));
    await nameIt('Plain');
    await dismiss(
      'Another look is already named Plain. Give this look a different name.',
    );
    expect(looks.looks.map((l) => l.name), ['Bright', 'Plain']);
    await app.dispose();
  });
}
