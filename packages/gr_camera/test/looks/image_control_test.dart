import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';

BleImageControlBlob _preset(int i) =>
    imageControlFromBytes(Uint8List.fromList(FakeLook.presets[i].data))!;

Map<BleImageControlParameter?, int> _values(BleImageControlBlob look) => {
  for (final e in look.parameters) e.parameter.known: e.value,
};

void main() {
  test('a new base keeps the values both bases share, drops the rest and '
      'starts the others in range', () {
    final positive = _preset(0)
        .withValue(BleImageControlParameter.sharpness, 3);
    final bleach = positive.withBase(BleImageControlBase.bleachBypass);

    expect(bleach.base.known, BleImageControlBase.bleachBypass);
    expect(bleach.version, positive.version);
    expect(bleach.reserved, positive.reserved);
    expect(_values(bleach), {
      BleImageControlParameter.saturation: 1,
      BleImageControlParameter.hue: 0,
      BleImageControlParameter.key: -1,
      BleImageControlParameter.contrast: 0,
      BleImageControlParameter.contrastHigh: 0,
      BleImageControlParameter.contrastLow: 0,
      BleImageControlParameter.sharpness: 3,
      // Bleach-bypass toning has no 0 on the camera: Normal is 1.
      BleImageControlParameter.toningBleachBypass: 1,
      BleImageControlParameter.shading: 0,
      BleImageControlParameter.clarity: 0,
    });
    expect(
      [for (final e in bleach.parameters) e.parameter.raw],
      [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x09, 0x13, 0x14],
      reason: 'wire-id order',
    );
  });

  test('a filter base carries the custom filter bytes', () {
    final mono = _preset(4).withBase(BleImageControlBase.monotone);
    expect(mono.valueOf(BleImageControlParameter.filterEffectBlueLow), 0);
    expect(mono.valueOf(BleImageControlParameter.saturation), isNull);
  });

  test('a new look copies the header of a camera blob and starts every '
      'parameter in range', () {
    final template = BleImageControlBlob(
      version: 4,
      reserved: 7,
      base: BleEnumValue.of(BleImageControlBase.standard),
      parameters: const [],
    );
    final hdr = newImageControl(
      BleImageControlBase.hdrTone,
      template: template,
    );
    expect(hdr.version, 4);
    expect(hdr.reserved, 7);
    expect(_values(hdr), {
      BleImageControlParameter.saturation: 0,
      BleImageControlParameter.hue: 0,
      BleImageControlParameter.toningHdr: 0,
      BleImageControlParameter.hdrStrength: 1,
    });
  });

  test('a value is set in place, or added when the look lacks it', () {
    final look = _preset(0);
    final keyed = look.withValue(BleImageControlParameter.key, 2);
    expect(
      keyed.parameters.indexWhere(
        (e) => e.parameter.known == BleImageControlParameter.key,
      ),
      2,
    );
    expect(keyed.valueOf(BleImageControlParameter.key), 2);
    expect(keyed.parameters, hasLength(look.parameters.length));

    final toned = look.withValue(BleImageControlParameter.toningRetro, -3);
    expect(
      toned.parameters.last.parameter.known,
      BleImageControlParameter.toningRetro,
    );
    expect(toned.valueOf(BleImageControlParameter.toningRetro), -3);
  });

  test('the same look in another order or format version still matches', () {
    final look = _preset(2);
    final shuffled = BleImageControlBlob(
      version: 1,
      reserved: look.reserved,
      base: look.base,
      parameters: look.parameters.reversed.toList(),
    );
    expect(look.sameLookAs(shuffled), isTrue);
    expect(
      look.sameLookAs(look.withValue(BleImageControlParameter.hue, 0)),
      isFalse,
    );
    expect(
      look.sameLookAs(look.withBase(BleImageControlBase.positiveFilm)),
      isFalse,
    );
    expect(
      look.sameLookAs(
        BleImageControlBlob(
          version: look.version,
          reserved: look.reserved,
          base: look.base,
          parameters: look.parameters.skip(1).toList(),
        ),
      ),
      isFalse,
    );
  });

  test('the GR IV Monochrome offers the monochrome bases, the GR IV the '
      'colour ones', () {
    expect(
      imageControlBases(GrModel.gr4Monochrome),
      contains(BleImageControlBase.pictorialist),
    );
    expect(
      imageControlBases(GrModel.gr4Monochrome),
      isNot(contains(BleImageControlBase.vivid)),
    );
    expect(
      imageControlBases(GrModel.gr4),
      containsAllInOrder([
        BleImageControlBase.standard,
        BleImageControlBase.crossProcess,
      ]),
    );
    expect(
      imageControlBases(GrModel.gr4),
      isNot(contains(BleImageControlBase.standardMono)),
    );
  });
}
