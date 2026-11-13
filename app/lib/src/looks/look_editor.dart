import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/looks/look_base_stepper.dart';
import 'package:grphoto/src/looks/look_compare.dart';
import 'package:grphoto/src/looks/look_spec.dart';
import 'package:grphoto/src/looks/look_widgets.dart';
import 'package:grphoto/src/looks/looks_model.dart';
import 'package:grphoto/src/looks/looks_store.dart';
import 'package:grphoto/src/sample_photos.dart';
import 'package:grphoto/src/shoot/shoot_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/pressable.dart';

/// Opens the editor on [look] under [name]. [saved] is the library entry
/// it edits, if any; [slot] is the Custom slot it was opened from, which
/// its Load button loads into; [source] says where a look that is not
/// saved yet came from (a slot).
Future<void> openLookEditor(
  BuildContext context, {
  required LooksModel model,
  required String name,
  required Look look,
  SavedLook? saved,
  int? slot,
  String? source,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => LookEditor(
      model: model,
      name: name,
      look: look,
      saved: saved,
      slot: slot,
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
  );
}

/// The look editor (mock `b-look-edit`): a photo before and under the look
/// ([LookCompare]), the base image ([LookBaseStepper]), its parameters
/// grouped as Tone, Colour, Detail and Effects, then Save and, when it was
/// opened from a Custom slot, Load into that slot.
///
/// The preview (mock `look-photos` A) is the picture, with the choice of
/// comparison and the full-screen button over its top corners, and the
/// photos to preview on in a strip under it, or down its side in a window
/// that is short and wide \[design\]. It sits above the controls, beside
/// them where the screen is wider than it is tall, and scrolls with them
/// where it is too short for both \[design\]. On a foldable each has one
/// side of an upright fold, and half-open on a table the picture has the
/// upright half and everything else the flat one \[design\]. Its button
/// grows it to the whole screen, with the choice of photo and of
/// comparison and nothing else; a tap on its pictures is the comparison's
/// own there and in its place \[design\].
class LookEditor extends StatefulWidget {
  const new({
    required this.model,
    required this.name,
    required this.look,
    super.key,
    this.saved,
    this.slot,
    this.source,
  });

  final LooksModel model;
  final String name;
  final Look look;
  final SavedLook? saved;

  /// The Custom slot (1–3) the editor was opened from; null when it was
  /// opened from the library or on a new look.
  final int? slot;

  final String? source;

  @override
  State<LookEditor> createState() => _LookEditorState();
}

enum _EditorAction { rename, load1, load2, load3, delete }

class _LookEditorState extends State<LookEditor>
    with SingleTickerProviderStateMixin {
  late Look _look = widget.look;
  late String _name = widget.name;
  late SavedLook? _saved = widget.saved;
  LookGroup? _group;

  /// How far the preview is on its way to the whole screen: 0 in its place
  /// in the editor, 1 with the whole screen. The editor is rebuilt when it
  /// sets off and when it arrives, which is when the preview changes
  /// parents.
  late final AnimationController _expansion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addStatusListener((_) => setState(() {}));

  @override
  void dispose() {
    if (_fullscreen) _showSystemBars();
    _expansion.dispose();
    super.dispose();
  }

  void _enterFullscreen() {
    if (_fullscreen) return;
    setState(() => _fullscreen = true);
    _expand(to: 1);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  void _leaveFullscreen() {
    if (!_fullscreen) return;
    setState(() => _fullscreen = false);
    _expand(to: 0);
    _showSystemBars();
  }

  /// Grows the preview to the whole screen ([to] 1) or shrinks it back to
  /// its place ([to] 0); at once where the phone asks for less motion.
  void _expand({required double to}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _expansion.value = to;
    } else if (to == 0) {
      _expansion.reverse();
    } else {
      _expansion.forward();
    }
  }

  /// Brings back the status and navigation bars, as the rest of the app
  /// has them (Flutter's default, edge to edge).
  void _showSystemBars() =>
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  LooksModel get _model => widget.model;

  /// The look differs from its saved version, or has none.
  bool get _unsaved {
    final saved = _saved;
    return saved == null ||
        saved.name != _name ||
        saved.settings != _look.settings;
  }

  late final LookRenderer _renderer = lookRendererFor(_model.body);

  /// The photos the look can be previewed on: the one it was saved from,
  /// when it has one, then GR Photo's sample photos, each with the look its
  /// camera developed it with ([SamplePhoto.look]).
  ///
  /// A sample's own look has nothing to do with the look being edited, so
  /// the comparison starts from the sample under Standard instead
  /// \[design\], and shows all of what the look does. The look's own photo
  /// is compared as it was taken, which is where the look came from.
  late final List<PreviewPhoto> _photos = [
    ?_findOwnPhoto(),
    for (final sample in samplePhotos)
      PreviewPhoto(
        image: _previewSized(AssetImage(sample.asset)),
        rerender: LookRerender(_renderer, source: sample.look),
        before: Look.onBase(LookBase.standard),
      ),
  ];

  /// Whether the first of [_photos] is the look's own; the samples come
  /// after it.
  late final bool _hasOwnPhoto = _photos.length > samplePhotos.length;

  /// Which of [_photos] the user picked for the preview; null until they
  /// pick one, and the editor chooses ([_preview]).
  int? _picked;

  LookCompareMode _mode = LookCompareMode.slide;

  /// The preview has the whole screen or is on its way there: the system's
  /// bars are hidden, and Back brings the editor back before it closes it.
  bool _fullscreen = false;

  /// The preview and the controls keep their state when the screen turns
  /// and they change places, and the preview when it leaves its place for
  /// the whole screen.
  final GlobalKey _previewKey = GlobalKey();
  final GlobalKey _controlsKey = GlobalKey();

  /// The picture with its two controls keeps its state when the photos
  /// move from under it to its side, or leave it for the flat half of a
  /// foldable.
  final GlobalKey _paneKey = GlobalKey();

  /// The preview's place in the editor and the box the editor fills, for
  /// working out where on the screen that place is.
  final GlobalKey _placeKey = GlobalKey();
  final GlobalKey _stageKey = GlobalKey();

  /// [photo] no larger than the picture the renderer's effects come out
  /// best on.
  ImageProvider _previewSized(ImageProvider photo) => ResizeImage(
    photo,
    width: _renderer.pictureLongSide,
    height: _renderer.pictureLongSide,
    policy: ResizeImagePolicy.fit,
  );

  /// The photo the look was saved from, with the look it was developed
  /// with; null for a look without a photo.
  PreviewPhoto? _findOwnPhoto() {
    final saved = widget.saved;
    final file = saved == null ? null : _model.store.photoOf(saved);
    if (saved == null || file == null) return null;
    return PreviewPhoto(
      image: _previewSized(FileImage(file)),
      rerender: LookRerender(_renderer, source: saved.photoLook),
      orientation: saved.photoOrientation,
    );
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

  Future<void> _load(int number) =>
      confirmAndLoad(context, _model, name: _name, look: _look, number: number);

  void _setBase(LookBase base) => setState(() => _look = _look.withBase(base));

  /// Lists [bases] in a sheet and moves the look to the one picked.
  Future<void> _pickBase(List<LookBase> bases) async {
    final picked = await showLookBaseList(
      context,
      bases: bases,
      selected: _look.base,
    );
    if (picked != null && mounted) _setBase(picked);
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
      final canLoad = _model.canLoad(_look);
      final table = _tableFold(context);
      final book = table == null ? _bookFold(context) : null;
      // The same under either parent, so that it keeps its state when it
      // moves between them.
      final preview = KeyedSubtree(
        key: _previewKey,
        child: Builder(
          builder: (context) => _preview(context, pictureAlone: table != null),
        ),
      );
      final inPlace = _expansion.isDismissed;
      return PopScope(
        canPop: !_fullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leaveFullscreen();
        },
        child: Stack(
          key: _stageKey,
          fit: StackFit.expand,
          children: [
            // Out of sight under a preview that has the whole screen, the
            // editor keeps its state: where its controls were scrolled to,
            // above all.
            Offstage(
              offstage: _expansion.isCompleted,
              child: Scaffold(
                key: const Key('look-editor'),
                appBar: _bar(context, canLoad: canLoad),
                body: SafeArea(
                  top: false,
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, box) => _layout(
                      context,
                      box,
                      // Its place keeps its size while it is away.
                      preview: KeyedSubtree(
                        key: _placeKey,
                        child: inPlace ? preview : const SizedBox.expand(),
                      ),
                      canLoad: canLoad,
                      table: table,
                      book: book,
                    ),
                  ),
                ),
              ),
            ),
            if (!inPlace) _expanding(context, preview, table: table?.fold),
          ],
        ),
      );
    },
  );

  /// [preview] over the editor, between its place there and the whole
  /// screen or with the whole screen, on black that covers the editor as
  /// the preview grows \[design\]. On a foldable half-open on a [table]
  /// the whole screen is its upright half for the picture, and the flat
  /// half has the photos to pick from.
  Widget _expanding(
    BuildContext context,
    Widget preview, {
    required Rect? table,
  }) {
    final app = Theme.of(context);
    // Dark around the pictures: the app's theme when it is a dark one, as
    // the live view page does.
    final dark = app.brightness == Brightness.dark
        ? app
        : grTheme(GrColors.dark);
    final insets = MediaQuery.paddingOf(context);
    return AnimatedBuilder(
      animation: _expansion,
      // Laid out after the editor, so the preview's place is where this
      // frame has it: it moves when the system's bars come and go.
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final grown = Curves.easeInOutCubic.transform(_expansion.value);
          final window = Offset.zero & box.biggest;
          final whole = table == null
              ? insets
                    .copyWith(bottom: math.max(insets.bottom, 12))
                    .deflateRect(window)
              : Rect.fromLTRB(
                  insets.left,
                  insets.top,
                  window.right - insets.right,
                  table.top,
                );
          return Theme(
            data: grown < .5 ? app : dark,
            child: Material(
              color: Colors.black.withValues(alpha: grown),
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: Rect.lerp(_placeOnScreen() ?? whole, whole, grown)!,
                    child: preview,
                  ),
                  if (table != null)
                    Positioned(
                      left: insets.left,
                      right: insets.right,
                      top: table.bottom,
                      child: Opacity(
                        opacity: grown,
                        child: Builder(builder: _photoChoice),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Where on the screen the preview's place in the editor is; null until
  /// the editor has been laid out.
  Rect? _placeOnScreen() {
    final place = _placeKey.currentContext?.findRenderObject();
    final stage = _stageKey.currentContext?.findRenderObject();
    if (place is! RenderBox || stage is! RenderBox || !place.hasSize) {
      return null;
    }
    return place.localToGlobal(Offset.zero, ancestor: stage) & place.size;
  }

  /// The look's name, the way back and the menu of what else to do with
  /// the look.
  PreferredSizeWidget _bar(BuildContext context, {required bool canLoad}) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return AppBar(
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
    );
  }

  /// The fold or hinge the window lies across; null on a device without
  /// one, on a foldable's cover screen and in a window to one side of it.
  static ui.DisplayFeature? _foldOf(BuildContext context) =>
      MediaQuery.displayFeaturesOf(context)
          .where(
            (feature) =>
                feature.type == ui.DisplayFeatureType.fold ||
                feature.type == ui.DisplayFeatureType.hinge,
          )
          .firstOrNull;

  /// The fold of a foldable that is half-open on a table, where the window
  /// has room for the picture above it and for the controls under it: its
  /// bounds in the window, and how much of the window's height lies under
  /// it. [context] is the editor's own, whose insets are the window's.
  static ({Rect fold, double flat})? _tableFold(BuildContext context) {
    final feature = _foldOf(context);
    if (feature == null ||
        feature.state != ui.DisplayFeatureState.postureHalfOpened) {
      return null;
    }
    final fold = feature.bounds;
    if (fold.width <= fold.height) return null;
    final window = MediaQuery.sizeOf(context);
    final upright =
        fold.top - MediaQuery.paddingOf(context).top - kToolbarHeight;
    final flat =
        window.height - MediaQuery.viewInsetsOf(context).bottom - fold.bottom;
    if (upright < _leastHalf || flat < _leastHalf) return null;
    return (fold: fold, flat: flat);
  }

  /// The fold of a foldable where it stands upright in the window, flat or
  /// half-open like a book, with room for the controls on either side:
  /// the width ahead of it, which the preview takes, and its own.
  /// [context] is the editor's own, whose insets are the window's.
  static ({double preview, double gap})? _bookFold(BuildContext context) {
    final fold = _foldOf(context)?.bounds;
    if (fold == null || fold.height <= fold.width) return null;
    final insets = MediaQuery.paddingOf(context);
    final left = fold.left - insets.left;
    final right = MediaQuery.sizeOf(context).width - insets.right - fold.right;
    if (math.min(left, right) < _narrowestControls) return null;
    final leftFirst = Directionality.of(context) == TextDirection.ltr;
    return (preview: leftFirst ? left : right, gap: fold.width);
  }

  /// [preview] and the controls in a [box]: the preview above the
  /// controls, beside them where the box is wider than it is tall, and
  /// scrolling with them where it is too short for both. On a foldable
  /// whose fold stands upright ([book]) they are beside each other with the
  /// fold between them, whatever the box's shape, and on one half-open on
  /// a [table] the preview has the upright half and the controls, led by
  /// the choice of photo, the flat one \[design\].
  Widget _layout(
    BuildContext context,
    BoxConstraints box, {
    required Widget preview,
    required bool canLoad,
    required ({Rect fold, double flat})? table,
    required ({double preview, double gap})? book,
  }) {
    if (table != null) {
      final gap = table.fold.height;
      return Column(
        children: [
          SizedBox(
            height: math.max(0, box.maxHeight - gap - table.flat),
            child: preview,
          ),
          SizedBox(height: gap),
          Expanded(
            child: KeyedSubtree(
              key: _controlsKey,
              child: _onTable(context, canLoad: canLoad),
            ),
          ),
        ],
      );
    }
    final wide =
        book != null ||
        (box.maxWidth > box.maxHeight && box.maxWidth >= _wideFrom);
    // Too short to keep a picture worth looking at in place above a
    // parameter: the preview scrolls with the controls.
    final scrolls = !wide && box.maxHeight < _inPlaceFrom;
    final controls = KeyedSubtree(
      key: _controlsKey,
      child: _controls(
        context,
        canLoad: canLoad,
        leading: scrolls
            ? SizedBox(height: _scrollingPreview, child: preview)
            : null,
      ),
    );
    if (scrolls) return controls;
    if (wide) {
      // The photos and the tags of the picture keep clear of the system's
      // bar along the bottom edge.
      final besideControls = SafeArea(
        top: false,
        left: false,
        right: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: preview,
      );
      final line = VerticalDivider(
        width: 1,
        thickness: 1,
        color: GrColors.of(context).line,
      );
      return Row(
        children: book == null
            ? [
                Expanded(child: besideControls),
                line,
                SizedBox(
                  width: (box.maxWidth * .42).clamp(
                    _narrowestControls,
                    _widestControls,
                  ),
                  child: controls,
                ),
              ]
            : [
                SizedBox(width: book.preview, child: besideControls),
                SizedBox(width: math.max(1, book.gap), child: line),
                Expanded(child: controls),
              ],
      );
    }
    return Column(
      children: [
        SizedBox(
          height: math.min(box.maxHeight * .45, _tallestPreview),
          child: preview,
        ),
        Expanded(child: controls),
      ],
    );
  }

  /// The least width at which the preview goes beside the controls, and
  /// the widths the controls then keep between.
  static const double _wideFrom = 560;
  static const double _narrowestControls = 300;
  static const double _widestControls = 440;

  /// The least height at which the preview stays in place above the
  /// controls, the most it then gets, and the height it has when it
  /// scrolls with them instead.
  static const double _inPlaceFrom = 400;
  static const double _tallestPreview = 600;
  static const double _scrollingPreview = 260;

  /// The least height of the controls at which the base images and the
  /// groups stay in place above the parameters instead of scrolling with
  /// them.
  static const double _pinnedFrom = 380;

  /// The height under which a window counts as short (Android's compact
  /// height class), and the least each half of a foldable on a table needs
  /// for the editor to be split at its fold.
  static const double _shortUnder = 480;
  static const double _leastHalf = 160;

  /// Whether the photos stand down the side of the picture rather than lie
  /// under it: in a [window] that is short and wide, as a phone's on its
  /// side, where a row under the picture would take height it lacks and a
  /// column beside it width it has to spare \[design\].
  static bool _stripAtSide(Size window) =>
      window.height < _shortUnder && window.width >= _wideFrom;

  /// Which of [_photos] the preview is on, how well it suits the look, and
  /// what there is to say about the preview.
  ({int index, LookSourceFit fit, String? note}) _shown(AppLocalizations l10n) {
    final firstSample = _hasOwnPhoto ? 1 : 0;
    // Until the user picks, the look's own photo when the look it was
    // taken with can be undone without a rougher result, and the first
    // sample photo otherwise \[design\]. Any of them can always be picked.
    final ownFit = _hasOwnPhoto ? _photos.first.rerender.fitFor(_look) : null;
    final startsOnOwn =
        ownFit == LookSourceFit.good || ownFit == LookSourceFit.unknown;
    final index = _picked ?? (startsOnOwn ? 0 : firstSample);
    final fit = _photos[index].rerender.fitFor(_look);
    final note = switch (fit) {
      // Why the editor did not start on the look's own photo.
      _ when _hasOwnPhoto && _picked == null && index == firstSample =>
        l10n.looksPreviewSample,
      LookSourceFit.rough => l10n.looksPreviewRough,
      LookSourceFit.unknown => l10n.looksPreviewUnknownLook,
      LookSourceFit.unusable => l10n.looksPreviewAsTaken,
      LookSourceFit.good => null,
    };
    return (index: index, fit: fit, note: note);
  }

  /// The picture with its controls over its top corners, then what to know
  /// about the preview and the photos to pick from, which stand at the
  /// picture's side instead in a short and wide window ([_stripAtSide]).
  /// With [pictureAlone] it is the picture and its controls only, and the
  /// rest is elsewhere ([_photoChoice]).
  Widget _preview(BuildContext context, {required bool pictureAlone}) {
    final shown = _shown(context.l10n);
    final picture = KeyedSubtree(
      key: _paneKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LookCompare(
            photo: _photos[shown.index],
            // A photo whose own look cannot be undone for this look has no
            // preview: it is shown as it was taken.
            look: shown.fit == LookSourceFit.unusable ? null : _look,
            mode: _mode,
          ),
          // Over the comparison, so a touch on them is not one on the
          // picture, which would move its divider.
          PositionedDirectional(
            top: _overPicture,
            start: _overPicture,
            child: LookCompareModeSwitch(
              selected: _mode,
              onSelect: (m) => setState(() => _mode = m),
            ),
          ),
          PositionedDirectional(
            top: _overPicture,
            end: _overPicture,
            child: _fullscreenButton(context),
          ),
        ],
      ),
    );
    if (pictureAlone) return picture;
    final atSide = _stripAtSide(MediaQuery.sizeOf(context));
    return Column(
      children: [
        Expanded(
          child: atSide
              ? Row(
                  children: [
                    _strip(context, shown.index, Axis.vertical),
                    Expanded(child: picture),
                  ],
                )
              : picture,
        ),
        // Above the photos, so they stay where they are when the note
        // comes, goes or changes length.
        ?_note(context, shown.note),
        if (!atSide) _strip(context, shown.index, Axis.horizontal),
      ],
    );
  }

  /// How far the controls over the picture are from its place's corners.
  static const double _overPicture = 8;

  /// What to know about the preview and the photos to pick from, where
  /// they are not part of the preview: on the flat half of a foldable
  /// half-open on a table.
  Widget _photoChoice(BuildContext context) {
    final shown = _shown(context.l10n);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?_note(context, shown.note),
        _strip(context, shown.index, Axis.horizontal),
      ],
    );
  }

  /// [note] as the preview says it; null without one.
  Widget? _note(BuildContext context, String? note) => note == null
      ? null
      : Padding(
          key: const Key('look-preview-note'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              note,
              style: TextStyle(fontSize: 12.5, color: GrColors.of(context).t2),
            ),
          ),
        );

  /// The photos to preview on, [shown] picked: in a row that fills the
  /// width, or a column that fills the height.
  Widget _strip(BuildContext context, int shown, Axis axis) {
    final l10n = context.l10n;
    final across = axis == Axis.horizontal;
    return Padding(
      padding: across
          ? const EdgeInsets.fromLTRB(16, 12, 16, 4)
          : const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
      child: Align(
        alignment: across
            ? AlignmentDirectional.centerStart
            : Alignment.topCenter,
        child: PreviewPhotoSwitch(
          photos: _photos,
          labels: [
            if (_hasOwnPhoto) l10n.looksPhotoOwn,
            for (var n = 1; n <= samplePhotos.length; n++)
              l10n.looksPhotoSample(n),
          ],
          selected: shown,
          onSelect: (i) => setState(() => _picked = i),
          axis: axis,
          ownFirst: _hasOwnPhoto,
        ),
      ),
    );
  }

  /// Grows the preview to the whole screen, and brings it back.
  Widget _fullscreenButton(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: _fullscreen
          ? l10n.looksPreviewExitFullScreen
          : l10n.looksPreviewFullScreen,
      child: Semantics(
        button: true,
        child: OverPicture(
          child: Pressable(
            key: const Key('look-preview-fullscreen'),
            onTap: _fullscreen ? _leaveFullscreen : _enterFullscreen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OverPicture.radius),
            ),
            child: SizedBox.square(
              dimension: 36,
              child: Icon(
                _fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                size: 20,
                color: GrColors.of(context).t1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The flat half of a foldable half-open on a table: the choice of photo
  /// ([_photoChoice]), then the controls. Where it is wide enough for two
  /// columns, the photos, the base images and Save and Load have one and
  /// the groups with their parameters the other, so that more than one
  /// parameter is in view in half a screen's height \[design\].
  Widget _onTable(BuildContext context, {required bool canLoad}) =>
      LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < _wideFrom) {
            return Column(
              children: [
                _photoChoice(context),
                Expanded(child: _controls(context, canLoad: canLoad)),
              ],
            );
          }
          final parts = _controlParts(context, canLoad: canLoad);
          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [_photoChoice(context), parts.bases],
                      ),
                    ),
                    ?parts.notOffered,
                    parts.actions,
                  ],
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: GrColors.of(context).line,
              ),
              Expanded(
                child: Column(
                  children: [
                    ?parts.groups,
                    Expanded(
                      child: ListView(
                        // Its last parameter scrolls clear of the system's
                        // bar along the bottom edge.
                        padding: EdgeInsets.only(
                          top: 6,
                          bottom: 12 + MediaQuery.paddingOf(context).bottom,
                        ),
                        children: parts.parameters,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );

  /// What the controls are made of: the base images, the groups (null for
  /// a look without parameters to show), the group's parameters, the note
  /// for a look the camera does not offer (null otherwise), and Save and
  /// Load clear of the system's bar.
  ({
    Widget bases,
    Widget? groups,
    List<Widget> parameters,
    Widget? notOffered,
    Widget actions,
  })
  _controlParts(BuildContext context, {required bool canLoad}) {
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
    final bases = _model.basesFor(_look);
    return (
      bases: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: LookBaseStepper(
          key: const Key('look-bases'),
          name: lookBaseLabel(l10n, _look),
          bases: bases,
          selected: base,
          onSelect: _setBase,
          onList: () => unawaited(_pickBase(bases)),
        ),
      ),
      groups: group == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: ShootSegmented<LookGroup>(
                key: const Key('look-groups'),
                values: groups,
                selected: group,
                label: (g) => groupLabel(l10n, g),
                onSelect: (g) => setState(() => _group = g),
              ),
            ),
      parameters: [
        if (base == null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(l10n.looksUnreadable, style: TextStyle(color: c.t2)),
          ),
        for (final p in params)
          if (groupOf(p) == group)
            _ParameterRow(
              key: ValueKey('look-param:${p.name}'),
              parameter: p,
              base: _look.base,
              value: _look.valueOf(p)!,
              onChanged: (v) => setState(() => _look = _look.withValue(p, v)),
            ),
      ],
      notOffered: _model.onCamera && !_look.offeredBy(_model.body)
          ? Padding(
              key: const Key('look-not-offered'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                l10n.looksNotOffered(lookBaseLabel(l10n, _look)),
                style: TextStyle(fontSize: 12.5, color: c.t2),
              ),
            )
          : null,
      actions: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _actions(context, canLoad: canLoad),
        ),
      ),
    );
  }

  /// The base images, the groups and the group's parameters, then Save
  /// and Load. [leading] scrolls with them, ahead of the base images.
  Widget _controls(
    BuildContext context, {
    required bool canLoad,
    Widget? leading,
  }) {
    final parts = _controlParts(context, canLoad: canLoad);
    final header = [parts.bases, ?parts.groups];
    return LayoutBuilder(
      builder: (context, box) {
        final pinned = leading == null && box.maxHeight >= _pinnedFrom;
        return Column(
          children: [
            if (pinned) ...header,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 12),
                children: [
                  ?leading,
                  if (!pinned) ...header,
                  ...parts.parameters,
                ],
              ),
            ),
            ?parts.notOffered,
            parts.actions,
          ],
        );
      },
    );
  }

  /// Save and, in an editor opened from a Custom slot, Load into that
  /// slot. Opened from the library the look has Save alone: it may be
  /// meant for any slot, and the menu loads it into each \[design\].
  Widget _actions(BuildContext context, {required bool canLoad}) {
    final l10n = context.l10n;
    final save = _unsaved ? () => unawaited(_save()) : null;
    final slot = widget.slot;
    if (slot == null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('look-save'),
          onPressed: save,
          child: Text(l10n.looksSave),
        ),
      );
    }
    return Row(
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
            onPressed: canLoad ? () => unawaited(_load(slot)) : null,
            icon: _model.loading == slot
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded, size: 18),
            label: Text(l10n.looksLoadInto(slot)),
          ),
        ),
      ],
    );
  }
}

/// One parameter (mock `.slider`): a slider for a signed adjustment, a
/// segmented control for a choice, or just the value when its range is
/// not known and it stays as the camera set it.
class _ParameterRow extends StatelessWidget {
  const new({
    required this.parameter,
    required this.base,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final LookParameter parameter;

  /// The look's base image, which decides the values on offer.
  final LookBase? base;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final range = lookRange(parameter, base);
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
                values: range!.values,
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
