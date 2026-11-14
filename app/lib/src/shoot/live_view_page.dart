import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/camera/camera_top_bar.dart';
import 'package:grphoto/src/connection/camera_pill.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/connection/connect_steps.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/library/format.dart';
import 'package:grphoto/src/library/library_scope.dart';
import 'package:grphoto/src/library/shot.dart';
import 'package:grphoto/src/library/shot_cell.dart';
import 'package:grphoto/src/library/viewer.dart';
import 'package:grphoto/src/platform/window_pose.dart';
import 'package:grphoto/src/shoot/live_view_controller.dart';
import 'package:grphoto/src/shoot/shoot_format.dart';
import 'package:grphoto/src/shoot/shoot_model.dart';
import 'package:grphoto/src/shoot/shoot_screen.dart';
import 'package:grphoto/src/shoot/shoot_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/pressable.dart';
import 'package:grphoto/src/widgets/toast.dart';
import 'package:grphoto/src/widgets/window_layout.dart';

/// Live view (mock `b-shoot`): a viewfinder, always dark, in the chosen
/// theme when that is dark and in the Dark theme otherwise. The picture is
/// shown whole and as large as the window allows. The controls take the
/// room it leaves, above and below it or in a rail on each side of it;
/// where that room is too little they lie over the picture's edges, on a
/// shade that keeps them legible, and the picture can be tapped to focus
/// anywhere between them. The exposure readouts edit on a dial; × goes
/// back to Remote. The last shot is the newest picture taken since live
/// view was opened, and a tap on it opens the viewer on all of them.
///
/// In a window with a [VerticalBar] (a foldable iPhone, closed or open and
/// held wide) × and the exposure mode stand in the bar, and in a wide one
/// the shutter and the last shot too: the bar is the rail at its end. On a
/// foldable that is half-open on a table the picture is in the half that
/// stands up and every control in the half that lies flat.
class LiveViewPage extends StatelessWidget {
  const new({required this.model, super.key});

  final ShootModel model;

  @override
  Widget build(BuildContext context) {
    final chosen = GrColors.of(context);
    return LibraryScope(
      library: AppScope.of(context).library,
      child: Theme(
        data: grTheme(
          chosen.brightness == Brightness.dark ? chosen : GrColors.dark,
        ),
        child: ListenableBuilder(
          listenable: model.liveView,
          builder: (context, _) => _LiveLayout(model: model),
        ),
      ),
    );
  }
}

class _LiveLayout extends StatefulWidget {
  const new({required this.model});

  final ShootModel model;

  @override
  State<_LiveLayout> createState() => _LiveLayoutState();
}

class _LiveLayoutState extends State<_LiveLayout> {
  /// The readout whose values the dial shows; null hides the dial.
  String? _dialKey;

  late final LibraryContext _library = LibraryScope.of(context);

  /// [LiveViewController.shots] as last grouped into [_grouped].
  List<CameraFile>? _groupedFiles;
  List<Shot> _grouped = const [];

  ShootModel get _model => widget.model;
  LiveViewController get _live => _model.liveView;

  /// The pictures taken since live view was opened, newest first, as the
  /// Library shows them: a RAW+JPEG pair is one.
  List<Shot> get _taken {
    final files = _live.shots;
    if (!identical(files, _groupedFiles)) {
      _groupedFiles = files;
      _grouped = groupShots(files);
    }
    return _grouped;
  }

  /// Opens the viewer on [_taken], at the newest. Live view stops under
  /// it ([LiveViewController.covered]).
  Future<void> _viewTaken() async {
    final shots = _taken;
    if (shots.isEmpty) return;
    final live = _live..covered = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LibraryScope(
            library: _library,
            child: ShotViewer(shots: shots, initialIndex: 0),
          ),
        ),
      );
    } finally {
      live.covered = false;
    }
  }

  Widget _lastShot() => _LastShot(
    serial: _library.model.serial,
    shots: _taken,
    onTap: () => unawaited(_viewTaken()),
  );

  /// The `/v1/props` keys of the readouts, left to right.
  static const _readouts = ['av', 'tv', 'sv', 'xv'];

  /// A setting the camera lets the app change now: it lists more than one
  /// value (Av lists apertures, not shutter speeds), and for the mode dial
  /// settings the camera has reported them since the dial last moved.
  GrSetting? _editable(String key) {
    if (!_live.modeSettled && CameraLiveView.modeSettings.contains(key)) {
      return null;
    }
    final s = _live.props?.setting(key);
    final options = s?.options;
    return options != null && options.length > 1 ? s : null;
  }

  Future<void> _set(String key, String value) async {
    final refusal = await _live.setSetting(key, value);
    if (refusal == null || !mounted) return;
    final l10n = context.l10n;
    final message = switch (refusal) {
      SettingRefusalNotOnWifi() => l10n.liveViewNotOnWifi,
      SettingRefusalByCamera(code: null) => l10n.liveViewSettingFailed,
      SettingRefusalByCamera(code: final code?) =>
        l10n.liveViewSettingFailedCode(code),
    };
    Toasts.of(context).failed(message);
  }

  Future<void> _pick(String key, String title) async {
    final s = _editable(key);
    if (s == null) return;
    final value = await showSettingPicker(
      context,
      title: title,
      key: key,
      options: s.options!,
      current: s.current,
    );
    if (value != null && value != s.current) await _set(key, value);
  }

  Future<void> _pickTimer() async {
    final current = _model.driveAndTimer?.$2;
    final picked = await showModalBottomSheet<ShootTimer>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in ShootTimer.values)
              ListTile(
                key: Key('shoot-timer-${t.name}'),
                title: Text(
                  t == ShootTimer.off
                      ? context.l10n.liveViewTimerOff
                      : t.label(context.l10n),
                ),
                trailing: t == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(context).pop(t),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _model.setTimer(picked);
  }

  /// From this width the controls below the picture take a row instead of
  /// a stack, and those above it two rows instead of three where the top
  /// bar has room for Remote / Live view ([ShootModeSwitch.inTopBar])
  /// \[design\].
  static const _wideWidth = 600.0;

  /// Each rail beside the picture in [_rails] takes the room the picture
  /// leaves on its side, within these widths \[design\].
  static const _minRailWidth = 152.0;
  static const _maxRailWidth = 220.0;

  /// The readouts are at most this wide in a row with the shutter, and
  /// the dial as wide as that \[design\].
  static const _maxReadoutsWidth = 420.0;

  /// The dial lies between the rails where it is at least this wide
  /// there \[design\].
  static const _minDialWidth = 200.0;

  static const _shutterSize = 80.0;

  /// Height of the open dial with the space under it.
  static const _dialRoom = 56.0;

  /// Height of the controls above and below the picture in [_bars], their
  /// margins included and the hint left out: stacked they measured 330 at
  /// text size 100 % and 397 at 200 %, a row each 206 and 247.
  static double _barsHeight(TextScaler text, {required bool wide}) =>
      wide ? 165 + text.scale(41) : 263 + text.scale(67);

  /// Height of the hint under the shutter: one line of it measured 24 at
  /// text size 100 % and 41 at 200 %.
  static double _hintHeight(TextScaler text) => 8 + text.scale(16);

  /// [_bars] needs this much room between its controls, which covers
  /// [_barsHeight] coming out a little short and leaves the steps of
  /// joining the camera's Wi-Fi a place \[design\].
  static const _minRoomBetweenBars = 48.0;

  /// The shutter in a [VerticalBar] fits the bar's width with a margin on
  /// either side \[design\].
  static const _barShutterSize = 64.0;

  /// Under the last shot at the foot of a [VerticalBar], at least: as far
  /// as the dock stands from it on the other pages \[design\].
  static const _barFoot = 16.0;

  /// Between the camera at the top of [_table] and the picture.
  static const _tableTopGap = 8.0;

  /// The half of a foldable on a table that stands up shows the picture
  /// where it has at least this height for it under the camera \[design\].
  static const _minTablePictureHeight = 120.0;

  /// Height of the controls in the flat half of [_table], about: those of
  /// [_bars] and the room kept for the dial.
  static double _tableControlsHeight(TextScaler text, {required bool wide}) =>
      _barsHeight(text, wide: wide) + _dialRoom;

  /// Width of the readouts in a window of [size]: in a row with the last
  /// shot and the shutter ([inRow]), or in a row of their own.
  static double _readoutsWidth(Size size, {required bool inRow}) => inRow
      ? math.min(_maxReadoutsWidth, size.width - 2 * (24 + _shutterSize + 12))
      : size.width - 32;

  /// Whether × and the exposure mode stand in the window's [VerticalBar]
  /// ([BarColumn]), and so nowhere among the other controls.
  bool get _buttonsInBar => VerticalBar.of(context) != null;

  bool get _streaming => _live.phase == LiveViewPhase.streaming;

  /// Width over height of the picture as shown: the frame, turned upright
  /// when the camera is held upright. A GR IV sends 3:2 frames.
  double get _pictureAspect {
    final d = _live.frame.value?.dimensions;
    final aspect = d == null || d.width == 0 || d.height == 0
        ? 3 / 2
        : d.width / d.height;
    return _live.orientation?.upright ?? false ? 1 / aspect : aspect;
  }

  /// Whether the controls go in a rail on each side of the picture
  /// ([_rails]) rather than above and below it ([_bars]), in a window of
  /// [size] that the picture fills to [picture]. Whichever keeps clear of
  /// the picture wins, the bars first (an upright window); the rails then
  /// suit a window as short as a phone on its side. Where both lie over
  /// the picture, the bars do unless they would hide more than a third of
  /// its height and the rails less of its width: a row of controls over
  /// each end of a large picture hides little of it, rails squeezed in
  /// beside it do not read well \[design\]. They never do in a window with
  /// a [VerticalBar], which takes the place of a rail.
  bool _controlsInRails(Size size, Size picture, {required bool wide}) {
    if (VerticalBar.of(context) != null) return false;
    final bars = _barsHeight(MediaQuery.textScalerOf(context), wide: wide);
    if (size.height - bars < _minRoomBetweenBars) return true;
    final underBars =
        math.max(0, bars - (size.height - picture.height)) / picture.height;
    if (underBars == 0) return false;
    final underRails =
        math.max(0, 2 * _minRailWidth - (size.width - picture.width)) /
        picture.width;
    if (underRails == 0) return true;
    return underBars > 1 / 3 && underRails < underBars;
  }

  /// The fold of a foldable that is half-open on a table, where it leaves
  /// a window of [window] in size with [insets] a half that stands up with
  /// room for a picture and a half that lies flat with room for every
  /// control ([_table]); null otherwise. [wide] is whether the controls
  /// can take a row each.
  Rect? _tableFold(Size window, EdgeInsets insets, {required bool wide}) {
    final fold = WindowFold.table(context);
    if (fold == null) return null;
    final uprightHeight = fold.top - insets.top;
    if (uprightHeight < CameraTopBar.height + _minTablePictureHeight) {
      return null;
    }
    final flatHeight = window.height - insets.bottom - fold.bottom;
    final text = MediaQuery.textScalerOf(context);
    return flatHeight >= _tableControlsHeight(text, wide: wide) ? fold : null;
  }

  @override
  Widget build(BuildContext context) {
    final dialKey = _dialKey != null && _editable(_dialKey!) != null
        ? _dialKey
        : null;
    final window = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final bar = VerticalBar.of(context);
    // As far in from one side of the screen as from the other: a phone on
    // its side has its camera cutout at one, and the picture stays in the
    // middle of the screen. A vertical bar is no cutout but the page's
    // own: the picture is in the middle of what the bar leaves.
    final side = bar == null ? math.max(insets.left, insets.right) : 0.0;
    final wide =
        window.width - math.max(insets.horizontal, 2 * side) >= _wideWidth;
    final tableFold = _tableFold(window, insets, wide: wide);
    // The bar where it is the rail at the end of the controls.
    final railBar = wide && tableFold == null ? bar : null;
    return BarColumn(
      buttons: [_close(), ?_exposureMode()],
      child: Scaffold(
        key: const Key('shoot-live'),
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              // On a table the camera goes beside the system's status, not
              // under it ([_tableTop]), and so does the top bar in a status
              // band ([_top]).
              top: tableFold == null && StatusBand.of(context) == null,
              minimum: EdgeInsets.only(left: side, right: side),
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = box.biggest;
                  if (tableFold != null) {
                    return _table(size, tableFold, dialKey, wide: wide);
                  }
                  if (railBar != null) return _barsBesideBar(size, dialKey);
                  final picture = _largestWithin(size, _pictureAspect);
                  return _controlsInRails(size, picture, wide: wide)
                      ? _rails(size, picture, dialKey)
                      : _bars(size, picture, dialKey, wide: wide);
                },
              ),
            ),
            if (railBar != null)
              ..._barRail(railBar, window, bottomInset: insets.bottom),
          ],
        ),
      ),
    );
  }

  /// The controls above and below the [picture], which lies under them
  /// where a window of [size] leaves them too little room of their own.
  /// The dial opens over the picture, above the readouts.
  Widget _bars(Size size, Size picture, String? dialKey, {required bool wide}) {
    final text = MediaQuery.textScalerOf(context);
    // Only where it does not push the controls onto the picture.
    final hint =
        size.height - picture.height >=
        _barsHeight(text, wide: wide) + _hintHeight(text);
    final readoutsWidth = _readoutsWidth(size, inRow: wide);
    return _barsAround(
      picture: _streaming ? picture : null,
      top: _top(switchInBar: ShootModeSwitch.inTopBar(context)),
      bottom: ToastFloor(
        child: wide
            ? _bottomRow(dialKey, readoutsWidth: readoutsWidth, hint: hint)
            : _bottomStack(dialKey, hint: hint),
      ),
      dial: dialKey == null
          ? null
          : SizedBox(width: readoutsWidth, child: _dial(dialKey)),
    );
  }

  /// [top] and [bottom], the controls above and below the picture, as a
  /// [_BarsLayout] places them, with [dial] over the picture above
  /// [bottom]. The picture is [picture] in size; without one it gets the
  /// room between the controls, of which what shows until frames come
  /// keeps to the first [stepsWidth]. With [fold] it ends above that and
  /// [bottom] starts under it.
  Widget _barsAround({
    required Widget top,
    required Widget bottom,
    Widget? dial,
    Size? picture,
    double? stepsWidth,
    Rect? fold,
  }) => CustomMultiChildLayout(
    delegate: _BarsLayout(picture: picture, fold: fold),
    children: [
      LayoutId(
        id: _Bar.picture,
        child: _Picture(model: _model, stepsWidth: stepsWidth),
      ),
      LayoutId(
        id: _Bar.top,
        child: _Scrim(
          key: const Key('live-top'),
          edge: Alignment.topCenter,
          child: top,
        ),
      ),
      LayoutId(
        id: _Bar.bottom,
        child: _Scrim(
          key: const Key('live-bottom'),
          edge: Alignment.bottomCenter,
          child: bottom,
        ),
      ),
      if (dial != null)
        LayoutId(
          id: _Bar.dial,
          child: ToastFloor(child: dial),
        ),
    ],
  );

  /// The controls in a wide window with a [VerticalBar], which is the rail
  /// at its end ([_barRail]): a row above the picture and a row below it,
  /// and the picture as large as fits between them, with nothing over it
  /// \[design\]. Each row is in two parts ([shootPages]), one on each page
  /// of a display that folds down the middle of the window: the camera and
  /// Remote / Live view above, the readouts and the chips below. Only the
  /// picture crosses the fold \[design\]: one cut in two is worse than one
  /// with a crease in it. The dial opens beside the readouts, in the chips'
  /// place \[design\]: it keeps off the picture too, and moves nothing.
  Widget _barsBesideBar(Size size, String? dialKey) {
    final pages = shootPages(context, size.width);
    final firstPage = pages.first;
    final foldGap = pages.gap;
    final readoutsWidth = math.min(_maxReadoutsWidth, firstPage - 2 * 16);
    return _barsAround(
      // Not across a fold that is half-open, where they would not read.
      stepsWidth: foldGap > 0 ? firstPage : null,
      top: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: StatusBandBar(
          barHeight: CameraTopBar.height,
          child: CameraTopBar(middle: _modeSwitch(), pages: pages),
        ),
      ),
      bottom: ToastFloor(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _inTwoParts(
            firstWidth: firstPage,
            gap: foldGap,
            first: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: readoutsWidth,
                child: _readoutsFor(dialKey),
              ),
            ),
            second: dialKey == null
                ? _chipsRow()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxReadoutsWidth,
                      ),
                      child: _dial(dialKey),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// [first] and [second] in a row, each from the start of its part of
  /// it: [first] in the first [firstWidth], [second] in what [gap] leaves
  /// after that.
  Widget _inTwoParts({
    required double firstWidth,
    required double gap,
    required Widget first,
    required Widget second,
  }) => Row(
    children: [
      SizedBox(
        width: firstWidth,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          heightFactor: 1,
          child: first,
        ),
      ),
      SizedBox(width: gap),
      Expanded(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          heightFactor: 1,
          child: second,
        ),
      ),
    ],
  );

  /// The shutter and the last shot in [bar], the rail at the end of
  /// [_barsBesideBar], under × and the exposure mode: the shutter halfway
  /// down a window of [window] in size, where the thumb of the hand that
  /// holds the phone rests, and the last shot at the bar's foot, clear of
  /// the system's [bottomInset].
  List<Widget> _barRail(
    VerticalBar bar,
    Size window, {
    required double bottomInset,
  }) {
    final left = bar.side == BarSide.left ? 0.0 : null;
    final right = bar.side == BarSide.right ? 0.0 : null;
    return [
      Positioned(
        top: (window.height - _barShutterSize) / 2,
        left: left,
        right: right,
        width: bar.width,
        child: Center(child: _shutter(size: _barShutterSize)),
      ),
      Positioned(
        bottom: math.max(bottomInset, _barFoot),
        left: left,
        right: right,
        width: bar.width,
        child: Center(child: _lastShot()),
      ),
    ];
  }

  /// On a foldable that is half-open on a table: the picture in the half
  /// that stands up, between the camera ([_tableTop]) and [fold], and
  /// every control in the half that lies flat, where a tap does not rock
  /// the phone \[design\]. Nothing lies on the fold. The readouts, the
  /// last shot and the shutter are stacked as on a phone, or in a [wide]
  /// window whose flat half is too short for that in a row. The dial
  /// opens in room kept for it above the readouts, and the flat half
  /// scrolls where the controls still come out taller than it.
  Widget _table(Size size, Rect fold, String? dialKey, {required bool wide}) {
    final text = MediaQuery.textScalerOf(context);
    final flatHeight = size.height - fold.bottom;
    final stacked =
        !wide || flatHeight >= _tableControlsHeight(text, wide: false);
    final hint =
        flatHeight >=
        _tableControlsHeight(text, wide: !stacked) + _hintHeight(text);
    final readoutsWidth = _readoutsWidth(size, inRow: !stacked);
    return _barsAround(
      fold: fold,
      top: _tableTop(),
      bottom: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: flatHeight),
          child: Column(
            // The shutter stays at the near edge, the choices under the
            // fold, and the dial opens in the room between them.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _tableChoices(),
              ToastFloor(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _dialRoom,
                      child: dialKey == null
                          ? null
                          : Align(
                              alignment: Alignment.bottomCenter,
                              child: SizedBox(
                                width: readoutsWidth,
                                child: _dial(dialKey),
                              ),
                            ),
                    ),
                    if (stacked)
                      _bottomStack(dialKey, hint: hint)
                    else
                      _bottomRow(
                        dialKey,
                        readoutsWidth: readoutsWidth,
                        hint: hint,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The camera at the top of [_table], clear of the system's status: in
  /// the window's [StatusBand] where it has one, which the picture stays
  /// under.
  Widget _tableTop() {
    final band = StatusBand.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: band?.height ?? 0),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBandBar(
            barHeight: CameraTopBar.height + _tableTopGap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 6, 18, _tableTopGap),
              child: Row(children: [Flexible(child: CameraPill())]),
            ),
          ),
        ],
      ),
    );
  }

  /// Remote / Live view, with × and the exposure mode where the window
  /// has no [VerticalBar] for them, over the chips: what the flat half of
  /// [_table] starts with.
  Widget _tableChoices() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        // Clear of the fold above it.
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _modeSwitch(),
              ),
            ),
            if (!_buttonsInBar) ...[_close(), ?_exposureMode()],
          ],
        ),
      ),
      const SizedBox(height: 12),
      _chipsRow(),
    ],
  );

  /// The controls in a rail at each end of a window of [size], where the
  /// hands hold a phone on its side: ×, the camera and the chips at the
  /// start, the readouts, the shutter and the last shot at the end. The
  /// [picture] is centred between the rails, and lies under them where
  /// the window is too narrow. A rail is too narrow for Remote / Live
  /// view (× goes back to Remote too) and for the hint \[design\]. The
  /// dial opens along the bottom of the picture.
  Widget _rails(Size size, Size picture, String? dialKey) {
    final railWidth = math.min(
      size.width / 2,
      ((size.width - picture.width) / 2).clamp(_minRailWidth, _maxRailWidth),
    );
    final between = size.width - 2 * railWidth;
    // In a window too narrow for the dial between the rails, it runs
    // across the window and they end above it.
    final dialBetween = between - 24 >= _minDialWidth;
    final dialWidth = math.min(
      _maxReadoutsWidth,
      (dialBetween ? between : size.width) - 24,
    );
    final railHeight =
        size.height - (dialKey == null || dialBetween ? 0 : _dialRoom);
    final pictureBox = _streaming
        ? Alignment.center.inscribe(picture, Offset.zero & size)
        // The steps of joining the camera's Wi-Fi keep clear of the rails.
        : Rect.fromLTWH(railWidth, 0, between, size.height);
    return Stack(
      children: [
        Positioned.fromRect(
          rect: pictureBox,
          child: _Picture(model: _model),
        ),
        PositionedDirectional(
          start: 0,
          top: 0,
          width: railWidth,
          height: railHeight,
          child: _Scrim(
            edge: AlignmentDirectional.centerStart,
            child: _startRail(),
          ),
        ),
        PositionedDirectional(
          end: 0,
          top: 0,
          width: railWidth,
          height: railHeight,
          child: _Scrim(
            edge: AlignmentDirectional.centerEnd,
            child: _endRail(dialKey, railHeight),
          ),
        ),
        if (dialKey != null)
          Positioned(
            left: (size.width - dialWidth) / 2,
            bottom: 0,
            width: dialWidth,
            height: _dialRoom,
            child: Align(
              alignment: Alignment.topCenter,
              child: ToastFloor(child: _dial(dialKey)),
            ),
          ),
      ],
    );
  }

  /// ×, the exposure mode, the camera and the chips, down from the top
  /// of the start rail. It scrolls in a window too short for them, by
  /// dragging a control: the space between the controls is left to the
  /// picture under it, for a tap there to focus.
  Widget _startRail() => SingleChildScrollView(
    key: const Key('live-rail-start'),
    hitTestBehavior: HitTestBehavior.deferToChild,
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Row(children: [_close(), const Spacer(), ?_exposureMode()]),
        const CameraPill(stacked: true),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: _chips(),
        ),
      ],
    ),
  );

  /// The readouts, two to a row, at the top of the end rail, the last
  /// shot at the bottom and the shutter between them. It is [height]
  /// tall, or as tall as they take in a window too short for them, where
  /// it scrolls as [_startRail] does.
  Widget _endRail(String? dialKey, double height) => SingleChildScrollView(
    key: const Key('live-rail-end'),
    hitTestBehavior: HitTestBehavior.deferToChild,
    padding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height - 2 * 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: 8,
        children: [_readoutsFor(dialKey, perRow: 2), _shutter(), _lastShot()],
      ),
    ),
  );

  Widget _close() => _RoundButton(
    key: const Key('live-close'),
    icon: Icons.close_rounded,
    label: context.l10n.liveViewBackToRemote,
    onTap: () => _model.mode = ShootMode.remote,
  );

  /// The camera's exposure mode; null while [ShootModel.exposure] is.
  Widget? _exposureMode() {
    final exposure = _model.exposure;
    if (exposure == null) return null;
    final c = GrColors.of(context);
    return Container(
      key: const Key('live-exposure'),
      height: 36,
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: c.s2.withValues(alpha: _surfaceOpacity),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line2),
      ),
      // As wide as its text takes, in a column as in a row.
      child: Center(
        widthFactor: 1,
        child: Text(
          exposureLabel(context.l10n, exposure),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.accent,
          ),
        ),
      ),
    );
  }

  Widget _modeSwitch() =>
      ShootModeSwitch(mode: _model.mode, onChanged: (m) => _model.mode = m);

  /// The chips in a row, which scrolls where it is too long.
  Widget _chipsRow() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(spacing: 8, children: _chips()),
  );

  /// The camera, Remote / Live view and the chips, with × and the
  /// exposure mode where the window has no [VerticalBar] for them:
  /// stacked in three rows, or with Remote / Live view in the top bar
  /// ([switchInBar]) in two. The top bar is Remote's ([CameraTopBar]),
  /// with × and the exposure mode for Back and Settings.
  Widget _top({required bool switchInBar}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusBandBar(
        barHeight: CameraTopBar.height,
        child: CameraTopBar(
          leading: _close(),
          trailing: _exposureMode(),
          middle: switchInBar ? _modeSwitch() : null,
        ),
      ),
      if (!switchInBar) ...[
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _modeSwitch(),
        ),
      ],
      const SizedBox(height: 12),
      _chipsRow(),
      const SizedBox(height: 12),
    ],
  );

  /// The drive, the self-timer, the metering and the Image Control.
  List<Widget> _chips() {
    final l10n = context.l10n;
    final split = _model.driveAndTimer;
    return [
      _Chip(
        key: const Key('live-chip-drive'),
        icon: Icons.burst_mode_outlined,
        label: split?.$1.label(l10n) ?? '—',
        onTap: _model.canShoot
            ? () => unawaited(showDrivePicker(context, _model))
            : null,
      ),
      _Chip(
        key: const Key('live-chip-timer'),
        icon: Icons.timer_outlined,
        label: split?.$2.label(l10n) ?? '—',
        onTap: _model.canShoot && split?.$1 != ShootDrive.continuous
            ? () => unawaited(_pickTimer())
            : null,
      ),
      for (final (key, icon, title) in [
        ('meteringMode', Icons.filter_center_focus, l10n.liveViewMetering),
        ('effect', Icons.tune_rounded, l10n.liveViewImageControl),
      ])
        if (_live.props?.setting(key)?.current case final v?)
          _Chip(
            key: Key('live-chip-$key'),
            icon: icon,
            label: settingLabel(l10n, key, v),
            onTap: _editable(key) == null
                ? null
                : () => unawaited(_pick(key, title)),
          ),
    ];
  }

  /// The readouts over the last shot and the shutter, and the hint when
  /// there is room for it ([hint]).
  Widget _bottomStack(String? dialKey, {required bool hint}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _readoutsFor(dialKey),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          children: [
            _lastShot(),
            Expanded(child: Center(child: _shutter())),
            const SizedBox(width: _LastShot.size),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (hint) _hint(),
    ],
  );

  /// The last shot, the readouts ([readoutsWidth] wide, in the middle of
  /// the window) and the shutter in a row, and the hint when there is
  /// room for it ([hint]).
  Widget _bottomRow(
    String? dialKey, {
    required double readoutsWidth,
    required bool hint,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            SizedBox(
              width: _shutterSize,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _lastShot(),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: readoutsWidth,
                  child: _readoutsFor(dialKey),
                ),
              ),
            ),
            _shutter(),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (hint) _hint(),
    ],
  );

  /// The readouts, [perRow] of them side by side.
  Widget _readoutsFor(String? dialKey, {int perRow = 4}) => _Readouts(
    live: _live,
    perRow: perRow,
    readouts: _readouts,
    selected: dialKey,
    editable: (k) => _editable(k) != null,
    onTap: (k) => setState(() => _dialKey = dialKey == k ? null : k),
  );

  Widget _dial(String key) => _Dial(
    key: Key('live-dial-$key'),
    setting: _editable(key)!,
    onSelect: (v) => unawaited(_set(key, v)),
  );

  /// The shutter, [size] across.
  Widget _shutter({double size = _shutterSize}) => DecoratedBox(
    // Sets the shutter off from a bright picture under it.
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: GrColors.of(context).shadow, blurRadius: 16),
      ],
    ),
    child: ShutterButton(
      model: _model,
      size: size,
      color: const Color(0xFFF6F4EF),
      // In proportion: 5 at its full size.
      ringGap: size / 16,
    ),
  );

  Widget _hint() => Padding(
    key: const Key('live-hint'),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      volumeShutter
          ? context.l10n.liveViewTapToFocusVolume
          : context.l10n.liveViewTapToFocus,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11.5, color: GrColors.of(context).t2),
    ),
  );
}

/// How far the controls' own surfaces hide a picture under them: enough
/// for their grey labels to read on a bright one \[design\].
const _surfaceOpacity = .88;

/// The largest size of [aspect] (width over height) that fits in [size].
Size _largestWithin(Size size, double aspect) =>
    size.width > size.height * aspect
    ? Size(size.height * aspect, size.height)
    : Size(size.width, size.width / aspect);

/// The parts [_BarsLayout] places.
enum _Bar { picture, top, bottom, dial }

/// Places [_LiveLayoutState._barsAround]: the controls at the top and the
/// bottom of its box, the dial above the bottom ones, and the picture
/// centred between them as far as the box allows.
class _BarsLayout extends MultiChildLayoutDelegate {
  new({this.picture, this.fold});

  /// The picture's size, which may reach under the controls; null while
  /// there is none, when what shows in its place (the steps of joining the
  /// camera's Wi-Fi) gets the room between the controls, and where the
  /// picture is to be as large as fits in that room.
  final Size? picture;

  /// The fold of a foldable that is half-open on a table
  /// ([_LiveLayoutState._table]), in a box that starts at the top of the
  /// window: the room for the picture ends above it, and the bottom
  /// controls get the room under it instead of the height they take at
  /// the bottom of the box.
  final Rect? fold;

  @override
  void performLayout(Size size) {
    final bar = BoxConstraints(
      minWidth: size.width,
      maxWidth: size.width,
      maxHeight: size.height,
    );
    final fold = this.fold;
    final bottomBar = fold == null
        ? bar
        : bar.tighten(height: size.height - fold.bottom);
    final top = layoutChild(_Bar.top, bar).height;
    final bottom = size.height - layoutChild(_Bar.bottom, bottomBar).height;
    positionChild(_Bar.top, Offset.zero);
    positionChild(_Bar.bottom, Offset(0, bottom));
    if (hasChild(_Bar.dial)) {
      final dial = layoutChild(_Bar.dial, BoxConstraints.loose(size));
      positionChild(
        _Bar.dial,
        Offset((size.width - dial.width) / 2, bottom - dial.height),
      );
    }
    final picture = this.picture;
    final pictureBottom = fold?.top ?? bottom;
    final box = picture == null
        ? Rect.fromLTRB(0, top, size.width, math.max(top, pictureBottom))
        : Offset(
                (size.width - picture.width) / 2,
                math.max(
                  0,
                  math.min(
                    (top + pictureBottom - picture.height) / 2,
                    size.height - picture.height,
                  ),
                ),
              ) &
              picture;
    layoutChild(_Bar.picture, BoxConstraints.tight(box.size));
    positionChild(_Bar.picture, box.topLeft);
  }

  @override
  bool shouldRelayout(_BarsLayout old) =>
      old.picture != picture || old.fold != fold;
}

/// [child] on a shade that is darkest at [edge] of the window and fades
/// out towards the opposite side, so controls stay legible where the
/// picture lies under them. Taps between the controls reach the picture.
class _Scrim extends StatelessWidget {
  const new({required this.edge, required this.child, super.key});

  final AlignmentGeometry edge;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Eased, so the shade ends without a visible line.
              gradient: LinearGradient(
                begin: edge,
                end: -edge,
                colors: const [
                  Color(0x80000000),
                  Color(0x52000000),
                  Color(0x29000000),
                  Color(0x0D000000),
                  Color(0x00000000),
                ],
                stops: const [0, .3, .6, .85, 1],
              ),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// The picture, whole and centred, turned upright as the camera is held,
/// with the focus mark; or, until frames come, the steps of joining the
/// camera's Wi-Fi or why it failed.
class _Picture extends StatelessWidget {
  const new({required this.model, this.stepsWidth});

  final ShootModel model;

  /// How much of the picture's room, from its start, what shows until
  /// frames come keeps to; null for all of it.
  final double? stepsWidth;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final live = model.liveView;
    final connection = live.connection;
    final failure = connection.failure;
    final camera = connection.camera;
    final phase = live.phase;
    if (phase != LiveViewPhase.streaming) {
      final Widget content;
      if (phase == LiveViewPhase.off) {
        // Turning the camera on first, or it is off.
        content = ShootPowerLine(model: model);
      } else if (phase == LiveViewPhase.joining &&
          failure != null &&
          failure.step == ConnectStep.wifi &&
          camera != null) {
        content = ConnectFailureView(
          camera: camera,
          failure: failure,
          connection: connection,
        );
      } else if (phase == LiveViewPhase.joining) {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (camera?.name) {
                final name? => context.l10n.liveViewJoining(name),
                null => context.l10n.liveViewJoiningUnnamed,
              },
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ConnectSteps(connection: connection),
          ],
        );
      } else {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(context.l10n.liveViewStarting, style: TextStyle(color: c.t2)),
          ],
        );
      }
      final stepsWidth = this.stepsWidth;
      // The picture's room may be short (a landscape window): the steps
      // scroll then.
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                end: stepsWidth == null ? 0 : box.maxWidth - stepsWidth,
              ),
              child: Center(
                child: Padding(
                  key: Key('live-${phase.name}'),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  // A block in the middle of a wide window, not lines
                  // across it.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final turns = live.orientation?.quarterTurns ?? 0;
    return ValueListenableBuilder<LiveViewFrame?>(
      valueListenable: live.frame,
      builder: (context, frame, _) {
        if (frame == null) return const SizedBox.shrink();
        final d = frame.dimensions;
        final aspect = d == null || d.width == 0 || d.height == 0
            ? 3 / 2
            : d.width / d.height;
        return Center(
          child: AspectRatio(
            aspectRatio: turns.isOdd ? 1 / aspect : aspect,
            // Turned as a whole: taps and the focus mark stay in the
            // frame's own layout, which is how the camera takes a focus
            // point (remote-shooting.md §3.2).
            child: RotatedBox(
              key: Key('live-turned-$turns'),
              quarterTurns: turns,
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  key: const Key('live-picture'),
                  onTapUp: (t) => unawaited(
                    live.focusAt(
                      Offset(
                        t.localPosition.dx / box.maxWidth,
                        t.localPosition.dy / box.maxHeight,
                      ),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        frame.jpeg,
                        gaplessPlayback: true,
                        fit: BoxFit.fill,
                      ),
                      if (live.focus case final f?)
                        _FocusMark(mark: f, size: box.biggest),
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

class _FocusMark extends StatelessWidget {
  const new({required this.mark, required this.size});

  final FocusMark mark;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    const side = 72.0;
    final color = switch (mark.state) {
      FocusState.focusing => c.accent,
      FocusState.focused => c.ok,
      FocusState.missed => c.danger,
    };
    return Positioned(
      key: Key('live-focus-${mark.state.name}'),
      left: mark.at.dx * size.width - side / 2,
      top: mark.at.dy * size.height - side / 2,
      width: side,
      height: side,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// Aperture, shutter, ISO and EV, [perRow] side by side; tapping one the
/// camera lets the app change opens the dial for it.
class _Readouts extends StatelessWidget {
  const new({
    required this.live,
    required this.readouts,
    required this.perRow,
    required this.selected,
    required this.editable,
    required this.onTap,
  });

  final LiveViewController live;

  /// The `/v1/props` keys to show.
  final List<String> readouts;
  final int perRow;
  final String? selected;
  final bool Function(String key) editable;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: c.s2.withValues(alpha: _surfaceOpacity),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          for (var first = 0; first < readouts.length; first += perRow)
            Row(
              children: [
                for (final key in readouts.skip(first).take(perRow))
                  Expanded(child: _readout(context, key)),
              ],
            ),
        ],
      ),
    );
  }

  /// A narrow window shrinks the text rather than wrapping a value over
  /// two lines.
  Widget _readout(BuildContext context, String key) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return Pressable(
      key: Key('live-readout-$key'),
      onTap: editable(key) ? () => onTap(key) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                l10n.upperCase(_readoutLabel(l10n, key)),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: l10n.capitalSpacing(.6),
                  color: c.t2,
                ),
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                switch (live.props?.setting(key)?.current) {
                  final v? => settingLabel(l10n, key, v),
                  null => '—',
                },
                style: GrFonts.monoStyle(
                  context,
                  size: 17,
                  weight: FontWeight.w500,
                  color: key == selected
                      ? c.accent
                      : editable(key)
                      ? c.t1
                      : c.t2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _readoutLabel(AppLocalizations l10n, String key) => switch (key) {
  'av' => l10n.liveViewAperture,
  'tv' => l10n.liveViewShutter,
  'sv' => l10n.liveViewIso,
  'xv' => l10n.liveViewEv,
  _ => key,
};

/// The values of one setting in a row, the current one centred
/// (mock `.dial`). It rises into its place above the readouts when it
/// opens.
class _Dial extends StatefulWidget {
  const new({required this.setting, required this.onSelect, super.key});

  final GrSetting setting;
  final ValueChanged<String> onSelect;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> with SingleTickerProviderStateMixin {
  static const _item = 56.0;
  late final ScrollController _scroll;
  late final _opening = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final _rise = CurvedAnimation(
    parent: _opening,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, .35),
    end: Offset.zero,
  ).animate(_rise);

  int get _index =>
      widget.setting.options!.indexOf(widget.setting.current ?? '');

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: _index < 0 ? 0 : _index * _item,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opening.isAnimating || _opening.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _opening.value = 1;
    } else {
      _opening.forward();
    }
  }

  @override
  void didUpdateWidget(_Dial old) {
    super.didUpdateWidget(old);
    if (old.setting.current != widget.setting.current && _index >= 0) {
      _scroll.animateTo(
        _index * _item,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    _opening.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final options = widget.setting.options!;
    final key = widget.setting.key;
    final dial = Container(
      height: 44,
      decoration: BoxDecoration(
        color: c.s1.withValues(alpha: _surfaceOpacity),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final pad = (box.maxWidth - _item) / 2;
          return ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemExtent: _item,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final v = options[i];
              final current = v == widget.setting.current;
              final label = settingLabel(
                context.l10n,
                key,
                v,
              ).replaceFirst('f/', '');
              return Pressable(
                key: Key('live-dial-option-$v'),
                onTap: current ? null : () => widget.onSelect(v),
                shape: const StadiumBorder(),
                child: Center(
                  child: FittedBox(
                    child: Text(
                      label,
                      style: GrFonts.monoStyle(
                        context,
                        size: 13,
                        weight: current ? FontWeight.w700 : FontWeight.w400,
                        color: current ? c.t1 : c.t2,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    return FadeTransition(
      opacity: _rise,
      child: SlideTransition(position: _slide, child: dial),
    );
  }
}

class _Chip extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Material(
      color: c.s2.withValues(alpha: _surfaceOpacity),
      shape: StadiumBorder(side: BorderSide(color: c.line2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: onTap == null ? c.t3 : c.t1),
              const SizedBox(width: 6),
              // A rail shrinks a long label rather than cutting it short.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    label,
                    style: GrFonts.monoStyle(
                      context,
                      size: 12.5,
                      color: onTap == null ? c.t2 : c.t1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: c.s2.withValues(alpha: _surfaceOpacity),
        shape: CircleBorder(side: BorderSide(color: c.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, size: 18, color: c.t1, semanticLabel: label),
          ),
        ),
      ),
    );
  }
}

/// The newest picture taken since live view was opened, the picture the
/// Library's grid shows of it, so it comes in as it stays: upright and
/// filling the square. A tap opens the pictures taken.
class _LastShot extends StatelessWidget {
  const new({required this.serial, required this.shots, required this.onTap});

  static const size = 56.0;
  static const _radius = BorderRadius.all(Radius.circular(12));

  /// The camera of [shots]; null while the library has none.
  final String? serial;

  /// The pictures taken, newest first.
  final List<Shot> shots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final serial = this.serial;
    final newest = shots.firstOrNull;
    final shown = serial != null && newest != null;
    final square = Container(
      key: const Key('live-last-shot'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: _radius,
        border: Border.all(color: c.line2),
      ),
      child: shown
          ? Stack(
              fit: StackFit.expand,
              children: [
                // The shot before stays under the newest until that one's
                // picture is in: the square is not empty in between.
                for (final shot in shots.take(2).toList().reversed)
                  CameraImage(
                    key: ValueKey(shot.primary),
                    serial: serial,
                    file: shot.primary,
                    size: shot.gridSize,
                  ),
              ],
            )
          : null,
    );
    if (!shown) return square;
    return Semantics(
      label: context.l10n.libraryShotSemantics(
        formatLabel(context, newest.format),
        newest.primary.name,
      ),
      button: true,
      child: Pressable(
        onTap: onTap,
        shape: const RoundedRectangleBorder(borderRadius: _radius),
        child: square,
      ),
    );
  }
}
