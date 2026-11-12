import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';

/// What the failure page shows for one failed pairing run: a title, a
/// sentence on what happened, numbered steps for the next attempt and an
/// optional extra hint.
@immutable
final class PairingFailureInfo {
  const new({
    required this.title,
    required this.body,
    required this.steps,
    required this.detail,
    this.hintTitle,
    this.hintBody,
  });

  /// Maps a `pairCamera` error to messages in [l10n], naming the [camera]
  /// being paired. Anything that is not a [GrPairingException] (a scan
  /// error, Bluetooth turning off) gets the generic page. [detail] always
  /// carries the error's [errorCode].
  factory from(
    Object error, {
    required String camera,
    required AppLocalizations l10n,
  }) {
    final detail = l10n.pairingErrorCode(errorCode(error));
    final retrySteps = [
      l10n.pairingStepReopenExecutePairing,
      l10n.pairingStepTapPair,
      l10n.pairingStepPressOk,
    ];
    final removeBondSteps = [
      l10n.pairingStepDeletePhoneFromCamera,
      l10n.pairingStepDeleteCameraFromPhone,
      l10n.pairingStepReopenExecutePairing,
    ];
    if (error is! GrPairingException) {
      return PairingFailureInfo(
        title: l10n.pairingFailedTitle,
        body: l10n.pairingFailedUnexpectedBody,
        steps: retrySteps,
        hintTitle: l10n.pairingPairedBeforeTitle,
        hintBody: l10n.pairingPairedBeforeBody,
        detail: detail,
      );
    }
    switch (error.failure) {
      case GrPairingFailure.notFound:
        return PairingFailureInfo(
          title: l10n.pairingNotFoundTitle(camera),
          body: l10n.pairingNotFoundBody,
          steps: [
            l10n.pairingStepTurnOnAndKeepClose,
            l10n.pairingStepCheckActionMode,
            l10n.pairingStepReopenExecutePairing,
          ],
          detail: detail,
        );
      case GrPairingFailure.cameraOff:
        return PairingFailureInfo(
          title: l10n.pairingCameraOffTitle(camera),
          body: l10n.pairingCameraOffBody,
          steps: [l10n.pairingStepTurnOn, l10n.pairingStepReopenExecutePairing],
          detail: detail,
        );
      case GrPairingFailure.connectFailed:
        return PairingFailureInfo(
          title: l10n.pairingConnectFailedTitle(camera),
          body: l10n.pairingConnectFailedBody,
          steps: [
            l10n.pairingStepKeepClose,
            l10n.pairingStepReopenExecutePairing,
            l10n.pairingStepTapPairThenOk,
          ],
          detail: detail,
        );
      case GrPairingFailure.notConfirmed when _bondRejected(error.cause):
        // Reported when the peer refuses stored keys. Only seen on a Mac
        // so far, so the copy names what to do, not what the phone says.
        return PairingFailureInfo(
          title: l10n.pairingRefusedTitle(camera),
          body: l10n.pairingRefusedBody,
          steps: removeBondSteps,
          detail: detail,
        );
      case GrPairingFailure.notConfirmed:
        return PairingFailureInfo(
          title: l10n.pairingFailedTitle,
          body: l10n.pairingNotConfirmedBody,
          steps: retrySteps,
          hintTitle: l10n.pairingPairedBeforeTitle,
          hintBody: l10n.pairingPairedBeforeBody,
          detail: detail,
        );
      case GrPairingFailure.bondUnusable:
        return PairingFailureInfo(
          title: l10n.pairingBondUnusableTitle(camera),
          body: l10n.pairingBondUnusableBody,
          steps: removeBondSteps,
          detail: detail,
        );
      case GrPairingFailure.registrationFailed:
        return PairingFailureInfo(
          title: l10n.pairingRegistrationFailedTitle(camera),
          body: l10n.pairingRegistrationFailedBody,
          steps: retrySteps,
          hintTitle: l10n.pairingPairedBeforeTitle,
          hintBody: l10n.pairingPairedBeforeBody,
          detail: detail,
        );
    }
  }

  final String title;
  final String body;
  final List<String> steps;
  final String? hintTitle;
  final String? hintBody;

  /// Technical code, shown small for support.
  final String detail;

  /// Technical code of a pairing or Bluetooth error, for support: the
  /// pairing step that failed and the Bluetooth error category under it,
  /// such as `notConfirmed/bondRejected`. Not translated.
  static String errorCode(Object error) => switch (error) {
    GrPairingException(:final failure, cause: BleException(:final code)) =>
      '${failure.name}/${code.name}',
    GrPairingException(:final failure) => failure.name,
    BleException(:final code) => code.name,
    _ => '${error.runtimeType}',
  };

  static bool _bondRejected(Object? cause) =>
      cause is BleException && cause.code == BleErrorCode.bondRejected;
}
