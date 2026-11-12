import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/geotag/geotag_model.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// Offers live geotagging for the current camera in a sheet over
/// [context]'s navigator, and saves the answer: Allow location turns it
/// on, and says so when the phone's location was then refused; Not now, and
/// closing the sheet any other way, leaves it off. Either way the offer
/// does not come back.
Future<void> showGeotagOffer(BuildContext context, GeotagModel geotag) async {
  // The sheet's own context is gone once it has closed.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final allowed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const GeotagOffer(),
  );
  if (!(allowed ?? false)) {
    await geotag.turnOffLive();
    return;
  }
  final outcome = await geotag.turnOnLive();
  if (outcome != GeotagTurnOn.refused) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.geotagRefused)));
}

/// What the geotagging offer says, with its two buttons. Each closes the
/// sheet with the answer: true for Allow location, false for Not now.
class GeotagOffer extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final body = TextStyle(fontSize: 14.5, height: 1.4, color: c.t2);
    // `showModalBottomSheet` keeps a sheet clear of the top of the screen
    // only, so the buttons stay above the system's navigation area here.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('geotag-offer'),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.geotagOfferTitle,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
                color: c.t1,
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.geotagOfferBody, style: body),
            const SizedBox(height: 10),
            Text(l10n.geotagOfferCost, style: body),
            // Only Android shows a notification while the location is used.
            if (defaultTargetPlatform == TargetPlatform.android) ...[
              const SizedBox(height: 10),
              Text(l10n.geotagOfferNotification, style: body),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('geotag-offer-allow'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.geotagOfferAllow),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('geotag-offer-not-now'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.geotagOfferNotNow),
            ),
          ],
        ),
      ),
    );
  }
}
