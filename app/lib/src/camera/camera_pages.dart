import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../connection/connection_controller.dart';
import '../data/settings.dart';
import '../library/library_screen.dart';
import '../shoot/shoot_model.dart';
import '../shoot/shoot_screen.dart';
import 'camera_tab_bar.dart';

/// The camera's pages, Library and Shoot, switched with the floating tab
/// bar ([ConnectionController.tab]). A page is built the first time it is
/// shown and kept while the pages are open, so switching keeps the
/// Library's scroll position and Shoot's state.
class CameraPages extends StatefulWidget {
  const CameraPages({super.key});

  @override
  State<CameraPages> createState() => _CameraPagesState();
}

class _CameraPagesState extends State<CameraPages> {
  late final AppModels _app = AppScope.of(context);
  late final ShootModel _shoot = ShootModel(
    connection: _app.connection,
    settings: _app.settings,
  );
  final Set<CameraTab> _built = {};

  /// The tab last shown; kept while the pages close ([tab] is then null).
  CameraTab _tab = CameraTab.library;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built.isEmpty) {
      _app.connection.addListener(_onConnection);
      _onConnection();
    }
  }

  void _onConnection() {
    final tab = _app.connection.tab;
    if (tab != null && (tab != _tab || _built.isEmpty)) {
      _built.add(tab);
      if (mounted) setState(() => _tab = tab);
    }
    _shoot.visible = tab == CameraTab.shoot;
  }

  @override
  void dispose() {
    _app.connection.removeListener(_onConnection);
    _shoot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _shoot,
    builder: (context, _) {
      // Live view is laid out like a camera app: the bar steps aside.
      final bar =
          !(_tab == CameraTab.shoot && _shoot.mode == ShootMode.liveView);
      final media = MediaQuery.of(context);
      final pages = IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in CameraTab.values)
            TickerMode(
              enabled: tab == _tab,
              child: !_built.contains(tab)
                  ? const SizedBox.shrink()
                  : switch (tab) {
                      CameraTab.library => const LibraryScreen(),
                      CameraTab.shoot => ShootScreen(model: _shoot),
                    },
            ),
        ],
      );
      return Stack(
        children: [
          // Pages keep their content above the bar.
          MediaQuery(
            data: bar
                ? media.copyWith(
                    padding: media.padding.copyWith(
                      bottom: media.padding.bottom + CameraTabBar.height + 8,
                    ),
                  )
                : media,
            child: pages,
          ),
          if (bar)
            Positioned(
              left: 0,
              right: 0,
              bottom: media.padding.bottom + 12,
              child: Center(
                child: CameraTabBar(
                  tab: _tab,
                  onSelect: _app.connection.selectTab,
                ),
              ),
            ),
        ],
      );
    },
  );
}
