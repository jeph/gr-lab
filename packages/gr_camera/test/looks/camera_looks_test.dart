import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

import '../shoot/rig.dart';

Look _held(ShootRig rig, int number) =>
    Look.fromBytes(Uint8List.fromList(rig.camera.lookSlot(number).data))!;

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
    await looks.readSlots();

    final slots = looks.slots!;
    expect([for (final s in slots) s.number], [1, 2, 3]);
    expect(
      [for (final s in slots) s.name],
      ['Tokyo Night', 'Daido', 'Soft Summer'],
    );
    final c1 = slots[0].look!;
    expect(c1.base, LookBase.positiveFilm);
    expect(c1.valueOf(LookParameter.saturation), 1);
    expect(c1.valueOf(LookParameter.key), -1);
    expect(c1.valueOf(LookParameter.grainStrength), 2);
    expect(c1.values, hasLength(12));
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
    final cine = Look.fromBytes(Uint8List.fromList(FakeLook.presets[3].data))!;

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
    final rebased = held.withBase(LookBase.highContrast);
    final fresh = Look.onBase(LookBase.standard, template: held);
    expect(rebased.values.length, greaterThan(held.values.length));
    expect(fresh.values.length, lessThan(held.values.length));

    final first = await looks.load(1, name: 'Rebased', look: rebased);
    final second = await looks.load(2, name: 'Fresh', look: fresh);

    expect(first.look!.sameAs(rebased), isTrue);
    expect(second.look!.sameAs(fresh), isTrue);
    expect(_held(rig, 1).sameAs(rebased), isTrue);
    expect(_held(rig, 2).sameAs(fresh), isTrue);
  });

  test('a blob the camera refuses leaves the slot as it was', () async {
    rig = await ShootRig.start();
    final looks = rig.session.looks;
    await looks.wake();
    final unsupported = Look.fromBytes(Uint8List.fromList([3, 0, 0x01, 0]))!;
    await expectLater(
      looks.load(1, name: 'Nope', look: unsupported),
      throwsA(isA<BleException>()),
    );
    expect(rig.camera.lookSlot(1).name, 'Tokyo Night');
  });

  test('a look on a base the camera does not offer is refused before '
      'anything is written', () async {
    rig = await ShootRig.start(
      config: const FakeCameraConfig(
        bonded: true,
        model: 'RICOH GR IV Monochrome',
      ),
    );
    final looks = rig.session.looks;
    await looks.wake();
    final positive = Look.fromBytes(
      Uint8List.fromList(FakeLook.presets[0].data),
    )!;
    final held = rig.camera.lookSlot(1).data;

    await expectLater(
      looks.load(1, name: 'Colour', look: positive),
      throwsA(
        isA<LookNotOffered>()
            .having((e) => e.base, 'base', LookBase.positiveFilm)
            .having((e) => e.model, 'model', GrModel.gr4Monochrome),
      ),
    );
    expect(rig.camera.lookSlot(1).data, held);
    expect(rig.camera.lookSlot(1).name, 'Tokyo Night');
    expect(rig.events('looks.load'), isEmpty);
    expect(rig.events('looks.refused').single, containsPair('slot', 1));

    final mono = await looks.load(
      1,
      name: 'Mono',
      look: positive.withBase(LookBase.standardMono),
    );
    expect(mono.look!.base, LookBase.standardMono);
  });

  test("the library reads a photo's Image Control over Wi-Fi", () async {
    rig = await ShootRig.start(wifi: true);
    final library = rig.session.library!;
    final files = await library.listFiles();
    final still = files.firstWhere((f) => f.name == 'R0000231.JPG');
    final movie = files.firstWhere((f) => f.name.endsWith('.MOV'));

    final look = await library.imageControl(still);
    expect(look.base, LookBase.positiveFilm);
    await expectLater(
      library.imageControl(movie),
      throwsA(isA<GrApiException>()),
    );
  });
}
