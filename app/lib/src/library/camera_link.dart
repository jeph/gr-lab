import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../connection/connection_controller.dart';

/// A usable Wi-Fi connection to one camera: what the library and the
/// download engine need from the session.
@immutable
final class CameraLink {
  const CameraLink({
    required this.serial,
    required this.http,
    this.storages = const [null],
    this.changes,
  });

  final String serial;
  final GrHttpClient http;

  /// Storages to list: `[in, sd1]` on a two-storage camera, `[null]` (no
  /// `storage=` parameter) on a camera with one.
  final List<String?> storages;

  /// `/v1/changes` events while the WebSocket is open.
  final Stream<GrChangeEvent>? changes;
}

/// Which storages to list, from `/v1/props`. GR WORLD adds `storage=` only
/// on cameras with two storages (http-api.md "Storage values"); a GR IV
/// lists only the SD card without it, so each equipped storage is listed on
/// its own.
List<String?> listedStorages(GrProps? props) {
  final storages = props?.storages ?? const <GrStorageInfo>[];
  if (storages.length < 2) return const [null];
  final names = [
    for (final s in storages)
      if (s.name case final name? when s.equipped != false) name,
  ];
  return names.isEmpty ? const [null] : names;
}

/// [CameraLink] of the [ConnectionController]: non-null while connected and
/// not recovering Wi-Fi, so work pauses during a rejoin and resumes with a
/// fresh link afterwards.
final class ConnectionLink extends ValueNotifier<CameraLink?> {
  ConnectionLink(this._connection) : super(null) {
    _connection.addListener(_update);
    _update();
  }

  final ConnectionController _connection;

  void _update() {
    final http = _connection.http;
    final serial = _connection.camera?.serial;
    if (http == null || serial == null || _connection.reconnecting) {
      value = null;
      return;
    }
    final current = value;
    if (current != null &&
        identical(current.http, http) &&
        current.serial == serial) {
      return;
    }
    value = CameraLink(
      serial: serial,
      http: http,
      storages: listedStorages(_connection.props),
      changes: _connection.session?.changes?.events,
    );
  }

  @override
  void dispose() {
    _connection.removeListener(_update);
    super.dispose();
  }
}
