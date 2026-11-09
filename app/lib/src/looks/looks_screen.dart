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

/// Which saved looks the list shows.
enum LooksFilter { all, mono, colour }

/// The Looks page (mock `b-looks`): the camera's Custom slots C1–C3 on top,
/// the user's saved looks below. A look is dragged onto a slot, or loaded
/// from its menu.
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
                const SliverToBoxAdapter(
                  child: CameraTopBar(showSettings: false),
                ),
                SliverToBoxAdapter(
                  child: PageTitle(
                    l10n.looksTitle,
                    actions: [
                      RoundIconButton(
                        key: const Key('looks-new'),
                        icon: Icons.add_rounded,
                        label: l10n.looksNew,
                        onTap: _model.template == null
                            ? null
                            : () => unawaited(openNewLook(context, _model)),
                      ),
                      const SettingsButton(),
                    ],
                  ),
                ),
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
    if (model.state == SlotsState.unsupported) {
      body = _SlotsNote(text: l10n.looksSlotsUnsupported);
    } else if (model.state == SlotsState.needsFirmware) {
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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.looksOnCamera.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .8,
                    color: c.t3,
                  ),
                ),
              ),
              Text(
                l10n.looksCustomSlots,
                style: TextStyle(fontSize: 12, color: c.t3),
              ),
            ],
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
/// its name and base image. A saved look dropped on it is loaded into it;
/// a tap opens what it holds in the editor.
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
    final reading = slot == null;
    return DragTarget<SavedLook>(
      onWillAcceptWithDetails: (d) =>
          !reading &&
          model.loading == null &&
          (d.data.look?.offeredBy(model.body) ?? false),
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
          child: GestureDetector(
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
                      target: number,
                      source: saved == null
                          ? l10n.looksSlotShort(number)
                          : null,
                    ),
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
                        LookThumb(
                          photo: saved == null
                              ? null
                              : model.store.photoOf(saved),
                          look: look,
                        ),
                        Positioned(
                          left: 7,
                          top: 7,
                          child: PhotoTag(l10n.looksSlotShort(number)),
                        ),
                        if (reading || loading)
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reading
                              ? '—'
                              : slot.name.isEmpty
                              ? l10n.looksSlotUnnamed
                              : slot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          look == null
                              ? (reading ? ' ' : l10n.looksUnreadable)
                              : lookBaseLabel(l10n, look),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: c.t2,
                          ),
                        ),
                      ],
                    ),
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
      inSlots: inSlots,
      menu: _LookMenu(model: model, saved: saved),
    );
    if (look == null) return row;
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
          child: LookThumb(photo: photo, look: look),
        ),
      ),
      childWhenDragging: Opacity(opacity: .4, child: row),
      child: InkWell(
        onTap: () => unawaited(
          openLookEditor(
            context,
            model: model,
            name: saved.name,
            look: look,
            saved: saved,
            target: inSlots.firstOrNull ?? 1,
          ),
        ),
        child: Semantics(hint: l10n.looksDragHint, child: row),
      ),
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
  final List<int> inSlots;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final look = this.look;
    final source = saved.source;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 58,
              child: LookThumb(photo: photo, look: look),
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
                    if (inSlots.isEmpty)
                      MiniTag(l10n.looksTagSaved)
                    else
                      for (final n in inSlots) ...[
                        MiniTag(l10n.looksTagInSlot(n), accent: true),
                        const SizedBox(width: 4),
                      ],
                    const SizedBox(width: 6),
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
    final canLoad =
        look != null &&
        look.offeredBy(model.body) &&
        model.state == SlotsState.ready &&
        model.loading == null;
    return PopupMenuButton<_LookAction>(
      key: Key('look-menu:${saved.id}'),
      icon: Icon(Icons.more_horiz_rounded, color: c.t3, size: 20),
      tooltip: l10n.looksMore,
      onSelected: (a) => unawaited(_act(context, a)),
      itemBuilder: (context) => [
        if (look != null)
          PopupMenuItem(value: _LookAction.edit, child: Text(l10n.looksEdit)),
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
          target: model.slotsHolding(saved).firstOrNull ?? 1,
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
