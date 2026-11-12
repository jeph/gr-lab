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
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';

/// The Live geotagging switch of the camera card, for a camera that can be
/// sent a location (nothing otherwise). Off until the user turns it on,
/// which is when the phone asks for its location \[design\]: nothing asks
/// before.
///
/// The line under the title says what the switch does, on or off: the
/// switch says which. What holds live geotagging up, where the user can
/// help, is said under the row with a button: turn the camera's Store
/// Location Info back on, resume after Stop on the phone's notice, or open
/// the page of the phone's settings that allows what is missing. A refusal
/// when turning it on leaves the switch off and says what is needed there.
class LiveGeotagSwitch extends StatefulWidget {
  const new({required this.camera, super.key});

  /// The camera of the card, as saved.
  final SavedCamera camera;

  @override
  State<LiveGeotagSwitch> createState() => _LiveGeotagSwitchState();
}

class _LiveGeotagSwitchState extends State<LiveGeotagSwitch> {
  late final GeotagController _geotag = AppScope.of(context).geotag;

  /// The phone is being asked; the switch waits.
  bool _asking = false;

  /// Why the phone refused to turn live geotagging on, until its access
  /// changes.
  ({GeotagNeed need, LocationAccess access})? _refused;

  String get _serial => widget.camera.serial;

  Future<void> _set({required bool on}) async {
    if (_asking) return;
    if (!on) {
      setState(() => _refused = null);
      await _geotag.turnLiveOff(_serial);
      return;
    }
    setState(() {
      _asking = true;
      _refused = null;
    });
    final need = await _geotag.turnLiveOn(_serial);
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
      if (!_geotag.supports(widget.camera)) return const SizedBox.shrink();
      final c = GrColors.of(context);
      final l10n = context.l10n;
      final live = widget.camera.liveGeotagging;
      final status = _geotag.statusOf(widget.camera);
      final refusal = _refused;
      final refused =
          !live && refusal != null && refusal.access == _geotag.access
          ? refusal.need
          : null;
      final missing = live ? GeotagController.needOf(status) : refused;
      final problem = refused != null
          ? geotagNeedText(l10n, refused)
          : live
          ? geotagProblemText(l10n, status)
          : null;
      final action = missing != null
          ? _Action(
              key: const Key('camera-card-geotag-settings'),
              label: l10n.geotagOpenSettings,
              onPressed: () => unawaited(_geotag.openSettings(missing)),
            )
          : switch (status) {
              GeotagStatus.offOnCamera => _Action(
                key: const Key('camera-card-geotag-store'),
                label: l10n.geotagTurnOnStoreLocationInfo,
                onPressed: () => unawaited(_geotag.turnOnStoreLocationInfo()),
              ),
              GeotagStatus.stopped => _Action(
                key: const Key('camera-card-geotag-resume'),
                label: l10n.geotagResume,
                onPressed: _geotag.resume,
              ),
              _ => null,
            };
      final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GrRadii.md),
        side: BorderSide(color: c.line),
      );
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          key: const Key('camera-card-geotag'),
          color: c.s2,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GroupRow(
                icon: Icons.location_on_outlined,
                title: l10n.geotagSwitch,
                subtitle: l10n.geotagLiveSubtitle,
                trailing: Switch(
                  key: const Key('camera-card-geotag-switch'),
                  value: live,
                  onChanged: _asking ? null : (on) => unawaited(_set(on: on)),
                ),
                onTap: _asking ? null : () => unawaited(_set(on: !live)),
              ),
              if (problem != null)
                Padding(
                  // Under the row's text, past its icon.
                  padding: const EdgeInsetsDirectional.fromSTEB(60, 0, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        problem,
                        key: const Key('camera-card-geotag-problem'),
                        style: TextStyle(fontSize: 12.5, color: c.t1),
                      ),
                      if (action != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: action.key,
                          style: smallOutlinedStyle,
                          onPressed: action.onPressed,
                          child: Text(action.label),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The button under what holds live geotagging up.
final class _Action {
  const new({required this.key, required this.label, required this.onPressed});

  final Key key;
  final String label;
  final VoidCallback onPressed;
}
