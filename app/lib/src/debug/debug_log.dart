import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart' show TraceEvent, TraceSink;
import 'package:grlab/src/data/settings.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands log files to the system share sheet. [origin] anchors the sheet on
/// iPad; phones ignore it.
typedef ShareLogFiles = Future<void> Function(List<File> files, Rect? origin);

/// The app's debug log, kept on the phone as JSON Lines so a bug report can
/// carry exactly what happened: every exchange with the camera (what was
/// sent and received, through [sink]), every line the app printed
/// ([recordPrint], which `runWithDebugLog` feeds with `print`, `debugPrint`
/// and Flutter's error reports) and errors nothing caught
/// ([onUncaughtError]). The native code's lines come in with the camera
/// traffic.
///
/// Events go to rotating files `trace-000001.jsonl`, `trace-000002.jsonl`, …;
/// when the newest reaches [maxFileBytes] a new one starts and the oldest
/// beyond [maxFiles] is deleted, so the log never grows past roughly
/// `maxFileBytes × maxFiles`. Files are appended across app restarts.
///
/// The exported log holds everything, including the camera's Wi-Fi
/// passphrase as read over Bluetooth; that is intended (see the camera layer
/// design, "Tracing contract").
final class DebugLog extends ChangeNotifier {
  new _({
    required this.dir,
    required this.defaultEnabled,
    required this._settings,
    required this.maxFileBytes,
    required this.maxFiles,
    required this._share,
  }) : _enabled = _settings.debugLogging ?? defaultEnabled;

  /// Opens the log in [dir], continuing the newest file left by an earlier
  /// run. [settings] holds the user's choice, which overrides
  /// [defaultEnabled].
  static Future<DebugLog> open({
    required Directory dir,
    required bool defaultEnabled,
    required SettingsController settings,
    int maxFileBytes = 5 * 1024 * 1024,
    int maxFiles = 10,
    ShareLogFiles? share,
  }) async {
    assert(
      maxFileBytes > 0 && maxFiles > 0,
      'log size limits must be positive',
    );
    final log = DebugLog._(
      dir: dir,
      defaultEnabled: defaultEnabled,
      settings: settings,
      maxFileBytes: maxFileBytes,
      maxFiles: maxFiles,
      share: share ?? _shareWithSystem,
    );
    await dir.create(recursive: true);
    final files = await log._files();
    var total = 0;
    for (final f in files) {
      total += await f.length();
    }
    if (files.isNotEmpty) {
      final current = await files.last.length();
      log
        .._index = _indexOf(files.last)!
        .._currentBytes = current
        .._closedBytes = total - current;
    }
    return log;
  }

  /// Logging is on by default in dev builds (and when no flavor is set, as
  /// in `flutter test`), off in prod builds. Pass `appFlavor` from
  /// `package:flutter/services.dart`.
  static bool defaultEnabledFor(String? flavor) => flavor != 'prod';

  /// Where the log lives on this phone: on Android the app's external files
  /// directory, so `adb pull /sdcard/Android/data/<appId>/files/debug-log`
  /// works on a release build; on iOS the cache directory, which iOS leaves
  /// out of backups (the log holds the camera's Wi-Fi passphrase). Android
  /// backup is off for the whole app (`android:allowBackup`).
  static Future<Directory> platformDirectory() async {
    final base = Platform.isAndroid
        ? await getExternalStorageDirectory() ??
              await getApplicationSupportDirectory()
        : await getApplicationCacheDirectory();
    return Directory('${base.path}/debug-log');
  }

  final Directory dir;

  /// Used until the user flips the switch once.
  final bool defaultEnabled;

  /// A new file starts once the current one would grow past this.
  final int maxFileBytes;

  /// Files kept; older ones are deleted when a new one starts.
  final int maxFiles;

  final SettingsController _settings;
  final ShareLogFiles _share;

  bool _enabled;

  /// Lines recorded but not yet handed to a file write.
  final List<String> _pending = [];
  bool _drainScheduled = false;

  /// Every file operation runs in this chain, one at a time, so rotation,
  /// clearing and export never interleave with a write.
  Future<void> _ops = Future.value();

  RandomAccessFile? _current;

  /// Index of the file being appended to (`trace-<index>.jsonl`).
  int _index = 1;
  int _closedBytes = 0;
  int _currentBytes = 0;
  bool _closed = false;

  /// Share sheets still open; their export copies must stay on disk.
  int _sharing = 0;
  int _snapshotCount = 0;

  /// Whether debug logs are kept now (Settings, "Enable debug logging").
  /// While off, nothing is recorded and `runWithDebugLog` keeps app prints
  /// off the console too; only the engine's own report of uncaught errors
  /// still reaches it ([onUncaughtError]).
  bool get enabled => _enabled;

  /// Persists the user's choice; it wins over [defaultEnabled] from now on.
  set enabled(bool value) {
    if (value == _enabled && _settings.debugLogging == value) return;
    _enabled = value;
    _settings.debugLogging = value;
    notifyListeners();
  }

  /// Bytes on disk across all log files, as of the last finished write.
  int get sizeBytes => _closedBytes + _currentBytes;

  /// Give this to the camera layer. Returns at once when logging is off;
  /// otherwise encodes the event and queues the write, so callers on the UI
  /// isolate never wait for the disk.
  TraceSink get sink => _record;

  /// Records a line the app printed.
  void recordPrint(String line) => _recordJson({
    'time': DateTime.now().toUtc().toIso8601String(),
    'channel': 'app',
    'direction': 'internal',
    'kind': 'print',
    'fields': {'message': line},
  });

  /// For `PlatformDispatcher.onError`: records an error nothing caught
  /// (only while [enabled]). Returns false, so the engine still reports it
  /// as unhandled to logcat or the console whether or not debug logging is
  /// on; crashes stay visible.
  bool onUncaughtError(Object error, StackTrace stack) {
    _recordJson({
      'time': DateTime.now().toUtc().toIso8601String(),
      'channel': 'app',
      'direction': 'internal',
      'kind': 'error',
      'fields': {'error': '$error', 'stack': '$stack'},
    });
    return false;
  }

  void _record(TraceEvent event) => _recordJson(event.toJson());

  void _recordJson(Map<String, Object?> json) {
    if (!_enabled || _closed) return;
    // Fields come from many protocol layers; anything JSON cannot encode
    // natively is kept as its string form rather than losing the event.
    _pending.add('${jsonEncode(json, toEncodable: _fallback)}\n');
    if (_drainScheduled) return;
    _drainScheduled = true;
    unawaited(_enqueue(_drain));
  }

  static Object? _fallback(Object? o) => o.toString();

  /// Runs [op] after every earlier file operation. A failure reaches only
  /// this caller; later operations still run.
  Future<void> _enqueue(Future<void> Function() op) {
    final done = _ops.then((_) => op());
    _ops = done.catchError((Object _) {});
    return done;
  }

  /// Completes when every event recorded so far is on disk.
  Future<void> flush() => _ops;

  /// Shares every log file oldest first. Returns false without opening the
  /// share sheet when the log is empty.
  ///
  /// The files shared are copies taken after every event recorded so far is
  /// written: recording carries on while the sheet is open (and the
  /// receiving app may read the files later), and rotation or [clear] must
  /// not delete or change a file it was handed.
  Future<bool> export({Rect? origin}) async {
    var copies = const <File>[];
    await _enqueue(() async => copies = await _snapshot());
    if (copies.isEmpty) return false;
    _sharing++;
    try {
      await _share(copies, origin);
    } finally {
      _sharing--;
    }
    return true;
  }

  /// Deletes every log file, including events still waiting to be written,
  /// and earlier export copies unless a share is still in progress.
  Future<void> clear() {
    _pending.clear();
    return _enqueue(() async {
      await _current?.close();
      _current = null;
      for (final f in await _files()) {
        await f.delete();
      }
      _index = 1;
      _closedBytes = 0;
      _currentBytes = 0;
      await _deleteSnapshots();
    }).whenComplete(notifyListeners);
  }

  /// Copies the non-empty log files into a fresh `export-<n>` directory.
  /// Runs inside the operation queue, so no write or rotation interleaves.
  Future<List<File>> _snapshot() async {
    await _deleteSnapshots();
    final out = Directory('${dir.path}/export-${++_snapshotCount}');
    final copies = <File>[];
    for (final f in await _files()) {
      if (await f.length() == 0) continue;
      await out.create(recursive: true);
      copies.add(await f.copy('${out.path}/${f.uri.pathSegments.last}'));
    }
    return copies;
  }

  /// Old export copies are kept until no share sheet may still read them.
  Future<void> _deleteSnapshots() async {
    if (_sharing > 0 || !dir.existsSync()) return;
    await for (final e in dir.list()) {
      final name = e.path.substring(e.path.lastIndexOf('/') + 1);
      if (e is Directory && _snapshotName.hasMatch(name)) {
        await e.delete(recursive: true);
      }
    }
  }

  /// Writes what is pending and closes the current file. Later events are
  /// ignored.
  Future<void> close() async {
    _closed = true;
    await flush();
    await _current?.close();
    _current = null;
  }

  Future<void> _drain() async {
    _drainScheduled = false;
    if (_pending.isEmpty) return;
    final lines = List.of(_pending);
    _pending.clear();
    try {
      final chunk = BytesBuilder(copy: false);
      for (final line in lines) {
        final bytes = utf8.encode(line);
        if (_currentBytes + chunk.length > 0 &&
            _currentBytes + chunk.length + bytes.length > maxFileBytes) {
          await _write(chunk.takeBytes());
          await _rotate();
        }
        chunk.add(bytes);
      }
      await _write(chunk.takeBytes());
      await _current?.flush();
    } on FileSystemException catch (e) {
      // A full or vanished disk must not break the camera connection that
      // feeds this log; the batch is lost and the next one reopens the file.
      // The message goes straight to the console: printed, it would come
      // back here as a log line and fail again.
      Zone.root.print('debug log write failed: $e');
      await _current?.close().catchError((Object _) {});
      _current = null;
    }
    notifyListeners();
  }

  Future<void> _write(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final file = _current ??= await _fileAt(_index)
        .open(mode: FileMode.writeOnlyAppend);
    await file.writeFrom(bytes);
    _currentBytes += bytes.length;
  }

  /// Starts the next file and deletes the oldest ones beyond [maxFiles].
  Future<void> _rotate() async {
    await _current?.close();
    _current = null;
    _closedBytes += _currentBytes;
    _currentBytes = 0;
    _index++;
    final files = await _files();
    // The new file is not created yet, so keep maxFiles - 1 of the old ones.
    final excess = files.length - (maxFiles - 1);
    for (final f in files.take(excess < 0 ? 0 : excess)) {
      _closedBytes -= await f.length();
      await f.delete();
    }
  }

  File _fileAt(int index) =>
      File('${dir.path}/trace-${index.toString().padLeft(6, '0')}.jsonl');

  /// Log files oldest first.
  Future<List<File>> _files() async {
    if (!dir.existsSync()) return [];
    final files = <File>[
      await for (final e in dir.list())
        if (e is File && _indexOf(e) != null) e,
    ]..sort((a, b) => _indexOf(a)!.compareTo(_indexOf(b)!));
    return files;
  }

  static final _name = RegExp(r'^trace-(\d+)\.jsonl$');
  static final _snapshotName = RegExp(r'^export-\d+$');

  static int? _indexOf(File f) {
    final m = _name.firstMatch(f.uri.pathSegments.last);
    return m == null ? null : int.parse(m.group(1)!);
  }

  static Future<void> _shareWithSystem(List<File> files, Rect? origin) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final f in files) XFile(f.path, mimeType: 'text/plain')],
        sharePositionOrigin: origin,
      ),
    );
  }
}

/// Runs [body] in a zone whose `print` goes to the debug log returned by
/// [log], and so does everything printed through it: `debugPrint` and
/// Flutter's reports of framework errors. While debug logging is off those
/// lines go nowhere, the console included. Until [log] returns a log (at
/// start-up, before it is open) they reach the console as usual.
R runWithDebugLog<R>(DebugLog? Function() log, R Function() body) => runZoned(
  body,
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      final current = log();
      if (current == null) return parent.print(zone, line);
      if (!current.enabled) return;
      current.recordPrint(line);
      parent.print(zone, line);
    },
  ),
);
