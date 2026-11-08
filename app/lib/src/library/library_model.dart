import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../data/json_file.dart';
import 'camera_link.dart';
import 'request_queue.dart';
import 'shot.dart';

/// What `/v1/photos/<dir>/<file>/info` told us about one file.
@immutable
final class FileInfo {
  const FileInfo({this.taken, this.size, this.duration});

  factory FileInfo.fromPhotoInfo(GrPhotoInfo info) => FileInfo(
    taken: parseCameraTime(info.datetime ?? info.recordedTime),
    size: info.size,
    duration: info.duration == null ? null : Duration(seconds: info.duration!),
  );

  factory FileInfo.fromJson(Map<String, Object?> json) => FileInfo(
    taken: switch (json['t']) {
      final String t => DateTime.tryParse(t),
      _ => null,
    },
    size: (json['z'] as num?)?.toInt(),
    duration: switch (json['v']) {
      final num v => Duration(seconds: v.toInt()),
      _ => null,
    },
  );

  /// Capture time in the camera's clock (local, no zone).
  final DateTime? taken;

  /// Bytes of the full file.
  final int? size;

  /// Movie length.
  final Duration? duration;

  Map<String, Object?> toJson() => {
    if (taken != null) 't': taken!.toIso8601String(),
    'z': ?size,
    if (duration != null) 'v': duration!.inSeconds,
  };
}

/// Parses the camera's `datetime`. Its format is untested on hardware
/// (burst-grouping.md), so ISO 8601 and the EXIF `YYYY:MM:DD HH:MM:SS`
/// form are both accepted, always as the camera's local wall clock.
DateTime? parseCameraTime(String? text) {
  if (text == null || text.isEmpty) return null;
  final exif = RegExp(
    r'^(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(text);
  if (exif != null) {
    final p = [for (var i = 1; i <= 6; i++) int.parse(exif.group(i)!)];
    return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

enum LibraryFilter { all, jpeg, raw, video, notDownloaded }

/// The camera's photos as shots, kept per camera serial in
/// `<cacheDir>/<serial>/library.json` so the grid appears at once and
/// offline. Refreshes whenever the camera connects and when its
/// `/v1/changes` socket reports a storage change.
final class LibraryModel extends ChangeNotifier {
  LibraryModel({
    required this.cacheDir,
    required this.link,
    required this.queue,
    this.changeDebounce = const Duration(milliseconds: 800),
    this.saveDelay = const Duration(seconds: 2),
  }) {
    link.addListener(_onLink);
  }

  final Directory cacheDir;
  final ValueListenable<CameraLink?> link;

  /// Shared with the image loader so the camera sees at most its
  /// concurrency in requests from the library.
  final RequestQueue queue;
  final Duration changeDebounce;
  final Duration saveDelay;

  String? _serial;
  List<Shot>? _shots;
  List<CameraFile> _files = const [];
  final Map<String, FileInfo> _info = {};
  final Map<String, Future<FileInfo?>> _infoInFlight = {};
  DateTime? _listedAt;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _loadingCache = false;
  Object? _error;
  CameraLink? _subscribedLink;
  StreamSubscription<GrChangeEvent>? _changes;
  Timer? _changeTimer;
  Timer? _saveTimer;
  Future<void> _saving = Future.value();
  int _generation = 0;
  bool _disposed = false;

  String? get serial => _serial;

  /// Shots newest first; null until a listing or the cache is read.
  List<Shot>? get shots => _shots;

  /// When the shown listing was read from the camera.
  DateTime? get listedAt => _listedAt;

  /// The current camera is connected.
  bool get connected => link.value != null && link.value!.serial == _serial;

  bool get refreshing => _refreshing;
  bool get loadingCache => _loadingCache;

  /// The last refresh failed; [shots] keeps the previous listing.
  Object? get error => _error;

  FileInfo? info(CameraFile f) => _info[f.key];

  /// Switches to [serial]'s library, showing its cached listing at once and
  /// refreshing it if that camera is connected.
  Future<void> setCamera(String? serial) async {
    if (serial == _serial) return;
    await _flushSave();
    final generation = ++_generation;
    _serial = serial;
    _shots = null;
    _files = const [];
    _info.clear();
    _infoInFlight.clear();
    _listedAt = null;
    _error = null;
    // A refresh or cache read for the previous camera may still be pending;
    // it no longer owns these flags (its generation check skips them), so
    // they restart here.
    _refreshing = false;
    _refreshAgain = false;
    _loadingCache = false;
    queue.clear();
    _subscribeChanges(null);
    if (serial == null) {
      _notify();
      return;
    }
    _loadingCache = true;
    _notify();
    await _readCache(serial, generation);
    if (generation != _generation) return;
    _loadingCache = false;
    _notify();
    _onLink();
  }

  /// Reads the camera's listing again. Does nothing while offline; a
  /// refresh requested during one runs once more afterwards.
  Future<void> refresh() async {
    final current = link.value;
    final serial = _serial;
    if (current == null || serial == null || current.serial != serial) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    final generation = _generation;
    _refreshing = true;
    _notify();
    try {
      final files = await _list(current);
      if (generation != _generation) return;
      _files = files;
      _shots = groupShots(files);
      _listedAt = DateTime.now();
      _error = null;
      final keys = {for (final f in files) f.key};
      _info.removeWhere((k, _) => !keys.contains(k));
      _scheduleSave(immediately: true);
    } on Object catch (e) {
      if (generation != _generation) return;
      _error = e;
    } finally {
      if (generation == _generation) {
        _refreshing = false;
        _notify();
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  Future<List<CameraFile>> _list(CameraLink current) async {
    final files = <CameraFile>[];
    Object? failure;
    var listed = 0;
    for (final storage in current.storages) {
      final found = <CameraFile>[];
      try {
        await for (final page in current.http.photoPages(storage: storage)) {
          for (final p in page.paths) {
            found.add(CameraFile(storage, p));
          }
        }
        files.addAll(found);
        listed++;
      } on GrApiException catch (e) {
        // A storage without a card answers with an error; the other one
        // still lists.
        failure = e;
      }
    }
    if (listed == 0 && failure != null) throw failure;
    return files;
  }

  /// Fetches a file's info from the camera if it is not known yet. Returns
  /// the known info, or null when offline or the request failed.
  Future<FileInfo?> ensureInfo(CameraFile f) {
    final known = _info[f.key];
    if (known != null) return Future.value(known);
    final current = link.value;
    final serial = _serial;
    if (current == null || current.serial != serial) return Future.value();
    return _infoInFlight[f.key] ??= _fetchInfo(current, f);
  }

  Future<FileInfo?> _fetchInfo(CameraLink current, CameraFile f) async {
    final generation = _generation;
    try {
      final request = queue.add(
        () => current.http.photoInfo(f.path, storage: f.storage),
      );
      final info = FileInfo.fromPhotoInfo(await request.future);
      if (generation != _generation) return null;
      _info[f.key] = info;
      _scheduleSave();
      _notify();
      return info;
    } on Object {
      return null;
    } finally {
      if (generation == _generation) _infoInFlight.remove(f.key)?.ignore();
    }
  }

  void _onLink() {
    if (_serial == null || _loadingCache) return;
    final current = link.value;
    if (current == null || current.serial != _serial) {
      _subscribeChanges(null);
      _notify();
      return;
    }
    if (identical(current, _subscribedLink)) return;
    _subscribeChanges(current);
    _notify();
    unawaited(refresh());
  }

  void _subscribeChanges(CameraLink? current) {
    _subscribedLink = current;
    _changeTimer?.cancel();
    unawaited(_changes?.cancel());
    _changes = current?.changes?.listen((e) {
      if (e is! GrStorageChange) return;
      _changeTimer?.cancel();
      _changeTimer = Timer(changeDebounce, () => unawaited(refresh()));
    });
  }

  File _cacheFile(String serial) =>
      File('${cacheDir.path}/$serial/library.json');

  Future<void> _readCache(String serial, int generation) async {
    final json = await JsonFile(_cacheFile(serial)).read();
    if (json == null || generation != _generation) return;
    final files = <CameraFile>[];
    for (final e in json['files'] as List<Object?>? ?? const []) {
      if (e is! Map<String, Object?>) continue;
      final dir = e['d'], file = e['f'], storage = e['s'];
      if (dir is! String || file is! String) continue;
      try {
        files.add(CameraFile(storage as String?, GrPhotoPath(dir, file)));
      } on Object {
        continue;
      }
    }
    final info = json['info'];
    if (info is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in info.entries) {
        if (value is Map<String, Object?>) {
          _info[key] = FileInfo.fromJson(value);
        }
      }
    }
    _files = files;
    _shots = groupShots(files);
    _listedAt = switch (json['listedAt']) {
      final String t => DateTime.tryParse(t),
      _ => null,
    };
  }

  void _scheduleSave({bool immediately = false}) {
    _saveTimer?.cancel();
    if (immediately) {
      _save();
    } else {
      _saveTimer = Timer(saveDelay, _save);
    }
  }

  void _save() {
    _saveTimer = null;
    final serial = _serial;
    final shots = _shots;
    if (serial == null || shots == null) return;
    final snapshot = {
      'version': 1,
      'listedAt': _listedAt?.toIso8601String(),
      'files': [
        for (final f in _files) {'s': f.storage, 'd': f.dir, 'f': f.name},
      ],
      'info': {
        for (final MapEntry(:key, :value) in _info.entries) key: value.toJson(),
      },
    };
    final file = JsonFile(_cacheFile(serial));
    _saving = _saving.then((_) => file.write(snapshot)).catchError((_) {});
  }

  Future<void> _flushSave() async {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _save();
    }
    await _saving;
  }

  /// Completes when the listing and info known so far are on disk.
  Future<void> flush() => _flushSave();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    link.removeListener(_onLink);
    _changeTimer?.cancel();
    unawaited(_changes?.cancel());
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _save();
    }
    super.dispose();
  }
}

/// Shots counted per filter chip and the filtered lists.
@immutable
final class FilteredShots {
  const FilteredShots(this.shots, this.counts);

  factory FilteredShots.of(
    List<Shot> all,
    LibraryFilter filter,
    bool Function(Shot) downloaded,
  ) {
    bool matches(Shot s, LibraryFilter f) => switch (f) {
      LibraryFilter.all => true,
      LibraryFilter.jpeg => s.hasJpeg,
      LibraryFilter.raw => s.hasRaw,
      LibraryFilter.video => s.isVideo,
      LibraryFilter.notDownloaded => !downloaded(s),
    };
    final counts = {
      for (final f in LibraryFilter.values)
        f: f == LibraryFilter.all
            ? all.length
            : all.where((s) => matches(s, f)).length,
    };
    return FilteredShots(
      filter == LibraryFilter.all
          ? all
          : [
              for (final s in all)
                if (matches(s, filter)) s,
            ],
      counts,
    );
  }

  final List<Shot> shots;
  final Map<LibraryFilter, int> counts;
}

/// Shots of one day in the grid.
@immutable
final class DaySection {
  const DaySection(this.day, this.shots);

  /// Midnight of the day, or null for leading shots whose date is not
  /// known yet.
  final DateTime? day;
  final List<Shot> shots;
}

/// Splits [shots] (newest first) into days by capture date. Dates arrive
/// lazily, so a shot without one stays with the shot before it; only shots
/// before the first known date form an undated section.
List<DaySection> daySections(List<Shot> shots, DateTime? Function(Shot) taken) {
  final sections = <DaySection>[];
  DateTime? day;
  var current = <Shot>[];
  for (final s in shots) {
    final t = taken(s);
    final d = t == null ? null : DateTime(t.year, t.month, t.day);
    if (d != null && d != day && (current.isNotEmpty || day != null)) {
      if (current.isNotEmpty) sections.add(DaySection(day, current));
      current = <Shot>[];
    }
    if (d != null) day = d;
    current.add(s);
  }
  if (current.isNotEmpty) sections.add(DaySection(day, current));
  return sections;
}
