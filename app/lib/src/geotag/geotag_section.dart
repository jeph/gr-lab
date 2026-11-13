import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';
import 'package:grphoto/src/geotag/geotag_text.dart';
import 'package:grphoto/src/geotag/geotagging_explained_screen.dart';
import 'package:grphoto/src/pairing/pairing_widgets.dart';
import 'package:grphoto/src/widgets/group.dart';

/// The Location and Clock sections of a camera's details. Location:
///
/// - Background geotagging: the switch for this camera, and under it what
///   keeps it from recording (a refusal when it was turned on, or a
///   permission taken away since, which leaves it on and paused) with a
///   button to the phone's settings.
/// - Learn more: what background geotagging does and keeps, on a screen
///   of its own ([GeotaggingExplainedScreen]).
///
/// Clock: Sync camera clock, on unless the user turns it off, and held on
/// while background geotagging is on ([SavedCamera.keepsClock]). Each
/// switch's line says what it does, whatever its state.
///
/// Live geotagging's switch is on the camera card (`LiveGeotagSwitch`).
class GeotagSection extends StatefulWidget {
  const new({required this.camera, super.key});

  /// The camera the section is about, as saved: the current one or not.
  final SavedCamera camera;

  @override
  State<GeotagSection> createState() => _GeotagSectionState();
}

class _GeotagSectionState extends State<GeotagSection> {
  late final GeotagController _geotag = AppScope.of(context).geotag;

  /// The phone is being asked; the switch waits.
  bool _asking = false;

  /// Why the phone refused to turn background geotagging on, until its
  /// access changes.
  ({GeotagNeed need, LocationAccess access})? _refused;

  String get _serial => widget.camera.serial;

  Future<void> _setBackground({required bool on}) async {
    if (_asking) return;
    if (!on) {
      setState(() => _refused = null);
      await _geotag.turnBackgroundOff(_serial);
      return;
    }
    setState(() {
      _asking = true;
      _refused = null;
    });
    final need = await _geotag.turnBackgroundOn(_serial);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _refused = need == null ? null : (need: need, access: _geotag.access);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _geotag,
    builder: (context, _) {
      final l10n = context.l10n;
      final background = widget.camera.backgroundGeotagging;
      final paused = _geotag.backgroundPausedBy(widget.camera);
      final refused = _refused;
      final need =
          paused ??
          (refused != null && refused.access == _geotag.access
              ? refused.need
              : null);
      return Column(
        key: const Key('camera-details-location'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(l10n.geotagSection),
          GroupBox(
            children: [
              GroupRow(
                key: const Key('camera-details-background'),
                icon: Icons.share_location_rounded,
                title: l10n.settingsBackgroundGeotagging,
                // What the setting does, whatever its state: the switch
                // says whether it is on.
                subtitle: l10n.settingsBackgroundGeotaggingSubtitle,
                trailing: Switch(
                  key: const Key('camera-details-background-switch'),
                  value: background,
                  onChanged: _asking
                      ? null
                      : (on) => unawaited(_setBackground(on: on)),
                ),
                onTap: _asking
                    ? null
                    : () => unawaited(_setBackground(on: !background)),
              ),
              if (need != null)
                GroupRow(
                  key: const Key('camera-details-background-need'),
                  icon: Icons.error_outline_rounded,
                  title: paused == null
                      ? geotagNeedText(l10n, need)
                      : l10n.settingsBackgroundGeotaggingPaused,
                  subtitle: paused == null
                      ? null
                      : geotagNeedText(l10n, paused),
                  trailing: TrailingFit(
                    child: OutlinedButton(
                      key: const Key('camera-details-background-settings'),
                      style: smallOutlinedStyle,
                      onPressed: () => unawaited(_geotag.openSettings(need)),
                      child: Text(l10n.geotagOpenSettings),
                    ),
                  ),
                ),
              GroupRow(
                key: const Key('camera-details-geotag-learn-more'),
                icon: Icons.help_outline_rounded,
                title: l10n.settingsBackgroundLearnMore,
                chevron: true,
                onTap: () => unawaited(GeotaggingExplainedScreen.push(context)),
              ),
            ],
          ),
          SectionLabel(l10n.geotagClockSection),
          GroupBox(children: [_clockRow(l10n, locked: background)]),
        ],
      );
    },
  );

  /// The clock's switch; [locked] on by background geotagging, which
  /// matches a photo by the time the camera wrote into it.
  Widget _clockRow(AppLocalizations l10n, {required bool locked}) {
    final on = widget.camera.keepsClock;
    void set({required bool on}) =>
        unawaited(_geotag.setSyncClock(_serial, on: on));
    return GroupRow(
      key: const Key('camera-details-clock'),
      icon: Icons.schedule_rounded,
      title: l10n.geotagSyncClock,
      subtitle: l10n.geotagSyncClockSubtitle,
      trailing: Switch(
        key: const Key('camera-details-clock-switch'),
        value: on,
        onChanged: locked ? null : (on) => set(on: on),
      ),
      onTap: locked ? null : () => set(on: !on),
    );
  }
}
