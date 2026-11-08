import 'package:flutter/material.dart';

import 'connection_controller.dart';

/// Explains the camera network before Android's own approval screen, the
/// first time a camera's Wi-Fi is joined. Closes itself when the request
/// goes away (the attempt was cancelled or replaced).
class WifiConsentDialog extends StatelessWidget {
  const WifiConsentDialog({
    super.key,
    required this.request,
    required this.connection,
  });

  final WifiConsentRequest request;
  final ConnectionController connection;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: connection,
    builder: (context, child) {
      if (!identical(connection.wifiConsent, request)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop(false);
        });
      }
      return child!;
    },
    child: AlertDialog(
      key: const Key('wifi-consent'),
      title: Text("Join ${request.cameraName}'s Wi-Fi?"),
      content: Text(
        'Photos come over the camera\'s own Wi-Fi network, '
        '"${request.ssid}". Android asks you to approve it once; after that '
        'GR Lab joins it by itself.',
      ),
      actions: [
        TextButton(
          key: const Key('wifi-consent-later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('wifi-consent-join'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}
