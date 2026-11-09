import 'dart:async';
import 'dart:typed_data';

import 'package:gr_protocol/src/ble/bytes.dart';
import 'package:gr_protocol/src/ble/catalog.dart';
import 'package:gr_protocol/src/ble/codecs.dart';
import 'package:gr_protocol/src/ble/enums.dart';
import 'package:gr_protocol/src/ble/model.dart';
import 'package:gr_protocol/src/ble/records.dart';
import 'package:gr_protocol/src/ble/tables.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:gr_protocol/src/trace.dart';
import 'package:gr_protocol/src/wifi/network_control.dart';

/// Discovered GATT database compared with [GrBleCatalog].
final class GrBleDiscoveryReport {
  new _({
    required this.services,
    required this.present,
    required this.missing,
    required this.extraServices,
    required this.extraCharacteristics,
    required this.declared,
  });

  /// Matches discovered (service, characteristic) pairs to the catalog.
  factory compare(List<BleServiceInfo> services) {
    final declared = <String, Set<BleCharacteristicProperty>>{};
    final extraServices = <String>[];
    final extra =
        <
          ({
            String service,
            String uuid,
            Set<BleCharacteristicProperty> properties,
          })
        >[];
    for (final s in services) {
      final service = GrBleServices.byUuid(s.uuid);
      if (service == null) extraServices.add(s.uuid);
      for (final c in s.characteristics) {
        final known = GrBleCatalog.byUuid(c.uuid);
        if (known != null && known.service.uuid == canonicalUuid(s.uuid)) {
          declared[known.key] = c.properties;
        } else {
          extra.add((
            service: canonicalUuid(s.uuid),
            uuid: canonicalUuid(c.uuid),
            properties: c.properties,
          ));
        }
      }
    }
    return GrBleDiscoveryReport._(
      services: List.unmodifiable(services),
      present: [
        for (final c in GrBleCatalog.all)
          if (declared.containsKey(c.key)) c,
      ],
      missing: [
        for (final c in GrBleCatalog.all)
          if (!declared.containsKey(c.key)) c,
      ],
      extraServices: List.unmodifiable(extraServices),
      extraCharacteristics: List.unmodifiable(extra),
      declared: Map.unmodifiable(declared),
    );
  }

  /// Every discovered service, as the platform reported it.
  final List<BleServiceInfo> services;

  /// Catalog characteristics found under their catalog service.
  final List<GrBleCharacteristic<Object>> present;

  /// Catalog characteristics this camera does not expose (normal for the
  /// other model family's characteristics).
  final List<GrBleCharacteristic<Object>> missing;

  /// Discovered services that are not in the catalog.
  final List<String> extraServices;

  /// Discovered characteristics not in the catalog (or under a different
  /// service than the catalog says).
  final List<
    ({String service, String uuid, Set<BleCharacteristicProperty> properties})
  >
  extraCharacteristics;

  /// Properties the camera declared, by catalog key.
  final Map<String, Set<BleCharacteristicProperty>> declared;

  /// Whether [c] was discovered under its catalog service.
  bool isPresent(GrBleCharacteristic<Object> c) => declared.containsKey(c.key);

  /// Diagnostic JSON: present characteristics with declared versus catalog
  /// properties, missing ones, and everything not in the catalog.
  Map<String, Object?> toJson() => {
    'services': [for (final s in services) s.uuid],
    'present': [
      for (final c in present)
        {
          'key': c.key,
          'uuid': c.uuid,
          'declared': [for (final p in declared[c.key]!) p.name],
          'catalog': [for (final p in c.properties) p.name],
          if (!_sameProperties(declared[c.key]!, c.properties))
            'propertiesDiffer': true,
        },
    ],
    'missing': [
      for (final c in missing)
        {
          'key': c.key,
          'uuid': c.uuid,
          'service': c.service.key,
          'firmware': {'gr3': c.onGr3, 'gr4': c.onGr4},
        },
    ],
    'extraServices': extraServices,
    'extraCharacteristics': [
      for (final e in extraCharacteristics)
        {
          'service': e.service,
          'uuid': e.uuid,
          'properties': [for (final p in e.properties) p.name],
        },
    ],
  };

  static bool _sameProperties(
    Set<BleCharacteristicProperty> a,
    Set<BleCharacteristicProperty> b,
  ) => a.length == b.length && a.containsAll(b);
}

/// Camera Information service values (ble.md §Camera Information), read
/// on every connect by GR WORLD. Missing or unreadable fields are null with
/// the reason in [issues].
final class GrBleIdentity {
  /// Creates an identity; [GrBleClient.readIdentity] fills it from the
  /// camera.
  const new({
    this.manufacturer,
    this.modelName,
    this.serialNumber,
    this.firmwareRevision,
    this.bluetoothDeviceName,
    this.bluetoothMacAddress,
    this.issues = const {},
  });

  /// Manufacturer name string as the camera reports it.
  final String? manufacturer;

  /// Firmware model property, e.g. `RICOH GR IV`; see [model].
  final String? modelName;

  /// Camera serial number string; matches the advertised tag `02` digits.
  final String? serialNumber;

  /// Firmware version string as the camera reports it.
  final String? firmwareRevision;

  /// Camera's Bluetooth device name.
  final String? bluetoothDeviceName;

  /// Camera's Bluetooth MAC address string; the exact format (separators,
  /// case) is not established (ble.md open question 14).
  final String? bluetoothMacAddress;

  /// Problems by characteristic key.
  final Map<String, List<String>> issues;

  /// Known GR body for [modelName], or null when absent or not an exact
  /// match.
  GrModel? get model {
    final m = modelName;
    return m == null ? null : GrModel.fromModelString(m);
  }

  /// Diagnostic JSON with every field plus the resolved model and family.
  Map<String, Object?> toJson() => {
    'manufacturer': manufacturer,
    'modelName': modelName,
    'model': model?.name,
    'family': model?.family.name,
    'serialNumber': serialNumber,
    'firmwareRevision': firmwareRevision,
    'bluetoothDeviceName': bluetoothDeviceName,
    'bluetoothMacAddress': bluetoothMacAddress,
    if (issues.isNotEmpty) 'issues': issues,
  };
}

/// Camera AP credentials read over BLE (ble.md §Minimal client sequence).
final class GrWifiCredentials {
  /// Creates credentials; [GrBleClient.readWifiCredentials] fills them from
  /// the camera.
  const new({
    required this.ssid,
    required this.passphrase,
    required this.security,
    required this.wifiSecurity,
    required this.securityAssumed,
    this.frequency,
    this.channel,
    this.available5GHz,
    this.networkType,
    this.issues = const [],
  });

  /// Camera AP network name; empty when it could not be decoded.
  final String ssid;

  /// Camera AP passphrase in clear text; empty when it could not be
  /// decoded.
  final String passphrase;

  /// Raw security characteristic; null when the camera lacks it (GR III).
  final BleEnumValue<BleWlanSecurity>? security;

  /// Security to join with. When the characteristic is absent this is WPA2,
  /// GR WORLD's read-all default, and [securityAssumed] is true. Null when
  /// the camera reports an undocumented security value.
  final WifiSecurity? wifiSecurity;

  /// True when [wifiSecurity] is GR WORLD's WPA2 default because the camera
  /// has no security characteristic.
  final bool securityAssumed;

  /// GR IV wlanFreq; null when absent.
  final BleEnumValue<BleWlanFrequency>? frequency;

  /// GR III WLAN Channel; null when absent.
  final BleEnumValue<BleWlanChannel>? channel;

  /// GR IV available5GHz flag; null when absent or unreadable.
  final bool? available5GHz;

  /// Current WLAN on/off state as read, when readable.
  final BleEnumValue<BleNetworkType>? networkType;

  /// Read and decode problems of the individual characteristics.
  final List<String> issues;

  /// Diagnostic JSON with every field, including the passphrase.
  Map<String, Object?> toJson() => {
    'ssid': ssid,
    'passphrase': passphrase,
    'security': security?.toJson(),
    'wifiSecurity': wifiSecurity?.name,
    'securityAssumed': securityAssumed,
    'frequency': frequency?.toJson(),
    'channel': channel?.toJson(),
    'available5GHz': available5GHz,
    'networkType': networkType?.toJson(),
    if (issues.isNotEmpty) 'issues': issues,
  };
}

/// One notification (or priming read) from [GrBleClient.watch].
final class GrBleNotification<T extends Object> {
  /// Wraps one decoded value, stamped with the local receive time.
  new(this.characteristic, this.decoded, {this.primed = false})
    : receivedAt = DateTime.now();

  /// Characteristic the value came from.
  final GrBleCharacteristic<T> characteristic;

  /// The value with its raw bytes and decode issues.
  final BleDecoded<T> decoded;

  /// Local time the value arrived.
  final DateTime receivedAt;

  /// True for the read GR WORLD performs right after subscribing.
  final bool primed;

  /// Diagnostic JSON: UTC time, characteristic key and the decoded value.
  Map<String, Object?> toJson() => {
    'time': receivedAt.toUtc().toIso8601String(),
    'characteristic': characteristic.key,
    if (primed) 'primed': true,
    ...decoded.toJson(),
  };
}

/// Which notifications to enable (ble-imagesync.md §4.3).
enum GrBleSubscriptionSet {
  /// GR WORLD: ten characteristics directly, each primed with a read
  /// (ble.md §Notification subscriptions).
  grWorld,

  /// Image Sync: three aggregators, Network Type, BLE Enable Condition and
  /// ISO Sensitivity List; no priming read.
  imageSync;

  /// [firmwareUpdateResult] adds GR WORLD's conditional first subscription.
  List<GrBleCharacteristic<Object>> characteristics({
    bool firmwareUpdateResult = false,
  }) => switch (this) {
    GrBleSubscriptionSet.grWorld => [
      if (firmwareUpdateResult) GrBleCatalog.firmwareUpdateResult,
      GrBleCatalog.cameraPower,
      GrBleCatalog.batteryLevel,
      GrBleCatalog.geoTag,
      GrBleCatalog.storageInformation,
      GrBleCatalog.fileTransferList,
      GrBleCatalog.powerOffDuringTransfer,
      GrBleCatalog.captureMode,
      GrBleCatalog.captureStatus,
      GrBleCatalog.driveMode,
      GrBleCatalog.shootingMode,
    ],
    GrBleSubscriptionSet.imageSync => [
      GrBleCatalog.shootingNotification,
      GrBleCatalog.highFrequencyShootingNotification,
      GrBleCatalog.cameraServiceNotification,
      GrBleCatalog.networkType,
      GrBleCatalog.bleEnableCondition,
      GrBleCatalog.isoList,
    ],
  };

  /// Whether each subscription is followed by one read (GR WORLD).
  bool get primesWithRead => this == GrBleSubscriptionSet.grWorld;
}

/// Typed access to a connected camera.
///
/// GATT operations are serialized, one in flight per connection, as both
/// apps do (GR WORLD per-service mutex, Image Sync single executor). Every
/// read, write, notification and decode is reported to [trace].
final class GrBleClient {
  /// Wraps [connection]; call [discover] before typed access so absent
  /// characteristics fail fast.
  new(
    this.connection, {
    this.trace,
    this.operationTimeout = const Duration(seconds: 10),
  });

  /// Link to the camera that every operation goes through.
  final BleConnection connection;

  /// Receives one event per GATT operation, notification and decode.
  final TraceSink? trace;

  /// Per read/write deadline reported to the caller. Image Sync uses 5 s;
  /// GR WORLD sets none. A timed-out request still occupies the queue until
  /// the platform settles it, so later operations never overlap it.
  final Duration operationTimeout;

  GrBleDiscoveryReport? _discovery;
  Future<void> _tail = Future<void>.value();
  DateTime? _lastPowerOff;
  bool? _lastPowerOn;

  /// Result of the last [discover], if any.
  GrBleDiscoveryReport? get discovery => _discovery;

  /// When this client last saw the camera power off: a camera-power
  /// notification going from on to off (what GR WORLD records), or a
  /// successful [powerOff] write. Feed it to `waitAfterPowerOff`.
  DateTime? get lastPowerOff => _lastPowerOff;

  // -- plumbing --------------------------------------------------------------

  void _emit(
    TraceDirection direction,
    String kind,
    Map<String, Object?> fields, [
    Uint8List? bytes,
  ]) {
    trace?.call(
      TraceEvent(
        channel: TraceChannel.ble,
        direction: direction,
        kind: kind,
        fields: {'deviceId': connection.deviceId, ...fields},
        bytes: bytes,
      ),
    );
  }

  /// Runs [op] once every earlier operation has settled. With [timeout]
  /// (an operation description), the caller gets a [BleErrorCode.timeout]
  /// error after [operationTimeout], but the queue stays held until [op]
  /// itself settles: `Future.timeout` cannot cancel the platform request,
  /// and releasing the slot early would put two GATT requests in flight.
  Future<T> _serialized<T>(Future<T> Function() op, {String? timeout}) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return previous.then((_) {
      final underlying = Future.sync(op);
      unawaited(
        underlying
            .then<void>((_) {}, onError: (Object _, StackTrace _) {})
            .whenComplete(released.complete),
      );
      if (timeout == null) return underlying;
      return underlying.timeout(
        operationTimeout,
        onTimeout: () {
          _emit(TraceDirection.internal, 'gatt.timeout', {
            'operation': timeout,
            'timeoutMs': operationTimeout.inMilliseconds,
            'queueHeldUntilSettled': true,
          });
          throw BleException(
            BleErrorCode.timeout,
            '$timeout timed out after ${operationTimeout.inMilliseconds} ms',
          );
        },
      );
    });
  }

  static String? _keyOf(String characteristicUuid) =>
      GrBleCatalog.byUuid(characteristicUuid)?.key;

  void _requirePresent(GrBleCharacteristic<Object> c) {
    final d = _discovery;
    if (d != null && !d.isPresent(c)) {
      throw BleException(
        BleErrorCode.notFound,
        '${c.key} (${c.uuid}) was not discovered on this camera',
      );
    }
  }

  // -- discovery --------------------------------------------------------------

  /// Discovers the GATT database and compares it with the catalog. Later
  /// typed calls on characteristics it did not find throw
  /// [BleErrorCode.notFound].
  Future<GrBleDiscoveryReport> discover() async {
    final services = await _serialized(() async {
      _emit(TraceDirection.outbound, 'gatt.discover', {});
      try {
        return await connection.discover();
      } catch (e) {
        _emit(TraceDirection.internal, 'gatt.discover.error', {'error': '$e'});
        rethrow;
      }
    });
    final report = GrBleDiscoveryReport.compare(services);
    _discovery = report;
    _emit(TraceDirection.inbound, 'gatt.discover.result', report.toJson());
    return report;
  }

  /// Whether [c] was discovered; null before [discover].
  bool? isPresent(GrBleCharacteristic<Object> c) => _discovery?.isPresent(c);

  // -- raw and typed access ---------------------------------------------------

  /// Reads any characteristic by UUID (canonicalized).
  Future<Uint8List> readUuid(String serviceUuid, String characteristicUuid) {
    final s = canonicalUuid(serviceUuid);
    final c = canonicalUuid(characteristicUuid);
    final fields = {'service': s, 'characteristic': c, 'key': _keyOf(c)};
    return _serialized(() async {
      _emit(TraceDirection.outbound, 'gatt.read', fields);
      try {
        final value = await connection.read(s, c, timeout: operationTimeout);
        _emit(TraceDirection.inbound, 'gatt.read.value', {
          ...fields,
          'hex': BleBytes.toHex(value),
        }, value);
        return value;
      } catch (e) {
        _emit(TraceDirection.internal, 'gatt.read.error', {
          ...fields,
          'error': '$e',
        });
        rethrow;
      }
    }, timeout: 'read $c');
  }

  /// Writes raw bytes with response (both apps; ble.md §Quick reference).
  Future<void> writeUuid(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
  }) {
    final s = canonicalUuid(serviceUuid);
    final c = canonicalUuid(characteristicUuid);
    final fields = {
      'service': s,
      'characteristic': c,
      'key': _keyOf(c),
      'hex': BleBytes.toHex(value),
      'withResponse': withResponse,
    };
    return _serialized(() async {
      _emit(TraceDirection.outbound, 'gatt.write', fields, value);
      try {
        await connection.write(
          s,
          c,
          value,
          withResponse: withResponse,
          timeout: operationTimeout,
        );
        _emit(TraceDirection.inbound, 'gatt.write.ok', fields);
      } catch (e) {
        _emit(TraceDirection.internal, 'gatt.write.error', {
          ...fields,
          'error': '$e',
        });
        rethrow;
      }
    }, timeout: 'write $c');
  }

  /// Reads [c]'s raw bytes; throws [BleErrorCode.notFound] when [discover]
  /// did not find it.
  Future<Uint8List> readRaw(GrBleCharacteristic<Object> c) {
    _requirePresent(c);
    return readUuid(c.service.uuid, c.uuid);
  }

  /// Writes raw bytes to [c] with response; throws [BleErrorCode.notFound]
  /// when [discover] did not find it.
  Future<void> writeRaw(GrBleCharacteristic<Object> c, Uint8List value) {
    _requirePresent(c);
    return writeUuid(c.service.uuid, c.uuid, value);
  }

  /// Reads and decodes [c]. Decoding never throws; GATT errors do.
  Future<BleDecoded<T>> read<T extends Object>(GrBleCharacteristic<T> c) async {
    final decoded = c.codec.decode(await readRaw(c));
    _emit(TraceDirection.internal, 'decoded', {
      'key': c.key,
      ...decoded.toJson(),
    });
    _observe(c, decoded);
    return decoded;
  }

  /// Encodes [value] with [c]'s codec and writes it.
  Future<void> write<T extends Object>(GrBleCharacteristic<T> c, T value) =>
      writeRaw(c, c.codec.encode(value));

  /// Decoded notifications of [c]; notifications are enabled while the
  /// stream is listened to. The CCCD write itself is performed by the
  /// transport and is not covered by this client's serialization.
  Stream<GrBleNotification<T>> watch<T extends Object>(
    GrBleCharacteristic<T> c,
  ) {
    _requirePresent(c);
    final source = connection.subscribe(c.service.uuid, c.uuid);
    return Stream.multi((controller) {
      _emit(TraceDirection.outbound, 'gatt.subscribe', {'key': c.key});
      final sub = source.listen(
        (bytes) {
          final decoded = c.codec.decode(bytes);
          _emit(TraceDirection.inbound, 'gatt.notify', {
            'key': c.key,
            ...decoded.toJson(),
          }, bytes);
          _observe(c, decoded);
          controller.add(GrBleNotification(c, decoded));
        },
        onError: (Object e, StackTrace st) {
          _emit(TraceDirection.internal, 'gatt.notify.error', {
            'key': c.key,
            'error': '$e',
          });
          controller.addError(e, st);
        },
        onDone: controller.close,
      );
      controller.onCancel = () {
        _emit(TraceDirection.outbound, 'gatt.unsubscribe', {'key': c.key});
        return sub.cancel();
      };
    });
  }

  /// Merged notifications of [characteristics] in subscription order. With
  /// [prime], each subscription is followed by one read, as GR WORLD does.
  /// Characteristics known to be absent after [discover] are skipped.
  Stream<GrBleNotification<Object>> watchAll(
    List<GrBleCharacteristic<Object>> characteristics, {
    bool prime = false,
  }) {
    final subs = <StreamSubscription<GrBleNotification<Object>>>[];
    var cancelled = false;
    late final StreamController<GrBleNotification<Object>> controller;
    controller = StreamController(
      onListen: () async {
        for (final c in characteristics) {
          if (cancelled) return;
          if (isPresent(c) == false) {
            _emit(TraceDirection.internal, 'subscribe.skipped', {
              'key': c.key,
              'reason': 'not discovered',
            });
            continue;
          }
          subs.add(
            watch(c).listen(controller.add, onError: controller.addError),
          );
          if (prime && c.readable) {
            try {
              final d = await read(c);
              if (!cancelled) {
                controller.add(GrBleNotification(c, d, primed: true));
              }
            } on BleException catch (e, st) {
              if (!cancelled) controller.addError(e, st);
            }
          }
        }
      },
      onCancel: () async {
        cancelled = true;
        for (final s in subs) {
          await s.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }

  /// Tracks camera-power transitions for [lastPowerOff].
  void _observe<T extends Object>(
    GrBleCharacteristic<T> c,
    BleDecoded<T> decoded,
  ) {
    if (c.uuid != GrBleCatalog.cameraPower.uuid) return;
    final v = decoded.value;
    if (v is! BleEnumValue<BleCameraPower>) return;
    final on = v.known == BleCameraPower.on;
    if (_lastPowerOn == true && v.known == BleCameraPower.off) {
      _lastPowerOff = DateTime.now();
      _emit(TraceDirection.internal, 'power.offObserved', {});
    }
    _lastPowerOn = on;
  }

  // -- identity and Wi-Fi -----------------------------------------------------

  /// Reads the six Camera Information characteristics.
  Future<GrBleIdentity> readIdentity() async {
    final values = <String, String?>{};
    final issues = <String, List<String>>{};
    for (final c in GrBleCatalog.identity) {
      if (isPresent(c) == false) {
        issues[c.key] = ['not discovered'];
        continue;
      }
      try {
        final d = await read(c);
        values[c.key] = d.value;
        if (d.issues.isNotEmpty) issues[c.key] = d.issues;
      } on BleException catch (e) {
        issues[c.key] = ['${e.code.name}: ${e.message}'];
      }
    }
    return GrBleIdentity(
      manufacturer: values[GrBleCatalog.manufacturerName.key],
      modelName: values[GrBleCatalog.modelName.key],
      serialNumber: values[GrBleCatalog.serialNumber.key],
      firmwareRevision: values[GrBleCatalog.firmwareRevision.key],
      bluetoothDeviceName: values[GrBleCatalog.bluetoothDeviceName.key],
      bluetoothMacAddress: values[GrBleCatalog.bluetoothMacAddress.key],
      issues: issues,
    );
  }

  /// Reads SSID and passphrase plus whichever of security, wlanFreq,
  /// available5GHz (GR IV) and Channel (GR III) the camera has. Runs
  /// [discover] first when it has not run, to decide which are present.
  Future<GrWifiCredentials> readWifiCredentials() async {
    if (_discovery == null) await discover();
    final issues = <String>[];

    Future<V?> optional<V extends Object>(GrBleCharacteristic<V> c) async {
      if (isPresent(c) != true) return null;
      try {
        final d = await read(c);
        for (final i in d.issues) {
          issues.add('${c.key}: $i');
        }
        return d.value;
      } on BleException catch (e) {
        issues.add('${c.key}: ${e.code.name}: ${e.message}');
        return null;
      }
    }

    final ssid = await read(GrBleCatalog.ssid);
    final passphrase = await read(GrBleCatalog.passphrase);
    for (final d in [ssid, passphrase]) {
      issues.addAll(d.issues);
    }
    final security = await optional(GrBleCatalog.wlanSecurity);
    final frequency = await optional(GrBleCatalog.wlanFrequency);
    final available5GHz = await optional(GrBleCatalog.available5GHz);
    final channel = await optional(GrBleCatalog.wlanChannel);
    final networkType = await optional(GrBleCatalog.networkType);
    return GrWifiCredentials(
      ssid: ssid.value ?? '',
      passphrase: passphrase.value ?? '',
      security: security,
      wifiSecurity: security == null
          ? WifiSecurity.wpa2
          : security.known?.wifiSecurity,
      securityAssumed: security == null,
      frequency: frequency,
      channel: channel,
      available5GHz: available5GHz,
      networkType: networkType,
      issues: issues,
    );
  }

  /// Camera AP on (`01`) or off (`00`) via Network Type (ble.md §Turning
  /// the camera's Wi-Fi on). The camera may refuse in movie mode or while
  /// USB is connected.
  Future<void> setWlan({required bool on}) => write(
    GrBleCatalog.networkType,
    BleEnumValue.of(on ? BleNetworkType.ap : BleNetworkType.off),
  );

  /// GR WORLD's full settings apply (ble.md §Changing the camera's WLAN
  /// settings): ssid, passphrase, wlanFreq (only if present), security (only
  /// if present), then WLAN off so the camera applies them. Null fields are
  /// not written. Changes persistent network settings.
  Future<void> applyWlanSettings({
    String? ssid,
    String? passphrase,
    BleWlanFrequency? frequency,
    BleWlanSecurity? security,
    BleWlanChannel? channel,
  }) async {
    if (_discovery == null) await discover();
    if (ssid != null) await write(GrBleCatalog.ssid, ssid);
    if (passphrase != null) await write(GrBleCatalog.passphrase, passphrase);
    if (frequency != null) {
      await write(GrBleCatalog.wlanFrequency, BleEnumValue.of(frequency));
    }
    if (security != null) {
      await write(GrBleCatalog.wlanSecurity, BleEnumValue.of(security));
    }
    if (channel != null) {
      await write(GrBleCatalog.wlanChannel, BleEnumValue.of(channel));
    }
    await setWlan(on: false);
  }

  // -- shooting ---------------------------------------------------------------

  /// Shutter release: `01 01` with AF (GR WORLD), `01 00` without (Image
  /// Sync). Image Sync also sends `01 00` to stop movie/continuous/interval/T
  /// capture.
  Future<void> shutter({bool autofocus = true}) => write(
    GrBleCatalog.operationRequest,
    autofocus
        ? BleOperationRequest.shutterWithAf
        : BleOperationRequest.shutterWithoutAf,
  );

  /// AF only, `00 01` (Image Sync).
  Future<void> focus() =>
      write(GrBleCatalog.operationRequest, BleOperationRequest.focusOnly);

  /// Green-button function, `00 02` (Image Sync).
  Future<void> greenButton() =>
      write(GrBleCatalog.operationRequest, BleOperationRequest.greenButton);

  /// Cancels a running self-timer countdown. GR WORLD sends 1 byte, Image
  /// Sync 2; the caller chooses.
  Future<void> cancelSelfTimer(BleSelfTimerCancelFormat format) =>
      write(GrBleCatalog.selfTimer, format.command);

  /// Writes Drive Mode (single, continuous, self-timer, ...).
  Future<void> setDriveMode(BleDriveMode mode) =>
      write(GrBleCatalog.driveMode, BleEnumValue.of(mode));

  /// Writes Capture Mode (still or movie).
  Future<void> setCaptureMode(BleCaptureMode mode) =>
      write(GrBleCatalog.captureMode, BleEnumValue.of(mode));

  /// Read-modify-write of Shooting Mode, keeping the length the camera
  /// returned (2 bytes GR WORLD, 3 bytes Image Sync).
  Future<void> setExposureMode(
    BleExposureMode mode, {
    BleUserMode? userMode,
  }) async {
    final current = await read(GrBleCatalog.shootingMode);
    final v = current.value;
    if (v == null) {
      throw BleException(
        BleErrorCode.gatt,
        'shooting mode could not be decoded for read-modify-write: '
        '${current.issues.join('; ')}',
      );
    }
    await write(
      GrBleCatalog.shootingMode,
      v.copyWith(
        mode: BleEnumValue.of(mode),
        userMode: userMode == null ? null : BleEnumValue.of(userMode),
      ),
    );
  }

  /// Writes Shutter Speed by table index (see [bleShutterSpeedLabels]);
  /// 0 is B/T.
  Future<void> setShutterSpeed(int index) => write(
    GrBleCatalog.shutterSpeed,
    BleIndexedValue(index, bleShutterSpeedLabels[index]),
  );

  /// Writes Aperture by table index (see [bleApertureLabels]); 0 is AUTO.
  Future<void> setAperture(int index) => write(
    GrBleCatalog.aperture,
    BleIndexedValue(index, bleApertureLabels[index]),
  );

  /// Literal ISO value, 0 = AUTO.
  Future<void> setIso(int iso) =>
      write(GrBleCatalog.iso, BleIndexedValue(iso, bleIsoLabels[iso]));

  /// Index: EV × 3 for 1/3 steps, ±51…±58 for half steps.
  Future<void> setExposureCompensation(int index) => write(
    GrBleCatalog.exposureCompensation,
    BleIndexedValue(index, bleExposureCompensationLabels[index]),
  );

  /// Writes White Balance.
  Future<void> setWhiteBalance(BleWhiteBalance wb) =>
      write(GrBleCatalog.whiteBalance, BleEnumValue.of(wb));

  /// Writes Metering Mode.
  Future<void> setMeteringMode(BleMeteringMode mode) =>
      write(GrBleCatalog.meteringMode, BleEnumValue.of(mode));

  /// Read-modify-write of File Type, as Image Sync writes whole records.
  Future<void> setFileType(BleStillFileType type, {BleRawType? rawType}) async {
    final current = await read(GrBleCatalog.fileType);
    final v = current.value;
    if (v == null) {
      throw BleException(
        BleErrorCode.gatt,
        'file type could not be decoded for read-modify-write: '
        '${current.issues.join('; ')}',
      );
    }
    await write(
      GrBleCatalog.fileType,
      v.copyWith(
        fileType: BleEnumValue.of(type),
        rawType: rawType == null ? null : BleEnumValue.of(rawType),
      ),
    );
  }

  /// Writes JPEG image size.
  Future<void> setJpegSize(BleJpegSize size) =>
      write(GrBleCatalog.jpegSize, BleEnumValue.of(size));

  /// Writes Movie Configuration (movie size and frame rate).
  Future<void> setMovieConfiguration(BleMovieConfiguration config) =>
      write(GrBleCatalog.movieConfiguration, BleEnumValue.of(config));

  // -- camera state -----------------------------------------------------------

  /// Writes [time] (default: now, local) to Date Time, as both apps do.
  Future<BleDateTime> syncDateTime([DateTime? time]) async {
    final value = BleDateTime.fromDateTime(time ?? DateTime.now());
    await write(GrBleCatalog.dateTime, value);
    return value;
  }

  /// Writes one phone-location record for geotagging; GR WORLD repeats it
  /// every 5, 30 or 180 s.
  Future<void> sendGps(BleGpsInformation record) =>
      write(GrBleCatalog.gpsInformation, record);

  /// Turns the camera's geotag setting on or off.
  Future<void> setGeoTag({required bool enabled}) =>
      write(GrBleCatalog.geoTag, enabled);

  /// Writes `00` to Camera Power, the only value either app writes. The
  /// camera turns off; GR WORLD then waits 6 s before reconnecting.
  Future<void> powerOff() async {
    await write(GrBleCatalog.cameraPower, BleEnumValue.of(BleCameraPower.off));
    _lastPowerOff = DateTime.now();
    _lastPowerOn = false;
  }

  /// Writes Operation Mode. GR WORLD wakes a camera reading BLE startup by
  /// writing playback, or capture for its Remote button (power-on-grworld.md);
  /// `GrSession` does the same.
  Future<void> setOperationMode(BleOperationMode mode) =>
      write(GrBleCatalog.operationMode, BleEnumValue.of(mode));

  /// Writes BLE Enable Condition (0 disable, 1 anytime, 2 power-on only).
  /// Image Sync never writes it; it changes whether the camera can be woken
  /// over BLE.
  Future<void> setBleEnableCondition(BleEnableCondition condition) =>
      write(GrBleCatalog.bleEnableCondition, BleEnumValue.of(condition));

  /// Writes [name] verbatim; see [sanitizePairedDeviceName] for GR WORLD's
  /// rules.
  Future<void> setPairedDeviceName(String name) =>
      write(GrBleCatalog.pairedDeviceName, name);

  /// Writes the camera's own name (GR IV Camera Service; default
  /// "MY GR IV").
  Future<void> setCameraName(String name) =>
      write(GrBleCatalog.cameraName, name);

  /// GR WORLD's phone-name sanitiser (0x82ebc8): keep U+0020..U+007E and
  /// U+3000, replace other characters with `?`, stop at 32 characters,
  /// trim, empty → "Unknown".
  static String sanitizePairedDeviceName(String name) {
    final out = StringBuffer();
    var count = 0;
    for (final rune in name.runes) {
      if (count == 32) break;
      final keep = (rune >= 0x20 && rune <= 0x7e) || rune == 0x3000;
      out.write(keep ? String.fromCharCode(rune) : '?');
      count++;
    }
    final trimmed = out.toString().trim();
    return trimmed.isEmpty ? 'Unknown' : trimmed;
  }

  /// GR WORLD's write: read current, wait 50 ms, write `[current0, new]`.
  /// [behavior] overrides byte 0 when given.
  Future<void> setPowerOffDuringTransfer({
    bool? autoResize,
    BleTransferPowerOffBehavior? behavior,
  }) async {
    final current = await read(GrBleCatalog.powerOffDuringTransfer);
    final v = current.value;
    if (v == null) {
      throw BleException(
        BleErrorCode.gatt,
        'power-off-during-transfer could not be decoded: '
        '${current.issues.join('; ')}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await write(
      GrBleCatalog.powerOffDuringTransfer,
      BlePowerOffDuringTransfer(
        behavior == null ? v.behavior : BleEnumValue.of(behavior),
        autoResize: autoResize ?? v.autoResize,
      ),
    );
  }

  // -- image control ----------------------------------------------------------

  static ({
    GrBleCharacteristic<String> name,
    GrBleCharacteristic<BleImageControlBlob> data,
  })
  _slot(int slot) {
    if (slot < 1 || slot > 3) {
      throw ArgumentError.value(slot, 'slot', 'must be 1, 2 or 3');
    }
    return GrBleCatalog.imageControlSlots[slot - 1];
  }

  /// Reads the name and data of Image Control Custom [slot] (1–3).
  Future<({BleDecoded<String> name, BleDecoded<BleImageControlBlob> data})>
  readImageControl(int slot) async {
    final s = _slot(slot);
    return (name: await read(s.name), data: await read(s.data));
  }

  /// Writes the name of Image Control Custom [slot] (1–3).
  Future<void> writeImageControlName(int slot, String name) =>
      write(_slot(slot).name, name);

  /// Writes the data blob of Image Control Custom [slot] (1–3).
  Future<void> writeImageControlData(int slot, BleImageControlBlob blob) =>
      write(_slot(slot).data, blob);

  // -- firmware ---------------------------------------------------------------

  /// Writes `01` to firmware-update start (GR WORLD step 4, after the image
  /// was uploaded over Wi-Fi). Starts flashing.
  Future<void> startFirmwareUpdate() =>
      write(GrBleCatalog.firmwareUpdateStart, true);

  /// Writes the firmware-update-available flag. The characteristic's
  /// meaning is \[inferred\] from block order; no GR WORLD caller writes it.
  Future<void> setFirmwareUpdateAvailable({required bool available}) =>
      write(GrBleCatalog.firmwareUpdateAvailable, available);

  /// Reads the firmware-update result (invalid, success or failure).
  Future<BleDecoded<BleEnumValue<BleFirmwareUpdateResult>>>
  readFirmwareUpdateResult() => read(GrBleCatalog.firmwareUpdateResult);
}
