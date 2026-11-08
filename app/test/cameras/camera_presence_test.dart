import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:grlab/src/cameras/camera_presence.dart';
import 'package:grlab/src/data/cameras.dart';

/// Hands the scan's advertisements to the test.
final class _ScanTransport implements BleTransport {
  // Closed in tearDown.
  // ignore: close_sinks
  final ads = StreamController<BleAdvertisement>.broadcast();

  @override
  Stream<BleAdvertisement> scan({List<String> serviceUuids = const []}) =>
      ads.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// A scan response as the GR firmware sends it: Ricoh payload with the
/// serial's digits as uint32 LE and the power flag (docs camera-models §4.1).
BleAdvertisement _ad(String deviceId, int serial, {required bool on}) =>
    BleAdvertisement(
      deviceId: deviceId,
      rssi: -60,
      manufacturerData: {
        grRicohCompanyId: Uint8List.fromList([
          0xDA, 0x01, 0x07, 0x02, //
          serial & 0xFF, (serial >> 8) & 0xFF,
          (serial >> 16) & 0xFF, (serial >> 24) & 0xFF,
          0x03, on ? 1 : 0,
        ]),
      },
    );

SavedCamera _camera(String serial, {String deviceId = 'AA:AA:AA:AA:AA:AA'}) =>
    SavedCamera(
      paired: GrPairedCamera(deviceId: deviceId, serialNumber: serial),
      name: 'GR IV',
      pairedAt: DateTime(2026, 11),
    );

void main() {
  late _ScanTransport transport;
  late CameraPresence presence;

  setUp(() {
    transport = _ScanTransport();
    presence = CameraPresence(transport)..start();
  });

  tearDown(() async {
    presence.dispose();
    await transport.ads.close();
  });

  Future<void> advertise(BleAdvertisement ad) async {
    transport.ads.add(ad);
    await pumpEventQueue();
  }

  test('a camera advertising under another address is found by the digits '
      'of its serial, however the camera writes them', () async {
    await advertise(_ad('BB:BB:BB:BB:BB:BB', 123456, on: false));
    expect(presence.of(_camera('00123456')), Presence.nearbyOff);
    expect(presence.of(_camera('No.123456')), Presence.nearbyOff);
    expect(presence.of(_camera('1234567')), Presence.away);
  });

  test('a scan response without the Ricoh payload keeps the serial and '
      'power state the primary packet had', () async {
    await advertise(_ad('BB:BB:BB:BB:BB:BB', 1234567, on: true));
    await advertise(
      const BleAdvertisement(deviceId: 'BB:BB:BB:BB:BB:BB', rssi: -60),
    );
    expect(presence.of(_camera('1234567')), Presence.nearbyOn);
  });

  test('the paired address matches without a Ricoh payload', () async {
    await advertise(
      const BleAdvertisement(deviceId: 'AA:AA:AA:AA:AA:AA', rssi: -60),
    );
    expect(presence.of(_camera('1234567')), Presence.nearby);
  });
}
