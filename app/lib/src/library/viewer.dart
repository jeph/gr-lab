import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/connection/idle_disconnect.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/format.dart';
import 'package:grlab/src/library/library_model.dart';
import 'package:grlab/src/library/library_scope.dart';
import 'package:grlab/src/library/shot.dart';
import 'package:grlab/src/library/shot_cell.dart';
import 'package:grlab/src/looks/look_spec.dart';
import 'package:grlab/src/looks/look_widgets.dart';
import 'package:grlab/src/looks/looks_store.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';
import 'package:grlab/src/widgets/skeleton.dart';
import 'package:video_player/video_player.dart';

/// Full-screen viewer (mock `b-viewer`): swipe between [shots], pinch to
/// zoom, file details, and Download. A RAW+JPEG pair offers its JPEG and
/// its RAW separately. A photo shown larger than its preview, or zoomed,
/// is replaced by the full JPEG once it arrives; a mark in its corner says
/// so until then. A tap on a photo gives it the whole screen, and another
/// tap or Back brings the bars and the details back.
///
/// The viewer follows the camera's listing: a shot that leaves it (deleted
/// on the camera, or its card taken out) leaves the swipe list, a pair
/// that lost one half shows the other, and the viewer closes once no shot
/// is left. It also closes when the Library switches to another camera:
/// its shots are not on that camera, and it has no listing of theirs to
/// follow any more \[design\].
class ShotViewer extends StatefulWidget {
  const new({required this.shots, required this.initialIndex, super.key});

  final List<Shot> shots;
  final int initialIndex;

  @override
  State<ShotViewer> createState() => _ShotViewerState();
}

class _ShotViewerState extends State<ShotViewer> {
  late final LibraryContext _library = LibraryScope.of(context);

  /// The camera of [_shots]: the listing's camera when the viewer opened.
  late final String? _serial;

  /// [ShotViewer.shots] still in the listing, in their order, as the
  /// listing has them now.
  late final List<Shot> _shots = [...widget.shots];
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;

  /// The photo shown has the whole screen: the viewer's bars and details
  /// and the system's bars are hidden. Only photos: a movie's page takes
  /// taps for playback, and would leave no way back out on iOS.
  bool _fullscreen = false;

  /// Set once nothing is left to show: the route is on its way out and
  /// shows none of [_shots] any more.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _serial = _library.model.serial;
    _library.model.addListener(_followListing);
  }

  @override
  void dispose() {
    _library.model.removeListener(_followListing);
    _pages.dispose();
    if (_fullscreen) _showSystemBars();
    super.dispose();
  }

  void _toggleFullscreen() =>
      _fullscreen ? _leaveFullscreen() : _enterFullscreen();

  void _enterFullscreen() {
    if (_fullscreen) return;
    setState(() => _fullscreen = true);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  void _leaveFullscreen() {
    if (!_fullscreen) return;
    setState(() => _fullscreen = false);
    _showSystemBars();
  }

  /// Brings back the status and navigation bars, as the rest of the app
  /// has them (Flutter's default, edge to edge).
  void _showSystemBars() =>
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  /// Takes each shot as [_serial]'s listing has it now and drops those it
  /// no longer has. A dropped shown shot gives way to the next one kept,
  /// or to the last one when none follows. Dropping shots settles the page
  /// on [_index] at once, ending a swipe under way: its offset and fling
  /// were measured against pages that moved. Without a listing (still
  /// being read) the shots stay.
  void _followListing() {
    if (_closing) return;
    final model = _library.model;
    if (model.serial != _serial) {
      _close();
      return;
    }
    final listing = model.shots;
    if (listing == null) return;
    final listed = {for (final s in listing) s.key: s};
    final kept = [for (final s in _shots) ?listed[s.key]];
    if (listEquals(kept, _shots)) return;
    if (kept.isEmpty) {
      _close();
      return;
    }
    final shown = _shots[_index];
    final keptBefore = _shots
        .take(_index)
        .where((s) => listed.containsKey(s.key))
        .length;
    final index = min(keptBefore, kept.length - 1);
    final dropped = kept.length != _shots.length;
    setState(() {
      _shots
        ..clear()
        ..addAll(kept);
      _index = index;
      // A changed shot gets a new page (keyed by the shot), unzoomed.
      if (kept[index] != shown) _zoomed = false;
    });
    if (dropped && _pages.hasClients) _pages.jumpToPage(index);
    if (kept[index].isVideo) _leaveFullscreen();
  }

  /// Closes the viewer's route, also when another route covers it.
  void _close() {
    setState(() => _closing = true);
    _leaveFullscreen();
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  void _onPageChanged(int index) {
    // Also reported after [_followListing] jumped to [_index].
    if (index == _index) return;
    setState(() {
      _index = index;
      _zoomed = false;
    });
    if (_shots[index].isVideo) _leaveFullscreen();
  }

  @override
  Widget build(BuildContext context) {
    if (_closing) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    final library = _library;
    final serial = _serial;
    final shot = _shots[_index];
    final fullscreen = _fullscreen;
    return PopScope(
      canPop: !fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveFullscreen();
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([library.model, library.engine]),
        builder: (context, _) {
          for (final f in shot.files) {
            unawaited(library.model.ensureInfo(f));
          }
          final taken = library.model.info(shot.primary)?.taken;
          return Scaffold(
            backgroundColor: fullscreen ? Colors.black : null,
            appBar: fullscreen
                ? null
                : AppBar(
                    leading: const BackButton(),
                    title: Column(
                      children: [
                        Text(
                          shot.primary.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            if (taken != null)
                              formatDayTime(context, taken, DateTime.now()),
                            ?storageLabel(context, shot.storage),
                          ].join(' · '),
                          style: GrFonts.monoStyle(context, size: 11),
                        ),
                      ],
                    ),
                  ),
            body: Column(
              children: [
                Expanded(
                  child: serial == null
                      ? const SizedBox.shrink()
                      : PageView.builder(
                          controller: _pages,
                          physics: _zoomed
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          itemCount: _shots.length,
                          onPageChanged: _onPageChanged,
                          // A page whose shot stays keeps its state (zoom,
                          // playback) when shots before it are dropped.
                          findChildIndexCallback: (key) {
                            final i = _shots.indexWhere(
                              (s) => ValueKey(s) == key,
                            );
                            return i < 0 ? null : i;
                          },
                          itemBuilder: (context, i) {
                            final s = _shots[i];
                            return s.isVideo
                                ? _VideoPage(
                                    key: ValueKey(s),
                                    serial: serial,
                                    shot: s,
                                    active: i == _index,
                                  )
                                : _PhotoPage(
                                    key: ValueKey(s),
                                    serial: serial,
                                    shot: s,
                                    onZoom: (zoomed) {
                                      if (zoomed != _zoomed) {
                                        setState(() => _zoomed = zoomed);
                                      }
                                    },
                                    onTap: _toggleFullscreen,
                                  );
                          },
                        ),
                ),
                // Hidden, not dropped, while the photo has the screen: the
                // details keep what they read from the camera.
                Offstage(
                  offstage: fullscreen,
                  child: Column(
                    children: [
                      _Details(shot: shot, model: library.model),
                      if (serial != null)
                        _ActionBar(
                          serial: serial,
                          shot: shot,
                          engine: library.engine,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoPage extends StatefulWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.onZoom,
    required this.onTap,
    super.key,
  });

  final String serial;
  final Shot shot;
  final ValueChanged<bool> onZoom;

  /// The photo was tapped, not pinched or dragged.
  final VoidCallback onTap;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      widget.onZoom(zoomed);
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.shot;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: CameraImage(
        serial: widget.serial,
        file: shot.primary,
        size: GrImageSize.view,
        fit: BoxFit.contain,
        // Only a JPEG's full file decodes; a DNG stays at its preview.
        sharper: shot.jpeg != null ? GrImageSize.full : null,
        wantSharper: _zoomed,
        // Detail for zooming in, without decoding all 26 megapixels.
        zoomHeadroom: 3,
        // The grid already loaded this `view`; no smaller stand-in that
        // would be swapped out.
        showProgress: true,
        // The mark is outside the zoomed picture, so it keeps its corner.
        builder:
            (context, image, {required aspectRatio, required sharpening}) =>
                Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      transformationController: _transform,
                      // Pinching out ends at the photo fitted to its page.
                      minScale: 1,
                      maxScale: 6,
                      child: SizedBox.expand(child: image),
                    ),
                    if (sharpening) _Sharpening(aspectRatio: aspectRatio),
                  ],
                ),
      ),
    );
  }
}

/// Says that the picture shown is a soft stand-in for the sharper copy on
/// its way, from the top corner of the photo as it lies fitted to its
/// page ([aspectRatio] is its width over its height; null takes the
/// page's corner).
class _Sharpening extends StatelessWidget {
  const new({required this.aspectRatio});

  final double? aspectRatio;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final page = constraints.biggest;
      final ratio = aspectRatio;
      final photo = ratio == null
          ? page
          : applyBoxFit(BoxFit.contain, Size(ratio, 1), page).destination;
      // Clear of the status bar and the camera cut-out when the photo has
      // the whole screen.
      final safe = MediaQuery.paddingOf(context);
      return Stack(
        children: [
          PositionedDirectional(
            top: max((page.height - photo.height) / 2, safe.top) + 12,
            end:
                max(
                  (page.width - photo.width) / 2,
                  max(safe.left, safe.right),
                ) +
                12,
            child: IgnorePointer(
              child: Semantics(
                label: context.l10n.viewerSharpening,
                child: Container(
                  key: const Key('viewer-sharpening'),
                  width: 30,
                  height: 30,
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: GrColors.photoBadgeScrim,
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _VideoPage extends StatefulWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.active,
    super.key,
  });

  final String serial;
  final Shot shot;

  /// Only the page on screen plays.
  final bool active;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final LibraryContext _library = LibraryScope.of(context);
  late final IdleDisconnect _idle = AppScope.of(context).idle;
  VideoPlayerController? _video;
  MovieDownload? _download;
  _MovieProblem? _problem;

  /// Set while Play waits for the camera to confirm the movie, so a
  /// second tap can't start a second copy or player.
  bool _checking = false;

  /// Keeps the movie's copy on disk while the page shows: the player
  /// reads the file without asking the cache again.
  CacheHold? _movieHold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _movieHold ??= _library.movies.hold(widget.serial, widget.shot.primary);
  }

  /// Set while a movie copy or playback keeps the camera's Wi-Fi up.
  VoidCallback? _release;

  void _holdWhileBusy() {
    final busy = _download != null || (_video?.value.isPlaying ?? false);
    if (busy && _release == null) {
      _release = _idle.hold();
    } else if (!busy && _release != null) {
      _release!();
      _release = null;
    }
  }

  /// Every change of [_download] or [_video] goes through here.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _holdWhileBusy();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (!widget.active) unawaited(_video?.pause());
  }

  @override
  void dispose() {
    _movieHold?.release();
    _release?.call();
    _download?.cancel();
    final video = _video;
    if (video != null) {
      video.removeListener(_holdWhileBusy);
      unawaited(_disposePlayer(video));
    }
    super.dispose();
  }

  /// Plays the cached copy, copying the movie from the camera first. While
  /// connected, the camera first confirms the cached copy is of the movie
  /// now at its path (the library drops it otherwise).
  Future<void> _play() async {
    if (_checking || _download != null || _video != null) return;
    final file = widget.shot.primary;
    setState(() {
      _checking = true;
      _problem = null;
    });
    await _library.model.ensureInfo(file);
    if (!mounted) return;
    setState(() => _checking = false);
    var local = _library.movies.cached(widget.serial, file);
    if (local == null) {
      final link = _library.link.value;
      if (link == null || link.serial != widget.serial) return;
      final download = _library.movies.download(link, file);
      setState(() {
        _download = download;
        _problem = null;
      });
      // Only the attempt still on screen may change the page: a cancelled
      // one settles later, possibly after Play started a new attempt.
      bool current() => mounted && identical(_download, download);
      try {
        local = await download.done;
      } on MovieDownloadCancelled {
        if (current()) setState(() => _download = null);
        return;
      } on Object {
        if (!current()) return;
        setState(() {
          _download = null;
          _problem = _MovieProblem.copyFailed;
        });
        return;
      }
      if (!current()) return;
    }
    final controller = VideoPlayerController.file(local)
      ..addListener(_holdWhileBusy);
    setState(() {
      _download = null;
      _video = controller;
      _problem = null;
    });
    try {
      await controller.initialize();
      if (!mounted || !widget.active) return;
      await controller.play();
      if (mounted) setState(() {});
    } on Object {
      unawaited(_disposePlayer(controller));
      if (!mounted) return;
      setState(() {
        _video = null;
        _problem = _MovieProblem.unplayable;
      });
    }
  }

  /// A player that failed to initialise may fail to dispose too; there is
  /// nothing left to release then.
  Future<void> _disposePlayer(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } on Object {
      return;
    }
  }

  void _cancel() {
    _download?.cancel();
    setState(() => _download = null);
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    if (video != null && video.value.isInitialized) {
      return GestureDetector(
        onTap: () =>
            unawaited(video.value.isPlaying ? video.pause() : video.play()),
        child: Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(video),
                VideoProgressIndicator(video, allowScrubbing: true),
              ],
            ),
          ),
        ),
      );
    }
    final download = _download;
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraImage(
          serial: widget.serial,
          file: widget.shot.primary,
          size: GrImageSize.thumb,
          fit: BoxFit.contain,
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: download != null
                ? _Copying(download: download, onCancel: _cancel)
                : video != null || _checking
                ? const CircularProgressIndicator()
                : ValueListenableBuilder(
                    valueListenable: _library.link,
                    builder: (context, link, _) => _PlayPrompt(
                      canPlay:
                          link?.serial == widget.serial ||
                          _library.movies.cached(
                                widget.serial,
                                widget.shot.primary,
                              ) !=
                              null,
                      problem: _problem,
                      onPlay: () => unawaited(_play()),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Why the movie is not playing.
enum _MovieProblem { copyFailed, unplayable }

class _PlayPrompt extends StatelessWidget {
  const new({
    required this.canPlay,
    required this.problem,
    required this.onPlay,
  });

  final bool canPlay;
  final _MovieProblem? problem;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final note = switch (problem) {
      _MovieProblem.copyFailed => l10n.viewerMovieCopyFailed,
      _MovieProblem.unplayable => l10n.viewerMovieUnplayable,
      null when !canPlay => l10n.viewerConnectToPlay,
      null => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          key: const ValueKey('viewer-play'),
          iconSize: 36,
          tooltip: l10n.viewerPlay,
          onPressed: canPlay ? onPlay : null,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
        if (note != null) ...[
          const SizedBox(height: 10),
          Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.t2),
          ),
        ],
      ],
    );
  }
}

/// Progress while the movie is copied from the camera, with Cancel.
class _Copying extends StatelessWidget {
  const new({required this.download, required this.onCancel});

  final MovieDownload download;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return ValueListenableBuilder(
      valueListenable: download.progress,
      builder: (context, fraction, _) => Column(
        key: const ValueKey('viewer-movie-copy'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(value: fraction),
          ),
          const SizedBox(height: 12),
          Text(
            fraction == null
                ? context.l10n.viewerCopying
                : context.l10n.viewerCopyingProgress(fraction),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.t2),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onCancel,
            child: Text(context.l10n.viewerCancel),
          ),
        ],
      ),
    );
  }
}

/// Format, size and date of the shot.
class _Details extends StatelessWidget {
  const new({required this.shot, required this.model});

  final Shot shot;
  final LibraryModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final infos = [for (final f in shot.files) model.info(f)];
    final sizes = [for (final i in infos) i?.size];
    final size = sizes.contains(null)
        ? '…'
        : formatBytes(context, sizes.fold(0, (a, b) => a + b!));
    final taken = model.info(shot.primary)?.taken;
    final duration = model.info(shot.primary)?.duration;
    final label = TextStyle(fontSize: 11.5, color: c.t3);
    final value = GrFonts.monoStyle(context, size: 13.5, color: c.t1);
    Widget cell(String title, String text) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: label),
          const SizedBox(height: 3),
          Text(text, style: value, maxLines: 1, overflow: TextOverflow.fade),
        ],
      ),
    );
    return GroupBox(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              cell(l10n.viewerFormat, formatLabel(context, shot.format)),
              cell(
                shot.isVideo ? l10n.viewerLength : l10n.viewerSize,
                shot.isVideo
                    ? (duration == null
                          ? '…'
                          : formatDuration(context, duration))
                    : size,
              ),
              cell(
                l10n.viewerTaken,
                taken == null
                    ? '…'
                    : formatDayTime(context, taken, DateTime.now()),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shot.files.map((f) => f.name).join(' + '),
                  style: GrFonts.monoStyle(context),
                ),
              ),
              if (shot.isVideo) Text(size, style: GrFonts.monoStyle(context)),
            ],
          ),
        ),
        if (!shot.isVideo)
          // Read again when the primary changes: a pair whose JPEG left
          // the camera shows its RAW.
          _ImageControlRow(key: ValueKey(shot.primary.key), shot: shot),
      ],
    );
  }
}

/// The Image Control the photo was shot with, read from the camera, and
/// Save look (mock `b-viewer`; GR WORLD's "save image control from
/// images"). A skeleton of the row while the camera is asked; hidden while
/// the camera is not connected or has none for the photo.
class _ImageControlRow extends StatefulWidget {
  const new({required this.shot, super.key});

  final Shot shot;

  @override
  State<_ImageControlRow> createState() => _ImageControlRowState();
}

class _ImageControlRowState extends State<_ImageControlRow> {
  late final LibraryContext _library = LibraryScope.of(context);
  Look? _look;

  /// The camera is being asked for the photo's Image Control.
  bool _reading = false;
  bool _saving = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final link = _library.link.value;
    if (link == null) return;
    _reading = true;
    unawaited(_read(link));
  }

  Future<void> _read(CameraLibrary link) async {
    Look? look;
    try {
      look = await link.imageControl(widget.shot.primary);
    } on Object {
      // No Image Control for this file, or the camera did not answer: the
      // row hides; the camera layer traced the exchange.
    }
    if (!mounted) return;
    setState(() {
      _look = look;
      _reading = false;
    });
  }

  Future<void> _save(Look look) async {
    final l10n = context.l10n;
    final store = AppScope.of(context).looks;
    final messenger = ScaffoldMessenger.of(context);
    final name = await askLookName(context, initial: lookBaseLabel(l10n, look));
    if (name == null || !mounted) return;
    setState(() => _saving = true);
    final serial = _library.model.serial;
    final file = widget.shot.primary;
    final photo = serial == null
        ? null
        : await _library.images
              .load(serial, file, GrImageSize.view)
              .future
              .then<Uint8List?>((b) => b, onError: (Object _) => null);
    try {
      await store.add(
        name: name,
        data: look.toBytes(),
        source: file.name,
        photo: photo,
      );
      showLooksMessage(messenger, l10n.looksSaved(name));
    } on LookConflict catch (conflict) {
      if (mounted) unawaited(showLookConflict(context, conflict));
    } on FileSystemException {
      showLooksMessage(messenger, l10n.looksSaveFailed(name));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;
    if (look == null) {
      return _reading ? const _ImageControlSkeleton() : const SizedBox.shrink();
    }
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          const _ImageControlRowHeight(),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.tune_rounded, size: 18, color: c.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.viewerImageControl,
                  style: const TextStyle(fontSize: _imageControlTitleSize),
                ),
                Text(
                  lookSummary(l10n, look),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _imageControlSummarySize,
                    color: c.t2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('viewer-save-look'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                fontFamily: GrFonts.ui,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: _saving ? null : () => unawaited(_save(look)),
            child: Text(l10n.viewerSaveLook),
          ),
        ],
      ),
    );
  }
}

/// Text sizes of [_ImageControlRow], shared with its skeleton and
/// [_ImageControlRowHeight].
const _imageControlTitleSize = 14.5;
const _imageControlSummarySize = 12.0;

/// As tall as [_ImageControlRow]'s title over a summary of two lines, and
/// of no width: in the row and in its skeleton, it keeps both at that
/// height whatever the summary's length, so the row replaces the skeleton
/// without moving the photo above.
class _ImageControlRowHeight extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spaces: a line without a glyph is laid out a little lower.
          Text(' ', style: TextStyle(fontSize: _imageControlTitleSize)),
          Text(' \n ', style: TextStyle(fontSize: _imageControlSummarySize)),
        ],
      ),
    ),
  );
}

/// [_ImageControlRow] while the camera is asked: its icon, its title, its
/// summary and Save look as blocks.
class _ImageControlSkeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const Padding(
    key: Key('viewer-image-control-loading'),
    padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: Skeleton(
      child: Row(
        children: [
          _ImageControlRowHeight(),
          SkeletonBox(width: 34, height: 34, radius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 96, fontSize: _imageControlTitleSize),
                SkeletonLine(width: 168, fontSize: _imageControlSummarySize),
              ],
            ),
          ),
          SizedBox(width: 8),
          SkeletonBox(width: 92, height: 36, radius: 18),
        ],
      ),
    ),
  );
}

/// Download for the shot; a RAW+JPEG pair gets one action per half. Saved
/// files can always be downloaded again: the app cannot see whether they
/// are still on the phone.
class _ActionBar extends StatelessWidget {
  const new({required this.serial, required this.shot, required this.engine});

  final String serial;
  final Shot shot;
  final DownloadEngine engine;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: shot.isPair
                  ? [
                      Flexible(
                        child: _DownloadAction(
                          key: const ValueKey('viewer-download:jpeg'),
                          serial: serial,
                          shot: shot,
                          files: [shot.jpeg!],
                          kind: _DownloadKind.jpeg,
                          engine: engine,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: _DownloadAction(
                          key: const ValueKey('viewer-download:raw'),
                          serial: serial,
                          shot: shot,
                          files: [shot.raw!],
                          kind: _DownloadKind.raw,
                          engine: engine,
                        ),
                      ),
                    ]
                  : [
                      Flexible(
                        child: _DownloadAction(
                          key: const ValueKey('viewer-download'),
                          serial: serial,
                          shot: shot,
                          files: shot.files,
                          kind: _DownloadKind.all,
                          engine: engine,
                        ),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which files of the shot a [_DownloadAction] fetches. The names are the
/// `kind` of the `viewerDownload` messages.
enum _DownloadKind { jpeg, raw, all }

/// Downloads [files] of the shot, or shows that they are queued or
/// downloading, or offers a retry when their job failed.
class _DownloadAction extends StatelessWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.files,
    required this.kind,
    required this.engine,
    super.key,
  });

  final String serial;
  final Shot shot;
  final List<CameraFile> files;
  final _DownloadKind kind;
  final DownloadEngine engine;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final jobs = [
      for (final j in engine.jobs)
        if (j.serial == serial && j.files.any(files.contains)) j,
    ];
    bool any(DownloadState s) => jobs.any((j) => j.state == s);
    final failed = jobs
        .where((j) => j.state == DownloadState.failed)
        .firstOrNull;
    final downloaded = engine.areFilesDownloaded(serial, files);
    final (IconData icon, String text) = any(DownloadState.running)
        ? (Icons.downloading_rounded, l10n.viewerDownloading)
        : any(DownloadState.queued)
        ? (Icons.schedule_rounded, l10n.viewerQueued)
        : failed != null
        ? (Icons.refresh_rounded, l10n.viewerRetryDownload)
        : downloaded
        ? (Icons.check_rounded, l10n.viewerDownloadAgain(kind.name))
        : (Icons.download_rounded, l10n.viewerDownload(kind.name));
    final VoidCallback? onTap;
    if (any(DownloadState.running) || any(DownloadState.queued)) {
      onTap = null;
    } else if (failed != null) {
      onTap = () => engine.retry(failed);
    } else {
      onTap = () => unawaited(engine.enqueueFiles(serial, shot, files));
    }
    return InkWell(
      borderRadius: BorderRadius.circular(GrRadii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap == null ? c.t3 : c.t1),
            const SizedBox(height: 4),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: c.t1,
              ),
            ),
            if (any(DownloadState.running))
              ValueListenableBuilder(
                valueListenable: engine.progress,
                builder: (context, p, _) => SizedBox(
                  width: 64,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: p.fraction,
                      minHeight: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
