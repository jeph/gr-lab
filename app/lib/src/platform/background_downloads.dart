import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:grlab/src/services.dart';

/// [BackgroundDownloads] over the `io.jeph.grlab/downloads` method channel.
///
/// `show` sends `{paused, title, detail, camera, fraction, toggle, cancel,
/// channel}` and `hide` `{finished}`; the platform calls `action` back with
/// `pause`, `resume` or `cancel`. Android (`DownloadService.kt`) answers
/// with a foreground service and its notification, iOS
/// (`BackgroundDownloadsPlugin.swift`) with a continued processing task.
/// A platform that cannot start its background work says why in the
/// call's error, which goes to the debug log: the download itself carries
/// on for as long as the system lets the app run.
final class PlatformBackgroundDownloads implements BackgroundDownloads {
  new({this._channel = const MethodChannel('io.jeph.grlab/downloads')}) {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _actions = StreamController<BackgroundDownloadAction>.broadcast();
  String? _lastFailure;

  @override
  Stream<BackgroundDownloadAction> get actions => _actions.stream;

  @override
  Future<void> show(BackgroundDownloadStatus status) => _invoke('show', {
    'paused': status.paused,
    'title': status.title,
    'detail': status.detail,
    'camera': status.cameraName,
    'fraction': status.fraction,
    'toggle': status.toggleLabel,
    'cancel': status.cancelLabel,
    'channel': status.channelName,
  });

  @override
  Future<void> hide({required bool finished}) =>
      _invoke('hide', {'finished': finished});

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
      _lastFailure = null;
    } on PlatformException catch (e) {
      // A status goes out every second: say why once, not every time.
      final failure = '$method: ${e.code} ${e.message}';
      if (failure == _lastFailure) return;
      _lastFailure = failure;
      debugPrint('Background downloads: $failure');
    } on MissingPluginException {
      // A platform without the channel downloads in the foreground only.
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'action') throw MissingPluginException();
    final action = BackgroundDownloadAction.values.asNameMap()[call.arguments];
    if (action != null) _actions.add(action);
  }
}
