import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/camera/camera_top_bar.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/connection/connect_steps.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/downloads/download_bar.dart';
import 'package:grphoto/src/downloads/download_engine.dart';
import 'package:grphoto/src/library/format.dart';
import 'package:grphoto/src/library/library_model.dart';
import 'package:grphoto/src/library/library_scope.dart';
import 'package:grphoto/src/library/shot.dart';
import 'package:grphoto/src/library/shot_cell.dart';
import 'package:grphoto/src/library/viewer.dart';
import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/gr_dialog.dart';
import 'package:grphoto/src/widgets/group.dart';
import 'package:grphoto/src/widgets/toast.dart';
import 'package:grphoto/src/widgets/window_layout.dart';

/// The camera's photos (mocks `b-library-ios` / `b-library-android`): the
/// top bar with the camera pill and settings, filter chips, a grid by day,
/// selection with a download bar, and the download mini bar.
///
/// In a window of two pages at a fold ([pagesAtFold]: a foldable held
/// open like a book, mock `duo-inner-split`) the Library keeps the first
/// page, laid out as on a phone, and the second shows the shot last
/// tapped in the grid ([ShotPane]), or asks for one ([_NoShotShown]).
/// Tapping a shot never moves the grid \[design\]: the pages stay as they
/// are whichever shot shows.
class LibraryScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => LibraryScope(
    library: AppScope.of(context).library,
    child: const _LibraryView(),
  );
}

class _LibraryView extends StatefulWidget {
  const new();

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  late final AppModels _app = AppScope.of(context);
  late final LibraryContext _library = LibraryScope.of(context);
  LibraryFilter _filter = LibraryFilter.all;
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _permissionDialogOpen = false;
  bool _listening = false;

  /// The shot on the second page, in a window of two pages at a fold.
  final _pane = ShotPaneController();

  /// The camera of the shot [_pane] shows.
  String? _paneSerial;

  /// The key of the shot [_pane] showed when the grid last brought its
  /// line into view; null with nothing shown.
  String? _revealedShotKey;

  /// The top bar, for how much of the grid it covers when it is back.
  final GlobalKey _topBarKey = GlobalKey();

  /// The grid, for where its lines are.
  final GlobalKey _gridKey = GlobalKey();

  /// How many shots wide, and how tall, the grid's lines of shots were
  /// last laid out.
  int _columns = 3;
  double _cellExtent = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listening) {
      _listening = true;
      _library.engine.addListener(_onEngine);
      _library.engine.addListener(_followGrid);
      _library.model.addListener(_followGrid);
      _pane.addListener(_onPaneShot);
      // The engine is the app's: the photo library may have refused it
      // while the camera pages were closed.
      _onEngine();
    }
    // A window that is one page has no room for a shot beside the grid.
    if (pagesAtFold(context) == null) _pane.close();
  }

  @override
  void dispose() {
    _library.engine.removeListener(_onEngine);
    _library.engine.removeListener(_followGrid);
    _library.model.removeListener(_followGrid);
    _pane.dispose();
    super.dispose();
  }

  void _onEngine() {
    final problem = _library.engine.permissionProblem;
    if (problem == null || _permissionDialogOpen) return;
    _permissionDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showPermissionGuidance(context);
      _library.engine.dismissPermissionProblem();
      _permissionDialogOpen = false;
    });
  }

  void _startSelecting(Shot shot) => setState(() {
    _selecting = true;
    _selected.add(shot.key);
  });

  void _toggle(Shot shot) => setState(() {
    if (!_selected.remove(shot.key)) _selected.add(shot.key);
    if (_selected.isEmpty) _selecting = false;
  });

  void _endSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  Future<void> _download(String serial, List<Shot> shots, FileKind kind) async {
    _endSelecting();
    await _library.engine.enqueue(serial, shots, kinds: {kind});
  }

  void _setFilter(LibraryFilter filter) {
    setState(() => _filter = filter);
    _followGrid();
  }

  /// Opens the viewer on the shot of [shots] at [index]. A shot beside
  /// the grid gives way to the one the viewer ended on.
  Future<void> _open(List<Shot> shots, int index) async {
    var last = shots[index];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryScope(
          library: _library,
          child: ShotViewer(
            shots: shots,
            initialIndex: index,
            onShown: (shot) => last = shot,
          ),
        ),
      ),
    );
    if (!mounted || !_pane.isOpen) return;
    final now = _library.grid.filtered(_filter)?.shots;
    if (now == null) return;
    final place = now.indexWhere((s) => s.key == last.key);
    if (place >= 0) _showBeside(now, place);
  }

  /// Shows the shot of [shots], the grid's, at [index] beside the grid.
  void _showBeside(List<Shot> shots, int index) {
    _paneSerial = _library.model.serial;
    _pane.show(shots, index);
  }

  /// Opens the viewer on the shot beside the grid.
  void _openShown() => unawaited(_open(_pane.shots, _pane.index));

  /// Keeps the shot beside the grid to the grid's shots: those of its
  /// camera that the filter leaves.
  void _followGrid() {
    if (!_pane.isOpen) return;
    final shots = _library.model.serial == _paneSerial
        ? _library.grid.filtered(_filter)?.shots
        : null;
    if (shots == null) {
      _pane.close();
    } else {
      _pane.follow(shots);
    }
  }

  /// Another shot shows beside the grid, or none does any more: once the
  /// grid is laid out for that, the shot's line is brought into view.
  void _onPaneShot() {
    final key = _pane.shown?.key;
    if (key == _revealedShotKey) return;
    _revealedShotKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealPaneShot());
  }

  /// Scrolls the grid, when it has to, so that the line of the shot
  /// [_pane] shows, or showed last, is in view, clear of the bars that
  /// float over the grid's top and bottom: a swipe beside the grid goes on
  /// to shots further along, and the grid has other columns once the
  /// window is one page again. A line too far away to be built is first
  /// jumped to where it is worked out to be ([afterJump] is set from then
  /// on).
  void _revealPaneShot({bool afterJump = false}) {
    final grid = _gridKey.currentContext;
    final shots = _library.grid.filtered(_filter)?.shots;
    if (!mounted || grid == null || !identical(shots, _pane.shots)) return;
    final sliver = grid.findRenderObject()! as RenderSliverMultiBoxAdaptor;
    final lines = _library.grid.lines(_pane.shots, _columns).lines;
    final shown = _pane.index;
    final place = lines.indexWhere(
      (l) =>
          l is GridShotsLine &&
          l.first <= shown &&
          shown < l.first + l.shots.length,
    );
    if (place < 0) return;
    RenderBox? line;
    var dayLabelExtent = _dayLabelExtentGuess;
    for (
      var built = sliver.firstChild;
      built != null;
      built = sliver.childAfter(built)
    ) {
      final at = sliver.indexOf(built);
      if (at == place) line = built;
      if (lines.elementAtOrNull(at) case GridDayLine(
        section: DaySection(day: _?),
      )) {
        dayLabelExtent = built.size.height;
      }
    }
    final position = Scrollable.of(grid).position;
    final bottomBarRoom = _bottomBarRoom + MediaQuery.paddingOf(context).bottom;
    if (line != null) {
      final viewport = RenderAbstractViewport.of(line);
      final topBar = _topBarKey.currentContext?.findRenderObject();
      final topBarRoom = topBar is RenderSliver
          ? topBar.geometry?.maxPaintExtent ?? 0
          : 0.0;
      final lineAtTop = viewport.getOffsetToReveal(line, 0).offset - topBarRoom;
      final lineAtBottom =
          viewport.getOffsetToReveal(line, 1).offset + bottomBarRoom;
      final scrolled = position.pixels;
      final inView = scrolled > lineAtTop
          ? lineAtTop
          : max(scrolled, lineAtBottom);
      final to = min(
        max(inView, position.minScrollExtent),
        position.maxScrollExtent,
      );
      if ((to - scrolled).abs() < 1) return;
      if (afterJump || MediaQuery.disableAnimationsOf(context)) {
        position.jumpTo(to);
      } else {
        unawaited(
          position.animateTo(
            to,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
        );
      }
      return;
    }
    // Not where it was worked out to be: the grid stays where it is.
    if (afterJump) return;
    double extent(GridLine line) => switch (line) {
      GridDayLine(section: DaySection(day: null)) => _undatedGap,
      GridDayLine() => dayLabelExtent,
      GridShotsLine(:final endsDay) => _cellExtent + (endsDay ? 0 : _cellGap),
    };
    var before = 0.0;
    var fromLine = 0.0;
    for (final (at, line) in lines.indexed) {
      if (at < place) {
        before += extent(line);
      } else {
        fromLine += extent(line);
      }
    }
    final lineStart = sliver.constraints.precedingScrollExtent + before;
    final viewportExtent = position.viewportDimension;
    final centred = lineStart - (viewportExtent - extent(lines[place])) / 2;
    final end = lineStart + fromLine + bottomBarRoom - viewportExtent;
    position.jumpTo(max(position.minScrollExtent, min(centred, end)));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealPaneShot(afterJump: true),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _library.model,
      _library.engine,
      _app.connection,
      _pane,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final model = _library.model;
    final serial = model.serial;
    final all = model.shots;
    final filtered = _library.grid.filtered(_filter);
    final shots = filtered?.shots;
    final selectedShots = [
      if (_selecting && all != null)
        for (final s in all)
          if (_selected.contains(s.key)) s,
    ];
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Without the camera's Wi-Fi the failure replaces the (cached) photos;
    // its Try again joins again.
    final failure = _app.connection.failure;
    final wifiFailure = !model.connected && failure?.step == ConnectStep.wifi
        ? failure
        : null;
    final camera = _app.connection.camera;
    final showsFailure = wifiFailure != null && camera != null;
    final l10n = context.l10n;
    // Cached photos stay up while their camera connects or is read again.
    final progress = showsFailure || all == null
        ? null
        : model.refreshing
        ? l10n.libraryUpdating
        : model.connected
        ? null
        : l10n.libraryConnecting;
    final c = GrColors.of(context);
    final bar = VerticalBar.of(context);
    // The two pages at a fold: the Library has the first, and the shot
    // shown beside the grid the second.
    final book = pagesAtFold(context);
    final showsGrid =
        !showsFailure && shots != null && shots.isNotEmpty && serial != null;
    // Pages that meet with no gap between them have a line there.
    final pageEdge = book == null || book.gap > 0
        ? null
        : BorderDirectional(start: BorderSide(color: c.line));
    final chips = showsFailure || filtered == null || all == null || all.isEmpty
        ? null
        : _Chips(
            filter: _filter,
            counts: filtered.counts,
            onSelect: _setFilter,
          );
    final title = PageTitle(l10n.libraryTitle, status: _Progress(progress));
    final page = Stack(
      children: [
        RefreshIndicator(
          onRefresh: model.refresh,
          notificationPredicate: (n) => model.connected && n.depth == 0,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverCameraTopBar(key: _topBarKey),
              SliverSafeArea(
                top: false,
                bottom: false,
                sliver: SliverToBoxAdapter(child: title),
              ),
              if (showsFailure)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: ConnectFailureView(
                      camera: camera,
                      failure: wifiFailure,
                      connection: _app.connection,
                    ),
                  ),
                )
              else ...[
                if (all != null && progress == null && model.error != null)
                  SliverToBoxAdapter(
                    child: _UpdateFailedLine(onRetry: model.refresh),
                  ),
                if (chips != null) SliverToBoxAdapter(child: chips),
                if (showsGrid)
                  // The grid's own width says how many shots go across
                  // it: beside a shot, or a vertical bar, it is not the
                  // window's.
                  SliverLayoutBuilder(
                    builder: (context, grid) => _grid(
                      context,
                      serial,
                      shots,
                      width: grid.crossAxisExtent,
                      tapShowsBeside: book != null,
                    ),
                  )
                else
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      model: model,
                      connection: _app.connection,
                      filter: _filter,
                    ),
                  ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(height: _bottomBarRoom + bottomInset),
              ),
            ],
          ),
        ),
        PositionedDirectional(
          start: 12,
          end: 12,
          bottom: 12 + bottomInset,
          child: ToastFloor(
            child: _selecting && serial != null
                ? _SelectionBar(
                    serial: serial,
                    shots: selectedShots,
                    onDownload: (kind) =>
                        _download(serial, selectedShots, kind),
                    onClose: _endSelecting,
                  )
                : const DownloadBar(),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: !_selecting,
      // Back ends choosing shots.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSelecting();
      },
      child: CameraBarColumn(
        child: Scaffold(
          // Beside the window's vertical bar, not under it.
          body: SafeArea(
            top: false,
            bottom: false,
            left: bar?.side == BarSide.left,
            right: bar?.side == BarSide.right,
            child: Stack(
              children: [
                // At the same place as one page and as the first of two,
                // so the Library keeps its state when the phone opens or
                // closes.
                PositionedDirectional(
                  top: 0,
                  bottom: 0,
                  start: 0,
                  end: book == null ? 0 : null,
                  width: book?.first,
                  child: _FirstPage(besideSecond: book != null, child: page),
                ),
                if (book != null)
                  PositionedDirectional(
                    top: 0,
                    bottom: 0,
                    start: book.first + book.gap,
                    end: 0,
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(border: pageEdge),
                      child: _pane.isOpen
                          ? ShotPane(controller: _pane, onOpen: _openShown)
                          : _NoShotShown(asks: showsGrid),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [shots] by day, a line at a time ([gridLines]), in a grid [width]
  /// wide: five shots to a line from 600 wide and three in a narrower one
  /// \[design\]. A tap on a shot opens it in the viewer, or beside the
  /// grid when [tapShowsBeside].
  Widget _grid(
    BuildContext context,
    String serial,
    List<Shot> shots, {
    required double width,
    required bool tapShowsBeside,
  }) {
    final model = _library.model;
    final engine = _library.engine;
    final columns = width >= 600 ? 5 : 3;
    final cellExtent = (width - (columns - 1) * _cellGap) / columns;
    _columns = columns;
    _cellExtent = cellExtent;
    final shownKey = _pane.shown?.key;
    final now = DateTime.now();
    final (:lines, :indexOf) = _library.grid.lines(shots, columns);
    void onTap(Shot shot, int index) {
      if (_selecting) {
        _toggle(shot);
      } else if (tapShowsBeside) {
        _showBeside(shots, index);
      } else {
        unawaited(_open(shots, index));
      }
    }

    Widget cell(Shot shot, int index) => ShotCell(
      key: ValueKey(shot.key),
      serial: serial,
      shot: shot,
      mark: _markFor(engine, serial, shot),
      duration: model.info(shot.primary)?.duration,
      shown: shot.key == shownKey,
      onTap: () => onTap(shot, index),
      onLongPress: () => _selecting ? _toggle(shot) : _startSelecting(shot),
    );
    // The line of [row], which starts at [first] among the shots.
    Widget cells(List<Shot> row, int first) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var column = 0; column < columns; column++) ...[
          if (column > 0) const SizedBox(width: _cellGap),
          Expanded(
            child: column < row.length
                ? cell(row[column], first + column)
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
    Widget line(GridLine line) => switch (line) {
      GridDayLine(section: DaySection(:final day?, shots: final ofDay)) =>
        _DayLabel(title: formatDay(context, day, now), shots: ofDay),
      GridDayLine() => const SizedBox(height: _undatedGap),
      GridShotsLine(:final first, shots: final row, :final endsDay) => Padding(
        padding: EdgeInsets.only(bottom: endsDay ? 0 : _cellGap),
        child: SizedBox(height: cellExtent, child: cells(row, first)),
      ),
    };
    return SliverList.builder(
      key: _gridKey,
      itemCount: lines.length,
      // A line that moves, as the lines under a label that just appeared
      // do, keeps its cells and the pictures they loaded or wait for.
      findChildIndexCallback: (key) => indexOf[(key as ValueKey<String>).value],
      itemBuilder: (context, i) =>
          KeyedSubtree(key: ValueKey(lines[i].id), child: line(lines[i])),
    );
  }

  CellMark _markFor(DownloadEngine engine, String serial, Shot shot) {
    if (_selecting) {
      return _selected.contains(shot.key)
          ? CellMark.selected
          : CellMark.unselected;
    }
    // A shot downloaded before and queued again shows that it is coming.
    if (shot.files.any((f) => engine.isFileQueued(serial, f))) {
      return CellMark.queued;
    }
    if (engine.isShotDownloaded(serial, shot)) return CellMark.downloaded;
    return CellMark.none;
  }
}

/// Space between the grid's cells.
const double _cellGap = 2;

/// Over the grid's leading shots without a date, when dated days follow
/// them.
const double _undatedGap = 8;

/// About as tall as a day's label is at the default text size: its height
/// while no label is laid out to measure.
const double _dayLabelExtentGuess = 44;

/// At the grid's end, for the bar that floats over the bottom of the
/// Library.
const double _bottomBarRoom = 96;

/// The second page at a fold while no shot shows there: a line that asks
/// for one when the grid has shots to tap ([asks]), and nothing while it
/// has none.
class _NoShotShown extends StatelessWidget {
  const new({required this.asks});

  final bool asks;

  @override
  Widget build(BuildContext context) {
    if (!asks) return const SizedBox.expand();
    final c = GrColors.of(context);
    return Center(
      key: const Key('shot-pane-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_outlined, size: 40, color: c.t3),
            const SizedBox(height: 14),
            Text(
              context.l10n.libraryPaneEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.t2),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child], the Library's page, as the first of two pages at a fold when
/// [besideSecond]: the window's inset on the far side is the second
/// page's then, not its own.
class _FirstPage extends StatelessWidget {
  const new({required this.besideSecond, required this.child});

  final bool besideSecond;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final leftFirst = Directionality.of(context) == TextDirection.ltr;
    return MediaQuery.removePadding(
      context: context,
      removeLeft: besideSecond && !leftFirst,
      removeRight: besideSecond && leftFirst,
      child: child,
    );
  }
}

/// Explains how to allow photo-library access after the OS refused it.
Future<void> showPermissionGuidance(BuildContext context) {
  final ios = Theme.of(context).platform == TargetPlatform.iOS;
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (context) => GrDialog(
      title: l10n.libraryPhotoAccessTitle,
      message: ios
          ? l10n.libraryPhotoAccessIos
          : l10n.libraryPhotoAccessAndroid,
      actions: [
        GrDialogAction.answer(
          label: l10n.libraryOk,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// A spinner and what it waits for, beside the title: there it comes and
/// goes without moving the photos. Where the title leaves less than its
/// width, the text is scaled down and the spinner keeps its size.
class _Progress extends StatelessWidget {
  const new(this.text);

  /// Nothing shows while this is null.
  final String? text;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    if (text == null) return const SizedBox.shrink();
    final c = GrColors.of(context);
    return Row(
      key: const Key('library-progress'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: PageTitle.minStatusWidth,
          height: PageTitle.minStatusWidth,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: c.t2),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(text, style: TextStyle(fontSize: 13, color: c.t2)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Failed-update note under the title. The Library only shows while the
/// camera's Wi-Fi is up; a failed update whose camera no longer answers
/// returns to the Cameras screen instead (see `ConnectionLink`).
class _UpdateFailedLine extends StatelessWidget {
  const new({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 15, color: c.danger),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.libraryUpdateFailed,
                style: TextStyle(fontSize: 13, color: c.t2),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(onRetry()),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.libraryRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const new({
    required this.filter,
    required this.counts,
    required this.onSelect,
  });

  final LibraryFilter filter;
  final Map<LibraryFilter, int> counts;
  final ValueChanged<LibraryFilter> onSelect;

  static String _label(AppLocalizations l10n, LibraryFilter f) => switch (f) {
    LibraryFilter.all => l10n.libraryFilterAll,
    LibraryFilter.jpeg => l10n.libraryFilterJpeg,
    LibraryFilter.raw => l10n.libraryFilterRaw,
    LibraryFilter.video => l10n.libraryFilterVideo,
    LibraryFilter.notDownloaded => l10n.libraryFilterNotDownloaded,
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Row(
      children: [
        for (final f in LibraryFilter.values) ...[
          if (f != LibraryFilter.all) const SizedBox(width: 8),
          GrChip(
            key: ValueKey('chip:${f.name}'),
            label: _label(context.l10n, f),
            count: counts[f],
            selected: f == filter,
            onTap: () => onSelect(f),
          ),
        ],
      ],
    ),
  );
}

class _DayLabel extends StatelessWidget {
  const new({required this.title, required this.shots});

  final String title;
  final List<Shot> shots;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final storages = {for (final s in shots) storageLabel(context, s.storage)}
      ..remove(null);
    final meta = [
      formatCount(context, shots.length),
      if (storages.isNotEmpty) storages.join(' + '),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            meta,
            style: GrFonts.monoStyle(
              context,
              color: c.t3,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const new({
    required this.model,
    required this.connection,
    required this.filter,
  });

  final LibraryModel model;
  final ConnectionController connection;
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final IconData icon;
    final String title;
    final String body;
    Widget? action;
    if (model.shots != null) {
      icon = Icons.photo_library_outlined;
      if (filter == LibraryFilter.all) {
        title = l10n.libraryEmptyTitle;
        body = l10n.libraryEmptyBody;
      } else {
        title = l10n.libraryFilterEmptyTitle;
        body = filter == LibraryFilter.notDownloaded
            ? l10n.libraryFilterEmptyNotDownloaded
            : l10n.libraryFilterEmptyBody;
      }
    } else if (model.connected && model.error != null) {
      icon = Icons.error_outline_rounded;
      title = l10n.libraryListFailedTitle;
      body = l10n.libraryListFailedBody;
      action = FilledButton(
        onPressed: () => unawaited(model.refresh()),
        child: Text(l10n.libraryTryAgain),
      );
    } else if (!model.connected) {
      return Padding(
        key: const Key('library-joining'),
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (connection.camera?.name) {
                final name? => l10n.libraryJoining(name),
                null => l10n.libraryJoiningUnnamed,
              },
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            ConnectSteps(connection: connection),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.libraryReading, style: TextStyle(color: c.t2)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: c.t3),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.t2),
          ),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }
}

/// 'N selected' with a download action per kind of file (mock `.selbar`):
/// JPEG and RAW, plus Video when movies are selected. A RAW+JPEG pair
/// counts for both. Each action shows what it would fetch: the files of its
/// kind that are not already queued, including files downloaded before
/// (they may have been deleted from the phone).
class _SelectionBar extends StatelessWidget {
  const new({
    required this.serial,
    required this.shots,
    required this.onDownload,
    required this.onClose,
  });

  final String serial;
  final List<Shot> shots;
  final ValueChanged<FileKind> onDownload;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final kinds = [
      FileKind.jpeg,
      FileKind.raw,
      if (shots.any((s) => s.isVideo)) FileKind.movie,
    ];
    return Material(
      color: c.invBg,
      borderRadius: BorderRadius.circular(20),
      shadowColor: c.shadow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onClose,
                  tooltip: l10n.libraryCancelSelection,
                  icon: Icon(Icons.close_rounded, color: c.invFg),
                ),
                Expanded(
                  child: Text(
                    l10n.librarySelectedCount(shots.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.invFg,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  for (final (i, kind) in kinds.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _KindAction(
                        serial: serial,
                        shots: shots,
                        kind: kind,
                        onDownload: () => onDownload(kind),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Downloads the selection's files of one kind: 'JPEG', '3 files · 24 MB'.
class _KindAction extends StatelessWidget {
  const new({
    required this.serial,
    required this.shots,
    required this.kind,
    required this.onDownload,
  });

  final String serial;
  final List<Shot> shots;
  final FileKind kind;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final library = LibraryScope.of(context);
    final files = [
      for (final s in shots) ...library.engine.filesToDownload(serial, s, kind),
    ];
    var bytes = 0;
    var sizeKnown = true;
    for (final f in files) {
      final size = library.model.info(f)?.size;
      if (size == null) {
        sizeKnown = false;
        unawaited(library.model.ensureInfo(f));
      } else {
        bytes += size;
      }
    }
    final String detail;
    if (files.isNotEmpty) {
      detail = [
        l10n.libraryFileCount(files.length),
        if (sizeKnown) formatBytes(context, bytes),
      ].join(' · ');
    } else if (shots.any((s) => s.filesOf(kind).isNotEmpty)) {
      detail = l10n.libraryKindQueued;
    } else {
      detail = l10n.libraryKindNoneSelected;
    }
    return FilledButton(
      key: ValueKey('selection-download:${kind.name}'),
      onPressed: files.isEmpty ? null : onDownload,
      style: FilledButton.styleFrom(
        backgroundColor: c.invFg,
        foregroundColor: c.invBg,
        disabledBackgroundColor: c.invFg.withValues(alpha: .08),
        disabledForegroundColor: c.invFg2,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GrRadii.md),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_rounded, size: 16),
              const SizedBox(width: 4),
              Text(
                switch (kind) {
                  FileKind.jpeg => l10n.libraryFormatJpeg,
                  FileKind.raw => l10n.libraryFormatRaw,
                  FileKind.movie => l10n.libraryFormatVideo,
                },
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Text(
            detail,
            key: ValueKey('selection-detail:${kind.name}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // The button's foreground, dimmed with it when disabled.
            style: const TextStyle(
              fontFamily: GrFonts.mono,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
