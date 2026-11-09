/// Firmware generation sharing one BLE/HTTP server build
/// (docs/camera-models.md §5): GR III family (codes 1, 3, 5, 6, identical
/// `bled`/`webapid`) and GR IV family (7–10, one firmware file).
enum GrModelFamily {
  /// GR III, GR IIIx and their HDF variants (codes 1, 3, 5, 6).
  gr3,

  /// GR IV, GR IV HDF, GR IV Monochrome and the unannounced GR IVx
  /// (codes 7–10).
  gr4,
}

/// GR bodies with a BLE model code (docs/camera-models.md §4.1 table).
/// GR II has no BLE and is identified only over Wi-Fi. Codes 0, 2 and 4
/// are PENTAX K-3 Mark III bodies sharing the `bled` table and are not GR
/// models; see [GrModelCode] for keeping them raw.
enum GrModel {
  /// GR III, advertised code 1.
  gr3(1, 'RICOH GR III', GrModelFamily.gr3),

  /// GR IIIx, advertised code 3.
  gr3x(3, 'RICOH GR IIIx', GrModelFamily.gr3),

  /// GR III HDF (highlight diffusion filter), advertised code 5.
  gr3Hdf(5, 'RICOH GR III HDF', GrModelFamily.gr3),

  /// GR IIIx HDF, advertised code 6.
  gr3xHdf(6, 'RICOH GR IIIx HDF', GrModelFamily.gr3),

  /// GR IV, advertised code 7.
  gr4(7, 'RICOH GR IV', GrModelFamily.gr4),

  /// GR IV HDF, advertised code 8.
  gr4Hdf(8, 'RICOH GR IV HDF', GrModelFamily.gr4),

  /// GR IV Monochrome, advertised code 9.
  gr4Monochrome(9, 'RICOH GR IV Monochrome', GrModelFamily.gr4),

  /// Present in GR IV firmware but unannounced; GR WORLD 2.0.0 rejects it.
  gr4x(10, 'RICOH GR IVx', GrModelFamily.gr4);

  new(this.code, this.modelString, this.family);

  /// Advertising tag `01` value.
  final int code;

  /// Firmware model property string (Camera Information model name, the
  /// `bled` advertising table, `/v1/props` `model`).
  final String modelString;

  /// Firmware generation this body runs, which decides the BLE/HTTP
  /// server build it speaks.
  final GrModelFamily family;

  /// Model string without the `RICOH ` prefix, as GR WORLD stores it.
  String get shortName => modelString.substring('RICOH '.length);

  /// Whether GR WORLD 2.0.0's scan accepts this code (ble.md §Camera models).
  bool get acceptedByGrWorld => this != GrModel.gr4x;

  /// Model for an advertising tag `01` code, or null for codes that are
  /// not GR bodies (PENTAX codes 0, 2, 4) or are not known yet.
  static GrModel? fromCode(int code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return null;
  }

  /// Exact match against the firmware string, with or without the `RICOH `
  /// prefix (GR WORLD strips it from `/v1/props`), after trimming
  /// whitespace and NUL padding. Anything else is null: model strings are
  /// compared exactly by both firmware and apps.
  static GrModel? fromModelString(String text) {
    final t = text.replaceAll('\u0000', '').trim();
    for (final m in values) {
      if (m.modelString == t || m.shortName == t) return m;
    }
    return null;
  }
}

/// Advertised model code that keeps unknown values (PENTAX codes, future
/// bodies) raw.
final class GrModelCode {
  /// Wraps the advertised tag `01` value, resolving it to a [GrModel] when
  /// the code is a known GR body.
  new(this.raw) : model = GrModel.fromCode(raw);

  /// Code exactly as advertised (0–255).
  final int raw;

  /// GR body for [raw], or null when the code is not a known GR model.
  final GrModel? model;

  /// Diagnostic JSON: the raw code plus the resolved model, if any.
  Object? toJson() => {
    'raw': raw,
    'name': model?.name,
    'modelString': model?.modelString,
    'family': model?.family.name,
  };

  @override
  String toString() => model?.modelString ?? 'unknown model code $raw';
}
