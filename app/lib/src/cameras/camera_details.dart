import 'dart:async';

import 'package:flutter/material.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/cameras/camera_identity.dart';
import 'package:grlab/src/connection/camera_sheet.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/data/cameras.dart';
import 'package:grlab/src/library/format.dart';
import 'package:grlab/src/pairing/pairing_widgets.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// One paired camera, from ⋯ on the Cameras screen (mock
/// `b-camera-detail`): connect to it, rename it or forget it.
class CameraDetailsScreen extends StatelessWidget {
  const new({required this.serial, super.key});

  final String serial;

  static Future<void> push(BuildContext context, String serial) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CameraDetailsScreen(serial: serial),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([models.cameras, models.connection]),
          builder: (context, _) {
            final camera = models.cameras.cameras
                .where((c) => c.serial == serial)
                .firstOrNull;
            // Forgotten: the screen is closing.
            if (camera == null) return const SizedBox.shrink();
            return ListView(
              key: const Key('camera-details'),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                  child: Row(
                    children: [
                      GrIconButton(
                        key: const Key('camera-details-back'),
                        icon: Icons.arrow_back_rounded,
                        tooltip: context.l10n.camerasBack,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                _Header(camera: camera),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: FilledButton(
                    key: const Key('camera-details-connect'),
                    onPressed:
                        models.connection.status == ConnectionStatus.connecting
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            unawaited(models.connection.connectTo(serial));
                          },
                    child: Text(context.l10n.camerasConnect),
                  ),
                ),
                SectionLabel(context.l10n.camerasDetailsSectionThisCamera),
                GroupBox(
                  children: [
                    GroupRow(
                      key: const Key('camera-details-rename'),
                      icon: Icons.edit_outlined,
                      title: context.l10n.camerasDetailsName,
                      trailing: TrailingFit.value(context, camera.name),
                      chevron: true,
                      onTap: () => showRenameCameraDialog(context, camera),
                    ),
                    GroupRow(
                      icon: Icons.schedule_rounded,
                      title: context.l10n.camerasDetailsPaired,
                      trailing: TrailingFit.value(
                        context,
                        formatDate(context, camera.pairedAt),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                GroupBox(children: [_ForgetRow(camera: camera)]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Text(
                    context.l10n.camerasDetailsUnpairHint,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: GrColors.of(context).t3,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const new({required this.camera});

  final SavedCamera camera;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.s3,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.photo_camera_outlined, size: 28, color: c.t1),
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

class _ForgetRow extends StatelessWidget {
  const new({required this.camera});

  final SavedCamera camera;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return InkWell(
      key: const Key('camera-forget'),
      onTap: () => _forget(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.danger.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: c.danger,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  context.l10n.camerasDetailsForget,
                  style: TextStyle(fontSize: 15, color: c.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _forget(BuildContext context) async {
    final models = AppScope.of(context);
    final navigator = Navigator.of(context);
    final c = GrColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.camerasDetailsForgetTitle(camera.name)),
        content: Text(context.l10n.camerasDetailsForgetMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.camerasDetailsForgetCancel),
          ),
          TextButton(
            key: const Key('camera-forget-confirm'),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.camerasDetailsForgetConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    navigator.pop();
    await models.forgetCamera(camera.serial);
  }
}
