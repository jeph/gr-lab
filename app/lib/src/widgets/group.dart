import 'package:flutter/material.dart';

import 'package:grlab/src/theme/tokens.dart';

/// Uppercase label above a [GroupBox] (mock `.seclabel`).
class SectionLabel extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: .8,
        color: GrColors.of(context).t3,
      ),
    ),
  );
}

/// Rounded card of rows separated by hairlines (mock `.group`).
class GroupBox extends StatelessWidget {
  const new({required this.children, super.key, this.margin, this.color});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  /// Background; defaults to the raised surface (`s1`).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color ?? c.s1,
        borderRadius: BorderRadius.circular(GrRadii.lg),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row of a [GroupBox]: icon tile, title with optional subtitle, and a
/// trailing value or control (mock `.li`).
class GroupRow extends StatelessWidget {
  const new({
    required this.title,
    super.key,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
  });

  final String title;
  final IconData? icon;

  /// Replaces the icon tile (e.g. a step number).
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final lead =
        leading ??
        (icon == null
            ? null
            : Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.s3,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: c.t1),
              ));
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, color: c.t1)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12.5, color: c.t2),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
              if (chevron) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.t3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Filter chip with an optional monospace count (mock `.chip`).
class GrChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final fg = selected ? c.invFg : c.t1;
    return Material(
      color: selected ? c.invBg : c.s2,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? Colors.transparent : c.line),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  _formatCount(count!),
                  style: TextStyle(
                    fontFamily: GrFonts.mono,
                    fontSize: 11.5,
                    color: selected ? c.invFg2 : c.t3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `1234` → `1,234`.
String _formatCount(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
