import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';

/// Bytes the camera serves for [photo] at [size]: the original file for
/// [GrImageSize.full], a JPEG for every other size.
typedef FakeMediaSource = Future<Uint8List> Function(
  FakePhoto photo,
  GrImageSize size,
);

/// One file on the simulated card. A RAW+JPEG shot is two photos with the
/// same base name (`R0000231.JPG`, `R0000231.DNG`), as the camera lists it.
final class FakePhoto {
  FakePhoto(
    this.dir,
    this.file,
    this.dateTime, {
    this.size,
    this.videoLength,
    this.storage = GrStorageId.sd,
    this.orientation = 1,
    this.av = '2.8',
    this.tv = '1.250',
    this.sv = '200',
    this.xv = '0.0',
  }) : path = GrPhotoPath(dir, file);

  final String dir;
  final String file;
  final GrPhotoPath path;

  /// Capture time; `/info` reports it as camera-local wall time.
  final DateTime dateTime;

  /// Size `/info` reports for the full file. Null reports the length of the
  /// bytes the [FakeMediaSource] serves for [GrImageSize.full], so listings
  /// and downloads agree.
  final int? size;

  /// Movie length (`/info` `duration`); MOV files only.
  final Duration? videoLength;

  /// `in` (internal memory) or `sd1`.
  final String storage;

  /// EXIF orientation (1–8) that `/info` `orientation` reports; null leaves
  /// the field out. A GR stores every frame in sensor (landscape) layout:
  /// the full JPEG carries this value as its EXIF Orientation tag, while
  /// thumbnails and previews are unrotated JPEGs without the tag (as in the
  /// embedded previews of a GR IV HDF file). [FakeMediaSource]s serve them
  /// that way.
  final int? orientation;

  /// Held upright (orientation 5–8): shown taller than wide.
  bool get portrait => switch (orientation) {
    5 || 6 || 7 || 8 => true,
    _ => false,
  };

  /// Exposure as `/info` reports it, in the camera's own notation
  /// (`tv` `1.250` = 1/250 s, the form `/v1/props` uses).
  final String av;
  final String tv;
  final String sv;
  final String xv;

  /// Upper-case extension: `JPG`, `DNG` or `MOV`.
  String get extension => path.extension;
  bool get isVideo => extension == 'MOV';
  bool get isRaw => extension == 'DNG';

  /// File name without extension; equal for both halves of a RAW+JPEG pair.
  String get baseName {
    final dot = file.lastIndexOf('.');
    return dot < 0 ? file : file.substring(0, dot);
  }

  /// A realistic GR card: 40 shots over six days ending on [lastDay] in
  /// `100RICOH` and `101RICOH`, mixing JPEG-only, DNG-only and RAW+JPEG
  /// shots (58 files), three movies (lengths from [videoLengths]) and a few
  /// portrait frames, held both ways (orientations 6 and 8). Deterministic
  /// for a given [lastDay].
  static List<FakePhoto> defaultCard({
    DateTime? lastDay,
    List<Duration> videoLengths = const [
      Duration(seconds: 12),
      Duration(seconds: 31),
      Duration(seconds: 64),
    ],
    String storage = GrStorageId.sd,
  }) {
    final end = lastDay ?? DateTime(2026, 11, 5);
    final firstDay = DateTime(end.year, end.month, end.day - 5);
    // P = RAW+JPEG, J = JPEG only, D = DNG only, M = movie.
    const kinds = 'PPJPJDPPMJPPJDJPPJMPJPPDJPJPPJMDPJPPJPDJ';
    const perDay = [7, 6, 8, 5, 7, 7];
    const startHour = [9, 17, 12, 8, 15, 18];
    const avs = ['2.8', '4.0', '5.6', '8.0', '3.5'];
    const tvs = ['1.60', '1.125', '1.250', '1.500', '1.1000', '1.30'];
    const svs = ['200', '400', '800', '1600', '3200', '100'];
    const xvs = ['0.0', '-0.3', '-0.7', '+0.3', '0.0', '-1.0'];

    final photos = <FakePhoto>[];
    var shot = 0;
    var movie = 0;
    for (var day = 0; day < perDay.length; day++) {
      var at = DateTime(
        firstDay.year,
        firstDay.month,
        firstDay.day + day,
        startHour[day],
        4 + day * 3,
        11,
      );
      for (var i = 0; i < perDay[day]; i++) {
        final number = 231 + shot;
        final dir = shot < 20 ? '100RICOH' : '101RICOH';
        final base = 'R${number.toString().padLeft(7, '0')}';
        final kind = kinds[shot];
        FakePhoto make(String ext, {Duration? length}) => FakePhoto(
          dir,
          '$base.$ext',
          at,
          videoLength: length,
          storage: storage,
          orientation: kind == 'M' || shot % 5 != 3
              ? 1
              : shot % 10 == 3
              ? 6
              : 8,
          av: avs[shot % avs.length],
          tv: tvs[shot % tvs.length],
          sv: svs[shot % svs.length],
          xv: xvs[shot % xvs.length],
        );
        switch (kind) {
          case 'P':
            photos
              ..add(make('JPG'))
              ..add(make('DNG'));
          case 'J':
            photos.add(make('JPG'));
          case 'D':
            photos.add(make('DNG'));
          default:
            photos.add(
              make('MOV', length: videoLengths[movie % videoLengths.length]),
            );
            movie++;
        }
        shot++;
        at = at.add(Duration(minutes: 3 + (shot * 7) % 23, seconds: shot * 13));
      }
    }
    return photos;
  }

  @override
  String toString() => '$storage:$dir/$file';
}

/// Identity, timing and failure injection for a [FakeGrCamera].
///
/// Delays default to small values so UIs show their loading states without
/// slowing tests; tests that need speed pass [Duration.zero].
final class FakeCameraConfig {
  const FakeCameraConfig({
    this.model = 'RICOH GR IV',
    this.serial = '1234567',
    this.firmware = '1.20',
    this.ssid = 'GR_H0053A8',
    this.passphrase = 'abcd1234',
    this.bluetoothName = 'GR_H0053A9',
    this.deviceId = '00:00:5E:00:53:A9',
    this.poweredOn = true,
    this.executePairingOpen = false,
    this.bonded = false,
    this.openExecutePairingOnScan = false,
    this.autoConfirmPairing,
    this.battery = 82,
    this.sdCard = true,
    this.photos,
    this.pageSize = grWorldPhotoPageSize,
    this.advertisingInterval = const Duration(milliseconds: 100),
    this.connectDelay = const Duration(milliseconds: 100),
    this.bleLatency = const Duration(milliseconds: 10),
    this.wakeDelay = const Duration(seconds: 1),
    this.wakeKeepsLink = false,
    this.wlanOnDelay = const Duration(milliseconds: 500),
    this.joinDelay = const Duration(milliseconds: 500),
    this.httpLatency = const Duration(milliseconds: 30),
    this.downloadBytesPerSecond,
    this.refusePairing = false,
    this.dropWifiAfter,
    this.unreachable = false,
    this.reportsWifiLoss = true,
    this.cutDownloadsAfterBytes,
    this.previewFailures = 0,
    this.brokenPreviews = 0,
    this.remainingPictures = 1234,
    this.exposureMode = BleExposureMode.av,
    this.captureDelay = const Duration(milliseconds: 300),
    this.focusTime = const Duration(milliseconds: 300),
    this.lensBeforeFocusAnswer = false,
    this.announcesDialChanges = true,
    this.selfTimerScale = 1.0,
  });

  /// `/v1/props` `model` and the Camera Information model name; must be a
  /// [GrModel] string (it selects the advertised model code and GATT set).
  final String model;
  final String serial;
  final String firmware;
  final String ssid;
  final String passphrase;

  /// Advertised name and Bluetooth Device Name characteristic (`bdName`).
  final String bluetoothName;

  /// Platform peripheral id the camera advertises under (an Android-style
  /// MAC from the documentation range).
  final String deviceId;

  /// Initial power state; off is the BT-only state that advertises power
  /// `00` and reads Operation Mode `02` (bleStartup).
  final bool poweredOn;

  /// Initial state of the camera's Execute Pairing screen.
  final bool executePairingOpen;

  /// The phone already holds a bond with this camera (a pairing from an
  /// earlier run).
  final bool bonded;

  /// Demo: the simulated user turns the camera on and opens Execute
  /// Pairing as soon as the app starts scanning, as the pairing screen asks.
  final bool openExecutePairingOnScan;

  /// When set, the simulated user presses OK on the camera this long after
  /// the phone starts bonding. Null leaves it to [FakeGrCamera.confirmPairing]
  /// and [FakeGrCamera.rejectPairing].
  final Duration? autoConfirmPairing;

  /// Battery percentage (`/v1/props` `battery`, BLE Battery Level).
  final int battery;

  /// An SD card is inserted: `/v1/props` lists `sd1` next to `in`, and
  /// listings without `storage` read it.
  final bool sdCard;

  /// Card contents; null means [FakePhoto.defaultCard].
  final List<FakePhoto>? photos;

  /// Files per `/v1/photos` page when the request has no `limit`.
  final int pageSize;
  final Duration advertisingInterval;
  final Duration connectDelay;

  /// Added to every GATT operation.
  final Duration bleLatency;

  /// After the power-on write the camera restarts into its main firmware
  /// after this delay. Unless [wakeKeepsLink], the link stops answering
  /// meanwhile and then drops (the first-link drop, GR IV: ~5.5 s).
  final Duration wakeDelay;

  /// The power-on write turns the camera on and the link stays up and
  /// answering (GR IV HDF, 2026-11-08, write on a 3 s old link).
  final bool wakeKeepsLink;

  /// From the WLAN-on write until the access point can be joined.
  final Duration wlanOnDelay;

  /// Association time once the access point is up (GR IV on a Mac: 16 s).
  final Duration joinDelay;

  /// Added before every HTTP response.
  final Duration httpLatency;

  /// Throttles image and movie bodies; null sends them at loopback speed.
  final int? downloadBytesPerSecond;

  /// The camera rejects the pairing request even on Execute Pairing.
  final bool refusePairing;

  /// The camera's access point goes down this long after the first
  /// successful join (once). A WLAN-on write brings it back.
  final Duration? dropWifiAfter;

  /// Out of range: no advertisements, connects time out, Wi-Fi absent and
  /// HTTP connections are dropped.
  final bool unreachable;

  /// The phone side reports a joined access point going down at once
  /// ([WifiNetworkControl.lost]), as Android does; false leaves the loss
  /// to liveness polling, as on iOS.
  final bool reportsWifiLoss;

  /// Full-size downloads stop after this many body bytes and the socket is
  /// closed, as when Wi-Fi drops mid-transfer.
  final int? cutDownloadsAfterBytes;

  /// The first this many thumbnail, preview and `xs` requests for each
  /// file and size answer HTTP 503, as a busy camera may; later ones
  /// succeed.
  final int previewFailures;

  /// After [previewFailures], this many more of those requests answer 200
  /// with a JPEG start and nothing else, which no decoder can show.
  final int brokenPreviews;

  /// Pictures the active storage still has room for: `/v1/props`
  /// `storages[].remain` and the BLE Storage Information entry's
  /// remainingPictures. Each capture takes one; at 0 releases are refused.
  final int remainingPictures;

  /// Initial position of the mode dial (BLE Shooting Mode, `/v1/props`
  /// `exposureMode`); [FakeGrCamera.setExposureMode] turns it.
  final BleExposureMode exposureMode;

  /// From the release (or the end of a self-timer countdown) until the
  /// picture is on the card.
  final Duration captureDelay;

  /// From a `POST /v1/lens/focus` answer until its `lens` change. On a GR
  /// IV HDF (2026-11-08) live view stalled 0.9-2 s per focus.
  final Duration focusTime;

  /// The `lens` change of a focus is sent before the answer to its
  /// `POST /v1/lens/focus` (50 ms before). They travel on different
  /// connections, so a client cannot rely on their order.
  final bool lensBeforeFocusAnswer;

  /// Turning the mode dial pushes a `camera` change over the WebSocket as
  /// well as the BLE Shooting Mode notification. Whether the GR IV pushes
  /// it is [unknown]; false leaves the BLE notification alone.
  final bool announcesDialChanges;

  /// Scales the 2 s and 10 s self-timer countdowns; tests pass small
  /// values.
  final double selfTimerScale;
}
