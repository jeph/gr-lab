import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/looks/look_preview.dart';
import 'package:grlab/src/looks/look_spec.dart';
import 'package:grlab/src/looks/look_widgets.dart';
import 'package:grlab/src/looks/looks_model.dart';
import 'package:grlab/src/looks/looks_store.dart';
import 'package:grlab/src/shoot/shoot_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';

/// Opens the editor on [look] under [name]. [saved] is the library entry
/// it edits, if any; [target] is the slot its main action loads it into;
/// [source] says where a look that is not saved yet came from (a slot).
Future<void> openLookEditor(
  BuildContext context, {
  required LooksModel model,
  required String name,
  required Look look,
  required int target,
  SavedLook? saved,
  String? source,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => LookEditor(
      model: model,
      name: name,
      look: look,
      saved: saved,
      target: target,
      source: source,
    ),
  ),
);

/// Opens the editor on a new look: the first base image it can be given
/// ([LooksModel.basesFor]), with every adjustment neutral and the header of
/// [LooksModel.template] when there is one.
Future<void> openNewLook(BuildContext context, LooksModel model) async {
  final template = model.template;
  final base = model.basesFor(template ?? Look.onBase(LookBase.standard)).first;
  await openLookEditor(
    context,
    model: model,
    name: baseLabel(context.l10n, base),
    look: Look.onBase(base, template: template),
    target: 1,
  );
}

/// The look editor (mock `b-look-edit`): before and an approximate preview,
/// the base image, its parameters grouped as Tone, Colour, Detail and
/// Effects, then Save and, on a camera's Looks page, Load into the slot.
class LookEditor extends StatefulWidget {
  const new({
    required this.model,
    required this.name,
    required this.look,
    required this.target,
    super.key,
    this.saved,
    this.source,
  });

  final LooksModel model;
  final String name;
  final Look look;
  final SavedLook? saved;
  final int target;
  final String? source;

  @override
  State<LookEditor> createState() => _LookEditorState();
}

enum _EditorAction { rename, load1, load2, load3, delete }

class _LookEditorState extends State<LookEditor> {
  late Look _look = widget.look;
  late String _name = widget.name;
  late SavedLook? _saved = widget.saved;
  late int _target = widget.target;
  LookGroup? _group;

  /// The chip of the base the editor opened on, scrolled into view once.
  final GlobalKey _openedBase = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _openedBase.currentContext;
      if (chip != null) Scrollable.ensureVisible(chip, alignment: .5);
    });
  }

  LooksModel get _model => widget.model;

  /// The look differs from its saved version, or has none.
  bool get _unsaved {
    final saved = _saved;
    return saved == null ||
        saved.name != _name ||
        saved.settings != _look.settings;
  }

  File? get _photo {
    final saved = _saved;
    return saved == null ? null : _model.store.photoOf(saved);
  }

  /// Stores the look, asking for a name when it is new, and says in a snack
  /// bar whether it reached the phone's storage, or in a dialog which saved
  /// look has its name or settings already.
  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final saved = _saved;
    final data = _look.toBytes();
    final name = saved != null
        ? _name
        : await askLookName(context, initial: _name);
    if (name == null || !mounted) return;
    setState(() => _name = name);
    final SavedLook stored;
    try {
      if (saved == null) {
        stored = await _model.store.add(
          name: name,
          data: data,
          source: widget.source,
        );
      } else {
        stored = saved.copyWith(name: name, data: data);
        await _model.store.update(stored);
      }
    } on LookConflict catch (conflict) {
      if (mounted) await showLookConflict(context, conflict);
      return;
    } on FileSystemException {
      showLooksMessage(messenger, l10n.looksSaveFailed(name));
      return;
    }
    if (mounted) setState(() => _saved = stored);
    showLooksMessage(messenger, l10n.looksSaved(name));
  }

  Future<void> _load(int number) async {
    setState(() => _target = number);
    await confirmAndLoad(
      context,
      _model,
      name: _name,
      look: _look,
      number: number,
    );
  }

  Future<void> _act(_EditorAction action) async {
    switch (action) {
      case _EditorAction.rename:
        final name = await askLookName(context, initial: _name);
        if (name != null && mounted) setState(() => _name = name);
      case _EditorAction.load1:
        await _load(1);
      case _EditorAction.load2:
        await _load(2);
      case _EditorAction.load3:
        await _load(3);
      case _EditorAction.delete:
        final saved = _saved;
        final l10n = context.l10n;
        final messenger = ScaffoldMessenger.of(context);
        if (saved == null || !await confirmDelete(context, saved)) return;
        try {
          await _model.store.delete(saved);
        } on FileSystemException {
          showLooksMessage(messenger, l10n.looksDeleteFailed(saved.name));
          return;
        }
        if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final c = GrColors.of(context);
      final l10n = context.l10n;
      final base = _look.base;
      final params = [
        for (final p in _look.values.keys)
          if (shownIn(_look, p)) p,
      ];
      final groups = [
        for (final g in LookGroup.values)
          if (params.any((p) => groupOf(p) == g)) g,
      ];
      final group = groups.contains(_group) ? _group! : groups.firstOrNull;
      final canLoad = _model.canLoad(_look);
      final save = _unsaved ? () => unawaited(_save()) : null;
      return Scaffold(
        key: const Key('look-editor'),
        appBar: AppBar(
          leading: const BackButton(),
          title: Text(_name, overflow: TextOverflow.ellipsis),
          actions: [
            PopupMenuButton<_EditorAction>(
              key: const Key('look-editor-menu'),
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: l10n.looksMore,
              onSelected: (a) => unawaited(_act(a)),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _EditorAction.rename,
                  child: Text(l10n.looksRename),
                ),
                if (_model.onCamera)
                  for (final (n, a) in const [
                    (1, _EditorAction.load1),
                    (2, _EditorAction.load2),
                    (3, _EditorAction.load3),
                  ])
                    PopupMenuItem(
                      value: a,
                      enabled: canLoad,
                      child: Text(l10n.looksLoadInto(n)),
                    ),
                if (_saved != null)
                  PopupMenuItem(
                    value: _EditorAction.delete,
                    child: Text(
                      l10n.looksDelete,
                      style: TextStyle(color: c.danger),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 208,
              child: Row(
                children: [
                  Expanded(
                    child: _PreviewPane(
                      label: l10n.looksBefore,
                      photo: _photo,
                      look: null,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _PreviewPane(
                      label: l10n.looksPreview,
                      photo: _photo,
                      look: _look,
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              key: const Key('look-bases'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    for (final b in _model.basesFor(_look))
                      Padding(
                        key: b == widget.look.base ? _openedBase : null,
                        padding: const EdgeInsets.only(right: 8),
                        child: _BaseChip(
                          key: ValueKey('look-base:${b.name}'),
                          label: baseLabel(l10n, b),
                          selected: base == b,
                          onTap: () =>
                              setState(() => _look = _look.withBase(b)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (group != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: ShootSegmented<LookGroup>(
                  key: const Key('look-groups'),
                  values: groups,
                  selected: group,
                  label: (g) => groupLabel(l10n, g),
                  onSelect: (g) => setState(() => _group = g),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 12),
                children: [
                  if (base == null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        l10n.looksUnreadable,
                        style: TextStyle(color: c.t2),
                      ),
                    ),
                  for (final p in params)
                    if (groupOf(p) == group)
                      _ParameterRow(
                        key: ValueKey('look-param:${p.name}'),
                        parameter: p,
                        value: _look.valueOf(p)!,
                        onChanged: (v) =>
                            setState(() => _look = _look.withValue(p, v)),
                      ),
                ],
              ),
            ),
            if (_model.onCamera && !_look.offeredBy(_model.body))
              Padding(
                key: const Key('look-not-offered'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  l10n.looksNotOffered(lookBaseLabel(l10n, _look)),
                  style: TextStyle(fontSize: 12.5, color: c.t2),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: _model.onCamera
                    ? Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: OutlinedButton(
                              key: const Key('look-save'),
                              onPressed: save,
                              child: Text(l10n.looksSave),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 8,
                            child: FilledButton.icon(
                              key: const Key('look-load'),
                              onPressed: canLoad
                                  ? () => unawaited(_load(_target))
                                  : null,
                              icon: _model.loading == _target
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.upload_rounded, size: 18),
                              label: Text(l10n.looksLoadInto(_target)),
                            ),
                          ),
                        ],
                      )
                    // Saving is all a look can do away from a camera.
                    : SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('look-save'),
                          onPressed: save,
                          child: Text(l10n.looksSave),
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// One half of the before/preview pair, with its tag.
class _PreviewPane extends StatelessWidget {
  const new({required this.label, required this.photo, required this.look});

  final String label;
  final File? photo;

  /// The look to approximate; null shows the photo as it is.
  final Look? look;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    final image = photo == null
        ? Image.asset('assets/welcome.jpg', fit: BoxFit.cover)
        : Image.file(photo, fit: BoxFit.cover, cacheWidth: 900);
    final look = this.look;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (look == null) image else LookPreview(look: look, child: image),
        Positioned(left: 8, bottom: 8, child: PhotoTag(label.toUpperCase())),
      ],
    );
  }
}

class _BaseChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Material(
      color: selected ? c.invBg : c.s2,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? Colors.transparent : c.line),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? c.invFg : c.t2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One parameter (mock `.slider`): a slider for a signed adjustment, a
/// segmented control for a choice, or just the value when its range is
/// not known and it stays as the camera set it.
class _ParameterRow extends StatelessWidget {
  const new({
    required this.parameter,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final LookParameter parameter;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final range = lookRange(parameter);
    final header = Row(
      children: [
        Expanded(
          child: Text(
            parameterLabel(l10n, parameter),
            style: const TextStyle(fontSize: 14),
          ),
        ),
        Text(
          valueLabel(l10n, parameter, value),
          style: GrFonts.monoStyle(context, size: 13, color: c.t2),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          switch (range?.kind) {
            null => Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                l10n.looksParamFixed,
                style: TextStyle(fontSize: 12, color: c.t3),
              ),
            ),
            LookValueKind.steps => _StepSlider(
              parameter: parameter,
              range: range!,
              value: value,
              onChanged: onChanged,
            ),
            LookValueKind.choice => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ShootSegmented<int>(
                values: [for (var v = range!.min; v <= range.max; v++) v],
                selected: value,
                label: (v) => valueLabel(l10n, parameter, v),
                onSelect: onChanged,
              ),
            ),
          },
        ],
      ),
    );
  }
}

/// A slider for a signed adjustment whose fill runs from 0 to the knob,
/// with a mark at 0 (mock `.track`).
class _StepSlider extends StatelessWidget {
  const new({
    required this.parameter,
    required this.range,
    required this.value,
    required this.onChanged,
  });

  final LookParameter parameter;
  final LookRange range;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final span = range.max - range.min;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.s4,
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
        showValueIndicator: ShowValueIndicator.never,
        tickMarkShape: SliderTickMarkShape.noTickMark,
        trackShape: _OriginTrackShape(
          origin: (range.initial - range.min) / span,
          mark: c.t3,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Slider(
        value: value.clamp(range.min, range.max).toDouble(),
        min: range.min.toDouble(),
        max: range.max.toDouble(),
        divisions: span,
        semanticFormatterCallback: (v) =>
            valueLabel(l10n, parameter, v.round()),
        onChanged: (v) {
          if (v.round() != value) onChanged(v.round());
        },
      ),
    );
  }
}

/// A track filled between [origin] (a fraction of its length) and the
/// thumb, with a [mark] at the origin.
class _OriginTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const new({required this.origin, required this.mark});

  final double origin;
  final Color mark;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required TextDirection textDirection,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final radius = Radius.circular(rect.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor!,
    );
    final x = textDirection == TextDirection.rtl
        ? rect.right - rect.width * origin
        : rect.left + rect.width * origin;
    final fill = Rect.fromLTRB(
      x < thumbCenter.dx ? x : thumbCenter.dx,
      rect.top,
      x < thumbCenter.dx ? thumbCenter.dx : x,
      rect.bottom,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(fill, radius),
        Paint()..color = sliderTheme.activeTrackColor!,
      )
      ..drawRect(
        Rect.fromCenter(
          center: Offset(x, rect.center.dy),
          width: 2,
          height: 12,
        ),
        Paint()..color = mark,
      );
  }
}
