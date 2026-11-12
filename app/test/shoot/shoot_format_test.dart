import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/shoot/shoot_format.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('readouts stay as the camera shows them', () {
    expect(settingLabel(en, 'av', '2.8'), 'f/2.8');
    expect(settingLabel(en, 'tv', '1.250'), '1/250');
    expect(settingLabel(en, 'tv', '3.10'), '0.3"');
    expect(settingLabel(en, 'sv', 'auto'), 'AUTO');
    expect(settingLabel(en, 'sv', '---'), '---');
    expect(settingLabel(en, 'xv', '0.0'), '±0.0');
  });

  test('menu names are messages', () {
    expect(settingLabel(en, 'meteringMode', 'spot'), 'Spot');
    expect(settingLabel(en, 'effect', 'efc_posiFilm'), 'Positive Film');
    expect(settingLabel(en, 'effect', 'efc_negaFilm'), 'Negative Film');
    expect(settingLabel(en, 'effect', 'efc_cineYellow'), 'Cinema (Yellow)');
    expect(settingLabel(en, 'effect', 'efc_cineGreen'), 'Cinema (Green)');
    expect(settingLabel(en, 'effect', 'efc_crossProcess'), 'Cross Processing');
    expect(settingLabel(en, 'effect', 'col_custom3'), 'Custom 3');
    expect(settingLabel(en, 'effect', 'unknown'), 'unknown');
    expect(ShootDrive.multipleExposure.label(en), 'Multi-exposure');
    expect(ShootTimer.off.label(en), 'Off');
    expect(ShootTimer.tenSeconds.label(en), '10 s');
  });
}
