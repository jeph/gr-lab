import 'dart:typed_data';

/// Platform Bluetooth LE central, implemented outside this package
/// (`universal_ble` in the Flutter app, fakes in tests).
///
/// UUIDs crossing this interface are canonical: uppercase, dashed, 128-bit
/// (see [canonicalUuid]).
abstract interface class BleTransport {
  Future<BleAdapterState> adapterState();

  /// Scans while the returned stream has a listener; cancelling stops the scan.
  /// Every advertisement and scan response is delivered (duplicates included).
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []});

  /// Opens a GATT connection. Bonding is left to the platform, which pairs
  /// when the camera first requires an encrypted attribute.
  Future<BleConnection> connect(String deviceId, {required Duration timeout});

  /// Releases the transport; open connections are disconnected.
  Future<void> close();
}

abstract interface class BleConnection {
  String get deviceId;

  /// Largest value accepted by one write with response, if the platform reports it.
  int? get maximumWriteLength;

  Future<List<BleServiceInfo>> discover();

  /// [timeout] is the deadline the platform request itself must allow.
  /// Plugins impose their own (universal_ble: 10 s), which would otherwise
  /// cut a read that is waiting for the user to confirm a pairing code.
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  });

  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  });

  /// Enables notifications when listened to and disables them on cancel.
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid);

  /// Bonds with the peer on this open link and completes once the bond is
  /// usable. Android, Windows and Linux use the system pairing call (GR
  /// WORLD calls Android `createBond()`); CoreBluetooth has none and pairs
  /// on the first encrypted access, so the transport reads
  /// [probeServiceUuid]/[probeCharacteristicUuid] (an encrypted, readable
  /// characteristic). [timeout] must cover the user confirming the code.
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  });

  /// Completes once when the link drops, for any reason.
  Future<BleDisconnect> get disconnected;

  Future<void> disconnect();
}

enum BleAdapterState {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn,
}

enum BleCharacteristicProperty {
  read,
  write,
  writeWithoutResponse,
  notify,
  indicate,
}

final class BleAdvertisement {
  const BleAdvertisement({
    required this.deviceId,
    required this.rssi,
    this.name,
    this.manufacturerData = const {},
    this.serviceUuids = const [],
    this.connectable,
  });

  /// Platform peripheral identifier (CoreBluetooth UUID, Android MAC).
  /// Not a camera identity: use the advertised serial number for that.
  final String deviceId;
  final String? name;
  final int rssi;

  /// Manufacturer-specific data keyed by Bluetooth SIG company ID; payloads
  /// exclude the 2-byte company ID.
  final Map<int, Uint8List> manufacturerData;
  final List<String> serviceUuids;
  final bool? connectable;
}

final class BleServiceInfo {
  const BleServiceInfo({required this.uuid, required this.characteristics});

  final String uuid;
  final List<BleCharacteristicInfo> characteristics;
}

final class BleCharacteristicInfo {
  const BleCharacteristicInfo({required this.uuid, required this.properties});

  final String uuid;
  final Set<BleCharacteristicProperty> properties;
}

final class BleDisconnect {
  const BleDisconnect({
    required this.requested,
    this.reason,
    this.bondRejected = false,
  });

  /// True when this side called [BleConnection.disconnect].
  final bool requested;
  final String? reason;

  /// The peer refused this device's stored pairing keys (see
  /// [BleErrorCode.bondRejected]).
  final bool bondRejected;
}

enum BleErrorCode {
  timeout,
  notConnected,
  notFound,
  unauthorized,

  /// The peer refused this device's stored pairing keys, e.g. CoreBluetooth
  /// "Peer removed pairing information". The bond is gone on the peer side;
  /// only deleting it on both sides and pairing again recovers. Retrying
  /// does harm on GR cameras: a pairing request outside Execute Pairing
  /// makes the camera delete its entry (docs/protocol/firmware-bonding.md
  /// §2).
  bondRejected,
  poweredOff,
  gatt,
  transport,
}

final class BleException implements Exception {
  const BleException(this.code, this.message);

  final BleErrorCode code;
  final String message;

  @override
  String toString() => 'BleException(${code.name}): $message';
}

const _baseUuidSuffix = '-0000-1000-8000-00805F9B34FB';

/// Uppercase dashed 128-bit form; 16- and 32-bit short UUIDs are expanded
/// with the Bluetooth base UUID.
String canonicalUuid(String uuid) {
  final u = uuid.trim().toUpperCase();
  if (RegExp(r'^[0-9A-F]{4}$').hasMatch(u)) return '0000$u$_baseUuidSuffix';
  if (RegExp(r'^[0-9A-F]{8}$').hasMatch(u)) return '$u$_baseUuidSuffix';
  if (RegExp(r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$')
      .hasMatch(u)) {
    return u;
  }
  throw FormatException('Not a Bluetooth UUID', uuid);
}
