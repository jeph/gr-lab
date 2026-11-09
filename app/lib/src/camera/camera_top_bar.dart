import 'package:flutter/material.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/connection/camera_pill.dart';
import 'package:grlab/src/settings/settings_screen.dart';
import 'package:grlab/src/theme/tokens.dart';

/// The row at the top of the camera's pages (mock `.topbar`): back to the
/// Cameras screen, the camera pill, and Settings.
class CameraTopBar extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
    child: Row(
      children: [
        RoundIconButton(
          key: const Key('camera-back'),
          icon: Icons.arrow_back_ios_new_rounded,
          iconSize: 16,
          label: context.l10n.cameraBarCameras,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: CameraPill(),
          ),
        ),
        const SizedBox(width: 8),
        RoundIconButton(
          key: const Key('camera-settings'),
          icon: Icons.settings_outlined,
          label: context.l10n.cameraBarSettings,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    ),
  );
}

/// A 36 pt round button on a raised surface (mock `.iconbtn`).
class RoundIconButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.iconSize = 18,
    this.color,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double iconSize;

  /// Background; defaults to the raised surface (`s2`).
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: color ?? c.s2,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor ?? c.t1,
              semanticLabel: label,
            ),
          ),
        ),
      ),
    );
  }
}

/// The large title under [CameraTopBar] (mock `.h1`).
class PageTitle extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
      ),
    ),
  );
}
