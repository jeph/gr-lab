import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/pairing/pairing_failure.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  PairingFailureInfo info(Object error, {GrModel model = GrModel.gr4}) =>
      PairingFailureInfo.from(
        error,
        camera: model.shortName,
        body: CameraBody(model: model, firmware: null),
        l10n: l10n,
      );

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

  test('a GR IV is confirmed with OK, a GR III by typing its code', () {
    const unconfirmed = GrPairingException(
      GrPairingFailure.notConfirmed,
      'pairing was not completed',
      BleException(BleErrorCode.timeout, 'timed out'),
    );
    const unregistered = GrPairingException(
      GrPairingFailure.registrationFailed,
      'not registered',
    );
    const dropped = GrPairingException(
      GrPairingFailure.connectFailed,
      'link lost',
    );
    const typeCode = "Enter the camera's code on the phone";

    expect(info(unconfirmed).steps.last, 'Press OK on the camera');
    expect(info(unregistered).body, contains('OK is pressed'));
    expect(info(dropped).steps.last, contains('press OK'));

    for (final model in [
      GrModel.gr3,
      GrModel.gr3x,
      GrModel.gr3Hdf,
      GrModel.gr3xHdf,
    ]) {
      final reason = model.name;
      final steps = [
        ...info(unconfirmed, model: model).steps,
        ...info(unregistered, model: model).steps,
        ...info(dropped, model: model).steps,
      ];
      expect(steps.where((s) => s.contains('OK')), isEmpty, reason: reason);
      expect(steps.where((s) => s == typeCode), hasLength(3), reason: reason);
      expect(
        info(unregistered, model: model).body,
        contains('its code is entered on the phone'),
        reason: reason,
      );
    }
  });

  test("a camera that was not found is asked about its own model's menu", () {
    const notFound = GrPairingException(GrPairingFailure.notFound, 'no advert');
    expect(
      info(notFound).steps,
      contains(
        'Check Action Mode is On '
        '(MENU → E6 Wireless Connection → Wireless Communication)',
      ),
    );
    expect(
      info(notFound, model: GrModel.gr3x).steps,
      contains(
        "Check Action Mode isn't Disable "
        '(MENU → E6 Wireless Connection → Bluetooth Setting)',
      ),
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
