part of 'fake_camera.dart';

/// Image Sync's `shootMode` values (remote-shooting.md §4.3) in BLE Drive
/// Mode order (ble.md, Drive mode row): the index is the wire value 0–15,
/// so `/v1/props` `shootMode` and BLE Drive Mode are one setting.
const _shootModes = [
  'single',
  'self10s',
  'self2s',
  'continuous',
  'bracket',
  'bracketSelf10s',
  'bracketSelf2s',
  'multiExp',
  'multiExpSelf10s',
  'multiExpSelf2s',
  'interval',
  'intervalSelf10s',
  'intervalSelf2s',
  'intervalComp',
  'intervalCompSelf10s',
  'intervalCompSelf2s',
];

/// Writable settings and the values `/v1/props` lists for them. Spelling
/// follows Image Sync's GR III tables (remote-shooting.md §4.3); the
/// ranges are a GR IV's \[design\]: f/2.8–16 and ISO 100–204800 in 1/3 steps,
/// 1/4000–30 s, ±5 EV. A real camera's lists come from its own props.
const _settingLists = <String, List<String>>{
  'av': [
    '2.8', '3.2', '3.5', '4.0', '4.5', '5.0', '5.6', '6.3', //
    '7.1', '8.0', '9.0', '10', '11', '13', '14', '16',
  ],
  // `N.D` = N/D seconds: `1.250` = 1/250 s, `3.10` = 0.3 s, `2.1` = 2 s.
  'tv': [
    '1.4000', '1.3200', '1.2500', '1.2000', '1.1600', '1.1250', //
    '1.1000', '1.800', '1.640', '1.500', '1.400', '1.320', '1.250',
    '1.200', '1.160', '1.125', '1.100', '1.80', '1.60', '1.50', '1.40',
    '1.30', '1.25', '1.20', '1.15', '1.13', '1.10', '1.8', '1.6', '1.5',
    '1.4', '3.10', '4.10', '5.10', '6.10', '8.10', '1.1', '13.10',
    '16.10', '2.1', '25.10', '32.10', '4.1', '5.1', '6.1', '8.1', '10.1',
    '13.1', '15.1', '20.1', '25.1', '30.1',
  ],
  'sv': [
    'auto', '100', '125', '160', '200', '250', '320', '400', '500', //
    '640', '800', '1000', '1250', '1600', '2000', '2500', '3200', '4000',
    '5000', '6400', '8000', '10000', '12800', '16000', '20000', '25600',
    '32000', '40000', '51200', '64000', '80000', '102400', '128000',
    '160000', '204800',
  ],
  // Image Sync sends `+` literally (remote-shooting.md §0 item 2).
  'xv': [
    '-5.0', '-4.7', '-4.3', '-4.0', '-3.7', '-3.3', '-3.0', '-2.7', //
    '-2.3', '-2.0', '-1.7', '-1.3', '-1.0', '-0.7', '-0.3', '0.0', '+0.3',
    '+0.7', '+1.0', '+1.3', '+1.7', '+2.0', '+2.3', '+2.7', '+3.0', '+3.3',
    '+3.7', '+4.0', '+4.3', '+4.7', '+5.0',
  ],
  'meteringMode': ['multi', 'center', 'spot', 'highlight'],
  'effect': [
    'off', 'col_vivid', 'col_custom1', 'col_custom2', 'efc_monochrome', //
    'efc_softMonochrome', 'efc_hardMonochrome', 'efc_highContrast',
    'efc_posiFilm', 'efc_bleachBypass', 'efc_retro', 'efc_HDRTone',
  ],
  'shootMode': _shootModes,
};

/// Mode-dial positions `/v1/props` lists for the read-only `exposureMode`
/// (Image Sync's GR III spelling; a GR IV dial \[design\]).
const _exposureModes = [
  'P', 'AV', 'TV', 'M', 'B', 'T', 'BT', 'SFP', 'U1', 'U2', 'U3', //
];

/// Shown in `/v1/props` for storage the shots-left setting does not cover
/// (the GR IV captures' internal-memory values).
const _internalRemain = 500;
const _internalRecordableTime = 3600;
const _sdRecordableTime = 72000;

/// `focusEffectiveArea` `[W, H]` in percent (remote-shooting.md §3.2):
/// Image Sync's default rectangle (0.111,0.125)–(0.889,0.875) \[design\].
const _focusEffectiveArea = [78, 75];

/// The camera's own live-view rate; `maxfps` only lowers it. The firmware
/// default is 90 (remote-shooting.md §1.3); a GR IV's real rate is
/// \[unknown\] and 10 fps keeps the fake light.
const _liveViewFps = 10;

/// Why a release cannot start: errCode and text.
typedef _Refusal = (int, String);

/// Remote shooting: releases over BLE (Operation Request) and HTTP
/// (`/v1/camera/shoot`), the self-timer countdown, Capture Status and the
/// change events a capture produces (remote-shooting.md §2.3), plus the
/// settings behind `/v1/props` and `PUT /v1/params/camera`.
extension on FakeGrCamera {
  /// Self-timer length of the current drive mode (ble.md, Drive mode row),
  /// scaled by [FakeCameraConfig.selfTimerScale], or null for none.
  Duration? get _selfTimer {
    final seconds = switch (_driveMode) {
      1 || 5 || 8 || 11 || 14 => 10,
      2 || 6 || 9 || 12 || 15 => 2,
      _ => null,
    };
    if (seconds == null) return null;
    return Duration(
      microseconds:
          (seconds * Duration.microsecondsPerSecond * config.selfTimerScale)
              .round(),
    );
  }

  bool get _releaseBusy => _capturing || _countdown != BleCountdown.none;

  /// The values `<key>List` offers in the current dial mode: aperture and
  /// shutter speed list only their current value where the camera sets
  /// them itself (Av locks the shutter speed), so a write of another value
  /// is refused. On a GR IV HDF the shutter speed could not be changed in
  /// Av and a write was refused (2026-11-08); the single-value list is
  /// \[inferred\].
  List<String>? _listFor(String key) {
    final list = _settingLists[key];
    final free = switch (key) {
      'av' => _apertureFree,
      'tv' => _shutterFree,
      _ => true,
    };
    return free || list == null ? list : [_settings[key]!];
  }

  bool get _apertureFree => switch (_exposureMode) {
    BleExposureMode.av ||
    BleExposureMode.tav ||
    BleExposureMode.m ||
    BleExposureMode.movieAv ||
    BleExposureMode.movieTav ||
    BleExposureMode.movieM => true,
    _ => false,
  };

  bool get _shutterFree => switch (_exposureMode) {
    BleExposureMode.tv ||
    BleExposureMode.tav ||
    BleExposureMode.m ||
    BleExposureMode.movieTv ||
    BleExposureMode.movieTav ||
    BleExposureMode.movieM => true,
    _ => false,
  };

  /// `/v1/props` `exposureMode`: the user preset when one is set.
  String get _exposureModeText => _userMode != BleUserMode.none
      ? 'U${_userMode.wire}'
      : switch (_exposureMode) {
          BleExposureMode.p => 'P',
          BleExposureMode.av => 'AV',
          BleExposureMode.tv => 'TV',
          BleExposureMode.m => 'M',
          BleExposureMode.b => 'B',
          BleExposureMode.bt => 'BT',
          BleExposureMode.t => 'T',
          BleExposureMode.tav => 'TAV',
          BleExposureMode.sv => 'SV',
          BleExposureMode.sfp => 'SFP',
          final other => other.name,
        };

  /// `countDown` as Image Sync reads it (remote-shooting.md §2.3).
  String get _countDownText => _countdown == BleCountdown.none
      ? 'idle'
      : const {1, 5, 8, 11, 14}.contains(_driveMode)
      ? 'busy10s'
      : 'busy2s';

  /// Capture Status in GR WORLD's 2-byte form (ble.md, Capture status row).
  List<int> get _captureStatus => [
    if (_capturing) BleCapturing.capturing.wire else BleCapturing.idle.wire,
    _countdown.wire,
  ];

  /// Pictures left on [storage]: the active storage holds
  /// [FakeCameraConfig.remainingPictures].
  int _remainOn(String storage) =>
      storage == _defaultStorage ? _remaining : _internalRemain;

  /// Storage Information, 14-byte entries as GR WORLD parses them (ble.md
  /// §Storage information): SD slot 1 when a card is in, then internal
  /// memory. The storage pictures go to comes first, since the 14-byte form
  /// has no active flag; a GR IV's order is \[unknown\].
  Uint8List _storageInformation() {
    BleStorageEntry entry(BleStorageType type, String storage, int seconds) =>
        BleStorageEntry(
          type: BleEnumValue.of(type),
          exists: true,
          locked: false,
          available: true,
          formatted: true,
          remainingPictures: _remainOn(storage),
          remainingVideoSeconds: seconds,
          fileType: 0,
        );
    return GrBleCatalog.storageInformation.codec.encode(
      BleStorageInformation([
        if (config.sdCard)
          entry(BleStorageType.sdSlot1, GrStorageId.sd, _sdRecordableTime),
        entry(
          BleStorageType.internalMemory,
          GrStorageId.internal,
          _internalRecordableTime,
        ),
      ], 14),
    );
  }

  /// A release is possible only with the camera on, in capture mode, idle
  /// and with room on the card. Refusing a busy camera, and the errCodes
  /// other than 412 (Image Sync's no-space code, remote-shooting.md §2.2),
  /// are \[design\].
  _Refusal? _releaseRefusal() {
    if (!_poweredOn) return (400, 'camera is off');
    if (_mode != BleOperationMode.capture.wire) {
      return (400, 'not in capture mode');
    }
    if (_releaseBusy) return (400, 'busy');
    if (_remaining <= 0) return (412, 'no space left');
    return null;
  }

  /// Starts a release (check [_releaseRefusal] first): a self-timer drive
  /// mode counts down first, every other drive mode takes one picture at
  /// once \[design\]. Returns the capture id the change events carry.
  String _release() {
    final id = '${++_captureIds}';
    final timer = _selfTimer;
    if (timer == null) {
      _startCapture(id);
      return id;
    }
    _countdown = BleCountdown.selfTimer;
    _captureStatusChanged();
    _releaseTimer = _after(timer, () {
      _releaseTimer = null;
      _countdown = BleCountdown.none;
      _startCapture(id);
    });
    return id;
  }

  void _startCapture(String id) {
    _capturing = true;
    _captureStatusChanged();
    _releaseTimer = _after(config.captureDelay, () {
      _releaseTimer = null;
      _finishCapture(id);
    });
  }

  /// The picture is on the card: Storage Information and Capture Status
  /// notify, and the WebSocket sees `storage` `add`, `capture` and an idle
  /// `cameraDirect` (remote-shooting.md §2.3; whether a GR IV sends the
  /// last two is \[unknown\]).
  void _finishCapture(String id) {
    final photo = _newPhoto();
    _photos.add(photo);
    if (_remaining > 0) _remaining--;
    _capturing = false;
    _notify(GrBleCatalog.storageInformation, _storageInformation());
    _notify(GrBleCatalog.captureStatus, _captureStatus);
    _pushStorage('add', photo, captureId: id);
    _push({
      'errCode': 200,
      'changed': 'capture',
      'captureId': id,
      'result': true,
    });
    _pushCameraDirect();
  }

  /// Cancels a running self-timer countdown (BLE Self Timer, HTTP
  /// `/v1/camera/shoot/cancel`): no picture is taken. False when none ran.
  bool _cancelSelfTimer() {
    if (_countdown == BleCountdown.none) return false;
    _cancel(_releaseTimer);
    _releaseTimer = null;
    _countdown = BleCountdown.none;
    _captureStatusChanged();
    return true;
  }

  /// Power off: a release in progress ends without a picture.
  void _abortRelease() {
    _cancel(_releaseTimer);
    _releaseTimer = null;
    _countdown = BleCountdown.none;
    _capturing = false;
  }

  void _captureStatusChanged() {
    _notify(GrBleCatalog.captureStatus, _captureStatus);
    _pushCameraDirect();
  }

  /// Image Sync's capture-state event (remote-shooting.md §2.3).
  void _pushCameraDirect() => _push({
    'errCode': 200,
    'changed': 'cameraDirect',
    'stateStill': _capturing ? 'busy' : 'idle',
    'stateMovie': 'idle',
    'countDown': _countDownText,
    'capturing': _capturing,
    'shootMode': _shootModes[_driveMode],
  });

  /// The next file on the active storage: the newest directory, the next
  /// number, the current exposure settings, and the bytes of the newest
  /// JPEG already on the card (any still when there is none).
  FakePhoto _newPhoto() {
    final storage = _defaultStorage;
    FakePhoto? template;
    for (final p in _photos.reversed) {
      if (p.extension == 'JPG') {
        template = p;
        break;
      }
      if (!p.isVideo) template ??= p;
    }
    var dir = '100RICOH';
    var number = 0;
    for (final p in _photos) {
      if (p.storage != storage) continue;
      if (p.dir.compareTo(dir) > 0) dir = p.dir;
      final n = int.tryParse(p.baseName.replaceAll(RegExp(r'\D'), ''));
      if (n != null && n > number) number = n;
    }
    final sv = _settings['sv']!;
    final photo = FakePhoto(
      dir,
      'R${(number + 1).toString().padLeft(7, '0')}.JPG',
      DateTime.now(),
      size: template?.size,
      storage: storage,
      // The served bytes are the template's, so is their orientation.
      orientation: template?.orientation ?? 1,
      av: _settings['av']!,
      tv: _settings['tv']!,
      sv: sv == 'auto' ? '200' : sv,
      xv: _settings['xv']!,
    );
    // The template may itself be a capture; its bytes are its source's.
    if (template != null) {
      _captureSources[photo] = _captureSources[template] ?? template;
    }
    return photo;
  }

  /// Drive Mode `0`–`15` (GR WORLD's decoder throws on other values,
  /// ble.md); notifies BLE and the WebSocket.
  void _setDriveMode(int wire) {
    if (wire == _driveMode) return;
    _driveMode = wire;
    _notify(GrBleCatalog.driveMode, [wire]);
    _push({'errCode': 200, 'changed': 'camera'});
  }

  /// Applies a `PUT /v1/params/camera` body; returns the refused pair, or
  /// null when every value was in its `<key>List` and has been set.
  /// Read-only keys (`exposureMode`: the dial decides, remote-shooting.md
  /// §4.2) and keys without a list are refused like unlisted values
  /// \[design\].
  String? _applyCameraParams(Map<String, String> params) {
    for (final MapEntry(:key, :value) in params.entries) {
      if (!(_listFor(key)?.contains(value) ?? false)) {
        return '$key=$value';
      }
    }
    for (final MapEntry(:key, :value) in params.entries) {
      if (key == 'shootMode') {
        _setDriveMode(_shootModes.indexOf(value));
      } else if (_settings[key] != value) {
        _settings[key] = value;
        _push({'errCode': 200, 'changed': 'camera'});
      }
    }
    return null;
  }
}

/// `key=value&…` as the camera reads it: nothing is decoded, so Image
/// Sync's literal `+` in `xv=+0.3` stays a plus (remote-shooting.md §0
/// item 2, §8). Null for a pair without `=` or with an empty key.
Map<String, String>? _keyValues(String body) {
  final pairs = <String, String>{};
  if (body.isEmpty) return pairs;
  for (final part in body.split('&')) {
    final eq = part.indexOf('=');
    if (eq <= 0) return null;
    pairs[part.substring(0, eq)] = part.substring(eq + 1);
  }
  return pairs;
}

/// `pos=X,Y` in integer percent 0–100 (remote-shooting.md §3.2), or null.
(int, int)? _focusPos(String text) {
  final m = RegExp(r'^(\d{1,3}),(\d{1,3})$').firstMatch(text);
  if (m == null) return null;
  final x = int.parse(m.group(1)!);
  final y = int.parse(m.group(2)!);
  if (x > 100 || y > 100) return null;
  return (x, y);
}
