import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/geotag/geotag_need.dart';
import 'package:grphoto/src/geotag/geotag_text.dart';

/// Explains live geotagging for [camera] and asks whether to turn it on,
/// before the phone's own permission prompt can appear: what is sent, that
/// it is sent only while the camera is on, that the camera's clock is kept
/// on the phone's time, and that Android shows a notification meanwhile.
/// Completes with true for Turn on. Either way the camera counts as
/// offered from then on (`SavedCamera.geotagOffered`).
Future<bool> showGeotagOffer(BuildContext context, SavedCamera camera) async {
  final cameras = AppScope.of(context).cameras;
  final accepted = await showDialog<bool>(
    context: context,
    // A stray tap beside it must not count as Not now.
    barrierDismissible: false,
    builder: (_) => GeotagOfferDialog(cameraName: camera.name),
  );
  try {
    await cameras.markGeotagOffered(camera.serial);
  } on Exception {
    // The store reports a failed write and makes up for it with its next.
  }
  return accepted ?? false;
}

/// Says in a snack bar what the phone lacks after a location mode was
/// refused, with a button to the page of the phone's settings that allows
/// it.
void showGeotagNeed(BuildContext context, GeotagNeed need) {
  final geotag = AppScope.of(context).geotag;
  final l10n = context.l10n;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(geotagNeedText(l10n, need)),
        action: need.settingsPage == null
            ? null
            : SnackBarAction(
                label: l10n.geotagOpenSettings,
                onPressed: () => unawaited(geotag.openSettings(need)),
              ),
      ),
    );
}

/// The offer of live geotagging ([showGeotagOffer]). Pops true for Turn on
/// and false for Not now.
class GeotagOfferDialog extends StatelessWidget {
  const new({required this.cameraName, super.key});

  /// The camera the offer is for, as the user named it.
  final String cameraName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final paragraphs = [
      l10n.geotagOfferBody,
      l10n.geotagOfferClock,
      // Only Android shows one (its foreground service notification).
      if (defaultTargetPlatform == TargetPlatform.android)
        l10n.geotagOfferNotification,
      l10n.geotagOfferPermission,
    ];
    return AlertDialog(
      key: const Key('geotag-offer'),
      title: Text(l10n.geotagOfferTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            // On a line of its own, so no language has to inflect it.
            Text(
              cameraName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final paragraph in paragraphs) Text(paragraph),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('geotag-offer-later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.geotagOfferNotNow),
        ),
        FilledButton(
          key: const Key('geotag-offer-on'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.geotagOfferTurnOn),
        ),
      ],
    );
  }
}

/// Offers live geotagging once per camera ([showGeotagOffer]): when the
/// current camera is linked over Bluetooth, can be sent a location and
/// has not been offered it yet, which is after its pairing or, for a
/// camera paired before GR Photo had geotagging, at its first connection.
/// It waits until the screen under it is in front, so it does not cover
/// pairing or the camera's pages. Turn on asks the phone for its location;
/// when that is refused, a snack bar says what is needed.
class GeotagOfferGate extends StatefulWidget {
  const new({required this.child, super.key});

  /// The screen the offer is shown over.
  final Widget child;

  @override
  State<GeotagOfferGate> createState() => _GeotagOfferGateState();
}

class _GeotagOfferGateState extends State<GeotagOfferGate> with RouteAware {
  late final AppModels _models = AppScope.of(context);
  ModalRoute<void>? _route;
  bool _offering = false;

  @override
  void initState() {
    super.initState();
    _models.connection.addListener(_check);
    _models.cameras.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route && route is ModalRoute<void>) {
      if (_route != null) _models.routes.unsubscribe(this);
      _route = route;
      _models.routes.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _models.routes.unsubscribe(this);
    _models.connection.removeListener(_check);
    _models.cameras.removeListener(_check);
    super.dispose();
  }

  /// The screen over this one closed.
  @override
  void didPopNext() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());

  void _check() {
    if (!mounted || _offering) return;
    final camera = _models.cameras.current;
    if (camera == null || camera.geotagOffered) return;
    if (!_models.connection.bleLinked || !_models.geotag.supported) return;
    if (!(_route?.isCurrent ?? true)) return;
    _offering = true;
    unawaited(_offer(camera));
  }

  Future<void> _offer(SavedCamera camera) async {
    final accepted = await showGeotagOffer(context, camera);
    if (accepted) {
      final need = await _models.geotag.turnLiveOn(camera.serial);
      if (need != null && mounted) showGeotagNeed(context, need);
    }
    _offering = false;
    // Another camera may have become the current one meanwhile.
    _check();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
