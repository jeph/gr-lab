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
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) =>
      _camera._scan(serviceUuids);

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

  /// Every catalog characteristic the model's firmware carries.
  List<GrBleCharacteristic<Object>> get _present => [
    for (final c in GrBleCatalog.all)
      if ((model.family == GrModelFamily.gr4 ? c.onGr4 : c.onGr3) != false) c,
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

  /// What the camera's main firmware serves is refused in the
  /// Bluetooth-only state of a camera that is off: the Custom slots
  /// \[inferred\] (firmware-bonding.md §6), and GPS Information and Date
  /// Time, reads and writes alike \[design\]. What an off camera does with
  /// a location record is \[unknown\] (geotagging.md §7, test 7), as is
  /// what it does with its clock.
  void _requireMainFirmware(GrBleCharacteristic<Object> c) {
    if (_poweredOn) return;
    if (!_isLookSlot(c) &&
        c != GrBleCatalog.gpsInformation &&
        c != GrBleCatalog.dateTime) {
      return;
    }
    throw BleException(BleErrorCode.gatt, '${c.key}: camera is off');
  }

  static bool _isLookSlot(GrBleCharacteristic<Object> c) =>
      GrBleCatalog.imageControlSlots.any((s) => s.name == c || s.data == c);

  Uint8List _read(GrBleCharacteristic<Object> c) {
    final live = switch (c) {
      GrBleCatalog.cameraPower =>
        _poweredOn ? BleCameraPower.on.wire : BleCameraPower.off.wire,
      GrBleCatalog.operationMode => operationMode.wire,
      GrBleCatalog.batteryLevel => _battery & 0xff,
      GrBleCatalog.networkType =>
        _wlanEnabled ? BleNetworkType.ap.wire : BleNetworkType.off.wire,
      GrBleCatalog.driveMode => _driveMode,
      GrBleCatalog.geoTag => _storeLocationInfo ? 1 : 0,
      _ => null,
    };
    if (live != null) return Uint8List.fromList([live]);
    final record = switch (c) {
      // GR WORLD's 2-byte forms (ble.md, Shooting mode / Capture status).
      GrBleCatalog.shootingMode => [_exposureMode.wire, _userMode.wire],
      GrBleCatalog.captureStatus => _captureStatus,
      GrBleCatalog.storageInformation => _storageInformation(),
      GrBleCatalog.dateTime => GrBleCatalog.dateTime.codec.encode(
        BleDateTime.fromDateTime(clock),
      ),
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
        if (v.length != BleImageControlBlob.length ||
            decoded.value == null ||
            decoded.issues.isNotEmpty) {
          throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
        }
        _values[c.uuid] = v;
      // `bled` takes only `00` or `01` (geotagging.md §1.1); a value of
      // another length is refused too \[design\]. When the main firmware
      // refuses the change is \[unknown\]: the fake always takes it.
      case GrBleCatalog.geoTag:
        if (v.length != 1 || first > 1) {
          throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
        }
        _setStoreLocationInfo(on: first == 1);
      case GrBleCatalog.gpsInformation:
        _takeLocation(c, v);
      case GrBleCatalog.dateTime:
        _setClock(c, v);
      default:
        _values[c.uuid] = v;
    }
  }

  /// Store Location Info changes, from the camera's menu or a GEO Tag
  /// write. Turning it off clears the location at once (geotagging.md
  /// §1.3: found for the menu, \[inferred\] for the write). A change
  /// notifies GEO Tag; that a write notifies as the menu does is
  /// \[design\].
  void _setStoreLocationInfo({required bool on}) {
    if (on == _storeLocationInfo) return;
    _storeLocationInfo = on;
    _notify(GrBleCatalog.geoTag, [if (on) 1 else 0]);
    if (!on) _clearLocation();
  }

  /// A GPS Information write, judged as the main firmware's property
  /// setter judges the record (geotagging.md §1.2): refused while Store
  /// Location Info is off, and unless latitude is within ±90, longitude
  /// within ±180, altitude within ±9999 and the fix time a real calendar
  /// date and time. An accepted record is the camera's location for
  /// [FakeCameraConfig.locationValidity] from now, and each one restarts
  /// that time (§1.3). Nothing is notified (§1.1).
  ///
  /// Where the fake departs from the firmware, or goes past what is known:
  /// * the firmware also wants the year within 50 years of a base year
  ///   that is \[unknown\], so the year is not checked;
  /// * a record shorter than 32 bytes is refused \[design\]: `bled` reads
  ///   31 bytes whatever the length. A longer one is taken, and the datum
  ///   byte is not looked at, as in `bled` (§1.1);
  /// * the ATT error of a refusal is \[unknown\]: a GATT error
  ///   \[design\];
  /// * what a read of GPS Information answers is \[unknown\]: an accepted
  ///   record is not kept for one.
  void _takeLocation(GrBleCharacteristic<Object> c, Uint8List v) {
    if (!_storeLocationInfo) {
      throw BleException(
        BleErrorCode.gatt,
        '${c.key}: Store Location Info is off',
      );
    }
    final record = GrBleCatalog.gpsInformation.codec.decode(v).value;
    if (record == null ||
        !_isWithin(record.latitude, 90) ||
        !_isWithin(record.longitude, 180) ||
        !_isWithin(record.altitude, 9999) ||
        !_isRealDateTime(
          record.year,
          record.month,
          record.day,
          record.hour,
          record.minute,
          record.second,
        )) {
      throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
    }
    _location = record;
    _acceptedLocations.add(record);
    _cancel(_locationExpiry);
    _locationExpiry = _after(config.locationValidity, _clearLocation);
  }

  /// The camera has no location any more. The clear after a clock change
  /// stays armed: it is the clock's, not the location's.
  void _clearLocation() {
    _cancel(_locationExpiry);
    _locationExpiry = null;
    _location = null;
  }

  /// A Date Time write sets the camera's clock. One that is not a real
  /// calendar date and time is refused \[design\]: what the camera does
  /// with one is \[unknown\], and trailing bytes are taken \[design\].
  ///
  /// On a GR IV family body the location is cleared
  /// [FakeCameraConfig.clockChangeClearsAfter] after the write
  /// (geotagging.md §1.3), with any record taken in between \[inferred\].
  /// Every accepted write counts as a change of the clock, and a second one
  /// inside that time starts it again \[design\]. No such clear was found
  /// in the GR III firmware (§1.5).
  void _setClock(GrBleCharacteristic<Object> c, Uint8List v) {
    final written = GrBleCatalog.dateTime.codec.decode(v).value;
    if (written == null ||
        !_isRealDateTime(
          written.year,
          written.month,
          written.day,
          written.hour,
          written.minute,
          written.second,
        )) {
      throw BleException(BleErrorCode.gatt, '${c.key}: invalid value');
    }
    _clockOffset = DateTime(
      written.year,
      written.month,
      written.day,
      written.hour,
      written.minute,
      written.second,
    ).difference(DateTime.now());
    _clockWrites++;
    if (model.family != GrModelFamily.gr4) return;
    _cancel(_clockChangeClear);
    _clockChangeClear = _after(config.clockChangeClearsAfter, _clearLocation);
  }

  /// Not NaN, and no further from zero than [limit].
  static bool _isWithin(double value, double limit) => value.abs() <= limit;

  /// Whether the fields name a date and time that exists: the month has
  /// that day, and so on. The year is free.
  static bool _isRealDateTime(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    final normalized = DateTime.utc(year, month, day, hour, minute, second);
    return normalized.month == month &&
        normalized.day == day &&
        normalized.hour == hour &&
        normalized.minute == minute &&
        normalized.second == second;
  }

  void _notify(GrBleCharacteristic<Object> c, List<int> value) {
    for (final link in _links.toList()) {
      final controllers = link._listeners[c.uuid]?.toList();
      for (final controller in controllers ?? const <Never>[]) {
        controller.add(Uint8List.fromList(value));
      }
    }
  }

  /// Numeric comparison on the camera: only on Execute Pairing, once.
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
    final confirmTimer = auto == null ? null : _after(auto, confirmPairing);
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
