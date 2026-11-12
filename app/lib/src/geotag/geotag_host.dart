import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/camera/camera_pages.dart';
import 'package:grphoto/src/geotag/geotag_model.dart';
import 'package:grphoto/src/geotag/geotag_offer.dart';

/// Gives live geotagging what it needs from the app's widgets: the texts
/// of its notification in the app's language, and the offer to turn it on,
/// shown once when a camera that has not been asked about is linked
/// ([GeotagModel.offerDue]) and the app is in front. The offer opens over
/// the Cameras screen or the camera's pages only: while anything else is
/// in front (pairing, which links the camera before its last page is
/// closed, Settings, a dialog) it waits until that has closed. Wraps the
/// app below its localizations, since the texts are in the app's
/// language.
class GeotagHost extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<GeotagHost> createState() => _GeotagHostState();
}

class _GeotagHostState extends State<GeotagHost> {
  late final AppModels _models = AppScope.of(context);
  late final GeotagModel _geotag = _models.geotag;

  /// Set by a change of the model. The offer waits for the event loop's
  /// next turn because the model also reports during a build (taking the
  /// texts), when no route can be pushed.
  Timer? _soon;

  /// The offer is on screen.
  bool _showing = false;

  /// The route in front that the offer waits to see closed.
  Route<void>? _inTheWay;

  /// The serials of the cameras offered since launch: the model still
  /// says an offer is due while the answer is being saved, and a camera is
  /// asked once.
  final Set<String> _offered = {};

  @override
  void initState() {
    super.initState();
    _geotag.addListener(_onGeotag);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The language changed, or is first known.
    final l10n = context.l10n;
    _geotag.setTexts(
      GeotagTexts(
        sendingTitle: l10n.geotagNoticeSendingTitle,
        sendingText: l10n.geotagNoticeSendingText,
        waitingTitle: l10n.geotagNoticeWaitingTitle,
        waitingText: l10n.geotagNoticeWaitingText,
        stopLabel: l10n.geotagNoticeStop,
        channelName: l10n.geotagNoticeChannel,
      ),
    );
  }

  @override
  void dispose() {
    _soon?.cancel();
    _geotag.removeListener(_onGeotag);
    super.dispose();
  }

  void _onGeotag() {
    if (_geotag.offerDue) _soon ??= Timer(Duration.zero, _offer);
  }

  Future<void> _offer() async {
    _soon = null;
    final connection = _models.connection;
    final serial = _models.cameras.current?.serial;
    // The question about joining the camera's Wi-Fi goes first; the model
    // reports again once it is answered.
    if (_showing ||
        serial == null ||
        !_geotag.offerDue ||
        !connection.foreground ||
        connection.wifiConsent != null ||
        _offered.contains(serial)) {
      return;
    }
    // This widget is above the app's navigator (it wraps what
    // `MaterialApp.builder` is given), so unlike `RootScreen`, which asks
    // about Wi-Fi through the navigator around it, it reaches the
    // navigator through the route observer the app registers with it.
    final navigator = _models.routes.navigator;
    if (navigator == null) return;
    final top = _topRoute(navigator);
    if (top != null &&
        !top.isFirst &&
        top.settings.name != CameraPages.routeName) {
      if (identical(top, _inTheWay)) return;
      _inTheWay = top;
      unawaited(
        top.popped.then((_) {
          if (identical(top, _inTheWay)) _inTheWay = null;
          if (mounted) _onGeotag();
        }),
      );
      return;
    }
    _offered.add(serial);
    _showing = true;
    try {
      await showGeotagOffer(navigator.context, _geotag);
    } finally {
      _showing = false;
    }
  }

  /// The route in front, without changing anything.
  static Route<void>? _topRoute(NavigatorState navigator) {
    Route<void>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
