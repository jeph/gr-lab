part of 'fake_camera.dart';

/// A connect to an absent peripheral waits for its timeout, at most this
/// long, so failure paths stay quick in tests and the demo.
const _unreachableGiveUp = Duration(seconds: 2);

final class _FakeTransport implements BleTransport {
  new(this._camera);

  final FakeGrCamera _camera;

  @override
  Future<BleAdapterState> adapterState() async => _camera.adapterState;

  @override
  Stream<BleAdvertisement> scan({
    List<String> serviceUuids = const [],
    BleScanRate? rate,
  }) => _camera._scan(serviceUuids);

  @override
  Future<BleConnection> connect(String deviceId, {required Duration timeout}) =>
      _camera._connect(deviceId, timeout);

  @override
  Future<void> close() async {
    for (final link in _camera._links.toList()) {
      await link.disconnect();
    }
  }
}

final class _FakeLink implements BleConnection {
  new(this._camera, this.deviceId);

  final FakeGrCamera _camera;
  @override
  final String deviceId;
  final Completer<BleDisconnect> _down = Completer();
  final Map<String, Set<StreamController<Uint8List>>> _listeners = {};

  /// The camera is restarting its radio (into its main firmware, or as
  /// its host wakes): nothing on this link is answered until it drops.
  bool _booting = false;

  bool get _open => !_down.isCompleted;

  @override
  int? get maximumWriteLength => 512;

  @override
  Future<BleDisconnect> get disconnected => _down.future;

  @override
  Future<void> disconnect() async =>
      _close(const BleDisconnect(requested: true));

  /// Camera-side drop.
  void _drop(String reason) =>
      _close(BleDisconnect(requested: false, reason: reason));

  void _close(BleDisconnect why) {
    if (_down.isCompleted) return;
    _down.complete(why);
    _camera._links.remove(this);
    for (final controllers in _listeners.values) {
      for (final c in controllers) {
        unawaited(c.close());
      }
    }
    _listeners.clear();
  }

  Future<void> _ready() async {
    await Future<void>.delayed(_camera.config.bleLatency);
    if (_booting && _open) await _down.future;
    if (!_open) {
      throw const BleException(BleErrorCode.notConnected, 'link is down');
    }
  }

  @override
  Future<List<BleServiceInfo>> discover() async {
    await _ready();
    return _camera._gatt();
  }

  @override
  Future<Uint8List> read(
    String serviceUuid,
    String characteristicUuid, {
    Duration? timeout,
  }) async {
    await _ready();
    final c = _camera._characteristic(serviceUuid, characteristicUuid);
    if (!c.readable) {
      throw BleException(BleErrorCode.gatt, '${c.key}: read not permitted');
    }
    if (_camera.config.unreadable.contains(c.key)) {
      throw BleException(BleErrorCode.gatt, '${c.key}: read failed');
    }
    _camera
      .._requireBond(c)
      .._requireMainFirmware(c);
    return _camera._read(c);
  }

  @override
  Future<void> write(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    await _ready();
    final c = _camera._characteristic(serviceUuid, characteristicUuid);
    if (!c.writable) {
      throw BleException(BleErrorCode.gatt, '${c.key}: write not permitted');
    }
    _camera
      .._requireBond(c)
      .._requireMainFirmware(c)
      .._write(this, c, Uint8List.fromList(value));
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String characteristicUuid) {
    late final StreamController<Uint8List> controller;
    String? key;
    controller = StreamController<Uint8List>(
      onListen: () {
        try {
          final c = _camera._characteristic(serviceUuid, characteristicUuid);
          if (!c.notifies) {
            throw BleException(BleErrorCode.gatt, '${c.key}: no notify');
          }
          _camera._requireBond(c);
          if (!_open) {
            throw const BleException(BleErrorCode.notConnected, 'link down');
          }
          key = c.uuid;
          (_listeners[c.uuid] ??= {}).add(controller);
        } on BleException catch (e) {
          controller.addError(e);
          unawaited(controller.close());
        }
      },
      // Returning close() here would deadlock: the done future waits for
      // the cancel that is waiting on it.
      onCancel: () {
        _listeners[key]?.remove(controller);
        unawaited(controller.close());
      },
    );
    return controller.stream;
  }

  @override
  Future<void> pair({
    required String probeServiceUuid,
    required String probeCharacteristicUuid,
    required Duration timeout,
  }) async {
    await _ready();
    await _camera._pair(this, timeout);
  }
}

extension on FakeGrCamera {
  BleAdvertisement _advertisement() {
    final serial =
        int.tryParse(config.serial.replaceAll(RegExp(r'\D'), '')) ?? 0;
    return BleAdvertisement(
      deviceId: config.deviceId,
      name: config.bluetoothName,
      rssi: -58,
      connectable: true,
      manufacturerData: {
        grRicohCompanyId: Uint8List.fromList([
          grAdvertisingMarker,
          0x01,
          model.code,
          0x02,
          serial & 0xff,
          (serial >> 8) & 0xff,
          (serial >> 16) & 0xff,
          (serial >> 24) & 0xff,
          0x03,
          if (_poweredOn) BleCameraPower.on.wire else BleCameraPower.off.wire,
        ]),
      },
      // GR WORLD's power hint: Camera Information while on, Client
      // Registration from the BT-only firmware (ble.md §Identifying).
      serviceUuids: [
        if (_poweredOn)
          GrBleServices.cameraInformation.uuid
        else
          GrBleServices.clientRegistration.uuid,
      ],
    );
  }

  Stream<BleAdvertisement> _scan(List<String> serviceUuids) {
    final wanted = {for (final u in serviceUuids) canonicalUuid(u)};
    Timer? timer;
    late final StreamController<BleAdvertisement> controller;
    void advertise() {
      if (_closed ||
          config.unreachable ||
          _bluetoothOff ||
          adapterState != BleAdapterState.poweredOn) {
        return;
      }
      final ad = _advertisement();
      if (wanted.isNotEmpty && !ad.serviceUuids.any(wanted.contains)) return;
      controller.add(ad);
    }

    controller = StreamController<BleAdvertisement>(
      onListen: () {
        if (_closed) {
          unawaited(controller.close());
          return;
        }
        if (adapterState != BleAdapterState.poweredOn) {
          controller.addError(
            BleException(
              BleErrorCode.poweredOff,
              'Bluetooth is ${adapterState.name}',
            ),
          );
          return;
        }
        if (config.openExecutePairingOnScan && !executePairingOpen) {
          openExecutePairing();
        }
        _scans.add(controller);
        advertise();
        final interval = config.advertisingInterval > Duration.zero
            ? config.advertisingInterval
            : const Duration(milliseconds: 1);
        // In [_timers] so close() stops a scan nobody cancelled.
        timer = Timer.periodic(interval, (_) => advertise());
        _timers.add(timer!);
      },
      onCancel: () {
        _cancel(timer);
        _scans.remove(controller);
        unawaited(controller.close());
      },
    );
    return controller.stream;
  }

  Future<BleConnection> _connect(String deviceId, Duration timeout) async {
    if (adapterState != BleAdapterState.poweredOn) {
      throw BleException(
        BleErrorCode.poweredOff,
        'Bluetooth is ${adapterState.name}',
      );
    }
    if (_closed ||
        config.unreachable ||
        _bluetoothOff ||
        deviceId != config.deviceId) {
      await Future<void>.delayed(
        timeout < _unreachableGiveUp ? timeout : _unreachableGiveUp,
      );
      throw BleException(BleErrorCode.timeout, 'no answer from $deviceId');
    }
    await Future<void>.delayed(config.connectDelay);
    final link = _FakeLink(this, deviceId);
    _links.add(link);
    final drop = config.firstOffLinkDrop;
    if (_hostAsleep && drop != null) {
      _hostAsleep = false;
      link._booting = true;
      _after(drop, () => link._drop('link supervision timeout'));
    }
    return link;
  }

  /// Every catalog characteristic the model's firmware carries, less the
  /// ones this camera is set up without ([FakeCameraConfig.absent]).
  List<GrBleCharacteristic<Object>> get _present => [
    for (final c in GrBleCatalog.all)
      if ((model.family == GrModelFamily.gr4 ? c.onGr4 : c.onGr3) != false &&
          !config.absent.contains(c.key))
        c,
  ];

  List<BleServiceInfo> _gatt() {
    final byService = <String, List<BleCharacteristicInfo>>{};
    for (final c in _present) {
      (byService[c.service.uuid] ??= []).add(
        BleCharacteristicInfo(uuid: c.uuid, properties: c.properties),
      );
    }
    return [
      for (final e in byService.entries)
        BleServiceInfo(uuid: e.key, characteristics: e.value),
    ];
  }

  GrBleCharacteristic<Object> _characteristic(
    String serviceUuid,
    String characteristicUuid,
  ) {
    final c = GrBleCatalog.byUuid(characteristicUuid);
    if (c == null ||
        c.service.uuid != canonicalUuid(serviceUuid) ||
        !_present.contains(c)) {
      throw BleException(
        BleErrorCode.notFound,
        'no characteristic $characteristicUuid in service $serviceUuid',
      );
    }
    return c;
  }

  /// DIS is open; every camera characteristic needs an encrypted link
  /// (ble.md §Pairing, observed on GR IV).
  void _requireBond(GrBleCharacteristic<Object> c) {
    if (c.service == GrBleServices.deviceInformation || _bonded) return;
    throw const BleException(
      BleErrorCode.unauthorized,
      'Authentication is insufficient.',
    );
  }

  /// The Custom slots are served by the camera's main firmware, not by the
  /// Bluetooth-only state of a camera that is off \[inferred\]
  /// (firmware-bonding.md §6).
  void _requireMainFirmware(GrBleCharacteristic<Object> c) {
    if (_poweredOn || !_isLookSlot(c)) return;
    throw BleException(BleErrorCode.gatt, '${c.key}: camera is off');
  }

  static bool _isLookSlot(GrBleCharacteristic<Object> c) =>
      GrBleCatalog.imageControlSlots.any((s) => s.name == c || s.data == c);

  /// Whether the camera's parser refuses [blob] for a value: it rejects
  /// the whole write when a value is outside its parameter's set, which
  /// for the Monochrome's HDR Tone has no Black & White toning (found by
  /// running the GR IV 1.20 firmware's parser in an emulator, not seen on
  /// a camera; research/protocol/image-control.md §1, §4). The parser's
  /// other checks (the format version, the body's bases, each base's
  /// exact parameters in order and the custom filter's values) are not
  /// simulated \[design\].
  static bool _refusesLookValue(BleImageControlBlob blob) =>
      blob.parameters.any((entry) {
        final value = entry.value;
        final (min, max) = switch (entry.parameter.known) {
          BleImageControlParameter.saturation ||
          BleImageControlParameter.hue ||
          BleImageControlParameter.key ||
          BleImageControlParameter.contrast ||
          BleImageControlParameter.contrastHigh ||
          BleImageControlParameter.contrastLow ||
          BleImageControlParameter.sharpness ||
          BleImageControlParameter.toningRetro ||
          BleImageControlParameter.shading ||
          BleImageControlParameter.clarity => (-4, 4),
          BleImageControlParameter.toningMonotone => (0, 5),
          BleImageControlParameter.toningCinema ||
          BleImageControlParameter.toningHdr ||
          BleImageControlParameter.grainSize ||
          BleImageControlParameter.grainStrength ||
          BleImageControlParameter.crossProcess => (0, 2),
          BleImageControlParameter.toningBleachBypass ||
          BleImageControlParameter.hdrStrength => (0, 3),
          BleImageControlParameter.filterEffect ||
          BleImageControlParameter.grain => (0, 1),
          BleImageControlParameter.solarizationType => (1, 3),
          _ => (value, value),
        };
        final monoHdrBlackAndWhite =
            blob.base.known == BleImageControlBase.hdrMono &&
            entry.parameter.known == BleImageControlParameter.toningHdr &&
            value == 1;
        return value < min || value > max || monoHdrBlackAndWhite;
      });

  Uint8List _read(GrBleCharacteristic<Object> c) {
    final live = switch (c) {
      GrBleCatalog.cameraPower =>
        _poweredOn ? BleCameraPower.on.wire : BleCameraPower.off.wire,
      GrBleCatalog.operationMode => operationMode.wire,
      GrBleCatalog.batteryLevel => _battery & 0xff,
      GrBleCatalog.networkType =>
        _wlanEnabled ? BleNetworkType.ap.wire : BleNetworkType.off.wire,
      GrBleCatalog.driveMode => _driveMode,
      _ => null,
    };
    if (live != null) return Uint8List.fromList([live]);
    final record = switch (c) {
      // GR WORLD's 2-byte forms (ble.md, Shooting mode / Capture status).
      GrBleCatalog.shootingMode => [_exposureMode.wire, _userMode.wire],
      GrBleCatalog.captureStatus => _captureStatus,
      GrBleCatalog.storageInformation => _storageInformation(),
      GrBleCatalog.dateTime => _readClock(),
      _ => null,
    };
    if (record != null) return Uint8List.fromList(record);
    return Uint8List.fromList(_values[c.uuid] ?? const [0]);
  }

  void _write(_FakeLink link, GrBleCharacteristic<Object> c, Uint8List v) {
    final first = v.isEmpty ? -1 : v.first;
    switch (c) {
      case GrBleCatalog.operationMode:
        final wakes =
            first == BleOperationMode.capture.wire ||
            first == BleOperationMode.playback.wire;
        if (_poweredOn) {
          // A running camera switches between capture and playback; other
          // values are refused [design].
          if (!wakes) {
            throw BleException(
              BleErrorCode.gatt,
              '${c.key}: $first not settable',
            );
          }
          _mode = first;
          _notify(c, v);
        } else if (wakes && config.wakeKeepsLink) {
          _after(
            config.wakeDelay,
            () => _setPower(true, mode: first, keepLinks: true),
          );
        } else if (wakes) {
          // GR WORLD's power-on: the camera boots its main firmware and the
          // BT-only link goes silent, then drops (GR IV: ~5.5 s).
          link._booting = true;
          _after(config.wakeDelay, () {
            link._drop('camera restarted');
            _setPower(true, mode: first);
          });
        }
      case GrBleCatalog.cameraPower:
        if (first == BleCameraPower.off.wire) {
          _after(config.bleLatency, () => _setPower(false, mode: _mode));
        }
      case GrBleCatalog.networkType:
        if (first == BleNetworkType.ap.wire) {
          if (!_poweredOn || _wlanBroken) {
            throw const BleException(BleErrorCode.gatt, 'WLAN unavailable');
          }
          _enableWlan();
        } else {
          _apDown();
        }
      case GrBleCatalog.pairedDeviceName:
        registeredClientName = utf8.decode(v, allowMalformed: true);
      // Remote shutter `01 01` / `01 00` (ble.md §Remote shooting). Focus
      // only and the green button (`00 ..`) are accepted and do nothing.
      case GrBleCatalog.operationRequest:
        if (v.length != 2) {
          throw BleException(BleErrorCode.gatt, '${c.key}: expected 2 bytes');
        }
        if (first == BleOperationCode.start.wire) {
          if (_releaseRefusal() case (_, final why)?) {
            throw BleException(BleErrorCode.gatt, '${c.key}: $why');
          }
          _release();
        }
      // `01` (GR WORLD) or `01 01` (Image Sync) cancels a countdown.
      case GrBleCatalog.selfTimer:
        if (first == BleCountdownCancel.cancel.wire) _cancelSelfTimer();
      case GrBleCatalog.driveMode:
        if (v.length != 1 ||
            first > BleDriveMode.intervalCompositeSelfTimer2s.wire) {
          throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
        }
        _setDriveMode(first);
      case GrBleCatalog.imageControl1Data ||
          GrBleCatalog.imageControl2Data ||
          GrBleCatalog.imageControl3Data:
        // The camera refuses a blob that is not BleImageControlBlob.length
        // bytes (observed, ble.md § Image Control blob). Other blobs GR
        // WORLD would ignore are refused too \[design\]: what the camera
        // does with one is \[unknown\].
        final decoded = GrBleCatalog.imageControl1Data.codec.decode(v);
        final blob = decoded.value;
        if (v.length != BleImageControlBlob.length ||
            blob == null ||
            decoded.issues.isNotEmpty ||
            _refusesLookValue(blob)) {
          throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
        }
        _values[c.uuid] = v;
      case GrBleCatalog.geoTag:
        _writeStoreLocationInfo(c, v);
      case GrBleCatalog.gpsInformation:
        _writeLocation(c, v);
      case GrBleCatalog.dateTime:
        _writeClock(c, v);
      default:
        _values[c.uuid] = v;
    }
  }

  void _notify(GrBleCharacteristic<Object> c, List<int> value) {
    for (final link in _links.toList()) {
      final controllers = link._listeners[c.uuid]?.toList();
      for (final controller in controllers ?? const <Never>[]) {
        controller.add(Uint8List.fromList(value));
      }
    }
  }

  /// The phone asks to bond: only on Execute Pairing, once. The camera
  /// shows its code and waits for OK (numeric comparison) or for the code
  /// to be typed on the phone (passkey entry), by [pairsByPasskey].
  Future<void> _pair(_FakeLink link, Duration timeout) async {
    if (_pairing != null) {
      throw const BleException(BleErrorCode.transport, 'pairing in progress');
    }
    if (!executePairingOpen || config.refusePairing) {
      // Firmware deletes the entry of a device that requests pairing outside
      // Execute Pairing, refuses, and disconnects (firmware-bonding.md §2).
      executePairingOpen = false;
      _bonded = false;
      _after(Duration.zero, () => link._drop('pairing refused'));
      throw const BleException(
        BleErrorCode.unauthorized,
        'Pairing rejected by the camera',
      );
    }
    final pending = _pairing = Completer<bool>();
    final auto = config.autoConfirmPairing;
    final confirmTimer = auto == null
        ? null
        : _after(auto, pairsByPasskey ? enterPairingCode : confirmPairing);
    final timeoutTimer = _after(timeout, () {
      if (!pending.isCompleted) {
        pending.completeError(
          const BleException(BleErrorCode.timeout, 'pairing not confirmed'),
        );
      }
    });
    unawaited(
      link.disconnected.then((_) {
        if (!pending.isCompleted) {
          pending.completeError(
            const BleException(BleErrorCode.notConnected, 'link dropped'),
          );
        }
      }),
    );
    try {
      if (!await pending.future) {
        throw const BleException(
          BleErrorCode.unauthorized,
          'Pairing cancelled on the camera',
        );
      }
      _bonded = true;
    } finally {
      _cancel(confirmTimer);
      _cancel(timeoutTimer);
      _pairing = null;
      executePairingOpen = false;
    }
  }
}
