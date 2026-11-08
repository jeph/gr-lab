import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// A camera Wi-Fi join the OS refused or could not complete.
final class WifiJoinException implements Exception {
  const WifiJoinException(this.code, this.message);

  /// `background` (Android only joins for an app in the foreground),
  /// `invalid` (the OS rejected the SSID or passphrase), `superseded` (a
  /// newer join replaced this one), `cancelled` ([PlatformWifiControl.leave]
  /// during the join), `unsupported` (no native implementation) or
  /// `failed`. A declined prompt is [WifiJoinDeclined] instead.
  final String code;
  final String message;

  @override
  String toString() => 'WifiJoinException($code): $message';
}

/// [WifiNetworkControl] over the `io.jeph.grlab/wifi` method channel.
///
/// Android requests the camera AP with a `WifiNetworkSpecifier` and binds
/// the whole process to it, so dart:io HTTP and WebSocket traffic reaches
/// 192.168.0.1 instead of mobile data. When that network is lost the native
/// side unbinds and drops the request; [currentSsid] then reports null and
/// the next [join] issues a fresh request, which is what GrSession's
/// recovery does after its liveness probe fails.
///
/// iOS applies a persistent `NEHotspotConfiguration`; the OS picks WPA2 or
/// WPA3 itself, so [WifiSecurity] only matters on Android.
final class PlatformWifiControl implements WifiNetworkControl {
  PlatformWifiControl({
    this._channel = const MethodChannel('io.jeph.grlab/wifi'),
  });

  final MethodChannel _channel;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
  }) async {
    // A non-positive window still gets one immediate native attempt rather
    // than an argument error, so the caller sees the real OS outcome.
    final ms = timeout.inMilliseconds < 1 ? 1 : timeout.inMilliseconds;
    try {
      await _channel.invokeMethod<void>('join', {
        'ssid': ssid,
        'passphrase': passphrase,
        'security': security.name,
        'timeoutMs': ms,
      });
    } on PlatformException catch (e) {
      final message = e.message ?? 'joining "$ssid" failed';
      if (e.code == 'timeout') throw TimeoutException(message, timeout);
      if (e.code == 'declined') throw WifiJoinDeclined(message);
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
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> leave() async {
    try {
      await _channel.invokeMethod<void>('leave');
    } on MissingPluginException {
      // Nothing was joined through a channel that does not exist.
    }
  }
}
