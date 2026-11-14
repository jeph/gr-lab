import 'dart:async';

import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_camera/src/geotag/geotagging.dart';
import 'package:gr_camera/src/library/camera_library.dart';
import 'package:gr_camera/src/looks/camera_looks.dart';
import 'package:gr_camera/src/platform/wifi_control.dart';
import 'package:gr_camera/src/shoot/live_view.dart';
import 'package:gr_camera/src/shoot/remote.dart';
import 'package:gr_camera/src/status.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// What a [CameraSession] asks the app before and around joining the
/// camera's Wi-Fi.
///
/// [ask] runs before the first join of the session (the join loop retries,
/// so once is enough); answering false ends the Wi-Fi start with
/// [GrSessionException.wifiDeclined]. [joined] records a successful join
/// so the app can skip the question next time.
///
/// Android can still show its network list for a network it approved
/// before (after the user disconnected it in Wi-Fi settings). When that
/// list covered a failed join of a camera approved before
/// ([cameraApproved]), [askAgain] explains it and, if the user agrees, the
/// join runs again, bringing the list back. Joins of an approved camera tell
/// the platform so (`WifiNetworkControl.join`'s `approved`).
final class WifiConsent {
  /// The app's answers; see the class doc for when each runs.
  const new({
    required this.ask,
    required this.askAgain,
    required this.cameraApproved,
    required this.joined,
  });

  /// Asks the user before the session's first join of the camera network
  /// (its SSID is passed); false declines.
  final Future<bool> Function(String ssid) ask;

  /// Explains a failed join of an approved camera's network (SSID passed)
  /// and asks to try again; false gives up.
  final Future<bool> Function(String ssid) askAgain;

  /// The user approved this camera's network before.
  final bool Function() cameraApproved;

  /// Records a successful join.
  final Future<void> Function() joined;
}

/// Why the app leaves the camera's Wi-Fi ([CameraSession.stopWifi]), for
/// the trace: the Wi-Fi is kept up between uses, so a log has to say what
/// ended it.
enum WifiStopReason {
  /// The user asked: Disconnect Wi-Fi, cancelling a join, or leaving a page
  /// while its join or recovery was still under way.
  user,

  /// The app was not used for the auto-disconnect time.
  idle,

  /// The app went off screen on a phone where the camera network outlives
  /// it (`GrCameraEnvironment.wifiOutlivesApp`).
  background,

  /// The Wi-Fi was lost while nothing shown needed it, so it is not got
  /// back.
  lostUnneeded,

  /// Bluetooth is gone for good and nothing shown needs the Wi-Fi: the
  /// session ends so the camera can be linked again.
  bluetoothLost,

  /// The session gave up getting a lost Wi-Fi back.
  recoveryGaveUp,

  /// The app's power button is turning the camera off.
  powerOff,
}

/// One connection to one paired camera, in two stages: Bluetooth
/// ([connectBluetooth]) and the camera's Wi-Fi ([startWifi], [stopWifi]).
/// The session reconnects Bluetooth and recovers a lost Wi-Fi link by
/// itself, except that it leaves a camera that turned off off, reporting
/// each step in [events] (also traced on [TraceChannel.session]).
final class CameraSession {
  /// A session with the camera reached through [camera], asking [consent]
  /// before joining its Wi-Fi.
  new(GrCameraEnvironment camera, {required WifiConsent consent})
    : this._(
        camera,
        _ConsentWifi(
          camera.wifi,
          approvalShown: camera.wifiApprovalShown,
          consent: consent,
        ),
      );

  new _(this._environment, this._wifi)
    : _session = GrSession(
        transport: _environment.ble,
        wifi: _wifi,
        host: _environment.cameraHost,
        options: _environment.sessionOptions,
        trace: _environment.trace,
        httpFactory: _environment.httpFactory,
      ) {
    status = createCameraStatus(_session, _environment);
    geotagging = createCameraGeotagging(
      _session,
      _environment,
      body: () => body,
    );
  }

  final GrSession _session;
  final GrCameraEnvironment _environment;
  final _ConsentWifi _wifi;

  /// The camera's battery and storages, for the whole session.
  late final CameraStatus status;

  /// Live geotagging and clock sync for this camera, for the whole
  /// session: it does nothing until the app gives it its settings
  /// (`CameraGeotagging.configure`), and stops when the session closes.
  late final CameraGeotagging geotagging;

  /// The paired camera's serial number, which [connectBluetooth] links to.
  String? _serial;

  /// The model and firmware recorded for the camera, which fill in what a
  /// link does not read ([body]).
  CameraBody _saved = CameraBody.unknown;
  CameraLibrary? _library;

  /// The change socket of the link [_library] belongs to.
  GrChangesSocket? _libraryLink;
  CameraRemote? _remote;
  CameraLooks? _looks;
  CameraLiveView? _liveView;

  /// Every step of the session, such as `ble.lost`, `ble.restored`,
  /// `ble.gaveUp`, `ble.needsPairing`, `wifi.lost`, `recovery.done` and
  /// `recovery.gaveUp` (fields `cameraOff`, `noBle`, `declined`,
  /// `vpnSuspected`).
  Stream<GrSessionEvent> get events => _session.events;

  /// Current stage, from scanning through the Bluetooth link and Wi-Fi
  /// join to `connected`, `recovering`, `lost` or `closed`.
  GrSessionPhase get phase => _session.phase;

  /// The camera is off (it answered over Bluetooth in its BT-only state),
  /// or reported turning off.
  bool get cameraOff => _session.cameraOff;

  /// The Bluetooth link is up.
  bool get bleLinked => _session.ble != null;

  /// The Bluetooth link dropped on its own and the session is linking
  /// again. Not while the camera is off or turning off ([turningOff]):
  /// those drops are the camera's own and no loss.
  bool get bleReconnecting => _session.bleReconnecting;

  /// This session turned the camera off and the camera has not settled
  /// yet: until it is linked again in its off state, or the time for that
  /// runs out.
  bool get turningOff => _session.turningOff;

  /// The session let go of a camera that is off and only reads its
  /// advertisements, until one says the camera is on and it links again
  /// (`ble.parked`, then `ble.seenOn`).
  bool get parked => _session.parked;

  /// The camera's Wi-Fi was lost and the session is getting it back.
  bool get wifiRecovering => _session.wifiRecovering;

  /// The firmware version the camera reported over Bluetooth when it last
  /// linked; null before the first link.
  String? get firmwareRevision => _session.identity?.firmwareRevision;

  /// The camera's model and firmware, for what it supports: as it reported
  /// them over Bluetooth when it last linked, with what it did not report
  /// (or before the first link, everything) from the `saved` record given
  /// to [connectBluetooth].
  CameraBody get body => switch (_session.identity) {
    final identity? => CameraBody.reported(identity).completedBy(_saved),
    null => _saved,
  };

  /// The newest `/v1/props` the session read over Wi-Fi.
  GrProps? get props => _session.props;

  /// The camera network's name, once the session has read it.
  String? get ssid => _session.credentials?.ssid;

  /// Links the camera over Bluetooth: directly to [deviceId], which pairing
  /// recorded, matching [serial]. [saved] is the model and firmware last
  /// recorded for it, for [body]. A camera that is off is not woken; it
  /// drops the link soon after, and [startWifi] links again. Throws
  /// [GrSessionException]; check [GrSessionException.needsPairing].
  Future<void> connectBluetooth({
    required String deviceId,
    required String serial,
    CameraBody saved = CameraBody.unknown,
  }) {
    _serial = serial;
    _saved = saved;
    return _session.connectBluetooth(deviceId: deviceId, serial: serial);
  }

  /// Joins the camera's Wi-Fi, turning the camera on first when it is off,
  /// and verifies it is the paired camera. Throws [GrSessionException];
  /// check [GrSessionException.wifiDeclined].
  Future<void> startWifi() => _session.startWifi();

  /// Leaves the camera's Wi-Fi, or stops joining it or getting it back,
  /// keeping Bluetooth; [reason] is traced (`wifi.stop`). With
  /// [powerOffIfWoken], a camera this session turned on is turned off
  /// again.
  Future<void> stopWifi({
    required WifiStopReason reason,
    bool powerOffIfWoken = false,
  }) {
    _environment.event('wifi.stop', {
      'reason': reason.name,
      'powerOffIfWoken': powerOffIfWoken,
    });
    return _session.stopWifi(powerOffIfWoken: powerOffIfWoken);
  }

  /// Turns the camera off if this session turned it on.
  Future<void> powerOffIfWoken() => _session.powerOffIfWoken();

  /// Turns the camera on into playback, as GR WORLD's power button does,
  /// linking again first when the link is down. The camera stays on when
  /// the session ends. Throws [GrSessionException].
  Future<void> powerOn() => _session.powerOn();

  /// Turns the camera off over Bluetooth, as GR WORLD's power button does;
  /// the camera drops the link and is linked again in its off state
  /// ([turningOff] meanwhile). Only while the camera's Wi-Fi is not in
  /// use ([stopWifi] first). Returns whether the camera took it.
  Future<bool> powerOff() => _session.powerOff();

  /// A request over Wi-Fi failed: asks the camera once whether its Wi-Fi
  /// still works; when it does not, the session counts the link as lost and
  /// recovers it. True while the camera answers.
  Future<bool> checkWifi() => _session.checkWifi();

  /// Ends the session: Wi-Fi, Bluetooth and every recovery. The phone
  /// always leaves the camera's Wi-Fi (or stops joining it). With
  /// [powerOffIfWoken], a camera this session turned on (including one
  /// whose wake is still in flight) is turned off again; camera power is
  /// separate from the phone's Wi-Fi.
  Future<void> close({bool powerOffIfWoken = false}) {
    status.close();
    geotagging.close();
    _remote?.close();
    _looks?.close();
    _liveView?.close();
    _wifi.cancelJoins();
    return _session.close(powerOffIfWoken: powerOffIfWoken);
  }

  /// The camera's `/v1/changes` notifications while its WebSocket is open
  /// (Wi-Fi verified); null otherwise. Each Wi-Fi join opens a new socket,
  /// so listen again after the link comes back.
  Stream<GrChangeEvent>? get changes => _session.changes?.events;

  /// The camera's photos while its Wi-Fi is verified; null otherwise. Each
  /// verified Wi-Fi link gives a new [CameraLibrary] (the same one for as
  /// long as that link lasts), so a view-model tells a rejoin apart with
  /// `identical` and drops work begun on the link that went.
  CameraLibrary? get library {
    final http = _session.http;
    // The session keeps its HTTP client across a recovered link but opens
    // a new change socket for each verified one, so the socket marks the
    // link.
    final link = _session.changes;
    final serial = _serial;
    if (http == null ||
        link == null ||
        serial == null ||
        _session.phase != GrSessionPhase.connected) {
      return null;
    }
    final current = _library;
    if (current != null &&
        identical(_libraryLink, link) &&
        current.serial == serial) {
      return current;
    }
    _libraryLink = link;
    return _library = newCameraLibrary(
      http,
      serial: serial,
      props: () => _session.props,
      // Read when a view-model listens; a later link's socket must not
      // reach this library.
      changes: () => identical(_session.changes, link) ? link : null,
      // A request on a link that has gone failed with it; only the current
      // link is probed.
      checkWifi: () async =>
          identical(_session.changes, link) && await _session.checkWifi(),
      event: _environment.event,
    );
  }

  /// Remote shooting over Bluetooth: readouts, shutter, self-timer and
  /// drive. One for the whole session.
  CameraRemote get remote => _remote ??= createCameraRemote(
    _session,
    _environment,
    onModeChanged: () => _liveView?.modeChanged(),
  );

  /// The camera's Image Control Custom slots over Bluetooth. One for the
  /// whole session.
  CameraLooks get looks =>
      _looks ??= createCameraLooks(_session, _environment, body: () => body);

  /// Live view over the camera's Wi-Fi, run between its `start` and
  /// `stop`. One for the whole session; it stops when the session closes.
  CameraLiveView get liveView =>
      _liveView ??= createCameraLiveView(_session, _environment);
}

/// The camera layer's Wi-Fi control: asks [WifiConsent] first and handles
/// Android's approval list coming back for an approved camera (see
/// [WifiConsent]).
final class _ConsentWifi implements WifiNetworkControl {
  new(this._inner, {required this.approvalShown, required this.consent});

  final WifiNetworkControl _inner;
  final Stream<void> approvalShown;
  final WifiConsent consent;
  bool _agreed = false;

  /// Counts cancellations ([leave], [cancelJoins]): an answer to a
  /// question asked before the latest one belongs to a cancelled join.
  int _cancels = 0;

  static const _cancelled = WifiJoinException(
    'cancelled',
    "the join was stopped while waiting for the user's answer",
  );

  /// Ends the joins in progress: a consent answer that arrives afterwards
  /// starts no join.
  void cancelJoins() => _cancels++;

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    final cancels = _cancels;
    if (!_agreed) {
      final agreed = await consent.ask(ssid);
      if (_cancels != cancels) throw _cancelled;
      if (!agreed) {
        throw const WifiJoinDeclined("not joining the camera's Wi-Fi now");
      }
      _agreed = true;
    }
    while (true) {
      final wasApproved = consent.cameraApproved();
      var shown = false;
      final sub = approvalShown.listen((_) => shown = true);
      try {
        await _inner.join(
          ssid: ssid,
          passphrase: passphrase,
          security: security,
          timeout: timeout,
          approved: wasApproved,
        );
        break;
      } catch (e) {
        // Backing out of Android's list, or leaving it open past the join
        // window. Leaving during the join (Disconnect, a newer join) is
        // not an answer to the list.
        final listOutcome = e is WifiJoinDeclined || e is TimeoutException;
        if (!shown || !wasApproved || !listOutcome) rethrow;
        final again = await consent.askAgain(ssid);
        if (_cancels != cancels) throw _cancelled;
        if (!again) {
          throw const WifiJoinDeclined("not joining the camera's Wi-Fi now");
        }
      } finally {
        await sub.cancel();
      }
    }
    await consent.joined();
  }

  @override
  Future<String?> currentSsid() => _inner.currentSsid();

  @override
  Future<void> leave() {
    cancelJoins();
    return _inner.leave();
  }

  @override
  Stream<void> get lost => _inner.lost;
}
