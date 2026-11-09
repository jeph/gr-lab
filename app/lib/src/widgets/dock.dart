import 'package:flutter/material.dart';

import 'package:grlab/src/theme/tokens.dart';

/// One page a [Dock] switches to.
@immutable
final class DockItem<T> {
  const new(this.value, {required this.icon, required this.label, this.key});

  final T value;
  final IconData icon;
  final String label;

  /// The key of the item's button.
  final Key? key;
}

/// The floating capsule switching between pages (mock direction H, `.tb`):
/// the chosen page shows its icon and name on a filled pill, the others
/// their icon alone.
class Dock<T> extends StatelessWidget {
  const new({
    required this.items,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  static const double height = 56;

  final List<DockItem<T>> items;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.float,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: c.line2),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // The dock floats over the pages' Scaffolds; its own Material gives
      // the labels a text style.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              _DockButton(
                key: item.key,
                icon: item.icon,
                label: item.label,
                selected: item.value == selected,
                onTap: () => onSelect(item.value),
              ),
          ],
        ),
      ),
    );
  }
}

/// [child] with [dock] floating at the bottom. The pages keep their content
/// above the dock, and so do floating snack bars, which Scaffold places
/// above the view padding. Without a [dock] (Shoot's live view), [child]
/// gets the whole screen; it keeps its place in the tree either way, so
/// the pages keep their state when the dock comes and goes.
class DockLayout extends StatelessWidget {
  const new({required this.dock, required this.child, super.key});

  final Widget? dock;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dock = this.dock;
    final media = MediaQuery.of(context);
    const reserved = Dock.height + 8;
    return Stack(
      children: [
        MediaQuery(
          data: dock == null
              ? media
              : media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: media.padding.bottom + reserved,
                  ),
                  viewPadding: media.viewPadding.copyWith(
                    bottom: media.viewPadding.bottom + reserved,
                  ),
                ),
          child: child,
        ),
        if (dock != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: media.padding.bottom + 12,
            child: Center(child: dock),
          ),
      ],
    );
  }
}

class _DockButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final color = selected ? c.invFg : c.t2;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 44,
          padding: EdgeInsets.fromLTRB(
            selected ? 15 : 16,
            0,
            selected ? 18 : 16,
            0,
          ),
          decoration: BoxDecoration(
            color: selected ? c.invBg : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
