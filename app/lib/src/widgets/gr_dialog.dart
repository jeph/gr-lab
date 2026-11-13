import 'package:flutter/material.dart';

import 'package:grphoto/src/theme/tokens.dart';

/// The space between two buttons of a [GrDialog].
const double _actionGap = 8;

/// The space a button of a [GrDialog] keeps on each side of its label.
const double _labelInset = 16;

/// How the buttons of a [GrDialog] write their labels. Whether two fit
/// side by side is measured with it, so the buttons use it as it is.
const _labelStyle = TextStyle(
  fontFamily: GrFonts.ui,
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

/// A question, a notice or a request for text, as a card in the middle of
/// the screen: the raised surface with a hairline edge, [title] and
/// [message] above [content], then [actions] as pill buttons of equal
/// width (direction A of `design/mockups/dialogs.html` in the local
/// research workspace, `../gr`). Where the screen is too short for it all,
/// what is above the buttons scrolls and the buttons stay in reach.
///
/// The last action is the answer and sits at the trailing edge. Where the
/// labels do not fit side by side, the buttons stack with the answer on
/// top.
class GrDialog extends StatelessWidget {
  const new({
    required this.title,
    required this.actions,
    super.key,
    this.message,
    this.content,
  });

  final String title;

  /// What [title] asks or says, at more length.
  final String? message;

  /// A control between the text and the buttons, such as a `GrTextField`.
  final Widget? content;

  /// The buttons in reading order, the answer last.
  final List<GrDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final message = this.message;
    final content = this.content;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 400),
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.s1,
            borderRadius: BorderRadius.circular(GrRadii.xl),
            border: Border.all(color: c.line2),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                blurRadius: 48,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Everything above the buttons scrolls where the screen is
              // too short for it: a long message, or a field above the
              // keyboard of a phone on its side. The padding is inside, so
              // the halo of a focused field is not cut off at the edges.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        namesRoute: true,
                        header: true,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.2,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            message,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.5,
                              color: c.t2,
                            ),
                          ),
                        ),
                      if (content != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: content,
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: _Actions(actions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The buttons of a [GrDialog]: a row of equal widths, or a column with
/// the answer on top where a label is wider than its share of the row.
class _Actions extends StatelessWidget {
  const new(this.actions);

  final List<GrDialogAction> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gaps = _actionGap * (actions.length - 1);
      final share =
          (constraints.maxWidth - gaps) / actions.length - 2 * _labelInset;
      final fit = actions.every((a) => _labelWidth(context, a.label) <= share);
      if (!fit) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _actionGap,
          children: actions.reversed.toList(),
        );
      }
      return Row(
        spacing: _actionGap,
        children: [for (final action in actions) Expanded(child: action)],
      );
    },
  );

  double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

enum _ActionRole { plain, answer, destructive }

/// A button of a [GrDialog]. The plain one leaves things as they are
/// (Cancel, Not now); [GrDialogAction.answer] does what the dialog is
/// about, in the accent; [GrDialogAction.destructive] does it where it
/// deletes something, tinted with the danger colour.
class GrDialogAction extends StatelessWidget {
  const new({required this.label, required this.onPressed, super.key})
    : _role = _ActionRole.plain;

  const new answer({required this.label, required this.onPressed, super.key})
    : _role = _ActionRole.answer;

  const new destructive({
    required this.label,
    required this.onPressed,
    super.key,
  }) : _role = _ActionRole.destructive;

  final String label;

  /// Null while the button cannot be used.
  final VoidCallback? onPressed;

  final _ActionRole _role;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    const padding = EdgeInsets.symmetric(horizontal: _labelInset);
    final text = Text(label, textAlign: TextAlign.center);
    return switch (_role) {
      _ActionRole.plain => OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: padding,
          textStyle: _labelStyle,
        ),
        onPressed: onPressed,
        child: text,
      ),
      _ActionRole.answer => FilledButton(
        style: FilledButton.styleFrom(padding: padding, textStyle: _labelStyle),
        onPressed: onPressed,
        child: text,
      ),
      _ActionRole.destructive => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Color.alphaBlend(
            c.danger.withValues(alpha: .13),
            c.s1,
          ),
          foregroundColor: c.danger,
          side: BorderSide(color: c.danger.withValues(alpha: .38)),
          padding: padding,
          textStyle: _labelStyle,
        ),
        onPressed: onPressed,
        child: text,
      ),
    };
  }
}
