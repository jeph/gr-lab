/// Firmware generation sharing one BLE/HTTP server build
/// (docs/camera-models.md §5): GR III family (codes 1, 3, 5, 6, identical
/// `bled`/`webapid`) and GR IV family (7–10, one firmware file).
enum GrModelFamily { gr3, gr4 }

/// GR bodies with a BLE model code (docs/camera-models.md §4.1 table).
/// GR II has no BLE and is identified only over Wi-Fi. Codes 0, 2 and 4
/// are PENTAX K-3 Mark III bodies sharing the `bled` table and are not GR
/// models; see [GrModelCode] for keeping them raw.
enum GrModel {
  gr3(1, 'RICOH GR III', GrModelFamily.gr3),
  gr3x(3, 'RICOH GR IIIx', GrModelFamily.gr3),
  gr3Hdf(5, 'RICOH GR III HDF', GrModelFamily.gr3),
  gr3xHdf(6, 'RICOH GR IIIx HDF', GrModelFamily.gr3),
  gr4(7, 'RICOH GR IV', GrModelFamily.gr4),
  gr4Hdf(8, 'RICOH GR IV HDF', GrModelFamily.gr4),
  gr4Monochrome(9, 'RICOH GR IV Monochrome', GrModelFamily.gr4),

  /// Present in GR IV firmware but unannounced; GR WORLD 2.0.0 rejects it.
  gr4x(10, 'RICOH GR IVx', GrModelFamily.gr4);

  const GrModel(this.code, this.modelString, this.family);

  /// Advertising tag `01` value.
  final int code;

  /// Firmware model property string (Camera Information model name, the
  /// `bled` advertising table, `/v1/props` `model`).
  final String modelString;
  final GrModelFamily family;

  /// Model string without the `RICOH ` prefix, as GR WORLD stores it.
  String get shortName => modelString.substring('RICOH '.length);

  /// Whether GR WORLD 2.0.0's scan accepts this code (ble.md §Camera models).
  bool get acceptedByGrWorld => this != GrModel.gr4x;

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
  GrModelCode(this.raw) : model = GrModel.fromCode(raw);

  final int raw;
  final GrModel? model;

  Object? toJson() => {
    'raw': raw,
    'name': model?.name,
    'modelString': model?.modelString,
    'family': model?.family.name,
  };

  @override
  String toString() => model?.modelString ?? 'unknown model code $raw';
}
