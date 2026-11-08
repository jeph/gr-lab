import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../data/json_file.dart';
import '../data/settings.dart';
import '../library/camera_link.dart';
import '../library/shot.dart';
import '../services.dart';

enum DownloadState {
  /// Waiting for its turn, for its camera to connect, or for [resume].
  queued,
  running,

  /// Stopped by an error; [DownloadEngine.retry] queues it again.
  failed,
}

/// One shot's files in the download queue.
final class DownloadJob {
  DownloadJob._({
    required this.id,
    required this.serial,
    required this.shot,
    required this._files,
    this.state = DownloadState.queued,
    this.error,
  });

  final String id;

  /// The camera the files are on.
  final String serial;
  final Shot shot;
  List<CameraFile> _files;
  DownloadState state;

  /// Why the job failed.
  String? error;

  /// The files this job saves (a pair's halves per the setting, minus any
  /// half already downloaded).
  List<CameraFile> get files => List.unmodifiable(_files);

  bool get active => state != DownloadState.failed;

  Map<String, Object?> _toJson() => {
    'id': id,
    'serial': serial,
    'shot': [for (final f in shot.files) _fileToJson(f)],
    'files': [for (final f in _files) _fileToJson(f)],
    'state': state == DownloadState.failed ? 'failed' : 'queued',
    'error': ?error,
  };

  static DownloadJob? _fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'], serial = json['serial'];
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
      error: failed
          ? switch (json['error']) {
              final String e => e,
              _ => null,
            }
          : null,
    );
  }
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
    final storage = e['s'], dir = e['d'], file = e['f'];
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
  const _StopSignal(this.reason);
  final _Stop reason;
}

/// Transfer progress of the running job.
@immutable
final class DownloadProgress {
  const DownloadProgress({
    this.received = 0,
    this.fraction = 0,
    this.bytesPerSecond = 0,
  });

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
  DownloadEngine({
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
  final ValueListenable<CameraLink?> link;
  final String album;

  /// After a network error, how long to wait for the connection to report
  /// it lost before the job counts as failed instead of paused.
  final Duration transportGrace;
  final Duration progressInterval;

  late final Future<void> _ready;
  late final JsonFile _file = JsonFile(File('${dataDir.path}/downloads.json'));
  final List<DownloadJob> _jobs = [];
  final Map<String, Set<String>> _downloaded = {};
  Future<void> _saving = Future.value();
  int _nextId = 0;

  bool _looping = false;
  Completer<void>? _idle;
  bool _paused = false;
  DownloadJob? _current;
  CameraLink? _currentLink;
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

  /// Every file [choice] selects for [shot] is on the phone.
  bool isShotDownloaded(String serial, Shot shot, RawJpegChoice choice) =>
      shot.filesFor(choice).every((f) => isFileDownloaded(serial, f));

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

  /// What downloading [shot] with [choice] would fetch: the selected files
  /// that are neither on the phone nor already queued.
  List<CameraFile> filesToDownload(
    String serial,
    Shot shot,
    RawJpegChoice choice,
  ) => [
    for (final f in shot.filesFor(choice))
      if (!isFileDownloaded(serial, f) && !isFileQueued(serial, f)) f,
  ];

  /// Queues [shots] of [serial]'s camera: pairs bring the halves [choice]
  /// selects, single files always come, and files already downloaded or
  /// queued are skipped. Returns the number of files added.
  Future<int> enqueue(
    String serial,
    Iterable<Shot> shots,
    RawJpegChoice choice,
  ) async {
    await _ready;
    var added = 0;
    for (final shot in shots) {
      added += _add(serial, shot, shot.filesFor(choice));
    }
    if (added > 0) _changed();
    return added;
  }

  /// Queues specific files of one shot (the viewer's JPEG / RAW / Both
  /// choice). Returns the number of files added.
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
        if (!isFileDownloaded(serial, f) && !isFileQueued(serial, f)) f,
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
          ..error = null;
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
      ..error = null;
    _changed();
  }

  void retryFailed() {
    var any = false;
    for (final j in _jobs) {
      if (j.state != DownloadState.failed) continue;
      j
        ..state = DownloadState.queued
        ..error = null;
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

  Future<void> _run(DownloadJob job, CameraLink current) async {
    _current = job;
    _currentLink = current;
    _stop = null;
    job
      ..state = DownloadState.running
      ..error = null;
    _samples.clear();
    _setProgress(const DownloadProgress());
    _notify();
    try {
      // Another job may have saved a half since this one was queued.
      final files = [
        for (final f in job._files)
          if (!isFileDownloaded(job.serial, f)) f,
      ];
      if (files.isNotEmpty) {
        final local = await _transfer(job, files, current);
        await media.saveShot(local, album: album);
        _downloaded.putIfAbsent(job.serial, () => {}).addAll([
          for (final f in files) f.key,
        ]);
      }
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
          if (j.active) {
            j
              ..state = DownloadState.failed
              ..error = 'No access to the photo library';
          }
        }
      } else {
        if (_stop == _Stop.cancel) {
          _stopped(job, _Stop.cancel);
        } else {
          _fail(job, e.message);
        }
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
        _fail(job, _describe(e));
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

  void _fail(DownloadJob job, String message) {
    job
      ..state = DownloadState.failed
      ..error = message;
  }

  /// Network errors usually mean the camera's Wi-Fi went away; give the
  /// connection a moment to notice before blaming the job.
  Future<bool> _connectionLost(Object error, CameraLink current) async {
    if (!identical(link.value, current)) return true;
    final transport =
        error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is GrMalformedResponseException;
    if (!transport) return false;
    await Future<void>.delayed(transportGrace);
    return !identical(link.value, current);
  }

  Future<List<File>> _transfer(
    DownloadJob job,
    List<CameraFile> files,
    CameraLink current,
  ) async {
    final dir = _tempDir(job);
    await dir.create(recursive: true);
    final local = <File>[];
    var before = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final out = File('${dir.path}/${f.name}');
      // A file finished before a pause stays; only the interrupted one
      // starts over.
      if (!out.existsSync()) {
        await current.http.downloadToFile(
          f.path,
          out,
          storage: f.storage,
          onProgress: (received, total) {
            if (_stop case final reason?) throw _StopSignal(reason);
            _progress(before + received, i, files.length, received, total);
          },
        );
      }
      if (_stop case final reason?) throw _StopSignal(reason);
      before += await out.length();
      local.add(out);
    }
    return local;
  }

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

  String _describe(Object e) => switch (e) {
    GrApiException(:final errCode, :final errMsg) =>
      'The camera refused the file ($errCode${errMsg == null ? '' : ' $errMsg'})',
    GrHttpStatusException(:final httpStatus) =>
      'The camera answered HTTP $httpStatus',
    GrMalformedResponseException() => 'The transfer was cut off',
    SocketException() || HttpException() => 'Lost the connection to the camera',
    TimeoutException() => 'The camera stopped sending',
    FileSystemException(:final message) => 'Could not write the file: $message',
    _ => '$e',
  };

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
  /// early change never overwrites the saved queue with an empty one.
  void _save() {
    _saving = _saving
        .then((_) => _ready)
        .then((_) => _file.write(_snapshot()))
        .catchError((Object _) {});
  }

  Map<String, Object?> _snapshot() => {
    'version': 1,
    'jobs': [for (final j in _jobs) j._toJson()],
    'downloaded': {
      for (final MapEntry(:key, :value) in _downloaded.entries)
        key: value.toList(),
    },
  };

  /// Completes when every change so far is on disk.
  Future<void> flush() => _saving;

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
