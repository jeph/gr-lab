import 'dart:async';

import 'package:gr_camera/src/geotag/camera_geotagging.dart';
import 'package:gr_camera/src/geotag/geotag_options.dart';
import 'package:gr_camera/src/platform/ble_transport.dart';
import 'package:gr_camera/src/platform/permissions.dart';
import 'package:gr_camera/src/platform/phone_location.dart';
import 'package:gr_camera/src/platform/tracing_wifi_control.dart';
import 'package:gr_camera/src/platform/wifi_control.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Everything the camera layer needs from the phone, built once at start-up:
/// the Bluetooth transport, the Wi-Fi control, the phone's own location,
/// where the camera serves HTTP and the [TraceSink] every exchange goes to.
///
/// The real device uses [GrCameraEnvironment.device]; the demo and tests
/// build one from a simulated camera's transport, Wi-Fi control and HTTP
/// client. Sessions, pairing runs and scanners are created from it
/// (`CameraSession`, `PairingRun`, `NearbyScanner`, `PresenceScanner`).
final class GrCameraEnvironment {
  /// [ble], [wifi] and [location] are wrapped so every Bluetooth exchange,
  /// Wi-Fi call and fix of the phone's position reaches [trace]. Without
  /// [location] the phone has none, and nothing is geotagged.
  /// [httpFactory] overrides the HTTP client a session builds (the demo
  /// camera serves on a loopback port). [wifiApprovalShown] emits when the
  /// OS's own network screen covers the app during a join (Android's
  /// approval list). [ensureBluetoothPermission] asks for the Bluetooth
  /// permission where the OS requires one; without it permission is
  /// assumed. [setNativeLogging] turns logging in the native code on or off.
  new({
    required BleTransport ble,
    required WifiNetworkControl wifi,
    required this.trace,
    PhoneLocation location = const NoPhoneLocation(),
    this.cameraHost = grCameraHost,
    this._httpFactory,
    this.sessionOptions = const GrSessionOptions(),
    this.geotagOptions = const GeotagOptions(),
    this.wifiApprovalShown = const Stream.empty(),
    this._ensureBluetoothPermission,
    this._setNativeLogging,
  }) : _ble = TracingBleTransport(ble, trace),
       _wifi = TracingWifiControl(wifi, trace),
       _location = TracingPhoneLocation(location, trace);

  /// The real device: Bluetooth through `universal_ble`, the camera network
  /// joined and the phone located by this package's native code.
  factory device({required TraceSink trace}) {
    final wifi = PlatformWifiControl(trace: trace);
    final location = PlatformPhoneLocation(trace: trace);
    return GrCameraEnvironment(
      ble: UniversalBleTransport(),
      wifi: wifi,
      trace: trace,
      location: location,
      wifiApprovalShown: wifi.approvalShown,
      ensureBluetoothPermission: ensureBluetoothPermission,
      setNativeLogging: ({required enabled}) => Future.wait([
        wifi.setLogging(enabled: enabled),
        location.setLogging(enabled: enabled),
      ]),
    );
  }

  /// Receives every exchange with a camera and with the phone's Bluetooth
  /// and Wi-Fi on its behalf.
  final TraceSink trace;

  /// Address of the camera's HTTP API; [grCameraHost] for a real camera.
  final String cameraHost;

  /// Timing and retry settings for camera sessions this environment opens.
  final GrSessionOptions sessionOptions;

  /// When sessions set a camera's clock and send it the phone's location.
  final GeotagOptions geotagOptions;

  /// Emits when the OS's own network screen covers the app while a join is
  /// in progress (Android's approval list). It also comes back for a camera
  /// that was approved before, after its network was disconnected by hand
  /// in Wi-Fi settings; a join that then fails is explained and retried
  /// only if the user agrees (see `WifiConsent.askAgain`).
  final Stream<void> wifiApprovalShown;

  final BleTransport _ble;
  final WifiNetworkControl _wifi;
  final PhoneLocation _location;
  final GrHttpClient Function(String host, TraceSink? trace)? _httpFactory;
  final Future<bool> Function()? _ensureBluetoothPermission;
  final Future<void> Function({required bool enabled})? _setNativeLogging;

  /// Turns logging in the phone-side native code (the Wi-Fi joining and
  /// location code) on or off, following the app's debug logging setting.
  /// Native code logs nothing until this turns it on; environments without
  /// native code ignore it.
  Future<void> setNativeLogging({required bool enabled}) async {
    await _setNativeLogging?.call(enabled: enabled);
  }

  /// Asks for Bluetooth scan/connect permission where the OS requires it
  /// (Android 12+ Nearby devices, iOS's first-use prompt). False when the
  /// user denied it.
  Future<bool> requestBluetoothPermission() async {
    final ask = _ensureBluetoothPermission;
    final granted = ask == null || await ask();
    _event('bluetooth.permission', {'granted': granted});
    return granted;
  }

  /// Whether Bluetooth can be used now: asks for permission first
  /// ([requestBluetoothPermission]; a denial reads as
  /// [BleAdapterState.unauthorized]), then reads the adapter state. With
  /// [waitForStartup], waits up to 3 s while the state is unknown or
  /// resetting: CoreBluetooth reports unknown until its manager has
  /// started.
  Future<BleAdapterState> bluetoothState({bool waitForStartup = false}) async {
    if (!await requestBluetoothPermission()) {
      return BleAdapterState.unauthorized;
    }
    var state = await _ble.adapterState();
    for (
      var i = 0;
      waitForStartup &&
          i < 10 &&
          (state == BleAdapterState.unknown ||
              state == BleAdapterState.resetting);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      state = await _ble.adapterState();
    }
    return state;
  }

  /// Live geotagging of the camera whose session is open: the phone's
  /// location sent to it while it is on.
  late final CameraGeotagging geotagging = createCameraGeotagging(this);

  /// Ends live geotagging and its use of the phone's location, for good:
  /// the app is done with this environment.
  void close() => geotagging.close();

  /// What the phone lets GR Photo know about where it is, without asking.
  Future<LocationAccess> locationAccess() => _location.access();

  /// Asks the system for the phone's location while the app is in use,
  /// when it can still be asked, and returns what the phone allows
  /// afterwards.
  Future<LocationAccess> requestLocationAccess() => _location.requestAccess();

  /// Opens the system settings where the user can allow location: the
  /// app's page, or on Android the phone's location switch when location
  /// is off for every app (iOS has no way to open that one).
  Future<void> openLocationSettings() => _location.openSettings();

  void _event(String kind, Map<String, Object?> fields) => trace(
    TraceEvent(
      channel: TraceChannel.session,
      direction: TraceDirection.internal,
      kind: kind,
      fields: fields,
    ),
  );
}

/// What this package's own classes read from an environment. Not exported:
/// the app reaches cameras only through the layer's API.
extension EnvironmentInternals on GrCameraEnvironment {
  /// The traced transport.
  BleTransport get ble => _ble;

  /// The traced phone Wi-Fi control.
  WifiNetworkControl get wifi => _wifi;

  /// The traced phone location.
  PhoneLocation get location => _location;

  /// Builds the HTTP client for a camera host; null uses the default client.
  GrHttpClient Function(String host, TraceSink? trace)? get httpFactory =>
      _httpFactory;

  /// Records one camera-layer decision on [TraceChannel.session].
  void event(String kind, [Map<String, Object?> fields = const {}]) =>
      _event(kind, fields);
}
