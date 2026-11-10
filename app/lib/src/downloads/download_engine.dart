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

/// The app stopped while the photo library was taking the shot, so whether
/// it took it is unknown; retrying saves it again.
final class DownloadSaveInterrupted extends DownloadFailure {
  const new();
}

/// A file of the job left the camera's listing: it was deleted on the
/// camera, or its card was taken out. Retrying asks the camera again, so a
/// card put back still downloads.
final class DownloadFileGone extends DownloadFailure {
  const new();
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

  /// The shot is being handed to the photo library. Saved with the queue
  /// before the hand-over, so a restart after a crash in it knows the save
  /// may have happened.
  bool _saving = false;

  /// The link the copies kept in the job's folder were made on. A copy
  /// from an earlier link may be of another file than the one now at its
  /// path (another card, a file deleted and shot again).
  CameraLibrary? _copiedOn;

  Map<String, Object?> _toJson() => {
    'id': id,
    'serial': serial,
    'shot': [for (final f in shot.files) _fileToJson(f)],
    'files': [for (final f in _files) _fileToJson(f)],
    'state': _saving
        ? 'saving'
        : state == DownloadState.failed
        ? 'failed'
        : 'queued',
    'error': ?_failureToJson(failure),
  };

  /// A job saved while [_saving] comes back failed with
  /// [DownloadSaveInterrupted]: the platforms give no way to ask the photo
  /// library whether the save happened, so the user decides instead of the
  /// shot being saved twice.
  static DownloadJob? _fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final serial = json['serial'];
    if (id is! String || serial is! String) return null;
    final shotFiles = _filesFromJson(json['shot']);
    final files = _filesFromJson(json['files']);
    final shots = groupShots(shotFiles);
    if (shots.length != 1 || files.isEmpty) return null;
    final failure = switch (json['state']) {
      'saving' => const DownloadSaveInterrupted(),
      'failed' => _failureFromJson(json['error']),
      _ => null,
    };
    final failed = failure != null || json['state'] == 'failed';
    return DownloadJob._(
      id: id,
      serial: serial,
      shot: shots.single,
      files: files,
      state: failed ? DownloadState.failed : DownloadState.queued,
      failure: failure,
    );
  }
}

Map<String, Object?>? _failureToJson(DownloadFailure? failure) =>
    switch (failure) {
      null => null,
      DownloadSaveFailed(:final reason) => {'save': reason.name},
      DownloadSaveInterrupted() => {'save': 'interrupted'},
      DownloadFileGone() => {'gone': true},
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
  if (json['gone'] == true) return const DownloadFileGone();
  if (json['save'] case final String save) {
    if (save == 'interrupted') return const DownloadSaveInterrupted();
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
/// what is already on the phone. A camera path can come back with another
/// file, so each record keeps what the camera reported of the file saved,
/// and the library's checks ([fileStale], [checkFile]) drop a record that
/// no longer matches. Files go to `<cacheDir>/downloads/<job>/` first and
/// are handed to [MediaSaver] per shot. A transfer interrupted by a pause
/// restarts that file from the beginning (the camera has no ranged
/// downloads) and keeps the shot's files finished before it; after a lost
/// connection the whole shot is copied again, as the camera may hold other
/// files at those paths by then. A shot the app stopped while saving comes
/// back failed with [DownloadSaveInterrupted] instead of being saved again,
/// as the photo library cannot be asked whether it took the shot.
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

  /// Per camera, the files saved to the phone, each with the size and
  /// capture time its camera reported when it was saved (null when the
  /// camera did not answer, and for records from before they were kept).
  final Map<String, Map<String, FileInfo?>> _downloaded = {};
  int _nextId = 0;

  bool _looping = false;
  Completer<void>? _idle;
  bool _paused = false;
  DownloadJob? _current;
  CameraLibrary? _currentLink;
  _Stop? _stop;

  /// Completed when the running transfer is stopped, so its camera request
  /// closes at once instead of at its next chunk or its own deadline.
  Completer<Object>? _abort;
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
      _downloaded[serial]?.containsKey(f.key) ?? false;

  /// Some file of [shot] was saved to the phone: the grid's mark and the
  /// "Not downloaded" filter use this. The app cannot see whether it is
  /// still in the photo library, so this is a hint only: it never stops a
  /// download.
  bool isShotDownloaded(String serial, Shot shot) =>
      shot.files.any((f) => isFileDownloaded(serial, f));

  /// Every one of [files] (one kind of a shot) was saved to the phone: the
  /// viewer's per-kind download buttons use this, so a RAW+JPEG pair with
  /// only the JPEG saved still offers its RAW.
  bool areFilesDownloaded(String serial, Iterable<CameraFile> files) =>
      files.every((f) => isFileDownloaded(serial, f));

  /// The library found that [serial]'s camera path [f] left the listing,
  /// or now holds another file than its cached info describes. A download
  /// recorded without the camera's info cannot be told apart from a file
  /// that comes to that path later, so its record goes; one recorded with
  /// it waits for [checkFile], so a card taken out and put back keeps its
  /// marks.
  Future<void> fileStale(String serial, CameraFile f) async {
    await _ready;
    final records = _downloaded[serial];
    if (records == null ||
        !records.containsKey(f.key) ||
        records[f.key] != null) {
      return;
    }
    records.remove(f.key);
    _save();
    _notify();
  }

  /// [serial]'s camera no longer lists [f]: it was deleted on the camera
  /// or its card was taken out. A job waiting to copy it, or one whose copy
  /// failed, fails with [DownloadFileGone] rather than asking the camera
  /// for a file it no longer has; a retry asks again. A running job fails
  /// by itself, and one whose files were copied (a failed save) still
  /// saves its copies on a retry.
  Future<void> fileGone(String serial, CameraFile f) async {
    await _ready;
    var failed = false;
    for (final j in _jobs) {
      if (j.serial != serial || !j._files.contains(f)) continue;
      final waiting =
          j.state == DownloadState.queued ||
          j.failure is DownloadTransferFailed;
      if (!waiting || identical(j, _current)) continue;
      _fail(j, const DownloadFileGone(), '$f left the listing');
      failed = true;
    }
    if (failed) _changed();
  }

  /// [serial]'s camera reports [now] for its path [f]. A download recorded
  /// for another file at that path ([FileInfo.sameContent]) no longer
  /// counts. One recorded without the camera's info takes [now] when
  /// [vouched] (the library's info of the file, cached before, matches
  /// [now]) and goes otherwise.
  Future<void> checkFile(
    String serial,
    CameraFile f,
    FileInfo now, {
    required bool vouched,
  }) async {
    await _ready;
    final records = _downloaded[serial];
    if (records == null || !records.containsKey(f.key)) return;
    final recorded = records[f.key];
    if (recorded != null && recorded.sameContent(now)) return;
    if (recorded == null && vouched) {
      records[f.key] = _identity(now);
      _save();
      return;
    }
    records.remove(f.key);
    _save();
    _notify();
  }

  static FileInfo _identity(FileInfo info) =>
      FileInfo(taken: info.taken, size: info.size);

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
  /// phone. A shot whose job failed downloads only what is asked now (see
  /// [enqueueFiles]). Returns the number of files added.
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

  /// Queues specific files of one shot (the viewer's choice for a pair).
  /// A job of the shot still waiting takes them as well; a failed one is
  /// asked again for exactly these, so choosing the RAW after the JPEG
  /// failed does not retry the JPEG. Returns the number of files added.
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
    // shot stays one queue entry and one save. A failed job is asked again
    // for these files only: the new request replaces the one that failed.
    for (final j in _jobs) {
      if (j.serial == serial &&
          j.shot.key == shot.key &&
          j.state != DownloadState.running) {
        j
          .._files = j.state == DownloadState.failed
              ? files
              : {...j._files, ...files}.toList()
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
      _stopRunning(_Stop.cancel);
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
    if (_current != null) _stopRunning(_Stop.cancel);
    _changed();
  }

  /// Forgets [serial]'s camera, removed from the app: its jobs go, a
  /// running one stops, and so do the records of its files saved to the
  /// phone. A shot the photo library is already saving still lands there.
  Future<void> forgetCamera(String serial) async {
    await _ready;
    final running = _current;
    for (final j in _jobs.toList()) {
      if (j.serial == serial) cancel(j);
    }
    // A job being saved records its files once the save ends.
    if (running?.serial == serial) await whenIdle();
    if (_downloaded.remove(serial) == null) return;
    _save();
    _notify();
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
    if (_current != null) _stopRunning(_Stop.pause);
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
      _stopRunning(_Stop.pause);
    }
    _kick();
    _notify();
  }

  /// Stops the running job for [reason]; a cancel overrides a pause asked
  /// for earlier. The transfer's camera request closes at once.
  void _stopRunning(_Stop reason) {
    final stop = _stop = reason == _Stop.cancel ? reason : _stop ?? reason;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete(_StopSignal(stop));
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
    _abort = Completer<Object>();
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
      // Copies kept on an earlier link may be of other files.
      if (!identical(job._copiedOn, current)) await _deleteTemp(job);
      job._copiedOn = current;
      final local = await _transfer(job, files, current);
      final identities = [for (final f in files) await _identify(f, current)];
      if (_stop case final reason?) throw _StopSignal(reason);
      await _markSaving(job);
      try {
        await media.saveShot(local, album: album);
      } finally {
        job._saving = false;
      }
      final records = _downloaded.putIfAbsent(job.serial, () => {});
      for (var i = 0; i < files.length; i++) {
        records[files[i].key] = identities[i];
      }
      if (_stop == _Stop.cancel) throw const _StopSignal(_Stop.cancel);
      _jobs.remove(job);
      _batchDone++;
      await _deleteTemp(job);
    } on _StopSignal catch (s) {
      // A cancel may follow the pause that aborted the transfer.
      _stopped(job, _stop ?? s.reason);
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
      _abort = null;
      _setProgress(const DownloadProgress());
      _save();
      _notify();
    }
  }

  /// Writes the queue with [job] marked as being saved before the photo
  /// library gets it, so a crash before the save is recorded leaves a job
  /// that asks instead of one that saves the shot again. When that write
  /// fails (the queue file logs it), the shot is not saved: the job fails
  /// as a write failure and keeps its copies for a retry, since a save the
  /// queue cannot record could be repeated after a restart.
  Future<void> _markSaving(DownloadJob job) async {
    job._saving = true;
    _save();
    try {
      await _file.flush();
    } on Object {
      job._saving = false;
      rethrow;
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

  /// The size and capture time [current]'s camera reports for [f], kept
  /// with its record; null when the camera does not answer, or the
  /// transfer is stopped meanwhile.
  Future<FileInfo?> _identify(CameraFile f, CameraLibrary current) async {
    try {
      return _identity(await current.fileInfo(f, abort: _abort?.future));
    } on Object {
      return null;
    }
  }

  Future<List<File>> _transfer(
    DownloadJob job,
    List<CameraFile> files,
    CameraLibrary current,
  ) => current.downloadFiles(
    files,
    _tempDir(job),
    onProgress: (bytes, index, received, total) =>
        _progress(bytes, index, files.length, received, total),
    afterFile: () {
      if (_stop case final reason?) throw _StopSignal(reason);
    },
    abort: _abort?.future,
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
      for (final MapEntry(key: serial, :value) in downloaded.entries) {
        _downloaded[serial] = switch (value) {
          // Version 1 kept the file keys only.
          final List<Object?> keys => {
            for (final key in keys.whereType<String>()) key: null,
          },
          final Map<String, Object?> records => {
            for (final MapEntry(:key, :value) in records.entries)
              key: value is Map<String, Object?>
                  ? FileInfo.fromJson(value)
                  : null,
          },
          _ => {},
        };
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
    'version': 2,
    'jobs': [for (final j in _jobs) j._toJson()],
    'downloaded': {
      for (final MapEntry(key: serial, value: records) in _downloaded.entries)
        serial: {
          for (final MapEntry(:key, :value) in records.entries)
            key: value?.toJson(),
        },
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
    if (_current != null) _stopRunning(_Stop.pause);
    progress.dispose();
    super.dispose();
  }
}
