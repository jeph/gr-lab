import 'json.dart';
import 'request.dart';

/// The `errCode` envelope every camera JSON response carries
/// (docs/protocol/http-api.md §8). [raw] keeps the whole object, unknown keys
/// included.
class GrEnvelope {
  GrEnvelope(this.raw);

  final Map<String, Object?> raw;

  JsonFields get _f => JsonFields(raw);

  /// `errCode`; `null` when absent or not numeric.
  int? get errCode => _f.integer('errCode');

  String? get errMsg => _f.string('errMsg');

  /// `detail.reason` (firmware routes, http-api.md §7).
  String? get reason => switch (_f.object('detail')) {
    final d? => JsonFields(d).string('reason'),
    null => null,
  };

  bool get ok => errCode == 200;

  /// Typed access to any field.
  JsonFields get fields => _f;
}

/// One exposure/setting key from `/v1/props`: the current value `props[key]`
/// and the camera-offered choices `props[key + "List"]`
/// (docs/protocol/remote-shooting.md §4.1).
final class GrSetting {
  const GrSetting(this.key, this.current, this.options);

  final String key;
  final String? current;

  /// `null` when the camera sent no `<key>List`.
  final List<String>? options;

  /// A value may only be written when the camera lists it. Without a list the
  /// camera's accepted values are unknown, so nothing is offered.
  bool offers(String value) => options?.contains(value) ?? false;

  Map<String, Object?> toJson() => {
    'key': key,
    'current': current,
    if (options != null) 'options': options,
  };
}

/// `GET /v1/props` (also the response shape of `PUT /v1/params/camera`).
///
/// Keys follow Image Sync's `BeanProps` and GR WORLD's props parser
/// (http-api.md §1 row 1, remote-shooting.md §4.1); any other key stays in
/// [raw].
final class GrProps extends GrEnvelope {
  GrProps(super.raw);

  /// Setting keys Image Sync reads with a `<key>List`
  /// (remote-shooting.md §4.1, `BeanProps.java`).
  static const settingKeys = [
    'av',
    'tv',
    'sv',
    'xv',
    'WBMode',
    'effect',
    'exposureMode',
    'stillSize',
    'stillFormat',
    'movieSize',
    'meteringMode',
    'focusMode',
    'focusSetting',
    'shootMode',
    'captureMode',
    'operationMode',
    'channel',
    'flashMode',
    'flashxv',
    'filter',
    'zoomLevel',
    'cameraMovieSetting',
  ];

  // Identity.
  String? get model => fields.string('model');
  String? get manufacturer => fields.string('manufacturer');
  String? get serialNo => fields.string('serialNo');
  String? get firmwareVersion => fields.string('firmwareVersion');
  String? get macAddress => fields.string('macAddress');
  String? get bdName => fields.string('bdName');
  String? get ssid => fields.string('ssid');

  /// Wi-Fi passphrase (`key`). GR WORLD repairs a malformed value on GR II
  /// with an undecoded regex suffix (http-api.md §4.1 step 2, [unknown]);
  /// this getter returns the camera text unmodified.
  String? get wifiKey => fields.string('key');

  GrCameraIdentity get identity => GrCameraIdentity(
    model: model,
    serialNo: serialNo,
    bdName: bdName,
    manufacturer: manufacturer,
  );

  // Status.
  int? get battery => fields.integer('battery');
  List<GrStorageInfo> get storages => [
    for (final s
        in fields.objects('storages') ?? const <Map<String, Object?>>[])
      GrStorageInfo(s),
  ];

  // State (remote-shooting.md §2.2–2.3, §4.1).
  String? get state => fields.string('state');
  String? get stateStill => fields.string('stateStill');
  String? get stateMovie => fields.string('stateMovie');
  String? get countDown => fields.string('countDown');
  int? get shotsTotal => fields.integer('shotsTotal');
  String? get captureMode => fields.string('captureMode');
  String? get exposureMode => fields.string('exposureMode');

  /// `"shift"` or `"hyper"` per Image Sync (remote-shooting.md §4.1).
  String? get exposureModeOption => fields.string('exposureModeOption');
  String? get operationMode => fields.string('operationMode');
  String? get cameraOrientation => fields.string('cameraOrientation');
  String? get datetime => fields.string('datetime');

  /// `[W, H]` in percent of the frame (remote-shooting.md §3.2).
  List<int>? get focusEffectiveArea => fields.ints('focusEffectiveArea');

  /// The setting [key] with its current value and `<key>List`, or `null` when
  /// the camera sent neither.
  GrSetting? setting(String key) {
    final current = fields.string(key);
    final options = fields.strings('${key}List');
    if (current == null && options == null && !raw.containsKey(key)) {
      return null;
    }
    return GrSetting(key, current, options);
  }

  /// Every key that has a `<key>List`, plus the known [settingKeys] present.
  Map<String, GrSetting> get settings {
    final keys = <String>{
      for (final k in settingKeys)
        if (raw.containsKey(k) || raw.containsKey('${k}List')) k,
      for (final k in raw.keys)
        if (k.length > 4 && k.endsWith('List') && raw[k] is List<Object?>)
          k.substring(0, k.length - 4),
    };
    return {for (final k in keys) k: ?setting(k)};
  }

  /// Whether the camera lists [value] for [key] (`<key>List`).
  bool offers(String key, String value) => setting(key)?.offers(value) ?? false;
}

/// Identity fields Image Sync's liveness check compares on every poll
/// (connection-imagesync.md §2.2, `isSameCameraInfo`).
final class GrCameraIdentity {
  const GrCameraIdentity({
    this.model,
    this.serialNo,
    this.bdName,
    this.manufacturer,
  });

  final String? model;
  final String? serialNo;
  final String? bdName;
  final String? manufacturer;

  @override
  bool operator ==(Object other) =>
      other is GrCameraIdentity &&
      other.model == model &&
      other.serialNo == serialNo &&
      other.bdName == bdName &&
      other.manufacturer == manufacturer;

  @override
  int get hashCode => Object.hash(model, serialNo, bdName, manufacturer);

  Map<String, Object?> toJson() => {
    'model': model,
    'serialNo': serialNo,
    'bdName': bdName,
    if (manufacturer != null) 'manufacturer': manufacturer,
  };

  @override
  String toString() => '$model serial=$serialNo bdName=$bdName';
}

/// One `storages[]` entry (GR WORLD `0x56bb1c`, Image Sync `BeanStorage`).
final class GrStorageInfo {
  GrStorageInfo(this.raw);

  final Map<String, Object?> raw;
  JsonFields get fields => JsonFields(raw);

  /// `in` or `sd1`.
  String? get name => fields.string('name');
  bool? get equipped => fields.boolean('equipped');
  bool? get writable => fields.boolean('writable');
  bool? get available => fields.boolean('available');
  bool? get active => fields.boolean('active');

  /// Recording format, e.g. `jpeg`, `rawdng` (remote-shooting.md §5).
  String? get format => fields.string('format');

  /// Remaining shots; a number in GR WORLD, a string in Image Sync.
  int? get remain => fields.integer('remain');
  String? get recordableTime => fields.string('recordableTime');
}

/// `GET /v1/status/device` (http-api.md §1 row 2). GR WORLD calls it on GR II
/// only; the literal is absent from GR III/IV webapid strings
/// (firmware-protocol-inventory.md "Baseline mismatch").
final class GrDeviceStatus extends GrEnvelope {
  GrDeviceStatus(super.raw);

  int? get battery => fields.integer('battery');
  List<GrStorageInfo> get storages => [
    for (final s
        in fields.objects('storages') ?? const <Map<String, Object?>>[])
      GrStorageInfo(s),
  ];
}

/// `GET /v1/photos` page (http-api.md §2.1).
final class GrPhotoList extends GrEnvelope {
  GrPhotoList(super.raw);

  List<GrPhotoDir> get dirs => [
    for (final d in fields.objects('dirs') ?? const <Map<String, Object?>>[])
      GrPhotoDir(
        JsonFields(d).string('name') ?? '',
        JsonFields(d).strings('files') ?? const [],
      ),
  ];

  int get fileCount => dirs.fold(0, (n, d) => n + d.files.length);

  /// Every `dir/file` on this page. Entries that are not valid photo paths
  /// are skipped (they remain in [raw]).
  List<GrPhotoPath> get paths => [
    for (final d in dirs)
      for (final f in d.files) ?GrPhotoPath.tryParseCamera('${d.name}/$f'),
  ];

  /// `lastDir.name/lastDir.files.last`, the `after=` cursor both apps use.
  GrPhotoPath? get last {
    for (final d in dirs.reversed) {
      if (d.files.isNotEmpty) {
        return GrPhotoPath.tryParseCamera('${d.name}/${d.files.last}');
      }
    }
    return null;
  }
}

final class GrPhotoDir {
  const GrPhotoDir(this.name, this.files);
  final String name;
  final List<String> files;
}

/// `GET /v1/photos/<dir>/<file>/info` (http-api.md §1 row 5; Image Sync
/// `BeanPhotoInfo`, remote-shooting.md §2.3).
final class GrPhotoInfo extends GrEnvelope {
  GrPhotoInfo(super.raw);

  String? get cameraModel => fields.string('cameraModel');
  String? get dir => fields.string('dir');
  String? get file => fields.string('file');
  int? get size => fields.integer('size');
  String? get datetime => fields.string('datetime');
  String? get recordedTime => fields.string('recordedTime');

  /// EXIF-style orientation 1–8 (connection-imagesync.md §4).
  int? get orientation => fields.integer('orientation');
  String? get aspectRatio => fields.string('aspectRatio');
  String? get av => fields.string('av');
  String? get tv => fields.string('tv');
  String? get sv => fields.string('sv');
  String? get xv => fields.string('xv');
  String? get latLng => fields.string('latLng');
  String? get gpsInfo => fields.string('gpsInfo');
  int? get duration => fields.integer('duration');
  String? get resolution => fields.string('resolution');
  bool? get captured => fields.boolean('captured');
}

/// `GET /v1/transfers?status=untransferred` (http-api.md §2.5).
final class GrTransferList extends GrEnvelope {
  GrTransferList(super.raw);

  List<GrTransferItem> get transfers => [
    for (final t
        in fields.objects('transfers') ?? const <Map<String, Object?>>[])
      GrTransferItem(t),
  ];
}

/// One reserved-transfer entry `{index, filepath, size}`.
final class GrTransferItem {
  GrTransferItem(this.raw);

  final Map<String, Object?> raw;
  JsonFields get fields => JsonFields(raw);

  int? get index => fields.integer('index');

  /// As sent, possibly with a `?xs` suffix (http-api.md §2.5 step 3).
  String? get filepath => fields.string('filepath');

  /// `full` or `xs` per Image Sync's `TransferQuality` mapping
  /// (connection-imagesync.md §4); GR WORLD compares it with `xs`.
  String? get size => fields.string('size');

  GrPhotoPath? get path =>
      filepath == null ? null : GrPhotoPath.tryParseCamera(filepath!);

  /// The size both apps download: `xs` only when requested and the file is a
  /// JPG; everything else full (http-api.md §2.4).
  GrImageSize get downloadSize {
    final xs = size == 'xs' || (filepath?.contains('?xs') ?? false);
    return xs && path?.extension == 'JPG' ? GrImageSize.xs : GrImageSize.full;
  }
}

/// `POST /v1/camera/shoot` response (Image Sync `BeanShoot`,
/// remote-shooting.md §2.2).
final class GrShootResult extends GrEnvelope {
  GrShootResult(super.raw);

  /// Correlates with WebSocket `lens`/`capture`/`storage` events. `"0"` means
  /// no tracked capture (Image Sync ignores it).
  String? get captureId => fields.string('captureId');
  bool? get captured => fields.boolean('captured');
  bool? get focused => fields.boolean('focused');
}

/// `POST /v1/lens/focus` response (Image Sync `BeanFocus`,
/// remote-shooting.md §3.1).
final class GrFocusResult extends GrEnvelope {
  GrFocusResult(super.raw);

  /// Non-empty: the final result arrives as WebSocket `lens` with this id.
  String? get captureId => fields.string('captureId');
  bool? get focused => fields.boolean('focused');
  bool? get focusRunning => fields.boolean('focusRunning');

  List<List<int>> get focusCenters {
    final v = raw['focusCenters'];
    if (v is! List<Object?>) return const [];
    return [
      for (final e in v)
        if (e is List<Object?>) [for (final n in e) ?intValue(n)],
    ];
  }

  List<int>? get focusEffectiveArea => fields.ints('focusEffectiveArea');
}

/// `GET /v1/ping`. The firmware builds a `Pong` from the camera datetime
/// (firmware-protocol-inventory.md "Additional-route verification"); the
/// JSON key name is [unknown], so [datetime] reads the most likely key and
/// [raw] keeps everything.
final class GrPing extends GrEnvelope {
  GrPing(super.raw);

  String? get datetime => fields.string('datetime');
}

/// `GET /v1/logs/camera?type=monthly_capture` (http-api.md §6). The nesting
/// of `dailyData` is [inferred], so it is exposed raw.
final class GrCameraLog extends GrEnvelope {
  GrCameraLog(super.raw);

  String? get type => fields.string('type');
  String? get date => fields.string('date');
  Object? get dailyData => raw['dailyData'];
}

/// Result of a streamed image download.
final class GrDownloadResult {
  const GrDownloadResult({
    required this.path,
    required this.size,
    required this.bytes,
    required this.contentLength,
    required this.contentType,
    required this.elapsed,
  });

  final GrPhotoPath path;
  final GrImageSize? size;

  /// Bytes written to the sink.
  final int bytes;

  /// `Content-Length` header; GR WORLD treats its absence as an error, this
  /// client only uses it to detect truncation.
  final int? contentLength;
  final String? contentType;
  final Duration elapsed;

  Map<String, Object?> toJson() => {
    'path': path.toString(),
    'size': size?.name,
    'bytes': bytes,
    'contentLength': contentLength,
    'contentType': contentType,
    'elapsedMs': elapsed.inMilliseconds,
  };
}
