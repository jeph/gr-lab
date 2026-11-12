import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';
import 'package:grphoto/src/geotag/geotag_offer.dart';
import 'package:grphoto/src/geotag/geotag_text.dart';
import 'package:grphoto/src/widgets/group.dart';

/// The camera sheet's location section, for a camera that can be sent a
/// location (nothing otherwise):
///
/// - Geotagging: the switch of live geotagging for this camera, with what
///   it is doing in a line under it and, where the user can help, a
///   button: turn the camera's Store Location Info back on, resume after
///   Stop on the phone's notice, or open the page of the phone's settings
///   that allows what is missing. A refusal when turning it on leaves the
///   switch off and says what is needed in that line.
/// - While it is on and the phone can start GR Photo for a camera: that it
///   starts when GR Photo is open, with Set up for starting whenever the
///   camera is switched on, or that it does so.
/// - Sync camera clock, forced on while geotagging is on.
class GeotagSection extends StatefulWidget {
  const new({required this.camera, super.key});

  /// The current camera, as saved.
  final SavedCamera camera;

  @override
  State<GeotagSection> createState() => _GeotagSectionState();
}

/// Why the phone refused what the user last asked for here, until the
/// phone's access changes.
typedef _Refusal = ({GeotagNeed need, LocationAccess access});

class _GeotagSectionState extends State<GeotagSection> {
  late final GeotagController _geotag = AppScope.of(context).geotag;

  /// The phone is being asked; the switch waits.
  bool _asking = false;
  _Refusal? _liveRefused;
  _Refusal? _autoStartRefused;

  String get _serial => widget.camera.serial;

  /// [refusal]'s need while the access it was refused with still holds.
  GeotagNeed? _standing(_Refusal? refusal) =>
      refusal != null && refusal.access == _geotag.access ? refusal.need : null;

  Future<void> _setLive({required bool on}) async {
    if (_asking) return;
    if (!on) {
      setState(() => _liveRefused = null);
      await _geotag.turnLiveOff(_serial);
      return;
    }
    setState(() {
      _asking = true;
      _liveRefused = null;
    });
    // The explanation comes before the phone's own prompt.
    final go =
        widget.camera.geotagOffered ||
        await showGeotagOffer(context, widget.camera);
    final need = go ? await _geotag.turnLiveOn(_serial) : null;
    if (!mounted) return;
    setState(() {
      _asking = false;
      _liveRefused = _refusal(need);
    });
  }

  Future<void> _setUpAutoStart() async {
    if (_asking) return;
    setState(() {
      _asking = true;
      _autoStartRefused = null;
    });
    final need = await _geotag.setUpAutoStart(_serial);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _autoStartRefused = _refusal(need);
    });
  }

  _Refusal? _refusal(GeotagNeed? need) =>
      need == null ? null : (need: need, access: _geotag.access);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _geotag,
    builder: (context, _) {
      if (!_geotag.supported) return const SizedBox.shrink();
      final l10n = context.l10n;
      final live = widget.camera.liveGeotagging;
      return Column(
        key: const Key('camera-sheet-location'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(l10n.geotagSection),
          GroupBox(
            children: [
              _liveRow(l10n, live: live),
              if (live && _geotag.autoStartSupported) _autoStartRow(l10n),
              _clockRow(l10n, live: live),
            ],
          ),
        ],
      );
    },
  );

  Widget _liveRow(AppLocalizations l10n, {required bool live}) {
    final status = _geotag.status;
    final refused = live ? null : _standing(_liveRefused);
    final missing = live ? GeotagController.needOf(status) : refused;
    return _ActionRow(
      action: missing != null
          ? _settingsAction('geotag', l10n, missing)
          : switch (status) {
              GeotagStatus.offOnCamera => _Action(
                key: const Key('camera-sheet-geotag-store'),
                label: l10n.geotagTurnOnStoreLocationInfo,
                onPressed: () => unawaited(_geotag.turnOnStoreLocationInfo()),
              ),
              GeotagStatus.stopped => _Action(
                key: const Key('camera-sheet-geotag-resume'),
                label: l10n.geotagResume,
                onPressed: _geotag.resume,
              ),
              _ => null,
            },
      child: GroupRow(
        key: const Key('camera-sheet-geotag'),
        icon: Icons.location_on_outlined,
        title: l10n.geotagSwitch,
        subtitle: refused != null
            ? geotagNeedText(l10n, refused)
            : geotagStatusText(l10n, status),
        trailing: Switch(
          key: const Key('camera-sheet-geotag-switch'),
          value: live,
          onChanged: _asking ? null : (on) => unawaited(_setLive(on: on)),
        ),
        onTap: _asking ? null : () => unawaited(_setLive(on: !live)),
      ),
    );
  }

  Widget _autoStartRow(AppLocalizations l10n) {
    const icon = Icons.power_settings_new_rounded;
    if (_geotag.autoStartReady(widget.camera)) {
      return GroupRow(
        key: const Key('camera-sheet-autostart'),
        icon: icon,
        title: l10n.geotagAutoStart,
        subtitle: l10n.geotagAutoStartReady,
      );
    }
    final refused = _standing(_autoStartRefused);
    final linked = _geotag.linkedToPhone(widget.camera);
    return _ActionRow(
      // What a settings page allows is allowed there; the rest is asked
      // for again.
      action: refused != null && refused.settingsPage != null
          ? _settingsAction('autostart', l10n, refused)
          : _Action(
              key: const Key('camera-sheet-autostart-setup'),
              label: l10n.geotagAutoStartSetUp,
              onPressed: _asking ? null : () => unawaited(_setUpAutoStart()),
            ),
      child: GroupRow(
        key: const Key('camera-sheet-autostart'),
        icon: icon,
        title: l10n.geotagAutoStart,
        subtitle: refused != null
            ? geotagNeedText(l10n, refused)
            : _geotag.locationAlways
            ? l10n.geotagAutoStartNeedsLink
            : linked
            ? l10n.geotagAutoStartNeedsAlways
            : l10n.geotagAutoStartNeedsBoth,
      ),
    );
  }

  Widget _clockRow(AppLocalizations l10n, {required bool live}) {
    final on = live || widget.camera.syncClock;
    void set({required bool on}) =>
        unawaited(_geotag.setSyncClock(_serial, on: on));
    return GroupRow(
      key: const Key('camera-sheet-clock'),
      icon: Icons.schedule_rounded,
      title: l10n.geotagSyncClock,
      // Geotagging needs the camera's clock right, so it keeps it there.
      subtitle: live
          ? l10n.geotagSyncClockForced
          : l10n.geotagSyncClockSubtitle,
      trailing: Switch(
        key: const Key('camera-sheet-clock-switch'),
        value: on,
        onChanged: live ? null : (on) => set(on: on),
      ),
      onTap: live ? null : () => set(on: !on),
    );
  }

  /// The button to the page of the phone's settings that allows [need],
  /// for the row named [row].
  _Action _settingsAction(String row, AppLocalizations l10n, GeotagNeed need) =>
      _Action(
        key: Key('camera-sheet-$row-settings'),
        label: l10n.geotagOpenSettings,
        onPressed: () => unawaited(_geotag.openSettings(need)),
      );
}

/// A button under a row; disabled without [onPressed].
final class _Action {
  const new({required this.key, required this.label, required this.onPressed});

  final Key key;
  final String label;
  final VoidCallback? onPressed;
}

/// A [GroupRow] with a small button under its text when [action] is set:
/// the row's trailing place is its switch's.
class _ActionRow extends StatelessWidget {
  const new({required this.child, required this.action});

  final Widget child;
  final _Action? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    if (action == null) return child;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        Padding(
          // Under the row's text, past its icon.
          padding: const EdgeInsetsDirectional.fromSTEB(60, 0, 14, 12),
          child: OutlinedButton(
            key: action.key,
            style: smallOutlinedStyle,
            onPressed: action.onPressed,
            child: Text(action.label),
          ),
        ),
      ],
    );
  }
}
