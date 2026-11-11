import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/data/cameras.dart';

/// Asks for a new display name for [camera] and saves it.
Future<void> showRenameCameraDialog(
  BuildContext context,
  SavedCamera camera,
) async {
  final cameras = AppScope.of(context).cameras;
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: camera.name),
  );
  if (name == null) return;
  await cameras.rename(camera.serial, name);
}

class _RenameDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final name = _text.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.connectionRenameTitle),
    content: TextField(
      key: const Key('camera-rename-field'),
      controller: _text,
      autofocus: true,
      maxLength: 32,
      textCapitalization: TextCapitalization.words,
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.connectionRenameCancel),
      ),
      ListenableBuilder(
        listenable: _text,
        builder: (context, _) => TextButton(
          key: const Key('camera-rename-save'),
          onPressed: _text.text.trim().isEmpty ? null : _save,
          child: Text(context.l10n.connectionRenameSave),
        ),
      ),
    ],
  );
}
