import 'dart:async';

import '../trace.dart';
import 'catalog.dart';
import 'client.dart';
import 'model.dart';
import 'transport.dart';
import 'wake.dart';

/// A camera this client has paired with. Persist it: [deviceId] is what
/// later connects and wakes use, and [serialNumber] matches adverts.
final class GrPairedCamera {
  const GrPairedCamera({
    required this.deviceId,
    required this.serialNumber,
    this.modelName,
    this.firmwareRevision,
    this.bluetoothDeviceName,
    this.bluetoothMacAddress,
  });

  factory GrPairedCamera.fromJson(Map<String, Object?> json) => GrPairedCamera(
    deviceId: json['deviceId']! as String,
    serialNumber: json['serialNumber']! as String,
    modelName: json['modelName'] as String?,
    firmwareRevision: json['firmwareRevision'] as String?,
    bluetoothDeviceName: json['bluetoothDeviceName'] as String?,
    bluetoothMacAddress: json['bluetoothMacAddress'] as String?,
  );

  /// Platform peripheral id (CoreBluetooth UUID, Android MAC).
  final String deviceId;
  final String serialNumber;
  final String? modelName;
  final String? firmwareRevision;
  final String? bluetoothDeviceName;
  final String? bluetoothMacAddress;

  GrModel? get model {
    final m = modelName;
    return m == null ? null : GrModel.fromModelString(m);
  }

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'serialNumber': serialNumber,
    'modelName': modelName,
    'firmwareRevision': firmwareRevision,
    'bluetoothDeviceName': bluetoothDeviceName,
    'bluetoothMacAddress': bluetoothMacAddress,
  };
}

/// Where [pairCamera] is, for UI prompts.
enum GrPairingStage {
  /// Looking for a powered-on camera.
  scanning,

  /// Connected; the OS pairing is running. The user must confirm the code
  /// on this device **and** press OK on the camera (GR WORLD copy
  /// pp+0x695b0; the OK is the camera's numeric-comparison accept,
  /// docs/protocol/firmware-bonding.md §2).
  awaitingConfirmation,

  /// Bonded; reading Camera Information and writing this client's name.
  registering,
}

enum GrPairingFailure {
  /// No powered-on GR camera advertised within the scan timeout.
  notFound,

  /// The camera advertises power off; pairing needs it on.
  cameraOff,

  /// No connection or GATT discovery.
  connectFailed,

  /// The OS pairing failed or timed out: the camera was not on Execute
  /// Pairing (it refuses and disconnects), the code was not confirmed, the
  /// camera still lists this device (it refuses known addresses), or it
  /// is refusing after repeated attempts (SMP reason 9). Start Execute
  /// Pairing again; do not retry automatically.
  notConfirmed,

  /// Bonded, but Camera Information still could not be read.
  bondUnusable,

  /// The Client Registration write failed. The camera only accepts it for
  /// a device it recorded as paired (firmware `PairedDeviceName::Write`
  /// 0x55e30), so this means the camera did not record the pairing.
  registrationFailed,
}

final class GrPairingException implements Exception {
  const GrPairingException(this.failure, this.message, [this.cause]);
  final GrPairingFailure failure;
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GrPairingException(${failure.name}): $message'
      '${cause == null ? '' : ' ($cause)'}';
}

/// Result of [pairCamera]: what to persist, plus the still-open link.
final class GrPairing {
  const GrPairing(this.camera, this.client);

  final GrPairedCamera camera;

  /// The pairing link. GR WORLD keeps it open after pairing; continue on it
  /// or call `client.connection.disconnect()`.
  final GrBleClient client;
}

/// Pairs with a camera that is on and showing **Execute Pairing**, in GR
/// WORLD's order (docs/protocol/grworld-connect-flow.md §1), on one link:
///
/// 1. scan for a powered-on camera, connect, discover, read the DIS model
///    and firmware (unencrypted);
/// 2. one explicit OS pairing ([BleConnection.pair]; GR WORLD calls
///    Android `createBond()`), bounded by [confirmationTimeout] (GR WORLD:
///    90 s);
/// 3. read Camera Information, then write [clientName] to Client
///    Registration last.
///
/// There is no automatic retry. Camera firmware deletes the entry of a
/// device that requests pairing outside Execute Pairing, refuses pairing
/// from an address it still lists, and answers rapid retries with SMP
/// reason 9 (docs/protocol/firmware-bonding.md §2).
Future<GrPairing> pairCamera(
  BleTransport transport, {
  required String clientName,
  String? serial,
  Duration scanTimeout = const Duration(seconds: 30),
  Duration connectTimeout = const Duration(seconds: 35),
  Duration confirmationTimeout = const Duration(seconds: 90),
  void Function(GrPairingStage stage)? onStage,
  TraceSink? trace,
}) async {
  void emit(String kind, [Map<String, Object?> fields = const {}]) =>
      trace?.call(
        TraceEvent(
          channel: TraceChannel.ble,
          direction: TraceDirection.internal,
          kind: 'pair.$kind',
          fields: fields,
        ),
      );

  onStage?.call(GrPairingStage.scanning);
  emit('scan', {'serial': serial});
  final ad = await findGrAdvertisement(
    transport,
    timeout: scanTimeout,
    where: (a) =>
        a.isGrCamera &&
        (serial == null || grSerialMatches(serial, a.serialNumber)),
  );
  if (ad == null) {
    throw const GrPairingException(
      GrPairingFailure.notFound,
      'no GR camera advertisement',
    );
  }
  if (ad.powerOn == false) {
    throw const GrPairingException(
      GrPairingFailure.cameraOff,
      'turn the camera on and open Execute Pairing',
    );
  }
  emit('found', ad.toJson());

  final BleConnection connection;
  try {
    connection = await transport.connect(ad.deviceId, timeout: connectTimeout);
  } on BleException catch (e) {
    throw GrPairingException(GrPairingFailure.connectFailed, 'connect', e);
  }
  final client = GrBleClient(connection, trace: trace);

  Future<Never> fail(GrPairingFailure f, String message, Object? e) async {
    await connection.disconnect();
    throw GrPairingException(f, message, e);
  }

  try {
    await client.discover();
  } on BleException catch (e) {
    return fail(GrPairingFailure.connectFailed, 'service discovery', e);
  }
  for (final c in [
    GrBleCatalog.disModelNumber,
    GrBleCatalog.disFirmwareRevision,
  ]) {
    if (client.isPresent(c) != true) continue;
    try {
      emit('dis', {'key': c.key, 'value': (await client.read(c)).value});
    } on BleException catch (e) {
      emit('disFailed', {'key': c.key, 'error': '$e'});
    }
  }

  onStage?.call(GrPairingStage.awaitingConfirmation);
  emit('bond.start');
  try {
    await connection.pair(
      probeServiceUuid: GrBleCatalog.serialNumber.service.uuid,
      probeCharacteristicUuid: GrBleCatalog.serialNumber.uuid,
      timeout: confirmationTimeout,
    );
  } on BleException catch (e) {
    return fail(
      GrPairingFailure.notConfirmed,
      'pairing was not completed; open Execute Pairing on the camera, '
      'remove this device from its Paired Devices list if it is there, '
      'and try again',
      e,
    );
  }
  emit('bond.done');

  onStage?.call(GrPairingStage.registering);
  final identity = await client.readIdentity();
  final serialNumber = identity.serialNumber;
  if (serialNumber == null) {
    return fail(
      GrPairingFailure.bondUnusable,
      'Camera Information unreadable after pairing',
      identity.issues,
    );
  }
  try {
    await client.setPairedDeviceName(clientName);
  } on BleException catch (e) {
    return fail(
      GrPairingFailure.registrationFailed,
      'the camera did not record the pairing (was OK pressed on the camera?)',
      e,
    );
  }
  final paired = GrPairedCamera(
    deviceId: connection.deviceId,
    serialNumber: serialNumber,
    modelName: identity.modelName,
    firmwareRevision: identity.firmwareRevision,
    bluetoothDeviceName: identity.bluetoothDeviceName,
    bluetoothMacAddress: identity.bluetoothMacAddress,
  );
  emit('paired', paired.toJson());
  return GrPairing(paired, client);
}
