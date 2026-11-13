import 'package:flutter/material.dart';

import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/cameras/cameras_screen.dart';
import 'package:grphoto/src/looks/looks_model.dart';
import 'package:grphoto/src/looks/looks_screen.dart';
import 'package:grphoto/src/widgets/dock.dart';

/// The pages of the home dock, shown while no camera's pages are open.
enum HomeTab {
  /// The paired cameras, to connect to one ([CamerasScreen]).
  cameras,

  /// The looks saved on the phone, whichever camera they came from.
  looks,
}

/// What the app shows under the camera's pages: the Cameras screen and the
/// saved looks, switched with the home dock. Both stay built, so switching
/// keeps their scroll positions.
class HomePages extends StatefulWidget {
  const new({super.key, this.autoConnect = false});

  /// Passed to [CamerasScreen.autoConnect].
  final bool autoConnect;

  @override
  State<HomePages> createState() => _HomePagesState();
}

class _HomePagesState extends State<HomePages> {
  late final LooksModel _looks = LooksModel.phone(
    store: AppScope.of(context).looks,
  );
  HomeTab _tab = HomeTab.cameras;

  @override
  void dispose() {
    _looks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DockLayout(
      dock: Dock<HomeTab>(
        key: const Key('home-tabs'),
        items: [
          DockItem(
            HomeTab.cameras,
            key: const Key('home-tab-cameras'),
            icon: Icons.camera_outlined,
            label: l10n.homeBarCameras,
          ),
          DockItem(
            HomeTab.looks,
            key: const Key('home-tab-looks'),
            icon: Icons.palette_outlined,
            label: l10n.homeBarLooks,
          ),
        ],
        selected: _tab,
        onSelect: (tab) => setState(() => _tab = tab),
      ),
      child: IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in HomeTab.values)
            TickerMode(
              enabled: tab == _tab,
              child: switch (tab) {
                HomeTab.cameras => CamerasScreen(
                  autoConnect: widget.autoConnect,
                  shown: tab == _tab,
                ),
                HomeTab.looks => LooksScreen(model: _looks),
              },
            ),
        ],
      ),
    );
  }
}
