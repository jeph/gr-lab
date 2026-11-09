import 'package:flutter/material.dart';

import 'package:grlab/src/connection/connection_controller.dart';

/// Explains the camera network before Android's own approval screen, the
/// first time a camera's Wi-Fi is joined, or after Android showed that
/// screen again and the join failed ([WifiConsentRequest.again]). Pops true
/// for Continue / Try again and false for Not now; whoever shows it closes
/// it if the request is withdrawn.
class WifiConsentDialog extends StatelessWidget {
  const new({required this.request, super.key});

  final WifiConsentRequest request;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('wifi-consent'),
    title: Text(
      request.again
          ? 'Choose "${request.ssid}"'
          : "Join ${request.cameraName}'s Wi-Fi?",
    ),
    content: Text(
      request.again
          ? "Android needs you to choose the camera's network in its list "
                'again. It asks after that network was disconnected in '
                'Wi-Fi settings. Choose "${request.ssid}" once and GR Lab '
                'joins it by itself again.'
          : "Photos come over the camera's own Wi-Fi network, "
                '"${request.ssid}". Android asks you to approve it once; '
                'after that GR Lab joins it by itself.',
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
        child: Text(request.again ? 'Try again' : 'Continue'),
      ),
    ],
  );
}
