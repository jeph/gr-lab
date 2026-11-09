import 'package:gr_protocol/src/http/json.dart';
import 'package:gr_protocol/src/http/request.dart';
import 'package:meta/meta.dart';

/// The `errCode` envelope every camera JSON response carries
/// (research/protocol/http-api.md §8). [raw] keeps the whole object, unknown keys
/// included.
class GrEnvelope {
  /// Wraps a decoded response object.
  new(this.raw);

  /// Complete response object as decoded.
  final Map<String, Object?> raw;

  JsonFields get _f => JsonFields(raw);

  /// `errCode`; `null` when absent or not numeric.
  int? get errCode => _f.integer('errCode');

  /// Error text the camera adds on failure, e.g. `Bad Request`.
  String? get errMsg => _f.string('errMsg');

  /// `detail.reason` (firmware routes, http-api.md §7).
  String? get reason => switch (_f.object('detail')) {
    final d? => JsonFields(d).string('reason'),
    null => null,
  };

  /// Whether [errCode] is 200, the camera's success code.
  bool get ok => errCode == 200;

  /// Typed access to any field.
  JsonFields get fields => _f;
}

/// One exposure/setting key from `/v1/props`: the current value `props[key]`
/// and the camera-offered choices `props[key + "List"]`
/// (research/protocol/remote-shooting.md §4.1).
final class GrSetting {
  /// Setting [key] with value [current] and choices [options].
  const new(this.key, this.current, this.options);

  /// `/v1/props` key, e.g. `av`, `tv`, `WBMode`.
  final String key;

  /// Current wire value (`props[key]`); `null` when absent or not a string.
  final String? current;

  /// `null` when the camera sent no `<key>List`.
  final List<String>? options;

  /// A value may only be written when the camera lists it. Without a list the
  /// camera's accepted values are unknown, so nothing is offered.
  bool offers(String value) => options?.contains(value) ?? false;

  /// Trace/log form.
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
  /// Wraps a decoded `/v1/props` object.
  new(super.raw);

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

  /// Model name, e.g. `RICOH GR IV`; Image Sync matches on the exact string.
  String? get model => fields.string('model');

  /// Maker name; not in GR WORLD's props parser, read by Image Sync's
  /// identity check.
  String? get manufacturer => fields.string('manufacturer');

  /// Camera serial number.
  String? get serialNo => fields.string('serialNo');

  /// Firmware version string.
  String? get firmwareVersion => fields.string('firmwareVersion');

  /// Camera's Wi-Fi MAC address as text.
  String? get macAddress => fields.string('macAddress');

  /// Camera's BLE device name.
  String? get bdName => fields.string('bdName');

  /// SSID of the camera's Wi-Fi access point.
  String? get ssid => fields.string('ssid');

  /// Wi-Fi passphrase (`key`). GR WORLD repairs a malformed value on GR II
  /// with an undecoded regex suffix (http-api.md §4.1 step 2, \[unknown\]);
  /// this getter returns the camera text unmodified.
  String? get wifiKey => fields.string('key');

  /// Fields Image Sync compares to tell whether the same camera answered.
  GrCameraIdentity get identity => GrCameraIdentity(
    model: model,
    serialNo: serialNo,
    bdName: bdName,
    manufacturer: manufacturer,
  );

  /// Battery charge in percent as the camera reports it.
  int? get battery => fields.integer('battery');

  /// One entry per storage (`in`, `sd1`).
  List<GrStorageInfo> get storages => [
    for (final s
        in fields.objects('storages') ?? const <Map<String, Object?>>[])
      GrStorageInfo(s),
  ];

  /// Camera state (remote-shooting.md §2.2–2.3, §4.1); values not
  /// established.
  String? get state => fields.string('state');

  /// Still capture state, as in the WebSocket `cameraDirect` event.
  String? get stateStill => fields.string('stateStill');

  /// Movie capture state; Image Sync waits for `busy` after a movie start.
  String? get stateMovie => fields.string('stateMovie');

  /// Self-timer state: `idle|busy2s|busy10s|busy12s|time`.
  String? get countDown => fields.string('countDown');

  /// Shots the current drive sequence will take; exact meaning unknown.
  int? get shotsTotal => fields.integer('shotsTotal');

  /// `still` or `movie`.
  String? get captureMode => fields.string('captureMode');

  /// Mode dial position, e.g. `P`, `AV`, `TV`, `M`; read-only.
  String? get exposureMode => fields.string('exposureMode');

  /// `"shift"` or `"hyper"` per Image Sync (remote-shooting.md §4.1).
  String? get exposureModeOption => fields.string('exposureModeOption');

  /// `capture`, `playback`, `bleStartup`, `powerOffTransfer` or `other`.
  String? get operationMode => fields.string('operationMode');

  /// Camera orientation; values not established.
  String? get cameraOrientation => fields.string('cameraOrientation');

  /// Camera clock as text; format not established.
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
@immutable
final class GrCameraIdentity {
  /// Identity from the given `/v1/props` fields.
  const new({this.model, this.serialNo, this.bdName, this.manufacturer});

  /// `/v1/props` `model`.
  final String? model;

  /// `/v1/props` `serialNo`.
  final String? serialNo;

  /// `/v1/props` `bdName` (BLE device name).
  final String? bdName;

  /// `/v1/props` `manufacturer`.
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

  /// Trace/log form; `manufacturer` only when present.
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
  /// Wraps one decoded `storages[]` object.
  new(this.raw);

  /// Complete entry as decoded.
  final Map<String, Object?> raw;

  /// Typed, non-throwing accessors over [raw].
  JsonFields get fields => JsonFields(raw);

  /// `in` or `sd1`.
  String? get name => fields.string('name');

  /// Whether the medium is present (an SD card inserted).
  bool? get equipped => fields.boolean('equipped');

  /// Whether the camera can write to it.
  bool? get writable => fields.boolean('writable');

  /// Whether it can be read now: equipped, accessible, formatted and
  /// without error. GR IV webapid refuses to list a storage that is not
  /// (research/protocol/http-api.md "Storage values").
  bool? get available => fields.boolean('available');

  /// Whether it is the storage the camera records to; inferred from the key.
  bool? get active => fields.boolean('active');

  /// Recording format, e.g. `jpeg`, `rawdng` (remote-shooting.md §5).
  String? get format => fields.string('format');

  /// Remaining shots; a number in GR WORLD, a string in Image Sync.
  int? get remain => fields.integer('remain');

  /// Remaining movie time as text; format not established.
  String? get recordableTime => fields.string('recordableTime');
}

/// `GET /v1/status/device` (http-api.md §1 row 2). GR WORLD calls it on GR II
/// only; the literal is absent from GR III/IV webapid strings
/// (firmware-protocol-inventory.md "Baseline mismatch").
final class GrDeviceStatus extends GrEnvelope {
  /// Wraps a decoded `/v1/status/device` object.
  new(super.raw);

  /// Battery charge in percent as the camera reports it.
  int? get battery => fields.integer('battery');

  /// One entry per storage (`in`, `sd1`).
  List<GrStorageInfo> get storages => [
    for (final s
        in fields.objects('storages') ?? const <Map<String, Object?>>[])
      GrStorageInfo(s),
  ];
}

/// `GET /v1/photos` page (http-api.md §2.1).
final class GrPhotoList extends GrEnvelope {
  /// Wraps a decoded `/v1/photos` object.
  new(super.raw);

  /// Folders on this page, in camera order.
  List<GrPhotoDir> get dirs => [
    for (final d in fields.objects('dirs') ?? const <Map<String, Object?>>[])
      GrPhotoDir(
        JsonFields(d).string('name') ?? '',
        JsonFields(d).strings('files') ?? const [],
      ),
  ];

  /// Files on this page; GR WORLD requests another page when it is 3000 or
  /// more (http-api.md §2.1).
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

/// One `dirs[]` entry of a `/v1/photos` page.
final class GrPhotoDir {
  /// Folder [name] holding [files].
  const new(this.name, this.files);

  /// Folder name, e.g. `100RICOH`.
  final String name;

  /// File names in the folder, e.g. `R0000001.JPG`.
  final List<String> files;
}

/// `GET /v1/photos/<dir>/<file>/info` (http-api.md §1 row 5; Image Sync
/// `BeanPhotoInfo`, remote-shooting.md §2.3).
final class GrPhotoInfo extends GrEnvelope {
  /// Wraps a decoded `/info` object.
  new(super.raw);

  /// Model that took the picture.
  String? get cameraModel => fields.string('cameraModel');

  /// Folder name, e.g. `100RICOH`.
  String? get dir => fields.string('dir');

  /// File name, e.g. `R0000001.JPG`.
  String? get file => fields.string('file');

  /// File size in bytes.
  int? get size => fields.integer('size');

  /// Capture date and time as text; format not established.
  String? get datetime => fields.string('datetime');

  /// Recording time as text; meaning and format not established.
  String? get recordedTime => fields.string('recordedTime');

  /// EXIF-style orientation 1–8 (connection-imagesync.md §4).
  int? get orientation => fields.integer('orientation');

  /// Aspect ratio as text, e.g. `3:2`; format inferred from the camera log
  /// vocabulary.
  String? get aspectRatio => fields.string('aspectRatio');

  /// Aperture in the `/v1/props` `av` notation, e.g. `2.8`.
  String? get av => fields.string('av');

  /// Shutter speed in the `/v1/props` `tv` notation (`1.250` = 1/250 s).
  String? get tv => fields.string('tv');

  /// ISO in the `/v1/props` `sv` notation.
  String? get sv => fields.string('sv');

  /// Exposure compensation in the `/v1/props` `xv` notation, e.g. `+0.3`.
  String? get xv => fields.string('xv');

  /// Location as text; format not established.
  String? get latLng => fields.string('latLng');

  /// GPS data as text; format not established.
  String? get gpsInfo => fields.string('gpsInfo');

  /// Movie length; unit not established.
  int? get duration => fields.integer('duration');

  /// Image or movie resolution as text; format not established.
  String? get resolution => fields.string('resolution');

  /// Image Sync `BeanPhotoInfo.captured`; meaning not established.
  bool? get captured => fields.boolean('captured');
}

/// `GET /v1/transfers?status=untransferred` (http-api.md §2.5).
final class GrTransferList extends GrEnvelope {
  /// Wraps a decoded `/v1/transfers` object.
  new(super.raw);

  /// Files the camera marked for transfer that have not been transferred.
  List<GrTransferItem> get transfers => [
    for (final t
        in fields.objects('transfers') ?? const <Map<String, Object?>>[])
      GrTransferItem(t),
  ];
}

/// One reserved-transfer entry `{index, filepath, size}`.
final class GrTransferItem {
  /// Wraps one decoded `transfers[]` object.
  new(this.raw);

  /// Complete entry as decoded.
  final Map<String, Object?> raw;

  /// Typed, non-throwing accessors over [raw].
  JsonFields get fields => JsonFields(raw);

  /// Camera's index for the entry (the `after=` cursor for the list).
  int? get index => fields.integer('index');

  /// As sent, possibly with a `?xs` suffix (http-api.md §2.5 step 3).
  String? get filepath => fields.string('filepath');

  /// `full` or `xs` per Image Sync's `TransferQuality` mapping
  /// (connection-imagesync.md §4); GR WORLD compares it with `xs`.
  String? get size => fields.string('size');

  /// [filepath] without any `?xs` suffix, or `null` when absent or malformed.
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
  /// Wraps a decoded shoot response.
  new(super.raw);

  /// Correlates with WebSocket `lens`/`capture`/`storage` events. `"0"` means
  /// no tracked capture (Image Sync ignores it).
  String? get captureId => fields.string('captureId');

  /// Whether the camera took the picture; inferred from the key name.
  bool? get captured => fields.boolean('captured');

  /// Whether autofocus locked before the shot; inferred from the key name.
  bool? get focused => fields.boolean('focused');
}

/// `POST /v1/lens/focus` response (Image Sync `BeanFocus`,
/// remote-shooting.md §3.1).
final class GrFocusResult extends GrEnvelope {
  /// Wraps a decoded focus response.
  new(super.raw);

  /// Non-empty: the final result arrives as WebSocket `lens` with this id.
  String? get captureId => fields.string('captureId');

  /// Whether the autofocus locked; used when [captureId] is empty. A GR IV
  /// HDF on fw 1.20 was observed to omit it.
  bool? get focused => fields.boolean('focused');

  /// Whether the focus search is still running; also omitted by the GR IV
  /// HDF on fw 1.20.
  bool? get focusRunning => fields.boolean('focusRunning');

  /// Focus point positions as `[x, y]` lists; units not established.
  List<List<int>> get focusCenters {
    final v = raw['focusCenters'];
    if (v is! List<Object?>) return const [];
    return [
      for (final e in v)
        if (e is List<Object?>) [for (final n in e) ?intValue(n)],
    ];
  }

  /// `[W, H]` of the centred AF area, percent of the frame.
  List<int>? get focusEffectiveArea => fields.ints('focusEffectiveArea');
}

/// `GET /v1/ping`. The firmware builds a `Pong` from the camera datetime
/// (firmware-protocol-inventory.md "Additional-route verification"); the
/// JSON key name is \[unknown\], so [datetime] reads the most likely key and
/// [raw] keeps everything.
final class GrPing extends GrEnvelope {
  /// Wraps a decoded `/v1/ping` object.
  new(super.raw);

  /// Camera clock, if the camera uses the `datetime` key.
  String? get datetime => fields.string('datetime');
}

/// `GET /v1/logs/camera?type=monthly_capture` (http-api.md §6). The nesting
/// of `dailyData` is \[inferred\], so it is exposed raw.
final class GrCameraLog extends GrEnvelope {
  /// Wraps a decoded camera log object.
  new(super.raw);

  /// Log type, `monthly_capture`.
  String? get type => fields.string('type');

  /// Month the log covers, `YYYY-MM`.
  String? get date => fields.string('date');

  /// Per-day still and movie statistics, undecoded.
  Object? get dailyData => raw['dailyData'];
}

/// Result of a streamed image download.
final class GrDownloadResult {
  /// Result fields as measured by the downloader.
  const new({
    required this.path,
    required this.size,
    required this.bytes,
    required this.contentLength,
    required this.contentType,
    required this.elapsed,
  });

  /// Image that was downloaded.
  final GrPhotoPath path;

  /// `size=` that was requested; `null` when none was sent.
  final GrImageSize? size;

  /// Bytes written to the sink.
  final int bytes;

  /// `Content-Length` header; GR WORLD treats its absence as an error, this
  /// client only uses it to detect truncation.
  final int? contentLength;

  /// `Content-Type` header of the response.
  final String? contentType;

  /// Time from request to the last byte.
  final Duration elapsed;

  /// Trace/log form.
  Map<String, Object?> toJson() => {
    'path': path.toString(),
    'size': size?.name,
    'bytes': bytes,
    'contentLength': contentLength,
    'contentType': contentType,
    'elapsedMs': elapsed.inMilliseconds,
  };
}
