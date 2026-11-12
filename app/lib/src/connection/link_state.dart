import 'package:flutter/foundation.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/connection_controller.dart';

/// What the camera pill and the camera sheet say about the link, derived
/// from the controller in this one place.
@immutable
final class LinkState {
  const new _(this.label, {required this.bluetooth});

  factory of(ConnectionController connection) {
    final bluetooth = connection.bleLinked;
    final label = switch (connection.status) {
      ConnectionStatus.offline => LinkLabel.offline,
      ConnectionStatus.failed => LinkLabel.notConnected,
      // The camera drops the link as it turns off and as it turns on: no
      // loss, and not worded as one.
      ConnectionStatus.bluetooth || ConnectionStatus.connected
          when connection.powerChange != null =>
        connection.powerChange == CameraPowerChange.off
            ? LinkLabel.turningOff
            : LinkLabel.turningOn,
      // Turned off while its Wi-Fi was in use, and left off.
      ConnectionStatus.bluetooth
          when connection.failure?.kind == ConnectFailureKind.cameraOff =>
        LinkLabel.cameraOff,
      // Off, and let go of until it says it is on: no link, and none lost.
      ConnectionStatus.bluetooth when connection.parked => LinkLabel.offline,
      ConnectionStatus.connecting || ConnectionStatus.bluetooth
          when connection.reconnecting =>
        LinkLabel.reconnecting,
      ConnectionStatus.connecting =>
        connection.step == ConnectStep.wifi
            ? LinkLabel.connectingWifi
            : LinkLabel.connecting,
      ConnectionStatus.bluetooth => LinkLabel.bluetooth,
      // Turning off with its Wi-Fi in use: red from the camera's notice,
      // before the session has let the Wi-Fi go.
      ConnectionStatus.connected when connection.reconnecting =>
        connection.cameraOff ? LinkLabel.cameraOff : LinkLabel.reconnecting,
      ConnectionStatus.connected => LinkLabel.wifi,
    };
    return LinkState._(label, bluetooth: bluetooth);
  }

  final LinkLabel label;

  /// Bluetooth is linked now ([ConnectionController.bleLinked]); the
  /// camera's Wi-Fi carries on without it.
  final bool bluetooth;

  /// The camera is being turned on or off
  /// ([ConnectionController.powerChange]).
  bool get changingPower =>
      label == LinkLabel.turningOn || label == LinkLabel.turningOff;

  LinkKind get kind => switch (label) {
    LinkLabel.offline => LinkKind.offline,
    LinkLabel.connecting ||
    LinkLabel.connectingWifi ||
    LinkLabel.turningOn ||
    LinkLabel.turningOff => LinkKind.connecting,
    LinkLabel.bluetooth || LinkLabel.wifi => LinkKind.connected,
    LinkLabel.reconnecting => LinkKind.reconnecting,
    LinkLabel.notConnected || LinkLabel.cameraOff => LinkKind.failed,
  };
}

enum LinkKind { offline, connecting, connected, reconnecting, failed }

/// The link state the pill and the sheet name.
enum LinkLabel {
  /// No link: no session, or one that let go of a camera that is off
  /// ([ConnectionController.parked]).
  offline,

  /// Connecting failed.
  notConnected,

  /// Linking over Bluetooth.
  connecting,

  /// Joining the camera's Wi-Fi.
  connectingWifi,

  /// Getting a lost link back.
  reconnecting,

  /// Linked over Bluetooth only.
  bluetooth,

  /// On the camera's Wi-Fi.
  wifi,

  /// Switched off with the Library open, while it is turned back on.
  cameraOff,

  /// The camera is being turned on, until it is on and linked.
  turningOn,

  /// The camera is being turned off, until it is linked again in its off
  /// state.
  turningOff;

  String text(AppLocalizations l10n) => switch (this) {
    offline => l10n.connectionPillOffline,
    notConnected => l10n.connectionPillNotConnected,
    connecting => l10n.connectionPillConnecting,
    connectingWifi => l10n.connectionPillConnectingWifi,
    reconnecting => l10n.connectionPillReconnecting,
    bluetooth => l10n.connectionPillBluetooth,
    wifi => l10n.connectionPillWifi,
    cameraOff => l10n.connectionPillCameraOff,
    turningOn => l10n.connectionPillTurningOn,
    turningOff => l10n.connectionPillTurningOff,
  };
}
