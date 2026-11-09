// Every text the app shows comes from app/lib/l10n (AGENTS.md, "Text the
// user sees"). Fails on string literals with words in them that are handed
// straight to a widget that shows text: `Text('…')`, `title: '…'`,
// `tooltip: '…'` and the like. It is a pattern check, not a full analysis,
// so it catches the common shapes rather than every one.
//
// A literal that must stay as it is (text from the camera, a brand name)
// carries `// not-translated: <why>` on the same line.
import 'dart:io';

/// Widgets whose first positional argument is shown as text.
final _positional = RegExp(
  r'''\b(?:Text|SelectableText|TextSpan|Tooltip)\(\s*(?:text:\s*)?(?:r?)(['"])((?:\\.|(?!\1).)*)\1''',
  dotAll: true,
);

/// Named arguments that are shown as text when given a string.
final _named = RegExp(
  r'''\b(?:title|subtitle|label|labelText|hintText|helperText|errorText|counterText|tooltip|semanticLabel|semanticsLabel|message|text|confirmText|cancelText|helpText)\s*:\s*(['"])((?:\\.|(?!\1).)*)\1''',
);

/// Interpolations are data; only the words around them are text.
final _interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');
final _word = RegExp('[A-Za-z]{2,}');

void main(List<String> args) {
  final root = args.isEmpty ? 'app/lib' : args.first;
  final hits = <String>[];
  for (final entity in Directory(root).listSync(recursive: true)) {
    final path = entity.path;
    if (entity is! File || !path.endsWith('.dart')) continue;
    if (path.contains('/l10n/') || path.contains('/src/demo/')) continue;
    hits.addAll(_scan(path, entity.readAsLinesSync()));
  }
  if (hits.isEmpty) return;
  stderr
    ..writeln('user-visible text must come from app/lib/l10n (AGENTS.md):')
    ..writeAll(hits, '\n')
    ..writeln();
  exitCode = 1;
}

Iterable<String> _scan(String path, List<String> lines) sync* {
  // Comments are blanked line by line so offsets still map to lines.
  final code = [
    for (final line in lines)
      if (line.trimLeft().startsWith('//')) '' else line,
  ].join('\n');
  for (final pattern in [_positional, _named]) {
    for (final m in pattern.allMatches(code)) {
      final literal = m.group(2)!;
      if (!_word.hasMatch(literal.replaceAll(_interpolation, ''))) continue;
      final lineIndex = '\n'.allMatches(code.substring(0, m.start)).length;
      final end = lineIndex + '\n'.allMatches(m.group(0)!).length;
      final span = lines.sublist(lineIndex, end + 1).join('\n');
      if (span.contains('// not-translated:')) continue;
      yield '$path:${lineIndex + 1}: ${literal.trim()}';
    }
  }
}
