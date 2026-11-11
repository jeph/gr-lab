import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/camera/camera_top_bar.dart';
import 'package:grlab/src/looks/look_editor.dart';
import 'package:grlab/src/looks/look_spec.dart';
import 'package:grlab/src/looks/look_widgets.dart';
import 'package:grlab/src/looks/looks_model.dart';
import 'package:grlab/src/looks/looks_store.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';
import 'package:grlab/src/widgets/pressable.dart';
import 'package:grlab/src/widgets/skeleton.dart';

/// Which saved looks the list shows.
enum LooksFilter { all, mono, colour }

/// A Looks page (mock `b-looks`): the user's saved looks, stored on the
/// phone whichever camera they came from. On a camera's page the camera's
/// Custom slots C1–C3 are on top, and a look is dragged onto a slot or
/// loaded from its menu; on the phone's page (the home dock) the looks are
/// only kept and edited.
class LooksScreen extends StatefulWidget {
  const new({required this.model, super.key});

  final LooksModel model;

  @override
  State<LooksScreen> createState() => _LooksScreenState();
}

class _LooksScreenState extends State<LooksScreen> {
  late final StreamSubscription<LoadRefusal> _refusals;
  LooksFilter _filter = LooksFilter.all;

  LooksModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    _refusals = _model.refusals.listen(_sayRefused);
  }

  @override
  void dispose() {
    unawaited(_refusals.cancel());
    super.dispose();
  }

  void _sayRefused(LoadRefusal refusal) {
    if (!mounted) return;
    final l10n = context.l10n;
    final code = refusal.code;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            code == null
                ? l10n.looksLoadFailed(refusal.slot)
                : l10n.looksLoadFailedWithCode(refusal.slot, code),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_model, app.connection]),
      builder: (context, _) {
        final l10n = context.l10n;
        final store = _model.store;
        final all = store.looks;
        final shown = [
          for (final l in all)
            if (_matches(l)) l,
        ];
        return Scaffold(
          key: const Key('looks'),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                if (_model.onCamera) const SliverCameraTopBar(),
                SliverToBoxAdapter(
                  child: PageTitle(
                    l10n.looksTitle,
                    actions: [
                      RoundIconButton(
                        key: const Key('looks-new'),
                        icon: Icons.add_rounded,
                        label: l10n.looksNew,
                        onTap: () => unawaited(openNewLook(context, _model)),
                      ),
                      // The phone's page has no top bar to carry it.
                      if (!_model.onCamera) const SettingsButton(),
                    ],
                  ),
                ),
                if (_model.onCamera)
                  SliverToBoxAdapter(child: _SlotsSection(model: _model)),
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Row(
                      children: [
                        for (final f in LooksFilter.values) ...[
                          if (f != LooksFilter.all) const SizedBox(width: 8),
                          GrChip(
                            key: ValueKey('looks-chip:${f.name}'),
                            label: switch (f) {
                              LooksFilter.all => l10n.looksFilterAll,
                              LooksFilter.mono => l10n.looksFilterMono,
                              LooksFilter.colour => l10n.looksFilterColour,
                            },
                            count: f == LooksFilter.all ? all.length : null,
                            selected: _filter == f,
                            onTap: () => setState(() => _filter = f),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (shown.isEmpty)
                  SliverToBoxAdapter(
                    child: _EmptyLooks(filtered: all.isNotEmpty),
                  )
                else
                  SliverToBoxAdapter(
                    child: GroupBox(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        for (final look in shown)
                          _LookRow(
                            key: ValueKey('look:${look.id}'),
                            model: _model,
                            saved: look,
                          ),
                      ],
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matches(SavedLook saved) {
    if (_filter == LooksFilter.all) return true;
    final base = saved.look?.base;
    if (base == null) return false;
    return isMonoBase(base) == (_filter == LooksFilter.mono);
  }
}

/// "On the camera": C1–C3, or why they cannot be shown.
class _SlotsSection extends StatelessWidget {
  const new({required this.model});

  final LooksModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final slots = model.slots;
    final Widget body;
    if (model.state == SlotsState.needsFirmware) {
      body = _SlotsNote(
        text: l10n.looksSlotsNeedFirmware(model.slotsFirmware!),
      );
    } else if (model.state == SlotsState.failed && slots == null) {
      body = _SlotsNote(
        text: model.failureCode == null
            ? l10n.looksSlotsFailed
            : l10n.looksSlotsFailedWithCode(model.failureCode!),
        action: TextButton(
          key: const Key('looks-retry'),
          onPressed: model.retry,
          child: Text(l10n.looksTryAgain),
        ),
      );
    } else {
      body = Row(
        children: [
          for (var n = 1; n <= 3; n++) ...[
            if (n > 1) const SizedBox(width: 10),
            Expanded(
              child: _SlotCard(model: model, number: n, slot: slots?[n - 1]),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
          child: Text(
            l10n.upperCase(l10n.looksOnCamera),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: l10n.capitalSpacing(.8),
              color: c.t3,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: body,
        ),
      ],
    );
  }
}

class _SlotsNote extends StatelessWidget {
  const new({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(GrRadii.md),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13.5, color: c.t2)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// One Custom slot (mock `.slot`): the photo of the saved look it holds,
/// its name and base image, or a skeleton of them until the camera's slots
/// are read. A saved look dropped on it is loaded into it; a tap opens
/// what it holds in the editor.
class _SlotCard extends StatelessWidget {
  const new({required this.model, required this.number, required this.slot});

  final LooksModel model;
  final int number;
  final LookSlot? slot;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final slot = this.slot;
    final saved = slot == null ? null : model.savedLookIn(slot);
    final look = slot?.look;
    final loading = model.loading == number;
    final Widget picture;
    final Widget caption;
    if (slot == null) {
      picture = const Skeleton(child: SkeletonBox(radius: 0));
      caption = const Skeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLine(width: 64, fontSize: 12.5),
            SizedBox(height: 1),
            SkeletonLine(width: 44, fontSize: 11),
          ],
        ),
      );
    } else {
      picture = LookThumb(
        photo: saved == null ? null : model.store.photoOf(saved),
        orientation: saved?.photoOrientation,
        look: look,
      );
      caption = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.name.isEmpty ? l10n.looksSlotUnnamed : slot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 1),
          Text(
            look == null ? l10n.looksUnreadable : lookBaseLabel(l10n, look),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: c.t2,
            ),
          ),
        ],
      );
    }
    return DragTarget<SavedLook>(
      onWillAcceptWithDetails: (d) {
        final look = d.data.look;
        return slot != null && look != null && model.canLoad(look);
      },
      onAcceptWithDetails: (d) {
        final look = d.data.look;
        if (look == null) return;
        unawaited(
          confirmAndLoad(
            context,
            model,
            name: d.data.name,
            look: look,
            number: number,
          ),
        );
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Semantics(
          button: true,
          label: l10n.looksSlotLabel(number),
          child: Pressable(
            key: Key('looks-slot-$number'),
            onTap: slot == null || look == null
                ? null
                : () => unawaited(
                    openLookEditor(
                      context,
                      model: model,
                      name: slot.name,
                      look: look,
                      saved: saved,
                      slot: number,
                      source: saved == null
                          ? l10n.looksSlotShort(number)
                          : null,
                    ),
                  ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GrRadii.md),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(GrRadii.md),
                border: Border.all(
                  color: hovering ? c.accent : c.line,
                  width: hovering ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 84,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        picture,
                        Positioned(
                          left: 7,
                          top: 7,
                          child: PhotoTag(l10n.looksSlotShort(number)),
                        ),
                        if (loading)
                          const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                    child: caption,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A saved look in the list (mock `.lookcard`). Press and hold to drag it
/// onto a slot.
class _LookRow extends StatelessWidget {
  const new({required this.model, required this.saved, super.key});

  final LooksModel model;
  final SavedLook saved;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final look = saved.look;
    final photo = model.store.photoOf(saved);
    final inSlots = model.slotsHolding(saved);
    final row = _LookRowBody(
      saved: saved,
      look: look,
      photo: photo,
      inSlots: model.onCamera ? inSlots : null,
      menu: _LookMenu(model: model, saved: saved),
    );
    if (look == null) return row;
    final open = InkWell(
      onTap: () => unawaited(
        openLookEditor(
          context,
          model: model,
          name: saved.name,
          look: look,
          saved: saved,
        ),
      ),
      child: model.onCamera
          ? Semantics(hint: l10n.looksDragHint, child: row)
          : row,
    );
    // Away from a camera there is no slot to drop it on.
    if (!model.onCamera) return open;
    return LongPressDraggable<SavedLook>(
      data: saved,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 72,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 18)],
          ),
          child: LookThumb(
            photo: photo,
            orientation: saved.photoOrientation,
            look: look,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .4, child: row),
      child: open,
    );
  }
}

class _LookRowBody extends StatelessWidget {
  const new({
    required this.saved,
    required this.look,
    required this.photo,
    required this.inSlots,
    required this.menu,
  });

  final SavedLook saved;
  final Look? look;
  final File? photo;

  /// The slots holding the look, tagged on a camera's page; null on the
  /// phone's, which has no slots to tag.
  final List<int>? inSlots;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final look = this.look;
    final source = saved.source;
    final inSlots = this.inSlots;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 58,
              child: LookThumb(
                photo: photo,
                orientation: saved.photoOrientation,
                look: look,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  saved.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  look == null ? l10n.looksUnreadable : lookSummary(l10n, look),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.t2),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (inSlots != null) ...[
                      if (inSlots.isEmpty)
                        MiniTag(l10n.looksTagSaved)
                      else
                        for (final n in inSlots) ...[
                          MiniTag(l10n.looksTagInSlot(n), accent: true),
                          const SizedBox(width: 4),
                        ],
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        source == null
                            ? l10n.looksMadeInApp
                            : l10n.looksFrom(source),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: c.t3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          menu,
        ],
      ),
    );
  }
}

enum _LookAction { edit, rename, delete, load1, load2, load3 }

class _LookMenu extends StatelessWidget {
  const new({required this.model, required this.saved});

  final LooksModel model;
  final SavedLook saved;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final look = saved.look;
    final canLoad = look != null && model.canLoad(look);
    return PopupMenuButton<_LookAction>(
      key: Key('look-menu:${saved.id}'),
      icon: Icon(Icons.more_horiz_rounded, color: c.t3, size: 20),
      tooltip: l10n.looksMore,
      onSelected: (a) => unawaited(_act(context, a)),
      itemBuilder: (context) => [
        if (look != null)
          PopupMenuItem(value: _LookAction.edit, child: Text(l10n.looksEdit)),
        if (model.onCamera)
          for (final (n, a) in const [
            (1, _LookAction.load1),
            (2, _LookAction.load2),
            (3, _LookAction.load3),
          ])
            PopupMenuItem(
              value: a,
              enabled: canLoad,
              child: Text(l10n.looksLoadInto(n)),
            ),
        PopupMenuItem(value: _LookAction.rename, child: Text(l10n.looksRename)),
        PopupMenuItem(
          value: _LookAction.delete,
          child: Text(l10n.looksDelete, style: TextStyle(color: c.danger)),
        ),
      ],
    );
  }

  Future<void> _act(BuildContext context, _LookAction action) async {
    final look = saved.look;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _LookAction.edit:
        if (look == null) return;
        await openLookEditor(
          context,
          model: model,
          name: saved.name,
          look: look,
          saved: saved,
        );
      case _LookAction.load1 || _LookAction.load2 || _LookAction.load3:
        if (look == null) return;
        final n = switch (action) {
          _LookAction.load1 => 1,
          _LookAction.load2 => 2,
          _ => 3,
        };
        await confirmAndLoad(
          context,
          model,
          name: saved.name,
          look: look,
          number: n,
        );
      case _LookAction.rename:
        final name = await askLookName(context, initial: saved.name);
        if (name == null) return;
        try {
          await model.store.update(saved.copyWith(name: name));
        } on LookConflict catch (conflict) {
          if (context.mounted) await showLookConflict(context, conflict);
        } on FileSystemException {
          showLooksMessage(messenger, l10n.looksSaveFailed(name));
        }
      case _LookAction.delete:
        if (!await confirmDelete(context, saved)) return;
        try {
          await model.store.delete(saved);
        } on FileSystemException {
          showLooksMessage(messenger, l10n.looksDeleteFailed(saved.name));
        }
    }
  }
}

class _EmptyLooks extends StatelessWidget {
  const new({required this.filtered});

  /// Looks exist, but none matches the filter.
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Text(
        filtered ? l10n.looksEmptyFiltered : l10n.looksEmpty,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, height: 1.45, color: c.t2),
      ),
    );
  }
}
