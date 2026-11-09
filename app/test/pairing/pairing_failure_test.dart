import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/pairing/pairing_failure.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  PairingFailureInfo info(Object error) =>
      PairingFailureInfo.from(error, camera: 'GR IV', l10n: l10n);

  test('a refused stored pairing asks to remove it on both sides', () {
    final failure = info(
      const GrPairingException(
        GrPairingFailure.notConfirmed,
        'pairing was not completed',
        BleException(BleErrorCode.bondRejected, 'Peer removed pairing'),
      ),
    );
    expect(failure.title, 'GR IV refused this phone');
    expect(failure.steps, hasLength(3));
    expect(failure.hintTitle, isNull);
    expect(failure.detail, 'Error code: notConfirmed/bondRejected');
  });

  test('an unconfirmed pairing shows the retry steps and the hint', () {
    final failure = info(
      const GrPairingException(
        GrPairingFailure.notConfirmed,
        'pairing was not completed',
        BleException(BleErrorCode.timeout, 'timed out'),
      ),
    );
    expect(failure.title, "Pairing didn't finish");
    expect(failure.steps.first, 'Reopen Execute Pairing on the camera');
    expect(failure.hintTitle, 'Paired this phone before?');
    expect(failure.detail, 'Error code: notConfirmed/timeout');
  });

  test('every pairing failure lists steps and carries its code', () {
    for (final kind in GrPairingFailure.values) {
      final failure = info(GrPairingException(kind, 'detail'));
      expect(failure.steps, isNotEmpty, reason: kind.name);
      expect(failure.detail, 'Error code: ${kind.name}', reason: kind.name);
    }
    expect(
      info(const GrPairingException(GrPairingFailure.cameraOff, '')).title,
      'GR IV is off',
    );
  });

  test('other errors get the generic page with their code', () {
    final failure = info(
      const BleException(BleErrorCode.poweredOff, 'Bluetooth is off'),
    );
    expect(failure.title, "Pairing didn't finish");
    expect(failure.detail, 'Error code: poweredOff');
    expect(PairingFailureInfo.errorCode(StateError('x')), 'StateError');
  });
}
