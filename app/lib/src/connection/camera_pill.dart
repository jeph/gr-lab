import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/connection/camera_sheet.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:intl/intl.dart';

/// Camera name, link state and battery at the top of the Library (mock
/// `.pill` in `b-library-*`, `b-connect`). Tapping opens the camera sheet.
class CameraPill extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([models.cameras, models.connection]),
      builder: (context, _) {
        final camera = models.cameras.current;
        if (camera == null) return const SizedBox.shrink();
        final c = GrColors.of(context);
        final link = PillLinkState.of(models.connection);
        return Semantics(
          button: true,
          label: context.l10n.connectionPillSemantics(
            camera.name,
            link.label.text(context.l10n),
          ),
          excludeSemantics: true,
          child: Material(
            key: const Key('camera-pill'),
            color: c.s2,
            shape: StadiumBorder(side: BorderSide(color: c.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => showCameraSheet(context),
              // Grows with large text instead of clipping it.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 34),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final dot = Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.s4,
                        ),
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: 13,
                          color: c.t1,
                        ),
                      );
                      final name = Text(
                        camera.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.t1,
                        ),
                      );
                      final meta = _Meta(link: link);
                      // Headers may give the pill unbounded width (a Row
                      // child), where Flexible is not allowed; there the
                      // name gets a fixed cap instead. When bounded, the
                      // state keeps its natural size up to half the pill
                      // (shrinking only beyond that) and the name ellipsizes
                      // into the rest.
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          dot,
                          const SizedBox(width: 8),
                          if (constraints.hasBoundedWidth) ...[
                            Flexible(child: name),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth / 2,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: meta,
                              ),
                            ),
                          ] else ...[
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: name,
                            ),
                            const SizedBox(width: 8),
                            meta,
                          ],
                        ],
                      );
                    },
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

/// What the pill says about the link, derived from the controller.
@immutable
final class PillLinkState {
  const new _(this.label, {this.battery});

  factory of(ConnectionController connection) => switch (connection.status) {
    ConnectionStatus.offline => const PillLinkState._(PillLinkLabel.offline),
    ConnectionStatus.failed => const PillLinkState._(
      PillLinkLabel.notConnected,
    ),
    ConnectionStatus.connecting when connection.reconnecting =>
      const PillLinkState._(PillLinkLabel.reconnecting),
    ConnectionStatus.connecting => PillLinkState._(
      connection.step == ConnectStep.wifi
          ? PillLinkLabel.connectingWifi
          : PillLinkLabel.connecting,
    ),
    ConnectionStatus.bluetooth => const PillLinkState._(
      PillLinkLabel.bluetooth,
    ),
    // Switched off with the Library open: red while it is woken and
    // its Wi-Fi joined again.
    ConnectionStatus.connected when connection.reconnecting =>
      connection.cameraOff
          ? const PillLinkState._(PillLinkLabel.cameraOff)
          : const PillLinkState._(PillLinkLabel.reconnecting),
    ConnectionStatus.connected => PillLinkState._(
      PillLinkLabel.wifi,
      battery: connection.props?.battery,
    ),
  };

  final PillLinkLabel label;

  PillLinkKind get kind => switch (label) {
    PillLinkLabel.offline => PillLinkKind.offline,
    PillLinkLabel.connecting ||
    PillLinkLabel.connectingWifi => PillLinkKind.connecting,
    PillLinkLabel.bluetooth || PillLinkLabel.wifi => PillLinkKind.connected,
    PillLinkLabel.reconnecting => PillLinkKind.reconnecting,
    PillLinkLabel.notConnected ||
    PillLinkLabel.cameraOff => PillLinkKind.failed,
  };

  /// Percent, when connected and the camera reported it.
  final int? battery;
}

enum PillLinkKind { offline, connecting, connected, reconnecting, failed }

/// The link state the pill names.
enum PillLinkLabel {
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

class _Meta extends StatelessWidget {
  const new({required this.link});

  final PillLinkState link;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final color = switch (link.kind) {
      PillLinkKind.offline => c.t3,
      PillLinkKind.connecting || PillLinkKind.reconnecting => c.accent,
      PillLinkKind.connected => c.t2,
      PillLinkKind.failed => c.danger,
    };
    final style = GrFonts.monoStyle(context, size: 11.5, color: color);
    final battery = link.battery;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (link.kind == PillLinkKind.connected) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.ok,
              boxShadow: [
                BoxShadow(color: c.ok.withValues(alpha: .2), spreadRadius: 3),
              ],
            ),
          ),
          const SizedBox(width: 9),
        ],
        Text(
          link.label.text(context.l10n),
          key: const Key('camera-pill-state'),
          style: style,
        ),
        if (battery != null) ...[
          const SizedBox(width: 7),
          Icon(batteryIcon(battery), size: 14, color: c.t2),
          const SizedBox(width: 2),
          Text(
            formatBattery(context, battery),
            key: const Key('camera-pill-battery'),
            style: style,
          ),
        ],
      ],
    );
  }
}

/// Material battery glyph for a 0–100 level.
IconData batteryIcon(int percent) {
  if (percent >= 95) return Icons.battery_full_rounded;
  const bars = [
    Icons.battery_0_bar_rounded,
    Icons.battery_1_bar_rounded,
    Icons.battery_2_bar_rounded,
    Icons.battery_3_bar_rounded,
    Icons.battery_4_bar_rounded,
    Icons.battery_5_bar_rounded,
    Icons.battery_6_bar_rounded,
  ];
  return bars[(percent.clamp(0, 94) * bars.length) ~/ 95];
}

/// A 0–100 battery level as a percentage for the current locale (`82%`).
String formatBattery(BuildContext context, int percent) =>
    NumberFormat.percentPattern(Localizations.localeOf(context).toString())
        .format(percent / 100);
