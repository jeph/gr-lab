import '../wifi/network_control.dart';
import 'codecs.dart';

// Wire values come from GR WORLD 2.0.0 (docs/protocol/ble.md) and from
// Image Sync's decrypted `def_ble.yaml` (docs/protocol/ble-imagesync.md §1).
// Values outside these tables are kept raw by BleEnumValue.

/// Operation Request byte 0 (ble-imagesync.md §1, Shooting Service).
enum BleOperationCode implements BleWireEnum {
  nop(0),
  start(1),

  /// Documented but never sent by Image Sync: it toggles with `start`
  /// instead (ble-imagesync.md §4.5).
  stop(2);

  const BleOperationCode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Operation Request byte 1.
enum BleOperationParameter implements BleWireEnum {
  noAf(0),
  af(1),
  greenButton(2);

  const BleOperationParameter(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Drive Mode (`B29E6DE3`). 0–15 are the GR modes decoded by GR WORLD;
/// 16–65 are the shared PENTAX table from `def_ble.yaml` (remote = IR
/// remote control; 12 s self-timer variants are PENTAX bodies).
enum BleDriveMode implements BleWireEnum {
  single(0),
  selfTimer10s(1),
  selfTimer2s(2),
  continuous(3),
  bracket(4),
  bracketSelfTimer10s(5),
  bracketSelfTimer2s(6),
  multipleExposure(7),
  multipleExposureSelfTimer10s(8),
  multipleExposureSelfTimer2s(9),
  interval(10),
  intervalSelfTimer10s(11),
  intervalSelfTimer2s(12),
  intervalComposite(13),
  intervalCompositeSelfTimer10s(14),
  intervalCompositeSelfTimer2s(15),
  singleRemote(16),
  singleRemote3s(17),
  continuousHigh(18),
  continuousHighSelfTimer12s(19),
  continuousHighSelfTimer2s(20),
  continuousHighRemote(21),
  continuousHighRemote3s(22),
  continuousMedium(23),
  continuousMediumSelfTimer12s(24),
  continuousMediumSelfTimer2s(25),
  continuousMediumRemote(26),
  continuousMediumRemote3s(27),
  continuousLow(28),
  continuousLowSelfTimer12s(29),
  continuousLowSelfTimer2s(30),
  continuousLowRemote(31),
  continuousLowRemote3s(32),
  bracketRemote(33),
  bracketRemote3s(34),
  multipleExposureRemote(35),
  multipleExposureRemote3s(36),
  intervalRemote(37),
  intervalRemote3s(38),
  intervalCompositeRemote(39),
  intervalCompositeRemote3s(40),
  intervalMovie(41),
  intervalMovieSelfTimer12s(42),
  intervalMovieSelfTimer2s(43),
  intervalMovieRemote(44),
  intervalMovieRemote3s(45),
  motionBracket(46),
  motionBracketSelfTimer12s(47),
  motionBracketSelfTimer2s(48),
  motionBracketRemote(49),
  motionBracketRemote3s(50),
  depthOfFieldBracket(51),
  depthOfFieldBracketSelfTimer12s(52),
  depthOfFieldBracketSelfTimer2s(53),
  depthOfFieldBracketRemote(54),
  depthOfFieldBracketRemote3s(55),
  mirrorUp(56),
  mirrorUpSelfTimer12s(57),
  mirrorUpSelfTimer2s(58),
  mirrorUpRemote(59),
  mirrorUpRemote3s(60),
  starStream(61),
  starStreamSelfTimer12s(62),
  starStreamSelfTimer2s(63),
  starStreamRemote(64),
  starStreamRemote3s(65);

  const BleDriveMode(this.wire);
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
  p(0),
  av(1),
  tv(2),
  m(3),
  b(4),
  bt(5),
  t(6),
  auto(7),
  tav(8),
  sv(9),
  x(10),
  movieP(11),
  movieTv(12),
  movieAv(13),
  movieTav(14),
  movieM(15),
  astroTracer(16),
  astroTracerT(17),
  astroTracerBt(18),
  sfp(19),
  astroTracerType3(20);

  const BleExposureMode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Shooting Mode byte 1. GR WORLD decodes U1–U3; Image Sync lists U1–U5.
enum BleUserMode implements BleWireEnum {
  none(0),
  u1(1),
  u2(2),
  u3(3),
  u4(4),
  u5(5);

  const BleUserMode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Shooting Mode byte 2, present only in Image Sync's 3-byte layout.
enum BleShootingModeOption implements BleWireEnum {
  none(0),
  hyper(1),
  shift(2);

  const BleShootingModeOption(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Mode (`78009238`).
enum BleCaptureMode implements BleWireEnum {
  still(0),
  movie(2);

  const BleCaptureMode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 0.
enum BleCapturing implements BleWireEnum {
  idle(0),
  capturing(1);

  const BleCapturing(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 1.
enum BleCountdown implements BleWireEnum {
  none(0),
  selfTimer(1),
  waitingForScheduledTime(2);

  const BleCountdown(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 2 (8-byte layout only).
enum BleStillCaptureState implements BleWireEnum {
  other(0),
  continuous(1),
  bracket(2),
  multipleExposure(3),
  interval(4),
  intervalComposite(5);

  const BleStillCaptureState(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 3 (8-byte layout only).
enum BleMovieCaptureState implements BleWireEnum {
  other(0),
  recording(1);

  const BleMovieCaptureState(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 4 (8-byte layout only; AstroTracer Type 3).
enum BleType3CaptureState implements BleWireEnum {
  idle(0),
  preCapture(1),
  mainCapture(2);

  const BleType3CaptureState(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Capture Status byte 5 (8-byte layout only).
enum BleType3PreCaptureResult implements BleWireEnum {
  ok(0),
  motionNotDetectable(1),
  exposureTimeError(2);

  const BleType3PreCaptureResult(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Self Timer byte 0.
enum BleCountdownCancel implements BleWireEnum {
  other(0),
  cancel(1);

  const BleCountdownCancel(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Self Timer byte 1 (Image Sync 2-byte layout only).
enum BleRemocon implements BleWireEnum {
  off(0),
  on(1);

  const BleRemocon(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// White Balance (`2361F4FF`). Value 5 is absent from the table.
enum BleWhiteBalance implements BleWireEnum {
  auto(0),
  daylight(1),
  shade(2),
  cloudy(3),
  incandescent(4),
  daylightFluorescent(6),
  dayWhiteFluorescent(7),
  coolWhiteFluorescent(8),
  warmWhiteFluorescent(9),
  colorTemperature1(10),
  colorTemperature2(11),
  colorTemperature3(12),
  manual1(13),
  manual2(14),
  manual3(15),
  cte(16),
  multiPatternAuto(17),
  custom1(18),
  custom2(19),
  custom3(20);

  const BleWhiteBalance(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Metering mode (`ED58217E`).
enum BleMeteringMode implements BleWireEnum {
  spot(0),
  centerWeighted(1),
  multiSegment(2),
  highlightWeighted(3);

  const BleMeteringMode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 0.
enum BleStillFileType implements BleWireEnum {
  jpeg(0),
  pef(1),
  dng(2),
  jpegPef(3),
  jpegDng(4);

  const BleStillFileType(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 1.
enum BleRawType implements BleWireEnum {
  pef(0),
  dng(1);

  const BleRawType(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 2.
enum BleCardSlot implements BleWireEnum {
  sd1(0),
  sd2(1);

  const BleCardSlot(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// File Type byte 3.
enum BleSlotMode implements BleWireEnum {
  sequential(0),
  duplicate(1),
  rawJpegSplit(2);

  const BleSlotMode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// JPEG Size (`9838BB04`): size × quality.
enum BleJpegSize implements BleWireEnum {
  lSuperFine(0),
  mSuperFine(1),
  sSuperFine(2),
  xsSuperFine(3),
  lFine(4),
  mFine(5),
  sFine(6),
  xsFine(7),
  lEconomy(8),
  mEconomy(9),
  sEconomy(10),
  xsEconomy(11);

  const BleJpegSize(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Movie Configuration (`404F6626`). The 4K values belong to the shared
/// PENTAX table; GR bodies record Full HD only.
enum BleMovieConfiguration implements BleWireEnum {
  fullHd60(0),
  fullHd30(1),
  fullHd24(2),
  uhd4k60(3),
  uhd4k30(4),
  uhd4k24(5);

  const BleMovieConfiguration(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Focus Mode byte 0.
enum BleFocusMode implements BleWireEnum {
  manual(0),
  auto(1);

  const BleFocusMode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Focus Mode byte 1 (focus setting).
enum BleFocusSetting implements BleWireEnum {
  manual(0),
  autoArea(1),
  select(2),
  pinpoint(3),
  tracking(4),
  continuous(5),
  snap(6),
  infinity(7),
  movie(8),
  autoAreaCenter(9),
  starAf(10);

  const BleFocusSetting(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Auto Focus Status byte 0.
enum BleAfRunning implements BleWireEnum {
  stopped(0),
  running(1);

  const BleAfRunning(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Auto Focus Status byte 1.
enum BleAfInFocus implements BleWireEnum {
  notInFocus(0),
  inFocus(1);

  const BleAfInFocus(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Camera Power (`B58CE84C`). `sleep` is from Image Sync only. Neither app
/// ever writes anything but `off`.
enum BleCameraPower implements BleWireEnum {
  off(0),
  on(1),
  sleep(2);

  const BleCameraPower(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Battery Level byte 1 as Image Sync reads it (power source). GR WORLD
/// reads the same byte as a long-form flag instead; see BleBatteryLevel.
enum BlePowerSource implements BleWireEnum {
  battery(0),
  acAdapter(1);

  const BlePowerSource(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Operation Mode (`1452335A`), enum SFb in GR WORLD.
enum BleOperationMode implements BleWireEnum {
  capture(0),
  playback(1),
  bleStartup(2),
  other(3),
  powerOffTransfer(4);

  const BleOperationMode(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Storage Information entry byte 0.
enum BleStorageType implements BleWireEnum {
  internalMemory(0),
  sdSlot1(1),
  sdSlot2(2);

  const BleStorageType(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Power Off During File Transfer byte 0 (Image Sync naming; GR WORLD
/// reads `== 1` as "behaviour enabled").
enum BleTransferPowerOffBehavior implements BleWireEnum {
  abortTransferAndPowerOff(0),
  powerOffAfterTransfer(1);

  const BleTransferPowerOffBehavior(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Grad ND (`209F9869`), a PENTAX K-3 III characteristic absent from both
/// GR firmware builds.
enum BleGradNd implements BleWireEnum {
  off(0),
  normal(1),
  reverse(2),
  custom1(3),
  custom2(4),
  custom3(5);

  const BleGradNd(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Network Type (`9111CDD0`), used as camera WLAN on/off.
enum BleNetworkType implements BleWireEnum {
  off(0),
  ap(1);

  const BleNetworkType(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// wlanFreq (`C4B7DFC0`, GR WORLD only).
enum BleWlanFrequency implements BleWireEnum {
  band24GHz(0),
  band5GHz(1);

  const BleWlanFrequency(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// security (`63BC8463`, GR WORLD only).
enum BleWlanSecurity implements BleWireEnum {
  wpa2(0),
  wpa3(1),
  transition(2);

  const BleWlanSecurity(this.wire);
  @override
  final int wire;
  @override
  String get label => name;

  WifiSecurity get wifiSecurity => switch (this) {
    BleWlanSecurity.wpa2 => WifiSecurity.wpa2,
    BleWlanSecurity.wpa3 => WifiSecurity.wpa3,
    BleWlanSecurity.transition => WifiSecurity.transition,
  };

  static BleWlanSecurity fromWifiSecurity(WifiSecurity s) => switch (s) {
    WifiSecurity.wpa2 => BleWlanSecurity.wpa2,
    WifiSecurity.wpa3 => BleWlanSecurity.wpa3,
    WifiSecurity.transition => BleWlanSecurity.transition,
  };
}

/// WLAN Channel (`51DE6EBC`, Image Sync; GR III firmware only).
enum BleWlanChannel implements BleWireEnum {
  auto(0),
  ch1(1),
  ch2(2),
  ch3(3),
  ch4(4),
  ch5(5),
  ch6(6),
  ch7(7),
  ch8(8),
  ch9(9),
  ch10(10),
  ch11(11);

  const BleWlanChannel(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// BLE Enable Condition (`D8676C92`).
enum BleEnableCondition implements BleWireEnum {
  disable(0),
  enableAnytime(1),
  enablePowerOn(2);

  const BleEnableCondition(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// GPS record datum byte.
enum BleGpsDatum implements BleWireEnum {
  wgs84(0);

  const BleGpsDatum(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Firmware update result (`39879aac`, GR WORLD 0x57d85c).
enum BleFirmwareUpdateResult implements BleWireEnum {
  invalid(0),
  success(1),
  failure(2);

  const BleFirmwareUpdateResult(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Aggregate notification "Include Changed Value" byte.
enum BleAggregateInclude implements BleWireEnum {
  notIncluded(0),
  included(1);

  const BleAggregateInclude(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Image Control blob byte 2 (GR WORLD parser 0xd8e104).
enum BleImageControlBase implements BleWireEnum {
  standard(0x00),
  vivid(0x01),
  monotone(0x02),
  softMonotone(0x03),
  hardMonotone(0x04),
  highContrast(0x05),
  positiveFilm(0x06),
  bleachBypass(0x07),
  retro(0x08),
  hdrTone(0x09),
  negativeFilm(0x0d),
  cineYellow(0x0e),
  cineGreen(0x0f),
  crossProcess(0x10),
  standardMono(0x11),
  softMono(0x12),
  highContrastMono(0x13),
  grainy(0x14),
  solid(0x15),
  hdrMono(0x16),
  pallet(0x17),
  solarization(0x18),
  pictorialist(0x19);

  const BleImageControlBase(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}

/// Image Control blob parameter id (GR WORLD list [pp+0x2bcf8]; filter and
/// RGB-tone order from work notes CamSvcChars.md).
enum BleImageControlParameter implements BleWireEnum {
  saturation(0x00),
  hue(0x01),
  key(0x02),
  contrast(0x03),
  contrastHigh(0x04),
  contrastLow(0x05),
  sharpness(0x06),
  toningMonotone(0x07),
  toningCinema(0x08),
  toningBleachBypass(0x09),
  toningRetro(0x0a),
  toningHdr(0x0b),
  filterEffect(0x0c),
  filterEffectRedHigh(0x0d),
  filterEffectRedLow(0x0e),
  filterEffectGreenHigh(0x0f),
  filterEffectGreenLow(0x10),
  filterEffectBlueHigh(0x11),
  filterEffectBlueLow(0x12),
  shading(0x13),
  clarity(0x14),
  grain(0x15),
  grainSize(0x16),
  grainStrength(0x17),
  hdrStrength(0x18),
  crossProcess(0x19),
  baseColor(0x1a),
  whitePoint(0x1b),
  blackPoint(0x1c),
  rgbToneHighlightsGm(0x1d),
  rgbToneHighlightsBa(0x1e),
  rgbToneMidtonesGm(0x1f),
  rgbToneMidtonesBa(0x20),
  rgbToneShadowsGm(0x21),
  rgbToneShadowsBa(0x22),
  solarizationType(0x23);

  const BleImageControlParameter(this.wire);
  @override
  final int wire;
  @override
  String get label => name;
}
