import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/settings.dart';
import '../theme/tokens.dart';
import '../widgets/group.dart';

/// App settings (subset of mock `b-settings`): appearance, which halves of
/// RAW+JPEG pairs to download, powering the camera on when connecting, and
/// licenses.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const SectionLabel('Appearance'),
            _ThemeGroup(
              mode: settings.themeMode,
              onChanged: (m) => settings.themeMode = m,
            ),
            const SectionLabel('Downloads'),
            GroupBox(
              children: [
                GroupRow(
                  icon: Icons.copy_rounded,
                  title: 'RAW+JPEG photos',
                  trailing: _RawJpegSegments(
                    value: settings.rawJpeg,
                    onChanged: (v) => settings.rawJpeg = v,
                  ),
                ),
              ],
            ),
            const SectionLabel('Camera'),
            GroupBox(
              children: [
                GroupRow(
                  icon: Icons.power_settings_new_rounded,
                  title: 'Turn on when connecting',
                  subtitle: 'Wakes the camera over Bluetooth',
                  onTap: () => settings.powerOnWhenConnecting =
                      !settings.powerOnWhenConnecting,
                  trailing: Switch(
                    key: const ValueKey('setting-power-on'),
                    value: settings.powerOnWhenConnecting,
                    onChanged: (v) => settings.powerOnWhenConnecting = v,
                  ),
                ),
              ],
            ),
            const SectionLabel('About'),
            GroupBox(
              children: [
                GroupRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Licenses',
                  chevron: true,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'GR Lab',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeGroup extends StatelessWidget {
  const _ThemeGroup({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(GrRadii.lg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Theme',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (m, label) in const [
                (ThemeMode.system, 'Auto'),
                (ThemeMode.light, 'Light'),
                (ThemeMode.dark, 'Dark'),
              ]) ...[
                if (m != ThemeMode.system) const SizedBox(width: 8),
                Expanded(
                  child: _ThemeTile(
                    key: ValueKey('theme:${m.name}'),
                    mode: m,
                    label: label,
                    selected: mode == m,
                    onTap: () => onChanged(m),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A tiny Library drawn in the theme it selects; Auto is half light, half
/// dark (mock `.tpick`).
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    super.key,
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final preview = switch (mode) {
      ThemeMode.light => const _MiniLibrary(GrColors.light),
      ThemeMode.dark => const _MiniLibrary(GrColors.dark),
      ThemeMode.system => const Row(
        children: [
          Expanded(child: _MiniLibrary(GrColors.light, clipRight: true)),
          Expanded(child: _MiniLibrary(GrColors.dark, clipLeft: true)),
        ],
      ),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 56,
              clipBehavior: Clip.antiAlias,
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? c.accent : c.line2,
                  width: selected ? 2 : 1,
                ),
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: preview,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.t1 : c.t2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniLibrary extends StatelessWidget {
  const _MiniLibrary(
    this.colors, {
    this.clipLeft = false,
    this.clipRight = false,
  });

  final GrColors colors;
  final bool clipLeft;
  final bool clipRight;

  static const _photoTones = [
    Color(0xFF8A7A4E),
    Color(0xFF9C9C98),
    Color(0xFFA0705A),
  ];

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: colors.bg,
    child: ClipRect(
      child: OverflowBox(
        alignment: clipLeft
            ? Alignment.centerRight
            : clipRight
            ? Alignment.centerLeft
            : Alignment.center,
        maxWidth: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.t1,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tone in _photoTones) ...[
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: tone,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// JPEG / RAW / Both segmented control (mock `.mseg`).
class _RawJpegSegments extends StatelessWidget {
  const _RawJpegSegments({required this.value, required this.onChanged});

  final RawJpegChoice value;
  final ValueChanged<RawJpegChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in const [
            (RawJpegChoice.jpeg, 'JPEG'),
            (RawJpegChoice.raw, 'RAW'),
            (RawJpegChoice.both, 'Both'),
          ])
            Semantics(
              button: true,
              selected: v == value,
              child: GestureDetector(
                key: ValueKey('raw-jpeg:${v.name}'),
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: v == value ? c.s1 : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: v == value
                        ? Border.all(color: c.line2)
                        : Border.all(color: Colors.transparent),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: v == value
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: v == value ? c.t1 : c.t2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
