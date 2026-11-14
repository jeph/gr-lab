import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gr_camera/src/platform/background_time.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// A camera Wi-Fi join the OS refused or could not complete.
final class WifiJoinException implements Exception {
  /// A failure with [code] and the platform's [message].
  const new(this.code, this.message);

  /// `background` (Android only joins for an app in the foreground),
  /// `invalid` (the OS rejected the SSID or passphrase), `superseded` (a
  /// newer join replaced this one), `cancelled` ([PlatformWifiControl.leave]
  /// during the join), `unsupported` (no native implementation) or
  /// `failed`. A declined prompt is [WifiJoinDeclined] and a suspected VPN
  /// block (Android) [WifiJoinVpnSuspected] instead.
  final String code;

  /// What the platform said, for the log.
  final String message;

  @override
  String toString() => 'WifiJoinException($code): $message';
}

/// [WifiNetworkControl] over the `io.jeph.grphoto/wifi` method channel, served
/// by this package's native code.
///
/// Android requests the camera AP with a `WifiNetworkSpecifier` and binds
/// the whole process to it, so dart:io HTTP and WebSocket traffic reaches
/// 192.168.0.1 instead of mobile data. When that network is lost the native
/// side unbinds, drops the request and reports it ([lost]), so the session
/// ends the Wi-Fi link at once instead of waiting for its liveness probe.
///
/// iOS applies a persistent `NEHotspotConfiguration`; the OS picks WPA2 or
/// WPA3 itself, so [WifiSecurity] only matters on Android. The
/// configuration outlives the app when iOS suspends or ends it, so iOS also
/// gives the app time to leave the network once it is off screen
/// ([beginBackgroundTime]) and removes what an ended app left installed
/// ([forgetLeftovers]).
///
/// Native events (`approvalShown`), every line the native code logs and the
/// native errors this class turns into a null or a no-op go to
/// [TraceChannel.wifi]: what the OS did during a join is otherwise
/// invisible in a tester's log. Calls and their outcomes are traced by the
/// environment's `TracingWifiControl`.
final class PlatformWifiControl implements WifiNetworkControl {
  /// A control on the native method channel, logging to the trace sink.
  new({
    required this._trace,
    this._channel = const MethodChannel('io.jeph.grphoto/wifi'),
  }) {
    // Android calls `lost` when the joined camera network goes away and
    // `approvalShown` when its network screen covers a join; iOS has
    // neither, so there the streams never emit. Both log their steps
    // (`log`).
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'lost':
          _lost.add(null);
        case 'approvalShown':
          _emit(TraceDirection.inbound, 'approvalShown');
          _approvalShown.add(null);
        case 'log':
          _emit(TraceDirection.internal, 'native', {'message': call.arguments});
        case 'backgroundTimeExpired':
          _emit(TraceDirection.inbound, 'backgroundTime.expired', {
            'id': call.arguments,
          });
      }
    });
  }

  final TraceSink _trace;
  final MethodChannel _channel;
  final _lost = StreamController<void>.broadcast();
  final _approvalShown = StreamController<void>.broadcast();

  @override
  Stream<void> get lost => _lost.stream;

  /// Emits when Android's own network screen covers the app while a join
  /// is in progress (passed on as `GrCameraEnvironment.wifiApprovalShown`).
  Stream<void> get approvalShown => _approvalShown.stream;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    // A non-positive window still gets one immediate native attempt rather
    // than an argument error, so the caller sees the real OS outcome.
    final ms = timeout.inMilliseconds < 1 ? 1 : timeout.inMilliseconds;
    final arguments = {
      'ssid': ssid,
      'passphrase': passphrase,
      'security': security.name,
      'timeoutMs': ms,
      'approved': approved,
    };
    try {
      await _channel.invokeMethod<void>('join', arguments);
    } on PlatformException catch (e) {
      final message = e.message ?? 'joining "$ssid" failed';
      if (e.code == 'timeout') throw TimeoutException(message, timeout);
      if (e.code == 'declined') throw WifiJoinDeclined(message);
      if (e.code == 'vpnSuspected') throw WifiJoinVpnSuspected(message);
      throw WifiJoinException(e.code, message);
    } on MissingPluginException {
      throw const WifiJoinException(
        'unsupported',
        'Wi-Fi join is not available on this platform',
      );
    }
  }

  @override
  Future<String?> currentSsid() async {
    try {
      return await _channel.invokeMethod<String>('currentSsid');
    } on PlatformException catch (e) {
      _emit(TraceDirection.inbound, 'native.currentSsid.error', {
        'code': e.code,
        'message': e.message,
      });
      return null;
    } on MissingPluginException {
      _emit(TraceDirection.inbound, 'native.currentSsid.error', {
        'code': 'unsupported',
      });
      return null;
    }
  }

  /// Turns the native Wi-Fi code's logging on or off: its logcat or unified
  /// log lines and the `log` lines it sends here. It follows the app's debug
  /// logging setting and is off until this is called.
  Future<void> setLogging({required bool enabled}) async {
    try {
      await _channel.invokeMethod<void>('setLogging', enabled);
    } on MissingPluginException {
      // No native code, so nothing to log.
    }
  }

  /// iOS: asks for time to finish work after the app left the screen (a
  /// background task), ended with [BackgroundTime.end]. When iOS takes it
  /// back first, the native side ends it and reports
  /// `backgroundTime.expired`. Without the native method (Android, which
  /// does not suspend an app this way) the time is unlimited.
  Future<BackgroundTime> beginBackgroundTime() async {
    final Map<String, Object?>? granted;
    try {
      granted = await _channel.invokeMapMethod<String, Object?>(
        'beginBackgroundTime',
      );
    } on MissingPluginException {
      return BackgroundTime.unlimited();
    }
    final id = granted?['id'];
    final ms = granted?['remainingMs'];
    return BackgroundTime(
      remaining: ms is int ? Duration(milliseconds: ms) : null,
      end: id is int
          ? () => _channel.invokeMethod<void>('endBackgroundTime', id)
          : null,
    );
  }

  /// iOS: removes every camera network configuration this app installed
  /// that no join of this run uses, and returns their SSIDs. An app that
  /// iOS ended while it was on a camera's Wi-Fi leaves its configuration
  /// behind, which keeps the phone on the camera network. Without the
  /// native method (Android, whose join ends with the app's process)
  /// nothing is removed.
  Future<List<String>> forgetLeftovers() async {
    try {
      return await _channel.invokeListMethod<String>('forgetLeftovers') ??
          const [];
    } on PlatformException catch (e) {
      _emit(TraceDirection.inbound, 'native.forgetLeftovers.error', {
        'code': e.code,
        'message': e.message,
      });
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> leave() async {
    try {
      await _channel.invokeMethod<void>('leave');
    } on MissingPluginException {
      // Nothing was joined through a channel that does not exist.
      _emit(TraceDirection.inbound, 'native.leave.error', {
        'code': 'unsupported',
      });
    }
  }

  void _emit(
    TraceDirection direction,
    String kind, [
    Map<String, Object?> fields = const {},
  ]) => _trace(
    TraceEvent(
      channel: TraceChannel.wifi,
      direction: direction,
      kind: kind,
      fields: fields,
    ),
  );
}
