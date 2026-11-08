import 'package:flutter/material.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../library/format.dart';
import '../library/library_scope.dart';
import '../library/shot.dart';
import '../library/shot_cell.dart';
import '../theme/tokens.dart';
import 'download_engine.dart';

/// Mini download bar floating over the grid (mock `.mini`): what is being
/// downloaded, "2 of 6 · 31 MB/s", pause/resume and cancel. Tapping it
/// opens the queue. Hidden while the queue is empty.
class DownloadBar extends StatelessWidget {
  const DownloadBar({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = LibraryScope.of(context).engine;
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        if (engine.jobs.isEmpty) return const SizedBox.shrink();
        return _Bar(engine: engine);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.engine});

  final DownloadEngine engine;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final job = engine.current ?? engine.jobs.first;
    final remaining = engine.remaining;
    final failed = engine.failedCount;
    final String title;
    if (remaining == 0) {
      title = failed == 1 ? '1 download failed' : '$failed downloads failed';
    } else if (engine.paused) {
      title = 'Downloads paused';
    } else if (engine.current != null) {
      title = 'Downloading';
    } else {
      title = 'Waiting for the camera';
    }
    final position = engine.current != null
        ? '${engine.batchDone + 1} of ${engine.batchTotal}'
        : '$remaining left';
    return Material(
      key: const ValueKey('download-bar'),
      color: c.float,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDownloadQueue(context),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
            child: Row(
              children: [
                _JobThumb(job: job),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: engine.progress,
                    builder: (context, progress, _) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          remaining == 0
                              ? 'Tap to see why'
                              : [
                                  position,
                                  if (engine.current != null &&
                                      progress.bytesPerSecond > 0)
                                    formatRate(progress.bytesPerSecond),
                                  if (failed > 0) '$failed failed',
                                ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GrFonts.monoStyle(context, size: 11.5),
                        ),
                        if (engine.current != null) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress.fraction,
                              minHeight: 3,
                              backgroundColor: c.s4,
                              color: c.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (remaining == 0)
                  TextButton(
                    onPressed: engine.retryFailed,
                    child: const Text('Retry'),
                  )
                else
                  IconButton(
                    tooltip: engine.paused ? 'Resume' : 'Pause',
                    onPressed: engine.paused ? engine.resume : engine.pause,
                    icon: Icon(
                      engine.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                  ),
                IconButton(
                  tooltip: 'Cancel all',
                  onPressed: engine.cancelAll,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobThumb extends StatelessWidget {
  const _JobThumb({required this.job, this.size = 40});

  final DownloadJob job;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: c.s3,
          child: CameraImage(
            serial: job.serial,
            file: job.shot.primary,
            size: GrImageSize.thumb,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
        ),
      ),
    );
  }
}

/// The queue: every job with its state, cancel per job and retry for
/// failed ones.
Future<void> showDownloadQueue(BuildContext context) {
  final library = LibraryScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => LibraryScope(
      library: library,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .5,
        maxChildSize: .9,
        builder: (context, controller) =>
            _QueueSheet(engine: library.engine, controller: controller),
      ),
    ),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet({required this.engine, required this.controller});

  final DownloadEngine engine;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final jobs = engine.jobs;
        return CustomScrollView(
          controller: controller,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Downloads',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (engine.failedCount > 0)
                      TextButton(
                        onPressed: engine.retryFailed,
                        child: const Text('Retry failed'),
                      ),
                    if (jobs.isNotEmpty)
                      TextButton(
                        onPressed: engine.cancelAll,
                        child: const Text('Cancel all'),
                      ),
                  ],
                ),
              ),
            ),
            if (jobs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Nothing to download',
                    style: TextStyle(color: c.t2),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: jobs.length,
                itemBuilder: (context, i) =>
                    _JobRow(engine: engine, job: jobs[i]),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.engine, required this.job});

  final DownloadEngine engine;
  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final names = job.files.map((f) => f.name).join(' + ');
    final String status;
    switch (job.state) {
      case DownloadState.running:
        status = 'Downloading';
      case DownloadState.queued:
        status = engine.paused ? 'Paused' : 'Queued';
      case DownloadState.failed:
        status = job.error ?? 'Failed';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          _JobThumb(job: job, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  names,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GrFonts.monoStyle(context, size: 13, color: c.t1),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    formatLabel(job.shot.format),
                    ?storageLabel(job.shot.storage),
                    status,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: job.state == DownloadState.failed ? c.danger : c.t2,
                  ),
                ),
              ],
            ),
          ),
          if (job.state == DownloadState.failed)
            IconButton(
              tooltip: 'Retry',
              onPressed: () => engine.retry(job),
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: 'Cancel',
            onPressed: () => engine.cancel(job),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
