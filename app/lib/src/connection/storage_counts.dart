import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:intl/intl.dart';

/// The pictures that still fit on each of the camera's storages, one
/// labelled line per storage that is there: the value of the camera
/// sheet's storage tile and of Shoot's shots-left readout.
///
/// Every storage shows because the camera does not say which one it saves
/// to: a GR IV follows its Shooting Memory Setting, which it reports over
/// neither link (research/protocol/ble.md §Storage information). The SD
/// card comes first \[design\].
class StorageCounts extends StatelessWidget {
  const new({
    required this.storages,
    required this.lineKeyPrefix,
    required this.soloSize,
    super.key,
  });

  /// The camera's storages as its status has them.
  final List<CameraStorage> storages;

  /// Each line's key is this, a hyphen and the storage's id
  /// (`camera-sheet-storage-sd1`).
  final String lineKeyPrefix;

  /// Font size of a count that has the readout to itself; two share its
  /// height at [_sharedSize].
  final double soloSize;

  static const _sharedSize = 15.0;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final count = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    final present = _presentSdFirst();
    if (present.isEmpty) {
      return Text(
        '—',
        style: GrFonts.monoStyle(context, size: soloSize, color: c.t1),
      );
    }
    final size = present.length > 1 ? _sharedSize : soloSize;
    // The lines shrink together to the readout's width instead of wrapping
    // or overflowing it at large text sizes and with long storage names.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final storage in present)
            Row(
              key: Key('$lineKeyPrefix-${storage.id}'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _label(l10n, storage),
                  style: TextStyle(fontSize: 11.5, color: c.t2),
                ),
                const SizedBox(width: 6),
                Text(switch (storage.remainingPictures) {
                  null => '—',
                  final remaining => count.format(remaining),
                }, style: GrFonts.monoStyle(context, size: size, color: c.t1)),
              ],
            ),
        ],
      ),
    );
  }

  List<CameraStorage> _presentSdFirst() {
    int rank(CameraStorage storage) => switch (storage.kind) {
      CameraStorageKind.sd1 => 0,
      CameraStorageKind.internal => 2,
      _ => 1,
    };
    return storages.where((s) => s.present).toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  static String _label(AppLocalizations l10n, CameraStorage storage) =>
      switch (storage.kind) {
        CameraStorageKind.sd1 => l10n.connectionSheetStorageSd,
        CameraStorageKind.internal => l10n.connectionSheetStorageInternal,
        _ when storage.id == '?' => l10n.connectionSheetStorageUnnamed,
        _ => storage.id,
      };
}
