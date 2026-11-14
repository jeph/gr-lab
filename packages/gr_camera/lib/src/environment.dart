import 'dart:async';
import 'dart:io';

import 'package:gr_camera/src/platform/background_time.dart';
import 'package:gr_camera/src/platform/ble_transport.dart';
import 'package:gr_camera/src/platform/inert.dart';
import 'package:gr_camera/src/platform/permissions.dart';
import 'package:gr_camera/src/platform/phone_location.dart';
import 'package:gr_camera/src/platform/tracing_phone_location.dart';
import 'package:gr_camera/src/platform/tracing_wifi_control.dart';
import 'package:gr_camera/src/platform/wifi_control.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// Everything the camera layer needs from the phone, built once at start-up:
/// the Bluetooth transport, the Wi-Fi control, the phone's location
/// service, where the camera serves HTTP and the [TraceSink] every
/// exchange goes to.
///
/// The real device uses [GrCameraEnvironment.device]; the demo and tests
/// build one from a simulated camera's transport, Wi-Fi control and HTTP
/// client. Sessions, pairing runs and scanners are created from it
/// (`CameraSession`, `PairingRun`, `NearbyScanner`, `PresenceScanner`).
final class GrCameraEnvironment {
  /// [ble], [wifi] and [location] are wrapped so every Bluetooth exchange,
  /// Wi-Fi call and location call reaches [trace]. Without [location] the
  /// app may never locate the phone.
  /// [httpFactory] overrides the HTTP client a session builds (the demo
  /// camera serves on a loopback port). [wifiApprovalShown] emits when the
  /// OS's own network screen covers the app during a join (Android's
  /// approval list). [ensureBluetoothPermission] asks for the Bluetooth
  /// permission where the OS requires one; without it permission is
  /// assumed. [setNativeLogging] turns logging in the native code on or off.
  /// `beginBackgroundTime` asks the OS for time to finish work off screen
  /// ([backgroundTime]) and `forgetLeftoverWifi` removes camera networks an
  /// earlier run left joined ([forgetLeftoverWifi]), where
  /// [wifiOutlivesApp]; without them the time is unlimited and nothing is
  /// removed.
  new({
    required BleTransport ble,
    required WifiNetworkControl wifi,
    required this.trace,
    PhoneLocation? location,
    this.cameraHost = grCameraHost,
    this._httpFactory,
    this.sessionOptions = const GrSessionOptions(),
    this.wifiApprovalShown = const Stream.empty(),
    this._ensureBluetoothPermission,
    this._setNativeLogging,
    this.wifiOutlivesApp = false,
    this._beginBackgroundTime,
    this._forgetLeftoverWifi,
  }) : _ble = TracingBleTransport(ble, trace),
       _wifi = TracingWifiControl(wifi, trace),
       location = TracingPhoneLocation(
         location ?? const InertPhoneLocation(),
         trace,
       ),
       _nativeLocation = location is PlatformPhoneLocation ? location : null;

  /// The real device: Bluetooth through `universal_ble`; the camera network
  /// joined and the phone located by this package's native code.
  factory device({required TraceSink trace}) {
    final wifi = PlatformWifiControl(trace: trace);
    return GrCameraEnvironment(
      ble: UniversalBleTransport(),
      wifi: wifi,
      trace: trace,
      location: PlatformPhoneLocation(trace: trace),
      wifiApprovalShown: wifi.approvalShown,
      ensureBluetoothPermission: ensureBluetoothPermission,
      setNativeLogging: wifi.setLogging,
      wifiOutlivesApp: Platform.isIOS,
      beginBackgroundTime: wifi.beginBackgroundTime,
      forgetLeftoverWifi: wifi.forgetLeftovers,
    );
  }

  /// Receives every exchange with a camera and with the phone's Bluetooth,
  /// Wi-Fi and location service on its behalf.
  final TraceSink trace;

  /// The phone's location service, for live geotagging and the location
  /// history; every call and every position taken for a camera is traced.
  final PhoneLocation location;

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

  /// A camera network joined for the app stays joined when the OS suspends
  /// or ends the app, and a suspended app runs no code to leave it: iOS,
  /// whose `NEHotspotConfiguration` belongs to the system. The app then
  /// leaves the camera's Wi-Fi when it goes off screen, in time it asks for
  /// with [backgroundTime], and calls [forgetLeftoverWifi] when it starts.
  /// Android's join is a request of the app's process, which ends with it,
  /// and Android does not suspend an app that leaves the screen within
  /// seconds, so there the Wi-Fi is left for lack of use only.
  /// (research/protocol/connection-lifecycle.md §9, "What GR Photo does")
  final bool wifiOutlivesApp;

  final BleTransport _ble;
  final WifiNetworkControl _wifi;

  /// The location service when it is this package's native one, whose
  /// logging [setNativeLogging] switches.
  final PlatformPhoneLocation? _nativeLocation;
  final GrHttpClient Function(String host, TraceSink? trace)? _httpFactory;
  final Future<bool> Function()? _ensureBluetoothPermission;
  final Future<void> Function({required bool enabled})? _setNativeLogging;
  final Future<BackgroundTime> Function()? _beginBackgroundTime;
  final Future<List<String>> Function()? _forgetLeftoverWifi;

  /// Asks the OS for time to finish leaving a camera after the app went
  /// off screen; [why] goes to the trace. Unlimited where the platform has
  /// no such limit.
  Future<BackgroundTime> backgroundTime(String why) async {
    final begin = _beginBackgroundTime;
    if (begin == null) return BackgroundTime.unlimited();
    _wifiEvent(TraceDirection.outbound, 'backgroundTime', {'why': why});
    final granted = await begin();
    _wifiEvent(TraceDirection.inbound, 'backgroundTime.done', {
      'why': why,
      'remainingMs': granted.remaining?.inMilliseconds,
    });
    return BackgroundTime(
      remaining: granted.remaining,
      end: () async {
        _wifiEvent(TraceDirection.outbound, 'backgroundTime.end', {'why': why});
        await granted.end();
      },
    );
  }

  /// Where a camera network outlives the app ([wifiOutlivesApp]), removes
  /// the ones an earlier run of the app left joined: iOS ended it before
  /// it could leave. Call once at start-up, before any session joins.
  Future<void> forgetLeftoverWifi() async {
    final forget = _forgetLeftoverWifi;
    if (!wifiOutlivesApp || forget == null) return;
    _wifiEvent(TraceDirection.outbound, 'forgetLeftovers');
    final ssids = await forget();
    _wifiEvent(TraceDirection.inbound, 'forgetLeftovers.done', {
      'ssids': ssids,
    });
  }

  /// Turns logging in the phone-side native code (the Wi-Fi joining code
  /// and the location code) on or off, following the
  /// app's debug logging setting. Native code logs nothing until this
  /// turns it on; environments without native code ignore it.
  Future<void> setNativeLogging({required bool enabled}) async {
    await _setNativeLogging?.call(enabled: enabled);
    await _nativeLocation?.setLogging(enabled: enabled);
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

  void _wifiEvent(
    TraceDirection direction,
    String kind, [
    Map<String, Object?> fields = const {},
  ]) => trace(
    TraceEvent(
      channel: TraceChannel.wifi,
      direction: direction,
      kind: kind,
      fields: fields,
    ),
  );

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
