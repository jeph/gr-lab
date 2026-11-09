import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

/// What the failure page shows for one failed pairing run: a title, a
/// sentence on what happened, numbered steps for the next attempt and an
/// optional extra hint.
@immutable
final class PairingFailureInfo {
  const new({
    required this.title,
    required this.body,
    required this.steps,
    this.hintTitle,
    this.hintBody,
    this.detail,
  });

  /// Maps a `pairCamera` error. Anything that is not a
  /// [GrPairingException] (a scan error, Bluetooth turning off) gets the
  /// generic page with the error text as [detail].
  factory from(Object error, {required String camera}) {
    if (error is! GrPairingException) {
      return PairingFailureInfo(
        title: "Pairing didn't finish",
        body:
            'Something went wrong talking to the camera. It may have left '
            'pairing mode. To try again:',
        steps: _retrySteps,
        hintTitle: _pairedBeforeTitle,
        hintBody: _pairedBeforeBody,
        detail: _describe(error),
      );
    }
    final detail = error.message;
    switch (error.failure) {
      case GrPairingFailure.notFound:
        return PairingFailureInfo(
          title: "Couldn't find $camera",
          body: 'The camera stopped showing up nearby. To try again:',
          steps: const [
            'Turn the camera on and keep it close to the phone',
            _actionModeStep,
            'Reopen Execute Pairing on the camera',
          ],
          detail: detail,
        );
      case GrPairingFailure.cameraOff:
        return PairingFailureInfo(
          title: '$camera is off',
          body: 'Pairing needs the camera switched on. To try again:',
          steps: const [
            'Turn the camera on',
            'Reopen Execute Pairing on the camera',
          ],
          detail: detail,
        );
      case GrPairingFailure.connectFailed:
        return PairingFailureInfo(
          title: "Couldn't connect to $camera",
          body:
              'The camera was found but the Bluetooth connection did not '
              'open. To try again:',
          steps: const [
            'Keep the camera close to the phone',
            'Reopen Execute Pairing on the camera',
            'Tap Pair on the phone, then press OK on the camera',
          ],
          detail: detail,
        );
      case GrPairingFailure.notConfirmed:
        if (_bondRejected(error.cause)) {
          // Reported when the peer refuses stored keys. Only seen on a Mac
          // so far, so the copy names what to do, not what the phone says.
          return PairingFailureInfo(
            title: '$camera refused this phone',
            body:
                'The camera rejected the pairing this phone still keeps for '
                'it. Remove the old pairing on both sides first:',
            steps: const [
              "Delete this phone from the camera's Paired Devices",
              "Delete the camera from this phone's Bluetooth settings",
              'Reopen Execute Pairing on the camera',
            ],
            detail: detail,
          );
        }
        return PairingFailureInfo(
          title: "Pairing didn't finish",
          body:
              "The camera didn't confirm, and it has left pairing mode. To "
              'try again:',
          steps: _retrySteps,
          hintTitle: _pairedBeforeTitle,
          hintBody: _pairedBeforeBody,
          detail: detail,
        );
      case GrPairingFailure.bondUnusable:
        return PairingFailureInfo(
          title: "$camera didn't answer after pairing",
          body:
              'The phone paired, but the camera would not share its '
              'details over the new pairing. Start again from a clean '
              'state:',
          steps: const [
            "Delete this phone from the camera's Paired Devices",
            "Delete the camera from this phone's Bluetooth settings",
            'Reopen Execute Pairing on the camera',
          ],
          detail: detail,
        );
      case GrPairingFailure.registrationFailed:
        return PairingFailureInfo(
          title: "$camera didn't keep the pairing",
          body:
              'The camera keeps a pairing only after OK is pressed on it. '
              'To try again:',
          steps: _retrySteps,
          hintTitle: _pairedBeforeTitle,
          hintBody: _pairedBeforeBody,
          detail: detail,
        );
    }
  }

  final String title;
  final String body;
  final List<String> steps;
  final String? hintTitle;
  final String? hintBody;

  /// Technical message, shown small for support.
  final String? detail;

  static const _retrySteps = [
    'Reopen Execute Pairing on the camera',
    'Tap Pair on the phone',
    'Press OK on the camera',
  ];

  static const _pairedBeforeTitle = 'Paired this phone before?';
  static const _pairedBeforeBody =
      "Delete it from the camera's Paired Devices and delete the camera from "
      "your phone's Bluetooth settings first";

  static bool _bondRejected(Object? cause) =>
      cause is BleException && cause.code == BleErrorCode.bondRejected;

  static String _describe(Object error) => switch (error) {
    BleException(:final message) => message,
    _ => '$error',
  };
}

/// A step too long for one line; a list literal may not hold adjacent strings
/// (no_adjacent_strings_in_list), so it lives here.
const _actionModeStep =
    'Check Action Mode is On (MENU → E6 Wireless Connection → '
    'Wireless Communication)';
