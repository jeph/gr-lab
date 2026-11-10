import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'package:grlab/src/camera/camera_pages.dart';
import 'package:grlab/src/library/image_orientation.dart';
import 'package:grlab/src/looks/look_compare.dart';
import 'package:grlab/src/looks/look_preview.dart';
import 'package:grlab/src/looks/looks_store.dart';
import 'package:grlab/src/widgets/skeleton.dart';

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

Look _slotLook(TestApp app, int number) =>
    Look.fromBytes(Uint8List.fromList(app.camera.lookSlot(number).data))!;

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
  });

  testWidgets('C1-C3 are skeletons of their cards, without a spinner, until '
      'the camera has been read', (tester) async {
    await _inLooks(tester);
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
  });

  testWidgets('a slot edited to a new base and toning loads back into the '
      'camera under its name', (tester) async {
    final app = await _inLooks(tester);
    await tapWhenReady(tester, _inSlot(1, 'Tokyo Night'));
    await pumpUntilFound(tester, find.byKey(const Key('look-editor')));

    final bleach = find.byKey(const ValueKey('look-base:bleachBypass'));
    await tester.scrollUntilVisible(
      bleach,
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('look-bases')),
        matching: find.byType(Scrollable),
      ),
    );
    await tapWhenReady(tester, bleach);
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
    expect(
      find.byKey(const ValueKey('look-base:positiveFilm')),
      findsNothing,
      reason: 'the editor offers the monochrome bases only',
    );

    await tapWhenReady(
      tester,
      find.byKey(const ValueKey('look-base:standardMono')),
    );
    expect(find.byKey(const Key('look-not-offered')), findsNothing);
    await tapWhenReady(tester, load);
    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Tokyo Night into C1'));
    expect(_slotLook(app, 1).base, LookBase.standardMono);
    expect(app.camera.lookSlot(1).data, isNot(held));
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
    await tapWhenReady(
      tester,
      find.byKey(const ValueKey('look-base:standardMono')),
    );
    await tapWhenReady(tester, find.byKey(const Key('look-load')));
    await tapWhenReady(tester, find.byKey(const Key('looks-load-confirm')));
    await pumpUntilFound(tester, find.text('Loaded Tokyo Night into C1'));
    expect(_slotLook(app, 1).base, LookBase.standardMono);
    await app.dispose();
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
    await tapWhenReady(tester, find.byKey(const Key('camera-forget')));
    await tapWhenReady(tester, find.byKey(const Key('camera-forget-confirm')));
    await pumpUntilFound(tester, find.byKey(const Key('cameras-welcome')));

    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await pumpUntilFound(tester, find.text('From C2'));
    expect(find.text('From R0001234.JPG'), findsOneWidget);
    expect(looks.looks.map((l) => l.name), ['Street', 'Daido']);
    expect(looks.photoOf(street), isNotNull);
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
      'starts on the sample photo when it can only be undone roughly or '
      'not at all; either photo can be picked, and a photo with nothing to '
      'offer the look is shown as it was taken', (tester) async {
    final app = await _start(tester, saveCamera: false);
    final looks = app.models.looks;
    final jpeg = File('assets/welcome.jpg').readAsBytesSync();
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
      // As a look saved before GR Lab kept the photo's own look.
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
    LookPreview preview() =>
        tester.widget<LookPreview>(find.byType(LookPreview));
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
    await tapWhenReady(tester, find.byKey(const ValueKey('look-base:vivid')));
    expect(note, findsNothing, reason: 'a Standard photo suits every look');
    expect(preview().look.base, LookBase.vivid);
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
    await tapWhenReady(tester, find.byKey(const ValueKey('look-base:vivid')));
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
    await tapWhenReady(tester, find.byKey(const ValueKey('look-base:vivid')));
    await pumpRounds(tester, 3);
    expect(noteSaying(startsOnSample), findsOneWidget);
    expect(previewed(), isA<AssetImage>());
    await close();

    await open(older);
    expect(
      noteSaying(
        "GR Lab doesn't know which look this photo was taken with, so the "
        'preview treats it as Standard.',
      ),
      findsOneWidget,
    );
    expect(previewed(), isNot(isA<AssetImage>()));
    await app.dispose();
  });

  testWidgets('a look with no photo of its own is previewed on the sample '
      'photo, with no photos to pick from', (tester) async {
    final app = await _start(tester, saveCamera: false);
    await tapWhenReady(tester, find.byKey(const Key('home-tab-looks')));
    await tapWhenReady(tester, find.byKey(const Key('looks-new')));
    await pumpUntilFound(tester, find.byType(LookPreview));
    expect(
      tester.widget<LookPreview>(find.byType(LookPreview)).image,
      isA<ResizeImage>().having(
        (i) => i.imageProvider,
        'photo',
        isA<AssetImage>(),
      ),
    );
    expect(find.byType(PreviewPhotoSwitch), findsNothing);
    expect(find.byKey(const Key('look-preview-note')), findsNothing);
    await app.dispose();
  });

  testWidgets('a look saved from a photo held on its side shows that photo '
      'upright, in the list and in the editor', (tester) async {
    final app = await _start(tester, saveCamera: false);
    final looks = app.models.looks;
    // The sample is 600 by 900 as stored; orientation 6 lays it on its
    // side, so upright it is wider than tall.
    final jpeg = File('assets/welcome.jpg').readAsBytesSync();
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
    expect(tester.getSize(picture).aspectRatio, closeTo(900 / 600, .01));
    expect(orientationIn(find.byKey(const ValueKey('look-photo:0'))), 6);
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find.byKey(const Key('look-editor')).evaluate().isEmpty,
      reason: 'editor closed',
    );

    await tapWhenReady(tester, storedRow);
    await pumpUntilFound(tester, find.byType(LookPreview));
    expect(tester.getSize(picture).aspectRatio, closeTo(600 / 900, .01));
    await app.dispose();
  });

  testWidgets("a camera's slot that holds a saved look shows that look's "
      'photo upright', (tester) async {
    final app = await _inLooks(tester);
    final saved = (await tester.runAsync(
      () => app.models.looks.add(
        name: 'Turned',
        data: Uint8List.fromList(app.camera.lookSlot(2).data),
        photo: File('assets/welcome.jpg').readAsBytesSync(),
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
      expect(list.height, greaterThan(60), reason: 'room for a parameter');
      expect(screen.contains(save.topLeft), isTrue);
      expect(screen.contains(save.bottomRight - const Offset(1, 1)), isTrue);
      for (final mode in LookCompareMode.values) {
        await tapWhenReady(
          tester,
          find.byKey(ValueKey('look-compare:${mode.name}')),
        );
        final picture = tester.getRect(find.byType(LookPreview));
        expect(picture.size.aspectRatio, closeTo(600 / 900, .02));
        expect(preview.expandToInclude(picture), preview, reason: mode.name);
      }
      await app.dispose();
    });
  }

  for (final (name, size) in const [
    ('a small phone', Size(320, 568)),
    ('half a phone, as in split screen', Size(360, 330)),
    ('a phone held on its side', Size(844, 390)),
  ]) {
    testWidgets('on $name a tap on the preview, or its button, gives it the '
        'whole screen with the choice of photo and of comparison and '
        'nothing else; its button or Back brings the editor back as it was', (
      tester,
    ) async {
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
      final jpeg = File('assets/welcome.jpg').readAsBytesSync();
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

      await tester.drag(list, const Offset(0, -60));
      await tester.pump();
      final scrolled = scroll().pixels;
      expect(scrolled, greaterThan(0));
      final state = tester.state(compare);
      final inEditor = tester.getRect(compare);
      expect(find.byTooltip('Full screen'), findsOneWidget);
      expect(modes, isEmpty);

      // Where the picture is: half the preview is scrolled away on the
      // shortest screen.
      await tester.tapAt(inEditor.bottomCenter - const Offset(40, 40));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(modes, ['SystemUiMode.immersiveSticky']);
      expect(find.byType(AppBar), findsNothing);
      expect(save.hitTestable(), findsNothing);
      expect(tester.state(compare), same(state), reason: 'its picture kept');
      expect(tester.getSize(compare).width, size.width);
      expect(tester.getSize(compare).height, greaterThan(size.height - 100));
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      expect(find.byTooltip('Full screen'), findsNothing);
      expect(find.byType(PreviewPhotoSwitch).hitTestable(), findsOneWidget);
      expect(find.byType(LookCompareModeSwitch).hitTestable(), findsOneWidget);

      // There a tap on the picture is the comparison's own again.
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
      expect(tester.state(compare), same(state));
      expect(tester.getRect(compare), inEditor);
      expect(shown().mode, LookCompareMode.single);
      expect(shown().photo, same(sample));
      expect(scroll().pixels, scrolled, reason: 'the controls where they were');
      expect(find.byTooltip('Full screen'), findsOneWidget);

      await tester.tap(button);
      await tester.pump();
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
    // A look without a photo of its own has nothing to pick between.
    expect(find.byType(PreviewPhotoSwitch), findsNothing);
    expect(find.byType(LookCompareModeSwitch).hitTestable(), findsOneWidget);
    await app.dispose();
    expect(modes, ['SystemUiMode.immersiveSticky', 'SystemUiMode.edgeToEdge']);
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

  for (final (name, size) in const [
    ('a phone held on its side', Size(844, 390)),
    ('a tablet held on its side', Size(1180, 820)),
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
      expect(
        tester.getRect(find.byType(LookCompareModeSwitch)).bottom,
        lessThanOrEqualTo(size.height - bar),
        reason: "the switches keep clear of the system's bar",
      );
      expect(
        tester.getRect(compare).right,
        lessThanOrEqualTo(tester.getRect(bases).left),
      );
      expect(tester.getRect(compare).width, greaterThan(size.width * .4));
      expect(tester.getRect(save).left, tester.getRect(bases).left + 16);
      expect((Offset.zero & size).contains(tester.getRect(save).center), true);

      await tapWhenReady(
        tester,
        find.byKey(const ValueKey('look-compare:sideBySide')),
      );
      await tapWhenReady(tester, find.byKey(const ValueKey('look-base:vivid')));
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
        tester.widget<LookCompare>(compare).mode,
        LookCompareMode.sideBySide,
      );
      expect(tester.widget<LookCompare>(compare).look?.base, LookBase.vivid);
      await app.dispose();
    });
  }

  testWidgets('the editor opens with the base image of its look in view, '
      'however far along the row it is', (tester) async {
    final app = await _inLooks(tester);
    await tapWhenReady(tester, _inSlot(3, 'Soft Summer'));
    await _editorOpen(tester);

    final bases = tester.getRect(find.byKey(const Key('look-bases')));
    final opened = tester.getRect(
      find.byKey(const ValueKey('look-base:negativeFilm')),
    );
    expect(opened.left, greaterThanOrEqualTo(bases.left));
    expect(opened.right, lessThanOrEqualTo(bases.right));
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
    await tapWhenReady(tester, find.byKey(const ValueKey('look-base:vivid')));
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
