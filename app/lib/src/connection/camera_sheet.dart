import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/cameras/camera_drawing.dart';
import 'package:grphoto/src/cameras/camera_identity.dart';
import 'package:grphoto/src/connection/camera_pill.dart';
import 'package:grphoto/src/connection/connect_failure_view.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/connection/storage_counts.dart';
import 'package:grphoto/src/data/cameras.dart';
import 'package:grphoto/src/geotag/geotag_section.dart';
import 'package:grphoto/src/pairing/pairing_flow.dart';
import 'package:grphoto/src/pairing/pairing_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/group.dart';

/// Opens the camera sheet over the current screen.
Future<void> showCameraSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CameraSheet(),
    );

/// The current camera's connection, from the camera card's chip and the
/// camera pill (mock `connection-controls.html`, direction A): why the
/// last attempt failed, battery and storage while on the camera's Wi-Fi,
/// and a row each for Bluetooth and Wi-Fi that says what the link is doing
/// and connects or disconnects it. Disconnecting Bluetooth ends the
/// session, Wi-Fi included; disconnecting Wi-Fi keeps Bluetooth. Either
/// one returns to the Cameras screen from the camera's pages. Under them,
/// for a camera that can be sent a location, its geotagging and clock
/// ([GeotagSection]).
class CameraSheet extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([models.cameras, models.connection]),
      builder: (context, _) {
        final camera = models.cameras.current;
        if (camera == null) return const SizedBox(height: 120);
        final connection = models.connection;
        final l10n = context.l10n;
        // Bluetooth failures end the link; Wi-Fi ones are kept next to it.
        final failure = switch (connection.status) {
          ConnectionStatus.failed ||
          ConnectionStatus.bluetooth => connection.failure,
          _ => null,
        };
        return SingleChildScrollView(
          key: const Key('camera-sheet'),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(camera: camera),
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ConnectFailureView(
                    camera: camera,
                    failure: failure,
                    connection: connection,
                    // Pairing takes the sheet's place.
                    onPairAgain: () {
                      Navigator.of(context).pop();
                      unawaited(PairingFlow.push(context));
                    },
                  ),
                ),
              if (connection.status == ConnectionStatus.connected)
                _StatusTiles(status: connection.cameraStatus),
              SectionLabel(l10n.connectionSheetLink),
              GroupBox(
                children: [
                  _bluetoothRow(l10n, connection),
                  _wifiRow(l10n, connection),
                ],
              ),
              GeotagSection(camera: camera),
            ],
          ),
        );
      },
    );
  }

  static _LinkRow _bluetoothRow(
    AppLocalizations l10n,
    ConnectionController connection,
  ) {
    const name = 'bluetooth';
    const icon = Icons.bluetooth_rounded;
    final title = l10n.connectionSheetLinkBluetooth;
    void disconnect() => unawaited(connection.disconnect());
    switch (connection.status) {
      case ConnectionStatus.offline || ConnectionStatus.failed:
        return _LinkRow(
          name: name,
          icon: icon,
          title: title,
          state: l10n.connectionPillNotConnected,
          action: _LinkAction.connect,
          onPressed: () => unawaited(connection.connect()),
        );
      case ConnectionStatus.connecting
          when connection.step == ConnectStep.bluetooth:
        return _LinkRow(
          name: name,
          icon: icon,
          title: title,
          state: l10n.connectionPillConnecting,
          action: _LinkAction.cancel,
          onPressed: disconnect,
        );
      case ConnectionStatus.connecting ||
          ConnectionStatus.bluetooth ||
          ConnectionStatus.connected:
        return _LinkRow(
          name: name,
          icon: icon,
          title: title,
          // The camera drops the link when it is woken or turned off; the
          // session links it again, except that it lets go of a camera
          // that is off until the camera says it is on.
          state: connection.cameraSession?.bleLinked ?? false
              ? l10n.connectionSheetConnected
              : connection.parked
              ? l10n.connectionPillCameraOff
              : !connection.bleLinking
              ? l10n.connectionPillNotConnected
              : switch (connection.powerChange) {
                  CameraPowerChange.on => l10n.connectionPillTurningOn,
                  CameraPowerChange.off => l10n.connectionPillTurningOff,
                  null => l10n.connectionPillReconnecting,
                },
          action: _LinkAction.disconnect,
          onPressed: disconnect,
        );
    }
  }

  static _LinkRow _wifiRow(
    AppLocalizations l10n,
    ConnectionController connection,
  ) {
    const name = 'wifi';
    const icon = Icons.wifi_rounded;
    final title = l10n.connectionSheetLinkWifi;
    void disconnect() => unawaited(connection.disconnectWifi());
    final reconnecting = connection.reconnecting;
    switch (connection.status) {
      case ConnectionStatus.connected:
        return _LinkRow(
          name: name,
          icon: icon,
          title: title,
          state: !reconnecting
              ? l10n.connectionSheetConnected
              : connection.cameraOff
              ? l10n.connectionPillCameraOff
              : l10n.connectionPillReconnecting,
          action: _LinkAction.disconnect,
          onPressed: disconnect,
        );
      case ConnectionStatus.connecting when connection.step == ConnectStep.wifi:
        return _LinkRow(
          name: name,
          icon: icon,
          title: title,
          state: reconnecting
              ? l10n.connectionPillReconnecting
              : l10n.connectionPillConnecting,
          action: _LinkAction.cancel,
          onPressed: disconnect,
        );
      case ConnectionStatus.offline ||
          ConnectionStatus.failed ||
          ConnectionStatus.connecting ||
          ConnectionStatus.bluetooth:
        return _LinkRow(
          name: name,
          icon: icon,
          title: title,
          state: l10n.connectionPillNotConnected,
          action: _LinkAction.connect,
          // Links Bluetooth first when needed.
          onPressed: () => unawaited(connection.joinWifi()),
        );
    }
  }
}

/// What a [_LinkRow]'s button does.
enum _LinkAction {
  connect,

  /// Stops connecting.
  cancel,
  disconnect,
}

/// One link of the connection, Bluetooth or Wi-Fi: what it is doing and a
/// button to connect it, stop connecting or disconnect it.
class _LinkRow extends StatelessWidget {
  const new({
    required this.name,
    required this.icon,
    required this.title,
    required this.state,
    required this.action,
    required this.onPressed,
  });

  /// `bluetooth` or `wifi`, for the row's keys.
  final String name;
  final IconData icon;
  final String title;
  final String state;
  final _LinkAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GroupRow(
      key: Key('camera-sheet-$name'),
      icon: icon,
      title: title,
      subtitle: state,
      trailing: TrailingFit(
        child: OutlinedButton(
          key: Key('camera-sheet-$name-${action.name}'),
          style: smallOutlinedStyle,
          onPressed: onPressed,
          child: Text(switch (action) {
            _LinkAction.connect => l10n.camerasConnect,
            _LinkAction.cancel => l10n.camerasCancel,
            _LinkAction.disconnect => l10n.connectionSheetDisconnect,
          }),
        ),
      ),
    );
  }
}

/// The camera's battery and the photos that still fit on its storages,
/// as it reports them over its Wi-Fi.
class _StatusTiles extends StatelessWidget {
  const new({required this.status});

  final CameraStatus? status;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final battery = status?.battery;
    final storages = status?.storages ?? const <CameraStorage>[];
    return Padding(
      key: const Key('camera-sheet-connected'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Tile(
              label: l10n.connectionSheetBattery,
              value: _Fit(
                child: Text(
                  battery == null ? '—' : formatBattery(context, battery),
                  key: const Key('camera-sheet-battery'),
                  style: GrFonts.monoStyle(context, size: 20, color: c.t1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Tile(
              label: l10n.connectionSheetStorage,
              value: StorageCounts(
                key: const Key('camera-sheet-storage'),
                storages: storages,
                lineKeyPrefix: 'camera-sheet-storage',
                soloSize: 20,
              ),
              caption: storages.any((s) => s.present)
                  ? l10n.connectionSheetShotsLeft
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The camera's name and identity beside a small drawing of its model, as
/// the rows of the Cameras screen's other cameras have it.
class _Header extends StatelessWidget {
  const new({required this.camera});

  final SavedCamera camera;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: ExcludeSemantics(
              child: CameraDrawing(
                key: const Key('camera-sheet-drawing'),
                body: camera.body,
                strokeWidth: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  camera.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                    color: c.t1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  camera.identityLine(context.l10n),
                  style: GrFonts.monoStyle(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the status tiles (battery, storage).
class _Tile extends StatelessWidget {
  const new({required this.label, required this.value, this.caption});

  final String label;
  final Widget value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(GrRadii.lg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.upperCase(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: context.l10n.capitalSpacing(.5),
              color: c.t2,
            ),
          ),
          const SizedBox(height: 6),
          value,
          if (caption case final caption?)
            Text(caption, style: TextStyle(fontSize: 10.5, color: c.t3)),
        ],
      ),
    );
  }
}

/// Shrinks one line of tile content to the tile's width instead of
/// wrapping or overflowing it at large text sizes.
class _Fit extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );
}
