import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/looks/look_spec.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/pressable.dart';

/// A look's base image in the look editor: [name] and its place among
/// [bases], between arrows that move the look to the base before and the
/// base after it, so bases can be tried one after another with the eyes on
/// the preview \[design\]. A tap on the name is [onList]'s, which lists
/// them all ([showLookBaseList]).
///
/// [selected] is null, or not one of [bases], for a base the camera does
/// not offer or GR Photo does not know: [name] then stands without a place,
/// and the arrow forward goes to the first of [bases].
class LookBaseStepper extends StatelessWidget {
  const new({
    required this.name,
    required this.bases,
    required this.selected,
    required this.onSelect,
    required this.onList,
    super.key,
  });

  final String name;
  final List<LookBase> bases;
  final LookBase? selected;
  final ValueChanged<LookBase> onSelect;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final selected = this.selected;
    final index = selected == null ? -1 : bases.indexOf(selected);
    final previous = index > 0 ? bases[index - 1] : null;
    final next = index + 1 < bases.length ? bases[index + 1] : null;
    final divider = VerticalDivider(width: 1, thickness: 1, color: c.line);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(GrRadii.md),
        border: Border.all(color: c.line),
      ),
      // As tall as the name and its place need at the phone's text size.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Arrow(
              key: const Key('look-base-previous'),
              icon: Icons.chevron_left_rounded,
              label: l10n.looksBasePrevious,
              onTap: previous == null ? null : () => onSelect(previous),
            ),
            divider,
            Expanded(
              child: Semantics(
                button: true,
                label: l10n.looksBaseImage,
                child: Pressable(
                  key: const Key('look-base-name'),
                  onTap: onList,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: c.t2,
                            ),
                          ],
                        ),
                        if (index >= 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              l10n.looksBasePosition(index + 1, bases.length),
                              style: GrFonts.monoStyle(context, size: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            divider,
            _Arrow(
              key: const Key('look-base-next'),
              icon: Icons.chevron_right_rounded,
              label: l10n.looksBaseNext,
              onTap: next == null ? null : () => onSelect(next),
            ),
          ],
        ),
      ),
    );
  }
}

/// An end of [LookBaseStepper]; without [onTap] there is no base that way.
class _Arrow extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: Pressable(
          onTap: onTap,
          child: SizedBox(
            width: 54,
            child: Icon(
              icon,
              size: 24,
              color: onTap == null ? c.t3.withValues(alpha: .5) : c.t1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists [bases] in a sheet, in two columns that read downwards in the
/// order of the camera's menu, with [selected] marked. Returns the one
/// tapped; null when the sheet is dismissed. Each has the swatch of its
/// colours ([swatchColors]) where swatches tell the bases apart: the
/// monochrome ones all share one.
Future<LookBase?> showLookBaseList(
  BuildContext context, {
  required List<LookBase> bases,
  required LookBase? selected,
}) => showModalBottomSheet<LookBase>(
  context: context,
  isScrollControlled: true,
  // A list taller than the screen scrolls below the status bar.
  useSafeArea: true,
  builder: (context) {
    final swatches = bases.any((b) => !isMonoBase(b));
    final firstColumn = (bases.length + 1) ~/ 2;
    Widget column(Iterable<LookBase> part) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          for (final b in part)
            _BaseCell(
              key: ValueKey('look-base:${b.name}'),
              base: b,
              selected: b == selected,
              swatch: swatches,
              onTap: () => Navigator.of(context).pop(b),
            ),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('look-base-list'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                context.l10n.looksBaseImage,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                column(bases.take(firstColumn)),
                column(bases.skip(firstColumn)),
              ],
            ),
          ],
        ),
      ),
    );
  },
);

/// One base image of [showLookBaseList].
class _BaseCell extends StatelessWidget {
  const new({
    required this.base,
    required this.selected,
    required this.swatch,
    required this.onTap,
    super.key,
  });

  final LookBase base;
  final bool selected;

  /// Whether the base's colours are shown before its name.
  final bool swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? c.invBg : c.s2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? Colors.transparent : c.line),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  if (swatch) ...[
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: swatchColors(base),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      baseLabel(context.l10n, base),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? c.invFg : c.t1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
