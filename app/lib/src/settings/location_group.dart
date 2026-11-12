import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';
import 'package:grphoto/src/geotag/geotag_text.dart';
import 'package:grphoto/src/pairing/pairing_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';

/// Settings' Location group: the Background geotagging switch, what keeps
/// it from recording (a refusal when it was turned on, or a permission
/// taken away since, which leaves it on and paused) with a button to the
/// phone's settings, and Delete location history. Turning the switch on
/// first explains the two ways of geotagging and what each costs, before
/// the phone asks for location at all times.
class LocationGroup extends StatefulWidget {
  const new({required this.geotag, super.key});

  /// Runs background geotagging and holds the location history.
  final GeotagController geotag;

  @override
  State<LocationGroup> createState() => _LocationGroupState();
}

class _LocationGroupState extends State<LocationGroup> {
  GeotagController get _geotag => widget.geotag;

  /// The phone is being asked; the switch waits.
  bool _asking = false;

  /// Why the phone refused to turn background geotagging on, until its
  /// access changes.
  ({GeotagNeed need, LocationAccess access})? _refused;

  Future<void> _set({required bool on}) async {
    if (_asking) return;
    if (!on) {
      setState(() => _refused = null);
      await _geotag.turnBackgroundOff();
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => const _ExplainDialog(),
    );
    if (go != true || !mounted) return;
    setState(() {
      _asking = true;
      _refused = null;
    });
    final need = await _geotag.turnBackgroundOn();
    if (!mounted) return;
    setState(() {
      _asking = false;
      _refused = need == null ? null : (need: need, access: _geotag.access);
    });
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDeleteHistoryTitle),
        content: Text(l10n.settingsDeleteHistoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('location-history-delete-confirm'),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsDeleteHistoryConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await _geotag.deleteHistory();
    // The screen may have closed meanwhile.
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? l10n.settingsDeleteHistoryDone
                : l10n.settingsDeleteHistoryFailed,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _geotag,
    builder: (context, _) {
      final l10n = context.l10n;
      final c = GrColors.of(context);
      final on = _geotag.settings.backgroundGeotagging;
      final paused = _geotag.backgroundPausedBy;
      final refused = _refused;
      final need =
          paused ??
          (refused != null && refused.access == _geotag.access
              ? refused.need
              : null);
      final days = GeotagController.historyKept.inDays;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GroupBox(
            children: [
              GroupRow(
                key: const Key('setting-background-geotag'),
                icon: Icons.share_location_rounded,
                title: l10n.settingsBackgroundGeotagging,
                subtitle: !on
                    ? l10n.settingsBackgroundGeotaggingOff
                    : paused != null
                    ? l10n.settingsBackgroundGeotaggingPaused
                    : l10n.settingsBackgroundGeotaggingOn,
                trailing: Switch(
                  key: const Key('setting-background-geotag-switch'),
                  value: on,
                  onChanged: _asking ? null : (on) => unawaited(_set(on: on)),
                ),
                onTap: _asking ? null : () => unawaited(_set(on: !on)),
              ),
              if (need != null)
                GroupRow(
                  key: const Key('setting-background-geotag-need'),
                  icon: Icons.error_outline_rounded,
                  title: geotagNeedText(l10n, need),
                  trailing: TrailingFit(
                    child: OutlinedButton(
                      key: const Key('setting-background-geotag-settings'),
                      style: smallOutlinedStyle,
                      onPressed: () => unawaited(_geotag.openSettings(need)),
                      child: Text(l10n.geotagOpenSettings),
                    ),
                  ),
                ),
              GroupRow(
                key: const Key('setting-location-history-delete'),
                icon: Icons.delete_outline_rounded,
                title: l10n.settingsDeleteHistory,
                onTap: () => unawaited(_delete()),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: Text(
              [
                l10n.settingsBackgroundExplain90Days(days),
                l10n.settingsBackgroundExplainLiveWins,
              ].join('\n\n'),
              key: const Key('setting-background-geotag-note'),
              style: TextStyle(fontSize: 12.5, color: c.t2),
            ),
          ),
        ],
      );
    },
  );
}

/// What live and background geotagging each do and cost, shown before the
/// phone asks for location at all times. Pops true for Continue and false
/// for Not now.
class _ExplainDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final days = GeotagController.historyKept.inDays;
    return AlertDialog(
      key: const Key('background-geotag-explain'),
      title: Text(l10n.settingsBackgroundExplainTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Text(l10n.settingsBackgroundExplainLive),
            Text(l10n.settingsBackgroundExplainBackground(days)),
            Text(l10n.settingsBackgroundExplainLiveWins),
            Text(l10n.settingsBackgroundExplain90Days(days)),
            Text(l10n.settingsBackgroundExplainPrivate),
            Text(l10n.settingsBackgroundExplainAsk),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('background-geotag-later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsBackgroundNotNow),
        ),
        FilledButton(
          key: const Key('background-geotag-continue'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.settingsBackgroundContinue),
        ),
      ],
    );
  }
}
