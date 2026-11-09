import 'package:flutter/material.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';

/// Bluetooth, then Wi-Fi (mock `b-home-connecting`), on the Cameras card.
class ConnectSteps extends StatelessWidget {
  const new({required this.connection, super.key});

  final ConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final linked = switch (connection.status) {
      ConnectionStatus.bluetooth || ConnectionStatus.connected => true,
      ConnectionStatus.connecting => connection.step == ConnectStep.wifi,
      ConnectionStatus.offline || ConnectionStatus.failed => false,
    };
    final joining =
        connection.status == ConnectionStatus.connecting &&
        connection.step == ConnectStep.wifi;
    return GrStepList(
      steps: [
        GrStep(
          linked ? 'Connected via Bluetooth' : 'Connecting via Bluetooth',
          linked ? GrStepState.done : GrStepState.now,
        ),
        GrStep(
          'Connecting to Wi-Fi',
          joining
              ? GrStepState.now
              : connection.status == ConnectionStatus.connected
              ? GrStepState.done
              : GrStepState.todo,
        ),
      ],
    );
  }
}
