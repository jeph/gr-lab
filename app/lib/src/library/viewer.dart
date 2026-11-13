import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/camera/camera_top_bar.dart';
import 'package:grphoto/src/connection/idle_disconnect.dart';
import 'package:grphoto/src/downloads/download_engine.dart';
import 'package:grphoto/src/geotag/geotag_controller.dart';
import 'package:grphoto/src/library/format.dart';
import 'package:grphoto/src/library/image_orientation.dart';
import 'package:grphoto/src/library/library_model.dart';
import 'package:grphoto/src/library/library_scope.dart';
import 'package:grphoto/src/library/movie_scrubber.dart';
import 'package:grphoto/src/library/shot.dart';
import 'package:grphoto/src/library/shot_cell.dart';
import 'package:grphoto/src/library/shot_over_details.dart';
import 'package:grphoto/src/looks/look_photo.dart';
import 'package:grphoto/src/looks/look_spec.dart';
import 'package:grphoto/src/looks/look_widgets.dart';
import 'package:grphoto/src/looks/looks_store.dart';
import 'package:grphoto/src/map/photo_map.dart';
import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';
import 'package:grphoto/src/widgets/skeleton.dart';
import 'package:grphoto/src/widgets/toast.dart';
import 'package:grphoto/src/widgets/window_layout.dart';
import 'package:video_player/video_player.dart';

/// Full-screen viewer: swipe between [shots] and pinch to zoom. A shot
/// opens with the whole screen and the header over its top: Back to the
/// Library, the shot's name, Info and Download, which asks a RAW+JPEG pair
/// whether to download its JPEG, its RAW or both. A tap on a photo puts
/// the header away and the next one brings it back. Info shows the file's
/// details below the shot, and Info again or a tap on the photo puts them
/// away. Below the details of a shot whose place is known is a map of it,
/// of which only the top shows until the viewer is scrolled up, so that
/// the shot keeps the screen. A photo shown larger than its preview, or
/// zoomed, is replaced by the full JPEG once it arrives; a mark in its
/// corner says so until then.
///
/// The viewer follows the camera's listing: a shot that leaves it (deleted
/// on the camera, or its card taken out) leaves the swipe list, a pair
/// that lost one half shows the other, and the viewer closes once no shot
/// is left. A picture taken a moment ago (the viewer opened from live
/// view) is in no listing yet: it stays until one has it, and is followed
/// like the others from then on. The viewer also closes when the Library
/// switches to another camera: its shots are not on that camera, and it
/// has no listing of theirs to follow any more \[design\].
///
/// In a window with a [VerticalBar] (a foldable iPhone, closed or open and
/// held wide) Back, Info and Download stand in the bar and the header is
/// the shot's name alone. On the closed phone the details show from the
/// start \[design\]: a photo is as wide as that window, which leaves the
/// room below it for them. On the open one, two pages at its fold
/// ([pagesAtFold]), the details are the second page, beside the shot on
/// the first, instead of below it \[design\]; an Android foldable keeps
/// them below the shot.
class ShotViewer extends StatefulWidget {
  const new({
    required this.shots,
    required this.initialIndex,
    super.key,
    this.onShown,
  });

  final List<Shot> shots;
  final int initialIndex;

  /// Told the shot that shows whenever it is another: after a swipe, and
  /// when the one shown left the listing.
  final ValueChanged<Shot>? onShown;

  @override
  State<ShotViewer> createState() => _ShotViewerState();
}

class _ShotViewerState extends State<ShotViewer>
    with TickerProviderStateMixin, _ShotPages<ShotViewer> {
  late final LibraryContext _library = LibraryScope.of(context);

  /// The camera of [_shots]: the listing's camera when the viewer opened.
  late final String? _serial;

  /// [ShotViewer.shots] not known to have left the listing, in their
  /// order, as the listing has them now.
  @override
  late final List<Shot> _shots = [...widget.shots];

  @override
  int get _firstIndex => widget.initialIndex;

  /// Keys of the [_shots] a listing has had: these leave with the listing.
  final Set<String> _listed = {};

  /// The listing [_shots] were last matched against. The library reports
  /// far more than new listings (each file's info, its refresh starting
  /// and ending); matching every shot again is for a new listing only.
  List<Shot>? _followed;

  /// The shot's pages under the header's room. They keep their state
  /// (zoom, playback) when a fold comes or goes and the details change
  /// sides.
  final GlobalKey _shotKey = GlobalKey();

  /// Whether the window the viewer opened in decided [_infoShown].
  bool _opened = false;

  /// The shot's details show below it, so it lies between them and the
  /// header instead of having the whole screen.
  bool _infoShown = false;

  /// The header shows, and the system's bars with it. Always with the
  /// details ([_infoShown]), which are reached from it, and on a movie:
  /// its page takes taps for playback, so a tap there could not bring the
  /// header back.
  bool _headerShown = true;

  /// 0 with the details in place, 1 once the shot has the whole screen
  /// (not [_infoShown]).
  late final AnimationController _immersion;
  late final CurvedAnimation _immersed;

  /// 0 with the header away, 1 with it in place ([_headerShown]).
  late final AnimationController _headerVisibility;

  /// Set once nothing is left to show: the route is on its way out and
  /// shows none of [_shots] any more.
  bool _closing = false;

  /// The status bar's icons as the app's theme has them, to give back
  /// when the viewer goes. The header has them white over a shot with the
  /// whole screen, and they stay as the last screen to say had them: the
  /// Library, which has no app bar, would not set them back.
  late SystemUiOverlayStyle _appStatusBar;

  @override
  void initState() {
    super.initState();
    _serial = _library.model.serial;
    if (_library.model.shots case final listing?) {
      final keys = {for (final s in listing) s.key};
      _listed.addAll(widget.shots.map((s) => s.key).where(keys.contains));
    }
    _library.model.addListener(_followListing);
    _immersion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
    _immersed = CurvedAnimation(
      parent: _immersion,
      curve: Curves.easeInOutCubic,
    );
    _headerVisibility = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_opened) {
      _opened = true;
      // \[design\] The closed foldable iPhone: the details start in place.
      if (VerticalBar.of(context) != null && pagesAtFold(context) == null) {
        _infoShown = true;
        _immersion.value = 0;
      }
    }
    final brightness = Theme.of(context).brightness;
    _appStatusBar = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: brightness,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: false,
    );
  }

  @override
  void dispose() {
    _library.model.removeListener(_followListing);
    _immersed.dispose();
    _immersion.dispose();
    _headerVisibility.dispose();
    if (!_headerShown) _showSystemBars();
    SystemChrome.setSystemUIOverlayStyle(_appStatusBar);
    super.dispose();
  }

  /// A tap on a photo puts its details away; without them, the header
  /// goes and comes with each tap.
  void _onPhotoTap() {
    if (_infoShown) {
      _setInfoShown(false);
    } else {
      _setHeaderShown(!_headerShown);
    }
  }

  void _setInfoShown(bool shown) {
    if (shown == _infoShown) return;
    setState(() => _infoShown = shown);
    _animate(_immersion, forward: !shown);
  }

  /// Shows or hides the header and, with it, the status and navigation
  /// bars: shown, they are as the rest of the app has them (Flutter's
  /// default, edge to edge).
  void _setHeaderShown(bool shown) {
    if (shown == _headerShown) return;
    setState(() => _headerShown = shown);
    _animate(_headerVisibility, forward: shown);
    if (shown) {
      _showSystemBars();
    } else {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
  }

  /// Takes [controller] to its end ([forward]) or back to its start: over
  /// a moment, or at once when the platform asks for less motion. Its
  /// status says which of the two it reached, which `animateTo` would not:
  /// that one ends completed at either.
  void _animate(AnimationController controller, {required bool forward}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = forward ? 1 : 0;
    } else if (forward) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  void _showSystemBars() =>
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  /// Takes each shot as [_serial]'s listing has it now and drops those it
  /// no longer has. A dropped shown shot gives way to the next one kept,
  /// or to the last one when none follows. Dropping shots settles the page
  /// on [_index] at once, ending a swipe under way: its offset and fling
  /// were measured against pages that moved. Without a listing (still
  /// being read) the shots stay.
  void _followListing() {
    if (_closing) return;
    final model = _library.model;
    if (model.serial != _serial) {
      _close();
      return;
    }
    final listing = model.shots;
    if (listing == null || identical(listing, _followed)) return;
    _followed = listing;
    final listed = {for (final s in listing) s.key: s};
    _listed.addAll(_shots.map((s) => s.key).where(listed.containsKey));
    // As the listing has it, itself while no listing has had it, or null
    // once it left the listing.
    Shot? now(Shot s) => listed[s.key] ?? (_listed.contains(s.key) ? null : s);
    final kept = [for (final s in _shots) ?now(s)];
    if (listEquals(kept, _shots)) return;
    if (kept.isEmpty) {
      _close();
      return;
    }
    final shown = _shots[_index];
    final keptBefore = _shots.take(_index).where((s) => now(s) != null).length;
    final index = min(keptBefore, kept.length - 1);
    final dropped = kept.length != _shots.length;
    setState(() {
      _shots
        ..clear()
        ..addAll(kept);
      _index = index;
      // A changed shot gets a new page (keyed by the shot), unzoomed.
      if (kept[index] != shown) _photoHeld = false;
    });
    if (dropped && _pages.hasClients) _pages.jumpToPage(index);
    if (kept[index] != shown) _onShown(kept[index]);
  }

  /// Closes the viewer's route, also when another route covers it.
  void _close() {
    setState(() => _closing = true);
    _setHeaderShown(true);
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  void _onShown(Shot shot) {
    if (shot.isVideo) _setHeaderShown(true);
    widget.onShown?.call(shot);
  }

  /// [button] of the header where it stands in the window's vertical bar:
  /// it goes and comes with the header.
  Widget _inBar(Widget button) => FadeTransition(
    opacity: _headerVisibility,
    child: IgnorePointer(ignoring: !_headerShown, child: button),
  );

  @override
  Widget build(BuildContext context) {
    if (_closing) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    final library = _library;
    final serial = _serial;
    final shot = _shots[_index];
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final bar = VerticalBar.of(context);
    final book = bar == null ? null : pagesAtFold(context);
    final media = MediaQuery.of(context);
    // A window with a vertical bar has no inset at its top, where the
    // display's corners are rounded.
    final headerTop = bar == null
        ? media.padding.top
        : max(media.padding.top, StatusBandBar.cornerMargin);
    final headerHeight = headerTop + kToolbarHeight;
    return ListenableBuilder(
      listenable: Listenable.merge([library.model, library.engine]),
      builder: (context, _) {
        for (final f in shot.files) {
          unawaited(library.model.ensureInfo(f));
        }
        final download = serial == null
            ? null
            : _DownloadAction(
                key: const ValueKey('viewer-download'),
                serial: serial,
                shot: shot,
                engine: library.engine,
                look: bar == null ? _DownloadLook.header : _DownloadLook.bar,
              );
        final shotUnderHeader = Column(
          key: _shotKey,
          children: [
            // The header's room, which a shot with the whole screen
            // takes: the header lies over it then.
            AnimatedBuilder(
              animation: _immersed,
              builder: (context, _) =>
                  SizedBox(height: headerHeight * (1 - _immersed.value)),
            ),
            Expanded(
              child: serial == null
                  ? const SizedBox.shrink()
                  : _buildPages(
                      serial: serial,
                      immersed: _immersed,
                      headerVisibility: _headerVisibility,
                      onPhotoTap: _onPhotoTap,
                    ),
            ),
          ],
        );
        final details = SafeArea(
          top: false,
          bottom: false,
          child: _Details(shot: shot, model: library.model),
        );
        final map = _ShotMap(serial: serial, shot: shot, model: library.model);
        return BarColumn(
          buttons: [
            if (bar != null) ...[
              _inBar(
                RoundIconButton(
                  key: const Key('viewer-back'),
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 16,
                  label: MaterialLocalizations.of(context).backButtonTooltip,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              _inBar(
                Semantics(
                  selected: _infoShown,
                  child: RoundIconButton(
                    key: const Key('viewer-info'),
                    icon: _infoShown
                        ? Icons.info_rounded
                        : Icons.info_outline_rounded,
                    label: l10n.viewerInfo,
                    color: _infoShown ? c.invBg : null,
                    iconColor: _infoShown ? c.invFg : null,
                    onTap: () => _setInfoShown(!_infoShown),
                  ),
                ),
              ),
              if (download != null) _inBar(download),
            ],
          ],
          child: Scaffold(
            body: AnimatedBuilder(
              animation: _immersed,
              // Black around a shot that has the whole screen.
              builder: (context, child) => ColoredBox(
                color: Colors.black.withValues(alpha: _immersed.value),
                child: child,
              ),
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(top: headerTop),
                ),
                // Beside the vertical bar, not under it.
                child: SafeArea(
                  top: false,
                  bottom: false,
                  left: bar?.side == BarSide.left,
                  right: bar?.side == BarSide.right,
                  child: Stack(
                    children: [
                      if (book == null)
                        // With a map below the details the column is
                        // taller than the screen, which shows the map's
                        // top: a scroll brings the rest of it up.
                        LayoutBuilder(
                          builder: (context, viewer) => SingleChildScrollView(
                            key: const Key('viewer-scroll'),
                            // A zoomed photo keeps drags to itself.
                            physics: _photoHeld
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            child: ShotOverDetails(
                              height: viewer.maxHeight,
                              belowShown:
                                  MediaQuery.paddingOf(context).bottom +
                                  _mapPeek,
                              shot: shotUnderHeader,
                              details: _DetailsBar(
                                immersed: _immersed,
                                child: details,
                              ),
                              below: _DetailsBar(
                                immersed: _immersed,
                                child: map,
                              ),
                            ),
                          ),
                        )
                      else
                        _ShotBesideDetails(
                          immersed: _immersed,
                          book: book,
                          top: headerHeight,
                          shot: shotUnderHeader,
                          details: SingleChildScrollView(
                            key: const Key('viewer-details-scroll'),
                            child: Column(children: [details, map]),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _Header(
                          shown: _headerShown,
                          visibility: _headerVisibility,
                          immersed: _immersed,
                          shot: shot,
                          model: library.model,
                          buttonsInBar: bar != null,
                          infoShown: _infoShown,
                          onInfo: () => _setInfoShown(!_infoShown),
                          download: bar == null ? download : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What the viewer and the Library's pane ([ShotPane]) share: the pages
/// their shots are swiped through, and which of them shows.
mixin _ShotPages<W extends StatefulWidget> on State<W> {
  /// The shots swiped through, in their order.
  List<Shot> get _shots;

  /// Which of [_shots] shows first.
  int get _firstIndex;

  late final PageController _pages;

  /// Which of [_shots] shows.
  late int _index;

  /// The photo shown keeps drags to itself ([_PhotoPage.onHold]) instead of
  /// letting them swipe to another shot.
  bool _photoHeld = false;

  /// [shot] came to show instead of another.
  void _onShown(Shot shot);

  // Set here and not when first read: the pane's first index is its
  // controller's, which has moved on by the time a shot is swiped to.
  @override
  void initState() {
    super.initState();
    _index = _firstIndex;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _onPhotoHold(bool held) {
    if (held == _photoHeld) return;
    // A swipe between shots that is under way goes on: stopped, it would
    // leave the pages between two shots.
    if (held &&
        _pages.hasClients &&
        _pages.position.isScrollingNotifier.value) {
      return;
    }
    setState(() => _photoHeld = held);
  }

  void _onPageChanged(int index) {
    // Also reported after a jump to [_index].
    if (index == _index) return;
    setState(() {
      _index = index;
      _photoHeld = false;
    });
    _onShown(_shots[index]);
  }

  /// [_shots], of the camera [serial], as pages to swipe through.
  /// [immersed] and [headerVisibility] are those of [_PhotoPage].
  Widget _buildPages({
    required String serial,
    required Animation<double> immersed,
    required Animation<double> headerVisibility,
    required VoidCallback onPhotoTap,
  }) => PageView.builder(
    controller: _pages,
    physics: _photoHeld
        ? const NeverScrollableScrollPhysics()
        : const PageScrollPhysics(),
    itemCount: _shots.length,
    onPageChanged: _onPageChanged,
    // A page whose shot stays keeps its state (zoom, playback) when shots
    // before it come or go.
    findChildIndexCallback: (key) {
      final i = _shots.indexWhere((s) => ValueKey(s) == key);
      return i < 0 ? null : i;
    },
    itemBuilder: (context, i) {
      final s = _shots[i];
      return s.isVideo
          ? _VideoPage(
              key: ValueKey(s),
              serial: serial,
              shot: s,
              active: i == _index,
              immersed: immersed,
            )
          : _PhotoPage(
              key: ValueKey(s),
              serial: serial,
              shot: s,
              immersed: immersed,
              headerVisibility: headerVisibility,
              onHold: _onPhotoHold,
              onTap: onPhotoTap,
            );
    },
  );
}

/// The narrowest page the Library and the viewer put beside another at a
/// fold \[design\]: a small phone's width, which holds three columns of
/// the grid, or a shot with its details.
const _leastPageAtFold = 320.0;

/// The two pages of a window with a fold standing upright in it
/// ([WindowFold.book]), as a page has them that lies beside the window's
/// [VerticalBar] and reaches the window's other edges: each with the
/// window's inset on its side, unless that is the bar's strip. Null in a
/// window that is one page. [context] is one whose insets are the
/// window's.
BookFold? pagesAtFold(BuildContext context) {
  final book = WindowFold.book(context, leastPage: _leastPageAtFold);
  if (book == null) return null;
  final insets = MediaQuery.paddingOf(context);
  final barSide = VerticalBar.of(context)?.side;
  final left = barSide == BarSide.left ? 0.0 : insets.left;
  final right = barSide == BarSide.right ? 0.0 : insets.right;
  final leftFirst = Directionality.of(context) == TextDirection.ltr;
  return BookFold(
    first: book.first + (leftFirst ? left : right),
    gap: book.gap,
    second: book.second + (leftFirst ? right : left),
  );
}

/// What the Library's [ShotPane] shows: one of the grid's shots. The
/// Library opens it on a shot ([show]), keeps it to the grid ([follow])
/// and closes it; the pane moves it as its shots are swiped through
/// ([moveTo]).
final class ShotPaneController extends ChangeNotifier {
  List<Shot> _shots = const [];
  int _index = 0;
  bool _open = false;

  /// The grid's shots, in its order, as they were when the pane last
  /// followed them.
  List<Shot> get shots => _shots;

  /// Which of [shots] the pane shows, or showed last.
  int get index => _index;

  bool get isOpen => _open;

  /// The shot the pane shows; null while it is closed.
  Shot? get shown => _open ? _shots[_index] : null;

  /// Opens the pane on the shot of [shots] at [index], or takes an open
  /// one there.
  void show(List<Shot> shots, int index) {
    if (_open && identical(shots, _shots) && index == _index) return;
    _shots = shots;
    _index = index;
    _open = true;
    notifyListeners();
  }

  /// Takes the pane to the shot of [shots] at [index], which was swiped
  /// to.
  void moveTo(int index) {
    if (!_open || index == _index) return;
    _index = index;
    notifyListeners();
  }

  /// Takes [shots], the grid's as they are now. The shot shown stays, at
  /// its place among them; one that left the grid gives way to the next
  /// one that stayed, or to the last one before it when none follows, and
  /// the pane closes when none of its shots is left.
  void follow(List<Shot> shots) {
    if (!_open || identical(shots, _shots)) return;
    final places = {for (final (i, s) in shots.indexed) s.key: i};
    final nearestFirst = [
      ..._shots.skip(_index),
      ..._shots.take(_index).toList().reversed,
    ];
    final place = nearestFirst.map((s) => places[s.key]).nonNulls.firstOrNull;
    if (place == null) {
      _open = false;
    } else {
      _shots = shots;
      _index = place;
    }
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }
}

/// The shape of the room [ShotPane] gives its shot \[design\]: the
/// sensor's, so a photo taken with the camera held level fills the page's
/// width.
const double _paneShotShape = 3 / 2;

/// A shot of the Library beside its grid, on the second of the two pages
/// of a window with a fold standing upright in it ([pagesAtFold], mock
/// `duo-inner-split`): the shot at the top of the page, fitted to its
/// width, then its name with Download, its details and the map of where
/// it was taken, which scroll when the page is too short for them. A
/// swipe on the shot moves through the grid's shots, a tap on a photo
/// opens it in the full-screen viewer ([onOpen]), and a movie plays in
/// place.
class ShotPane extends StatefulWidget {
  const new({required this.controller, required this.onOpen, super.key});

  /// Says which shot shows, and is told the one swiped to. The same one
  /// for as long as the pane is there.
  final ShotPaneController controller;

  /// The photo shown was tapped.
  final VoidCallback onOpen;

  @override
  State<ShotPane> createState() => _ShotPaneState();
}

class _ShotPaneState extends State<ShotPane> with _ShotPages<ShotPane> {
  late final LibraryContext _library = LibraryScope.of(context);

  /// The shot at [_index] when the controller last said which shows.
  late Shot? _shown = widget.controller.shown;

  @override
  List<Shot> get _shots => widget.controller.shots;

  @override
  int get _firstIndex => widget.controller.index;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  /// Shows the shot the controller is at. One that was not swiped to (a
  /// cell of the grid was tapped, or shots before it came or went) has
  /// its page jumped to, which ends a swipe under way.
  void _onController() {
    final shown = widget.controller.shown;
    // Closed: the Library takes the pane away.
    if (shown == null) return;
    final index = widget.controller.index;
    final moved = index != _index;
    setState(() {
      _index = index;
      // Another shot has another page (keyed by the shot), unzoomed.
      if (shown != _shown) _photoHeld = false;
      _shown = shown;
    });
    if (moved && _pages.hasClients) _pages.jumpToPage(index);
  }

  @override
  void _onShown(Shot shot) => widget.controller.moveTo(_index);

  @override
  Widget build(BuildContext context) {
    final library = _library;
    final serial = library.model.serial;
    final shot = widget.controller.shown;
    // Closed, or its camera gone: the Library is taking the pane away.
    if (shot == null || serial == null) return const SizedBox.shrink();
    final c = GrColors.of(context);
    final leftFirst = Directionality.of(context) == TextDirection.ltr;
    // The window's inset on the side of the fold is the other page's.
    return MediaQuery.removePadding(
      context: context,
      removeLeft: leftFirst,
      removeRight: !leftFirst,
      child: ListenableBuilder(
        listenable: Listenable.merge([library.model, library.engine]),
        builder: (context, _) {
          for (final f in shot.files) {
            unawaited(library.model.ensureInfo(f));
          }
          return SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              key: const Key('shot-pane-scroll'),
              // A zoomed photo keeps drags to itself.
              physics: _photoHeld ? const NeverScrollableScrollPhysics() : null,
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: _paneShotShape,
                    // The details are always in place, and there is no
                    // header.
                    child: _buildPages(
                      serial: serial,
                      immersed: kAlwaysDismissedAnimation,
                      headerVisibility: kAlwaysCompleteAnimation,
                      onPhotoTap: widget.onOpen,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      20,
                      12,
                      16,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ShotName(
                            shot: shot,
                            model: library.model,
                            color: c.t1,
                            detailColor: c.t2,
                            alignment: CrossAxisAlignment.start,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _DownloadAction(
                          key: const ValueKey('pane-download'),
                          serial: serial,
                          shot: shot,
                          engine: library.engine,
                          look: _DownloadLook.labelled,
                        ),
                      ],
                    ),
                  ),
                  _Details(shot: shot, model: library.model),
                  _ShotMap(serial: serial, shot: shot, model: library.model),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The viewer's two pages at a fold ([pagesAtFold]): the [shot] on the
/// first and its [details], which begin [top] down the window, on the
/// second. As the shot takes the whole screen ([immersed] going from 0 to
/// 1) it grows across the fold and they leave by the window's far edge.
/// Away, they are not built: they ask the camera for the photo's Image
/// Control and draw a map, which nothing shows then.
class _ShotBesideDetails extends StatelessWidget {
  const new({
    required this.immersed,
    required this.book,
    required this.top,
    required this.shot,
    required this.details,
  });

  final Animation<double> immersed;
  final BookFold book;
  final double top;
  final Widget shot;
  final Widget details;

  @override
  Widget build(BuildContext context) {
    final leftFirst = Directionality.of(context) == TextDirection.ltr;
    final acrossFold = book.gap + book.second;
    final secondPage = Padding(
      padding: EdgeInsetsDirectional.only(start: book.gap, top: top),
      // The window's inset on the side of the fold is the first page's.
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: leftFirst,
        removeRight: !leftFirst,
        child: details,
      ),
    );
    return AnimatedBuilder(
      animation: immersed,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: shot),
          if (!immersed.isCompleted)
            ClipRect(
              child: SizedBox(
                width: acrossFold * (1 - immersed.value),
                // At its full width whatever shows of it, so it slides
                // instead of being laid out again narrower.
                child: OverflowBox(
                  alignment: AlignmentDirectional.topStart,
                  minWidth: acrossFold,
                  maxWidth: acrossFold,
                  child: secondPage,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The viewer's header: Back to the Library, the shot's name, when it was
/// taken and where it is stored, Info, which shows and hides the shot's
/// details, and [download]. Over the top of a shot that has the whole
/// screen ([immersed] at 1) it is white on the scrim of the badges over
/// photos, so it reads on a bright photo and a dark one, and fades away
/// and back with [visibility]; above a shot with its details ([immersed]
/// at 0) it is the app's bar. With its buttons in the window's vertical
/// bar ([buttonsInBar]) it is the shot's name alone, from the start of
/// the window.
class _Header extends StatelessWidget {
  const new({
    required this.shown,
    required this.visibility,
    required this.immersed,
    required this.shot,
    required this.model,
    required this.buttonsInBar,
    required this.infoShown,
    required this.onInfo,
    required this.download,
  });

  /// Where [visibility] is heading: a header on its way out takes no taps.
  final bool shown;

  /// 0 with the header away, 1 with it in place.
  final Animation<double> visibility;

  /// 0 with the shot's details in place, 1 once the shot has the whole
  /// screen.
  final Animation<double> immersed;
  final Shot shot;
  final LibraryModel model;

  /// Back, Info and Download stand in the window's [VerticalBar], not
  /// here.
  final bool buttonsInBar;
  final bool infoShown;
  final VoidCallback onInfo;
  final Widget? download;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return IgnorePointer(
      ignoring: !shown,
      child: AnimatedBuilder(
        animation: Listenable.merge([visibility, immersed]),
        builder: (context, _) {
          final foreground = Color.lerp(c.t1, Colors.white, immersed.value);
          return Offstage(
            offstage: visibility.isDismissed,
            child: Opacity(
              opacity: visibility.value,
              child: AppBar(
                automaticallyImplyLeading: !buttonsInBar,
                leading: buttonsInBar ? null : const BackButton(),
                centerTitle: buttonsInBar ? false : null,
                titleSpacing: buttonsInBar ? 20 : null,
                foregroundColor: foreground,
                backgroundColor: Color.lerp(
                  c.bg,
                  GrColors.photoBadgeScrim,
                  immersed.value,
                ),
                title: _ShotName(
                  shot: shot,
                  model: model,
                  color: foreground,
                  detailColor: Color.lerp(c.t2, Colors.white70, immersed.value),
                  alignment: buttonsInBar
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                ),
                actions: [
                  if (!buttonsInBar) ...[
                    IconButton(
                      key: const Key('viewer-info'),
                      tooltip: context.l10n.viewerInfo,
                      isSelected: infoShown,
                      onPressed: onInfo,
                      icon: const Icon(Icons.info_outline_rounded),
                      selectedIcon: const Icon(Icons.info_rounded),
                    ),
                    ?download,
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A shot's name over when it was taken and where it is stored.
class _ShotName extends StatelessWidget {
  const new({
    required this.shot,
    required this.model,
    required this.color,
    required this.detailColor,
    required this.alignment,
  });

  final Shot shot;
  final LibraryModel model;
  final Color? color;

  /// The colour of when it was taken and where it is stored.
  final Color? detailColor;

  /// Where the two lines are across the room they have.
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final taken = model.info(shot.primary)?.taken;
    final takenAndStorage = [
      if (taken != null) formatDayTime(context, taken, DateTime.now()),
      ?storageLabel(context, shot.storage),
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text(
          shot.primary.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Text(
          takenAndStorage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GrFonts.monoStyle(context, size: 11, color: detailColor),
        ),
      ],
    );
  }
}

/// How much of the map below a shot's details shows before the viewer is
/// scrolled \[design\]: enough to tell that it is a map and that there is
/// more of it, and no more, so the shot keeps the screen.
const _mapPeek = 64.0;

/// The height of the map below a shot's details.
const _mapHeight = 280.0;

/// The shot's details, or what is below them. As the shot takes the whole
/// screen ([immersed] going from 0 to 1) they slide off the bottom of the
/// screen and leave their room to it. Away, they are not built: they ask
/// the camera for the photo's Image Control and draw a map, which nothing
/// shows then.
class _DetailsBar extends StatelessWidget {
  const new({required this.immersed, required this.child});

  final Animation<double> immersed;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: ReverseAnimation(immersed),
    // The edge next to the shot stays on the shot's.
    alignment: Alignment.topCenter,
    child: AnimatedBuilder(
      animation: immersed,
      builder: (context, child) =>
          immersed.isCompleted ? const SizedBox.shrink() : child!,
      child: child,
    ),
  );
}

/// What is below a shot's details: a map with a pin where the shot was
/// taken, and the room the bottom edge of the screen keeps free.
///
/// The place is the location the camera saved with the shot, which it had
/// from live geotagging. A photo without one gets the place background
/// geotagging gives it when it is downloaded
/// ([GeotagController.backgroundPlace]), while that is on for the camera.
/// A shot with neither has no map.
class _ShotMap extends StatefulWidget {
  const new({required this.serial, required this.shot, required this.model});

  /// The camera of [shot]; null without one, which has no history to ask.
  final String? serial;
  final Shot shot;
  final LibraryModel model;

  @override
  State<_ShotMap> createState() => _ShotMapState();
}

class _ShotMapState extends State<_ShotMap> {
  late GeotagController _geotag;

  /// The camera, shot and capture time [_fromHistory] was asked for; null
  /// when the history is not asked.
  (String, String, DateTime)? _asked;

  /// What the location history has for [_asked].
  GrPhotoLocation? _fromHistory;

  /// The location the camera saved with the shot: with the file shown, or
  /// with the other half of a pair.
  GrPhotoLocation? get _saved {
    final shot = widget.shot;
    for (final file in [shot.primary, ...shot.files]) {
      final location = widget.model.info(file)?.location;
      if (location != null) return location;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _geotag = AppScope.of(context).geotag;
    _askHistory();
  }

  @override
  void didUpdateWidget(_ShotMap old) {
    super.didUpdateWidget(old);
    // Also when the camera's answer about the shot arrives: the viewer
    // builds again then.
    _askHistory();
  }

  /// Asks the location history where the shot was taken, unless it was
  /// asked that already. A shot the camera saved a location with is not
  /// looked up, nor is a movie, which gets none at download, nor a shot
  /// whose capture time is not known yet.
  void _askHistory() {
    final shot = widget.shot;
    final serial = widget.serial;
    final taken = widget.model.info(shot.primary)?.taken;
    final asking =
        serial == null || taken == null || shot.isVideo || _saved != null
        ? null
        : (serial, shot.key, taken);
    if (asking == _asked) return;
    _asked = asking;
    _fromHistory = null;
    if (asking == null) return;
    unawaited(_lookUp(asking));
  }

  Future<void> _lookUp((String, String, DateTime) asking) async {
    final (serial, _, taken) = asking;
    final fix = await _geotag.backgroundPlace(serial, taken);
    if (!mounted || asking != _asked || fix == null) return;
    setState(() => _fromHistory = GrPhotoLocation(fix.latitude, fix.longitude));
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final place = saved ?? _fromHistory;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (place != null)
          SafeArea(
            top: false,
            bottom: false,
            child: GroupBox(
              key: const Key('viewer-map'),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                SizedBox(
                  height: _mapHeight,
                  child: PhotoMap(
                    place: place,
                    // \[design\] The streets around a location the camera
                    // saved, which the phone took as the photo was; the
                    // part of town around one from the history, which
                    // records a place only now and then.
                    zoom: saved != null ? 14 : 12,
                  ),
                ),
              ],
            ),
          ),
        SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

class _PhotoPage extends StatefulWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.immersed,
    required this.headerVisibility,
    required this.onHold,
    required this.onTap,
    super.key,
  });

  final String serial;
  final Shot shot;

  /// 0 with the shot's details in place, 1 once the photo has the whole
  /// screen.
  final Animation<double> immersed;

  /// 0 with the viewer's header away, 1 with it in place.
  final Animation<double> headerVisibility;

  /// Whether the photo keeps drags to itself: it is zoomed in, where a
  /// drag moves it, or two fingers are on it for a pinch.
  final ValueChanged<bool> onHold;

  /// The photo was tapped, not pinched or dragged.
  final VoidCallback onTap;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final _transform = TransformationController();
  bool _zoomed = false;

  /// The fingers on the photo.
  final _fingers = <int>{};

  /// The finger that may be tapping, as it went down; null once it moved
  /// away or another finger joined it.
  PointerDownEvent? _tapping;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    _reportHold();
  }

  void _reportHold() => widget.onHold(_zoomed || _fingers.length > 1);

  void _onFingerDown(PointerDownEvent event) {
    _fingers.add(event.pointer);
    _tapping = _fingers.length == 1 ? event : null;
    _reportHold();
  }

  void _onFingerMove(PointerMoveEvent event) {
    final down = _tapping;
    if (down == null) return;
    if ((event.position - down.position).distance > kTouchSlop) {
      _tapping = null;
    }
  }

  void _onFingerUp(PointerUpEvent event) {
    final down = _tapping;
    _onFingerGone(event);
    if (down != null && event.timeStamp - down.timeStamp < kLongPressTimeout) {
      widget.onTap();
    }
  }

  void _onFingerGone(PointerEvent event) {
    _fingers.remove(event.pointer);
    _tapping = null;
    _reportHold();
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.shot;
    return Semantics(
      onTap: widget.onTap,
      // Taps are told from pinches and drags here, not by a tap
      // recogniser: that one would contend with every pinch and drag for
      // its first movements, which the photo would then not follow.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onFingerDown,
        onPointerMove: _onFingerMove,
        onPointerUp: _onFingerUp,
        onPointerCancel: _onFingerGone,
        child: CameraImage(
          serial: widget.serial,
          file: shot.primary,
          size: GrImageSize.view,
          fit: BoxFit.contain,
          // Only a JPEG's full file decodes; a DNG stays at its preview.
          sharper: shot.jpeg != null ? GrImageSize.full : null,
          wantSharper: _zoomed,
          // For the whole screen, which the photo gets in full screen,
          // rather than once more for each size on the way there.
          decodeSize: MediaQuery.sizeOf(context),
          // Detail for zooming in, without decoding all 26 megapixels.
          zoomHeadroom: 3,
          // The grid already loaded this `view`; no smaller stand-in that
          // would be swapped out.
          showProgress: true,
          // The mark is outside the zoomed picture, so it keeps its corner.
          builder:
              (context, image, {required aspectRatio, required sharpening}) =>
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      InteractiveViewer(
                        transformationController: _transform,
                        // Pinching out ends at the photo fitted to its page.
                        minScale: 1,
                        maxScale: 6,
                        child: SizedBox.expand(child: image),
                      ),
                      if (sharpening)
                        _Sharpening(
                          aspectRatio: aspectRatio,
                          immersed: widget.immersed,
                          headerVisibility: widget.headerVisibility,
                        ),
                    ],
                  ),
        ),
      ),
    );
  }
}

/// Says that the picture shown is a soft stand-in for the sharper copy on
/// its way, from the top corner of the photo as it lies fitted to its
/// page ([aspectRatio] is its width over its height; null takes the
/// page's corner).
class _Sharpening extends StatelessWidget {
  const new({
    required this.aspectRatio,
    required this.immersed,
    required this.headerVisibility,
  });

  final double? aspectRatio;

  /// 0 with the shot's details in place, 1 once the photo has the whole
  /// screen.
  final Animation<double> immersed;

  /// 0 with the viewer's header away, 1 with it in place.
  final Animation<double> headerVisibility;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final page = constraints.biggest;
      final ratio = aspectRatio;
      final photo = ratio == null
          ? page
          : applyBoxFit(BoxFit.contain, Size(ratio, 1), page).destination;
      final safe = MediaQuery.paddingOf(context);
      return AnimatedBuilder(
        animation: Listenable.merge([immersed, headerVisibility]),
        builder: (context, mark) => Stack(
          children: [
            PositionedDirectional(
              // Clear of what the page reaches under once the photo has
              // the whole screen: the status bar and the camera cut-out,
              // and the header while it shows.
              top:
                  max(
                    (page.height - photo.height) / 2,
                    (safe.top + kToolbarHeight * headerVisibility.value) *
                        immersed.value,
                  ) +
                  12,
              end:
                  max(
                    (page.width - photo.width) / 2,
                    max(safe.left, safe.right),
                  ) +
                  12,
              child: mark!,
            ),
          ],
        ),
        child: IgnorePointer(
          child: Semantics(
            label: context.l10n.viewerSharpening,
            child: Container(
              key: const Key('viewer-sharpening'),
              width: 30,
              height: 30,
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: GrColors.photoBadgeScrim,
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _VideoPage extends StatefulWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.active,
    required this.immersed,
    super.key,
  });

  final String serial;
  final Shot shot;

  /// Only the page on screen plays.
  final bool active;

  /// 0 with the shot's details in place, 1 once the movie has the whole
  /// screen.
  final Animation<double> immersed;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final LibraryContext _library = LibraryScope.of(context);
  late final IdleDisconnect _idle = AppScope.of(context).idle;
  VideoPlayerController? _video;
  MovieDownload? _download;
  _MovieProblem? _problem;

  /// Set while Play waits for the camera to confirm the movie, so a
  /// second tap can't start a second copy or player.
  bool _checking = false;

  /// Keeps the movie's copy on disk while the page shows: the player
  /// reads the file without asking the cache again.
  CacheHold? _movieHold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _movieHold ??= _library.movies.hold(widget.serial, widget.shot.primary);
  }

  /// Set while a movie copy or playback keeps the camera's Wi-Fi up.
  VoidCallback? _release;

  void _holdWhileBusy() {
    final busy = _download != null || (_video?.value.isPlaying ?? false);
    if (busy && _release == null) {
      _release = _idle.hold();
    } else if (!busy && _release != null) {
      _release!();
      _release = null;
    }
  }

  /// Every change of [_download] or [_video] goes through here.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _holdWhileBusy();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (!widget.active) unawaited(_video?.pause());
  }

  @override
  void dispose() {
    _movieHold?.release();
    _release?.call();
    _download?.cancel();
    final video = _video;
    if (video != null) {
      video.removeListener(_holdWhileBusy);
      unawaited(_disposePlayer(video));
    }
    super.dispose();
  }

  /// Plays the cached copy, copying the movie from the camera first. While
  /// connected, the camera first confirms the cached copy is of the movie
  /// now at its path (the library drops it otherwise).
  Future<void> _play() async {
    if (_checking || _download != null || _video != null) return;
    final file = widget.shot.primary;
    setState(() {
      _checking = true;
      _problem = null;
    });
    await _library.model.ensureInfo(file);
    if (!mounted) return;
    setState(() => _checking = false);
    var local = _library.movies.cached(widget.serial, file);
    if (local == null) {
      final link = _library.link.value;
      if (link == null || link.serial != widget.serial) return;
      final download = _library.movies.download(link, file);
      setState(() {
        _download = download;
        _problem = null;
      });
      // Only the attempt still on screen may change the page: a cancelled
      // one settles later, possibly after Play started a new attempt.
      bool current() => mounted && identical(_download, download);
      try {
        local = await download.done;
      } on MovieDownloadCancelled {
        if (current()) setState(() => _download = null);
        return;
      } on Object {
        if (!current()) return;
        setState(() {
          _download = null;
          _problem = _MovieProblem.copyFailed;
        });
        return;
      }
      if (!current()) return;
    }
    final controller = VideoPlayerController.file(local)
      ..addListener(_holdWhileBusy);
    setState(() {
      _download = null;
      _video = controller;
      _problem = null;
    });
    try {
      await controller.initialize();
      if (!mounted || !widget.active) return;
      await controller.play();
      if (mounted) setState(() {});
    } on Object {
      unawaited(_disposePlayer(controller));
      if (!mounted) return;
      setState(() {
        _video = null;
        _problem = _MovieProblem.unplayable;
      });
    }
  }

  /// A player that failed to initialise may fail to dispose too; there is
  /// nothing left to release then.
  Future<void> _disposePlayer(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } on Object {
      return;
    }
  }

  void _cancel() {
    _download?.cancel();
    setState(() => _download = null);
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    if (video != null && video.value.isInitialized) {
      return GestureDetector(
        onTap: () =>
            unawaited(video.value.isPlaying ? video.pause() : video.play()),
        child: Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [VideoPlayer(video), MovieScrubber(video)],
            ),
          ),
        ),
      );
    }
    final download = _download;
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraImage(
          serial: widget.serial,
          file: widget.shot.primary,
          size: GrImageSize.thumb,
          fit: BoxFit.contain,
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: download != null
                ? _Copying(download: download, onCancel: _cancel)
                : video != null || _checking
                ? const _OverPhoto(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : ValueListenableBuilder(
                    valueListenable: _library.link,
                    builder: (context, link, _) => _PlayPrompt(
                      immersed: widget.immersed,
                      canPlay:
                          link?.serial == widget.serial ||
                          _library.movies.cached(
                                widget.serial,
                                widget.shot.primary,
                              ) !=
                              null,
                      problem: _problem,
                      onPlay: () => unawaited(_play()),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Why the movie is not playing.
enum _MovieProblem { copyFailed, unplayable }

/// Play, over the movie's still, and why it can't play. The reason is in
/// the app's colour beside the still while the details show, and white
/// once the movie has the whole screen ([immersed] at 1), where black
/// surrounds it in every theme.
class _PlayPrompt extends StatelessWidget {
  const new({
    required this.canPlay,
    required this.problem,
    required this.immersed,
    required this.onPlay,
  });

  final bool canPlay;
  final _MovieProblem? problem;
  final Animation<double> immersed;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final note = switch (problem) {
      _MovieProblem.copyFailed => l10n.viewerMovieCopyFailed,
      _MovieProblem.unplayable => l10n.viewerMovieUnplayable,
      null when !canPlay => l10n.viewerConnectToPlay,
      null => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          key: const ValueKey('viewer-play'),
          iconSize: 36,
          tooltip: l10n.viewerPlay,
          onPressed: canPlay ? onPlay : null,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
        if (note != null) ...[
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: immersed,
            builder: (context, _) => Text(
              note,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color.lerp(c.t2, Colors.white70, immersed.value),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A panel over the movie's still on the scrim of the badges over photos
/// ([GrColors.photoBadgeScrim]), so what it holds reads on a bright frame
/// and a dark one, in every theme. Its content is white.
class _OverPhoto extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: GrColors.photoBadgeScrim,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

/// Progress while the movie is copied from the camera, with Cancel.
class _Copying extends StatelessWidget {
  const new({required this.download, required this.onCancel});

  final MovieDownload download;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => _OverPhoto(
    child: ValueListenableBuilder(
      valueListenable: download.progress,
      builder: (context, fraction, _) => Column(
        key: const ValueKey('viewer-movie-copy'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: fraction,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            fraction == null
                ? context.l10n.viewerCopying
                : context.l10n.viewerCopyingProgress(fraction),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: onCancel,
            child: Text(context.l10n.viewerCancel),
          ),
        ],
      ),
    ),
  );
}

/// Format, size and date of the shot.
class _Details extends StatelessWidget {
  const new({required this.shot, required this.model});

  final Shot shot;
  final LibraryModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final infos = [for (final f in shot.files) model.info(f)];
    final sizes = [for (final i in infos) i?.size];
    final size = sizes.contains(null)
        ? '…'
        : formatBytes(context, sizes.fold(0, (a, b) => a + b!));
    final taken = model.info(shot.primary)?.taken;
    final duration = model.info(shot.primary)?.duration;
    final label = TextStyle(fontSize: 11.5, color: c.t3);
    final value = GrFonts.monoStyle(context, size: 13.5, color: c.t1);
    Widget cell(String title, String text) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: label),
        const SizedBox(height: 3),
        Text(text, style: value),
      ],
    );
    return GroupBox(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          // Cells as wide as their text, which go on to another line once
          // the row is full: a third of the row each cut the time off a
          // date, and the date itself in another year or at large text.
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                cell(l10n.viewerFormat, formatLabel(context, shot.format)),
                cell(
                  shot.isVideo ? l10n.viewerLength : l10n.viewerSize,
                  shot.isVideo
                      ? (duration == null
                            ? '…'
                            : formatDuration(context, duration))
                      : size,
                ),
                cell(
                  l10n.viewerTaken,
                  taken == null
                      ? '…'
                      : formatDayTime(context, taken, DateTime.now()),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shot.files.map((f) => f.name).join(' + '),
                  style: GrFonts.monoStyle(context),
                ),
              ),
              if (shot.isVideo) Text(size, style: GrFonts.monoStyle(context)),
            ],
          ),
        ),
        if (!shot.isVideo)
          // Read again when the primary changes: a pair whose JPEG left
          // the camera shows its RAW.
          _ImageControlRow(key: ValueKey(shot.primary.key), shot: shot),
      ],
    );
  }
}

/// The Image Control the photo was shot with, read from the camera, and
/// Save look (mock `b-viewer`; GR WORLD's "save image control from
/// images"). A skeleton of the row while the camera is asked; hidden while
/// the camera is not connected or has none for the photo.
class _ImageControlRow extends StatefulWidget {
  const new({required this.shot, super.key});

  final Shot shot;

  @override
  State<_ImageControlRow> createState() => _ImageControlRowState();
}

class _ImageControlRowState extends State<_ImageControlRow> {
  late final LibraryContext _library = LibraryScope.of(context);
  Look? _look;

  /// The camera is being asked for the photo's Image Control.
  bool _reading = false;
  bool _saving = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final link = _library.link.value;
    if (link == null) return;
    _reading = true;
    unawaited(_read(link));
  }

  Future<void> _read(CameraLibrary link) async {
    Look? look;
    try {
      look = await link.imageControl(widget.shot.primary);
    } on Object {
      // No Image Control for this file, or the camera did not answer: the
      // row hides; the camera layer traced the exchange.
    }
    if (!mounted) return;
    setState(() {
      _look = look;
      _reading = false;
    });
  }

  /// The picture of the shot to keep with a look saved from it, no more
  /// than [longSide] pixels on its long side, and the layout of the JPEG
  /// it shows as: the shot's full JPEG made smaller, when it has one and
  /// the camera sends it, and else the camera's own preview of the shot,
  /// which is small and in the sensor's layout. Nothing away from a
  /// camera that has neither.
  Future<(Uint8List?, JpegLayout?)> _photoToKeep(int longSide) async {
    final serial = _library.model.serial;
    if (serial == null) return (null, null);
    Future<Uint8List?> load(CameraFile file, GrImageSize size) => _library
        .images
        .load(serial, file, size)
        .future
        .then<Uint8List?>((b) => b, onError: (Object _) => null);

    final jpeg = widget.shot.jpeg;
    final full = jpeg == null ? null : await load(jpeg, GrImageSize.full);
    final smaller = full == null
        ? null
        : await lookPhotoOf(full, longSide: longSide);
    if (smaller != null) return (smaller, readJpegLayout(full!));
    final view = await load(widget.shot.primary, GrImageSize.view);
    return (view, view == null ? null : readJpegLayout(view));
  }

  Future<void> _save(Look look) async {
    final l10n = context.l10n;
    final models = AppScope.of(context);
    final store = models.looks;
    final toasts = Toasts.of(context);
    final name = await askLookName(context, initial: lookBaseLabel(l10n, look));
    if (name == null || !mounted) return;
    setState(() => _saving = true);
    final file = widget.shot.primary;
    final (photo, layout) = await _photoToKeep(
      lookRendererFor(models.connection.body).pictureLongSide,
    );
    // How the camera was held is in the shot's info.
    final info = photo == null
        ? null
        : _library.model.info(file) ?? await _library.model.ensureInfo(file);
    try {
      await store.add(
        name: name,
        data: look.toBytes(),
        source: file.name,
        photo: photo,
        photoOrientation: photo == null
            ? null
            : orientationToApply(layout, info?.orientation),
      );
      toasts.done(l10n.looksSaved(name));
    } on LookConflict catch (conflict) {
      if (mounted) unawaited(showLookConflict(context, conflict));
    } on FileSystemException {
      toasts.failed(l10n.looksSaveFailed(name));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;
    if (look == null) {
      return _reading ? const _ImageControlSkeleton() : const SizedBox.shrink();
    }
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          const _ImageControlRowHeight(),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.tune_rounded, size: 18, color: c.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.viewerImageControl,
                  style: const TextStyle(fontSize: _imageControlTitleSize),
                ),
                Text(
                  lookSummary(l10n, look),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _imageControlSummarySize,
                    color: c.t2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('viewer-save-look'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                fontFamily: GrFonts.ui,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: _saving ? null : () => unawaited(_save(look)),
            child: Text(l10n.viewerSaveLook),
          ),
        ],
      ),
    );
  }
}

/// Text sizes of [_ImageControlRow], shared with its skeleton and
/// [_ImageControlRowHeight].
const _imageControlTitleSize = 14.5;
const _imageControlSummarySize = 12.0;

/// As tall as [_ImageControlRow]'s title over a summary of two lines, and
/// of no width: in the row and in its skeleton, it keeps both at that
/// height whatever the summary's length, so the row replaces the skeleton
/// without moving the photo above.
class _ImageControlRowHeight extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spaces: a line without a glyph is laid out a little lower.
          Text(' ', style: TextStyle(fontSize: _imageControlTitleSize)),
          Text(' \n ', style: TextStyle(fontSize: _imageControlSummarySize)),
        ],
      ),
    ),
  );
}

/// [_ImageControlRow] while the camera is asked: its icon, its title, its
/// summary and Save look as blocks.
class _ImageControlSkeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const Padding(
    key: Key('viewer-image-control-loading'),
    padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: Skeleton(
      child: Row(
        children: [
          _ImageControlRowHeight(),
          SkeletonBox(width: 34, height: 34, radius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 96, fontSize: _imageControlTitleSize),
                SkeletonLine(width: 168, fontSize: _imageControlSummarySize),
              ],
            ),
          ),
          SizedBox(width: 8),
          SkeletonBox(width: 92, height: 36, radius: 18),
        ],
      ),
    ),
  );
}

/// Where a [_DownloadAction] stands, which decides its shape.
enum _DownloadLook {
  /// An icon in the viewer's header.
  header,

  /// A round button in the window's vertical bar.
  bar,

  /// A button that says what it does, beside the shot's name in the
  /// Library's pane.
  labelled,
}

/// Downloads the shot: a RAW+JPEG pair asks whether to download its JPEG,
/// its RAW or both, also after a failed download, so a failed JPEG never
/// keeps its RAW from being chosen; any other shot starts at once, or
/// retries its failed job. Its icon and its tooltip, or its text where it
/// has one ([look]), say that the shot's files are downloading (a ring
/// fills as they do) or queued, that their job failed, or that they were
/// downloaded. Saved files can always be downloaded again: the app cannot
/// see whether they are still on the phone.
class _DownloadAction extends StatelessWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.engine,
    required this.look,
    super.key,
  });

  final String serial;
  final Shot shot;
  final DownloadEngine engine;
  final _DownloadLook look;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final files = shot.files;
    final jobs = [
      for (final j in engine.jobs)
        if (j.serial == serial && j.files.any(files.contains)) j,
    ];
    final running = jobs.any((j) => j.state == DownloadState.running);
    final queued = jobs.any((j) => j.state == DownloadState.queued);
    final failed = jobs
        .where((j) => j.state == DownloadState.failed)
        .firstOrNull;
    final addable = [
      for (final f in files)
        if (!engine.isFileQueued(serial, f)) f,
    ];
    final (IconData icon, String text) = running
        ? (Icons.downloading_rounded, l10n.viewerDownloading)
        : queued
        ? (Icons.schedule_rounded, l10n.viewerQueued)
        : failed != null
        ? (Icons.refresh_rounded, l10n.viewerRetryDownload)
        : engine.areFilesDownloaded(serial, files)
        ? (Icons.check_rounded, l10n.viewerDownloadAgain)
        : (Icons.download_rounded, l10n.viewerDownload);
    final VoidCallback? onTap;
    if (addable.isEmpty) {
      onTap = null;
    } else if (shot.isPair) {
      onTap = () => unawaited(_choose(context));
    } else if (failed != null) {
      onTap = () => engine.retry(failed);
    } else {
      onTap = () => unawaited(engine.enqueueFiles(serial, shot, addable));
    }
    // In [color], and fainter over a part not yet downloaded.
    Widget ring(Color? color) => ValueListenableBuilder(
      valueListenable: engine.progress,
      builder: (context, p, _) => CircularProgressIndicator(
        value: p.fraction,
        strokeWidth: 2,
        color: color,
        backgroundColor: color?.withValues(alpha: .24),
      ),
    );
    switch (look) {
      case _DownloadLook.header:
        final color = IconTheme.of(context).color;
        return IconButton(
          tooltip: text,
          // The header's colour: the app's own is dark over a photo in
          // the light theme. Fainter, except while downloading: the ring
          // is to be read, though nothing is left to tap for.
          disabledColor: running ? color : color?.withValues(alpha: .38),
          onPressed: onTap,
          icon: running
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.arrow_downward_rounded, size: 14),
                    SizedBox.square(dimension: 24, child: ring(color)),
                  ],
                )
              : Icon(icon),
        );
      case _DownloadLook.bar:
        final c = GrColors.of(context);
        return Stack(
          alignment: Alignment.center,
          children: [
            RoundIconButton(
              icon: running ? Icons.arrow_downward_rounded : icon,
              iconSize: running ? 14 : 18,
              label: text,
              onTap: onTap,
              iconColor: onTap == null && !running ? c.t3 : null,
            ),
            if (running)
              IgnorePointer(
                child: SizedBox.square(dimension: 24, child: ring(c.t1)),
              ),
          ],
        );
      case _DownloadLook.labelled:
        final c = GrColors.of(context);
        return FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: c.invBg,
            foregroundColor: c.invFg,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: running
              // In the button's colour, which is fainter while nothing is
              // left to tap for.
              ? Builder(
                  builder: (context) => SizedBox.square(
                    dimension: 16,
                    child: ring(IconTheme.of(context).color),
                  ),
                )
              : Icon(icon, size: 18),
          label: Text(text),
        );
    }
  }

  /// Asks which files of the pair to download (bottom sheet) and queues
  /// them. A choice whose files are all queued already is disabled.
  Future<void> _choose(BuildContext context) async {
    final model = LibraryScope.of(context).model;
    final picked = await showModalBottomSheet<List<CameraFile>>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final l10n = context.l10n;
        Widget option(
          String name,
          IconData icon,
          String label,
          List<CameraFile> files,
        ) {
          final wanted = [
            for (final f in files)
              if (!engine.isFileQueued(serial, f)) f,
          ];
          int? bytes = 0;
          for (final f in files) {
            final size = model.info(f)?.size;
            bytes = size == null || bytes == null ? null : bytes + size;
          }
          final detail = wanted.isEmpty
              ? l10n.viewerQueued
              : bytes == null
              ? null
              : formatBytes(context, bytes);
          return ListTile(
            key: Key('viewer-download-choice:$name'),
            leading: Icon(icon),
            title: Text(label),
            subtitle: detail == null ? null : Text(detail),
            enabled: wanted.isNotEmpty,
            onTap: () => Navigator.of(context).pop(wanted),
          );
        }

        return SafeArea(
          child: ListView(
            key: const Key('viewer-download-sheet'),
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  l10n.viewerDownload,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              option('jpeg', Icons.image_outlined, l10n.libraryFormatJpeg, [
                shot.jpeg!,
              ]),
              option('raw', Icons.raw_on_outlined, l10n.libraryFormatRaw, [
                shot.raw!,
              ]),
              option(
                'both',
                Icons.collections_outlined,
                l10n.viewerDownloadBoth,
                shot.files,
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || picked.isEmpty) return;
    await engine.enqueueFiles(serial, shot, picked);
  }
}
