import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/services.dart';

/// Leaves the camera's Wi-Fi ([ConnectionController.leaveUnusedWifi])
/// after [SettingsController.autoDisconnect] without use, keeping
/// Bluetooth. Joining the Wi-Fi is slow, so nothing else ends it once it
/// is up short of the user asking: it stays when the user moves on to a
/// page that does not need it, or back to the Cameras screen. \[design\]
///
/// Use is a touch, scroll or key press anywhere in the app (reported by
/// [IdleInput]), navigation ([observer]), and a download, movie copy,
/// playback or live view ([hold]), whose end counts as use too. Counting
/// starts when the Wi-Fi comes up and measures wall-clock time ([clock]),
/// so time in the background counts.
///
/// Where the camera network outlives the app (iOS,
/// `GrCameraEnvironment.wifiOutlivesApp`), a timer cannot be relied on off
/// screen: iOS suspends the app within seconds, and a suspended or ended
/// app keeps the phone on the camera's network, and the camera on, for as
/// long as it lies there. So once the app is off screen the Wi-Fi, or a
/// join still under way (iOS installs the network's configuration before
/// the join completes), is left after [backgroundGrace], whatever the
/// setting, in background time asked of iOS for it, and sooner when iOS
/// gives less than [backgroundGrace] and [backgroundMargin] together.
/// It is kept while iOS keeps the app running for the download queue
/// ([BackgroundDownloads.continued]), also between two downloads; a queue
/// that ends off screen leaves it at once ([leaveOffScreen]), and when iOS
/// ends the task the [backgroundGrace] that has passed counts. \[design\]
///
/// Everywhere else (Android) the phone stays on the camera's network only
/// while the app runs, but the app can be frozen off screen, and its timer
/// with it. So from the start of a join until the Wi-Fi is left the app
/// holds [AppServices.cameraWifi], a foreground service that keeps it
/// running and shows the Wi-Fi, first as joining and then as connected
/// with when it is left, with a Disconnect button, and off screen
/// it keeps the phone awake until the Wi-Fi is due to be left and
/// [awakeMargin] after. A leave that comes late anyway, because the phone
/// slept regardless, says how long the app was really unused.
/// (research/protocol/connection-lifecycle.md §9, "What GR Photo does")
final class IdleDisconnect {
  new({required this.connection, required this.settings})
    : _last = clock.now(),
      _outlivesApp = connection.services.camera.wifiOutlivesApp {
    connection.addListener(_update);
    settings.addListener(_schedule);
    _continued.addListener(_schedule);
    if (!_outlivesApp) {
      _disconnects = _service.disconnects.listen(
        (_) => unawaited(connection.disconnectWifi()),
      );
    }
    _update();
  }

  /// Off screen where the camera network outlives the app, how long the
  /// Wi-Fi stays: long enough to answer a message and come back.
  static const backgroundGrace = Duration(seconds: 20);

  /// Kept free at the end of the background time iOS gives, for leaving:
  /// the network removal, then the Bluetooth write that turns the camera's
  /// Wi-Fi (or the camera) off.
  static const backgroundMargin = Duration(seconds: 8);

  /// Kept awake past the moment the Wi-Fi is due to be left, for leaving:
  /// the Bluetooth write that turns the camera's Wi-Fi (or the camera) off.
  static const awakeMargin = Duration(seconds: 30);

  final ConnectionController connection;
  final SettingsController settings;
  final bool _outlivesApp;

  /// Counts every route change as use. Add to `navigatorObservers`.
  late final NavigatorObserver observer = _NavigationUse(this);

  ValueListenable<bool> get _continued =>
      connection.services.background.continued;

  DateTime _last;
  Timer? _timer;
  int _holds = 0;
  bool _connected = false;

  /// Connected, or joining the camera's Wi-Fi.
  bool _onWifi = false;

  /// Off screen where the camera network outlives the app: when the Wi-Fi
  /// is left. Null in front, and everywhere else.
  DateTime? _offScreenUntil;

  /// The background time asked of iOS, while it is held or being asked for.
  Future<BackgroundTime>? _time;
  Future<void> _leaving = Future.value();
  bool _leavingOffScreen = false;

  CameraWifiService get _service => connection.services.cameraWifi;
  StreamSubscription<void>? _disconnects;

  /// What [_service] shows while it is held; null when it is not.
  CameraWifiNotice? _held;

  /// Until when [_service] keeps the phone awake; null for not at all.
  DateTime? _awakeUntil;

  /// Leaves the camera's Wi-Fi at once if the app is off screen where the
  /// camera network outlives the app, and completes once that is done; at
  /// once when there is nothing to leave. The download queue calls this
  /// before it ends iOS's continued processing task, which lets iOS
  /// suspend the app (`DownloadBackground`).
  Future<void> leaveOffScreen() {
    if (_offScreenUntil == null || _leavingOffScreen || !_onWifi) {
      return _leaving;
    }
    _timer?.cancel();
    _timer = null;
    _leaveOffScreen();
    return _leaving;
  }

  /// Records use now.
  void touch() => _last = clock.now();

  /// Keeps the Wi-Fi up until the returned callback runs (more than once
  /// is fine); that moment counts as use. Until then the Wi-Fi counts as
  /// busy ([ConnectionController.wifiBusy]), so a lost one is got back.
  VoidCallback hold() {
    _holds++;
    connection.wifiBusy = true;
    _schedule();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _holds--;
      connection.wifiBusy = _holds > 0;
      touch();
      _schedule();
    };
  }

  void _update() {
    final offScreen = _outlivesApp && !connection.foreground;
    final status = connection.status;
    final connected = status == ConnectionStatus.connected;
    final onWifi =
        connected ||
        (status == ConnectionStatus.connecting &&
            connection.step == ConnectStep.wifi);
    if (connected && !_connected) touch();
    final changed =
        connected != _connected ||
        onWifi != _onWifi ||
        offScreen != (_offScreenUntil != null);
    _connected = connected;
    _onWifi = onWifi;
    if (offScreen && _offScreenUntil == null) {
      _offScreenUntil = clock.now().add(backgroundGrace);
    } else if (!offScreen && _offScreenUntil != null) {
      _offScreenUntil = null;
      if (!_leavingOffScreen) _endTime();
    }
    if (changed) {
      _schedule();
    } else {
      _syncService();
    }
  }

  void _schedule() {
    _syncService();
    _timer?.cancel();
    _timer = null;
    if (_offScreenUntil != null) return _scheduleOffScreen();
    final after = settings.autoDisconnect.after;
    if (!_connected || after == null || _holds > 0) return;
    final left = _last.add(after).difference(clock.now());
    _timer = Timer(left.isNegative ? Duration.zero : left, _expired);
  }

  void _expired() {
    _timer = null;
    final after = settings.autoDisconnect.after;
    if (_offScreenUntil != null || !_connected || after == null || _holds > 0) {
      return;
    }
    final unused = clock.now().difference(_last);
    if (unused < after) {
      _schedule();
      return;
    }
    unawaited(connection.leaveUnusedWifi(UnusedFor(unused)));
  }

  /// Where the app can be frozen off screen: holds [_service] while on the
  /// camera's Wi-Fi, and off screen has it keep the phone awake until the
  /// Wi-Fi is due to be left.
  void _syncService() {
    if (_outlivesApp) return;
    if (!_onWifi) return _releaseService();
    final notice = _notice();
    if (notice != _held) {
      _held = notice;
      _trace('wifi.service.hold', {'text': notice.text});
      unawaited(_service.hold(notice));
    }
    final after = settings.autoDisconnect.after;
    final awakeUntil =
        !connection.foreground && _connected && after != null && _holds == 0
        ? _last.add(after + awakeMargin)
        : null;
    if (awakeUntil == _awakeUntil) return;
    _awakeUntil = awakeUntil;
    final awake = awakeUntil?.difference(clock.now()) ?? Duration.zero;
    final duration = awake.isNegative ? Duration.zero : awake;
    _trace('wifi.service.keepAwake', {'ms': duration.inMilliseconds});
    unawaited(_service.keepAwake(duration));
  }

  void _releaseService() {
    if (_held == null) return;
    _held = null;
    _awakeUntil = null;
    _trace('wifi.service.release');
    unawaited(_service.release());
  }

  void _trace(String kind, [Map<String, Object?> fields = const {}]) =>
      connection.services.trace(
        TraceEvent(
          channel: TraceChannel.session,
          direction: TraceDirection.internal,
          kind: kind,
          fields: fields,
        ),
      );

  /// What the phone shows of the camera's Wi-Fi, in the app's language:
  /// what `MaterialApp` resolves, without a widget to ask. Auto-disconnect
  /// counts from the moment the Wi-Fi is up, so a join shows no countdown.
  CameraWifiNotice _notice() {
    final l10n = lookupAppLocalizations(
      settings.language ??
          resolveAppLocale(
            PlatformDispatcher.instance.locales,
            AppLocalizations.supportedLocales,
          ),
    );
    final countdown = _connected ? settings.autoDisconnect.after : null;
    return CameraWifiNotice(
      title: _connected
          ? l10n.cameraWifiNoticeTitle
          : l10n.cameraWifiNoticeJoiningTitle,
      text: countdown == null
          ? ''
          : l10n.cameraWifiNoticeText(countdown.inMinutes),
      cameraName: connection.camera?.name ?? '',
      disconnectLabel: l10n.connectionSheetDisconnect,
      channelName: l10n.cameraWifiNoticeChannel,
    );
  }

  /// Off screen where the camera network outlives the app.
  void _scheduleOffScreen() {
    if (_leavingOffScreen) return;
    if (!_onWifi) return _endTime();
    // iOS keeps the app running for the download queue until the task
    // ends, also between two downloads, when nothing holds the Wi-Fi.
    if (_continued.value) return _endTime();
    _askTime();
    final left = _offScreenUntil!.difference(clock.now());
    if (left > Duration.zero) {
      _timer = Timer(left, _schedule);
      return;
    }
    _leaveOffScreen();
  }

  void _leaveOffScreen() {
    // The session traces why (`wifi.stop`, reason `background`).
    _leavingOffScreen = true;
    _leaving = connection
        .leaveUnusedWifi(const UnusedInBackground())
        .whenComplete(() {
          _leavingOffScreen = false;
          _endTime();
        });
  }

  /// Asks iOS for background time, once per stay off screen; time it gives
  /// that ends before [_offScreenUntil] and [backgroundMargin] brings the
  /// leave forward.
  void _askTime() {
    if (_time != null) return;
    final asked = clock.now();
    final time = _time = connection.services.camera.backgroundTime(
      'leave camera Wi-Fi',
    );
    unawaited(_granted(time, asked));
  }

  Future<void> _granted(Future<BackgroundTime> time, DateTime asked) async {
    final granted = await time;
    // Given back meanwhile ([_endTime] ends it).
    if (!identical(_time, time)) return;
    final remaining = granted.remaining;
    final until = _offScreenUntil;
    if (remaining == null || until == null) return;
    final latest = asked.add(remaining - backgroundMargin);
    if (!latest.isBefore(until)) return;
    _offScreenUntil = latest;
    _schedule();
  }

  void _endTime() {
    final time = _time;
    _time = null;
    if (time != null) unawaited(time.then((granted) => granted.end()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _endTime();
    unawaited(_disconnects?.cancel());
    _releaseService();
    connection.removeListener(_update);
    settings.removeListener(_schedule);
    _continued.removeListener(_schedule);
  }
}

final class _NavigationUse extends NavigatorObserver {
  new(this._idle);

  final IdleDisconnect _idle;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _idle.touch();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _idle.touch();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _idle.touch();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _idle.touch();
}

/// Reports touches, scrolls and key presses under [child] to [idle].
class IdleInput extends StatefulWidget {
  const new({required this.idle, required this.child, super.key});

  final IdleDisconnect idle;
  final Widget child;

  @override
  State<IdleInput> createState() => _IdleInputState();
}

class _IdleInputState extends State<IdleInput> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    widget.idle.touch();
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => widget.idle.touch(),
    onPointerSignal: (_) => widget.idle.touch(),
    onPointerPanZoomStart: (_) => widget.idle.touch(),
    child: widget.child,
  );
}
