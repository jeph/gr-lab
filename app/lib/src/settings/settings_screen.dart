import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/settings/debug_log_group.dart';
import 'package:grlab/src/settings/privacy_policy_screen.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';
import 'package:grlab/src/widgets/pressable.dart';

/// App settings (subset of mock `b-settings`): appearance, leaving the
/// camera's Wi-Fi when the app is not used, the debug log, licenses and the
/// privacy policy.
class SettingsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    final settings = models.settings;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            SectionLabel(l10n.settingsAppearance),
            _ThemeGroup(
              theme: settings.theme,
              onChanged: (theme) => settings.theme = theme,
            ),
            SectionLabel(l10n.settingsCamera),
            GroupBox(
              children: [
                GroupRow(
                  key: const Key('setting-auto-disconnect'),
                  icon: Icons.timer_outlined,
                  title: l10n.settingsAutoDisconnect,
                  subtitle: l10n.settingsAutoDisconnectSubtitle,
                  trailing: TrailingFit.value(
                    context,
                    _autoDisconnectLabel(l10n, settings.autoDisconnect),
                  ),
                  chevron: true,
                  onTap: () => unawaited(_chooseAutoDisconnect(context)),
                ),
              ],
            ),
            SectionLabel(l10n.settingsDebugLog),
            DebugLogGroup(log: models.debugLog),
            SectionLabel(context.l10n.privacyAboutSection),
            GroupBox(
              children: [
                GroupRow(
                  icon: Icons.info_outline_rounded,
                  title: context.l10n.privacyLicensesRow,
                  chevron: true,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: context.l10n.appTitle,
                  ),
                ),
                GroupRow(
                  key: const Key('setting-privacy-policy'),
                  icon: Icons.privacy_tip_outlined,
                  title: context.l10n.privacyPolicyRow,
                  chevron: true,
                  onTap: () => unawaited(PrivacyPolicyScreen.push(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `5 min`, `Never`.
String _autoDisconnectLabel(AppLocalizations l10n, AutoDisconnect choice) =>
    switch (choice.after) {
      null => l10n.settingsAutoDisconnectNever,
      final after => l10n.settingsAutoDisconnectMinutes(after.inMinutes),
    };

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
            SectionLabel(context.l10n.settingsAutoDisconnectSheetTitle),
            GroupBox(
              children: [
                for (final choice in AutoDisconnect.values)
                  GroupRow(
                    key: ValueKey('auto-disconnect:${choice.name}'),
                    title: _autoDisconnectLabel(context.l10n, choice),
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
  const new({required this.theme, required this.onChanged});

  final AppTheme theme;
  final ValueChanged<AppTheme> onChanged;

  /// Auto with the two themes it follows, then the tinted themes.
  static const List<List<AppTheme>> _rows = [
    [AppTheme.system, AppTheme.light, AppTheme.dark],
    [AppTheme.darkroom, AppTheme.paper, AppTheme.cyanotype],
  ];

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
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
        spacing: 12,
        children: [
          Text(
            l10n.settingsTheme,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          for (final row in _rows)
            Row(
              spacing: 8,
              children: [
                for (final choice in row)
                  Expanded(
                    child: _ThemeTile(
                      key: ValueKey('theme:${choice.name}'),
                      theme: choice,
                      selected: theme == choice,
                      onTap: () => onChanged(choice),
                    ),
                  ),
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
    required this.theme,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final colors = theme.colors;
    final preview = colors == null
        ? const Row(
            children: [
              Expanded(child: _MiniLibrary(GrColors.light, clipRight: true)),
              Expanded(child: _MiniLibrary(GrColors.dark, clipLeft: true)),
            ],
          )
        : _MiniLibrary(colors);
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.settingsThemeSemantics(theme.name),
      child: Pressable(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              l10n.settingsThemeName(theme.name),
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
