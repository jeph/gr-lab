import 'package:gr_protocol/src/ble/codecs.dart';
import 'package:gr_protocol/src/wifi/network_control.dart';

// Wire values come from GR WORLD 2.0.0 (research/protocol/ble.md) and from
// Image Sync's decrypted `def_ble.yaml` (research/protocol/ble-imagesync.md §1).
// Values outside these tables are kept raw by BleEnumValue.

/// Operation Request byte 0 (ble-imagesync.md §1, Shooting Service).
enum BleOperationCode implements BleWireEnum {
  /// No operation.
  nop(0),

  /// Starts (or, when sent again, toggles off) the requested operation.
  start(1),

  /// Documented but never sent by Image Sync: it toggles with `start`
  /// instead (ble-imagesync.md §4.5).
  stop(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Operation Request byte 1.
enum BleOperationParameter implements BleWireEnum {
  /// No autofocus requested (`01 00` starts or toggles capture).
  noAf(0),

  /// Autofocus requested; with `nop` it focuses only (`00 01`).
  af(1),

  /// Green-button function; Image Sync `applyGreenButton` writes
  /// `00 02`.
  greenButton(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Drive Mode (`B29E6DE3`). 0–15 are the GR modes decoded by GR WORLD;
/// 16–65 are the shared PENTAX table from `def_ble.yaml` (remote = IR
/// remote control; 12 s self-timer variants are PENTAX bodies).
enum BleDriveMode implements BleWireEnum {
  /// Single frame.
  single(0),

  /// Single frame, 10 s self-timer.
  selfTimer10s(1),

  /// Single frame, 2 s self-timer.
  selfTimer2s(2),

  /// Continuous.
  continuous(3),

  /// Exposure bracketing.
  bracket(4),

  /// Exposure bracketing, 10 s self-timer.
  bracketSelfTimer10s(5),

  /// Exposure bracketing, 2 s self-timer.
  bracketSelfTimer2s(6),

  /// Multiple exposure.
  multipleExposure(7),

  /// Multiple exposure, 10 s self-timer.
  multipleExposureSelfTimer10s(8),

  /// Multiple exposure, 2 s self-timer.
  multipleExposureSelfTimer2s(9),

  /// Interval shooting.
  interval(10),

  /// Interval shooting, 10 s self-timer.
  intervalSelfTimer10s(11),

  /// Interval shooting, 2 s self-timer.
  intervalSelfTimer2s(12),

  /// Interval composite.
  intervalComposite(13),

  /// Interval composite, 10 s self-timer.
  intervalCompositeSelfTimer10s(14),

  /// Interval composite, 2 s self-timer.
  intervalCompositeSelfTimer2s(15),

  /// Single frame, IR remote.
  singleRemote(16),

  /// Single frame, IR remote, 3 s delay.
  singleRemote3s(17),

  /// Continuous high speed.
  continuousHigh(18),

  /// Continuous high speed, 12 s self-timer.
  continuousHighSelfTimer12s(19),

  /// Continuous high speed, 2 s self-timer.
  continuousHighSelfTimer2s(20),

  /// Continuous high speed, IR remote.
  continuousHighRemote(21),

  /// Continuous high speed, IR remote, 3 s delay.
  continuousHighRemote3s(22),

  /// Continuous medium speed.
  continuousMedium(23),

  /// Continuous medium speed, 12 s self-timer.
  continuousMediumSelfTimer12s(24),

  /// Continuous medium speed, 2 s self-timer.
  continuousMediumSelfTimer2s(25),

  /// Continuous medium speed, IR remote.
  continuousMediumRemote(26),

  /// Continuous medium speed, IR remote, 3 s delay.
  continuousMediumRemote3s(27),

  /// Continuous low speed.
  continuousLow(28),

  /// Continuous low speed, 12 s self-timer.
  continuousLowSelfTimer12s(29),

  /// Continuous low speed, 2 s self-timer.
  continuousLowSelfTimer2s(30),

  /// Continuous low speed, IR remote.
  continuousLowRemote(31),

  /// Continuous low speed, IR remote, 3 s delay.
  continuousLowRemote3s(32),

  /// Exposure bracketing, IR remote.
  bracketRemote(33),

  /// Exposure bracketing, IR remote, 3 s delay.
  bracketRemote3s(34),

  /// Multiple exposure, IR remote.
  multipleExposureRemote(35),

  /// Multiple exposure, IR remote, 3 s delay.
  multipleExposureRemote3s(36),

  /// Interval shooting, IR remote.
  intervalRemote(37),

  /// Interval shooting, IR remote, 3 s delay.
  intervalRemote3s(38),

  /// Interval composite, IR remote.
  intervalCompositeRemote(39),

  /// Interval composite, IR remote, 3 s delay.
  intervalCompositeRemote3s(40),

  /// Interval movie.
  intervalMovie(41),

  /// Interval movie, 12 s self-timer.
  intervalMovieSelfTimer12s(42),

  /// Interval movie, 2 s self-timer.
  intervalMovieSelfTimer2s(43),

  /// Interval movie, IR remote.
  intervalMovieRemote(44),

  /// Interval movie, IR remote, 3 s delay.
  intervalMovieRemote3s(45),

  /// Motion bracketing.
  motionBracket(46),

  /// Motion bracketing, 12 s self-timer.
  motionBracketSelfTimer12s(47),

  /// Motion bracketing, 2 s self-timer.
  motionBracketSelfTimer2s(48),

  /// Motion bracketing, IR remote.
  motionBracketRemote(49),

  /// Motion bracketing, IR remote, 3 s delay.
  motionBracketRemote3s(50),

  /// Depth-of-field bracketing.
  depthOfFieldBracket(51),

  /// Depth-of-field bracketing, 12 s self-timer.
  depthOfFieldBracketSelfTimer12s(52),

  /// Depth-of-field bracketing, 2 s self-timer.
  depthOfFieldBracketSelfTimer2s(53),

  /// Depth-of-field bracketing, IR remote.
  depthOfFieldBracketRemote(54),

  /// Depth-of-field bracketing, IR remote, 3 s delay.
  depthOfFieldBracketRemote3s(55),

  /// Mirror-up.
  mirrorUp(56),

  /// Mirror-up, 12 s self-timer.
  mirrorUpSelfTimer12s(57),

  /// Mirror-up, 2 s self-timer.
  mirrorUpSelfTimer2s(58),

  /// Mirror-up, IR remote.
  mirrorUpRemote(59),

  /// Mirror-up, IR remote, 3 s delay.
  mirrorUpRemote3s(60),

  /// Star stream.
  starStream(61),

  /// Star stream, 12 s self-timer.
  starStreamSelfTimer12s(62),

  /// Star stream, 2 s self-timer.
  starStreamSelfTimer2s(63),

  /// Star stream, IR remote.
  starStreamRemote(64),

  /// Star stream, IR remote, 3 s delay.
  starStreamRemote3s(65);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;

  /// True for the 10 s self-timer variants that GR WORLD's shutter handler
  /// cancels instead of releasing (ble.md §Remote shooting).
  bool get isSelfTimer10s => const {1, 5, 8, 11, 14}.contains(wire);
}

/// Shooting Mode byte 0 (exposure program). GR WORLD decodes 0–6 and 19;
/// Image Sync lists the full shared table.
enum BleExposureMode implements BleWireEnum {
  /// Program AE.
  p(0),

  /// Aperture priority.
  av(1),

  /// Shutter priority.
  tv(2),

  /// Manual exposure.
  m(3),

  /// Bulb.
  b(4),

  /// Bulb timer.
  bt(5),

  /// Time exposure.
  t(6),

  /// Full auto.
  auto(7),

  /// TAv (Image Sync table name).
  tav(8),

  /// Sv (Image Sync table name).
  sv(9),

  /// X (Image Sync table name); meaning \[unknown\].
  x(10),

  /// Movie, program AE.
  movieP(11),

  /// Movie, shutter priority.
  movieTv(12),

  /// Movie, aperture priority.
  movieAv(13),

  /// Movie TAv.
  movieTav(14),

  /// Movie, manual exposure.
  movieM(15),

  /// AstroTracer.
  astroTracer(16),

  /// AstroTracer, time exposure.
  astroTracerT(17),

  /// AstroTracer, bulb timer.
  astroTracerBt(18),

  /// SFP (GR WORLD wire 0x13); expansion \[unknown\].
  sfp(19),

  /// AstroTracer Type 3.
  astroTracerType3(20);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Shooting Mode byte 1. GR WORLD decodes U1–U3; Image Sync lists U1–U5.
enum BleUserMode implements BleWireEnum {
  /// No user (U) mode active.
  none(0),

  /// User mode U1.
  u1(1),

  /// User mode U2.
  u2(2),

  /// User mode U3.
  u3(3),

  /// User mode U4 (Image Sync table only).
  u4(4),

  /// User mode U5 (Image Sync table only).
  u5(5);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Shooting Mode byte 2, present only in Image Sync's 3-byte layout.
enum BleShootingModeOption implements BleWireEnum {
  /// No program option.
  none(0),

  /// Hyper (HTTP `exposureModeOption` `hyper` maps to the HyperProgram flag).
  hyper(1),

  /// Shift (HTTP `exposureModeOption` `shift` maps to program or
  /// ISO-priority shift).
  shift(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Mode (`78009238`).
enum BleCaptureMode implements BleWireEnum {
  /// Still photography.
  still(0),

  /// Movie recording.
  movie(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 0.
enum BleCapturing implements BleWireEnum {
  /// No capture in progress.
  idle(0),

  /// A capture is in progress.
  capturing(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 1.
enum BleCountdown implements BleWireEnum {
  /// No countdown running.
  none(0),

  /// Self-timer countdown running.
  selfTimer(1),

  /// Waiting for a scheduled start time.
  waitingForScheduledTime(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 2 (8-byte layout only).
enum BleStillCaptureState implements BleWireEnum {
  /// Single frame or no multi-frame sequence.
  other(0),

  /// Continuous burst in progress.
  continuous(1),

  /// Bracketing sequence in progress.
  bracket(2),

  /// Multiple exposure in progress.
  multipleExposure(3),

  /// Interval shooting in progress.
  interval(4),

  /// Interval composite in progress.
  intervalComposite(5);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 3 (8-byte layout only).
enum BleMovieCaptureState implements BleWireEnum {
  /// Not recording.
  other(0),

  /// Movie recording in progress.
  recording(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 4 (8-byte layout only; AstroTracer Type 3).
enum BleType3CaptureState implements BleWireEnum {
  /// No AstroTracer Type 3 capture.
  idle(0),

  /// Pre-capture running.
  preCapture(1),

  /// Main exposure running.
  mainCapture(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 5 (8-byte layout only).
enum BleType3PreCaptureResult implements BleWireEnum {
  /// Pre-capture succeeded.
  ok(0),

  /// Star motion could not be detected.
  motionNotDetectable(1),

  /// Exposure time error.
  exposureTimeError(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Self Timer byte 0.
enum BleCountdownCancel implements BleWireEnum {
  /// No cancel request.
  other(0),

  /// Cancel the running self-timer countdown.
  cancel(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Self Timer byte 1 (Image Sync 2-byte layout only).
enum BleRemocon implements BleWireEnum {
  /// Remote-control release off.
  off(0),

  /// Remote-control release on.
  on(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// White Balance (`2361F4FF`). Value 5 is absent from the table.
enum BleWhiteBalance implements BleWireEnum {
  /// Auto white balance.
  auto(0),

  /// Daylight.
  daylight(1),

  /// Shade.
  shade(2),

  /// Cloudy.
  cloudy(3),

  /// Incandescent (tungsten).
  incandescent(4),

  /// Daylight fluorescent.
  daylightFluorescent(6),

  /// Day-white fluorescent.
  dayWhiteFluorescent(7),

  /// Cool-white fluorescent.
  coolWhiteFluorescent(8),

  /// Warm-white fluorescent.
  warmWhiteFluorescent(9),

  /// Color temperature preset 1.
  colorTemperature1(10),

  /// Color temperature preset 2.
  colorTemperature2(11),

  /// Color temperature preset 3.
  colorTemperature3(12),

  /// Manual (measured) white balance 1.
  manual1(13),

  /// Manual (measured) white balance 2.
  manual2(14),

  /// Manual (measured) white balance 3.
  manual3(15),

  /// Color temperature enhancement.
  cte(16),

  /// Multi-pattern auto white balance.
  multiPatternAuto(17),

  /// Custom white balance 1.
  custom1(18),

  /// Custom white balance 2.
  custom2(19),

  /// Custom white balance 3.
  custom3(20);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Metering mode (`ED58217E`).
enum BleMeteringMode implements BleWireEnum {
  /// Spot metering.
  spot(0),

  /// Center-weighted metering.
  centerWeighted(1),

  /// Multi-segment metering.
  multiSegment(2),

  /// Highlight-weighted metering.
  highlightWeighted(3);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 0.
enum BleStillFileType implements BleWireEnum {
  /// JPEG only.
  jpeg(0),

  /// PEF raw only.
  pef(1),

  /// DNG raw only.
  dng(2),

  /// JPEG plus PEF raw.
  jpegPef(3),

  /// JPEG plus DNG raw.
  jpegDng(4);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 1.
enum BleRawType implements BleWireEnum {
  /// PENTAX PEF raw format.
  pef(0),

  /// Adobe DNG raw format.
  dng(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 2.
enum BleCardSlot implements BleWireEnum {
  /// SD card slot 1.
  sd1(0),

  /// SD card slot 2 (dual-slot PENTAX bodies).
  sd2(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 3.
enum BleSlotMode implements BleWireEnum {
  /// Fill slot 1, then slot 2.
  sequential(0),

  /// Record the same file to both slots.
  duplicate(1),

  /// Raw to one slot, JPEG to the other.
  rawJpegSplit(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// JPEG Size (`9838BB04`): size × quality.
enum BleJpegSize implements BleWireEnum {
  /// Size L, super fine quality.
  lSuperFine(0),

  /// Size M, super fine quality.
  mSuperFine(1),

  /// Size S, super fine quality.
  sSuperFine(2),

  /// Size XS, super fine quality.
  xsSuperFine(3),

  /// Size L, fine quality.
  lFine(4),

  /// Size M, fine quality.
  mFine(5),

  /// Size S, fine quality.
  sFine(6),

  /// Size XS, fine quality.
  xsFine(7),

  /// Size L, economy quality.
  lEconomy(8),

  /// Size M, economy quality.
  mEconomy(9),

  /// Size S, economy quality.
  sEconomy(10),

  /// Size XS, economy quality.
  xsEconomy(11);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Movie Configuration (`404F6626`). The 4K values belong to the shared
/// PENTAX table; GR bodies record Full HD only.
enum BleMovieConfiguration implements BleWireEnum {
  /// Full HD at 60p.
  fullHd60(0),

  /// Full HD at 30p.
  fullHd30(1),

  /// Full HD at 24p.
  fullHd24(2),

  /// 4K UHD at 60p (PENTAX only).
  uhd4k60(3),

  /// 4K UHD at 30p (PENTAX only).
  uhd4k30(4),

  /// 4K UHD at 24p (PENTAX only).
  uhd4k24(5);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Focus Mode byte 0.
enum BleFocusMode implements BleWireEnum {
  /// Manual focus.
  manual(0),

  /// Autofocus.
  auto(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Focus Mode byte 1 (focus setting).
enum BleFocusSetting implements BleWireEnum {
  /// Manual focus.
  manual(0),

  /// Auto-area AF.
  autoArea(1),

  /// Select-point AF.
  select(2),

  /// Pinpoint AF.
  pinpoint(3),

  /// Tracking AF.
  tracking(4),

  /// Continuous AF.
  continuous(5),

  /// Snap focus at a preset distance.
  snap(6),

  /// Focus fixed at infinity.
  infinity(7),

  /// Movie AF.
  movie(8),

  /// Auto-area AF weighted to the center.
  autoAreaCenter(9),

  /// Star AF for astrophotography.
  starAf(10);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Auto Focus Status byte 0.
enum BleAfRunning implements BleWireEnum {
  /// Autofocus not running.
  stopped(0),

  /// Autofocus running.
  running(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Auto Focus Status byte 1.
enum BleAfInFocus implements BleWireEnum {
  /// Focus not achieved.
  notInFocus(0),

  /// Focus achieved.
  inFocus(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Camera Power (`B58CE84C`). `sleep` is from Image Sync only. Neither app
/// ever writes anything but `off`.
enum BleCameraPower implements BleWireEnum {
  /// Power off; the only value either app writes.
  off(0),

  /// Powered on.
  on(1),

  /// Sleep (Image Sync only).
  sleep(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Battery Level byte 1 as Image Sync reads it (power source). GR WORLD
/// reads the same byte as a long-form flag instead; see BleBatteryLevel.
enum BlePowerSource implements BleWireEnum {
  /// Running on battery.
  battery(0),

  /// Powered by an AC adapter.
  acAdapter(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Operation Mode (`1452335A`), enum SFb in GR WORLD.
enum BleOperationMode implements BleWireEnum {
  /// Shooting mode.
  capture(0),

  /// Playback mode.
  playback(1),

  /// Camera woke for a BLE link; GR WORLD answers by writing
  /// `playback` or `capture`.
  bleStartup(2),

  /// Any other mode.
  other(3),

  /// Transferring files while powered off.
  powerOffTransfer(4);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Storage Information entry byte 0.
enum BleStorageType implements BleWireEnum {
  /// Built-in memory.
  internalMemory(0),

  /// SD card slot 1.
  sdSlot1(1),

  /// SD card slot 2.
  sdSlot2(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Power Off During File Transfer byte 0 (Image Sync naming; GR WORLD
/// reads `== 1` as "behaviour enabled").
enum BleTransferPowerOffBehavior implements BleWireEnum {
  /// Power-off aborts any running transfer.
  abortTransferAndPowerOff(0),

  /// Power-off waits until the transfer finishes.
  powerOffAfterTransfer(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Grad ND (`209F9869`), a PENTAX K-3 III characteristic absent from both
/// GR firmware builds.
enum BleGradNd implements BleWireEnum {
  /// Grad ND off.
  off(0),

  /// Graduated ND, normal orientation.
  normal(1),

  /// Graduated ND, reversed orientation.
  reverse(2),

  /// Custom setting 1.
  custom1(3),

  /// Custom setting 2.
  custom2(4),

  /// Custom setting 3.
  custom3(5);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Network Type (`9111CDD0`), used as camera WLAN on/off.
enum BleNetworkType implements BleWireEnum {
  /// Camera WLAN off.
  off(0),

  /// Camera WLAN on as an access point.
  ap(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// wlanFreq (`C4B7DFC0`, GR WORLD only).
enum BleWlanFrequency implements BleWireEnum {
  /// 2.4 GHz band.
  band24GHz(0),

  /// 5 GHz band.
  band5GHz(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// security (`63BC8463`, GR WORLD only).
enum BleWlanSecurity implements BleWireEnum {
  /// WPA2-PSK.
  wpa2(0),

  /// WPA3-SAE.
  wpa3(1),

  /// WPA2/WPA3 transition mode.
  transition(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;

  /// Equivalent Wi-Fi network-control security mode.
  WifiSecurity get wifiSecurity => switch (this) {
    BleWlanSecurity.wpa2 => WifiSecurity.wpa2,
    BleWlanSecurity.wpa3 => WifiSecurity.wpa3,
    BleWlanSecurity.transition => WifiSecurity.transition,
  };

  /// BLE value for the Wi-Fi network-control security mode [s].
  static BleWlanSecurity fromWifiSecurity(WifiSecurity s) => switch (s) {
    WifiSecurity.wpa2 => BleWlanSecurity.wpa2,
    WifiSecurity.wpa3 => BleWlanSecurity.wpa3,
    WifiSecurity.transition => BleWlanSecurity.transition,
  };
}

/// WLAN Channel (`51DE6EBC`, Image Sync; GR III firmware only).
enum BleWlanChannel implements BleWireEnum {
  /// Channel chosen automatically.
  auto(0),

  /// 2.4 GHz channel 1.
  ch1(1),

  /// 2.4 GHz channel 2.
  ch2(2),

  /// 2.4 GHz channel 3.
  ch3(3),

  /// 2.4 GHz channel 4.
  ch4(4),

  /// 2.4 GHz channel 5.
  ch5(5),

  /// 2.4 GHz channel 6.
  ch6(6),

  /// 2.4 GHz channel 7.
  ch7(7),

  /// 2.4 GHz channel 8.
  ch8(8),

  /// 2.4 GHz channel 9.
  ch9(9),

  /// 2.4 GHz channel 10.
  ch10(10),

  /// 2.4 GHz channel 11.
  ch11(11);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// BLE Enable Condition (`D8676C92`).
enum BleEnableCondition implements BleWireEnum {
  /// Bluetooth disabled.
  disable(0),

  /// Bluetooth enabled at any time (Image Sync name); Image Sync
  /// connects in the background for this value.
  enableAnytime(1),

  /// Bluetooth enabled at power on (Image Sync name); Image Sync
  /// connects in the background for this value.
  enablePowerOn(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// GPS record datum byte.
enum BleGpsDatum implements BleWireEnum {
  /// WGS 84, the only datum defined.
  wgs84(0);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Firmware update result (`39879aac`, GR WORLD 0x57d85c).
enum BleFirmwareUpdateResult implements BleWireEnum {
  /// Named `invalid` in GR WORLD; meaning \[unknown\].
  invalid(0),

  /// Update succeeded.
  success(1),

  /// Update failed.
  failure(2);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Aggregate notification "Include Changed Value" byte.
enum BleAggregateInclude implements BleWireEnum {
  /// The notification carries no changed value.
  notIncluded(0),

  /// The notification carries the changed value.
  included(1);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Image Control blob byte 2 (GR WORLD parser 0xd8e104).
enum BleImageControlBase implements BleWireEnum {
  /// Standard style.
  standard(0x00),

  /// Vivid style.
  vivid(0x01),

  /// Monotone style.
  monotone(0x02),

  /// Soft monotone style.
  softMonotone(0x03),

  /// Hard monotone style.
  hardMonotone(0x04),

  /// High contrast style.
  highContrast(0x05),

  /// Positive film style.
  positiveFilm(0x06),

  /// Bleach bypass style.
  bleachBypass(0x07),

  /// Retro style.
  retro(0x08),

  /// Hdr tone style.
  hdrTone(0x09),

  /// Negative film style.
  negativeFilm(0x0d),

  /// Cine yellow style.
  cineYellow(0x0e),

  /// Cine green style.
  cineGreen(0x0f),

  /// Cross process style.
  crossProcess(0x10),

  /// Standard mono style.
  standardMono(0x11),

  /// Soft mono style.
  softMono(0x12),

  /// High contrast mono style.
  highContrastMono(0x13),

  /// Grainy style.
  grainy(0x14),

  /// Solid style.
  solid(0x15),

  /// Hdr mono style.
  hdrMono(0x16),

  /// Pallet style.
  pallet(0x17),

  /// Solarization style.
  solarization(0x18),

  /// Pictorialist style.
  pictorialist(0x19);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}

/// Image Control blob parameter id (GR WORLD list [pp+0x2bcf8]; filter and
/// RGB-tone order from work notes CamSvcChars.md).
enum BleImageControlParameter implements BleWireEnum {
  /// Saturation adjustment.
  saturation(0x00),

  /// Hue adjustment.
  hue(0x01),

  /// Key adjustment.
  key(0x02),

  /// Contrast adjustment.
  contrast(0x03),

  /// Contrast high adjustment.
  contrastHigh(0x04),

  /// Contrast low adjustment.
  contrastLow(0x05),

  /// Sharpness adjustment.
  sharpness(0x06),

  /// Toning monotone adjustment.
  toningMonotone(0x07),

  /// Toning cinema adjustment.
  toningCinema(0x08),

  /// Toning bleach bypass adjustment.
  toningBleachBypass(0x09),

  /// Toning retro adjustment.
  toningRetro(0x0a),

  /// Toning hdr adjustment.
  toningHdr(0x0b),

  /// Filter effect adjustment.
  filterEffect(0x0c),

  /// Filter effect red high adjustment.
  filterEffectRedHigh(0x0d),

  /// Filter effect red low adjustment.
  filterEffectRedLow(0x0e),

  /// Filter effect green high adjustment.
  filterEffectGreenHigh(0x0f),

  /// Filter effect green low adjustment.
  filterEffectGreenLow(0x10),

  /// Filter effect blue high adjustment.
  filterEffectBlueHigh(0x11),

  /// Filter effect blue low adjustment.
  filterEffectBlueLow(0x12),

  /// Shading adjustment.
  shading(0x13),

  /// Clarity adjustment.
  clarity(0x14),

  /// Grain adjustment.
  grain(0x15),

  /// Grain size adjustment.
  grainSize(0x16),

  /// Grain strength adjustment.
  grainStrength(0x17),

  /// Hdr strength adjustment.
  hdrStrength(0x18),

  /// Cross process adjustment.
  crossProcess(0x19),

  /// Base color adjustment.
  baseColor(0x1a),

  /// White point adjustment.
  whitePoint(0x1b),

  /// Black point adjustment.
  blackPoint(0x1c),

  /// RGB tone highlights, GM axis.
  rgbToneHighlightsGm(0x1d),

  /// RGB tone highlights, BA axis.
  rgbToneHighlightsBa(0x1e),

  /// RGB tone midtones, GM axis.
  rgbToneMidtonesGm(0x1f),

  /// RGB tone midtones, BA axis.
  rgbToneMidtonesBa(0x20),

  /// RGB tone shadows, GM axis.
  rgbToneShadowsGm(0x21),

  /// RGB tone shadows, BA axis.
  rgbToneShadowsBa(0x22),

  /// Solarization type adjustment.
  solarizationType(0x23);

  new(this.wire);

  /// Byte value on the wire.
  @override
  final int wire;
  @override
  String get label => name;
}
