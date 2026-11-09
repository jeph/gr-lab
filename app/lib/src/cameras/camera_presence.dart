import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/data/cameras.dart';

/// What the scan says about one paired camera.
enum Presence {
  /// Not advertising, or not since [PresenceScanner.forgetAfter].
  away,

  /// Advertising; its power state is unknown.
  nearby,

  /// Advertising as switched off: Connect wakes it.
  nearbyOff,

  /// Advertising as switched on.
  nearbyOn,
}

/// Which paired cameras are nearby and switched on, from their Bluetooth
/// advertisements while the Cameras screen scans ([PresenceScanner]).
final class CameraPresence implements Listenable {
  new(
    GrCameraEnvironment camera, {
    Duration forgetAfter = const Duration(seconds: 15),
    Duration settleAfter = const Duration(seconds: 8),
  }) : _scanner = PresenceScanner(
         camera,
         forgetAfter: forgetAfter,
         settleAfter: settleAfter,
       );

  final PresenceScanner _scanner;

  bool get scanning => _scanner.scanning;

  /// The scan has run long enough that a camera it has not seen is away.
  bool get settled => _scanner.settled;

  /// Why the last scan stopped (Bluetooth off, platform error).
  Object? get error => _scanner.error;

  /// What the scan says about [camera]: matched by its paired device id or
  /// its serial.
  Presence of(SavedCamera camera) {
    final seen = _scanner.sighting(
      deviceId: camera.paired.deviceId,
      serial: camera.serial,
    );
    if (seen == null) return Presence.away;
    return switch (seen.powerOn) {
      true => Presence.nearbyOn,
      false => Presence.nearbyOff,
      null => Presence.nearby,
    };
  }

  void start() => _scanner.start();

  /// Stops scanning, as connecting or another screen's scan needs. What
  /// was seen is kept until it is old.
  Future<void> stop() => _scanner.stop();

  @override
  void addListener(VoidCallback listener) => _scanner.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _scanner.removeListener(listener);

  void dispose() => _scanner.dispose();
}
