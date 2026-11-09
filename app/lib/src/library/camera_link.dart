import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/connection/connection_controller.dart';

/// The [CameraLibrary] of the [ConnectionController]'s session: non-null
/// while the camera's Wi-Fi is up, so work stops when it goes, and a new
/// one after every rejoin. Whether it is the camera a user works for is the
/// user's to check against [CameraLibrary.serial] (`LibraryModel` for its
/// listing, `CameraImages` and `DownloadEngine` per request).
final class ConnectionLink extends ValueNotifier<CameraLibrary?> {
  new(this._connection) : super(null) {
    _connection.addListener(_update);
    _update();
  }

  final ConnectionController _connection;

  void _update() {
    value = _connection.status == ConnectionStatus.connected
        ? _connection.cameraSession?.library
        : null;
  }

  @override
  void dispose() {
    _connection.removeListener(_update);
    super.dispose();
  }
}
