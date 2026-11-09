import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/connection/camera_sheet.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// Last pairing page (mock `b-pair-done`). The camera is already saved and
/// connecting underneath; this page names it and asks how to connect.
/// Done returns to the Library.
class PairingDoneScreen extends StatelessWidget {
  const new({required this.serial, super.key});

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
            final l10n = context.l10n;
            // Saving the camera finishes just after this page opens.
            final name = camera?.name;
            final firmware = camera?.firmware;
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
                          name == null
                              ? l10n.pairingDoneTitleUnsaved
                              : l10n.pairingDoneTitle(name),
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
                        firmware == null
                            ? l10n.pairingSerialNumber(serial)
                            : l10n.pairingDoneSerialAndFirmware(
                                serial,
                                firmware,
                              ),
                        textAlign: TextAlign.center,
                        style: GrFonts.monoStyle(context),
                      ),
                      SectionLabel(l10n.pairingDoneNameSection),
                      GroupBox(
                        children: [
                          GroupRow(
                            key: const Key('pairing-done-name'),
                            icon: Icons.photo_camera_outlined,
                            title: l10n.pairingDoneCameraName,
                            trailing: TrailingFit.value(
                              context,
                              name ?? l10n.pairingDoneUnsavedName,
                            ),
                            chevron: true,
                            onTap: camera == null
                                ? null
                                : () => showRenameCameraDialog(context, camera),
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
                      child: Text(l10n.pairingDone),
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
