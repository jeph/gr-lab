import 'package:flutter/material.dart';

import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/widgets/dock.dart';

/// The [Dock] switching the camera's pages: [tabs], the ones the camera
/// has ([ConnectionController.tabs]).
class CameraTabBar extends StatelessWidget {
  const new({
    required this.tabs,
    required this.tab,
    required this.onSelect,
    super.key,
  });

  final List<CameraTab> tabs;
  final CameraTab tab;
  final ValueChanged<CameraTab> onSelect;

  /// The icon of [tab]'s page, here and on the camera card's buttons.
  static IconData icon(CameraTab tab) => switch (tab) {
    CameraTab.library => Icons.photo_library_outlined,
    CameraTab.shoot => Icons.photo_camera_outlined,
    CameraTab.looks => Icons.palette_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dock<CameraTab>(
      key: const Key('camera-tabs'),
      items: [
        for (final t in tabs)
          DockItem(
            t,
            key: Key('camera-tab-${t.name}'),
            icon: icon(t),
            label: switch (t) {
              CameraTab.library => l10n.cameraBarLibrary,
              CameraTab.shoot => l10n.cameraBarShoot,
              CameraTab.looks => l10n.cameraBarLooks,
            },
          ),
      ],
      selected: tab,
      onSelect: onSelect,
    );
  }
}
