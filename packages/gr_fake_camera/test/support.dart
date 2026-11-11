import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// Polls [condition] until it holds; fails after 5 s.
Future<void> until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) fail('timed out');
    await Future<void>.delayed(ms(2));
  }
}

/// Camera timings shrunk so whole sessions run in well under a second.
FakeCameraConfig fastConfig({
  bool poweredOn = true,
  bool executePairingOpen = false,
  bool bonded = false,
  bool openExecutePairingOnScan = false,
  Duration? autoConfirmPairing,
  bool refusePairing = false,
  Duration? dropWifiAfter,
  bool unreachable = false,
  int? cutDownloadsAfterBytes,
  int? downloadBytesPerSecond,
  List<FakePhoto>? photos,
  bool sdCard = true,
  Duration? joinDelay,
  bool reportsWifiLoss = true,
  bool answersPing = true,
  bool wakeKeepsLink = false,
  Duration? firstOffLinkDrop,
  int remainingPictures = 1234,
  double selfTimerScale = 0.01,
}) => FakeCameraConfig(
  remainingPictures: remainingPictures,
  selfTimerScale: selfTimerScale,
  captureDelay: ms(20),
  focusTime: ms(150),
  poweredOn: poweredOn,
  wakeKeepsLink: wakeKeepsLink,
  firstOffLinkDrop: firstOffLinkDrop,
  executePairingOpen: executePairingOpen,
  bonded: bonded,
  openExecutePairingOnScan: openExecutePairingOnScan,
  autoConfirmPairing: autoConfirmPairing,
  refusePairing: refusePairing,
  dropWifiAfter: dropWifiAfter,
  unreachable: unreachable,
  reportsWifiLoss: reportsWifiLoss,
  answersPing: answersPing,
  cutDownloadsAfterBytes: cutDownloadsAfterBytes,
  downloadBytesPerSecond: downloadBytesPerSecond,
  photos: photos,
  sdCard: sdCard,
  advertisingInterval: ms(5),
  connectDelay: Duration.zero,
  bleLatency: Duration.zero,
  wakeDelay: ms(60),
  wlanOnDelay: ms(40),
  joinDelay: joinDelay ?? ms(10),
  httpLatency: Duration.zero,
);

/// Session options scaled to [fastConfig]: quick liveness loss and
/// recovery instead of Image Sync's 40 s.
const fastSessionOptions = GrSessionOptions(
  scanTimeout: Duration(seconds: 1),
  bleConnectTimeout: Duration(seconds: 1),
  joinTimeout: Duration(seconds: 2),
  joinRetryDelay: Duration(milliseconds: 20),
  wakeSettle: Duration(milliseconds: 200),
  powerOffGuard: Duration(milliseconds: 40),
  verifyTimeout: Duration(seconds: 2),
  verifyProbeTimeout: Duration(seconds: 1),
  livenessInterval: Duration(milliseconds: 20),
  livenessFailureThreshold: 2,
  livenessLossAfter: Duration(milliseconds: 100),
  wifiRecoveryDelays: [Duration(milliseconds: 20)],
  maxWifiRecoveryAttempts: 4,
  bleReconnectDelays: [Duration(milliseconds: 20)],
  maxBleReconnectAttempts: 3,
  bleLostAfter: Duration(milliseconds: 500),
);

/// A started camera; closed by the caller.
Future<FakeGrCamera> startCamera(
  FakeCameraConfig config, {
  FakeMediaSource? media,
}) async {
  final camera = FakeGrCamera(config: config, media: media ?? syntheticMedia());
  await camera.startHttp();
  return camera;
}

GrSession sessionFor(
  FakeGrCamera camera, {
  GrSessionOptions options = fastSessionOptions,
}) => GrSession(
  transport: camera.transport,
  wifi: camera.wifi,
  options: options,
  httpFactory: camera.httpClient,
);
