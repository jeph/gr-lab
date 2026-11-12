import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/widgets/group.dart';

/// Where a row's button starts: under its title, past the icon tile.
const _underTitle = EdgeInsets.fromLTRB(60, 0, 14, 12);

/// What the Geotagging row says of [status]. While [live] is off it says
/// Off, whatever the camera layer still reports, or what is missing when
/// the user turned it on and [refused] the phone's location.
String geotagStatusText(
  AppLocalizations l10n,
  GeotagStatus status, {
  required bool live,
  bool refused = false,
}) {
  if (!live) {
    return refused ? l10n.geotagStatusNeedsLocation : l10n.geotagStatusOff;
  }
  return switch (status) {
    GeotagStatus.off => l10n.geotagStatusOff,
    GeotagStatus.unsupported => l10n.geotagStatusUnsupported,
    GeotagStatus.needsLocation => l10n.geotagStatusNeedsLocation,
    GeotagStatus.needsPreciseLocation => l10n.geotagStatusNeedsPreciseLocation,
    GeotagStatus.locationOff => l10n.geotagStatusLocationOff,
    GeotagStatus.waitingForCamera => l10n.geotagStatusWaitingForCamera,
    GeotagStatus.offOnCamera => l10n.geotagStatusOffOnCamera,
    GeotagStatus.needsApp => l10n.geotagStatusStarting,
    GeotagStatus.stopped => l10n.geotagStatusStopped,
    GeotagStatus.waitingForLocation => l10n.geotagStatusWaitingForLocation,
    GeotagStatus.sending => l10n.geotagStatusSending,
  };
}

/// What the Geotagging row's button does.
enum _Fix {
  /// Opens the system settings where location is allowed.
  openSettings,

  /// Turns the camera's Store Location Info on.
  turnOnCamera,
}

/// The camera sheet's Geotagging row: a switch for live geotagging, where
/// it stands, and a button for what only the user can put right (location
/// not allowed on the phone, or Store Location Info off on the camera).
///
/// The button goes under the status rather than beside the switch: the two
/// together leave the title no room at large text sizes. \[design\]
class GeotagRow extends StatelessWidget {
  const new({
    required this.live,
    required this.status,
    required this.onChanged,
    required this.onOpenSettings,
    required this.onTurnOnCamera,
    this.refused = false,
    super.key,
  });

  /// Live geotagging is turned on for the camera.
  final bool live;

  /// The user turned it on and refused the phone's location, so it is off.
  final bool refused;
  final GeotagStatus status;

  /// The user turned live geotagging on or off.
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onTurnOnCamera;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fix = !live
        ? (refused ? _Fix.openSettings : null)
        : switch (status) {
            GeotagStatus.needsLocation ||
            GeotagStatus.needsPreciseLocation ||
            GeotagStatus.locationOff => _Fix.openSettings,
            GeotagStatus.offOnCamera => _Fix.turnOnCamera,
            _ => null,
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupRow(
          icon: Icons.location_on_outlined,
          title: l10n.geotagLive,
          subtitle: geotagStatusText(
            l10n,
            status,
            live: live,
            refused: refused,
          ),
          trailing: Switch(
            key: const Key('camera-sheet-geotag-switch'),
            value: live,
            onChanged: onChanged,
          ),
          onTap: () => onChanged(!live),
        ),
        if (fix != null)
          Padding(
            padding: _underTitle,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: switch (fix) {
                _Fix.openSettings => OutlinedButton(
                  key: const Key('camera-sheet-geotag-settings'),
                  style: smallOutlinedStyle,
                  onPressed: onOpenSettings,
                  child: Text(l10n.geotagOpenSettings),
                ),
                _Fix.turnOnCamera => OutlinedButton(
                  key: const Key('camera-sheet-geotag-turn-on'),
                  style: smallOutlinedStyle,
                  onPressed: onTurnOnCamera,
                  child: Text(l10n.geotagTurnOnCamera),
                ),
              },
            ),
          ),
      ],
    );
  }
}

/// The camera sheet's Sync time row: a switch for keeping the camera's
/// clock on the phone's time. Live geotagging keeps the clock in step
/// whatever the switch says, so while [live] is on the switch shows on and
/// cannot be changed.
class SyncTimeRow extends StatelessWidget {
  const new({
    required this.live,
    required this.syncTime,
    required this.onChanged,
    super.key,
  });

  /// Live geotagging is turned on for the camera.
  final bool live;

  /// The user's choice for the camera's clock.
  final bool syncTime;

  /// The user changed [syncTime].
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GroupRow(
      icon: Icons.schedule_rounded,
      title: l10n.geotagSyncTime,
      subtitle: live
          ? l10n.geotagSyncTimeWithLive
          : l10n.geotagSyncTimeSubtitle,
      trailing: Switch(
        key: const Key('camera-sheet-sync-time-switch'),
        value: live || syncTime,
        onChanged: live ? null : onChanged,
      ),
      onTap: live ? null : () => onChanged(!syncTime),
    );
  }
}
