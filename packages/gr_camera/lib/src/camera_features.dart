import 'package:flutter/foundation.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Something GR Photo does with a camera that not every GR model or firmware
/// version can do.
///
/// `_minimumFirmware` is the one place that decides which camera has which
/// feature. Code that behaves differently by model or firmware asks
/// [CameraBody.supports] rather than comparing models, families or
/// versions, and behaviour that comes to depend on them adds a feature and
/// its row there, with the evidence for it.
enum CameraFeature {
  /// Reading and loading the Image Control Custom slots C1–C3 over
  /// Bluetooth (`CameraLooks`).
  lookSlots,

  /// Image Control offers the monochrome base images instead of the colour
  /// ones (`lookBases`).
  monochromeLooks,

  /// The 26.1 mm lens (40 mm in 35 mm terms) of the x bodies, in place of
  /// the 18.3 mm (28 mm) one; the camera's drawing shows it.
  lens40mm,

  /// The grayish-silver shutter button Ricoh gives the HDF bodies in place
  /// of a black one; the camera's drawing shows it.
  silverShutterButton,

  /// The Monochrome's finish: a matte black body whose GR logo is black
  /// too; the camera's drawing shows it.
  blackFinish,

  /// Taking the phone's position over Bluetooth and saving it in the
  /// pictures it takes: the GPS Information and GEO Tag (Store Location
  /// Info) characteristics (`CameraGeotagging`).
  geotagging,

  /// Pairing by typing the code the camera shows into the phone's pairing
  /// prompt (Passkey Entry, the camera displaying), in place of comparing
  /// a code on both and pressing OK on the camera (Numeric Comparison).
  passkeyPairing,

  /// Bluetooth is set under Bluetooth Setting in the camera's menu, whose
  /// Action Mode offers On anytime, On when power is on and Disable, in
  /// place of Wireless Communication with an Action Mode of On or Off.
  bluetoothSettingMenu,
}

/// For each feature, the oldest firmware version of each model that has
/// it; `0.00` (GR WORLD's own "any version") where every version does. A
/// model that is not listed has the feature on no version.
const _minimumFirmware = <CameraFeature, Map<GrModel, String>>{
  // GR WORLD offers Image Control on a GR IV from firmware 1.04 and on the
  // other GR IV bodies on any version (`isImageControlSupported`, observed
  // in GR WORLD 2.0.0's code; research/protocol/image-control.md §1). The
  // GR III family's `bled` registers none of the slot characteristics
  // (observed in GR III firmware 2.20; image-control.md §3).
  CameraFeature.lookSlots: {
    GrModel.gr4: '1.04',
    GrModel.gr4Hdf: '0.00',
    GrModel.gr4Monochrome: '0.00',
    GrModel.gr4x: '0.00',
  },
  // GR WORLD gives the monochrome bases to the GR IV Monochrome
  // (`findSupportedByCameraType` 0xda1db4, observed in GR WORLD 2.0.0's
  // code; image-control.md §3).
  CameraFeature.monochromeLooks: {GrModel.gr4Monochrome: '0.00'},
  // How the bodies differ outside, which no firmware version changes
  // (Ricoh's product pages; research/camera-models.md §7). The GR IVx is
  // not announced: its lens is [inferred] from the GR IIIx's name.
  CameraFeature.lens40mm: {
    GrModel.gr3x: '0.00',
    GrModel.gr3xHdf: '0.00',
    GrModel.gr4x: '0.00',
  },
  CameraFeature.silverShutterButton: {
    GrModel.gr3Hdf: '0.00',
    GrModel.gr3xHdf: '0.00',
    GrModel.gr4Hdf: '0.00',
  },
  CameraFeature.blackFinish: {GrModel.gr4Monochrome: '0.00'},
  // The GPS Information and GEO Tag characteristics are in the `bled` of
  // both families (research/firmware-protocol-inventory.md, the UUID
  // table; `GrBleCatalog.gpsInformation` and `geoTag`), and the main
  // firmware of both takes a position behind the GEO Tag setting (found in
  // GR IV 1.20 and GR III 2.20; research/protocol/geotagging.md §1.2,
  // §1.5). Each family shares one `bled` (research/camera-models.md §5),
  // so the x, HDF and Monochrome bodies are listed too; the GR IIIx
  // firmware was not read. Any version is [inferred]: older firmware was
  // not read either. Nothing was run on a camera yet (geotagging.md §7).
  CameraFeature.geotagging: {
    GrModel.gr3: '0.00',
    GrModel.gr3x: '0.00',
    GrModel.gr3Hdf: '0.00',
    GrModel.gr3xHdf: '0.00',
    GrModel.gr4: '0.00',
    GrModel.gr4Hdf: '0.00',
    GrModel.gr4Monochrome: '0.00',
    GrModel.gr4x: '0.00',
  },
  // The GR III family's `bled` sets the display-only IO capability and
  // hands the passkey to the camera's screen (`SetDisplayPairingMode`,
  // `OnPasskeyNotify`), and has no handler for a numeric comparison; the
  // GR IV's sets display-yes-no and waits for OK (found in GR III firmware
  // 2.20 and GR IV 1.20; research/protocol/firmware-bonding-gr3.md §1,
  // §2). The family shares one `bled` (research/camera-models.md §5). Any
  // version is [inferred]: older firmware was not read. Not run on a GR
  // III yet.
  CameraFeature.passkeyPairing: {
    GrModel.gr3: '0.00',
    GrModel.gr3x: '0.00',
    GrModel.gr3Hdf: '0.00',
    GrModel.gr3xHdf: '0.00',
  },
  // The GR III manual and the menu text of GR III firmware 2.20 and GR
  // IIIx 1.70 (research/protocol/firmware-bonding-gr3.md §4); the GR IV's
  // menu has Wireless Communication instead (GR IV firmware 1.20). The
  // HDF bodies are [inferred] from sharing the family's firmware.
  CameraFeature.bluetoothSettingMenu: {
    GrModel.gr3: '0.00',
    GrModel.gr3x: '0.00',
    GrModel.gr3Hdf: '0.00',
    GrModel.gr3xHdf: '0.00',
  },
};

/// A camera as far as what it supports goes: its model and the firmware
/// version it runs.
@immutable
final class CameraBody {
  /// A camera of [model] running [firmware].
  const new({required this.model, required this.firmware});

  /// The camera as it reported itself over Bluetooth ([identity]).
  new reported(GrBleIdentity identity)
    : this(model: identity.model, firmware: identity.firmwareRevision);

  /// A camera whose model and firmware are not known; it has no feature.
  static const unknown = CameraBody(model: null, firmware: null);

  /// The camera's model; null when it was not reported or is one GR Photo
  /// does not know.
  final GrModel? model;

  /// The firmware version as the camera reports it, such as `1.20`; null
  /// when it was not read.
  final String? firmware;

  /// The oldest firmware version of this model that has [feature], such as
  /// `1.04`; null when no version does.
  String? minimumFirmware(CameraFeature feature) =>
      _minimumFirmware[feature]![model];

  /// This camera with what it does not say taken from [saved]: a link's
  /// Camera Information read can fail field by field, and a model or
  /// firmware the camera reported before still holds.
  CameraBody completedBy(CameraBody saved) => CameraBody(
    model: model ?? saved.model,
    firmware: firmware ?? saved.firmware,
  );

  /// Whether this camera has [feature]: its model has it and its firmware
  /// is at least [minimumFirmware]. A firmware version that was not read
  /// meets only a minimum of `0.00`.
  bool supports(CameraFeature feature) {
    final minimum = _version(minimumFirmware(feature));
    if (minimum == null) return false;
    if (minimum == 0) return true;
    final version = _version(firmware);
    return version != null && version >= minimum;
  }

  /// [text] as a number: Ricoh writes versions as a major number and a
  /// two-digit minor one (`1.04`, `1.20`), so they compare as decimals.
  static double? _version(String? text) => text == null
      ? null
      : double.tryParse(text.replaceAll('\u0000', '').trim());

  @override
  String toString() => 'CameraBody(${model?.name}, firmware $firmware)';
}
