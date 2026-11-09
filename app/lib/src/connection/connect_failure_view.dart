import 'dart:async';

import 'package:flutter/material.dart';
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

/// Why connecting failed, with the checks that fix it (mock
/// `b-home-fail`). It stays until Try again or another camera is chosen;
/// pairing is never retried by itself.
class ConnectFailureView extends StatelessWidget {
  const new({
    required this.camera,
    required this.failure,
    required this.connection,
    super.key,
  });

  final SavedCamera camera;
  final ConnectFailure failure;
  final ConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final kind = failure.kind;
    final name = camera.name;
    final (title, body) = switch (kind) {
      ConnectFailureKind.bluetoothOff => (
        'Bluetooth is off',
        'Turn on Bluetooth on this phone, then try again.',
      ),
      ConnectFailureKind.bluetoothDenied => (
        "GR Lab can't use Bluetooth",
        'Allow Bluetooth (on Android: Nearby devices) for GR Lab in the '
            "phone's settings, then try again.",
      ),
      ConnectFailureKind.unreachable => (
        "Can't reach $name",
        "The camera didn't answer over Bluetooth.",
      ),
      ConnectFailureKind.needsPairing => (
        'Pair $name again',
        "The camera no longer accepts this phone's pairing, so trying again "
            "won't help. To pair again:",
      ),
      ConnectFailureKind.wifi => (
        "Couldn't join $name's Wi-Fi",
        "Bluetooth works, but the phone couldn't join or keep the camera's "
            'Wi-Fi.',
      ),
      ConnectFailureKind.wifiDeclined => (
        "Not on $name's Wi-Fi",
        "Photos come over the camera's own Wi-Fi. Join it to browse and "
            'download them.',
      ),
    };
    void pairAgain() => unawaited(PairingFlow.push(context));
    final checks = switch (kind) {
      ConnectFailureKind.unreachable => [
        const GroupRow(
          icon: Icons.battery_std_rounded,
          title: "The camera is close and its battery isn't empty",
        ),
        const GroupRow(
          icon: Icons.bluetooth_rounded,
          title: 'Action Mode is On',
          subtitle: 'MENU → E6 → Wireless Communication',
        ),
        GroupRow(
          icon: Icons.info_outline_rounded,
          title: 'Camera forgot this phone?',
          subtitle: "If its Paired Devices list doesn't show this phone",
          trailing: TrailingFit(
            child: TextButton(
              key: const Key('connect-pair-again'),
              onPressed: pairAgain,
              child: const Text('Pair again'),
            ),
          ),
        ),
      ],
      ConnectFailureKind.needsPairing => const [
        GroupRow(
          leading: NumberTile(1),
          title: "Delete this phone from the camera's Paired Devices",
        ),
        GroupRow(
          leading: NumberTile(2),
          title: "Delete the camera from this phone's Bluetooth settings",
        ),
        GroupRow(
          leading: NumberTile(3),
          title: 'Open Execute Pairing on the camera and pair',
        ),
      ],
      ConnectFailureKind.wifi => const [
        GroupRow(
          icon: Icons.wifi_rounded,
          title: 'The phone stays close to the camera',
        ),
        GroupRow(
          icon: Icons.check_circle_outline_rounded,
          title: "If the phone asks to join the camera's network, allow it",
        ),
      ],
      ConnectFailureKind.bluetoothOff ||
      ConnectFailureKind.bluetoothDenied ||
      ConnectFailureKind.wifiDeclined => const <Widget>[],
    };
    final retryLabel = Text(
      kind == ConnectFailureKind.wifiDeclined ? 'Join Wi-Fi' : 'Try again',
    );
    // Wi-Fi failures keep the Bluetooth link; only Wi-Fi is tried again,
    // from the camera's pages when they are open.
    final wifiStep = failure.step == ConnectStep.wifi;
    void retry() => unawaited(
      !wifiStep
          ? connection.connect()
          : connection.tab == null
          ? connection.openCamera(CameraTab.library)
          : connection.joinWifi(),
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
        if (kind != ConnectFailureKind.wifiDeclined) ...[
          const SizedBox(height: 10),
          Text(
            failure.message,
            style: GrFonts.monoStyle(context, size: 11, color: c.t3),
          ),
        ],
        const SizedBox(height: 14),
        if (kind == ConnectFailureKind.needsPairing) ...[
          FilledButton(
            key: const Key('connect-pair-again'),
            style: smallFilledStyle,
            onPressed: pairAgain,
            child: const Text('Pair again'),
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
}
