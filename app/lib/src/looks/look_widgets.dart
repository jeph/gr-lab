import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/library/image_orientation.dart';
import 'package:grphoto/src/looks/look_spec.dart';
import 'package:grphoto/src/looks/looks_model.dart';
import 'package:grphoto/src/looks/looks_store.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';
import 'package:grphoto/src/widgets/gr_text_field.dart';
import 'package:grphoto/src/widgets/toast.dart';

/// The picture standing for a look: the photo it was saved from, turned
/// upright by [orientation] ([SavedLook.photoOrientation]), or a swatch in
/// the colours of its base image.
class LookThumb extends StatelessWidget {
  const new({
    required this.photo,
    required this.look,
    super.key,
    this.orientation,
  });

  final File? photo;
  final Look? look;
  final int? orientation;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    if (photo != null) {
      return ExifOrientation(
        orientation: orientation ?? 1,
        child: Image.file(
          photo,
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, _, _) => _Swatch(look: look),
        ),
      );
    }
    return _Swatch(look: look);
  }
}

class _Swatch extends StatelessWidget {
  const new({required this.look});

  final Look? look;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final base = look?.base;
    final colors = base == null ? [c.s3, c.s2] : swatchColors(base);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.tune_rounded,
          size: 20,
          color: Colors.white.withValues(alpha: .7),
        ),
      ),
    );
  }
}

/// A small label on a photo (mock `.slot .c`, `.tag`).
class PhotoTag extends StatelessWidget {
  const new(this.text, {super.key, this.icon});

  final String text;

  /// A sign before the text, for a tag that does something when tapped.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final label = Text(
      text,
      style: const TextStyle(
        fontFamily: GrFonts.mono,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: GrColors.photoBadgeScrim,
        borderRadius: BorderRadius.circular(6),
      ),
      child: icon == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                label,
              ],
            ),
    );
  }
}

/// A tag under a look's name (mock `.minitag`): accent for "In C1".
class MiniTag extends StatelessWidget {
  const new(this.text, {super.key, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? c.accent.withValues(alpha: .16) : c.s3,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: accent ? c.accent : c.t2,
        ),
      ),
    );
  }
}

/// Asks before loading [look] under [name] into slot [number], naming what
/// it replaces, then loads it and says so in a toast. Returns whether
/// the camera took it; a refusal reaches [LooksModel.refusals].
Future<bool> confirmAndLoad(
  BuildContext context,
  LooksModel model, {
  required String name,
  required Look look,
  required int number,
}) async {
  final current = model.slots?[number - 1];
  final l10n = context.l10n;
  final toasts = Toasts.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => GrDialog(
      title: l10n.looksLoadConfirmTitle(name, number),
      message: current == null || current.name.isEmpty
          ? l10n.looksLoadConfirmBody(number)
          : l10n.looksLoadConfirmReplaces(number, current.name),
      actions: [
        GrDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        GrDialogAction.answer(
          key: const Key('looks-load-confirm'),
          label: l10n.looksLoadInto(number),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final loaded = await model.load(number, name: name, look: look);
  if (loaded) toasts.done(l10n.looksLoaded(name, number));
  return loaded;
}

/// Asks for a look's name; null when cancelled.
Future<String?> askLookName(
  BuildContext context, {
  required String initial,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _LookNameDialog(initial: initial),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// The dialog of [askLookName]. It keeps the field's controller for as long
/// as it is on screen, which is longer than until it answers: it is still
/// built while it leaves, as when the keyboard closes under it.
class _LookNameDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_LookNameDialog> createState() => _LookNameDialogState();
}

class _LookNameDialogState extends State<_LookNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GrDialog(
      title: l10n.looksNameTitle,
      content: GrTextField(
        key: const Key('looks-name-field'),
        controller: _name,
        autofocus: true,
        maxLength: lookNameMaxLength,
        inputFormatters: [
          FilteringTextInputFormatter.allow(lookNameCharacters),
        ],
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        GrDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.pop(context),
        ),
        GrDialogAction.answer(
          key: const Key('looks-name-ok'),
          label: l10n.looksNameSave,
          onPressed: () => Navigator.pop(context, _name.text),
        ),
      ],
    );
  }
}

/// Says why a look was not saved: the saved look [conflict] names has its
/// name, its settings or both.
Future<void> showLookConflict(BuildContext context, LookConflict conflict) {
  final l10n = context.l10n;
  final other = conflict.other.name;
  final exists = conflict.kind == LookConflictKind.nameAndSettings;
  return showDialog<void>(
    context: context,
    builder: (context) => GrDialog(
      key: Key('looks-conflict:${conflict.kind.name}'),
      title: exists ? l10n.looksConflictExistsTitle : l10n.looksConflictTitle,
      message: switch (conflict.kind) {
        LookConflictKind.nameAndSettings => l10n.looksConflictExistsBody(other),
        LookConflictKind.settings => l10n.looksConflictSettingsBody(other),
        LookConflictKind.name => l10n.looksConflictNameBody(other),
      },
      actions: [
        GrDialogAction.answer(
          key: const Key('looks-conflict-ok'),
          label: l10n.looksConflictOk,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}

/// Asks before deleting [saved] from the library.
Future<bool> confirmDelete(BuildContext context, SavedLook saved) async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => GrDialog(
      title: l10n.looksDeleteTitle(saved.name),
      message: l10n.looksDeleteBody,
      actions: [
        GrDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        GrDialogAction.destructive(
          key: const Key('looks-delete-confirm'),
          label: l10n.looksDelete,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return ok ?? false;
}
