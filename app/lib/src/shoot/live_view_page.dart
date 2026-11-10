import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/connection/camera_pill.dart';
import 'package:grlab/src/connection/connect_failure_view.dart';
import 'package:grlab/src/connection/connect_steps.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/settings.dart';
import 'package:grlab/src/shoot/live_view_controller.dart';
import 'package:grlab/src/shoot/shoot_format.dart';
import 'package:grlab/src/shoot/shoot_model.dart';
import 'package:grlab/src/shoot/shoot_screen.dart';
import 'package:grlab/src/shoot/shoot_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';

/// Live view (mock `b-shoot`): a viewfinder, always dark, in the chosen
/// theme when that is dark and in the Dark theme otherwise. The picture is
/// shown whole and as large as the window allows. The controls take the
/// room it leaves, above and below it or beside it; where that room is too
/// little they lie over the picture's edges, on a shade that keeps them
/// legible, and the picture can be tapped to focus anywhere between them.
/// The exposure readouts edit on a dial; × goes back to Remote.
class LiveViewPage extends StatelessWidget {
  const new({required this.model, super.key});

  final ShootModel model;

  @override
  Widget build(BuildContext context) {
    final chosen = GrColors.of(context);
    return Theme(
      data: grTheme(
        chosen.brightness == Brightness.dark ? chosen : GrColors.dark,
      ),
      child: Builder(
        builder: (context) => Scaffold(
          key: const Key('shoot-live'),
          backgroundColor: Colors.black,
          body: ListenableBuilder(
            listenable: model.liveView,
            builder: (context, _) => _LiveLayout(model: model),
          ),
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

  ShootModel get _model => widget.model;
  LiveViewController get _live => _model.liveView;

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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  /// From this width the controls above and below the picture take a row
  /// each instead of a stack \[design\].
  static const _wideWidth = 600.0;

  /// The panel beside the picture in [_beside] takes the room the picture
  /// leaves, within these widths \[design\].
  static const _minPanelWidth = 300.0;
  static const _maxPanelWidth = 360.0;

  /// The readouts are at most this wide in a row with the shutter
  /// \[design\].
  static const _maxReadoutsWidth = 420.0;

  static const _shutterSize = 80.0;

  /// Height of the Remote / Live view switch as a row of its own, with the
  /// space above it.
  static const _modeSwitchRowHeight = 52.0;

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

  /// Whether the controls go beside the picture ([_beside]) rather than
  /// above and below it ([_bars]), in a window of [size] that the picture
  /// fills to [picture]. Whichever keeps clear of the picture wins, the
  /// bars first (an upright window); the panel then suits a window as
  /// short as a phone on its side. Where both lie over the picture, the
  /// bars do unless they would hide more than a third of its height and
  /// the panel less of its width: a row of controls over each end of a
  /// large picture hides little of it, a panel squeezed in beside it does
  /// not read well \[design\].
  bool _controlsBeside(Size size, Size picture, {required bool wide}) {
    final bars = _barsHeight(MediaQuery.textScalerOf(context), wide: wide);
    if (size.height - bars < _minRoomBetweenBars) return true;
    final underBars =
        math.max(0, bars - (size.height - picture.height)) / picture.height;
    if (underBars == 0) return false;
    final underPanel =
        math.max(0, _minPanelWidth - (size.width - picture.width)) /
        picture.width;
    if (underPanel == 0) return true;
    return underBars > 1 / 3 && underPanel < underBars;
  }

  @override
  Widget build(BuildContext context) {
    final dialKey = _dialKey != null && _editable(_dialKey!) != null
        ? _dialKey
        : null;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final wide = size.width >= _wideWidth;
          final picture = _largestWithin(size, _pictureAspect);
          return _controlsBeside(size, picture, wide: wide)
              ? _beside(size, picture, dialKey)
              : _bars(size, picture, dialKey, wide: wide);
        },
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
    final readoutsWidth = wide
        ? math.min(_maxReadoutsWidth, size.width - 2 * (24 + _shutterSize + 12))
        : size.width - 32;
    return CustomMultiChildLayout(
      delegate: _BarsLayout(picture: _streaming ? picture : null),
      children: [
        LayoutId(
          id: _Bar.picture,
          child: _Picture(model: _model),
        ),
        LayoutId(
          id: _Bar.top,
          child: _Scrim(
            key: const Key('live-top'),
            edge: Alignment.topCenter,
            child: _top(wide: wide),
          ),
        ),
        LayoutId(
          id: _Bar.bottom,
          child: _Scrim(
            key: const Key('live-bottom'),
            edge: Alignment.bottomCenter,
            child: wide
                ? _bottomRow(dialKey, readoutsWidth: readoutsWidth, hint: hint)
                : _bottomStack(dialKey, shutterInset: 40, hint: hint),
          ),
        ),
        if (dialKey != null)
          LayoutId(
            id: _Bar.dial,
            child: SizedBox(width: readoutsWidth, child: _dial(dialKey)),
          ),
      ],
    );
  }

  /// The controls in a panel at the end of a window of [size]. The
  /// [picture] is centred in the room beside the panel, and lies under it
  /// where that room is too narrow. The dial opens above the readouts.
  Widget _beside(Size size, Size picture, String? dialKey) {
    final text = MediaQuery.textScalerOf(context);
    final panelWidth = math.min(
      size.width,
      (size.width - picture.width).clamp(_minPanelWidth, _maxPanelWidth),
    );
    final room = size.width - panelWidth;
    final bars = _barsHeight(text, wide: false);
    // A window too short for all of it does without the switch: × goes
    // back to Remote too.
    final modeSwitch = size.height >= bars;
    final height = math.max(
      size.height,
      bars - (modeSwitch ? 0 : _modeSwitchRowHeight),
    );
    // The open dial takes the chips' place in a window too short for both.
    final chips = dialKey == null || size.height >= height + _dialRoom;
    // Only where the panel is clear of the picture and has room to spare.
    final hint =
        room >= picture.width &&
        size.height >= bars + _dialRoom + _hintHeight(text);
    final pictureBox = _streaming
        ? Offset(
                math.max(0, (room - picture.width) / 2),
                (size.height - picture.height) / 2,
              ) &
              picture
        // The steps of joining the camera's Wi-Fi keep clear of the panel.
        : Offset.zero & Size(room, size.height);
    return Stack(
      children: [
        PositionedDirectional(
          start: pictureBox.left,
          top: pictureBox.top,
          width: pictureBox.width,
          height: pictureBox.height,
          child: _Picture(model: _model),
        ),
        PositionedDirectional(
          end: 0,
          top: 0,
          bottom: 0,
          width: panelWidth,
          child: _Scrim(
            edge: AlignmentDirectional.centerEnd,
            // Scrolls in a window too short even without the switch, by
            // dragging a control: the space between the controls is left
            // to the picture under it, for a tap there to focus.
            child: SingleChildScrollView(
              key: const Key('live-panel'),
              hitTestBehavior: HitTestBehavior.deferToChild,
              child: SizedBox(
                height: height,
                child: CustomMultiChildLayout(
                  delegate: _BarsLayout(),
                  children: [
                    LayoutId(
                      id: _Bar.top,
                      child: _top(
                        wide: false,
                        modeSwitch: modeSwitch,
                        chips: chips,
                      ),
                    ),
                    LayoutId(
                      id: _Bar.bottom,
                      child: _bottomStack(
                        dialKey,
                        shutterInset: 16,
                        hint: hint,
                      ),
                    ),
                    if (dialKey != null)
                      LayoutId(
                        id: _Bar.dial,
                        child: SizedBox(
                          width: panelWidth - 32,
                          child: _dial(dialKey),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// ×, the camera, Remote / Live view, the exposure mode and the chips:
  /// stacked in three rows (fewer without the [modeSwitch] or the
  /// [chips]), or when [wide] in two.
  Widget _top({required bool wide, bool modeSwitch = true, bool chips = true}) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final close = _RoundButton(
      key: const Key('live-close'),
      icon: Icons.close_rounded,
      label: l10n.liveViewBackToRemote,
      onTap: () => _model.mode = ShootMode.remote,
    );
    final remoteOrLiveView = ShootModeSwitch(
      mode: _model.mode,
      onChanged: (m) => _model.mode = m,
    );
    final exposure = switch (_model.exposure) {
      null => null,
      final exposure => Container(
        key: const Key('live-exposure'),
        height: 36,
        constraints: const BoxConstraints(minWidth: 36),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.s2.withValues(alpha: _surfaceOpacity),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line2),
        ),
        child: Text(
          exposureLabel(l10n, exposure),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.accent,
          ),
        ),
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Row(
            children: wide
                ? [
                    Expanded(
                      child: Row(
                        children: [
                          close,
                          const SizedBox(width: 8),
                          const Flexible(child: CameraPill()),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: remoteOrLiveView,
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [?exposure],
                      ),
                    ),
                  ]
                : [
                    close,
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CameraPill(),
                      ),
                    ),
                    ?exposure,
                  ],
          ),
        ),
        if (!wide && modeSwitch) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: remoteOrLiveView,
          ),
        ],
        if (chips) ...[const SizedBox(height: 12), _chips()],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _chips() {
    final l10n = context.l10n;
    final split = _model.driveAndTimer;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        spacing: 8,
        children: [
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
        ],
      ),
    );
  }

  /// The readouts over the last shot and the shutter, and the hint when
  /// there is room for it ([hint]).
  Widget _bottomStack(
    String? dialKey, {
    required double shutterInset,
    required bool hint,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _readoutsFor(dialKey),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: shutterInset),
        child: Row(
          children: [
            _LastShot(bytes: _live.lastShot),
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
                child: _LastShot(bytes: _live.lastShot),
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

  Widget _readoutsFor(String? dialKey) => _Readouts(
    live: _live,
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

  Widget _shutter() => DecoratedBox(
    // Sets the shutter off from a bright picture under it.
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: GrColors.of(context).shadow, blurRadius: 16),
      ],
    ),
    child: ShutterButton(
      model: _model,
      size: _shutterSize,
      color: const Color(0xFFF6F4EF),
      ringGap: 5,
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

/// Places controls at the top and the bottom of its box and the dial above
/// the bottom ones, and for [_LiveLayoutState._bars] the picture centred
/// between them as far as the box allows.
class _BarsLayout extends MultiChildLayoutDelegate {
  new({this.picture});

  /// The picture's size, which may reach under the controls; null while
  /// there is none, when what shows in its place (the steps of joining the
  /// camera's Wi-Fi) gets the room between the controls.
  final Size? picture;

  @override
  void performLayout(Size size) {
    final bar = BoxConstraints(
      minWidth: size.width,
      maxWidth: size.width,
      maxHeight: size.height,
    );
    final top = layoutChild(_Bar.top, bar).height;
    final bottom = size.height - layoutChild(_Bar.bottom, bar).height;
    positionChild(_Bar.top, Offset.zero);
    positionChild(_Bar.bottom, Offset(0, bottom));
    if (hasChild(_Bar.dial)) {
      final dial = layoutChild(_Bar.dial, BoxConstraints.loose(size));
      positionChild(
        _Bar.dial,
        Offset((size.width - dial.width) / 2, bottom - dial.height),
      );
    }
    if (!hasChild(_Bar.picture)) return;
    final picture = this.picture;
    final box = picture == null
        ? Rect.fromLTRB(0, top, size.width, math.max(top, bottom))
        : Offset(
                (size.width - picture.width) / 2,
                math.max(
                  0,
                  math.min(
                    (top + bottom - picture.height) / 2,
                    size.height - picture.height,
                  ),
                ),
              ) &
              picture;
    layoutChild(_Bar.picture, BoxConstraints.tight(box.size));
    positionChild(_Bar.picture, box.topLeft);
  }

  @override
  bool shouldRelayout(_BarsLayout old) => old.picture != picture;
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
  const new({required this.model});

  final ShootModel model;

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
      // The picture's room may be short (a landscape window): the steps
      // scroll then.
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
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

/// Aperture, shutter, ISO and EV; tapping one the camera lets the app change
/// opens the dial for it.
class _Readouts extends StatelessWidget {
  const new({
    required this.live,
    required this.readouts,
    required this.selected,
    required this.editable,
    required this.onTap,
  });

  final LiveViewController live;

  /// The `/v1/props` keys to show.
  final List<String> readouts;
  final String? selected;
  final bool Function(String key) editable;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final props = live.props;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: c.s2.withValues(alpha: _surfaceOpacity),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        children: [
          for (final key in readouts)
            Expanded(
              child: GestureDetector(
                key: Key('live-readout-$key'),
                behavior: HitTestBehavior.opaque,
                onTap: editable(key) ? () => onTap(key) : null,
                // A narrow window shrinks the text rather than wrapping
                // a value over two lines.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _readoutLabel(l10n, key).toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .6,
                            color: c.t2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          switch (props?.setting(key)?.current) {
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
              ),
            ),
        ],
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
              return GestureDetector(
                key: Key('live-dial-option-$v'),
                behavior: HitTestBehavior.opaque,
                onTap: current ? null : () => widget.onSelect(v),
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
              Text(
                label,
                style: GrFonts.monoStyle(
                  context,
                  size: 12.5,
                  color: onTap == null ? c.t2 : c.t1,
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

/// The newest picture taken while live view is on.
class _LastShot extends StatelessWidget {
  const new({required this.bytes});

  static const size = 56.0;

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final b = bytes;
    return Container(
      key: const Key('live-last-shot'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line2),
      ),
      child: b == null
          ? null
          : Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}
