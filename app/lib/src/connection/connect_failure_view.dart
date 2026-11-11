import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/pairing/pairing_flow.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// Small pill buttons of the Cameras card, its rows and the camera's
/// pages (mock `.btn.sm`).
const _smallSize = Size(0, 34);
const _smallPadding = EdgeInsets.symmetric(horizontal: 14);
const _smallText = TextStyle(
  fontFamily: GrFonts.ui,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);
final ButtonStyle smallFilledStyle = FilledButton.styleFrom(
  minimumSize: _smallSize,
  padding: _smallPadding,
  textStyle: _smallText,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
final ButtonStyle smallOutlinedStyle = OutlinedButton.styleFrom(
  minimumSize: _smallSize,
  padding: _smallPadding,
  textStyle: _smallText,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// What went wrong, in a line: the title of [ConnectFailureView], and what
/// the camera card's chip says.
String connectFailureTitle(
  AppLocalizations l10n,
  ConnectFailure failure,
  String cameraName,
) => switch (failure.kind) {
  ConnectFailureKind.bluetoothOff => l10n.connectionFailureBluetoothOffTitle,
  ConnectFailureKind.bluetoothDenied =>
    l10n.connectionFailureBluetoothDeniedTitle,
  ConnectFailureKind.unreachable => l10n.connectionFailureUnreachableTitle(
    cameraName,
  ),
  ConnectFailureKind.needsPairing => l10n.connectionFailureNeedsPairingTitle(
    cameraName,
  ),
  ConnectFailureKind.wifi => l10n.connectionFailureWifiTitle(cameraName),
  ConnectFailureKind.wifiDeclined => l10n.connectionFailureWifiDeclinedTitle(
    cameraName,
  ),
  ConnectFailureKind.wifiVpn => l10n.connectionFailureWifiVpnTitle(cameraName),
  ConnectFailureKind.cameraOff => l10n.connectionFailureCameraOffTitle(
    cameraName,
  ),
};

/// Why connecting failed, with the checks that fix it (mock
/// `b-home-fail`), on the camera sheet and on the pages that need the
/// camera's Wi-Fi. It stays until Try again (Turn on for a camera that
/// turned off) or another camera is chosen; pairing is never retried by
/// itself.
class ConnectFailureView extends StatelessWidget {
  const new({
    required this.camera,
    required this.failure,
    required this.connection,
    super.key,
    this.onPairAgain,
  });

  final SavedCamera camera;
  final ConnectFailure failure;
  final ConnectionController connection;

  /// Opens pairing in place of [PairingFlow.push]: the camera sheet closes
  /// itself first.
  final VoidCallback? onPairAgain;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final kind = failure.kind;
    final title = connectFailureTitle(l10n, failure, camera.name);
    final body = switch (kind) {
      ConnectFailureKind.bluetoothOff => l10n.connectionFailureBluetoothOffBody,
      ConnectFailureKind.bluetoothDenied =>
        l10n.connectionFailureBluetoothDeniedBody,
      ConnectFailureKind.unreachable => l10n.connectionFailureUnreachableBody,
      ConnectFailureKind.needsPairing => l10n.connectionFailureNeedsPairingBody,
      ConnectFailureKind.wifi => l10n.connectionFailureWifiBody,
      ConnectFailureKind.wifiDeclined => l10n.connectionFailureWifiDeclinedBody,
      ConnectFailureKind.wifiVpn => l10n.connectionFailureWifiVpnBody,
      ConnectFailureKind.cameraOff => l10n.connectionFailureCameraOffBody,
    };
    final pairAgain = onPairAgain ?? () => unawaited(PairingFlow.push(context));
    final checks = switch (kind) {
      ConnectFailureKind.unreachable => [
        GroupRow(
          icon: Icons.battery_std_rounded,
          title: l10n.connectionFailureCheckBattery,
        ),
        GroupRow(
          icon: Icons.bluetooth_rounded,
          title: l10n.connectionFailureCheckActionMode,
          subtitle: l10n.connectionFailureCheckActionModePath,
        ),
        GroupRow(
          icon: Icons.info_outline_rounded,
          title: l10n.connectionFailureCheckForgotten,
          subtitle: l10n.connectionFailureCheckForgottenHint,
          trailing: TrailingFit(
            child: TextButton(
              key: const Key('connect-pair-again'),
              onPressed: pairAgain,
              child: Text(l10n.connectionFailurePairAgain),
            ),
          ),
        ),
      ],
      ConnectFailureKind.needsPairing => [
        GroupRow(
          leading: const NumberTile(1),
          title: l10n.connectionFailurePairStep1,
        ),
        GroupRow(
          leading: const NumberTile(2),
          title: l10n.connectionFailurePairStep2,
        ),
        GroupRow(
          leading: const NumberTile(3),
          title: l10n.connectionFailurePairStep3,
        ),
      ],
      ConnectFailureKind.wifi => [
        GroupRow(
          icon: Icons.wifi_rounded,
          title: l10n.connectionFailureCheckStayClose,
        ),
        GroupRow(
          icon: Icons.check_circle_outline_rounded,
          title: l10n.connectionFailureCheckAllowJoin,
        ),
      ],
      ConnectFailureKind.wifiVpn => [
        GroupRow(
          icon: Icons.vpn_lock_rounded,
          title: l10n.connectionFailureCheckVpnExclude,
        ),
        GroupRow(
          icon: Icons.vpn_key_off_rounded,
          title: l10n.connectionFailureCheckVpnOff,
        ),
      ],
      ConnectFailureKind.bluetoothOff ||
      ConnectFailureKind.bluetoothDenied ||
      ConnectFailureKind.wifiDeclined ||
      ConnectFailureKind.cameraOff => const <Widget>[],
    };
    final detail = _detail(l10n);
    final retryLabel = Text(switch (kind) {
      ConnectFailureKind.wifiDeclined => l10n.connectionFailureJoinWifi,
      ConnectFailureKind.cameraOff => l10n.connectionFailureTurnOn,
      _ => l10n.connectionFailureTryAgain,
    });
    // Wi-Fi failures keep the Bluetooth link; only Wi-Fi is tried again,
    // which turns a camera that is off on first.
    void retry() => unawaited(
      failure.step == ConnectStep.wifi
          ? connection.joinWifi()
          : connection.connect(),
    );
    return Column(
      key: Key('connect-failed-${kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.t1,
          ),
        ),
        const SizedBox(height: 4),
        Text(body, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.t2)),
        if (checks.isNotEmpty) ...[
          const SizedBox(height: 12),
          GroupBox(margin: EdgeInsets.zero, color: c.s2, children: checks),
        ],
        if (detail != null) ...[
          const SizedBox(height: 10),
          Text(
            detail,
            style: GrFonts.monoStyle(context, size: 11, color: c.t3),
          ),
        ],
        const SizedBox(height: 14),
        if (kind == ConnectFailureKind.needsPairing) ...[
          FilledButton(
            key: const Key('connect-pair-again'),
            style: smallFilledStyle,
            onPressed: pairAgain,
            child: Text(l10n.connectionFailurePairAgain),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('connect-retry'),
            style: smallOutlinedStyle,
            onPressed: retry,
            child: retryLabel,
          ),
        ] else
          FilledButton(
            key: const Key('connect-retry'),
            style: smallFilledStyle,
            onPressed: retry,
            child: retryLabel,
          ),
      ],
    );
  }

  /// The small technical line under the checks: the link that was lost,
  /// what the connection reported, or the phone's Bluetooth state. A
  /// declined join needs none.
  String? _detail(AppLocalizations l10n) {
    if (failure.kind == ConnectFailureKind.wifiDeclined) return null;
    if (failure.loss case final loss?) {
      return switch (loss) {
        ConnectLoss.bluetooth => l10n.connectionFailureDetailLostBluetooth,
        ConnectLoss.camera => l10n.connectionFailureDetailLostCamera,
        ConnectLoss.wifi => l10n.connectionFailureDetailLostWifi,
      };
    }
    if (failure.detail case final detail?) {
      return l10n.connectionFailureDetailError(detail);
    }
    return switch (failure.kind) {
      ConnectFailureKind.bluetoothOff =>
        l10n.connectionFailureDetailBluetoothOff,
      ConnectFailureKind.bluetoothDenied =>
        l10n.connectionFailureDetailBluetoothDenied,
      _ => null,
    };
  }
}
