import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:gr_camera/src/looks/look.dart';
import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';

Look _preset(int i) =>
    Look.fromBytes(Uint8List.fromList(FakeLook.presets[i].data))!;

/// Header `[version][byte 1][base][count]`, then `[id][value]` pairs.
Uint8List _bytes(List<int> header, List<int> parameters) =>
    Uint8List.fromList([...header, ...parameters]);

CameraBody _body(GrModel model) => CameraBody(model: model, firmware: '1.20');

void main() {
  test('a look reads its base and the parameters GR Photo knows, in the '
      'order it lists them', () {
    final look = Look.fromBytes(
      _bytes([1, 0, 0x06], [3, 0x02, 0xff, 0x00, 0x01, 0x17, 0x02]),
    )!;
    expect(look.base, LookBase.positiveFilm);
    expect(look.unknownBaseNumber, isNull);
    expect(look.values, {
      LookParameter.key: -1,
      LookParameter.saturation: 1,
      LookParameter.grainStrength: 2,
    });
    expect(look.values.keys.first, LookParameter.key, reason: 'look order');
    expect(look.valueOf(LookParameter.hue), isNull);
  });

  test('a look writes the header, each parameter, then zeros up to the '
      "slot's 56 bytes", () {
    final look = Look.fromBytes(_bytes([2, 5, 0x00, 1], [0x03, 0xfe]))!;
    expect(look.toBytes(), [
      2, 5, 0x00, 1, 0x03, 0xfe, //
      ...List.filled(50, 0),
    ]);
  });

  test('a camera look with a base, parameter and header GR Photo does not '
      'know writes back unchanged', () {
    final wire = Uint8List.fromList([
      4, 9, 0x7a, 3, 0x02, 0x01, 0x6f, 0x05, 0x14, 0xfd, //
      ...List.filled(46, 0),
    ]);
    final look = Look.fromBytes(wire)!;
    expect(look.base, isNull);
    expect(look.unknownBaseNumber, 0x7a);
    expect(look.values, {LookParameter.key: 1, LookParameter.clarity: -3});
    expect(look.toBytes(), wire);
    expect(look.withValue(LookParameter.key, 2).toBytes(), [
      4,
      9,
      0x7a,
      3,
      0x02,
      0x02,
      0x6f,
      0x05,
      0x14,
      0xfd,
      ...wire.skip(10),
    ], reason: 'an edit keeps what GR Photo does not know');
  });

  test('a look saved shorter, before looks were padded, still reads and '
      'writes back padded', () {
    final saved = _bytes([1, 0, 0x01, 1], [0x00, 0x02]);
    final look = Look.fromBytes(saved)!;
    expect(look.base, LookBase.vivid);
    expect(look.valueOf(LookParameter.saturation), 2);
    expect(look.toBytes(), [...saved, ...List.filled(50, 0)]);
    expect(Look.fromBytes(Uint8List.fromList([1, 0, 0x01])), isNull);
  });

  test('a new base keeps the values both bases share, drops the rest and '
      'starts the others in range', () {
    final positive = _preset(0).withValue(LookParameter.sharpness, 3);
    final bleach = positive.withBase(LookBase.bleachBypass);

    expect(bleach.base, LookBase.bleachBypass);
    expect(bleach.blob.version, positive.blob.version);
    expect(bleach.blob.reserved, positive.blob.reserved);
    expect(bleach.values, {
      LookParameter.saturation: 1,
      LookParameter.hue: 0,
      LookParameter.key: -1,
      LookParameter.contrast: 0,
      LookParameter.contrastHigh: 0,
      LookParameter.contrastLow: 0,
      LookParameter.sharpness: 3,
      // Bleach-bypass toning has no 0 on the camera: Normal is 1.
      LookParameter.toningBleachBypass: 1,
      LookParameter.shading: 0,
      LookParameter.clarity: 0,
    });
    expect(
      [for (final e in bleach.blob.parameters) e.parameter.raw],
      [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x09, 0x13, 0x14],
      reason: 'wire-id order',
    );
  });

  test('a filter base carries the custom filter bytes', () {
    final mono = _preset(4).withBase(LookBase.monotone);
    expect(mono.valueOf(LookParameter.filterEffectBlueLow), 0);
    expect(mono.valueOf(LookParameter.saturation), isNull);
  });

  test('a new look copies the header of a camera look and starts every '
      'parameter in range', () {
    final template = Look.fromBytes(_bytes([4, 7, 0x00, 0], []))!;
    final hdr = Look.onBase(LookBase.hdrTone, template: template);
    expect(hdr.toBytes().take(4), [4, 7, 0x09, 4]);
    expect(hdr.values, {
      LookParameter.saturation: 0,
      LookParameter.hue: 0,
      LookParameter.toningHdr: 0,
      LookParameter.hdrStrength: 1,
    });
  });

  test("a new look with no camera look to copy takes GR WORLD's fallback "
      'header', () {
    final fresh = Look.onBase(LookBase.vivid);
    expect(fresh.toBytes().take(4), [1, 0, 0x01, fresh.values.length]);
  });

  test('a value is set in place, or added when the look lacks it', () {
    final look = _preset(0);
    final keyed = look.withValue(LookParameter.key, 2);
    expect(keyed.values.keys.toList().indexOf(LookParameter.key), 2);
    expect(keyed.valueOf(LookParameter.key), 2);
    expect(keyed.values, hasLength(look.values.length));

    final toned = look.withValue(LookParameter.toningRetro, -3);
    expect(toned.values.keys.last, LookParameter.toningRetro);
    expect(toned.valueOf(LookParameter.toningRetro), -3);
  });

  test('looks have equal settings whatever their header, parameter order '
      'and padding', () {
    final look = _preset(2);
    final shuffled = lookOf(
      BleImageControlBlob(
        version: 4,
        reserved: look.blob.reserved + 1,
        base: look.blob.base,
        parameters: look.blob.parameters.reversed.toList(),
      ),
    );
    expect(shuffled.settings, look.settings);
    expect(shuffled.settings.hashCode, look.settings.hashCode);
    expect({look.settings, shuffled.settings}, hasLength(1));

    final unpadded = _bytes([1, 0, 0x01, 2], [0x00, 0x02, 0x02, 0xff]);
    expect(
      Look.fromBytes(unpadded)!.settings,
      Look.fromBytes(Uint8List.fromList([...unpadded, ...List.filled(48, 0)]))!
          .settings,
    );
  });

  test('looks with another base, value or set of parameters have '
      'different settings', () {
    final look = _preset(2);
    expect(look.withValue(LookParameter.hue, 0).settings, isNot(look.settings));
    expect(look.withBase(LookBase.positiveFilm).settings, isNot(look.settings));
    expect(
      lookOf(
        BleImageControlBlob(
          version: look.blob.version,
          reserved: look.blob.reserved,
          base: look.blob.base,
          parameters: look.blob.parameters.skip(1).toList(),
        ),
      ).settings,
      isNot(look.settings),
      reason: 'a missing parameter is not its initial value',
    );
  });

  test('settings compare a base and parameters GR Photo does not know, and '
      'take the first value of a parameter listed twice', () {
    Look read(List<int> header, List<int> parameters) =>
        Look.fromBytes(_bytes(header, parameters))!;
    final unknown = read([4, 0, 0x7a, 2], [0x6f, 0x05, 0x02, 0x01]);
    expect(
      read([1, 9, 0x7a, 2], [0x02, 0x01, 0x6f, 0x05]).settings,
      unknown.settings,
    );
    expect(
      read([4, 0, 0x7a, 2], [0x6f, 0x06, 0x02, 0x01]).settings,
      isNot(unknown.settings),
      reason: 'an unknown parameter with another value',
    );
    expect(
      read([4, 0, 0x7b, 2], [0x6f, 0x05, 0x02, 0x01]).settings,
      isNot(unknown.settings),
      reason: 'another unknown base',
    );

    final twice = read([1, 0, 0x00, 2], [0x02, 0x01, 0x02, 0x03]);
    expect(twice.valueOf(LookParameter.key), 1);
    expect(twice.settings, read([1, 0, 0x00, 1], [0x02, 0x01]).settings);
    expect(twice.settings, isNot(read([1, 0, 0x00, 1], [0x02, 0x03]).settings));
  });

  test('the GR IV Monochrome offers the monochrome bases GR WORLD gives it, '
      'the GR IV the colour ones', () {
    final mono = _body(GrModel.gr4Monochrome);
    final gr4 = _body(GrModel.gr4);
    expect(
      lookBases(mono),
      containsAllInOrder([LookBase.standardMono, LookBase.solarization]),
    );
    expect(
      lookBases(mono),
      isNot(contains(LookBase.pictorialist)),
      reason: 'GR WORLD gives Pictorialist to the GR IVx Monochrome only',
    );
    expect(lookBases(mono), isNot(contains(LookBase.vivid)));
    expect(
      lookBases(gr4),
      containsAllInOrder([LookBase.standard, LookBase.crossProcess]),
    );
    expect(lookBases(gr4), hasLength(14));
    expect(lookBases(gr4), isNot(contains(LookBase.standardMono)));
    expect(lookBases(_body(GrModel.gr4x)), isNot(contains(LookBase.palette)));
  });

  test('a look edited away from a camera keeps to the bases of the bodies '
      'that offer its base', () {
    final mono = lookBases(_body(GrModel.gr4Monochrome));
    final colour = lookBases(_body(GrModel.gr4));
    expect(lookBasesWith(LookBase.solid), mono);
    expect(lookBasesWith(LookBase.vivid), colour);
    expect(lookBasesWith(LookBase.pictorialist), colour);
    expect(lookBasesWith(null), colour);
  });

  test("a look is offered by a body whose bases include the look's", () {
    final positive = _preset(0);
    expect(positive.offeredBy(_body(GrModel.gr4)), isTrue);
    expect(positive.offeredBy(_body(GrModel.gr4Monochrome)), isFalse);
    final solid = positive.withBase(LookBase.solid);
    expect(solid.offeredBy(_body(GrModel.gr4Monochrome)), isTrue);
    expect(solid.offeredBy(_body(GrModel.gr4Hdf)), isFalse);
    final unknown = Look.fromBytes(_bytes([1, 0, 0x7a, 0], []))!;
    expect(unknown.offeredBy(_body(GrModel.gr4)), isFalse);
  });

  test('a choice range covers its named values up to the last one, and '
      'every value it holds has a name', () {
    for (final p in LookParameter.values) {
      final range = lookRange(p, null);
      final choices = lookChoices(p);
      if (range?.kind != LookValueKind.choice) {
        expect(
          range == null || choices == null,
          isTrue,
          reason: '$p: a number has no names',
        );
        continue;
      }
      expect(choices, isNotNull, reason: '$p');
      expect(range!.min, greaterThanOrEqualTo(0), reason: '$p');
      expect(range.max, choices!.length - 1, reason: '$p');
      for (final v in range.values) {
        expect(choices[v], isNotNull, reason: '$p $v');
      }
    }
    // Named, but its custom filters' values are unknown, so not editable.
    expect(lookChoices(LookParameter.filterEffect), [
      LookChoice.off,
      LookChoice.customFilter1,
      LookChoice.customFilter2,
      LookChoice.customFilter3,
      LookChoice.customFilter4,
    ]);
    expect(lookRange(LookParameter.filterEffect, null), isNull);
    // GR WORLD names Off, but the camera starts these at 1.
    for (final p in [
      LookParameter.toningBleachBypass,
      LookParameter.hdrStrength,
    ]) {
      expect(lookChoices(p)?.first, LookChoice.off);
      expect(lookRange(p, null)!.values, [1, 2, 3]);
    }
  });

  test("the Monochrome's HDR Tone has no Black & White toning, which the "
      'camera refuses on it, so a look moved there does not keep it', () {
    const toning = LookParameter.toningHdr;
    expect(lookRange(toning, LookBase.hdrTone)!.values, [0, 1, 2]);
    expect(lookRange(toning, LookBase.hdrMono)!.values, [0, 2]);

    final blackAndWhite = Look.onBase(LookBase.hdrTone).withValue(toning, 1);
    expect(blackAndWhite.withBase(LookBase.hdrMono).valueOf(toning), 0);
    final sepia = blackAndWhite.withValue(toning, 2);
    expect(sepia.withBase(LookBase.hdrMono).valueOf(toning), 2);
  });

  test('the Solarization Type runs from Type 1 to Type 3, and a look that '
      'gains it starts on Type 1', () {
    const type = LookParameter.solarizationType;
    expect(lookRange(type, LookBase.solarization)!.values, [1, 2, 3]);
    expect(lookChoices(type), [
      null,
      LookChoice.type1,
      LookChoice.type2,
      LookChoice.type3,
    ]);

    expect(Look.onBase(LookBase.solarization).valueOf(type), 1);
    final moved = Look.onBase(LookBase.standardMono)
        .withBase(LookBase.solarization);
    expect(moved.valueOf(type), 1);
    final third = moved.withValue(type, 3);
    expect(third.withBase(LookBase.solarization).valueOf(type), 3);
  });
}
