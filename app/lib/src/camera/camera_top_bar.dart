import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/connection/camera_pill.dart';
import 'package:grphoto/src/settings/settings_screen.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/scroll_away_header.dart';
import 'package:grphoto/src/widgets/window_layout.dart';

/// The row at the top of the camera's pages (mock `.topbar`): back to the
/// Cameras screen, the camera pill and Settings. In a window with a
/// [VerticalBar] it is the camera pill alone: Back and Settings stand in
/// the bar ([CameraBarColumn]).
class CameraTopBar extends StatelessWidget {
  const new({
    super.key,
    this.middle,
    this.pages,
    this.leading = const CameraBackButton(),
    this.trailing = const SettingsButton(),
  });

  /// Centred in the bar, for a page in a window too short to give it a row
  /// of its own. It gets the width that [_minSideWidth] leaves and has to
  /// fit that, by scaling down for example.
  final Widget? middle;

  /// The parts of a wide window with a [VerticalBar], which has the bar's
  /// buttons: the camera pill goes in the first and [middle] from the
  /// start of the second instead of in the middle, so that neither crosses
  /// a fold. Without [middle] it is ignored.
  final BookFold? pages;

  /// At the bar's ends, where the window has no [VerticalBar] for them:
  /// Back and Settings on most pages; live view has × and the exposure
  /// mode there.
  final Widget? leading;
  final Widget? trailing;

  /// The room either side of [middle] keeps: the back button and a camera
  /// pill cut down to its icon, the start of the name and the link's state
  /// \[design\].
  static const _minSideWidth = 144.0;

  /// The bar's height at the default text size: its padding and its
  /// 36 pt buttons.
  static const double height = 6 + 36;

  static const _padding = EdgeInsets.fromLTRB(18, 6, 18, 0);

  @override
  Widget build(BuildContext context) {
    final ownButtons = VerticalBar.of(context) == null;
    final leading = ownButtons ? this.leading : null;
    final trailing = ownButtons ? this.trailing : null;
    final middle = this.middle;
    if (middle == null) {
      return Padding(
        padding: _padding,
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            const Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: CameraPill(),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      );
    }
    final pages = this.pages;
    if (pages != null) return _inPages(middle, pages);
    return Padding(
      padding: _padding,
      child: LayoutBuilder(
        builder: (context, bar) => Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (leading != null) ...[leading, const SizedBox(width: 8)],
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
              child: trailing == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: trailing,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The camera pill in the first of [pages], and [middle] from the start
  /// of what the gap after it leaves.
  Widget _inPages(Widget middle, BookFold pages) => Padding(
    padding: EdgeInsets.only(top: _padding.top),
    child: Row(
      children: [
        SizedBox(
          width: pages.first,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _padding.left),
            child: const Align(
              alignment: AlignmentDirectional.centerStart,
              heightFactor: 1,
              child: CameraPill(),
            ),
          ),
        ),
        SizedBox(width: pages.gap),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              heightFactor: 1,
              child: middle,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A page of the camera with Back and Settings, and then [more], down the
/// window's [VerticalBar] where it has one ([BarColumn]). [CameraTopBar]
/// leaves them out there.
class CameraBarColumn extends StatelessWidget {
  const new({required this.child, super.key, this.more = const []});

  /// The page's own buttons, under Settings.
  final List<Widget> more;
  final Widget child;

  @override
  Widget build(BuildContext context) => BarColumn(
    buttons: [const CameraBackButton(), const SettingsButton(), ...more],
    child: child,
  );
}

/// Goes back from the camera's pages to the Cameras screen.
class CameraBackButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => RoundIconButton(
    key: const Key('camera-back'),
    icon: Icons.arrow_back_ios_new_rounded,
    iconSize: 16,
    label: context.l10n.cameraBarCameras,
    onTap: () => Navigator.of(context).maybePop(),
  );
}

/// [CameraTopBar] as the first sliver of a page that scrolls
/// ([SliverScrollAwayHeader]). It leaves as the page scrolls down and
/// comes back over the page as soon as it scrolls up \[design\]: Cameras,
/// the link and Settings stay a short scroll away in a long Library.
///
/// The bar has no background \[design\]: its buttons float over the page,
/// which shows, and takes taps, between and around them.
class SliverCameraTopBar extends StatelessWidget {
  const new({super.key});

  /// Under the bar, between its buttons and the start of the page.
  static const _bottomGap = 6.0;

  @override
  Widget build(BuildContext context) => const SliverScrollAwayHeader(
    child: StatusBandBar(
      barHeight: CameraTopBar.height + _bottomGap,
      child: Padding(
        padding: EdgeInsets.only(bottom: _bottomGap),
        child: CameraTopBar(),
      ),
    ),
  );
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
