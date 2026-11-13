import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Has the map fetch its tiles over the phone's internet connection. Call
/// it before a map is shown; a second call does nothing.
///
/// On Android all of GR Photo's traffic goes to the camera's Wi-Fi while
/// one is joined, where no tile is to be had: the app's native side
/// (`MapNetwork.kt`) gives MapLibre a client of its own for the phone's
/// default network. iOS needs nothing \[inferred\]: it sends only what is
/// addressed to the camera's network over it
/// (research/protocol/connection-lifecycle.md §9, "What GR Photo does").
Future<void> useInternetForMap({
  MethodChannel channel = const MethodChannel('io.jeph.grphoto/map'),
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await channel.invokeMethod<void>('useInternet');
  } on PlatformException catch (e) {
    debugPrint('The map keeps the default network: ${e.code}');
  } on MissingPluginException {
    // No native side: a test.
  }
}
