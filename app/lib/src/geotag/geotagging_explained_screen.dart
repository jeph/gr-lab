import 'package:flutter/material.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/theme/tokens.dart';

/// What background geotagging does, how it compares with live geotagging,
/// what the phone asks when it is turned on, and where and for how long
/// the location history is kept. Opened by Learn more in a camera's
/// details, under its Background geotagging switch.
class GeotaggingExplainedScreen extends StatelessWidget {
  const new({super.key});

  static Future<void> push(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const GeotaggingExplainedScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = GrColors.of(context);
    final days = GeotagController.historyKept.inDays;
    final paragraphs = [
      l10n.settingsBackgroundExplainHow(days),
      l10n.settingsBackgroundExplainHistory(days),
    ];
    return Scaffold(
      // The title is long in some languages, so it wraps in the page
      // instead of being cut off in the bar.
      appBar: AppBar(),
      body: SingleChildScrollView(
        key: const Key('background-geotag-explain'),
        padding: EdgeInsets.fromLTRB(
          22,
          0,
          22,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.settingsBackgroundGeotagging,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: c.t1,
                  ),
                ),
              ),
            ),
            for (final paragraph in paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  paragraph,
                  style: TextStyle(fontSize: 15, height: 1.45, color: c.t1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
