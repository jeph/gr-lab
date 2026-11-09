import 'package:gr_protocol/gr_protocol.dart';

/// Something GR Lab does with a camera that not every GR model can do.
///
/// [CameraFeatures.supports] is the one place that decides which models
/// have which feature. Code that behaves differently by model asks
/// `model.supports(feature)` rather than comparing models or families, and
/// behaviour that comes to depend on the model adds a feature here, with
/// the evidence for the models that have it.
enum CameraFeature {
  /// Reading and loading the Image Control Custom slots C1–C3 over
  /// Bluetooth (`CameraLooks`). The GR IV family's firmware serves them; the
  /// GR III family's has no way to read or write its slots from outside the
  /// camera: its `bled` registers none of the Image Control characteristics
  /// (observed in GR III firmware 2.20; research/protocol/image-control.md
  /// §3).
  lookSlots,

  /// Image Control offers the monochrome base images instead of the colour
  /// ones (`lookBases`), as GR WORLD gives them to the GR IV Monochrome
  /// (`findSupportedByCameraType` 0xda1db4, observed in GR WORLD 2.0.0's
  /// code; research/protocol/image-control.md §3).
  monochromeLooks,
}

/// Which [GrModel] has which [CameraFeature].
extension CameraFeatures on GrModel? {
  /// Whether a camera of this model has [feature]. A model GR Lab does not
  /// know, or one that was not reported (null), has none: a new body gets a
  /// feature only once it is added here.
  bool supports(CameraFeature feature) {
    final model = this;
    if (model == null) return false;
    return switch (feature) {
      CameraFeature.lookSlots => model.family == GrModelFamily.gr4,
      CameraFeature.monochromeLooks => model == GrModel.gr4Monochrome,
    };
  }
}
