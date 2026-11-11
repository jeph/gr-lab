import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/format.dart';
import 'package:grlab/src/services.dart';

/// How often transfer progress alone refreshes what the platform shows.
/// Android drops notification updates that come much faster.
const _progressInterval = Duration(seconds: 1);

/// Keeps the download queue going while GR Lab is not in front
/// ([BackgroundDownloads]), and tells the platform what to show of it: the
/// download bar's texts, with the camera's name and the progress across
/// the batch. Wraps the app below its localizations, since the texts are
/// in the app's language.
///
/// The platform's display is up while the connected camera has downloads
/// to run, paused or not, so its buttons can pause and resume them. It
/// goes when the queue is done, failed or cancelled, and when the camera's
/// Wi-Fi is gone: both platforms only join a camera's network for the app
/// in front, so nothing could go on until the user is back. \[design\]
class DownloadBackground extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<DownloadBackground> createState() => _DownloadBackgroundState();
}

class _DownloadBackgroundState extends State<DownloadBackground> {
  late final AppModels _models = AppScope.of(context);
  late final DownloadEngine _engine = _models.downloads;
  late final BackgroundDownloads _background = _models.services.background;
  late final StreamSubscription<BackgroundDownloadAction> _actions;

  /// Set by a change of the queue. It waits for the event loop's next turn
  /// because the engine reports a finished shot before it starts the next
  /// one, and the moment between is not worth showing.
  Timer? _soon;

  /// Set by transfer progress.
  Timer? _later;
  BackgroundDownloadStatus? _shown;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onQueue);
    _engine.progress.addListener(_onProgress);
    _actions = _background.actions.listen(_onAction);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The language changed.
    _onQueue();
  }

  @override
  void dispose() {
    _soon?.cancel();
    _later?.cancel();
    _engine.removeListener(_onQueue);
    _engine.progress.removeListener(_onProgress);
    unawaited(_actions.cancel());
    if (_shown != null) unawaited(_background.hide(finished: false));
    super.dispose();
  }

  void _onQueue() => _soon ??= Timer(Duration.zero, _sync);

  void _onProgress() => _later ??= Timer(_progressInterval, _sync);

  void _onAction(BackgroundDownloadAction action) {
    switch (action) {
      case BackgroundDownloadAction.pause:
        _engine.pause();
      case BackgroundDownloadAction.resume:
        _engine.resume();
      case BackgroundDownloadAction.cancel:
        _engine.cancelAll();
    }
  }

  void _sync() {
    _soon?.cancel();
    _soon = null;
    _later?.cancel();
    _later = null;
    final status = _status();
    if (status == _shown) return;
    _shown = status;
    if (status != null) {
      unawaited(_background.show(status));
      return;
    }
    final finished = _engine.remaining == 0 && _engine.failedCount == 0;
    unawaited(_background.hide(finished: finished));
  }

  /// What to show now; null when the connected camera has no download to
  /// run.
  BackgroundDownloadStatus? _status() {
    final camera = _engine.link.value;
    if (camera == null) return null;
    final serial = camera.serial;
    if (!_engine.jobs.any((j) => j.active && j.serial == serial)) return null;
    final l10n = context.l10n;
    final paused = _engine.paused;
    final transferring = !paused && _engine.current != null;
    final progress = _engine.progress.value;
    final done = _engine.batchDone;
    final total = _engine.batchTotal;
    final failed = _engine.failedCount;
    final name = _models.cameras.cameras
        .where((c) => c.serial == serial)
        .firstOrNull
        ?.name;
    return BackgroundDownloadStatus(
      paused: paused,
      title: paused ? l10n.downloadBarPaused : l10n.downloadBarDownloading,
      detail: [
        if (transferring)
          l10n.downloadBarPosition(done + 1, total)
        else
          l10n.downloadBarLeft(_engine.remaining),
        if (transferring && progress.bytesPerSecond > 0)
          formatRate(context, progress.bytesPerSecond),
        if (failed > 0) l10n.downloadBarFailedCount(failed),
      ].join(' · '),
      cameraName: name ?? '',
      fraction: ((done + (transferring ? progress.fraction : 0)) / total).clamp(
        0,
        1,
      ),
      toggleLabel: paused ? l10n.downloadResume : l10n.downloadPause,
      cancelLabel: l10n.downloadCancelAll,
      channelName: l10n.downloadQueueTitle,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
