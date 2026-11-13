import 'package:flutter/services.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// The map's style with its colours left open: OpenFreeMap's Positron, in
/// which every colour is a name in double braces ([mapStyle] fills them
/// in). The asset bundle keeps it once read.
Future<String> loadMapStyleTemplate() =>
    rootBundle.loadString('assets/map/style.json');

/// [template] as a MapLibre style in the colours of the app's theme
/// \[design\]: the map is drawn on the theme's own surfaces, so that it is
/// one more card of the screen it is on rather than a picture from
/// elsewhere.
///
/// Positron is grey: water is darker than land, and roads are the lightest
/// thing on it. A light theme keeps that on its surfaces. A dark theme has
/// water as its darkest surface and land above it, and roads lighter than
/// both, since a dark map with roads darker than the land reads as a
/// negative.
String mapStyle(String template, GrColors colors) {
  final dark = colors.brightness == Brightness.dark;
  final land = colors.s2;
  final water = dark ? colors.bg : colors.s4;
  final palette = <String, Color>{
    'land': land,
    'water': water,
    'park': dark ? Color.lerp(colors.s1, colors.s2, 0.4)! : colors.s3,
    'building': dark ? colors.s3 : Color.lerp(colors.s2, colors.s3, 0.6)!,
    'casing': dark ? colors.s1 : colors.s4,
    'minor': dark ? colors.s4 : colors.s1,
    'major': dark ? Color.lerp(colors.s4, colors.t3, 0.55)! : colors.s1,
    'rail': colors.s4,
    'border': colors.s4,
    'text': colors.t2,
    'waterText': colors.t3,
  };
  var style = template;
  for (final MapEntry(key: name, value: color) in palette.entries) {
    style = style.replaceAll('{{$name}}', _hex(color));
  }
  return style;
}

/// [color] as `#rrggbb`: the theme's surfaces and text are opaque.
String _hex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}
