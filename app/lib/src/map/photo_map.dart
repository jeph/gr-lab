import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/src/map/map_style.dart';
import 'package:grphoto/src/platform/map_network.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// A map with a pin on [place], where a photo was taken, in the colours of
/// the app's theme ([mapStyle]).
///
/// The map is a picture to look at \[design\]: it is not dragged, zoomed
/// or turned, so that a drag over it scrolls the screen it is on. The pin
/// is drawn over its centre, which stays on [place].
///
/// MapLibre draws it from OpenFreeMap's tiles, fetched over the internet:
/// the only traffic of GR Photo that does not go to a camera
/// ([useInternetForMap]). Without a connection
/// the pin stands on the empty ground of the theme.
class PhotoMap extends StatefulWidget {
  const new({required this.place, required this.zoom, super.key});

  /// Where the pin stands.
  final GrPhotoLocation place;

  /// MapLibre's zoom level: 14 shows the streets around [place], 12 the
  /// part of town.
  final double zoom;

  @override
  State<PhotoMap> createState() => _PhotoMapState();
}

class _PhotoMapState extends State<PhotoMap> {
  /// The style's template, once the map can be drawn: its requests are
  /// routed first.
  late final Future<String> _template = () async {
    await useInternetForMap();
    return await loadMapStyleTemplate();
  }();

  /// Where the map was created: its camera is moved to a later
  /// [PhotoMap.place].
  late final GrPhotoLocation _createdAt = widget.place;
  late final double _createdZoom = widget.zoom;
  MapLibreMapController? _map;

  CameraUpdate get _view => CameraUpdate.newLatLngZoom(
    LatLng(widget.place.latitude, widget.place.longitude),
    widget.zoom,
  );

  @override
  void didUpdateWidget(PhotoMap old) {
    super.didUpdateWidget(old);
    if (old.place != widget.place || old.zoom != widget.zoom) {
      unawaited(_show());
    }
  }

  void _onMapCreated(MapLibreMapController map) {
    _map = map;
    // Another photo may have been shown while the map was being created.
    if (widget.place != _createdAt || widget.zoom != _createdZoom) {
      unawaited(_show());
    }
  }

  /// Moves the map to [PhotoMap.place], once there is one.
  Future<void> _show() async {
    try {
      await _map?.moveCamera(_view);
    } on PlatformException catch (e) {
      debugPrint('Moving the map failed: ${e.code}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GrColors.of(context);
    return ColoredBox(
      // The map's ground, until its tiles are drawn.
      color: colors.s2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder(
            future: _template,
            builder: (context, template) {
              final style = template.data;
              if (style == null) return const SizedBox.shrink();
              return MapLibreMap(
                styleString: mapStyle(style, colors),
                initialCameraPosition: CameraPosition(
                  target: LatLng(_createdAt.latitude, _createdAt.longitude),
                  zoom: _createdZoom,
                ),
                onMapCreated: _onMapCreated,
                foregroundLoadColor: colors.s2,
                attributionButtonColor: colors.t3,
                compassEnabled: false,
                rotateGesturesEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                tiltGesturesEnabled: false,
                doubleClickZoomEnabled: false,
                dragEnabled: false,
                // The pin is drawn here, not by the map.
                annotationOrder: const [],
              );
            },
          ),
          // Its tip on the centre of the map.
          IgnorePointer(
            child: Center(
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: CustomPaint(
                  size: const Size(30, 40),
                  painter: _PinPainter(
                    fill: colors.accent,
                    dot: colors.accentInk,
                    outline: colors.brightness == Brightness.dark
                        ? const Color(0x8C000000)
                        : const Color(0xE6FFFFFF),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A map pin: a drop standing on its tip, with a dot in its head.
class _PinPainter extends CustomPainter {
  const new({required this.fill, required this.dot, required this.outline});

  final Color fill;
  final Color dot;

  /// Sets the pin off from a map of its own colour.
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w / 2 - 1;
    final head = Offset(w / 2, radius + 1);
    // From the tip up one side, around the head and down the other.
    final drop = Path()
      ..moveTo(w / 2, h - 0.5)
      ..cubicTo(w * 0.42, h * 0.82, 1, h * 0.60, 1, head.dy)
      ..arcToPoint(Offset(w - 1, head.dy), radius: Radius.circular(radius))
      ..cubicTo(w - 1, h * 0.60, w * 0.58, h * 0.82, w / 2, h - 0.5)
      ..close();
    canvas
      ..drawPath(drop, Paint()..color = fill)
      ..drawPath(
        drop,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      )
      ..drawCircle(head, w / 6, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_PinPainter old) =>
      old.fill != fill || old.dot != dot || old.outline != outline;
}
