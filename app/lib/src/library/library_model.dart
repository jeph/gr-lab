import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/library/shot.dart';

enum LibraryFilter { all, jpeg, raw, video, notDownloaded }

/// What keeps copies of camera files (images, movies, download records),
/// told what [LibraryModel] finds out about the file at each path.
abstract interface class FileCopies {
  /// Something besides the library's cached info, such as a download,
  /// depends on which file [serial]'s [f] is, so its path is checked on
  /// each link even without cached info.
  bool isRecorded(String serial, CameraFile f);

  /// [serial]'s [f] left the listing, or its path now holds another file
  /// than the library's cached info describes.
  void stale(String serial, CameraFile f);

  /// The camera of [current] gave the first info the library has of [f]:
  /// copies made on an earlier link may be of another file that was at
  /// its path then, so those go. True when one did. Download records are
  /// left to [checked].
  bool dropUnchecked(CameraLibrary current, CameraFile f);

  /// [serial]'s camera reports [now] for [f]. [vouched] when the library's
  /// info of the path, cached before, matches it.
  void checked(
    String serial,
    CameraFile f,
    FileInfo now, {
    required bool vouched,
  });
}

/// The current camera's ([CameraStore.current]) photos as shots, kept per
/// camera serial in `<cacheDir>/<serial>/library.json` so the grid appears
/// at once and offline. Refreshes whenever the camera connects and when its
/// `/v1/changes` socket reports a storage change.
///
/// A camera path can come back with another file (a card swapped, a shot
/// deleted and taken again), and the listing gives names only. So on each
/// link, and again on a refresh the user asks for, the camera's `/info` of
/// every listed file with cached info or a record in [copies] is read
/// again in the background, and a cell shown asks for its own at once.
/// When the answer differs from the cached info ([FileInfo.sameContent]),
/// or the file left the listing, [copies] drops what it keeps of the file
/// and [revision] changes. Until the answer comes, and offline, what is
/// cached shows. When the first info of a file arrives, copies of it made
/// on an earlier link go, as nothing told what they were of. \[design\]
/// Not checked: a path reused while one link lasts (until the user
/// refreshes).
final class LibraryModel extends ChangeNotifier {
  new({
    required this.cacheDir,
    required this.cameras,
    required this.link,
    required this.queue,
    this.copies,
    this.changeDebounce = const Duration(milliseconds: 800),
    this.saveDelay = const Duration(seconds: 2),
    this.infoTimeout = const Duration(seconds: 10),
  }) : _infoRequests = SharedRequests(queue) {
    link.addListener(_onLink);
    cameras.addListener(_followCurrent);
    _followCurrent();
  }

  /// Told what the checks find, so it drops what it keeps of a file that
  /// is gone or replaced.
  final FileCopies? copies;

  final Directory cacheDir;

  /// The paired cameras; the model shows the current one's library.
  final CameraStore cameras;
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

  /// [CameraStore.current]'s serial when last seen. [serial] becomes it
  /// once the previous camera's listing is saved.
  String? _current;
  Future<void> _switched = Future.value();

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

  /// Keys of the files whose cached copies the camera confirmed on
  /// [_confirmedOn], the link they were checked on.
  final Set<String> _confirmed = {};
  CameraLibrary? _confirmedOn;

  /// Background `/info` checks on [_confirmedOn].
  final List<RequestTicket<FileInfo>> _checks = [];
  final Map<String, int> _revisions = {};

  /// The camera whose listing this is. Lags behind [CameraStore.current]
  /// while the previous camera's listing is saved.
  String? get serial => _serial;

  /// Shots newest first; null until a listing or the cache is read.
  List<Shot>? get shots => _shots;

  /// When the shown listing was read from the camera.
  DateTime? get listedAt => _listedAt;

  /// The camera of the listing is connected.
  bool get connected => _ownLink != null;

  bool get refreshing => _refreshing;
  bool get loadingCache => _loadingCache;

  /// The last refresh failed; [shots] keeps the previous listing.
  Object? get error => _error;

  FileInfo? info(CameraFile f) => _info[f.key];

  /// Changes each time [f]'s path turns out to hold another file than the
  /// one cached, so an image of it shown is loaded again.
  int revision(CameraFile f) => _revisions[f.key] ?? 0;

  /// Completes when the model has switched to the current camera's
  /// library: its cached listing is read and, when it is connected, its
  /// refresh has started.
  Future<void> get switched => _switched;

  /// The link when it belongs to the camera of the listing ([serial]),
  /// else null. The one place that matches the connection to the listing:
  /// the link follows whichever camera is connected, and [serial] can lag
  /// behind it while a switch saves and reads cached listings, so nothing
  /// for one camera reaches another's listing.
  CameraLibrary? get _ownLink {
    final current = link.value;
    return current != null && current.serial == _serial ? current : null;
  }

  /// [_ownLink], after dropping the confirmations and checks of a previous
  /// link: a new link may reach another card.
  CameraLibrary? _confirming() {
    final current = _ownLink;
    if (identical(current, _confirmedOn)) return current;
    _confirmedOn = current;
    _confirmed.clear();
    for (final check in _checks) {
      check.cancel();
    }
    _checks.clear();
    return current;
  }

  void _followCurrent() {
    final serial = cameras.current?.serial;
    if (serial == _current) return;
    _current = serial;
    _switched = _switchTo(serial);
  }

  /// Switches to [serial]'s library, showing its cached listing at once and
  /// refreshing it if that camera is connected. A switch superseded while
  /// it saves the previous listing stops there.
  Future<void> _switchTo(String? serial) async {
    if (serial == _serial) return;
    await _flushSave();
    if (_disposed || serial != _current) return;
    final generation = ++_generation;
    _serial = serial;
    _shots = null;
    _files = const [];
    _info.clear();
    _revisions.clear();
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

  /// Reads the camera's listing again and checks every cached file against
  /// it once more. Does nothing while offline; a refresh requested during
  /// one runs once more afterwards.
  Future<void> refresh() {
    _confirmed.clear();
    return _refresh('user');
  }

  /// [reason] says why the listing is read, for the trace.
  Future<void> _refresh(String reason) async {
    final current = _ownLink;
    if (current == null) return;
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
      final keys = {for (final f in files) f.key};
      final gone = [
        for (final f in _files)
          if (!keys.contains(f.key)) f,
      ];
      _files = files;
      _shots = groupShots(files);
      _listedAt = DateTime.now();
      _error = null;
      _info.removeWhere((k, _) => !keys.contains(k));
      gone.forEach(_stale);
      _revalidate(current);
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

  /// Fetches a file's info from the camera if it is not known, or not
  /// confirmed on this link yet. Returns the info, the cached info when the
  /// request failed, or null when offline and nothing is cached.
  Future<FileInfo?> ensureInfo(CameraFile f) {
    final known = _info[f.key];
    final ticket = requestInfo(f);
    if (ticket == null) return Future.value(known);
    return ticket.future.then<FileInfo?>(
      (i) => i,
      onError: (Object _) => known,
    );
  }

  /// Fetches a file's info from the camera, shared with every other caller
  /// asking for it; cancelling the ticket drops the request if nobody else
  /// waits. The cached info when offline or already confirmed on this link;
  /// null when offline without it. The ticket fails when the request did.
  RequestTicket<FileInfo>? requestInfo(CameraFile f) {
    final known = _info[f.key];
    final current = _confirming();
    if (known != null && (current == null || _confirmed.contains(f.key))) {
      return RequestTicket.done(known);
    }
    if (current == null) return null;
    return _requestInfo(f, current);
  }

  RequestTicket<FileInfo> _requestInfo(
    CameraFile f,
    CameraLibrary current, {
    bool background = false,
  }) {
    final generation = _generation;
    final key = '${current.serial}|$generation|${f.key}';
    return _infoRequests.join(
      key,
      current,
      (signal) async {
        // Past the deadline the request closes at once, freeing its slot.
        final info = await current.fileInfo(f, abort: signal.aborted);
        if (generation == _generation) _accept(f, info, current);
        return info;
      },
      timeout: infoTimeout,
      background: background,
    );
  }

  /// [info] is what [from]'s camera says of [f] now.
  void _accept(CameraFile f, FileInfo info, CameraLibrary from) {
    final known = _info[f.key];
    _info[f.key] = info;
    final same = known != null && known.sameContent(info);
    if (known == null) {
      // Nothing told what copies from an earlier link were of.
      if (copies?.dropUnchecked(from, f) ?? false) {
        _revisions[f.key] = revision(f) + 1;
      }
    } else if (!same) {
      _stale(f);
    }
    if (identical(_confirming(), from)) _confirmed.add(f.key);
    copies?.checked(from.serial, f, info, vouched: same);
    _scheduleSave();
    _notify();
  }

  /// Reads again, in the background, the info of every listed file not
  /// confirmed on [current] yet that has cached info or a record in
  /// [copies]. Without either, there is nothing the answer could disprove.
  void _revalidate(CameraLibrary current) {
    if (!identical(_confirming(), current)) return;
    for (final f in _files) {
      if (_confirmed.contains(f.key)) continue;
      if (!_info.containsKey(f.key) &&
          !(copies?.isRecorded(current.serial, f) ?? false)) {
        continue;
      }
      final check = _requestInfo(f, current, background: true);
      _checks.add(check);
      // A check that fails leaves the file unconfirmed: the next link, or
      // a cell showing it, asks again.
      unawaited(
        check.future
            .then<void>((_) {}, onError: (Object _) {})
            .whenComplete(() => _checks.remove(check)),
      );
    }
  }

  /// [f]'s cached copies no longer show what is at its path.
  void _stale(CameraFile f) {
    _revisions[f.key] = revision(f) + 1;
    _confirmed.remove(f.key);
    if (_serial case final serial?) copies?.stale(serial, f);
  }

  void _onLink() {
    if (_loadingCache) return;
    final current = _confirming();
    if (current == null) {
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
    cameras.removeListener(_followCurrent);
    _changeTimer?.cancel();
    unawaited(_changes?.cancel());
    for (final check in _checks) {
      check.cancel();
    }
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
