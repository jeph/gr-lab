import 'package:flutter/material.dart';

import '../pairing/pairing_widgets.dart';
import 'connection_controller.dart';

/// The steps of the running connection attempt (mock `b-home-connecting`),
/// shown on the Cameras card and in the camera sheet while reconnecting.
class ConnectSteps extends StatelessWidget {
  const ConnectSteps({super.key, required this.connection});

  final ConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final visible = connection.visibleSteps;
    final current = connection.step;
    final at = current == null ? -1 : visible.indexOf(current);
    GrStepState state(int i) => i < at
        ? GrStepState.done
        : i == at
        ? GrStepState.now
        : GrStepState.todo;
    return GrStepList(
      steps: [
        for (var i = 0; i < visible.length; i++)
          _step(visible[i], state(i), connection.ssid),
      ],
    );
  }

  static GrStep _step(ConnectStep step, GrStepState state, String? ssid) =>
      switch (step) {
        ConnectStep.finding => GrStep(
          state == GrStepState.done
              ? 'Found the camera nearby'
              : 'Looking for the camera',
          state,
        ),
        ConnectStep.waking => GrStep(
          'Waking the camera',
          state,
          detail: state == GrStepState.now
              ? 'It was off. The first link drops while it starts up; the '
                    'app reconnects'
              : null,
        ),
        ConnectStep.bluetooth => GrStep(
          state == GrStepState.done
              ? 'Connected over Bluetooth'
              : 'Connecting over Bluetooth',
          state,
        ),
        ConnectStep.wifiOn => GrStep("Turning on the camera's Wi-Fi", state),
        ConnectStep.joining => GrStep(
          ssid == null ? "Joining the camera's Wi-Fi" : 'Joining $ssid',
          state,
          detail: state == GrStepState.now ? 'This can take a while' : null,
        ),
      };
}
