import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

/// Where the phone has been, kept for 90 days. One writer: this class.
///
/// The history is a directory of text files, one per UTC day
/// (`2026-11-05.txt`). A day's file holds one line per position,
/// `time,latitude,longitude,accuracy,altitude`: milliseconds since the
/// epoch, degrees, and metres, the last two empty when the phone gave
/// none. Lines are only ever appended, in the order the positions arrive,
/// which need not be the order they were taken in; a day is read whole and
/// sorted by time when a photo is matched. Nothing is rewritten: a day that
/// ended more than the kept time ago is deleted as a file, and a position
/// that old in a day still on disk is passed over. A line that is not a
/// position of its day is skipped.
///
/// Its calls run one after the other, in the order they were made, so two
/// of them never write a file at once. The positions never reach the debug
/// log; a file that cannot be written or deleted is reported there by name.
final class LocationHistory {
  new _(this._dir, this._keep);

  /// Opens the history in [dir], creating the directory when it is missing
  /// and deleting the days that ended more than [keep] ago.
  static Future<LocationHistory> open(
    Directory dir, {
    Duration keep = const Duration(days: 90),
  }) async {
    final history = LocationHistory._(dir, keep);
    await history._queued(history._load);
    return history;
  }

  /// How long after a photo the next position may come and still be the
  /// photo's, when the history has none from before it. Without this a
  /// photo from before the history was turned on would get the place the
  /// phone was at when recording started. \[design\]
  static const _followingWindow = Duration(minutes: 10);

  static const _oneDay = Duration(days: 1);
  static const _newline = 0x0A;

  /// `#`, which ends a line that was cut short ([_append]).
  static const _cutShort = 0x23;

  /// How many days [_loaded] holds before it is emptied: a download reads
  /// the same one or two days for every photo of an outing.
  static const _loadedDays = 4;

  static final _fileName = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.txt$');

  final Directory _dir;
  final Duration _keep;

  /// The start (UTC) of every day that has a file, oldest first.
  final SplayTreeSet<DateTime> _days = SplayTreeSet();

  /// The positions of days read for [nearest], sorted by their time; a day
  /// leaves when its file changes.
  final Map<DateTime, List<LocationFix>> _loaded = {};

  /// The line of the position added last, to tell when it comes again.
  String? _lastLine;

  /// Completes when every call so far has finished.
  Future<void> _tail = Future.value();

  /// Adds [fixes], in any order. A position taken more than the kept time
  /// ago is left out, and so is one that repeats the position added just
  /// before it in every value. Days that ended more than the kept time ago
  /// are deleted. Never throws: positions that cannot be written are lost.
  Future<void> add(Iterable<LocationFix> fixes) {
    // Read now: the caller may change its list before this call's turn.
    final added = List.of(fixes);
    return _queued(() async {
      final oldest = clock.now().subtract(_keep);
      final lines = <DateTime, StringBuffer>{};
      var last = _lastLine;
      for (final fix in added) {
        if (fix.time.isBefore(oldest) || !_storable(fix)) continue;
        final line = _encode(fix);
        if (line == last) continue;
        last = line;
        lines.putIfAbsent(_dayOf(fix.time), StringBuffer.new).writeln(line);
      }
      _lastLine = last;
      for (final MapEntry(key: day, value: text) in lines.entries) {
        await _append(day, text.toString());
      }
      await _prune();
    });
  }

  /// The recorded position nearest in time to [capturedAt], whether the
  /// phone took it before or after; positions are compared by the time
  /// they were taken, not by when they were added. Null when the history
  /// has none for a photo taken then:
  ///
  /// - a photo taken more than the kept time ago gets none;
  /// - a photo with no position at or before it takes the next one only
  ///   when that came within 10 minutes of it.
  ///
  /// Never throws: a day that cannot be read counts as empty.
  Future<LocationFix?> nearest(DateTime capturedAt) => _queued(() async {
    final oldest = clock.now().subtract(_keep);
    if (capturedAt.isBefore(oldest)) return null;
    final captureDay = _dayOf(capturedAt);
    final days = _days.toList();

    LocationFix? before;
    for (final day in days.reversed) {
      if (day.isAfter(captureDay)) continue;
      final points = await _points(day);
      final through = _countThrough(points, capturedAt);
      if (through == 0) continue;
      before = points[through - 1];
      break;
    }
    // A day still on disk can hold positions that have run out; when the
    // latest one before the photo has, all before it have.
    if (before != null && before.time.isBefore(oldest)) before = null;

    // A later position is the answer only when it is nearer than the
    // earlier one, so the days past that distance are not read.
    final reach = before == null
        ? _followingWindow
        : capturedAt.difference(before.time);
    final horizon = capturedAt.add(reach);
    LocationFix? after;
    for (final day in days) {
      if (day.isBefore(captureDay)) continue;
      if (day.isAfter(horizon)) break;
      final points = await _points(day);
      final through = _countThrough(points, capturedAt);
      if (through == points.length) continue;
      after = points[through];
      break;
    }

    if (after == null) return before;
    final wait = after.time.difference(capturedAt);
    if (before == null) return wait <= _followingWindow ? after : null;
    return wait < capturedAt.difference(before.time) ? after : before;
  });

  /// Deletes every recorded position. Throws a [FileSystemException] when
  /// a day could not be deleted; the history still holds that day then.
  Future<void> clear() => _queued(() async {
    _loaded.clear();
    _lastLine = null;
    // The directory is asked rather than [_days], so that a day this run
    // failed to list goes too.
    if (_dir.existsSync()) {
      final files = [
        await for (final entry in _dir.list())
          if (entry is File && _dayOfFile(entry) != null) entry,
      ];
      for (final file in files) {
        await file.delete();
      }
    }
    _days.clear();
  });

  /// No position is recorded, or every one has run out.
  Future<bool> get isEmpty => _queued(() async {
    final oldest = clock.now().subtract(_keep);
    for (final day in _days.toList().reversed) {
      final points = await _points(day);
      if (points.isEmpty) continue;
      // The latest position there is: when it has run out, all have.
      return points.last.time.isBefore(oldest);
    }
    return true;
  });

  /// Runs [operation] once every earlier one has finished, whether or not
  /// it failed.
  Future<T> _queued<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _load() async {
    try {
      await _dir.create(recursive: true);
      await for (final entry in _dir.list()) {
        final day = entry is File ? _dayOfFile(entry) : null;
        if (day != null) _days.add(day);
      }
    } on FileSystemException catch (e) {
      debugPrint('Opening the location history failed: $e');
    }
    await _prune();
    if (_days.isNotEmpty) _lastLine = (await _lines(_days.last)).lastOrNull;
  }

  /// Deletes the days that ended more than [_keep] ago.
  Future<void> _prune() async {
    final oldest = _dayOf(clock.now().subtract(_keep));
    while (_days.isNotEmpty && _days.first.isBefore(oldest)) {
      final day = _days.first;
      _days.remove(day);
      _loaded.remove(day);
      try {
        await _file(day).delete();
      } on FileSystemException catch (e) {
        debugPrint('Deleting ${_name(day)} of the location history failed: $e');
      }
    }
  }

  /// Appends [lines], each ended by a line end, to [day]'s file.
  Future<void> _append(DateTime day, String lines) async {
    try {
      final file = await _file(day).open(mode: FileMode.append);
      try {
        final length = await file.length();
        if (length > 0) {
          // A line cut short when the app was stopped while writing it
          // would run into the first new one. It is closed with a
          // character no value has: what is left of it could read as a
          // whole position, with the digits its last value has left.
          await file.setPosition(length - 1);
          if (await file.readByte() != _newline) {
            await file.writeFrom(const [_cutShort, _newline]);
          }
        }
        // Not synced to the disk: a position lost with the phone's power
        // is no loss worth a sync for each one, and a line cut short is
        // passed over.
        await file.writeString(lines);
      } finally {
        await file.close();
      }
      _days.add(day);
      _loaded.remove(day);
    } on FileSystemException catch (e) {
      debugPrint('Writing ${_name(day)} of the location history failed: $e');
    }
  }

  /// The positions of [day], sorted by the time they were taken.
  Future<List<LocationFix>> _points(DateTime day) async {
    final loaded = _loaded[day];
    if (loaded != null) return loaded;
    final points = [for (final line in await _lines(day)) ?_decode(line, day)]
      ..sort((a, b) => a.time.compareTo(b.time));
    if (_loaded.length >= _loadedDays) _loaded.clear();
    return _loaded[day] = points;
  }

  /// The complete lines of [day]'s file in the order they were written;
  /// none when the file cannot be read. What follows the last line end was
  /// cut short while it was written and is left out.
  Future<List<String>> _lines(DateTime day) async {
    final String text;
    try {
      // Every byte is a character in Latin-1, so damage costs the lines it
      // is in rather than the whole day.
      text = await _file(day).readAsString(encoding: latin1);
    } on FileSystemException {
      return const [];
    }
    final lines = text.split('\n');
    return lines.sublist(0, lines.length - 1);
  }

  File _file(DateTime day) => File('${_dir.path}/${_name(day)}');

  static String _name(DateTime day) =>
      '${_digits(day.year, 4)}-${_digits(day.month, 2)}-'
      '${_digits(day.day, 2)}.txt';

  static String _digits(int value, int width) =>
      value.toString().padLeft(width, '0');

  /// The day [file] holds, or null when it is not one of the history's.
  static DateTime? _dayOfFile(File file) {
    final name = file.uri.pathSegments.last;
    final match = _fileName.firstMatch(name);
    if (match == null) return null;
    final day = DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    // A date that does not exist (month 13) is not a day file's name.
    return _name(day) == name ? day : null;
  }

  /// The start of the UTC day [time] is in.
  static DateTime _dayOf(DateTime time) {
    final utc = time.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// How many of [points], sorted by time, were taken at or before [time].
  static int _countThrough(List<LocationFix> points, DateTime time) {
    var low = 0;
    var high = points.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (points[middle].time.isAfter(time)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }

  static bool _onEarth(double latitude, double longitude) =>
      latitude.abs() <= 90 && longitude.abs() <= 180;

  /// [fix] is a place on Earth at a time a day file can be named for.
  static bool _storable(LocationFix fix) {
    final year = fix.time.toUtc().year;
    return _onEarth(fix.latitude, fix.longitude) && year >= 0 && year <= 9999;
  }

  static String _encode(LocationFix fix) {
    final altitude = fix.altitude;
    return '${fix.time.millisecondsSinceEpoch},'
        '${fix.latitude},${fix.longitude},'
        '${fix.accuracy.isFinite ? fix.accuracy : ''},'
        '${altitude != null && altitude.isFinite ? altitude : ''}';
  }

  /// The position [line] of [day]'s file holds, or null when it is not a
  /// line [_encode] wrote for a time in that day.
  static LocationFix? _decode(String line, DateTime day) {
    final fields = line.split(',');
    if (fields.length != 5) return null;
    final time = int.tryParse(fields[0]);
    final latitude = double.tryParse(fields[1]);
    final longitude = double.tryParse(fields[2]);
    final accuracy = fields[3].isEmpty
        ? double.infinity
        : double.tryParse(fields[3]);
    final altitude = fields[4].isEmpty ? null : double.tryParse(fields[4]);
    if (time == null ||
        latitude == null ||
        longitude == null ||
        accuracy == null ||
        accuracy.isNaN ||
        (altitude == null) != fields[4].isEmpty ||
        !(altitude?.isFinite ?? true) ||
        !_onEarth(latitude, longitude)) {
      return null;
    }
    final sinceMidnight = time - day.millisecondsSinceEpoch;
    if (sinceMidnight < 0 || sinceMidnight >= _oneDay.inMilliseconds) {
      return null;
    }
    return LocationFix(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      time: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
    );
  }
}
