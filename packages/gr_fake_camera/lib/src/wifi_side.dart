part of 'fake_camera.dart';

final class _FakeWifi implements WifiNetworkControl {
  _FakeWifi(this._camera);

  final FakeGrCamera _camera;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
  }) => _camera._join(ssid, passphrase, timeout);

  @override
  Future<String?> currentSsid() async => _camera._joined ? _camera._ssid : null;

  @override
  Future<void> leave() async {
    _camera._joined = false;
  }

  @override
  Stream<void> get lost => _camera._wifiLost.stream;
}

extension on FakeGrCamera {
  /// The access point exists only after WLAN-on over BLE; a join started
  /// while it is still coming up waits for it within [timeout], as the
  /// platform join APIs do.
  Future<void> _join(String ssid, String passphrase, Duration timeout) async {
    await Future<void>.delayed(config.bleLatency);
    if (_closed || config.unreachable || !_wlanEnabled || ssid != _ssid) {
      throw FakeWifiException('network "$ssid" not found');
    }
    if (!_apReady) {
      final up = await (_apUp ??= Completer<bool>()).future.timeout(
        timeout,
        onTimeout: () => false,
      );
      if (!up) throw FakeWifiException('network "$ssid" not found');
    }
    await Future<void>.delayed(config.joinDelay);
    if (!_apReady) throw FakeWifiException('association with "$ssid" lost');
    if (passphrase != _passphrase) {
      throw FakeWifiException('authentication failed for "$ssid"');
    }
    _joined = true;
    final dropAfter = config.dropWifiAfter;
    if (dropAfter != null && !_dropArmed) {
      _dropArmed = true;
      _after(dropAfter, dropWifi);
    }
  }
}
