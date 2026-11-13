import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';

/// Says why background geotagging needs location all the time, which
/// choice allows it and what the location history is used for, before
/// Android opens GR Photo's location settings for it: that page says
/// nothing about why it opened. Pops true for Open settings and false for
/// Not now.
///
/// Android only. iOS asks in an alert of its own over the app, which shows
/// GR Photo's reason, so it names no [choice] and this is never shown
/// there (`PhoneLocation.alwaysSettingsChoice`).
class AlwaysLocationDialog extends StatelessWidget {
  const new({required this.choice, super.key});

  /// The choice that allows location all the time, as the phone's settings
  /// word it.
  final String choice;

  /// Shows the dialog; true when the user wants the settings opened.
  static Future<bool> show(BuildContext context, String choice) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlwaysLocationDialog(choice: choice),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GrDialog(
      key: const Key('always-location'),
      title: l10n.geotagAlwaysTitle,
      message: l10n.geotagAlwaysBody(choice),
      actions: [
        GrDialogAction(
          key: const Key('always-location-later'),
          label: l10n.geotagAlwaysNotNow,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        GrDialogAction.answer(
          key: const Key('always-location-settings'),
          label: l10n.geotagOpenSettings,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
