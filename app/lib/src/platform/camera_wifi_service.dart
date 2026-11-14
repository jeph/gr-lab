import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:grphoto/src/services.dart';

/// [CameraWifiService] over the `io.jeph.grphoto/camera-wifi` method
/// channel.
///
/// `hold` sends `{title, text, camera, disconnect, channel}`, `keepAwake`
/// `{ms}` and `release` nothing; the platform calls `disconnect` back.
/// Android (`CameraWifiService.kt`) answers with a foreground service and
/// its notification; iOS has no such channel, and the calls do nothing
/// there. A service the platform did not start says why in the call's
/// error, which goes to the debug log.
final class PlatformCameraWifiService implements CameraWifiService {
  new({this._channel = const MethodChannel('io.jeph.grphoto/camera-wifi')}) {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _disconnects = StreamController<void>.broadcast();

  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  Future<void> hold(CameraWifiNotice notice) => _invoke('hold', {
    'title': notice.title,
    'text': notice.text,
    'camera': notice.cameraName,
    'disconnect': notice.disconnectLabel,
    'channel': notice.channelName,
  });

  @override
  Future<void> keepAwake(Duration duration) =>
      _invoke('keepAwake', {'ms': duration.inMilliseconds});

  @override
  Future<void> release() => _invoke('release');

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (e) {
      debugPrint('Camera Wi-Fi service: $method: ${e.code} ${e.message}');
    } on MissingPluginException {
      // iOS: nothing to hold.
    }
  }

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'disconnect':
        _disconnects.add(null);
      default:
        throw MissingPluginException();
    }
  }
}
