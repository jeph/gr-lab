import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/data/cameras.dart';

/// The line under a camera's name.
extension CameraIdentity on SavedCamera {
  /// `GR IV · No. 1234567 · fw 1.20`, leaving out the model when [name]
  /// already says it and the firmware unless [firmware].
  String identityLine(AppLocalizations l10n, {bool firmware = true}) {
    final model = modelName;
    final version = firmware ? this.firmware : null;
    return switch ((model == null || model == name ? null : model, version)) {
      (null, null) => l10n.camerasIdentitySerial(serial),
      (null, final version?) => l10n.camerasIdentitySerialFirmware(
        serial,
        version,
      ),
      (final model?, null) => l10n.camerasIdentityModelSerial(model, serial),
      (final model?, final version?) => l10n.camerasIdentityModelSerialFirmware(
        model,
        serial,
        version,
      ),
    };
  }
}
