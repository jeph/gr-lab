import 'package:gr_fake_camera/gr_fake_camera.dart';
import 'package:gr_protocol/gr_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeGrCamera camera;

  setUp(() {
    camera = FakeGrCamera(
      config: fastConfig(bonded: true),
      media: syntheticMedia(),
    );
  });
  tearDown(() => camera.close());

  Future<void> join({String? ssid, String? passphrase}) => camera.wifi.join(
    ssid: ssid ?? camera.config.ssid,
    passphrase: passphrase ?? camera.config.passphrase,
    security: WifiSecurity.wpa2,
    timeout: const Duration(seconds: 1),
  );

  Future<GrBleClient> bleClient() async {
    final link = await camera.transport.connect(
      camera.config.deviceId,
      timeout: const Duration(seconds: 1),
    );
    final client = GrBleClient(link);
    await client.discover();
    addTearDown(link.disconnect);
    return client;
  }

  test('no WLAN-on over BLE: the network is not there', () async {
    await expectLater(join(), throwsA(isA<FakeWifiException>()));
    expect(camera.wifiJoined, isFalse);
    expect(await camera.wifi.currentSsid(), isNull);
  });

  test('after WLAN-on: wrong passphrase and wrong SSID fail, the BLE '
      'credentials join', () async {
    final client = await bleClient();
    final credentials = await client.readWifiCredentials();
    expect(credentials.ssid, camera.config.ssid);
    expect(credentials.passphrase, camera.config.passphrase);
    expect(credentials.wifiSecurity, WifiSecurity.wpa2);
    expect(credentials.issues, isEmpty);

    await client.setWlan(true);
    expect(camera.wlanOn, isTrue);
    await expectLater(
      join(passphrase: 'wrong-key'),
      throwsA(
        isA<FakeWifiException>().having(
          (e) => e.message,
          'message',
          contains('authentication'),
        ),
      ),
    );
    await expectLater(
      join(ssid: 'GR_OTHER'),
      throwsA(isA<FakeWifiException>()),
    );
    expect(camera.wifiJoined, isFalse);

    await join(ssid: credentials.ssid, passphrase: credentials.passphrase);
    expect(camera.wifiJoined, isTrue);
    expect(await camera.wifi.currentSsid(), camera.config.ssid);

    await camera.wifi.leave();
    expect(camera.wifiJoined, isFalse);
  });

  test('a join started while the AP comes up waits for it', () async {
    final client = await bleClient();
    await client.setWlan(true);
    // wlanOnDelay has not passed yet.
    await join();
    expect(camera.wifiJoined, isTrue);
  });

  test('WLAN-off over BLE ends the association', () async {
    final client = await bleClient();
    await client.setWlan(true);
    await join();
    await client.setWlan(false);
    expect(camera.wlanOn, isFalse);
    expect(camera.wifiJoined, isFalse);
  });

  test('WLAN-on is refused after an unrecoverable drop', () async {
    final client = await bleClient();
    camera.dropWifi(recoverable: false);
    await expectLater(client.setWlan(true), throwsA(isA<BleException>()));
  });
}
