import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/shoot/camera_error_code.dart';
import 'package:grlab/src/shoot/shoot_model.dart';
import 'package:grlab/src/shoot/shoot_screen.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  GrSessionException waking(String message, [Object? cause]) =>
      GrSessionException(GrSessionPhase.waking, message, cause);

  test('a failed wake is classified from the session error', () {
    expect(
      ShootPowerFailure.of(waking('the camera did not turn on')),
      ShootPowerFailure.noAnswer,
    );
    expect(
      ShootPowerFailure.of(
        waking(
          'write failed',
          const BleException(BleErrorCode.poweredOff, 'off'),
        ),
      ),
      ShootPowerFailure.bluetoothOff,
    );
    expect(
      ShootPowerFailure.of(
        waking(
          'write failed',
          const BleException(BleErrorCode.bondRejected, 'removed'),
        ),
      ),
      ShootPowerFailure.needsPairing,
    );
    expect(
      ShootPowerFailure.of(
        const BleException(BleErrorCode.notConnected, 'gone'),
      ),
      ShootPowerFailure.linkLost,
    );
    expect(
      ShootPowerFailure.of(StateError('anything else')),
      ShootPowerFailure.noAnswer,
    );
  });

  test('every power failure has its own message', () {
    final messages = {
      for (final f in ShootPowerFailure.values) shootPowerFailureMessage(en, f),
    };
    expect(messages, hasLength(ShootPowerFailure.values.length));
    expect(
      shootPowerFailureMessage(en, ShootPowerFailure.noAnswer),
      "The camera didn't answer.",
    );
  });

  test('error codes are codes, never the error text', () {
    expect(
      cameraErrorCode(
        const GrApiException(
          errCode: 412,
          route: 'PUT /v1/params/camera',
          httpStatus: 412,
          errMsg: 'Precondition Failed',
        ),
      ),
      '412',
    );
    expect(
      cameraErrorCode(const BleException(BleErrorCode.gatt, 'write failed')),
      'gatt',
    );
    expect(
      cameraErrorCode(
        waking('write failed', const BleException(BleErrorCode.timeout, 't')),
      ),
      'timeout',
    );
    expect(cameraErrorCode(TimeoutException('slow')), 'timeout');
    expect(cameraErrorCode(waking('the camera did not turn on')), isNull);
    expect(cameraErrorCode(StateError('no')), isNull);
  });

  test('refusals read with or without a code', () {
    expect(
      shootRefusalMessage(en, const ShootRefusal(ShootRequest.shutter, 'gatt')),
      "The camera didn't take the picture (gatt)",
    );
    expect(
      shootRefusalMessage(en, const ShootRefusal(ShootRequest.driveMode, null)),
      "The camera didn't change the drive mode",
    );
  });
}
