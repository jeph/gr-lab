import 'dart:async';

import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: log,
    builder: (context, _) => GroupBox(
      children: [
        GroupRow(
          key: const Key('setting-debug-log'),
          icon: Icons.bug_report_outlined,
          title: 'Enable debug logging',
          subtitle: 'Keeps app and camera logs for bug reports',
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
            title: 'Export log',
            trailing: TrailingFit.value(context, formatLogSize(log.sizeBytes)),
            onTap: () => unawaited(_export(context)),
          ),
        ),
        GroupRow(
          key: const Key('setting-debug-log-clear'),
          icon: Icons.delete_outline_rounded,
          title: 'Clear log',
          onTap: () => unawaited(_clear(context)),
        ),
      ],
    ),
  );

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // The iPad share sheet points at the row it came from.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final String? message;
    try {
      message = await log.export(origin: origin)
          ? null
          : 'The log is empty. Nothing to export.';
    } on Exception {
      // A full disk while copying, or the share sheet failing to open: say
      // so rather than leave the tap without an answer.
      _show(messenger, "Couldn't export the log. Try again.");
      return;
    }
    if (message != null) _show(messenger, message);
  }

  Future<void> _clear(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final c = GrColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the log?'),
        content: const Text('The debug log is deleted from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('debug-log-clear-confirm'),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await log.clear();
    } on Exception {
      _show(messenger, "Couldn't clear the log. Try again.");
      return;
    }
    _show(messenger, 'Log cleared');
  }

  /// The screen may have closed while the log was busy.
  static void _show(ScaffoldMessengerState messenger, String text) {
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// `1234567` → `1.2 MB`; the log size shown next to Export.
String formatLogSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
