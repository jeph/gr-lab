import 'dart:typed_data';

/// Receives every protocol exchange for hardware-validation logs.
typedef TraceSink = void Function(TraceEvent event);

enum TraceChannel { ble, http, websocket, liveview, session }

enum TraceDirection { outbound, inbound, internal }

/// One observed protocol exchange. [bytes] holds raw payloads (BLE values,
/// HTTP bodies up to a caller-chosen cap); [fields] holds structured detail
/// such as method, URL, status, UUIDs or decoded values.
final class TraceEvent {
  TraceEvent({
    required this.channel,
    required this.direction,
    required this.kind,
    DateTime? time,
    this.fields = const {},
    this.bytes,
  }) : time = time ?? DateTime.now().toUtc();

  final DateTime time;
  final TraceChannel channel;
  final TraceDirection direction;
  final String kind;
  final Map<String, Object?> fields;
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
