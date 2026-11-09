import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import '../shoot/rig.dart';

void main() {
  late ShootRig rig;

  tearDown(() => rig.close());

  test('after the wake, the slots read back what the camera holds', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    final looks = rig.session.looks;
    expect(looks.slots, isNull);
    await looks.wake();
    expect(looks.hasSlots, isTrue);
    await looks.readSlots();

    final slots = looks.slots!;
    expect([for (final s in slots) s.number], [1, 2, 3]);
    expect(
      [for (final s in slots) s.name],
      ['Tokyo Night', 'Daido', 'Soft Summer'],
    );
    final c1 = slots[0].look!;
    expect(c1.base.known, BleImageControlBase.positiveFilm);
    expect(c1.valueOf(BleImageControlParameter.saturation), 1);
    expect(c1.valueOf(BleImageControlParameter.key), -1);
    expect(c1.valueOf(BleImageControlParameter.grainStrength), 2);
    expect(c1.parameters, hasLength(12));
  });

  test('a camera that is off does not answer for its slots', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(bonded: true, poweredOn: false),
    );
    await expectLater(
      rig.session.looks.readSlots(),
      throwsA(isA<BleException>()),
    );
    expect(rig.session.looks.slots, isNull);
  });

  test('load writes the data and the name, and the slot reads back the '
      'new look', () async {
    rig = await ShootRig.start();
    final looks = rig.session.looks;
    await looks.wake();
    await looks.readSlots();
    final cine = imageControlFromBytes(
      Uint8List.fromList(FakeLook.presets[3].data),
    )!;

    final slot = await looks.load(2, name: 'Cine Teal', look: cine);

    expect(slot.number, 2);
    expect(slot.name, 'Cine Teal');
    expect(slot.data, FakeLook.presets[3].data);
    expect(rig.camera.lookSlot(2).name, 'Cine Teal');
    expect(rig.camera.lookSlot(2).data, FakeLook.presets[3].data);
    expect(looks.slots![1].name, 'Cine Teal');
    expect(looks.slots![0].name, 'Tokyo Night', reason: 'C1 untouched');
    expect(rig.events('looks.loaded').single, {
      'slot': 2,
      'sameData': true,
      'sameName': true,
    });
  });

  test('looks with more or fewer parameters than the slot held load and '
      'read back', () async {
    rig = await ShootRig.start();
    final looks = rig.session.looks;
    await looks.wake();
    await looks.readSlots();
    final held = looks.slots![0].look!;
    final rebased = held.withBase(BleImageControlBase.highContrast);
    final fresh = newImageControl(BleImageControlBase.standard, template: held);
    expect(rebased.parameters.length, greaterThan(held.parameters.length));
    expect(fresh.parameters.length, lessThan(held.parameters.length));

    final first = await looks.load(1, name: 'Rebased', look: rebased);
    final second = await looks.load(2, name: 'Fresh', look: fresh);

    expect(first.look!.sameLookAs(rebased), isTrue);
    expect(second.look!.sameLookAs(fresh), isTrue);
    expect(rig.camera.lookSlot(1).look.sameLookAs(rebased), isTrue);
    expect(rig.camera.lookSlot(2).look.sameLookAs(fresh), isTrue);
  });

  test('a blob the camera refuses leaves the slot as it was', () async {
    rig = await ShootRig.start();
    final looks = rig.session.looks;
    await looks.wake();
    final unsupported = BleImageControlBlob(
      version: 3,
      reserved: 0,
      base: BleEnumValue.of(BleImageControlBase.vivid),
      parameters: const [],
    );
    await expectLater(
      looks.load(1, name: 'Nope', look: unsupported),
      throwsA(isA<BleException>()),
    );
    expect(rig.camera.lookSlot(1).name, 'Tokyo Night');
  });

  test('a GR III has no slots', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(bonded: true, model: 'RICOH GR III'),
    );
    expect(rig.session.looks.hasSlots, isFalse);
  });

  test("the library reads a photo's Image Control over Wi-Fi", () async {
    rig = await ShootRig.start(wifi: true);
    final library = rig.session.library!;
    final files = await library.listFiles();
    final still = files.firstWhere((f) => f.name == 'R0000231.JPG');
    final movie = files.firstWhere((f) => f.name.endsWith('.MOV'));

    final look = await library.imageControl(still);
    expect(look.base.known, BleImageControlBase.positiveFilm);
    await expectLater(
      library.imageControl(movie),
      throwsA(isA<GrApiException>()),
    );
  });
}
