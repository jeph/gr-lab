import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// GR Photo's privacy policy (Settings › About), rendered from the bundled
/// `assets/privacy.md`. The policy is the legal text and stays in English;
/// only the screen around it is translated.
class PrivacyPolicyScreen extends StatefulWidget {
  const new({super.key});

  /// The policy as Markdown, in the subset [PrivacyPolicyScreen] renders:
  /// `#` and `##` headings, paragraphs and `- ` bullets.
  static const asset = 'assets/privacy.md';

  static Future<void> push(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()));

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late final Future<List<_Block>> _blocks = DefaultAssetBundle.of(context)
      .loadString(PrivacyPolicyScreen.asset)
      .then(_parse);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.privacyPolicyTitle)),
    body: FutureBuilder(
      future: _blocks,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.l10n.privacyPolicyLoadFailed,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final blocks = snapshot.data;
        if (blocks == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return SelectionArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              22,
              8,
              22,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [for (final block in blocks) _BlockView(block)],
          ),
        );
      },
    ),
  );
}

enum _Kind { title, section, paragraph, bullet }

typedef _Block = ({_Kind kind, String text});

/// Splits [source] into blocks: a `# ` or `## ` line is a heading, a line
/// starting `- ` begins a bullet, and any other line begins a paragraph or
/// continues the paragraph or bullet above it. Blank lines end paragraphs
/// and bullets.
List<_Block> _parse(String source) {
  final blocks = <_Block>[];
  _Kind? openKind;
  final openLines = <String>[];

  void close() {
    final kind = openKind;
    if (kind == null) return;
    blocks.add((kind: kind, text: openLines.join(' ')));
    openKind = null;
    openLines.clear();
  }

  for (final rawLine in const LineSplitter().convert(source)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      close();
      continue;
    }
    final heading = switch (line) {
      _ when line.startsWith('# ') => _Kind.title,
      _ when line.startsWith('## ') => _Kind.section,
      _ => null,
    };
    if (heading != null) {
      close();
      blocks.add((kind: heading, text: line.substring(line.indexOf(' ') + 1)));
      continue;
    }
    if (line.startsWith('- ')) {
      close();
      openKind = _Kind.bullet;
      openLines.add(line.substring(2).trimLeft());
      continue;
    }
    openKind ??= _Kind.paragraph;
    openLines.add(line);
  }
  close();
  return blocks;
}

class _BlockView extends StatelessWidget {
  const new(this.block);

  final _Block block;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final body = TextStyle(fontSize: 15, height: 1.45, color: c.t1);
    return switch (block.kind) {
      _Kind.title => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Semantics(
          header: true,
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: c.t1,
            ),
          ),
        ),
      ),
      _Kind.section => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Semantics(
          header: true,
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.t1,
            ),
          ),
        ),
      ),
      _Kind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(block.text, style: body),
      ),
      _Kind.bullet => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•', style: body.copyWith(color: c.t2)),
            const SizedBox(width: 10),
            Expanded(child: Text(block.text, style: body)),
          ],
        ),
      ),
    };
  }
}
