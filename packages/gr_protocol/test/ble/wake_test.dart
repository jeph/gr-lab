import 'dart:typed_data';

import 'package:gr_protocol/src/ble/ble.dart';
import 'package:gr_protocol/src/ble/transport.dart';
import 'package:test/test.dart';

BleAdvertisement advert(String id, {required int serial, required int power}) =>
    BleAdvertisement(
      deviceId: id,
      rssi: -50,
      manufacturerData: {
        grRicohCompanyId: Uint8List.fromList([
          0xda,
          0x01,
          0x08,
          0x02,
          serial & 0xff,
          (serial >> 8) & 0xff,
          (serial >> 16) & 0xff,
          (serial >> 24) & 0xff,
          0x03,
          power,
        ]),
      },
    );

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  test('grSerialMatches compares digits only', () {
    expect(grSerialMatches('0012345', 12345), isTrue);
    expect(grSerialMatches('No. 12345', 12345), isTrue);
    expect(grSerialMatches('12346', 12345), isFalse);
    expect(grSerialMatches('abc', 0), isFalse);
    expect(grSerialMatches('1', null), isFalse);
  });

  test('waitAfterPowerOff waits only for the remainder of 6 s', () async {
    final past = DateTime.now().subtract(const Duration(seconds: 10));
    expect(await waitAfterPowerOff(past), Duration.zero);
    final recent = DateTime.now();
    final waited = await waitAfterPowerOff(recent, guard: ms(30));
    expect(waited > Duration.zero && waited <= ms(30), isTrue);
    expect(grWorldPowerOffReconnectGuard, const Duration(seconds: 6));
  });
}
