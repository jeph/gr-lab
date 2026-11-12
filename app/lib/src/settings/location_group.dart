import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';

/// Settings' Location group: Delete location history, the one history of
/// where the phone has been that background geotagging records for every
/// camera that has it on (the switch is in each camera's details).
class LocationGroup extends StatelessWidget {
  const new({required this.geotag, super.key});

  /// Holds the location history.
  final GeotagController geotag;

  Future<void> _delete(BuildContext context) async {
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
    final deleted = await geotag.deleteHistory();
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
  Widget build(BuildContext context) => GroupBox(
    children: [
      GroupRow(
        key: const Key('setting-location-history-delete'),
        icon: Icons.delete_outline_rounded,
        title: context.l10n.settingsDeleteHistory,
        onTap: () => unawaited(_delete(context)),
      ),
    ],
  );
}
