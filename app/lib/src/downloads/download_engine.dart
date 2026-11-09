import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/data/json_file.dart';
import 'package:grlab/src/library/shot.dart';
import 'package:grlab/src/services.dart';

enum DownloadState {
  /// Waiting for its turn, for its camera to connect, or for
  /// [DownloadEngine.resume].
  queued,
  running,

  /// Stopped by an error; [DownloadEngine.retry] queues it again.
  failed,
}

/// Why a job failed; the queue puts it into words.
sealed class DownloadFailure {
  const new();
}

/// Copying a file from the camera failed.
final class DownloadTransferFailed extends DownloadFailure {
  const new(this.reason);
  final TransferFailure reason;
}

/// The photo library did not take the shot.
final class DownloadSaveFailed extends DownloadFailure {
  const new(this.reason);
  final MediaSaveFailure reason;
}

/// One shot's files in the download queue.
final class DownloadJob {
  new _({
    required this.id,
    required this.serial,
    required this.shot,
    required this._files,
    this.state = DownloadState.queued,
    this.failure,
  });

  final String id;

  /// The camera the files are on.
  final String serial;
  final Shot shot;
  List<CameraFile> _files;
  DownloadState state;

  /// Why the job failed.
  DownloadFailure? failure;

  /// The files this job saves: the kinds asked for, for a pair one or
  /// both halves.
  List<CameraFile> get files => List.unmodifiable(_files);

  bool get active => state != DownloadState.failed;

  Map<String, Object?> _toJson() => {
    'id': id,
    'serial': serial,
    'shot': [for (final f in shot.files) _fileToJson(f)],
    'files': [for (final f in _files) _fileToJson(f)],
    'state': state == DownloadState.failed ? 'failed' : 'queued',
    'error': ?_failureToJson(failure),
  };

  static DownloadJob? _fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final serial = json['serial'];
    if (id is! String || serial is! String) return null;
    final shotFiles = _filesFromJson(json['shot']);
    final files = _filesFromJson(json['files']);
    final shots = groupShots(shotFiles);
    if (shots.length != 1 || files.isEmpty) return null;
    final failed = json['state'] == 'failed';
    return DownloadJob._(
      id: id,
      serial: serial,
      shot: shots.single,
      files: files,
      state: failed ? DownloadState.failed : DownloadState.queued,
      failure: failed ? _failureFromJson(json['error']) : null,
    );
  }
}

Map<String, Object?>? _failureToJson(DownloadFailure? failure) =>
    switch (failure) {
      null => null,
      DownloadSaveFailed(:final reason) => {'save': reason.name},
      DownloadTransferFailed(:final reason) => switch (reason) {
        TransferRefused(:final errCode, :final errMsg) => {
          'transfer': 'refused',
          'errCode': errCode,
          'errMsg': ?errMsg,
        },
        TransferHttpStatus(:final httpStatus) => {
          'transfer': 'httpStatus',
          'httpStatus': httpStatus,
        },
        TransferCutOff() => {'transfer': 'cutOff'},
        TransferConnectionLost() => {'transfer': 'connectionLost'},
        TransferStalled() => {'transfer': 'stalled'},
        TransferWriteFailed() => {'transfer': 'writeFailed'},
        TransferOtherError() => {'transfer': 'other'},
      },
    };

/// A failure saved by [_failureToJson]; null for anything else, such as the
/// English sentences saved before failures were typed.
DownloadFailure? _failureFromJson(Object? json) {
  if (json is! Map<String, Object?>) return null;
  if (json['save'] case final String save) {
    final reason = MediaSaveFailure.values.asNameMap()[save];
    return reason == null ? null : DownloadSaveFailed(reason);
  }
  final reason = switch (json) {
    {'transfer': 'refused', 'errCode': final int errCode} => TransferRefused(
      errCode: errCode,
      errMsg: switch (json['errMsg']) {
        final String m => m,
        _ => null,
      },
    ),
    {'transfer': 'httpStatus', 'httpStatus': final int status} =>
      TransferHttpStatus(status),
    {'transfer': 'cutOff'} => const TransferCutOff(),
    {'transfer': 'connectionLost'} => const TransferConnectionLost(),
    {'transfer': 'stalled'} => const TransferStalled(),
    {'transfer': 'writeFailed'} => const TransferWriteFailed(),
    {'transfer': 'other'} => const TransferOtherError(),
    _ => null,
  };
  return reason == null ? null : DownloadTransferFailed(reason);
}

Map<String, Object?> _fileToJson(CameraFile f) => {
  's': f.storage,
  'd': f.dir,
  'f': f.name,
};

List<CameraFile> _filesFromJson(Object? json) {
  final files = <CameraFile>[];
  if (json is! List<Object?>) return files;
  for (final e in json) {
    if (e is! Map<String, Object?>) continue;
    final storage = e['s'];
    final dir = e['d'];
    final file = e['f'];
    if (dir is! String || file is! String) continue;
    try {
      files.add(
        CameraFile(storage is String ? storage : null, GrPhotoPath(dir, file)),
      );
    } on FormatException {
      continue;
    }
  }
  return files;
}

/// Why the running transfer is being stopped.
enum _Stop { cancel, pause }

final class _StopSignal implements Exception {
  const new(this.reason);
  final _Stop reason;
}

/// Transfer progress of the running job.
@immutable
final class DownloadProgress {
  const new({this.received = 0, this.fraction = 0, this.bytesPerSecond = 0});

  /// Bytes of the running job received so far.
  final int received;

  /// 0..1 across the job's files.
  final double fraction;
  final double bytesPerSecond;
}

/// Downloads shots from the camera into the phone's photo library, one file
/// at a time.
///
/// The queue and the record of downloaded files live in
/// `<dataDir>/downloads.json`, so the queue survives restarts and badges know
/// what is already on the phone. Files go to `<cacheDir>/downloads/<job>/`
/// first and are handed to [MediaSaver] per shot. A transfer interrupted by
/// a lost connection or a pause restarts that file from the beginning once
/// the camera is back (the camera has no ranged downloads).
final class DownloadEngine extends ChangeNotifier {
  new({
    required this.dataDir,
    required this.cacheDir,
    required this.media,
    required this.link,
    this.album = 'GR',
    this.transportGrace = const Duration(seconds: 3),
    this.progressInterval = const Duration(milliseconds: 100),
  }) {
    _ready = _load().whenComplete(() {
      // Restored jobs start if their camera is already connected, and the
      // loaded records show as badges.
      if (_disposed) return;
      _kick();
      _notify();
    });
    link.addListener(_onLink);
  }

  final Directory dataDir;
  final Directory cacheDir;
  final MediaSaver media;
  final ValueListenable<CameraLibrary?> link;
  final String album;

  /// After a network error, how long to wait for the connection to report
  /// it lost before the job counts as failed instead of paused.
  final Duration transportGrace;
  final Duration progressInterval;

  late final Future<void> _ready;
  late final JsonFile _file = JsonFile(File('${dataDir.path}/downloads.json'));
  final List<DownloadJob> _jobs = [];
  final Map<String, Set<String>> _downloaded = {};
  int _nextId = 0;

  bool _looping = false;
  Completer<void>? _idle;
  bool _paused = false;
  DownloadJob? _current;
  CameraLibrary? _currentLink;
  _Stop? _stop;
  int _batchDone = 0;
  MediaSaveException? _permissionProblem;
  bool _disposed = false;

  final ValueNotifier<DownloadProgress> progress = ValueNotifier(
    const DownloadProgress(),
  );
  final List<(Duration, int)> _samples = [];
  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastProgress = Duration.zero;

  /// Completes when the saved queue and records are loaded.
  Future<void> get ready => _ready;

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);

  /// The job being transferred or saved.
  DownloadJob? get current => _current;

  /// Paused by the user.
  bool get paused => _paused;

  /// Jobs not yet done (queued or running).
  int get remaining => _jobs.where((j) => j.active).length;
  int get failedCount =>
      _jobs.where((j) => j.state == DownloadState.failed).length;

  /// Shots finished since the queue was last empty: "Downloading
  /// [batchDone] + 1 of [batchTotal]".
  int get batchDone => _batchDone;
  int get batchTotal => _batchDone + remaining;

  /// Queued jobs wait because their camera is not connected.
  bool get waitingForCamera =>
      !_paused &&
      _current == null &&
      _jobs.any((j) => j.state == DownloadState.queued);

  /// Set when the photo library refused access; the queue was failed. Shown
  /// once, then cleared with [dismissPermissionProblem].
  MediaSaveException? get permissionProblem => _permissionProblem;

  void dismissPermissionProblem() {
    if (_permissionProblem == null) return;
    _permissionProblem = null;
    _notify();
  }

  bool isFileDownloaded(String serial, CameraFile f) =>
      _downloaded[serial]?.contains(f.key) ?? false;

  /// Some file of [shot] was saved to the phone. The app cannot see whether
  /// it is still in the photo library, so this is a hint only: it never
  /// stops a download.
  bool isShotDownloaded(String serial, Shot shot) =>
      shot.files.any((f) => isFileDownloaded(serial, f));

  /// Files of [serial]'s camera in a queued or running job.
  bool isFileQueued(String serial, CameraFile f) =>
      _jobs.any((j) => j.active && j.serial == serial && j._files.contains(f));

  /// The job holding [shot], if any.
  DownloadJob? jobFor(String serial, Shot shot) {
    for (final j in _jobs) {
      if (j.serial == serial && j.shot.key == shot.key) return j;
    }
    return null;
  }

  /// What downloading [shot]'s files of [kind] would fetch: those not
  /// already waiting in the queue. Files saved before come again.
  List<CameraFile> filesToDownload(String serial, Shot shot, FileKind kind) => [
    for (final f in shot.filesOf(kind))
      if (!isFileQueued(serial, f)) f,
  ];

  /// Queues the files of [kinds] (every file by default) of [shots] of
  /// [serial]'s camera, skipping files already queued. Files downloaded
  /// before are downloaded again: the user may have deleted them from the
  /// phone. Returns the number of files added.
  Future<int> enqueue(
    String serial,
    Iterable<Shot> shots, {
    Set<FileKind> kinds = const {FileKind.jpeg, FileKind.raw, FileKind.movie},
  }) async {
    await _ready;
    var added = 0;
    for (final shot in shots) {
      added += _add(serial, shot, [
        for (final f in shot.files)
          if (kinds.contains(fileKind(f.extension))) f,
      ]);
    }
    if (added > 0) _changed();
    return added;
  }

  /// Queues specific files of one shot (the viewer's JPEG or RAW of a
  /// pair). Returns the number of files added.
  Future<int> enqueueFiles(
    String serial,
    Shot shot,
    List<CameraFile> files,
  ) async {
    await _ready;
    final added = _add(serial, shot, [
      for (final f in files)
        if (shot.files.contains(f)) f,
    ]);
    if (added > 0) _changed();
    return added;
  }

  int _add(String serial, Shot shot, List<CameraFile> wanted) {
    final files = [
      for (final f in wanted)
        if (!isFileQueued(serial, f)) f,
    ];
    if (files.isEmpty) return 0;
    // A waiting or failed job for the same shot takes the files, so one
    // shot stays one queue entry and one save.
    for (final j in _jobs) {
      if (j.serial == serial &&
          j.shot.key == shot.key &&
          j.state != DownloadState.running) {
        j
          .._files = {...j._files, ...files}.toList()
          ..state = DownloadState.queued
          ..failure = null;
        return files.length;
      }
    }
    _jobs.add(
      DownloadJob._(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
        serial: serial,
        shot: shot,
        files: files,
      ),
    );
    return files.length;
  }

  /// Removes [job]; a running transfer stops and its partial files are
  /// deleted.
  void cancel(DownloadJob job) {
    if (identical(job, _current)) {
      _stop = _Stop.cancel;
      _notify();
      return;
    }
    if (!_jobs.remove(job)) return;
    unawaited(_deleteTemp(job));
    _changed();
  }

  /// Removes every job.
  void cancelAll() {
    for (final j in _jobs.toList()) {
      if (identical(j, _current)) continue;
      _jobs.remove(j);
      unawaited(_deleteTemp(j));
    }
    if (_current != null) _stop = _Stop.cancel;
    _changed();
  }

  /// Queues a failed [job] again.
  void retry(DownloadJob job) {
    if (job.state != DownloadState.failed || !_jobs.contains(job)) return;
    job
      ..state = DownloadState.queued
      ..failure = null;
    _changed();
  }

  void retryFailed() {
    var any = false;
    for (final j in _jobs) {
      if (j.state != DownloadState.failed) continue;
      j
        ..state = DownloadState.queued
        ..failure = null;
      any = true;
    }
    if (any) _changed();
  }

  /// Stops transferring; the running file restarts on [resume].
  void pause() {
    if (_paused) return;
    _paused = true;
    if (_current != null) _stop ??= _Stop.pause;
    _changed();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _changed();
  }

  /// Completes when no job is running (the queue is empty, paused, failed or
  /// waiting for a camera).
  Future<void> whenIdle() async {
    await _ready;
    await (_idle?.future ?? Future<void>.value());
  }

  void _onLink() {
    final current = _currentLink;
    if (current != null && !identical(link.value, current)) {
      _stop ??= _Stop.pause;
    }
    _kick();
    _notify();
  }

  void _changed() {
    _save();
    _kick();
    _notify();
  }

  void _kick() {
    if (_looping || _disposed) return;
    _looping = true;
    _idle = Completer<void>();
    unawaited(_loop());
  }

  Future<void> _loop() async {
    try {
      await _ready;
      while (!_disposed && !_paused) {
        final current = link.value;
        if (current == null) break;
        final job = _jobs
            .where(
              (j) =>
                  j.state == DownloadState.queued && j.serial == current.serial,
            )
            .firstOrNull;
        if (job == null) break;
        await _run(job, current);
      }
    } finally {
      _looping = false;
      if (remaining == 0) _batchDone = 0;
      _idle?.complete();
      _idle = null;
      _notify();
    }
  }

  Directory _tempDir(DownloadJob job) =>
      Directory('${cacheDir.path}/downloads/${job.id}');

  Future<void> _deleteTemp(DownloadJob job) async {
    try {
      final dir = _tempDir(job);
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // A leftover in the cache directory is harmless.
    }
  }

  Future<void> _run(DownloadJob job, CameraLibrary current) async {
    _current = job;
    _currentLink = current;
    _stop = null;
    job
      ..state = DownloadState.running
      ..failure = null;
    _samples.clear();
    _setProgress(const DownloadProgress());
    _notify();
    try {
      // Every file comes, even one saved before: the user asked again,
      // perhaps after deleting it from the phone.
      final files = List.of(job._files);
      final local = await _transfer(job, files, current);
      await media.saveShot(local, album: album);
      _downloaded.putIfAbsent(job.serial, () => {}).addAll([
        for (final f in files) f.key,
      ]);
      if (_stop == _Stop.cancel) throw const _StopSignal(_Stop.cancel);
      _jobs.remove(job);
      _batchDone++;
      await _deleteTemp(job);
    } on _StopSignal catch (s) {
      _stopped(job, s.reason);
    } on MediaSaveException catch (e) {
      if (e.permissionDenied) {
        _permissionProblem = e;
        for (final j in _jobs) {
          if (j.active) _fail(j, DownloadSaveFailed(e.failure), e);
        }
      } else if (_stop == _Stop.cancel) {
        _stopped(job, _Stop.cancel);
      } else {
        _fail(job, DownloadSaveFailed(e.failure), e);
      }
    } on Object catch (e) {
      // A cancel or pause can arrive while waiting out the grace period; it
      // wins over the network error.
      final lost = _stop == null && await _connectionLost(e, current);
      if (_stop case final reason?) {
        _stopped(job, reason);
      } else if (lost) {
        job.state = DownloadState.queued;
      } else {
        _fail(job, DownloadTransferFailed(TransferFailure.of(e)), e);
      }
    } finally {
      _current = null;
      _currentLink = null;
      _stop = null;
      _setProgress(const DownloadProgress());
      _save();
      _notify();
    }
  }

  void _stopped(DownloadJob job, _Stop reason) {
    switch (reason) {
      case _Stop.cancel:
        _jobs.remove(job);
        unawaited(_deleteTemp(job));
      case _Stop.pause:
        job.state = DownloadState.queued;
    }
  }

  /// [error] goes to the debug log; the queue shows [failure].
  void _fail(DownloadJob job, DownloadFailure failure, Object error) {
    debugPrint('Download of ${job.shot} failed: $error');
    job
      ..state = DownloadState.failed
      ..failure = failure;
  }

  /// Network errors usually mean the camera's Wi-Fi went away; give the
  /// connection a moment to notice before blaming the job.
  Future<bool> _connectionLost(Object error, CameraLibrary current) async {
    if (!identical(link.value, current)) return true;
    if (!isConnectionError(error)) return false;
    await Future<void>.delayed(transportGrace);
    return !identical(link.value, current);
  }

  Future<List<File>> _transfer(
    DownloadJob job,
    List<CameraFile> files,
    CameraLibrary current,
  ) => current.downloadFiles(
    files,
    _tempDir(job),
    onProgress: (bytes, index, received, total) {
      if (_stop case final reason?) throw _StopSignal(reason);
      _progress(bytes, index, files.length, received, total);
    },
    afterFile: () {
      if (_stop case final reason?) throw _StopSignal(reason);
    },
  );

  void _progress(int jobBytes, int index, int count, int received, int? total) {
    final now = _clock.elapsed;
    _samples.add((now, jobBytes));
    while (_samples.length > 2 &&
        now - _samples.first.$1 > const Duration(seconds: 3)) {
      _samples.removeAt(0);
    }
    if (now - _lastProgress < progressInterval && received != total) return;
    _lastProgress = now;
    final (t0, b0) = _samples.first;
    final seconds = (now - t0).inMicroseconds / 1e6;
    final fileFraction = total == null || total == 0 ? 0.0 : received / total;
    _setProgress(
      DownloadProgress(
        received: jobBytes,
        fraction: ((index + fileFraction) / count).clamp(0, 1),
        bytesPerSecond: seconds > 0 ? (jobBytes - b0) / seconds : 0,
      ),
    );
  }

  void _setProgress(DownloadProgress value) {
    if (!_disposed) progress.value = value;
  }

  Future<void> _load() async {
    final json = await _file.read();
    if (json == null) return;
    final jobs = json['jobs'];
    if (jobs is List<Object?>) {
      for (final e in jobs) {
        final job = DownloadJob._fromJson(e);
        if (job != null) _jobs.add(job);
      }
    }
    final downloaded = json['downloaded'];
    if (downloaded is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in downloaded.entries) {
        if (value is List<Object?>) {
          _downloaded[key] = {...value.whereType<String>()};
        }
      }
    }
  }

  /// Writes the state as it is when the write runs, after loading, so an
  /// early change never overwrites the saved queue with an empty one. A
  /// failed write goes to the debug log and [flush]; the next change writes
  /// the whole state again.
  void _save() {
    unawaited(
      _file.save(() async {
        await _ready;
        return _snapshot();
      }),
    );
  }

  Map<String, Object?> _snapshot() => {
    'version': 1,
    'jobs': [for (final j in _jobs) j._toJson()],
    'downloaded': {
      for (final MapEntry(:key, :value) in _downloaded.entries)
        key: value.toList(),
    },
  };

  /// Completes when every change so far is on disk; fails when the latest
  /// write did.
  Future<void> flush() => _file.flush();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    link.removeListener(_onLink);
    if (_current != null) _stop ??= _Stop.pause;
    progress.dispose();
    super.dispose();
  }
}
