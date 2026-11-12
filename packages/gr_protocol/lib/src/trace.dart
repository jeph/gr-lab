import 'dart:typed_data';

/// Receives every protocol exchange for hardware-validation logs.
typedef TraceSink = void Function(TraceEvent event);

/// Transport an exchange used.
enum TraceChannel {
  /// Bluetooth LE: scans, GATT reads, writes and notifications.
  ble,

  /// HTTP requests to the camera's web API.
  http,

  /// The `/v1/changes` WebSocket.
  websocket,

  /// The `/v1/liveview` MJPEG stream.
  liveview,

  /// Session-level decisions such as retries and state changes.
  session,

  /// The phone joining and leaving the camera network, including the
  /// native Wi-Fi code's own log lines.
  wifi,
}

/// Direction of a traced exchange.
enum TraceDirection {
  /// Phone to camera (or to the platform on the camera's behalf).
  outbound,

  /// Camera (or platform) to phone.
  inbound,

  /// A local decision or state change; nothing crossed the link.
  internal,
}

/// One observed protocol exchange. [bytes] holds raw binary payloads (BLE
/// values, advertisement data); [fields] holds structured detail such as
/// method, URL, headers, text bodies, status, UUIDs or decoded values.
final class TraceEvent {
  /// Event stamped with [time], or the current UTC time when omitted.
  new({
    required this.channel,
    required this.direction,
    required this.kind,
    DateTime? time,
    this.fields = const {},
    this.bytes,
  }) : time = time ?? DateTime.now().toUtc();

  /// When the exchange happened, UTC.
  final DateTime time;

  /// Transport the exchange used.
  final TraceChannel channel;

  /// Who sent it.
  final TraceDirection direction;

  /// Short event name within [channel], e.g. `request`, `open`, `notify`.
  final String kind;

  /// Structured detail; JSON-encodable values.
  final Map<String, Object?> fields;

  /// Raw binary payload, if any.
  final Uint8List? bytes;

  /// One JSON Lines trace record; [bytes] become lowercase `hex`.
  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'channel': channel.name,
    'direction': direction.name,
    'kind': kind,
    if (fields.isNotEmpty) 'fields': fields,
    if (bytes != null)
      'hex': bytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  };
}
