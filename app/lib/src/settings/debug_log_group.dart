import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';

import 'package:grlab/src/debug/debug_log.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// The debug logging switch, export and clear, so a bug report can carry
/// the app's debug logs, including what went to and from the camera.
class DebugLogGroup extends StatelessWidget {
  const new({required this.log, super.key});

  final DebugLog log;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) => GroupBox(
        children: [
          GroupRow(
            key: const Key('setting-debug-log'),
            icon: Icons.bug_report_outlined,
            title: l10n.debugLogEnable,
            subtitle: log.available
                ? l10n.debugLogEnableSubtitle
                : l10n.debugLogUnavailable,
            trailing: Switch(
              key: const Key('setting-debug-log-switch'),
              value: log.enabled,
              onChanged: (v) => log.enabled = v,
            ),
            onTap: () => log.enabled = !log.enabled,
          ),
          Builder(
            builder: (context) => GroupRow(
              key: const Key('setting-debug-log-export'),
              icon: Icons.ios_share_rounded,
              title: l10n.debugLogExport,
              trailing: TrailingFit.value(
                context,
                formatLogSize(l10n, log.sizeBytes),
              ),
              onTap: () => unawaited(_export(context)),
            ),
          ),
          GroupRow(
            key: const Key('setting-debug-log-clear'),
            icon: Icons.delete_outline_rounded,
            title: l10n.debugLogClear,
            onTap: () => unawaited(_clear(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // The iPad share sheet points at the row it came from.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final bool exported;
    try {
      exported = await log.export(origin: origin);
    } on Exception {
      // A full disk while copying, or the share sheet failing to open: say
      // so rather than leave the tap without an answer.
      _show(messenger, l10n.debugLogExportFailed);
      return;
    }
    if (!exported) _show(messenger, l10n.debugLogEmpty);
  }

  Future<void> _clear(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.debugLogClearTitle),
        content: Text(l10n.debugLogClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('debug-log-clear-confirm'),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.debugLogClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await log.clear();
    } on Exception {
      _show(messenger, l10n.debugLogClearFailed);
      return;
    }
    _show(messenger, l10n.debugLogCleared);
  }

  /// The screen may have closed while the log was busy.
  static void _show(ScaffoldMessengerState messenger, String text) {
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// `1234567` → `1.2 MB` in English; the log size shown next to Export.
String formatLogSize(AppLocalizations l10n, int bytes) {
  const kilobyte = 1024;
  const megabyte = 1024 * kilobyte;
  if (bytes < kilobyte) return l10n.debugLogSizeBytes(bytes);
  if (bytes < megabyte) return l10n.debugLogSizeKilobytes(bytes / kilobyte);
  return l10n.debugLogSizeMegabytes(bytes / megabyte);
}
