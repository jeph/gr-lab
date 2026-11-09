import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/settings/debug_log_group.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// App settings (subset of mock `b-settings`): appearance, leaving the
/// camera's Wi-Fi when the app is not used, the debug log, and licenses.
class SettingsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    final settings = models.settings;
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
            const SectionLabel('Camera'),
            GroupBox(
              children: [
                GroupRow(
                  key: const Key('setting-auto-disconnect'),
                  icon: Icons.timer_outlined,
                  title: 'Auto-disconnect',
                  subtitle: "Leaves the camera's Wi-Fi when GR Lab isn't used",
                  trailing: TrailingFit.value(
                    context,
                    settings.autoDisconnect.label,
                  ),
                  chevron: true,
                  onTap: () => unawaited(_chooseAutoDisconnect(context)),
                ),
              ],
            ),
            const SectionLabel('Debug log'),
            DebugLogGroup(log: models.debugLog),
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

Future<void> _chooseAutoDisconnect(BuildContext context) {
  final settings = AppScope.of(context).settings;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Disconnect Wi-Fi after'),
            GroupBox(
              children: [
                for (final choice in AutoDisconnect.values)
                  GroupRow(
                    key: ValueKey('auto-disconnect:${choice.name}'),
                    title: choice.label,
                    trailing: choice == settings.autoDisconnect
                        ? Icon(
                            Icons.check_rounded,
                            color: GrColors.of(context).accent,
                          )
                        : null,
                    onTap: () {
                      settings.autoDisconnect = choice;
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ThemeGroup extends StatelessWidget {
  const new({required this.mode, required this.onChanged});

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
  const new({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
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
  const new(this.colors, {this.clipLeft = false, this.clipRight = false});

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
