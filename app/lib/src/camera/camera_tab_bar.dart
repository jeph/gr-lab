import 'package:flutter/material.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/theme/tokens.dart';

/// The floating capsule switching the camera's pages (mock direction H,
/// `.tb`): the chosen page shows its icon and name on a filled pill, the
/// other its icon alone.
class CameraTabBar extends StatelessWidget {
  const new({required this.tab, required this.onSelect, super.key});

  static const double height = 56;

  final CameraTab tab;
  final ValueChanged<CameraTab> onSelect;

  static (IconData, String) _look(AppLocalizations l10n, CameraTab t) =>
      switch (t) {
        CameraTab.library => (Icons.grid_view_rounded, l10n.cameraBarLibrary),
        CameraTab.shoot => (Icons.camera_outlined, l10n.cameraBarShoot),
        CameraTab.looks => (Icons.tune_rounded, l10n.cameraBarLooks),
      };

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return Container(
      key: const Key('camera-tabs'),
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
      // The bar floats over the pages' Scaffolds; its own Material gives the
      // labels a text style.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in CameraTab.values)
              if (_look(l10n, t) case (final icon, final label))
                _Tab(
                  key: Key('camera-tab-${t.name}'),
                  icon: icon,
                  label: label,
                  selected: t == tab,
                  onTap: () => onSelect(t),
                ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
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
