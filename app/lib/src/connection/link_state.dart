import 'package:flutter/foundation.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/connection/connection_controller.dart';

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
      ConnectionStatus.connecting || ConnectionStatus.bluetooth
          when connection.reconnecting =>
        LinkLabel.reconnecting,
      ConnectionStatus.connecting =>
        connection.step == ConnectStep.wifi
            ? LinkLabel.connectingWifi
            : LinkLabel.connecting,
      ConnectionStatus.bluetooth => LinkLabel.bluetooth,
      // Switched off with the Library open: red while it is woken and
      // its Wi-Fi joined again.
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

  LinkKind get kind => switch (label) {
    LinkLabel.offline => LinkKind.offline,
    LinkLabel.connecting || LinkLabel.connectingWifi => LinkKind.connecting,
    LinkLabel.bluetooth || LinkLabel.wifi => LinkKind.connected,
    LinkLabel.reconnecting => LinkKind.reconnecting,
    LinkLabel.notConnected || LinkLabel.cameraOff => LinkKind.failed,
  };
}

enum LinkKind { offline, connecting, connected, reconnecting, failed }

/// The link state the pill and the sheet name.
enum LinkLabel {
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
  cameraOff;

  String text(AppLocalizations l10n) => switch (this) {
    offline => l10n.connectionPillOffline,
    notConnected => l10n.connectionPillNotConnected,
    connecting => l10n.connectionPillConnecting,
    connectingWifi => l10n.connectionPillConnectingWifi,
    reconnecting => l10n.connectionPillReconnecting,
    bluetooth => l10n.connectionPillBluetooth,
    wifi => l10n.connectionPillWifi,
    cameraOff => l10n.connectionPillCameraOff,
  };
}
