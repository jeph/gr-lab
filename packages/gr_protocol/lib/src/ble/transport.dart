import 'dart:typed_data';

/// Platform Bluetooth LE central, implemented outside this package
/// (`universal_ble` in the Flutter app, fakes in tests).
///
/// UUIDs crossing this interface are canonical: uppercase, dashed, 128-bit
/// (see [canonicalUuid]).
abstract interface class BleTransport {
  /// Current state of the phone's Bluetooth adapter.
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

/// An open GATT link to one peripheral. Reads and writes use canonical
/// service and characteristic UUIDs; callers serialize operations (see
/// `GrBleClient`).
abstract interface class BleConnection {
  /// Platform peripheral identifier this link was opened with.
  String get deviceId;

  /// Largest value accepted by one write with response, if the platform
  /// reports it.
  int? get maximumWriteLength;

  /// Discovers every service and characteristic with its declared
  /// properties.
  Future<List<BleServiceInfo>> discover();

  /// Reads one characteristic value. [timeout] is the deadline the
  /// platform request itself must allow. Plugins impose their own
  /// (universal_ble: 10 s), which would otherwise cut a read that is
  /// waiting for the user to confirm a pairing code.
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  });

  /// Writes [value] to one characteristic, with response unless
  /// [withResponse] is false. [timeout] works as for [read].
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

  /// Closes the link from this side; [disconnected] then completes with
  /// [BleDisconnect.requested] true.
  Future<void> disconnect();
}

/// State of the phone's Bluetooth adapter, as CoreBluetooth names it.
enum BleAdapterState {
  /// Not known yet; CoreBluetooth reports this until its manager started.
  unknown,

  /// The stack is restarting; the state will change shortly.
  resetting,

  /// The phone has no Bluetooth LE support.
  unsupported,

  /// The app may not use Bluetooth (permission denied).
  unauthorized,

  /// Bluetooth is turned off.
  poweredOff,

  /// Bluetooth is on and usable.
  poweredOn,
}

/// GATT characteristic property declared by the peripheral.
enum BleCharacteristicProperty {
  /// Value can be read.
  read,

  /// Value can be written with response.
  write,

  /// Value can be written without response.
  writeWithoutResponse,

  /// Value changes can be notified (unacknowledged).
  notify,

  /// Value changes can be indicated (acknowledged).
  indicate,
}

/// One advertisement or scan response as the platform scanner reported it.
final class BleAdvertisement {
  /// Creates an advertisement; transports build these from scan results.
  const new({
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

  /// Advertised local name, or null when this packet had none.
  final String? name;

  /// Received signal strength in dBm.
  final int rssi;

  /// Manufacturer-specific data keyed by Bluetooth SIG company ID; payloads
  /// exclude the 2-byte company ID.
  final Map<int, Uint8List> manufacturerData;

  /// Advertised service UUIDs, canonical.
  final List<String> serviceUuids;

  /// Whether the advertisement is connectable, when the platform reports
  /// it.
  final bool? connectable;
}

/// One discovered GATT service.
final class BleServiceInfo {
  /// Creates a service entry; transports build these in discovery.
  const new({required this.uuid, required this.characteristics});

  /// Service UUID, canonical.
  final String uuid;

  /// Characteristics discovered under this service.
  final List<BleCharacteristicInfo> characteristics;
}

/// One discovered GATT characteristic.
final class BleCharacteristicInfo {
  /// Creates a characteristic entry; transports build these in discovery.
  const new({required this.uuid, required this.properties});

  /// Characteristic UUID, canonical.
  final String uuid;

  /// Properties the peripheral declares for it.
  final Set<BleCharacteristicProperty> properties;
}

/// How a link ended; the value of [BleConnection.disconnected].
final class BleDisconnect {
  /// Creates a disconnect record.
  const new({required this.requested, this.reason, this.bondRejected = false});

  /// True when this side called [BleConnection.disconnect].
  final bool requested;

  /// Platform's disconnect reason text, when it gives one.
  final String? reason;

  /// The peer refused this device's stored pairing keys (see
  /// [BleErrorCode.bondRejected]).
  final bool bondRejected;
}

/// Category of a [BleException], mapped from the platform's error.
enum BleErrorCode {
  /// The operation did not complete in time.
  timeout,

  /// The link is not (or no longer) connected.
  notConnected,

  /// Device, service or characteristic not found.
  notFound,

  /// Bluetooth permission denied, or the peer refused access
  /// (insufficient authentication or encryption).
  unauthorized,

  /// The peer refused this device's stored pairing keys, e.g. CoreBluetooth
  /// "Peer removed pairing information". The bond is gone on the peer side;
  /// only deleting it on both sides and pairing again recovers. Retrying
  /// does harm on GR cameras: a pairing request outside Execute Pairing
  /// makes the camera delete its entry (docs/protocol/firmware-bonding.md
  /// §2).
  bondRejected,

  /// Bluetooth is turned off.
  poweredOff,

  /// The peer rejected or failed a GATT read or write.
  gatt,

  /// Any other platform or transport failure.
  transport,
}

/// Failure of a Bluetooth operation, raised by transports and
/// `GrBleClient`.
final class BleException implements Exception {
  /// Creates an exception of category [code].
  const new(this.code, this.message);

  /// Category, for deciding whether and how to recover.
  final BleErrorCode code;

  /// Platform or client description of the failure.
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
