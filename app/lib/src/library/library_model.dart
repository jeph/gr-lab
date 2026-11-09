import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/library/shot.dart';

enum LibraryFilter { all, jpeg, raw, video, notDownloaded }

/// The camera's photos as shots, kept per camera serial in
/// `<cacheDir>/<serial>/library.json` so the grid appears at once and
/// offline. Refreshes whenever the camera connects and when its
/// `/v1/changes` socket reports a storage change.
final class LibraryModel extends ChangeNotifier {
  new({
    required this.cacheDir,
    required this.link,
    required this.queue,
    this.changeDebounce = const Duration(milliseconds: 800),
    this.saveDelay = const Duration(seconds: 2),
    this.infoTimeout = const Duration(seconds: 10),
  }) : _infoRequests = SharedRequests(queue) {
    link.addListener(_onLink);
  }

  final Directory cacheDir;
  final ValueListenable<CameraLibrary?> link;

  /// Shared with the image loader so the camera sees at most its
  /// concurrency in requests from the library.
  final RequestQueue queue;
  final Duration changeDebounce;
  final Duration saveDelay;

  /// Deadline of one `/info` request, so a camera that stops answering
  /// frees its queue slot and the grid can retry.
  final Duration infoTimeout;
  final SharedRequests<FileInfo> _infoRequests;

  String? _serial;
  List<Shot>? _shots;
  List<CameraFile> _files = const [];
  final Map<String, FileInfo> _info = {};
  DateTime? _listedAt;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _loadingCache = false;
  Object? _error;
  CameraLibrary? _subscribedLink;
  StreamSubscription<void>? _changes;
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
  Future<void> refresh() => _refresh('user');

  /// [reason] says why the listing is read, for the trace.
  Future<void> _refresh(String reason) async {
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
      final files = await current.listFiles(reason: reason);
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
      // A failed listing usually means the Wi-Fi went; the app then
      // returns to the Cameras screen, so the error is kept only while the
      // camera still answers.
      final answers = await current.checkWifi(after: 'listing');
      if (generation != _generation || !answers) return;
      _error = e;
    } finally {
      if (generation == _generation) {
        _refreshing = false;
        _notify();
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(_refresh('again'));
        }
      }
    }
  }

  /// Fetches a file's info from the camera if it is not known yet. Returns
  /// the known info, or null when offline or the request failed.
  Future<FileInfo?> ensureInfo(CameraFile f) {
    final known = _info[f.key];
    if (known != null) return Future.value(known);
    final ticket = requestInfo(f);
    if (ticket == null) return Future.value();
    return ticket.future.then<FileInfo?>((i) => i, onError: (Object _) => null);
  }

  /// Fetches a file's info from the camera, shared with every other caller
  /// asking for it; cancelling the ticket drops the request if nobody else
  /// waits. Null when offline. The ticket fails when the request did.
  RequestTicket<FileInfo>? requestInfo(CameraFile f) {
    final known = _info[f.key];
    if (known != null) return RequestTicket.done(known);
    final current = link.value;
    final serial = _serial;
    if (current == null || serial == null || current.serial != serial) {
      return null;
    }
    final generation = _generation;
    return _infoRequests.join('$serial|$generation|${f.key}', current, (
      _,
    ) async {
      final info = await current.fileInfo(f);
      if (generation == _generation) {
        _info[f.key] = info;
        _scheduleSave();
        _notify();
      }
      return info;
    }, timeout: infoTimeout);
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
    unawaited(_refresh('connected'));
  }

  void _subscribeChanges(CameraLibrary? current) {
    _subscribedLink = current;
    _changeTimer?.cancel();
    unawaited(_changes?.cancel());
    _changes = current?.storageChanges.listen((_) {
      _changeTimer?.cancel();
      _changeTimer = Timer(
        changeDebounce,
        () => unawaited(_refresh('storageChange')),
      );
    });
  }

  Future<void> _readCache(String serial, int generation) async {
    final cached = await readCachedListing(cacheDir, serial);
    if (cached == null || generation != _generation) return;
    _info.addAll(cached.info);
    _files = cached.files;
    _shots = groupShots(cached.files);
    _listedAt = cached.listedAt;
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
    // Copies: the collections change while the write waits its turn.
    final listing = (
      files: List.of(_files),
      info: Map.of(_info),
      listedAt: _listedAt,
    );
    _saving = _saving
        .then((_) => writeCachedListing(cacheDir, serial, listing))
        .catchError((_) {});
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
    // A refresh or info request still in flight must not write afterwards.
    _generation++;
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
  const new(this.shots, this.counts);

  factory of(
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
  const new(this.day, this.shots);

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
