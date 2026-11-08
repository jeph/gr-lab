import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:video_player/video_player.dart';

import '../downloads/download_engine.dart';
import '../theme/tokens.dart';
import '../widgets/group.dart';
import 'format.dart';
import 'library_model.dart';
import 'library_scope.dart';
import 'movie_cache.dart';
import 'shot.dart';
import 'shot_cell.dart';

/// Full-screen viewer (mock `b-viewer`): swipe between [shots], pinch to
/// zoom, file details, and Download. A RAW+JPEG pair offers its JPEG and
/// its RAW separately. A photo shown larger than its preview, or zoomed,
/// is replaced by the full JPEG once it arrives.
class ShotViewer extends StatefulWidget {
  const ShotViewer({
    super.key,
    required this.shots,
    required this.initialIndex,
  });

  final List<Shot> shots;
  final int initialIndex;

  @override
  State<ShotViewer> createState() => _ShotViewerState();
}

class _ShotViewerState extends State<ShotViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final serial = library.model.serial;
    final shot = widget.shots[_index];
    return ListenableBuilder(
      listenable: Listenable.merge([library.model, library.engine]),
      builder: (context, _) {
        for (final f in shot.files) {
          unawaited(library.model.ensureInfo(f));
        }
        final taken = library.model.info(shot.primary)?.taken;
        return Scaffold(
          appBar: AppBar(
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
                    if (taken != null) formatDayTime(taken, DateTime.now()),
                    ?storageLabel(shot.storage),
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
                        itemCount: widget.shots.length,
                        onPageChanged: (i) => setState(() {
                          _index = i;
                          _zoomed = false;
                        }),
                        itemBuilder: (context, i) {
                          final s = widget.shots[i];
                          return s.isVideo
                              ? _VideoPage(
                                  key: ValueKey(s.key),
                                  serial: serial,
                                  shot: s,
                                  active: i == _index,
                                )
                              : _PhotoPage(
                                  key: ValueKey(s.key),
                                  serial: serial,
                                  shot: s,
                                  onZoom: (zoomed) {
                                    if (zoomed != _zoomed) {
                                      setState(() => _zoomed = zoomed);
                                    }
                                  },
                                );
                        },
                      ),
              ),
              _Details(shot: shot, model: library.model),
              if (serial != null)
                _ActionBar(serial: serial, shot: shot, engine: library.engine),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    super.key,
    required this.serial,
    required this.shot,
    required this.onZoom,
  });

  final String serial;
  final Shot shot;
  final ValueChanged<bool> onZoom;

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
    return InteractiveViewer(
      transformationController: _transform,
      maxScale: 6,
      child: SizedBox.expand(
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
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  const _VideoPage({
    super.key,
    required this.serial,
    required this.shot,
    required this.active,
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
  VideoPlayerController? _video;
  MovieDownload? _download;
  String? _error;

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (!widget.active) unawaited(_video?.pause());
  }

  @override
  void dispose() {
    _download?.cancel();
    final video = _video;
    if (video != null) unawaited(_disposePlayer(video));
    super.dispose();
  }

  /// Plays the cached copy, copying the movie from the camera first.
  Future<void> _play() async {
    final file = widget.shot.primary;
    var local = _library.movies.cached(widget.serial, file);
    if (local == null) {
      final link = _library.link.value;
      if (link == null || link.serial != widget.serial) return;
      final download = _library.movies.download(link, file);
      setState(() {
        _download = download;
        _error = null;
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
          _error = "Couldn't copy the movie from the camera";
        });
        return;
      }
      if (!current()) return;
    }
    final controller = VideoPlayerController.file(local);
    setState(() {
      _download = null;
      _video = controller;
      _error = null;
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
        _error = "This movie can't be played";
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
                : video != null
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
                      error: _error,
                      onPlay: () => unawaited(_play()),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PlayPrompt extends StatelessWidget {
  const _PlayPrompt({
    required this.canPlay,
    required this.error,
    required this.onPlay,
  });

  final bool canPlay;
  final String? error;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final note = error ?? (canPlay ? null : 'Connect to the camera to play');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          key: const ValueKey('viewer-play'),
          iconSize: 36,
          tooltip: 'Play',
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
  const _Copying({required this.download, required this.onCancel});

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
                ? 'Copying from the camera…'
                : 'Copying from the camera · ${(fraction * 100).round()}%',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.t2),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

/// Format, size and date of the shot.
class _Details extends StatelessWidget {
  const _Details({required this.shot, required this.model});

  final Shot shot;
  final LibraryModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final infos = [for (final f in shot.files) model.info(f)];
    final sizes = [for (final i in infos) i?.size];
    final size = sizes.contains(null)
        ? '…'
        : formatBytes(sizes.fold(0, (a, b) => a + b!));
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
              cell('Format', formatLabel(shot.format)),
              cell(
                shot.isVideo ? 'Length' : 'Size',
                shot.isVideo
                    ? (duration == null ? '…' : formatDuration(duration))
                    : size,
              ),
              cell(
                'Taken',
                taken == null ? '…' : formatDayTime(taken, DateTime.now()),
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
                  style: GrFonts.monoStyle(context, size: 12),
                ),
              ),
              if (shot.isVideo) Text(size, style: GrFonts.monoStyle(context)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Download for the shot; a RAW+JPEG pair gets one action per half. Saved
/// files can always be downloaded again: the app cannot see whether they
/// are still on the phone.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.serial,
    required this.shot,
    required this.engine,
  });

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
                          label: 'Download JPEG',
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
                          label: 'Download RAW',
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
                          label: 'Download',
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

/// Downloads [files] of the shot, or shows that they are queued or
/// downloading, or offers a retry when their job failed.
class _DownloadAction extends StatelessWidget {
  const _DownloadAction({
    super.key,
    required this.serial,
    required this.shot,
    required this.files,
    required this.label,
    required this.engine,
  });

  final String serial;
  final Shot shot;
  final List<CameraFile> files;
  final String label;
  final DownloadEngine engine;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final jobs = [
      for (final j in engine.jobs)
        if (j.serial == serial && j.files.any(files.contains)) j,
    ];
    bool any(DownloadState s) => jobs.any((j) => j.state == s);
    final failed = jobs
        .where((j) => j.state == DownloadState.failed)
        .firstOrNull;
    final downloaded = files.every((f) => engine.isFileDownloaded(serial, f));
    final (IconData icon, String text) = any(DownloadState.running)
        ? (Icons.downloading_rounded, 'Downloading')
        : any(DownloadState.queued)
        ? (Icons.schedule_rounded, 'Queued')
        : failed != null
        ? (Icons.refresh_rounded, 'Retry download')
        : downloaded
        ? (Icons.check_rounded, '$label again')
        : (Icons.download_rounded, label);
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
