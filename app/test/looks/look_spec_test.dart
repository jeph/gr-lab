import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/looks/look_spec.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final number = RegExp(r'^[+-]?\d+$');

  List<String> offered(LookParameter p) {
    final range = lookRange(p)!;
    return [for (var v = range.min; v <= range.max; v++) valueLabel(en, p, v)];
  }

  test('every value the editor offers for a choice has a name', () {
    for (final p in LookParameter.values) {
      if (lookRange(p)?.kind != LookValueKind.choice) continue;
      for (final label in offered(p)) {
        expect(label, isNot(matches(number)), reason: '$p');
      }
    }
  });

  test('names follow the wire value, and the editor skips Off where the '
      'camera starts at 1', () {
    const bleach = LookParameter.toningBleachBypass;
    expect(
      [for (var v = 0; v <= 3; v++) valueLabel(en, bleach, v)],
      ['Off', 'Normal', 'Cool', 'Warm'],
    );
    expect(offered(bleach), ['Normal', 'Cool', 'Warm']);
    expect(offered(LookParameter.hdrStrength), ['Low', 'Medium', 'High']);
    expect(valueLabel(en, LookParameter.filterEffect, 0), 'Off');
  });

  test('a value past the last name, or of a number, reads as the number', () {
    expect(valueLabel(en, LookParameter.toningMonotone, 6), '+6');
    expect(valueLabel(en, LookParameter.contrast, -2), '-2');
    expect(valueLabel(en, LookParameter.contrast, 0), '0');
  });
}
