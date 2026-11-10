import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import 'package:grlab/src/camera/camera_pages.dart';
import 'package:grlab/src/looks/look_preview.dart';
import 'package:grlab/src/looks/looks_store.dart';

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

  testWidgets('the editor previews a look on the photo it was saved from, '
      "says when that photo's own look makes the preview rough or is not "
      'known, and shows the sample photo when the photo has nothing to '
      'offer the look', (tester) async {
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
    // The photo itself, under the size the preview asks for it in.
    ImageProvider previewed() => switch (preview().image) {
      ResizeImage(:final imageProvider) => imageProvider,
      final other => other,
    };
    Future<void> open(SavedLook look) async {
      await tapWhenReady(tester, find.byKey(ValueKey('look:${look.id}')));
      await pumpUntilFound(tester, find.byKey(const Key('look-editor')));
    }

    Future<void> close() async {
      await tester.pageBack();
      await pumpUntil(
        tester,
        () => find.byKey(const Key('look-editor')).evaluate().isEmpty,
        reason: 'editor closed',
      );
    }

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
    await close();

    await open(grey);
    expect(
      noteSaying(
        "This photo's own look can't be undone exactly, so the preview is "
        'rougher than usual.',
      ),
      findsOneWidget,
    );
    expect(previewed(), isNot(isA<AssetImage>()));
    await tapWhenReady(tester, find.byKey(const ValueKey('look-base:vivid')));
    await pumpUntilFound(
      tester,
      noteSaying(
        "This photo's own look can't be undone for this look, so the "
        'preview shows a sample photo instead.',
      ),
    );
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
