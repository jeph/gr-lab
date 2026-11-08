import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../connection/camera_sheet.dart';
import '../theme/tokens.dart';
import '../widgets/group.dart';
import 'pairing_widgets.dart';

/// Last pairing page (mock `b-pair-done`). The camera is already saved and
/// connecting underneath; this page names it and asks how to connect.
/// Done returns to the Library.
class PairingDoneScreen extends StatelessWidget {
  const PairingDoneScreen({super.key, required this.serial});

  final String serial;

  static Route<void> route(String serial) => MaterialPageRoute<void>(
    builder: (_) => PairingDoneScreen(serial: serial),
  );

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    final c = GrColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([models.cameras, models.settings]),
          builder: (context, _) {
            final camera = models.cameras.cameras
                .where((c) => c.serial == serial)
                .firstOrNull;
            final name = camera?.name ?? 'Camera';
            final firmware = camera?.paired.firmwareRevision;
            return Column(
              key: const Key('pairing-done'),
              children: [
                const PairingTopBar(step: 4),
                Expanded(
                  child: ListView(
                    children: [
                      const SizedBox(height: 34),
                      Center(
                        child: StatusBadge(
                          icon: Icons.check_rounded,
                          color: c.ok,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
                        child: Text(
                          '$name is paired',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                            color: c.t1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          'No. $serial',
                          if (firmware != null) 'fw $firmware',
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        style: GrFonts.monoStyle(context),
                      ),
                      const SectionLabel('Name'),
                      GroupBox(
                        children: [
                          GroupRow(
                            key: const Key('pairing-done-name'),
                            icon: Icons.photo_camera_outlined,
                            title: 'Camera name',
                            trailing: TrailingFit.value(context, name),
                            chevron: true,
                            onTap: camera == null
                                ? null
                                : () => showRenameCameraDialog(context, camera),
                          ),
                        ],
                      ),
                      const SectionLabel('When connecting'),
                      GroupBox(
                        children: [
                          GroupRow(
                            icon: Icons.power_settings_new_rounded,
                            title: 'Turn the camera on',
                            subtitle: 'Switch it on over Bluetooth when off',
                            trailing: Switch(
                              key: const Key('pairing-done-power-on'),
                              value: models.settings.powerOnWhenConnecting,
                              onChanged: (v) =>
                                  models.settings.powerOnWhenConnecting = v,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                BottomAction(
                  children: [
                    FilledButton(
                      key: const Key('pairing-done-button'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
