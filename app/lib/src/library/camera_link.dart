import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/connection/connection_controller.dart';

/// The [CameraLibrary] of the [ConnectionController]'s camera: non-null
/// while connected, so work stops when the Wi-Fi goes, and a new one after
/// every rejoin.
final class ConnectionLink extends ValueNotifier<CameraLibrary?> {
  new(this._connection) : super(null) {
    _connection.addListener(_update);
    _update();
  }

  final ConnectionController _connection;

  void _update() {
    final serial = _connection.camera?.serial;
    final library = _connection.status == ConnectionStatus.connected
        ? _connection.cameraSession?.library
        : null;
    value = library == null || serial == null || library.serial != serial
        ? null
        : library;
  }

  @override
  void dispose() {
    _connection.removeListener(_update);
    super.dispose();
  }
}
