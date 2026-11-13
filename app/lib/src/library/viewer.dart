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
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';
import 'package:grphoto/src/widgets/skeleton.dart';
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
class ShotViewer extends StatefulWidget {
  const new({required this.shots, required this.initialIndex, super.key});

  final List<Shot> shots;
  final int initialIndex;

  @override
  State<ShotViewer> createState() => _ShotViewerState();
}

class _ShotViewerState extends State<ShotViewer> with TickerProviderStateMixin {
  late final LibraryContext _library = LibraryScope.of(context);

  /// The camera of [_shots]: the listing's camera when the viewer opened.
  late final String? _serial;

  /// [ShotViewer.shots] not known to have left the listing, in their
  /// order, as the listing has them now.
  late final List<Shot> _shots = [...widget.shots];

  /// Keys of the [_shots] a listing has had: these leave with the listing.
  final Set<String> _listed = {};

  /// The listing [_shots] were last matched against. The library reports
  /// far more than new listings (each file's info, its refresh starting
  /// and ending); matching every shot again is for a new listing only.
  List<Shot>? _followed;
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  /// The photo shown keeps drags to itself ([_PhotoPage.onHold]) instead of
  /// letting them swipe to another shot.
  bool _photoHeld = false;

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
    _pages.dispose();
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
    if (kept[index].isVideo) _setHeaderShown(true);
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

  void _onPageChanged(int index) {
    // Also reported after [_followListing] jumped to [_index].
    if (index == _index) return;
    setState(() {
      _index = index;
      _photoHeld = false;
    });
    if (_shots[index].isVideo) _setHeaderShown(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_closing) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    final library = _library;
    final serial = _serial;
    final shot = _shots[_index];
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return ListenableBuilder(
      listenable: Listenable.merge([library.model, library.engine]),
      builder: (context, _) {
        for (final f in shot.files) {
          unawaited(library.model.ensureInfo(f));
        }
        return Scaffold(
          body: AnimatedBuilder(
            animation: _immersed,
            // Black around a shot that has the whole screen.
            builder: (context, child) => ColoredBox(
              color: Colors.black.withValues(alpha: _immersed.value),
              child: child,
            ),
            child: Stack(
              children: [
                // With a map below the details the column is taller than
                // the screen, which shows the map's top: a scroll brings
                // the rest of it up.
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
                          MediaQuery.paddingOf(context).bottom + _mapPeek,
                      shot: Column(
                        children: [
                          // The header's room, which a shot with the whole
                          // screen takes: the header lies over it then.
                          AnimatedBuilder(
                            animation: _immersed,
                            builder: (context, _) => SizedBox(
                              height: headerHeight * (1 - _immersed.value),
                            ),
                          ),
                          Expanded(
                            child: serial == null
                                ? const SizedBox.shrink()
                                : PageView.builder(
                                    controller: _pages,
                                    physics: _photoHeld
                                        ? const NeverScrollableScrollPhysics()
                                        : const PageScrollPhysics(),
                                    itemCount: _shots.length,
                                    onPageChanged: _onPageChanged,
                                    // A page whose shot stays keeps its state
                                    // (zoom, playback) when shots before it
                                    // are dropped.
                                    findChildIndexCallback: (key) {
                                      final i = _shots.indexWhere(
                                        (s) => ValueKey(s) == key,
                                      );
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
                                              immersed: _immersed,
                                            )
                                          : _PhotoPage(
                                              key: ValueKey(s),
                                              serial: serial,
                                              shot: s,
                                              immersed: _immersed,
                                              headerVisibility:
                                                  _headerVisibility,
                                              onHold: _onPhotoHold,
                                              onTap: _onPhotoTap,
                                            );
                                    },
                                  ),
                          ),
                        ],
                      ),
                      details: _DetailsBar(
                        immersed: _immersed,
                        child: SafeArea(
                          top: false,
                          bottom: false,
                          child: _Details(shot: shot, model: library.model),
                        ),
                      ),
                      below: _DetailsBar(
                        immersed: _immersed,
                        child: _ShotMap(
                          serial: serial,
                          shot: shot,
                          model: library.model,
                        ),
                      ),
                    ),
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
                    infoShown: _infoShown,
                    onInfo: () => _setInfoShown(!_infoShown),
                    download: serial == null
                        ? null
                        : _DownloadAction(
                            key: const ValueKey('viewer-download'),
                            serial: serial,
                            shot: shot,
                            engine: library.engine,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The viewer's header: Back to the Library, the shot's name, when it was
/// taken and where it is stored, Info, which shows and hides the shot's
/// details, and [download]. Over the top of a shot that has the whole
/// screen ([immersed] at 1) it is white on the scrim of the badges over
/// photos, so it reads on a bright photo and a dark one, and fades away
/// and back with [visibility]; above a shot with its details ([immersed]
/// at 0) it is the app's bar.
class _Header extends StatelessWidget {
  const new({
    required this.shown,
    required this.visibility,
    required this.immersed,
    required this.shot,
    required this.model,
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
  final bool infoShown;
  final VoidCallback onInfo;
  final Widget? download;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final taken = model.info(shot.primary)?.taken;
    final subtitle = [
      if (taken != null) formatDayTime(context, taken, DateTime.now()),
      ?storageLabel(context, shot.storage),
    ].join(' · ');
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
                leading: const BackButton(),
                foregroundColor: foreground,
                backgroundColor: Color.lerp(
                  c.bg,
                  GrColors.photoBadgeScrim,
                  immersed.value,
                ),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shot.primary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GrFonts.monoStyle(
                        context,
                        size: 11,
                        color: Color.lerp(c.t2, Colors.white70, immersed.value),
                      ),
                    ),
                  ],
                ),
                actions: [
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
              ),
            ),
          );
        },
      ),
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
    final messenger = ScaffoldMessenger.of(context);
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
      showLooksMessage(messenger, l10n.looksSaved(name));
    } on LookConflict catch (conflict) {
      if (mounted) unawaited(showLookConflict(context, conflict));
    } on FileSystemException {
      showLooksMessage(messenger, l10n.looksSaveFailed(name));
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

/// Downloads the shot, from the viewer's header: a RAW+JPEG pair asks
/// whether to download its JPEG, its RAW or both, also after a failed
/// download, so a failed JPEG never keeps its RAW from being chosen; any
/// other shot starts at once, or retries its failed job. Its icon and its
/// tooltip say that the shot's files are downloading (a ring fills as they
/// do) or queued, that their job failed, or that they were downloaded.
/// Saved files can always be downloaded again: the app cannot see whether
/// they are still on the phone.
class _DownloadAction extends StatelessWidget {
  const new({
    required this.serial,
    required this.shot,
    required this.engine,
    super.key,
  });

  final String serial;
  final Shot shot;
  final DownloadEngine engine;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
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
    return IconButton(
      tooltip: text,
      // The header's colour: the app's own is dark over a photo in the
      // light theme. Fainter, except while downloading: the ring is to be
      // read, though nothing is left to tap for.
      disabledColor: running ? color : color?.withValues(alpha: .38),
      onPressed: onTap,
      icon: running
          ? Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.arrow_downward_rounded, size: 14),
                SizedBox.square(
                  dimension: 24,
                  child: ValueListenableBuilder(
                    valueListenable: engine.progress,
                    builder: (context, p, _) => CircularProgressIndicator(
                      value: p.fraction,
                      strokeWidth: 2,
                      color: color,
                      backgroundColor: color?.withValues(alpha: .24),
                    ),
                  ),
                ),
              ],
            )
          : Icon(icon),
    );
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
