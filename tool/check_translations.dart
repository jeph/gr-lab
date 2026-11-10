// GR Lab is translated into every language of the camera's menus (AGENTS.md,
// "Text the user sees"). gen-l10n shows the English text for a message a
// translation lacks and accepts a translation that drops a placeholder, so
// this fails when a translation in app/lib/l10n:
// - lacks a message of the template (app_en.arb), or has one it lacks;
// - names other placeholders than the template's message;
// - changes a plural or select: its argument, a select's cases, a plural
//   without `other`;
// - has another number of `<b>`/`</b>` tags or line breaks.
import 'dart:convert';
import 'dart:io';

const _template = 'app_en.arb';

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'app/lib/l10n' : args.first);
  final template = _messages(_read(File('${dir.path}/$_template')));
  final problems = <String>[];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb') && _name(f) != _template)
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = _name(file);
    final Map<String, Object?> arb;
    try {
      arb = _read(file);
    } on FormatException catch (e) {
      problems.add('$name: not valid JSON: ${e.message}');
      continue;
    }
    final locale = name.substring('app_'.length, name.length - '.arb'.length);
    if (arb['@@locale'] != locale) {
      problems.add('$name: "@@locale" must be "$locale"');
    }
    final translated = _messages(arb);
    for (final key in template.keys) {
      if (!translated.containsKey(key)) problems.add('$name: $key: missing');
    }
    for (final MapEntry(:key, :value) in translated.entries) {
      final source = template[key];
      if (source is! String) {
        problems.add('$name: $key: not in $_template');
      } else if (value is! String || value.trim().isEmpty) {
        problems.add('$name: $key: empty');
      } else {
        problems.addAll(
          _differences(source, value).map((d) => '$name: $key: $d'),
        );
      }
    }
  }
  if (problems.isEmpty) return;
  stderr
    ..writeln('translations must match app/lib/l10n/$_template (AGENTS.md):')
    ..writeAll(problems, '\n')
    ..writeln();
  exitCode = 1;
}

String _name(File file) => file.uri.pathSegments.last;

Map<String, Object?> _read(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

/// The entries of [arb] that are messages rather than `@` metadata.
Map<String, Object?> _messages(Map<String, Object?> arb) => {
  for (final MapEntry(:key, :value) in arb.entries)
    if (!key.startsWith('@')) key: value,
};

/// How the translation [value] departs from the structure of [source].
List<String> _differences(String source, String value) {
  final _Message want;
  final _Message got;
  try {
    want = _Parser(source).parse();
    got = _Parser(value).parse();
  } on FormatException catch (e) {
    return [e.message];
  }
  final differences = <String>[];
  final wantArguments = want.allArguments.toList()..sort();
  final gotArguments = got.allArguments.toList()..sort();
  if (wantArguments.join(',') != gotArguments.join(',')) {
    differences.add(
      'placeholders {${gotArguments.join('}, {')}} must be '
      '{${wantArguments.join('}, {')}}',
    );
  }
  String shape(_Message m) =>
      m.choices.map((c) => '${c.argument},${c.kind}').join(';');
  if (shape(want) != shape(got)) {
    differences.add('plurals and selects must be: ${shape(want)}');
    return differences;
  }
  for (var i = 0; i < want.choices.length; i++) {
    final wanted = want.choices[i];
    final cases = got.choices[i].cases.keys.toSet();
    if (wanted.kind == 'select') {
      final wantedCases = wanted.cases.keys.toSet();
      if (!cases.containsAll(wantedCases) || !wantedCases.containsAll(cases)) {
        differences.add('select cases must be: ${wantedCases.join(', ')}');
      }
      continue;
    }
    if (!cases.contains('other')) differences.add('plural needs "other"');
    final unknown = cases.where((c) => !_pluralCase.hasMatch(c));
    if (unknown.isNotEmpty) {
      differences.add('unknown plural cases: ${unknown.join(', ')}');
    }
  }
  for (final mark in ['<b>', '</b>', '\n']) {
    if (mark.allMatches(source).length != mark.allMatches(value).length) {
      differences.add(
        mark == '\n'
            ? 'must have as many line breaks'
            : 'must have as many $mark tags',
      );
    }
  }
  return differences;
}

final _pluralCase = RegExp(r'^(zero|one|two|few|many|other|=\d+)$');

/// What an ICU message asks of its translations: the arguments it names
/// and its plurals and selects.
final class _Message {
  final Set<String> arguments = {};
  final List<_Choice> choices = [];

  /// The arguments named anywhere in the message, the cases of its plurals
  /// and selects included.
  Set<String> get allArguments => {
    ...arguments,
    for (final choice in choices) ...[
      choice.argument,
      for (final message in choice.cases.values) ...message.allArguments,
    ],
  };
}

/// A plural or select.
final class _Choice {
  new(this.argument, this.kind);

  final String argument;

  /// `plural` or `select`.
  final String kind;
  final Map<String, _Message> cases = {};
}

/// Reads the subset of ICU message syntax that gen-l10n takes: `{name}`,
/// `{name, plural, case{…}}` and `{name, select, case{…}}`.
final class _Parser {
  new(this._text);

  final String _text;
  int _at = 0;

  static final _argument = RegExp(r'\s*(\w+)\s*');
  static final _kind = RegExp(r',\s*(plural|select)\s*,');
  static final _case = RegExp(r'\s*(=\d+|\w+)\s*\{');
  static final _space = RegExp(r'\s*');

  _Message parse() => _message(nested: false);

  _Message _message({required bool nested}) {
    final message = _Message();
    while (_at < _text.length) {
      final char = _text[_at++];
      if (char == '}') {
        if (!nested) throw FormatException('unmatched } at ${_at - 1}');
        return message;
      }
      if (char != '{') continue;
      final argument = _expect(_argument, 'a placeholder name');
      if (_at < _text.length && _text[_at] == '}') {
        _at++;
        message.arguments.add(argument);
        continue;
      }
      final choice = _Choice(argument, _expect(_kind, 'plural or select'));
      while (true) {
        _at = _space.matchAsPrefix(_text, _at)!.end;
        if (_at >= _text.length) throw const FormatException('unclosed {');
        if (_text[_at] == '}') break;
        final name = _expect(_case, 'a plural or select case');
        choice.cases[name] = _message(nested: true);
      }
      _at++;
      message.choices.add(choice);
    }
    if (nested) throw const FormatException('unclosed {');
    return message;
  }

  /// The first group of [pattern] at the current position, moving past it.
  String _expect(RegExp pattern, String what) {
    final match = pattern.matchAsPrefix(_text, _at);
    if (match == null) throw FormatException('expected $what at $_at');
    _at = match.end;
    return match[1]!;
  }
}
