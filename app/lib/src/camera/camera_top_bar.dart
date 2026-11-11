import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/connection/camera_pill.dart';
import 'package:grlab/src/settings/settings_screen.dart';
import 'package:grlab/src/theme/tokens.dart';

/// The row at the top of the camera's pages (mock `.topbar`): back to the
/// Cameras screen, the camera pill and, on pages without a [PageTitle],
/// Settings.
class CameraTopBar extends StatelessWidget {
  const new({super.key, this.showSettings = true, this.middle});

  /// Whether the bar carries [SettingsButton]. Pages with a [PageTitle] put
  /// it in the title's row instead.
  final bool showSettings;

  /// Centred in the bar, for a page in a window too short to give it a row
  /// of its own. It gets the width that [_minSideWidth] leaves and has to
  /// fit that, by scaling down for example.
  final Widget? middle;

  /// The room either side of [middle] keeps: the back button and a camera
  /// pill cut down to its icon, the start of the name and the link's state
  /// \[design\].
  static const _minSideWidth = 144.0;

  @override
  Widget build(BuildContext context) {
    final back = RoundIconButton(
      key: const Key('camera-back'),
      icon: Icons.arrow_back_ios_new_rounded,
      iconSize: 16,
      label: context.l10n.cameraBarCameras,
      onTap: () => Navigator.of(context).maybePop(),
    );
    const padding = EdgeInsets.fromLTRB(18, 6, 18, 0);
    final middle = this.middle;
    if (middle == null) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            back,
            const SizedBox(width: 8),
            const Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: CameraPill(),
              ),
            ),
            if (showSettings) ...[
              const SizedBox(width: 8),
              const SettingsButton(),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, bar) => Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  back,
                  const SizedBox(width: 8),
                  const Flexible(child: CameraPill()),
                ],
              ),
            ),
            // A Row lets a child like this be as wide as it likes.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0, bar.maxWidth - 2 * _minSideWidth),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: middle,
              ),
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: showSettings ? const SettingsButton() : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens Settings from the camera's pages.
class SettingsButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => RoundIconButton(
    key: const Key('camera-settings'),
    icon: Icons.settings_outlined,
    label: context.l10n.cameraBarSettings,
    onTap: () => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
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

/// The large title of a page (mock `.h1`), with its [status] after it and
/// its [actions] at the end of the same row.
class PageTitle extends StatelessWidget {
  const new(this.text, {super.key, this.status, this.actions = const []});

  final String text;

  /// A state that comes and goes, such as the Library's Updating…. Beside
  /// the title it leaves the rest of the page where it is \[design\]: a
  /// status on a line of its own would move the page. It gets the width the
  /// title leaves, never less than [minStatusWidth], and has to fit that.
  ///
  /// A page passes its status widget in every state, showing nothing in it
  /// between times: a title that had the whole row until the status came
  /// could wrap then, and move the page after all.
  final Widget? status;

  /// The width [status] always has: room for a spinner.
  static const minStatusWidth = 12.0;

  /// Between the title and [status].
  static const _statusGap = 12.0;

  /// Buttons at the end of the row, such as [SettingsButton].
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final title = Text(
      text,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 18, 4),
      child: Row(
        children: [
          Expanded(
            child: status == null
                ? title
                : LayoutBuilder(
                    builder: (context, row) => Row(
                      children: [
                        // A Row lets a child like this be as wide as it
                        // likes; a long title still wraps, in the row less
                        // the status's room.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.max(
                              0,
                              row.maxWidth - _statusGap - minStatusWidth,
                            ),
                          ),
                          child: title,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: _statusGap,
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: status,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          for (final action in actions) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}
