import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:grphoto/src/geotag/location_history.dart';
import 'package:grphoto/src/geotag/photo_location.dart';

/// Background geotagging at download: gives a shot's photos the place the
/// phone was at when they were taken, from the [LocationHistory].
///
/// A photo's capture time is the camera's clock with no zone; it is read
/// as local time in the phone's current zone \[design\], so it matches the
/// history only as well as the camera's clock matches the phone's.
final class DownloadGeotagger {
  /// Matches against [history] for the cameras [enabled] answers true for
  /// (background geotagging is on for the camera with that serial
  /// number). [beforeMatch] runs once per [tag] call that has a
  /// photo to match, before the history is asked: the moment to hand it
  /// the positions the phone still holds. [log] gets one line per file
  /// saying what became of it, never a position; the debug log when left
  /// out.
  new({
    required this.history,
    required this.enabled,
    this.beforeMatch,
    void Function(String line)? log,
  }) : _log = log ?? debugPrint;

  /// The positions a photo's location is taken from.
  final LocationHistory history;

  /// Whether background geotagging is on for the camera with the given
  /// serial number.
  final bool Function(String serial) enabled;

  /// Runs before the history is asked, once per [tag] call that has a
  /// photo to match.
  final Future<void> Function()? beforeMatch;

  final void Function(String line) _log;

  /// Gives every JPEG and DNG in [files], downloaded from [serial]'s
  /// camera, without a location the nearest one from the history. Never
  /// throws; a download never fails because of
  /// its location.
  ///
  /// A file the camera gave a location keeps it, and a movie, a photo
  /// without a capture time and a photo the history has no position for
  /// (see [LocationHistory.nearest]) stay as they are.
  Future<void> tag(String serial, List<File> files) async {
    try {
      if (!enabled(serial)) return;
      var prepared = false;
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final captured = await readCaptureTime(file);
        if (captured == null) {
          _log('Geotag $name: no capture time');
          continue;
        }
        if (!prepared) {
          prepared = true;
          await _prepare();
        }
        final fix = await history.nearest(captured.toUtc());
        if (fix == null) {
          _log('Geotag $name: no position in the history');
          continue;
        }
        final outcome = await writeLocation(file, fix);
        _log('Geotag $name: ${outcome.name}');
      }
    } on Object catch (e) {
      // Only the type: what failed may have a position in its message.
      debugPrint('Geotagging a download failed: ${e.runtimeType}');
    }
  }

  /// Runs [beforeMatch]; when it fails, the photos are matched against
  /// what the history has.
  Future<void> _prepare() async {
    try {
      await beforeMatch?.call();
    } on Object catch (e) {
      _log('Geotag: preparing the history failed (${e.runtimeType})');
    }
  }
}
