import 'package:flutter/material.dart';

import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/pressable.dart';
import 'package:grphoto/src/widgets/toast.dart';
import 'package:grphoto/src/widgets/window_layout.dart';

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
/// their icon alone. In a window with a [VerticalBar] it stands upright in
/// that, as the system's own tab bar does there, and every page shows its
/// icon alone: the strip has no room for a name.
class Dock<T> extends StatelessWidget {
  const new({
    required this.items,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// How far the capsule reaches across its length: its height lying
  /// down, its width standing up.
  static const double height = 56;

  final List<DockItem<T>> items;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final upright = VerticalBar.of(context) != null;
    return Container(
      height: upright ? null : height,
      width: upright ? height : null,
      padding: const EdgeInsets.all(6),
      decoration: c.floating(radius: height / 2),
      // The dock floats over the pages' Scaffolds; its own Material gives
      // the labels a text style.
      child: Material(
        type: MaterialType.transparency,
        child: Flex(
          direction: upright ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              _DockButton(
                key: item.key,
                icon: item.icon,
                label: item.label,
                selected: item.value == selected,
                named: !upright,
                onTap: () => onSelect(item.value),
              ),
          ],
        ),
      ),
    );
  }
}

/// [child] with [dock] floating at the bottom. The pages keep their content
/// above the dock, and toasts float above it. In a window with a
/// [VerticalBar] the dock stands at the foot of that instead, beside the
/// pages, which then reach the bottom of the window. Without a [dock]
/// (Shoot's live view), [child] gets the whole screen; it keeps its place
/// in the tree either way, so the pages keep their state when the dock
/// comes and goes.
class DockLayout extends StatelessWidget {
  const new({required this.dock, required this.child, super.key});

  final Widget? dock;
  final Widget child;

  /// Under a dock that stands in the [VerticalBar], which the system's
  /// home indicator stays clear of \[design\].
  static const _uprightBottom = 16.0;

  @override
  Widget build(BuildContext context) {
    final dock = this.dock;
    final media = MediaQuery.of(context);
    final bar = VerticalBar.of(context);
    const reserved = Dock.height + 8;
    return Stack(
      children: [
        MediaQuery(
          data: dock == null || bar != null
              ? media
              : media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: media.padding.bottom + reserved,
                  ),
                ),
          child: child,
        ),
        if (dock != null && bar == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: media.padding.bottom + 12,
            child: Center(child: ToastFloor(child: dock)),
          ),
        // Beside the pages, so nothing floats above it: toasts keep to the
        // bottom of the window.
        if (dock != null && bar != null)
          Positioned(
            left: bar.side == BarSide.left ? 0 : null,
            right: bar.side == BarSide.right ? 0 : null,
            width: bar.width,
            bottom: _uprightBottom,
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
    required this.named,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// Whether the chosen page shows its name beside its icon.
  final bool named;
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
      child: Pressable(
        onTap: onTap,
        shape: const StadiumBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 44,
          padding: named
              ? EdgeInsets.fromLTRB(
                  selected ? 15 : 16,
                  0,
                  selected ? 18 : 16,
                  0,
                )
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: selected ? c.invBg : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            // Standing upright, the button is as wide as the dock.
            mainAxisSize: named ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: selected && named
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
