import 'dart:async';

import 'package:gr_camera/src/environment.dart';
import 'package:gr_camera/src/library/camera_library.dart';
import 'package:gr_camera/src/shoot/live_view.dart';
import 'package:gr_camera/src/shoot/remote.dart';
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

/// One connection to one paired camera, in two stages: Bluetooth
/// ([connectBluetooth]) and the camera's Wi-Fi ([startWifi], [stopWifi]).
/// The session reconnects Bluetooth and recovers a lost Wi-Fi link by
/// itself, reporting each step in [events] (also traced on
/// [TraceChannel.session]).
final class CameraSession {
  /// A session with the camera reached through [camera], asking [consent]
  /// before joining its Wi-Fi.
  new(GrCameraEnvironment camera, {required WifiConsent consent})
    : _environment = camera,
      _session = GrSession(
        transport: camera.ble,
        wifi: _ConsentWifi(
          camera.wifi,
          approvalShown: camera.wifiApprovalShown,
          consent: consent,
        ),
        host: camera.cameraHost,
        options: camera.sessionOptions,
        trace: camera.trace,
        httpFactory: camera.httpFactory,
      );

  final GrSession _session;
  final GrCameraEnvironment _environment;

  /// The serial [connectBluetooth] was asked for.
  String? _serial;
  CameraLibrary? _library;

  /// The change socket of the link [_library] belongs to.
  GrChangesSocket? _libraryLink;
  CameraRemote? _remote;
  CameraLiveView? _liveView;

  /// Every step of the session, such as `ble.lost`, `ble.restored`,
  /// `ble.gaveUp`, `ble.needsPairing`, `wifi.lost`, `recovery.done` and
  /// `recovery.gaveUp` (fields `noBle`, `declined`).
  Stream<GrSessionEvent> get events => _session.events;

  /// Current stage, from scanning through the Bluetooth link and Wi-Fi
  /// join to `connected`, `recovering`, `lost` or `closed`.
  GrSessionPhase get phase => _session.phase;

  /// The camera is off (it answered over Bluetooth in its BT-only state),
  /// or reported turning off.
  bool get cameraOff => _session.cameraOff;

  /// `/v1/props` from the last identity check over Wi-Fi.
  GrProps? get props => _session.props;

  /// The camera network's name, once the session has read it.
  String? get ssid => _session.credentials?.ssid;

  /// Links the camera over Bluetooth: directly to [deviceId], which pairing
  /// recorded, matching [serial]. A camera that is off is not woken; it
  /// drops the link soon after, and [startWifi] links again. Throws
  /// [GrSessionException]; check [GrSessionException.needsPairing].
  Future<void> connectBluetooth({required String deviceId, String? serial}) {
    _serial = serial;
    return _session.connectBluetooth(deviceId: deviceId, serial: serial);
  }

  /// Joins the camera's Wi-Fi, turning the camera on first when it is off,
  /// and verifies it is the paired camera. Throws [GrSessionException];
  /// check [GrSessionException.wifiDeclined].
  Future<void> startWifi() => _session.startWifi();

  /// Leaves the camera's Wi-Fi, or stops joining it, keeping Bluetooth.
  /// With [powerOffIfWoken], a camera this session turned on is turned off
  /// again.
  Future<void> stopWifi({bool powerOffIfWoken = false}) =>
      _session.stopWifi(powerOffIfWoken: powerOffIfWoken);

  /// Turns the camera off if this session turned it on.
  Future<void> powerOffIfWoken() => _session.powerOffIfWoken();

  /// A request over Wi-Fi failed: asks the camera once whether its Wi-Fi
  /// still works; when it does not, the session counts the link as lost and
  /// recovers it. True while the camera answers.
  Future<bool> checkWifi() => _session.checkWifi();

  /// Ends the session: Wi-Fi, Bluetooth and every recovery. With
  /// [powerOffIfWoken], a camera this session turned on (including one
  /// whose wake is still in flight) is turned off again.
  Future<void> close({bool powerOffIfWoken = false}) {
    _remote?.close();
    _liveView?.close();
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
    final serial = _serial ?? _session.props?.serialNo;
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
      props: _session.props,
      // Read when a view-model listens; a later link's socket must not
      // reach this library.
      changes: () => identical(_session.changes, link) ? link.events : null,
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

  @override
  Future<void> join({
    required String ssid,
    required String passphrase,
    required WifiSecurity security,
    required Duration timeout,
    bool approved = false,
  }) async {
    if (!_agreed) {
      if (!await consent.ask(ssid)) {
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
        if (!await consent.askAgain(ssid)) {
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
  Future<void> leave() => _inner.leave();

  @override
  Stream<void> get lost => _inner.lost;
}
