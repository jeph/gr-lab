import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';
import 'package:grphoto/src/widgets/group.dart';
import 'package:grphoto/src/widgets/toast.dart';

/// Settings' Location group: Delete location history, the one history of
/// where the phone has been that background geotagging records for every
/// camera that has it on (the switch is in each camera's details).
class LocationGroup extends StatelessWidget {
  const new({required this.geotag, super.key});

  /// Holds the location history.
  final GeotagController geotag;

  Future<void> _delete(BuildContext context) async {
    final toasts = Toasts.of(context);
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GrDialog(
        title: l10n.settingsDeleteHistoryTitle,
        message: l10n.settingsDeleteHistoryBody,
        actions: [
          GrDialogAction(
            label: l10n.commonCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GrDialogAction.destructive(
            key: const Key('location-history-delete-confirm'),
            label: l10n.settingsDeleteHistoryConfirm,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await geotag.deleteHistory()) {
      toasts.done(l10n.settingsDeleteHistoryDone);
    } else {
      toasts.failed(l10n.settingsDeleteHistoryFailed);
    }
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
