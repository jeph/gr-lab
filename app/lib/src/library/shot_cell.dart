import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../theme/tokens.dart';
import 'camera_images.dart';
import 'format.dart';
import 'image_orientation.dart';
import 'library_scope.dart';
import 'shot.dart';

/// Badge in a cell's top-right corner.
enum CellMark { none, downloaded, queued, selected, unselected }

/// A camera image that loads through [CameraImages] while it is on screen
/// and drops its pending request when it scrolls away. It shows the image
/// upright using the shot's `/info` orientation, which it fetches when the
/// image does not carry its own (see [orientationToApply]).
class CameraImage extends StatefulWidget {
  const CameraImage({
    super.key,
    required this.serial,
    required this.file,
    required this.size,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.placeholder,
    this.onLoaded,
  });

  final String serial;
  final CameraFile file;
  final GrImageSize size;
  final BoxFit fit;

  /// Decode width in physical pixels of the shown (upright) image;
  /// thumbnails need far less than the file holds.
  final int? cacheWidth;
  final Widget? placeholder;
  final VoidCallback? onLoaded;

  @override
  State<CameraImage> createState() => _CameraImageState();
}

class _CameraImageState extends State<CameraImage> {
  late final LibraryContext _library = LibraryScope.of(context);
  Uint8List? _bytes;
  JpegLayout? _layout;

  /// The file's `/info` orientation as last built.
  int? _orientation;
  ImageRequest? _request;
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listening) {
      _listening = true;
      _library.link.addListener(_onLink);
      _library.model.addListener(_onModel);
      _orientation = _infoOrientation();
      _load();
    }
  }

  @override
  void didUpdateWidget(CameraImage old) {
    super.didUpdateWidget(old);
    if (old.serial != widget.serial ||
        old.file != widget.file ||
        old.size != widget.size) {
      _request?.cancel();
      _bytes = null;
      _layout = null;
      _orientation = _infoOrientation();
      _load();
    }
  }

  @override
  void dispose() {
    _library.link.removeListener(_onLink);
    _library.model.removeListener(_onModel);
    _request?.cancel();
    super.dispose();
  }

  void _onLink() {
    if (_library.link.value?.serial != widget.serial) return;
    if (_bytes == null) {
      setState(_load);
    } else {
      widget.onLoaded?.call();
    }
  }

  /// The `/info` orientation, once the library knows it for this camera.
  int? _infoOrientation() {
    final model = _library.model;
    if (model.serial != widget.serial) return null;
    return model.info(widget.file)?.orientation;
  }

  void _onModel() {
    final orientation = _infoOrientation();
    if (orientation != _orientation) {
      setState(() => _orientation = orientation);
    }
  }

  void _show(Uint8List bytes) {
    _bytes = bytes;
    _layout = readJpegLayout(bytes);
    // Only `/info` says how a shot in stored layout was held.
    final model = _library.model;
    if (_layout?.decoderOrients != true &&
        model.serial == widget.serial &&
        model.info(widget.file) == null) {
      unawaited(model.ensureInfo(widget.file));
    }
  }

  void _load() {
    final images = _library.images;
    final hit = images.cached(widget.serial, widget.file, widget.size);
    if (hit != null) {
      _show(hit);
      widget.onLoaded?.call();
      return;
    }
    _request?.cancel();
    final request = images.load(widget.serial, widget.file, widget.size);
    _request = request;
    request.future.then((bytes) {
      if (!mounted || !identical(_request, request)) return;
      _request = null;
      if (bytes == null) return;
      setState(() => _show(bytes));
      widget.onLoaded?.call();
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    final orientation = orientationToApply(_layout, _orientation);
    // Decode sizes count stored pixels: after a quarter turn the shown
    // width is the stored height.
    final turned = orientationSwapsAxes(orientation);
    return Image.memory(
      bytes,
      key: ValueKey('image:${widget.size.name}:${widget.file.key}'),
      fit: widget.fit,
      cacheWidth: turned ? null : widget.cacheWidth,
      cacheHeight: turned ? widget.cacheWidth : null,
      gaplessPlayback: true,
      // Turns the decoded image only, never the error placeholder.
      frameBuilder: (context, child, _, _) =>
          ExifOrientation(orientation: orientation, child: child),
      errorBuilder: (context, _, _) =>
          widget.placeholder ?? const SizedBox.expand(),
    );
  }
}

/// One grid item: thumbnail, format tag and a status badge (mock `.cell`).
class ShotCell extends StatelessWidget {
  const ShotCell({
    super.key,
    required this.serial,
    required this.shot,
    required this.mark,
    required this.onTap,
    required this.onLongPress,
    this.duration,
    this.onVisible,
  });

  final String serial;
  final Shot shot;
  final CellMark mark;
  final Duration? duration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Called once the thumbnail is shown, to fetch the shot's info.
  final VoidCallback? onVisible;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width / 3;
    final selected = mark == CellMark.selected;
    return Semantics(
      label: '${formatLabel(shot.format)} ${shot.primary.name}',
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: c.s2,
              child: CameraImage(
                serial: serial,
                file: shot.primary,
                size: GrImageSize.thumb,
                cacheWidth: (width * dpr).round(),
                onLoaded: onVisible,
                placeholder: Center(
                  child: Icon(
                    shot.isVideo
                        ? Icons.videocam_outlined
                        : Icons.photo_outlined,
                    color: c.t3,
                    size: 22,
                  ),
                ),
              ),
            ),
            Positioned(left: 5, bottom: 5, child: PhotoTag(_tag())),
            if (_badge(c) case final badge?)
              Positioned(top: 6, right: 6, child: badge),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c.accent, width: 3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _tag() => switch (shot.format) {
    ShotFormat.video => duration == null ? 'MOV' : formatDuration(duration!),
    final f => formatLabel(f),
  };

  Widget? _badge(GrColors c) => switch (mark) {
    CellMark.none => null,
    CellMark.downloaded => const _Dot(
      color: GrColors.photoBadgeScrim,
      child: Icon(Icons.check_rounded, size: 13, color: GrColors.photoBadgeOk),
    ),
    CellMark.queued => const _Dot(
      color: GrColors.photoBadgeScrim,
      child: Icon(Icons.arrow_downward_rounded, size: 13, color: Colors.white),
    ),
    CellMark.selected => _Dot(
      color: c.accent,
      child: Icon(Icons.check_rounded, size: 13, color: c.accentInk),
    ),
    CellMark.unselected => Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: .2),
        border: Border.all(
          color: Colors.white.withValues(alpha: .9),
          width: 1.5,
        ),
      ),
    ),
  };
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    alignment: Alignment.center,
    child: child,
  );
}

/// Small monospace label over a photo (mock `.tag`).
class PhotoTag extends StatelessWidget {
  const PhotoTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: GrFonts.mono,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: .4,
        color: Colors.white,
      ),
    ),
  );
}
