import 'dart:async';

import 'package:gr_camera/src/platform/ble_transport.dart';
import 'package:gr_camera/src/platform/inert.dart';
import 'package:gr_camera/src/platform/permissions.dart';
import 'package:gr_camera/src/platform/phone_location.dart';
import 'package:gr_camera/src/platform/power_on_watch.dart';
import 'package:gr_camera/src/platform/tracing_phone_location.dart';
import 'package:gr_camera/src/platform/tracing_wifi_control.dart';
import 'package:gr_camera/src/platform/wifi_control.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Everything the camera layer needs from the phone, built once at start-up:
/// the Bluetooth transport, the Wi-Fi control, the phone's location
/// service, the watch for a camera being switched on, where the camera
/// serves HTTP and the [TraceSink] every exchange goes to.
///
/// The real device uses [GrCameraEnvironment.device]; the demo and tests
/// build one from a simulated camera's transport, Wi-Fi control and HTTP
/// client. Sessions, pairing runs and scanners are created from it
/// (`CameraSession`, `PairingRun`, `NearbyScanner`, `PresenceScanner`).
final class GrCameraEnvironment {
  /// [ble], [wifi], [location] and [powerOnWatch] are wrapped so every
  /// Bluetooth exchange, Wi-Fi call, location call and watch call reaches
  /// [trace]. Without [location] the app may never locate the phone, and
  /// without [powerOnWatch] the platform never watches for a camera.
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
    PhoneLocation? location,
    PowerOnWatch? powerOnWatch,
    this.cameraHost = grCameraHost,
    this._httpFactory,
    this.sessionOptions = const GrSessionOptions(),
    this.wifiApprovalShown = const Stream.empty(),
    this._ensureBluetoothPermission,
    this._setNativeLogging,
  }) : _ble = TracingBleTransport(ble, trace),
       _wifi = TracingWifiControl(wifi, trace),
       location = TracingPhoneLocation(
         location ?? const InertPhoneLocation(),
         trace,
       ),
       powerOnWatch = TracingPowerOnWatch(
         powerOnWatch ?? const InertPowerOnWatch(),
         trace,
       ),
       _nativeLocation = location is PlatformPhoneLocation ? location : null,
       _nativeWatch = powerOnWatch is PlatformPowerOnWatch
           ? powerOnWatch
           : null;

  /// The real device: Bluetooth through `universal_ble`; the camera network
  /// joined, the phone located and cameras watched for by this package's
  /// native code.
  factory device({required TraceSink trace}) {
    final wifi = PlatformWifiControl(trace: trace);
    return GrCameraEnvironment(
      ble: UniversalBleTransport(),
      wifi: wifi,
      trace: trace,
      location: PlatformPhoneLocation(trace: trace),
      powerOnWatch: PlatformPowerOnWatch(trace: trace),
      wifiApprovalShown: wifi.approvalShown,
      ensureBluetoothPermission: ensureBluetoothPermission,
      setNativeLogging: wifi.setLogging,
    );
  }

  /// Receives every exchange with a camera and with the phone's Bluetooth,
  /// Wi-Fi and location service on its behalf.
  final TraceSink trace;

  /// The phone's location service, for live geotagging and the location
  /// history; every call and every position taken for a camera is traced.
  final PhoneLocation location;

  /// Notices a paired camera being switched on while the app is not on
  /// screen, or not running; every call and sighting is traced.
  final PowerOnWatch powerOnWatch;

  /// Address of the camera's HTTP API; [grCameraHost] for a real camera.
  final String cameraHost;

  /// Timing and retry settings for camera sessions this environment opens.
  final GrSessionOptions sessionOptions;

  /// Emits when the OS's own network screen covers the app while a join is
  /// in progress (Android's approval list). It also comes back for a camera
  /// that was approved before, after its network was disconnected by hand
  /// in Wi-Fi settings; a join that then fails is explained and retried
  /// only if the user agrees (see `WifiConsent.askAgain`).
  final Stream<void> wifiApprovalShown;

  final BleTransport _ble;
  final WifiNetworkControl _wifi;

  /// The location service and the watch when they are this package's
  /// native ones, whose logging [setNativeLogging] switches.
  final PlatformPhoneLocation? _nativeLocation;
  final PlatformPowerOnWatch? _nativeWatch;
  final GrHttpClient Function(String host, TraceSink? trace)? _httpFactory;
  final Future<bool> Function()? _ensureBluetoothPermission;
  final Future<void> Function({required bool enabled})? _setNativeLogging;

  /// Turns logging in the phone-side native code (the Wi-Fi joining code,
  /// the location code and the power-on watch) on or off, following the
  /// app's debug logging setting. Native code logs nothing until this
  /// turns it on; environments without native code ignore it.
  Future<void> setNativeLogging({required bool enabled}) async {
    await _setNativeLogging?.call(enabled: enabled);
    await _nativeLocation?.setLogging(enabled: enabled);
    await _nativeWatch?.setLogging(enabled: enabled);
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

  void _event(String kind, Map<String, Object?> fields) => trace(
    TraceEvent(
      channel: TraceChannel.session,
      direction: TraceDirection.internal,
      kind: kind,
      fields: fields,
    ),
  );
}

/// The phone's own location service without a camera environment around
/// it, for the demo: a simulated camera given the phone's real location
/// (`GrCameraEnvironment`'s `location`). Its native log lines go to [trace],
/// and the environment it is given to switches its logging.
PhoneLocation devicePhoneLocation({required TraceSink trace}) =>
    PlatformPhoneLocation(trace: trace);

/// What this package's own classes read from an environment. Not exported:
/// the app reaches cameras only through the layer's API.
extension EnvironmentInternals on GrCameraEnvironment {
  /// The traced transport.
  BleTransport get ble => _ble;

  /// The traced phone Wi-Fi control.
  WifiNetworkControl get wifi => _wifi;

  /// Builds the HTTP client for a camera host; null uses the default client.
  GrHttpClient Function(String host, TraceSink? trace)? get httpFactory =>
      _httpFactory;

  /// Records one camera-layer decision on [TraceChannel.session].
  void event(String kind, [Map<String, Object?> fields = const {}]) =>
      _event(kind, fields);
}
