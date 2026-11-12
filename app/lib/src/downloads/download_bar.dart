import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/downloads/download_engine.dart';
import 'package:grphoto/src/library/format.dart';
import 'package:grphoto/src/library/library_scope.dart';
import 'package:grphoto/src/library/shot_cell.dart';
import 'package:grphoto/src/services.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// Mini download bar floating over the grid (mock `.mini`): what is being
/// downloaded, "2 of 6 · 31 MB/s", pause/resume and cancel. Tapping it
/// opens the queue. Hidden while the queue is empty.
class DownloadBar extends StatelessWidget {
  const new({super.key});

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
  const new({required this.engine});

  final DownloadEngine engine;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final job = engine.current ?? engine.jobs.first;
    final remaining = engine.remaining;
    final failed = engine.failedCount;
    final String title;
    if (remaining == 0) {
      title = l10n.downloadBarFailed(failed);
    } else if (engine.paused) {
      title = l10n.downloadBarPaused;
    } else if (engine.current != null) {
      title = l10n.downloadBarDownloading;
    } else {
      title = l10n.downloadBarWaiting;
    }
    final position = engine.current != null
        ? l10n.downloadBarPosition(engine.batchDone + 1, engine.batchTotal)
        : l10n.downloadBarLeft(remaining);
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
                              ? l10n.downloadBarSeeWhy
                              : [
                                  position,
                                  if (engine.current != null &&
                                      progress.bytesPerSecond > 0)
                                    formatRate(
                                      context,
                                      progress.bytesPerSecond,
                                    ),
                                  if (failed > 0)
                                    l10n.downloadBarFailedCount(failed),
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
                    child: Text(l10n.downloadRetry),
                  )
                else
                  IconButton(
                    tooltip: engine.paused
                        ? l10n.downloadResume
                        : l10n.downloadPause,
                    onPressed: engine.paused ? engine.resume : engine.pause,
                    icon: Icon(
                      engine.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                  ),
                IconButton(
                  tooltip: l10n.downloadCancelAll,
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
  const new({required this.job, this.size = 40});

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
        maxChildSize: .9,
        builder: (context, controller) =>
            _QueueSheet(engine: library.engine, controller: controller),
      ),
    ),
  );
}

class _QueueSheet extends StatelessWidget {
  const new({required this.engine, required this.controller});

  final DownloadEngine engine;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
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
                    Expanded(
                      child: Text(
                        l10n.downloadQueueTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (engine.failedCount > 0)
                      TextButton(
                        onPressed: engine.retryFailed,
                        child: Text(l10n.downloadRetryFailed),
                      ),
                    if (jobs.isNotEmpty)
                      TextButton(
                        onPressed: engine.cancelAll,
                        child: Text(l10n.downloadCancelAll),
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
                    l10n.downloadQueueEmpty,
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
  const new({required this.engine, required this.job});

  final DownloadEngine engine;
  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final names = job.files.map((f) => f.name).join(' + ');
    final status = switch (job.state) {
      DownloadState.running => l10n.downloadStateRunning,
      DownloadState.queued when engine.paused => l10n.downloadStatePaused,
      DownloadState.queued => l10n.downloadStateQueued,
      DownloadState.failed => switch (job.failure) {
        final failure? => _failureMessage(l10n, failure),
        null => l10n.downloadStateFailed,
      },
    };
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
                    formatLabel(context, job.shot.format),
                    ?storageLabel(context, job.shot.storage),
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
              tooltip: l10n.downloadRetry,
              onPressed: () => engine.retry(job),
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: l10n.downloadCancel,
            onPressed: () => engine.cancel(job),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Why [failure] stopped a download, in words for the queue.
String _failureMessage(AppLocalizations l10n, DownloadFailure failure) =>
    switch (failure) {
      DownloadSaveFailed(:final reason) => switch (reason) {
        MediaSaveFailure.permissionDenied => l10n.downloadErrorNoPhotoAccess,
        MediaSaveFailure.unsupported => l10n.downloadErrorSaveUnsupported,
        MediaSaveFailure.failed => l10n.downloadErrorSaveFailed,
      },
      DownloadSaveInterrupted() => l10n.downloadErrorSaveInterrupted,
      DownloadFileGone() => l10n.downloadErrorNotOnCamera,
      DownloadTransferFailed(:final reason) => switch (reason) {
        TransferRefused(:final errCode, errMsg: null) =>
          l10n.downloadErrorRefused(errCode),
        TransferRefused(:final errCode, :final String errMsg) =>
          l10n.downloadErrorRefusedWithMessage(errCode, errMsg),
        TransferHttpStatus(:final httpStatus) => l10n.downloadErrorHttpStatus(
          httpStatus,
        ),
        TransferCutOff() => l10n.downloadErrorCutOff,
        TransferConnectionLost() => l10n.downloadErrorConnectionLost,
        TransferStalled() => l10n.downloadErrorStalled,
        TransferWriteFailed() => l10n.downloadErrorWriteFailed,
        TransferOtherError() => l10n.downloadErrorOther,
      },
    };
