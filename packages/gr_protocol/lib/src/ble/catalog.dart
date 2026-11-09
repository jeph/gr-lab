import 'dart:typed_data';

import 'package:gr_protocol/src/ble/aggregate.dart';
import 'package:gr_protocol/src/ble/codecs.dart';
import 'package:gr_protocol/src/ble/enums.dart';
import 'package:gr_protocol/src/ble/records.dart';
import 'package:gr_protocol/src/ble/tables.dart';
import 'package:gr_protocol/src/ble/transport.dart';

/// Which reverse-engineered app documents (and uses) an attribute.
enum GrBleApp {
  /// GR WORLD 2.0.0 (research/protocol/ble.md), the GR IV-capable app.
  grWorld,

  /// Image Sync 2.1.32 (research/protocol/ble-imagesync.md), GR III only.
  imageSync,
}

/// A GATT service of the camera.
final class GrBleService {
  /// Creates the catalog entry for one service.
  const new({
    required this.key,
    required this.uuid,
    required this.name,
    this.imageSyncName,
    this.onGr3,
    this.onGr4,
  });

  /// Stable kebab-case name used by the CLI.
  final String key;

  /// Canonical UUID (see [canonicalUuid]).
  final String uuid;

  /// Name used in research/protocol/ble.md.
  final String name;

  /// Name in Image Sync's `def_ble.yaml`, when it differs.
  final String? imageSyncName;

  /// Whether the UUID bytes occur in the analyzed GR III `bled` binary
  /// (research/firmware-protocol-inventory.md; null = not established).
  /// Byte presence does not prove runtime registration.
  final bool? onGr3;

  /// Same as [onGr3], for the GR IV `bled` binary.
  final bool? onGr4;

  /// JSON form of this entry.
  Map<String, Object?> toJson() => {
    'key': key,
    'uuid': uuid,
    'name': name,
    'imageSyncName': imageSyncName,
    'firmware': {'gr3': onGr3, 'gr4': onGr4},
  };
}

/// One characteristic with its typed codec and provenance.
final class GrBleCharacteristic<T extends Object> {
  /// Creates the catalog entry for one characteristic.
  const new({
    required this.key,
    required this.name,
    required this.uuid,
    required this.service,
    required this.properties,
    required this.apps,
    required this.onGr3,
    required this.onGr4,
    required this.codec,
    this.guarded = false,
    this.notes,
  });

  /// Stable kebab-case name used by the CLI.
  final String key;

  /// Display name, from research/protocol/ble.md or Image Sync's `def_ble.yaml`.
  final String name;

  /// Canonical UUID.
  final String uuid;

  /// Service the characteristic belongs to.
  final GrBleService service;

  /// Union of the properties both apps document (GR WORLD "Ops", Image
  /// Sync `property`). Discovery reports what the camera declares.
  final Set<BleCharacteristicProperty> properties;

  /// Apps whose analysis documents this characteristic.
  final Set<GrBleApp> apps;

  /// UUID byte presence in GR III `bled` (ble-imagesync.md §1 diff;
  /// firmware-protocol-inventory.md). Null = not established.
  final bool? onGr3;

  /// Same as [onGr3], for GR IV `bled`.
  final bool? onGr4;

  /// Writing can power the camera off, change Wi-Fi credentials or pairing
  /// behaviour, or touch firmware; front ends must require confirmation.
  final bool guarded;

  /// Decodes and encodes the value bytes.
  final BleCodec<T> codec;

  /// Layout differences or unknowns worth showing to a user.
  final String? notes;

  /// Whether [properties] include read.
  bool get readable => properties.contains(BleCharacteristicProperty.read);

  /// Whether [properties] include write, with or without response.
  bool get writable =>
      properties.contains(BleCharacteristicProperty.write) ||
      properties.contains(BleCharacteristicProperty.writeWithoutResponse);

  /// Whether [properties] include notify or indicate.
  bool get notifies =>
      properties.contains(BleCharacteristicProperty.notify) ||
      properties.contains(BleCharacteristicProperty.indicate);

  /// JSON form of this entry; [service] appears as its key.
  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'uuid': uuid,
    'service': service.key,
    'properties': [for (final p in properties) p.name],
    'apps': [for (final a in apps) a.name],
    'firmware': {'gr3': onGr3, 'gr4': onGr4},
    'guarded': guarded,
    'syntax': codec.syntax,
    'notes': ?notes,
  };
}

const Set<BleCharacteristicProperty> _r = {BleCharacteristicProperty.read};
const Set<BleCharacteristicProperty> _w = {BleCharacteristicProperty.write};
const Set<BleCharacteristicProperty> _rw = {
  BleCharacteristicProperty.read,
  BleCharacteristicProperty.write,
};
const Set<BleCharacteristicProperty> _rn = {
  BleCharacteristicProperty.read,
  BleCharacteristicProperty.notify,
};
const Set<BleCharacteristicProperty> _rwn = {
  BleCharacteristicProperty.read,
  BleCharacteristicProperty.write,
  BleCharacteristicProperty.notify,
};

const Set<GrBleApp> _both = {GrBleApp.grWorld, GrBleApp.imageSync};
const Set<GrBleApp> _gw = {GrBleApp.grWorld};
const Set<GrBleApp> _is = {GrBleApp.imageSync};

/// The camera's GATT services (ble.md §Services; ble-imagesync.md §1).
abstract final class GrBleServices {
  /// Standard Device Information (`180A`). Readable without encryption
  /// (observed on GR IV); GR WORLD reads model and firmware here when
  /// pairing.
  static const deviceInformation = GrBleService(
    key: 'device-information',
    uuid: '0000180A-0000-1000-8000-00805F9B34FB',
    name: 'Device Information',
  );

  /// Camera identity strings. GR WORLD scans for this UUID to find cameras;
  /// the camera presumably advertises it while on \[inferred\].
  static const cameraInformation = GrBleService(
    key: 'camera-information',
    uuid: '9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1',
    name: 'Camera Information',
    imageSyncName: 'Camera Information Service',
    onGr3: true,
    onGr4: true,
  );

  /// Shooting: exposure settings, shutter release, focus and capture status.
  static const cameraControl = GrBleService(
    key: 'camera-control',
    uuid: '9F00F387-8345-4BBC-8B92-B87B52E3091A',
    name: 'Camera Control',
    imageSyncName: 'Shooting Service',
    onGr3: true,
    onGr4: true,
  );

  /// Camera-wide state: power, battery, clock, operation mode, storage,
  /// transfer and firmware update.
  static const cameraState = GrBleService(
    key: 'camera-state',
    uuid: '4B445988-CAA0-4DD3-941D-37B4F52ACA86',
    name: 'Camera State',
    imageSyncName: 'Camera Service',
    onGr3: true,
    onGr4: true,
  );

  /// The camera's Wi-Fi access point: on/off, credentials, band.
  static const wlanControl = GrBleService(
    key: 'wlan-control',
    uuid: 'F37F568F-9071-445D-A938-5441F2E82399',
    name: 'WLAN Control',
    imageSyncName: 'WLAN Control Command',
    onGr3: true,
    onGr4: true,
  );

  /// Phone location pushed to the camera for geotagging.
  static const gps = GrBleService(
    key: 'gps',
    uuid: '84A0DD62-E8AA-4D0F-91DB-819B6724C69E',
    name: 'GPS',
    imageSyncName: 'GPS Control Command',
    onGr3: true,
    onGr4: true,
  );

  /// Client registration, written after bonding. A powered-off camera
  /// advertises this UUID instead of Camera Information (observed on
  /// GR IV HDF).
  static const clientRegistration = GrBleService(
    key: 'client-registration',
    uuid: '0F291746-0C80-4726-87A7-3C501FD3B4B6',
    name: 'Client Registration',
    imageSyncName: 'Bluetooth Control Command',
    onGr3: true,
    onGr4: true,
  );

  /// Every service, in catalog order.
  static const List<GrBleService> all = [
    deviceInformation,
    cameraInformation,
    cameraControl,
    cameraState,
    wlanControl,
    gps,
    clientRegistration,
  ];

  /// Lookup by UUID in any accepted form; null when unknown. Throws
  /// [FormatException] when [uuid] is malformed.
  static GrBleService? byUuid(String uuid) {
    final u = canonicalUuid(uuid);
    for (final s in all) {
      if (s.uuid == u) return s;
    }
    return null;
  }
}

/// Every characteristic documented by GR WORLD 2.0.0 and Image Sync 2.1.32.
abstract final class GrBleCatalog {
  // Device Information 180A (standard; bled has no DIS implementation, so
  // firmware presence is not established).

  /// Standard manufacturer string; neither GR app reads it.
  static const GrBleCharacteristic<String> disManufacturerName =
      GrBleCharacteristic(
        key: 'dis-manufacturer-name',
        name: 'Manufacturer Name (DIS)',
        uuid: '00002A29-0000-1000-8000-00805F9B34FB',
        service: GrBleServices.deviceInformation,
        properties: _r,
        apps: _both,
        onGr3: null,
        onGr4: null,
        codec: BleUtf8Codec(),
      );

  /// Model string GR WORLD reads when pairing to pick the minimum firmware.
  static const GrBleCharacteristic<String> disModelNumber = GrBleCharacteristic(
    key: 'dis-model-number',
    name: 'Model Number (DIS)',
    uuid: '00002A24-0000-1000-8000-00805F9B34FB',
    service: GrBleServices.deviceInformation,
    properties: _r,
    apps: _both,
    onGr3: null,
    onGr4: null,
    codec: BleUtf8Codec(),
    notes:
        'GR WORLD gates firmware on exact "GR IV"/"GR IIIx"/"GR III"/"GR II"',
  );

  /// Standard serial number string; neither GR app reads it.
  static const GrBleCharacteristic<String> disSerialNumber =
      GrBleCharacteristic(
        key: 'dis-serial-number',
        name: 'Serial Number (DIS)',
        uuid: '00002A25-0000-1000-8000-00805F9B34FB',
        service: GrBleServices.deviceInformation,
        properties: _r,
        apps: _both,
        onGr3: null,
        onGr4: null,
        codec: BleUtf8Codec(),
      );

  /// Firmware version (`major.minor`) GR WORLD checks against the model's
  /// minimum when pairing.
  static const GrBleCharacteristic<String> disFirmwareRevision =
      GrBleCharacteristic(
        key: 'dis-firmware-revision',
        name: 'Firmware Revision (DIS)',
        uuid: '00002A26-0000-1000-8000-00805F9B34FB',
        service: GrBleServices.deviceInformation,
        properties: _r,
        apps: _both,
        onGr3: null,
        onGr4: null,
        codec: BleUtf8Codec(),
      );

  /// Standard software revision string; neither GR app reads it.
  static const GrBleCharacteristic<String> disSoftwareRevision =
      GrBleCharacteristic(
        key: 'dis-software-revision',
        name: 'Software Revision (DIS)',
        uuid: '00002A28-0000-1000-8000-00805F9B34FB',
        service: GrBleServices.deviceInformation,
        properties: _r,
        apps: _both,
        onGr3: null,
        onGr4: null,
        codec: BleUtf8Codec(),
      );

  // Camera Information 9A5ED1C5 (ble.md §Camera Information).

  /// Manufacturer string, read with the other identity strings on connect.
  static const GrBleCharacteristic<String> manufacturerName =
      GrBleCharacteristic(
        key: 'manufacturer-name',
        name: 'Manufacturer Name String',
        uuid: 'F5666A48-6A74-40AE-A817-3C9B3EFB59A6',
        service: GrBleServices.cameraInformation,
        properties: _r,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleUtf8Codec(),
      );

  /// Camera model string; GR WORLD's firmware check depends on it.
  static const GrBleCharacteristic<String> modelName = GrBleCharacteristic(
    key: 'model-name',
    name: 'Model Number String',
    uuid: '35FE6272-6AA5-44D9-88E1-F09427F51A71',
    service: GrBleServices.cameraInformation,
    properties: _r,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BleUtf8Codec(),
    notes:
        'firmware model property, e.g. "RICOH GR IV HDF" (camera-models §4.2)',
  );

  /// Camera serial number.
  static const GrBleCharacteristic<String> serialNumber = GrBleCharacteristic(
    key: 'serial-number',
    name: 'Serial Number String',
    uuid: '0D2FC4D5-5CB3-4CDE-B519-445E599957D8',
    service: GrBleServices.cameraInformation,
    properties: _r,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BleUtf8Codec(),
  );

  /// Firmware version as `major.minor`.
  static const GrBleCharacteristic<String> firmwareRevision =
      GrBleCharacteristic(
        key: 'firmware-revision',
        name: 'Firmware Revision String',
        uuid: 'B4EB8905-7411-40A6-A367-2834C2157EA7',
        service: GrBleServices.cameraInformation,
        properties: _r,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleUtf8Codec(),
      );

  /// The camera's Bluetooth device name.
  static const GrBleCharacteristic<String> bluetoothDeviceName =
      GrBleCharacteristic(
        key: 'bluetooth-device-name',
        name: 'Bluetooth Device Name',
        uuid: '6FE9D605-3122-4FCE-A0AE-FD9BC08FF879',
        service: GrBleServices.cameraInformation,
        properties: _r,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleUtf8Codec(),
      );

  /// The camera's Bluetooth MAC address as a string.
  static const GrBleCharacteristic<String> bluetoothMacAddress =
      GrBleCharacteristic(
        key: 'bluetooth-mac-address',
        name: 'Bluetooth MAC Address String',
        uuid: '97E34DA2-2E1A-405B-B80D-F8F0AA9CC51C',
        service: GrBleServices.cameraInformation,
        properties: _r,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleUtf8Codec(),
        notes: 'string format (separators, case) unknown',
      );

  // Camera Control / Shooting Service 9F00F387.

  /// Aggregate change notification (Image Sync layout): a count, then
  /// entries naming a Shooting Service characteristic by UUID with its new
  /// value.
  static const GrBleCharacteristic<BleAggregateNotification>
  shootingNotification = GrBleCharacteristic(
    key: 'shooting-notification',
    name: 'Shooting Service Notification',
    uuid: '671466A5-5535-412E-AC4F-8B2F06AF2237',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleAggregateNotificationCodec(),
    notes: 'aggregate; embedded UUID byte order unconfirmed',
  );

  /// Same layout as [shootingNotification]; which values it carries is
  /// \[unknown\].
  static const GrBleCharacteristic<BleAggregateNotification>
  highFrequencyShootingNotification = GrBleCharacteristic(
    key: 'high-frequency-shooting-notification',
    name: 'High Frequency Shooting Service Notification',
    uuid: '2AC97991-A78B-4CD4-9AE8-6E030E1D9EDB',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleAggregateNotificationCodec(),
    notes: 'aggregate; embedded UUID byte order unconfirmed',
  );

  /// Shutter speed as an index into [bleShutterSpeedLabels]; 0 means B/T
  /// mode.
  static const GrBleCharacteristic<BleIndexedValue> shutterSpeed =
      GrBleCharacteristic(
        key: 'shutter-speed',
        name: 'Shutter Speed',
        uuid: 'D3CE2AED-10FA-4648-833D-CD74C6F35905',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleIndexedCodec(BleIntFormat.uint8, bleShutterSpeedLabels),
      );

  /// Aperture as an index into [bleApertureLabels]; 0 means AUTO.
  static const GrBleCharacteristic<BleIndexedValue> aperture =
      GrBleCharacteristic(
        key: 'aperture',
        name: 'Aperture',
        uuid: '3911F22D-9771-479D-B2B9-F729D9BAF9DC',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleIndexedCodec(BleIntFormat.sint8, bleApertureLabels),
      );

  /// ISO as the literal value (sint32 LE); 0 means AUTO.
  static const GrBleCharacteristic<BleIndexedValue> iso = GrBleCharacteristic(
    key: 'iso',
    name: 'ISO Sensitivity',
    uuid: '206BD02C-78B2-42C4-820A-CF30E0963909',
    service: GrBleServices.cameraControl,
    properties: _rwn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    // Image Sync masks sint32 writes with 0x00FFFFFF (ble-imagesync.md §4.1).
    codec: BleIndexedCodec(
      BleIntFormat.sint32,
      bleIsoLabels,
      encodeMin: 0,
      encodeMax: 0x00FFFFFF,
    ),
  );

  /// Exposure compensation index: EV × 3 for third steps, ±51…±58 for half
  /// steps (±0.5…±7.5 EV).
  static const GrBleCharacteristic<BleIndexedValue> exposureCompensation =
      GrBleCharacteristic(
        key: 'exposure-compensation',
        name: 'Exposure Compensation',
        uuid: '30BCC8EB-725D-4048-A832-E76AE26A57E9',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleIndexedCodec(
          BleIntFormat.sint8,
          bleExposureCompensationLabels,
        ),
      );

  /// White balance preset.
  static const GrBleCharacteristic<BleEnumValue<BleWhiteBalance>> whiteBalance =
      GrBleCharacteristic(
        key: 'white-balance',
        name: 'White Balance',
        uuid: '2361F4FF-2C7E-4FC5-876B-F9B0EFBC06FD',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleEnumCodec(BleWhiteBalance.values),
      );

  /// Drive mode, including self-timer, bracket, multi-exposure and interval
  /// variants.
  static const GrBleCharacteristic<BleEnumValue<BleDriveMode>> driveMode =
      GrBleCharacteristic(
        key: 'drive-mode',
        name: 'Drive Mode',
        uuid: 'B29E6DE3-1AEC-48C1-9D05-02CEA57CE664',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleEnumCodec(BleDriveMode.values, BleIntFormat.uint8),
      );

  /// Exposure mode (P, Av, Tv, M, …) with the active user mode; Image Sync
  /// adds a program option byte.
  static const GrBleCharacteristic<BleShootingMode>
  shootingMode = GrBleCharacteristic(
    key: 'shooting-mode',
    name: 'Shooting Mode',
    uuid: 'A3C51525-DE3E-4777-A1C2-699E28736FCF',
    service: GrBleServices.cameraControl,
    properties: _rwn,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BleShootingModeCodec(),
    notes:
        'GR WORLD reads 2 bytes, Image Sync declares 3; GR WORLD never writes',
  );

  /// Metering: spot, center-weighted, multi-segment or highlight-weighted.
  static const GrBleCharacteristic<BleEnumValue<BleMeteringMode>> meteringMode =
      GrBleCharacteristic(
        key: 'metering-mode',
        name: 'Metering mode',
        uuid: 'ED58217E-1839-43B2-BCD7-DC48C36AC0DE',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleEnumCodec(BleMeteringMode.values),
      );

  /// Still or movie capture.
  static const GrBleCharacteristic<BleEnumValue<BleCaptureMode>> captureMode =
      GrBleCharacteristic(
        key: 'capture-mode',
        name: 'Capture Mode',
        uuid: '78009238-AC3D-4370-9B6F-C9CE2F4E3CA8',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleEnumCodec(BleCaptureMode.values),
        notes: 'Image Sync writes it; GR WORLD only reads',
      );

  /// Still file type, RAW format, card slot and slot mode (4 bytes).
  static const GrBleCharacteristic<BleFileType> fileType = GrBleCharacteristic(
    key: 'file-type',
    name: 'File Type',
    uuid: '95BFA8CA-4680-424D-B27C-AAC20D86E48B',
    service: GrBleServices.cameraControl,
    properties: _rwn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleFileTypeCodec(),
  );

  /// JPEG size and quality.
  static const GrBleCharacteristic<BleEnumValue<BleJpegSize>> jpegSize =
      GrBleCharacteristic(
        key: 'jpeg-size',
        name: 'JPEG Size',
        uuid: '9838BB04-4ABB-4C12-AE22-626D02E3704B',
        service: GrBleServices.cameraControl,
        properties: _rwn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleEnumCodec(BleJpegSize.values),
      );

  /// Movie resolution and frame rate. GR III/IV record Full HD only; the 4K
  /// values belong to the shared PENTAX enum.
  static const GrBleCharacteristic<BleEnumValue<BleMovieConfiguration>>
  movieConfiguration = GrBleCharacteristic(
    key: 'movie-configuration',
    name: 'Movie Configuration',
    uuid: '404F6626-1294-407F-AB3D-DDC6B805B6BC',
    service: GrBleServices.cameraControl,
    properties: _rwn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleEnumCodec(BleMovieConfiguration.values),
  );

  /// Shutter release: an operation code (start/stop shooting or recording)
  /// and an AF parameter. GR WORLD writes `01 01`.
  static const GrBleCharacteristic<BleOperationRequest> operationRequest =
      GrBleCharacteristic(
        key: 'operation-request',
        name: 'Operation Request (shutter)',
        uuid: '559644B8-E0BC-4011-929B-5CF9199851E7',
        service: GrBleServices.cameraControl,
        properties: _w,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleOperationRequestCodec(),
      );

  /// Selectable [shutterSpeed] values \[inferred\].
  static const GrBleCharacteristic<List<BleIndexedValue>> shutterSpeedList =
      GrBleCharacteristic(
        key: 'shutter-speed-list',
        name: 'Shutter Speed List',
        uuid: 'B355330D-4ADC-4434-A222-7B91404B4788',
        service: GrBleServices.cameraControl,
        properties: _rn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleListCodec(
          BleIndexedCodec(BleIntFormat.uint8, bleShutterSpeedLabels),
          1,
        ),
      );

  /// Selectable [aperture] values \[inferred\].
  static const GrBleCharacteristic<List<BleIndexedValue>> apertureList =
      GrBleCharacteristic(
        key: 'aperture-list',
        name: 'Aperture List',
        uuid: '4866F4A9-2C83-457B-B393-B9535E1447E5',
        service: GrBleServices.cameraControl,
        properties: _rn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleListCodec(
          BleIndexedCodec(BleIntFormat.sint8, bleApertureLabels),
          1,
        ),
      );

  /// Selectable [iso] values \[inferred\].
  static const GrBleCharacteristic<List<BleIndexedValue>> isoList =
      GrBleCharacteristic(
        key: 'iso-list',
        name: 'ISO Sensitivity List',
        uuid: '9C83DF56-FD93-4639-8CA7-857BB7B3CA3D',
        service: GrBleServices.cameraControl,
        properties: _rn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleListCodec(
          BleIndexedCodec(BleIntFormat.sint32, bleIsoLabels),
          4,
        ),
      );

  /// Selectable [exposureCompensation] values \[inferred\].
  static const GrBleCharacteristic<List<BleIndexedValue>>
  exposureCompensationList = GrBleCharacteristic(
    key: 'exposure-compensation-list',
    name: 'Exposure Compensation List',
    uuid: '01879798-28EE-4D97-92C9-FD249C88BBCC',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleListCodec(
      BleIndexedCodec(BleIntFormat.sint8, bleExposureCompensationLabels),
      1,
    ),
  );

  /// Selectable [whiteBalance] values \[inferred\].
  static const GrBleCharacteristic<List<BleEnumValue<BleWhiteBalance>>>
  whiteBalanceList = GrBleCharacteristic(
    key: 'white-balance-list',
    name: 'White Balance List',
    uuid: 'FB673486-2A76-41B8-88F7-F88552FE5745',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleListCodec(BleEnumCodec(BleWhiteBalance.values), 1),
  );

  /// Selectable [driveMode] values \[inferred\].
  static const GrBleCharacteristic<List<BleEnumValue<BleDriveMode>>>
  driveModeList = GrBleCharacteristic(
    key: 'drive-mode-list',
    name: 'Drive Mode List',
    uuid: 'F4B6C78C-7873-43F0-9748-F4406185224D',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    // Elements are declared sint8, unlike the uint8 Drive Mode itself.
    codec: BleListCodec(BleEnumCodec(BleDriveMode.values), 1),
  );

  /// Selectable still file types \[inferred\].
  static const GrBleCharacteristic<List<BleEnumValue<BleStillFileType>>>
  fileTypeList = GrBleCharacteristic(
    key: 'file-type-list',
    name: 'File Type List',
    uuid: 'F3BFB222-C62B-4AAA-BB61-EF6486626CC8',
    service: GrBleServices.cameraControl,
    properties: _r,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleListCodec(BleEnumCodec(BleStillFileType.values), 1),
  );

  /// Focus mode (MF/AF) and AF area setting; not writable.
  static const GrBleCharacteristic<BleFocus> focusMode = GrBleCharacteristic(
    key: 'focus-mode',
    name: 'Focus Mode',
    uuid: '89458F80-50A1-42C1-B031-1BC6082179C0',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleFocusCodec(),
  );

  /// Whether AF is running and whether it has achieved focus.
  static const GrBleCharacteristic<BleAfStatus> afStatus = GrBleCharacteristic(
    key: 'af-status',
    name: 'Auto Focus Status',
    uuid: 'CDFC734E-EA21-427D-A69F-C1A0F7F1E9A3',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleAfStatusCodec(),
  );

  /// Whether the camera is shooting and whether a self-timer or scheduled
  /// countdown runs; Image Sync adds drive-mode and astro states.
  static const GrBleCharacteristic<BleCaptureStatus> captureStatus =
      GrBleCharacteristic(
        key: 'capture-status',
        name: 'Capture Status',
        uuid: 'B5589C08-B5FD-46F5-BE7D-AB1B8C074CAA',
        service: GrBleServices.cameraControl,
        properties: _rn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleCaptureStatusCodec(),
        notes: 'GR WORLD reads 2 bytes, Image Sync declares 8',
      );

  /// Current and total shot counts, one signed byte each.
  static const GrBleCharacteristic<BleShotCount> shotCount =
      GrBleCharacteristic(
        key: 'shot-count',
        name: 'Shot Count',
        uuid: '12D262BA-D8BF-44B0-8E85-C414A40230A9',
        service: GrBleServices.cameraControl,
        properties: _rn,
        apps: _is,
        onGr3: true,
        onGr4: true,
        codec: BleShotCountCodec(),
      );

  /// Cancels a running self-timer countdown when written.
  static const GrBleCharacteristic<BleSelfTimerCommand> selfTimer =
      GrBleCharacteristic(
        key: 'self-timer',
        name: 'Self Timer (countdown cancel)',
        uuid: '009A8E70-B306-4451-B943-7F54392EB971',
        service: GrBleServices.cameraControl,
        properties: _w,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleSelfTimerCodec(),
        notes: 'GR WORLD writes 1 byte 01, Image Sync 2 bytes 01 01',
      );

  /// Selectable exposure modes \[inferred\].
  static const GrBleCharacteristic<List<BleEnumValue<BleExposureMode>>>
  shootingModeList = GrBleCharacteristic(
    key: 'shooting-mode-list',
    name: 'Shooting Mode List',
    uuid: 'F662DCD8-AC6E-4E02-A4B2-CE92CD44C7C3',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleListCodec(BleEnumCodec(BleExposureMode.values), 1),
  );

  /// Selectable AF area settings \[inferred\].
  static const GrBleCharacteristic<List<BleEnumValue<BleFocusSetting>>>
  focusSettingList = GrBleCharacteristic(
    key: 'focus-setting-list',
    name: 'Focus Setting List',
    uuid: '31B28DAB-BD3C-4C27-AA08-F379BF737C1E',
    service: GrBleServices.cameraControl,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleListCodec(BleEnumCodec(BleFocusSetting.values), 1),
  );

  /// Name of Image Control custom slot 1 \[inferred\].
  static const GrBleCharacteristic<String> imageControl1Name =
      GrBleCharacteristic(
        key: 'image-control-1-name',
        name: 'Image Control Custom 1 name',
        uuid: '30ADB439-1BC0-4B8E-9C8B-2BD1892AD6B0',
        service: GrBleServices.cameraControl,
        properties: _rw,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        codec: BleUtf8Codec(),
        notes: '"name" meaning inferred',
      );

  /// Name of Image Control custom slot 2 \[inferred\].
  static const GrBleCharacteristic<String> imageControl2Name =
      GrBleCharacteristic(
        key: 'image-control-2-name',
        name: 'Image Control Custom 2 name',
        uuid: 'E799198F-CF3F-4650-9373-B15DDA1B618C',
        service: GrBleServices.cameraControl,
        properties: _rw,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        codec: BleUtf8Codec(),
        notes: '"name" meaning inferred',
      );

  /// Name of Image Control custom slot 3 \[inferred\].
  static const GrBleCharacteristic<String> imageControl3Name =
      GrBleCharacteristic(
        key: 'image-control-3-name',
        name: 'Image Control Custom 3 name',
        uuid: 'DF77DD09-0A48-44AA-9664-2116D03B6FD7',
        service: GrBleServices.cameraControl,
        properties: _rw,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        codec: BleUtf8Codec(),
        notes: '"name" meaning inferred',
      );

  /// Settings blob of Image Control custom slot 1.
  static const GrBleCharacteristic<BleImageControlBlob> imageControl1Data =
      GrBleCharacteristic(
        key: 'image-control-1-data',
        name: 'Image Control Custom 1 data',
        uuid: '3E0673E0-1C7B-4F97-8CA6-5C2C8BC56680',
        service: GrBleServices.cameraControl,
        properties: _rw,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        codec: BleImageControlCodec(),
      );

  /// Settings blob of Image Control custom slot 2.
  static const GrBleCharacteristic<BleImageControlBlob> imageControl2Data =
      GrBleCharacteristic(
        key: 'image-control-2-data',
        name: 'Image Control Custom 2 data',
        uuid: '0936B04C-7269-4CEF-9F34-07217D40CC55',
        service: GrBleServices.cameraControl,
        properties: _rw,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        codec: BleImageControlCodec(),
      );

  /// Settings blob of Image Control custom slot 3.
  static const GrBleCharacteristic<BleImageControlBlob> imageControl3Data =
      GrBleCharacteristic(
        key: 'image-control-3-data',
        name: 'Image Control Custom 3 data',
        uuid: 'CD879E7A-AB9F-4C58-90ED-689BAE67EF8E',
        service: GrBleServices.cameraControl,
        properties: _rw,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        codec: BleImageControlCodec(),
      );

  // Camera State / Camera Service 4B445988.

  /// Aggregate change notification for Camera Service values; same layout
  /// as [shootingNotification].
  static const GrBleCharacteristic<BleAggregateNotification>
  cameraServiceNotification = GrBleCharacteristic(
    key: 'camera-service-notification',
    name: 'Camera Service Notification',
    uuid: 'FAA0AEAF-1654-4842-A139-F4E1C1E722AC',
    service: GrBleServices.cameraState,
    properties: _rn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    codec: BleAggregateNotificationCodec(),
    notes: 'aggregate; embedded UUID byte order unconfirmed',
  );

  /// Power state: 0 off, 1 on, 2 sleep (Image Sync). Writing `00` powers
  /// the camera off.
  static const GrBleCharacteristic<BleEnumValue<BleCameraPower>> cameraPower =
      GrBleCharacteristic(
        key: 'camera-power',
        name: 'Camera Power',
        uuid: 'B58CE84C-0666-4DE9-BEC8-2D27B27B3211',
        service: GrBleServices.cameraState,
        properties: _rwn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        guarded: true,
        codec: BleEnumCodec(BleCameraPower.values),
        notes: 'both apps only ever write 00 (power off)',
      );

  /// Battery level byte, then a power-source byte (Image Sync) or long-form
  /// flag (GR WORLD).
  static const GrBleCharacteristic<BleBatteryLevel> batteryLevel =
      GrBleCharacteristic(
        key: 'battery',
        name: 'Battery Level',
        uuid: '875FC41D-4980-434C-A653-FD4A4D4410C4',
        service: GrBleServices.cameraState,
        properties: _rn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleBatteryLevelCodec(),
        notes: 'byte1: power source (Image Sync) or long-form flag (GR WORLD)',
      );

  /// Camera clock in local time: year uint16 LE, month, day, hour, minute,
  /// second.
  static const GrBleCharacteristic<BleDateTime> dateTime = GrBleCharacteristic(
    key: 'date-time',
    name: 'Date Time',
    uuid: 'FA46BBDD-8A8F-4796-8CF3-AA58949B130A',
    service: GrBleServices.cameraState,
    properties: _rw,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BleDateTimeCodec(),
  );

  /// Operation modes the camera offers (Image Sync); GR WORLD reads only
  /// byte 0.
  static const GrBleCharacteristic<List<BleEnumValue<BleOperationMode>>>
  operationModeList = GrBleCharacteristic(
    key: 'operation-mode-list',
    name: 'Operation Mode List',
    uuid: '430B80A3-CC2E-4EC2-AACD-08610281FF38',
    service: GrBleServices.cameraState,
    properties: _rn,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BleListCodec(BleEnumCodec(BleOperationMode.values), 1),
    notes: 'list per Image Sync; GR WORLD reads only byte0',
  );

  /// Capture, playback, BLE startup, other or power-off transfer. A camera
  /// woken over BLE reads BLE startup until a client writes capture or
  /// playback (GR WORLD power-on, ble.md).
  static const GrBleCharacteristic<BleEnumValue<BleOperationMode>>
  operationMode = GrBleCharacteristic(
    key: 'operation-mode',
    name: 'Operation Mode',
    uuid: '1452335A-EC7F-4877-B8AB-0F72E18BB295',
    service: GrBleServices.cameraState,
    properties: _rwn,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BleEnumCodec(BleOperationMode.values),
    notes: 'GR WORLD writes playback or capture to wake a camera (bleStartup)',
  );

  /// Whether geotagging is enabled.
  static const GrBleCharacteristic<bool> geoTag = GrBleCharacteristic(
    key: 'geotag',
    name: 'GEO Tag',
    uuid: 'A36AFDCF-6B67-4046-9BE7-28FB67DBC071',
    service: GrBleServices.cameraState,
    properties: _rwn,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BleBoolCodec(),
  );

  /// Per card slot: presence, lock, format and remaining shots and movie
  /// seconds.
  static const GrBleCharacteristic<BleStorageInformation> storageInformation =
      GrBleCharacteristic(
        key: 'storage',
        name: 'Storage Information',
        uuid: 'A0C10148-8865-4470-9631-8F36D79A41A5',
        service: GrBleServices.cameraState,
        properties: _rn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleStorageInformationCodec(),
        notes: '14-byte (GR WORLD, GR III) or 15-byte (Image Sync) entries',
      );

  /// Whether the camera's transfer list is non-empty and whether it changed.
  static const GrBleCharacteristic<BleFileTransferList> fileTransferList =
      GrBleCharacteristic(
        key: 'file-transfer-list',
        name: 'File Transfer List',
        uuid: 'D9AE1C06-447D-4DEA-8B7D-FC8B19C2CDAE',
        service: GrBleServices.cameraState,
        properties: _rn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleFileTransferListCodec(),
      );

  /// Whether power-off aborts or waits for a pending transfer, and whether
  /// transferred images are resized.
  static const GrBleCharacteristic<BlePowerOffDuringTransfer>
  powerOffDuringTransfer = GrBleCharacteristic(
    key: 'power-off-during-transfer',
    name: 'Power Off During File Transfer',
    uuid: 'BD6725FC-5D16-496A-A48A-F784594C8ECB',
    service: GrBleServices.cameraState,
    properties: _rwn,
    apps: _both,
    onGr3: true,
    onGr4: true,
    codec: BlePowerOffDuringTransferCodec(),
  );

  /// Graduated ND filter setting; Image Sync lists it, GR firmware lacks it.
  static const GrBleCharacteristic<BleEnumValue<BleGradNd>> gradNd =
      GrBleCharacteristic(
        key: 'grad-nd',
        name: 'Grad ND',
        uuid: '209F9869-8540-460E-97A6-5C3AC08F2C73',
        service: GrBleServices.cameraState,
        properties: _rn,
        apps: _is,
        onGr3: false,
        onGr4: false,
        codec: BleEnumCodec(BleGradNd.values),
        notes: 'PENTAX K-3 III characteristic; absent from both GR bled builds',
      );

  /// User-set camera name (GR WORLD's default is "MY GR IV").
  static const GrBleCharacteristic<String> cameraName = GrBleCharacteristic(
    key: 'camera-name',
    name: 'Camera Name',
    uuid: 'EF437870-180A-44AE-AFFD-99DBD85ADE43',
    service: GrBleServices.cameraState,
    properties: _rw,
    apps: _gw,
    onGr3: false,
    onGr4: true,
    codec: BleUtf8Codec(),
  );

  /// Presumably tells the camera a firmware update exists \[inferred\]; no
  /// writer is known.
  static const GrBleCharacteristic<bool> firmwareUpdateAvailable =
      GrBleCharacteristic(
        key: 'firmware-update-available',
        name: 'Firmware Update Available',
        uuid: 'E450ED9B-DD61-43F2-BDFB-6AF500C910C3',
        service: GrBleServices.cameraState,
        properties: _w,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        guarded: true,
        codec: BleBoolCodec(),
        notes: 'name inferred from getter order; no GR WORLD caller found',
      );

  /// Starts the firmware update \[inferred\]; GR WORLD writes `01` after
  /// uploading the firmware.
  static const GrBleCharacteristic<bool> firmwareUpdateStart =
      GrBleCharacteristic(
        key: 'firmware-update-start',
        name: 'Firmware Update Start',
        uuid: '5F0A7BA9-AE46-4645-ABAC-58AB2A1F4FE4',
        service: GrBleServices.cameraState,
        properties: _w,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        guarded: true,
        codec: BleBoolCodec(),
        notes: 'name inferred; GR WORLD writes 01 after uploading firmware',
      );

  /// Firmware update outcome: 0 invalid, 1 success, 2 failure.
  static const GrBleCharacteristic<BleEnumValue<BleFirmwareUpdateResult>>
  firmwareUpdateResult = GrBleCharacteristic(
    key: 'firmware-update-result',
    name: 'Firmware Update Result',
    uuid: '39879AAC-0AF6-44B5-AFBB-CA50053FA575',
    service: GrBleServices.cameraState,
    properties: _rn,
    apps: _gw,
    onGr3: false,
    onGr4: true,
    guarded: true,
    codec: BleEnumCodec(BleFirmwareUpdateResult.values),
  );

  /// Raw bytes GR WORLD reads for its end screen; layout \[unknown\].
  static const GrBleCharacteristic<Uint8List> endScreenData =
      GrBleCharacteristic(
        key: 'end-screen-data',
        name: 'End-screen data',
        uuid: 'F759F4DD-5FAF-4CAC-82F4-5A3FE11737E7',
        service: GrBleServices.cameraState,
        properties: _r,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        codec: BleBytesCodec(),
        notes: 'layout unknown',
      );

  // WLAN Control F37F568F.

  /// Camera Wi-Fi AP switch: write `01` for on, `00` for off. The AP
  /// appears about 16 s after on (observed on GR IV HDF fw 1.20).
  static const GrBleCharacteristic<BleEnumValue<BleNetworkType>> networkType =
      GrBleCharacteristic(
        key: 'wlan',
        name: 'Network Type (WLAN on/off)',
        uuid: '9111CDD0-9F01-45C4-A2D4-E09E8FB0424D',
        service: GrBleServices.wlanControl,
        properties: _rwn,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleEnumCodec(BleNetworkType.values),
      );

  /// SSID of the camera's Wi-Fi AP.
  static const GrBleCharacteristic<String> ssid = GrBleCharacteristic(
    key: 'ssid',
    name: 'SSID',
    uuid: '90638E5A-E77D-409D-B550-78F7E1CA5AB4',
    service: GrBleServices.wlanControl,
    properties: _rw,
    apps: _both,
    onGr3: true,
    onGr4: true,
    guarded: true,
    codec: BleUtf8Codec(),
  );

  /// Passphrase of the camera's Wi-Fi AP.
  static const GrBleCharacteristic<String> passphrase = GrBleCharacteristic(
    key: 'passphrase',
    name: 'Passphrase',
    uuid: '0F38279C-FE9E-461B-8596-81287E8C9A81',
    service: GrBleServices.wlanControl,
    properties: _rw,
    apps: _both,
    onGr3: true,
    onGr4: true,
    guarded: true,
    codec: BleUtf8Codec(),
  );

  /// Wi-Fi AP channel: 0 auto, 1–11 fixed.
  static const GrBleCharacteristic<BleEnumValue<BleWlanChannel>> wlanChannel =
      GrBleCharacteristic(
        key: 'wlan-channel',
        name: 'Channel',
        uuid: '51DE6EBC-0F22-4357-87E4-B1FA1D385AB8',
        service: GrBleServices.wlanControl,
        properties: _rw,
        apps: _is,
        onGr3: true,
        onGr4: false,
        guarded: true,
        codec: BleEnumCodec(BleWlanChannel.values),
        notes: 'GR III only; GR IV has wlan-frequency instead',
      );

  /// Wi-Fi AP band: `00` 2.4 GHz, `01` 5 GHz.
  static const GrBleCharacteristic<BleEnumValue<BleWlanFrequency>>
  wlanFrequency = GrBleCharacteristic(
    key: 'wlan-frequency',
    name: 'wlanFreq',
    uuid: 'C4B7DFC0-80FD-4223-B132-B7D25A59CF85',
    service: GrBleServices.wlanControl,
    properties: _rw,
    apps: _gw,
    onGr3: false,
    onGr4: true,
    guarded: true,
    codec: BleEnumCodec(BleWlanFrequency.values),
  );

  /// Wi-Fi AP security: WPA2, WPA3 or WPA2/WPA3 transition.
  static const GrBleCharacteristic<BleEnumValue<BleWlanSecurity>> wlanSecurity =
      GrBleCharacteristic(
        key: 'wlan-security',
        name: 'security',
        uuid: '63BC8463-228F-4698-B30D-FAF8E3D7BD88',
        service: GrBleServices.wlanControl,
        properties: _rw,
        apps: _gw,
        onGr3: false,
        onGr4: true,
        guarded: true,
        codec: BleEnumCodec(BleWlanSecurity.values),
      );

  /// Whether the AP can use 5 GHz \[inferred\].
  static const GrBleCharacteristic<bool> available5GHz = GrBleCharacteristic(
    key: 'available-5ghz',
    name: 'available5GHz',
    uuid: '460828AC-94EB-4EDF-9BB0-D31E75F2B165',
    service: GrBleServices.wlanControl,
    properties: _r,
    apps: _gw,
    onGr3: false,
    onGr4: true,
    codec: BleBoolCodec(),
  );

  // GPS 84A0DD62.

  /// Phone location for geotagging: latitude, longitude and altitude
  /// (float64 BE), fix time and datum; 32 bytes. GR WORLD writes it every
  /// 5, 30 or 180 s.
  static const GrBleCharacteristic<BleGpsInformation> gpsInformation =
      GrBleCharacteristic(
        key: 'gps',
        name: 'GPS Information',
        uuid: '28F59D60-8B8E-4FCD-A81F-61BDB46595A9',
        service: GrBleServices.gps,
        properties: _rw,
        apps: _both,
        onGr3: true,
        onGr4: true,
        codec: BleGpsInformationCodec(),
        notes: 'fix time UTC in Image Sync; GR WORLD basis unknown',
      );

  // Client Registration / Bluetooth Control Command 0F291746.

  /// When the camera keeps BLE on: never, always, or only while powered on.
  static const GrBleCharacteristic<BleEnumValue<BleEnableCondition>>
  bleEnableCondition = GrBleCharacteristic(
    key: 'ble-enable-condition',
    name: 'BLE Enable Condition',
    uuid: 'D8676C92-DC4E-4D9E-ACCE-B9E251DDCC0C',
    service: GrBleServices.clientRegistration,
    properties: _rwn,
    apps: _is,
    onGr3: true,
    onGr4: true,
    guarded: true,
    codec: BleEnumCodec(BleEnableCondition.values),
    notes: 'wake from off presumably needs enableAnytime',
  );

  /// Phone name shown by the camera; rejected before bonding (observed on
  /// GR IV HDF).
  static const GrBleCharacteristic<String> pairedDeviceName =
      GrBleCharacteristic(
        key: 'paired-device-name',
        name: 'Paired Device Name',
        uuid: 'FE3A32F8-A189-42DE-A391-BC81AE4DAA76',
        service: GrBleServices.clientRegistration,
        properties: _w,
        apps: _both,
        onGr3: true,
        onGr4: true,
        guarded: true,
        codec: BleUtf8Codec(),
      );

  /// Every characteristic, grouped by service.
  static const List<GrBleCharacteristic<Object>> all = [
    disManufacturerName,
    disModelNumber,
    disSerialNumber,
    disFirmwareRevision,
    disSoftwareRevision,
    manufacturerName,
    modelName,
    serialNumber,
    firmwareRevision,
    bluetoothDeviceName,
    bluetoothMacAddress,
    shootingNotification,
    highFrequencyShootingNotification,
    shutterSpeed,
    aperture,
    iso,
    exposureCompensation,
    whiteBalance,
    driveMode,
    shootingMode,
    meteringMode,
    captureMode,
    fileType,
    jpegSize,
    movieConfiguration,
    operationRequest,
    shutterSpeedList,
    apertureList,
    isoList,
    exposureCompensationList,
    whiteBalanceList,
    driveModeList,
    fileTypeList,
    focusMode,
    afStatus,
    captureStatus,
    shotCount,
    selfTimer,
    shootingModeList,
    focusSettingList,
    imageControl1Name,
    imageControl2Name,
    imageControl3Name,
    imageControl1Data,
    imageControl2Data,
    imageControl3Data,
    cameraServiceNotification,
    cameraPower,
    batteryLevel,
    dateTime,
    operationModeList,
    operationMode,
    geoTag,
    storageInformation,
    fileTransferList,
    powerOffDuringTransfer,
    gradNd,
    cameraName,
    firmwareUpdateAvailable,
    firmwareUpdateStart,
    firmwareUpdateResult,
    endScreenData,
    networkType,
    ssid,
    passphrase,
    wlanChannel,
    wlanFrequency,
    wlanSecurity,
    available5GHz,
    gpsInformation,
    bleEnableCondition,
    pairedDeviceName,
  ];

  /// Camera Information characteristics in GR WORLD's read-all order.
  static const List<GrBleCharacteristic<String>> identity = [
    manufacturerName,
    modelName,
    serialNumber,
    firmwareRevision,
    bluetoothDeviceName,
    bluetoothMacAddress,
  ];

  /// Image Control custom slots 1–3: (name, data).
  static const List<
    ({
      GrBleCharacteristic<BleImageControlBlob> data,
      GrBleCharacteristic<String> name,
    })
  >
  imageControlSlots = [
    (name: imageControl1Name, data: imageControl1Data),
    (name: imageControl2Name, data: imageControl2Data),
    (name: imageControl3Name, data: imageControl3Data),
  ];

  static final Map<String, GrBleCharacteristic<Object>> _byUuid = {
    for (final c in all) c.uuid: c,
  };
  static final Map<String, GrBleCharacteristic<Object>> _byKey = {
    for (final c in all) c.key: c,
  };

  /// Lookup by UUID in any accepted form; null when unknown or malformed.
  static GrBleCharacteristic<Object>? byUuid(String uuid) {
    try {
      return _byUuid[canonicalUuid(uuid)];
    } on FormatException {
      return null;
    }
  }

  /// Lookup by CLI key, case-insensitively; null when unknown.
  static GrBleCharacteristic<Object>? byKey(String key) =>
      _byKey[key.toLowerCase()];

  /// Lookup by CLI key or UUID.
  static GrBleCharacteristic<Object>? lookup(String keyOrUuid) =>
      byKey(keyOrUuid) ?? byUuid(keyOrUuid);
}
