import 'package:flutter/material.dart';

import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';

/// Explains the camera network before Android's own approval screen, the
/// first time a camera's Wi-Fi is joined, or after Android showed that
/// screen again and the join failed ([WifiConsentRequest.again]). Pops true
/// for Continue / Try again and false for Not now; whoever shows it closes
/// it if the request is withdrawn.
class WifiConsentDialog extends StatelessWidget {
  const new({required this.request, super.key});

  final WifiConsentRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final again = request.again;
    return GrDialog(
      key: const Key('wifi-consent'),
      title: again
          ? l10n.connectionWifiConsentAgainTitle(request.ssid)
          : l10n.connectionWifiConsentTitle(request.cameraName),
      message: again
          ? l10n.connectionWifiConsentAgainBody(request.ssid)
          : l10n.connectionWifiConsentBody(request.ssid),
      actions: [
        GrDialogAction(
          key: const Key('wifi-consent-later'),
          label: l10n.connectionWifiConsentNotNow,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        GrDialogAction.answer(
          key: const Key('wifi-consent-join'),
          label: again
              ? l10n.connectionWifiConsentTryAgain
              : l10n.connectionWifiConsentContinue,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
