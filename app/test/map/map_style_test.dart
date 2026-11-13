import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grphoto/src/map/map_style.dart';
import 'package:grphoto/src/theme/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the map style is a MapLibre style with every colour filled in from '
      'the theme, for each theme', () async {
    final template = await loadMapStyleTemplate();
    expect(template, contains('{{land}}'));
    for (final colors in [
      GrColors.dark,
      GrColors.light,
      GrColors.darkroom,
      GrColors.paper,
      GrColors.cyanotype,
    ]) {
      final style = mapStyle(template, colors);
      expect(style, isNot(contains('{{')));
      final json = jsonDecode(style) as Map<String, Object?>;
      expect(json['version'], 8);
      final layers = (json['layers']! as List).cast<Map<String, Object?>>();
      final background = layers.singleWhere((l) => l['type'] == 'background');
      final land = colors.s2.toARGB32() & 0xFFFFFF;
      expect(
        (background['paint']! as Map)['background-color'],
        '#${land.toRadixString(16).padLeft(6, '0')}',
      );
    }
  });
}
