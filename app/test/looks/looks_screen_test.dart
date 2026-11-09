import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import '../support/test_app.dart';

const _quietLiveness = GrSessionOptions(
  livenessInterval: Duration(hours: 1),
  livenessLossAfter: Duration(hours: 2),
);

/// The whole app with the fake GR IV paired and off, on the Looks tab.
Future<TestApp> _inLooks(WidgetTester tester) async {
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
  await tapWhenReady(tester, find.byKey(const Key('camera-card-shoot')));
  await tapWhenReady(tester, find.byKey(const Key('camera-tab-looks')));
  await pumpUntilFound(tester, find.byKey(const Key('looks')));
  return app;
}

Finder _inSlot(int number, String text) => find.descendant(
  of: find.byKey(Key('looks-slot-$number')),
  matching: find.text(text),
);

BleImageControlBlob _slotLook(TestApp app, int number) => imageControlFromBytes(
  Uint8List.fromList(app.camera.lookSlot(number).data),
)!;

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
    expect(look.base.known, BleImageControlBase.bleachBypass);
    expect(look.valueOf(BleImageControlParameter.toningBleachBypass), 3);
    expect(look.valueOf(BleImageControlParameter.saturation), 1);
    expect(look.valueOf(BleImageControlParameter.grain), isNull);
    expect(app.camera.lookSlot(1).name, 'Tokyo Night');
    expect(app.camera.lookSlot(2).name, 'Daido', reason: 'C2 untouched');
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
}
