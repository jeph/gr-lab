import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/library/format.dart';
import 'package:grlab/src/library/image_orientation.dart';
import 'package:grlab/src/library/library_scope.dart';
import 'package:grlab/src/library/shot.dart';
import 'package:grlab/src/theme/tokens.dart';

/// Badge in a cell's top-right corner.
enum CellMark { none, downloaded, queued, selected, unselected }

/// A camera image that loads through [CameraImages] while it is on screen
/// and drops its pending requests when it goes away.
///
/// It appears only once it can be shown upright: a GR's thumbnails and
/// previews are stored unrotated, so the shot's `/info` orientation (kept
/// in the library's cache) is fetched alongside the image, unless the
/// image carries a tag the decoder applies (see [orientationToApply]).
/// Failed requests are retried after a short pause while the widget is
/// mounted; after repeated failures it shows a retry button.
///
/// With [sharper], an image that would be enlarged on screen, or any image
/// while [wantSharper], is followed by that size, loaded behind other
/// camera requests and drawn over it once ready.
class CameraImage extends StatefulWidget {
  const new({
    required this.serial,
    required this.file,
    required this.size,
    super.key,
    this.sharper,
    this.wantSharper = false,
    this.fit = BoxFit.cover,
    this.zoomHeadroom = 1,
    this.placeholder,
    this.showProgress = false,
  });

  final String serial;
  final CameraFile file;
  final GrImageSize size;
  final GrImageSize? sharper;
  final bool wantSharper;
  final BoxFit fit;

  /// Images are decoded at most at the box's physical size times this, so
  /// a zoomable view keeps detail when zoomed in.
  final double zoomHeadroom;
  final Widget? placeholder;

  /// Shows a spinner over [placeholder] while loading.
  final bool showProgress;

  @override
  State<CameraImage> createState() => _CameraImageState();
}

final class _Loaded {
  new(this.bytes, this.size) : layout = readJpegLayout(bytes);

  final Uint8List bytes;
  final GrImageSize size;
  final JpegLayout? layout;
}

class _CameraImageState extends State<CameraImage> {
  /// Pauses before each retry; one more failure shows the retry button.
  static const _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// Lets a cell scrolled past, or a page swiped past, go before its
  /// sharper copy is asked for.
  static const _sharperDelay = Duration(milliseconds: 400);

  /// Enlargement above which the image looks soft.
  static const _blurry = 1.25;

  late final LibraryContext _library = LibraryScope.of(context);
  bool _listening = false;

  _Loaded? _base;
  _Loaded? _sharp;
  ImageRequest? _image;
  RequestTicket<FileInfo>? _info;
  ImageRequest? _sharpRequest;
  Timer? _sharpTimer;
  bool _sharpTried = false;
  bool _sharpCheckScheduled = false;
  int _failures = 0;
  Timer? _retry;
  bool _failed = false;

  /// The file's `/info`, as last built.
  bool _infoKnown = false;
  int? _orientation;

  /// The library holds this camera's info, so the orientation can be
  /// known; for another camera's file the image shows as stored.
  bool _infoAvailable = false;

  /// The library's `LibraryModel.revision` of the file shown.
  int _revision = 0;

  /// The box in physical pixels, as last laid out.
  Size _box = Size.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listening) {
      _listening = true;
      _library.link.addListener(_onLink);
      _library.model.addListener(_onModel);
      _revision = _currentRevision();
      _readInfo();
      _start();
    }
  }

  @override
  void didUpdateWidget(CameraImage old) {
    super.didUpdateWidget(old);
    if (old.serial != widget.serial ||
        old.file != widget.file ||
        old.size != widget.size ||
        old.sharper != widget.sharper) {
      _restart();
    } else if (widget.wantSharper && !old.wantSharper) {
      _considerSharper();
    }
  }

  int _currentRevision() {
    final model = _library.model;
    return model.serial == widget.serial ? model.revision(widget.file) : 0;
  }

  /// Drops what is shown and loads the image again.
  void _restart() {
    _stop();
    _base = null;
    _sharp = null;
    _sharpTried = false;
    _failures = 0;
    _failed = false;
    _revision = _currentRevision();
    _readInfo();
    _start();
  }

  @override
  void dispose() {
    _library.link.removeListener(_onLink);
    _library.model.removeListener(_onModel);
    _stop();
    super.dispose();
  }

  void _stop() {
    _image?.cancel();
    _image = null;
    _info?.cancel();
    _info = null;
    _sharpRequest?.cancel();
    _sharpRequest = null;
    _sharpTimer?.cancel();
    _sharpTimer = null;
    _retry?.cancel();
    _retry = null;
  }

  bool get _ready {
    final shown = _sharp ?? _base;
    return shown != null &&
        (_infoKnown || !_infoAvailable || shown.layout?.decoderOrients == true);
  }

  /// Reads the file's info from the library; true when it changed.
  bool _readInfo() {
    final model = _library.model;
    final available = model.serial == widget.serial;
    final info = available ? model.info(widget.file) : null;
    final known = info != null;
    final orientation = info?.orientation;
    if (available == _infoAvailable &&
        known == _infoKnown &&
        orientation == _orientation) {
      return false;
    }
    _infoAvailable = available;
    _infoKnown = known;
    _orientation = orientation;
    return true;
  }

  void _start() {
    _failed = false;
    if (_base == null) _loadImage();
    _loadInfo();
  }

  void _loadImage() {
    _image?.cancel();
    _image = null;
    final images = _library.images;
    final sharper = widget.sharper;
    if (sharper != null && _sharp == null) {
      // Scrolling back to a cell whose sharper copy is still in memory.
      final hit = images.cached(widget.serial, widget.file, sharper);
      if (hit != null) {
        _sharp = _Loaded(hit, sharper);
        _sharpTried = true;
      }
    }
    final hit = images.cached(widget.serial, widget.file, widget.size);
    if (hit != null) {
      _base = _Loaded(hit, widget.size);
      _progressed();
      return;
    }
    final request = images.load(widget.serial, widget.file, widget.size);
    _image = request;
    unawaited(
      request.future.then(
        (bytes) {
          if (!mounted || !identical(_image, request)) return;
          _image = null;
          // Null: not connected; the link listener starts again.
          if (bytes == null) return;
          setState(() => _base = _Loaded(bytes, widget.size));
          _progressed();
        },
        onError: (Object _) {
          if (!mounted || !identical(_image, request)) return;
          _image = null;
          _failure();
        },
      ),
    );
  }

  /// Asks the library for the file's info, also when it is cached: on a
  /// new link the camera confirms it, and the library reloads what it
  /// shows if the path now holds another file.
  void _loadInfo() {
    if (_info != null || !_infoAvailable) return;
    final ticket = _library.model.requestInfo(widget.file);
    if (ticket == null) return;
    _info = ticket;
    unawaited(
      ticket.future.then(
        (_) {
          if (!mounted || !identical(_info, ticket)) return;
          _info = null;
          _onModel();
        },
        onError: (Object _) {
          if (!mounted || !identical(_info, ticket)) return;
          _info = null;
          if (!_ready) _failure();
        },
      ),
    );
  }

  /// Something arrived; once the image can show, a sharper copy may help.
  /// Failures start over only when a frame decodes (see [_decoded]): bytes
  /// that start like a JPEG may still be unreadable.
  void _progressed() {
    if (!_ready) return;
    _scheduleSharperCheck();
  }

  void _decoded(_Loaded loaded) {
    if (identical(loaded, _base)) _failures = 0;
  }

  void _failure() {
    if (_retry != null || _failed) return;
    if (_failures >= _retryDelays.length) {
      setState(() => _failed = true);
      return;
    }
    _retry = Timer(_retryDelays[_failures++], () {
      _retry = null;
      if (mounted) _start();
    });
  }

  void _retryNow() {
    _retry?.cancel();
    _retry = null;
    _failures = 0;
    setState(_start);
  }

  void _onLink() {
    final link = _library.link.value;
    if (link == null || link.serial != widget.serial) return;
    // Requests made on the previous connection may never answer.
    _info?.cancel();
    _info = null;
    if (_ready) {
      _loadInfo();
    } else {
      _retry?.cancel();
      _retry = null;
      _failures = 0;
      setState(_start);
    }
    _considerSharper();
  }

  void _onModel() {
    // The file's path holds another file than the one shown.
    if (_currentRevision() != _revision) {
      setState(_restart);
      return;
    }
    if (!_readInfo()) return;
    setState(() {});
    // The library switched to this camera after the widget started.
    if (!_infoKnown) _loadInfo();
    _progressed();
  }

  void _scheduleSharperCheck() {
    if (widget.sharper == null || _sharpCheckScheduled) return;
    _sharpCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sharpCheckScheduled = false;
      if (mounted) _considerSharper();
    });
  }

  /// Asks for [CameraImage.sharper] when the image shown would be enlarged
  /// (or is wanted sharper), from disk at once or from the camera after a
  /// pause.
  void _considerSharper() {
    final sharper = widget.sharper;
    final base = _base;
    if (sharper == null ||
        base == null ||
        _sharp != null ||
        _sharpTried ||
        _sharpRequest != null ||
        _sharpTimer != null ||
        !_ready) {
      return;
    }
    final orientation = orientationToApply(base.layout, _orientation);
    final soft =
        enlargement(base.layout, orientation, _box, widget.fit) > _blurry;
    if (!soft && !widget.wantSharper) return;
    if (_library.images.isLocal(widget.serial, widget.file, sharper)) {
      _loadSharper();
      return;
    }
    final link = _library.link.value;
    if (link == null || link.serial != widget.serial) return;
    _sharpTimer = Timer(_sharperDelay, () {
      _sharpTimer = null;
      if (mounted) _loadSharper();
    });
  }

  void _loadSharper() {
    final sharper = widget.sharper;
    if (sharper == null) return;
    _sharpTried = true;
    final request = _library.images.load(
      widget.serial,
      widget.file,
      sharper,
      background: true,
    );
    _sharpRequest = request;
    unawaited(
      request.future.then(
        (bytes) {
          if (!mounted || !identical(_sharpRequest, request)) return;
          _sharpRequest = null;
          if (bytes == null) {
            // Not connected; tried again when the camera is back.
            _sharpTried = false;
            return;
          }
          setState(() => _sharp = _Loaded(bytes, sharper));
        },
        // The image already shown stays; the next visit tries again.
        onError: (Object _) {
          if (mounted && identical(_sharpRequest, request)) {
            _sharpRequest = null;
          }
        },
      ),
    );
  }

  /// The decoder refused [loaded]: drop the copy so the camera is asked
  /// again (the base image) or the base image shows alone (the sharper).
  void _decodeFailed(_Loaded loaded) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _library.images.evict(widget.serial, widget.file, loaded.size);
      if (identical(loaded, _sharp)) {
        setState(() => _sharp = null);
      } else if (identical(loaded, _base)) {
        setState(() => _base = null);
        _failure();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(
          constraints.maxWidth * dpr,
          constraints.maxHeight * dpr,
        );
        if (box != _box) {
          _box = box;
          _scheduleSharperCheck();
        }
        if (!_ready) return _placeholder(context);
        // The sharper copy covers the first once decoded; until then the
        // first one shows through.
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_base case final base?) _picture(base),
            if (_sharp case final sharp?) _picture(sharp),
          ],
        );
      },
    );
  }

  Widget _picture(_Loaded loaded) {
    final orientation = orientationToApply(loaded.layout, _orientation);
    return Image.memory(
      loaded.bytes,
      key: ValueKey('image:${loaded.size.name}:${widget.file.key}'),
      fit: widget.fit,
      cacheWidth: decodeWidth(
        loaded.layout,
        orientation,
        _box * widget.zoomHeadroom,
        widget.fit,
      ),
      gaplessPlayback: true,
      // Turns the decoded image only, never the error placeholder.
      frameBuilder: (context, child, frame, _) {
        if (frame != null) _decoded(loaded);
        return ExifOrientation(orientation: orientation, child: child);
      },
      errorBuilder: (context, _, _) {
        _decodeFailed(loaded);
        return const SizedBox.shrink();
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    final placeholder = widget.placeholder ?? const SizedBox.expand();
    final Widget? overlay;
    if (_failed) {
      final c = GrColors.of(context);
      overlay = IconButton(
        key: ValueKey('image-retry:${widget.size.name}:${widget.file.key}'),
        tooltip: context.l10n.libraryImageRetry,
        onPressed: _retryNow,
        style: IconButton.styleFrom(backgroundColor: c.s3),
        icon: Icon(Icons.refresh_rounded, color: c.t1, size: 20),
      );
    } else if (widget.showProgress) {
      overlay = const CircularProgressIndicator();
    } else {
      overlay = null;
    }
    if (overlay == null) return placeholder;
    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        Center(child: overlay),
      ],
    );
  }
}

/// One grid item: thumbnail, format tag and a status badge (mock `.cell`).
class ShotCell extends StatelessWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.mark,
    required this.onTap,
    required this.onLongPress,
    super.key,
    this.duration,
  });

  final String serial;
  final Shot shot;
  final CellMark mark;
  final Duration? duration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final selected = mark == CellMark.selected;
    return Semantics(
      label: context.l10n.libraryShotSemantics(
        formatLabel(context, shot.format),
        shot.primary.name,
      ),
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
                size: shot.gridSize,
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
            Positioned(left: 5, bottom: 5, child: PhotoTag(_tag(context))),
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

  String _tag(BuildContext context) => switch (shot.format) {
    ShotFormat.video => switch (duration) {
      final d? => formatDuration(context, d),
      null => context.l10n.libraryTagMovie,
    },
    final f => formatLabel(context, f),
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
  const new({required this.color, required this.child});

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
  const new(this.text, {super.key});

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
