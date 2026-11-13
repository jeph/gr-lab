import 'package:flutter/material.dart';
import 'package:grphoto/src/app_scope.dart';
import 'package:grphoto/src/camera/camera_tab_bar.dart';
import 'package:grphoto/src/connection/connection_controller.dart';
import 'package:grphoto/src/data/settings.dart';
import 'package:grphoto/src/library/library_screen.dart';
import 'package:grphoto/src/looks/looks_model.dart';
import 'package:grphoto/src/looks/looks_screen.dart';
import 'package:grphoto/src/shoot/shoot_model.dart';
import 'package:grphoto/src/shoot/shoot_screen.dart';
import 'package:grphoto/src/widgets/dock.dart';

/// The camera's pages, Library, Shoot and Looks (when the camera has
/// Custom slots to load looks into, [ConnectionController.tabs]), switched
/// with the floating tab bar ([ConnectionController.tab]). A page is built
/// the first time it is shown and kept while the pages are open, so
/// switching keeps the Library's scroll position and Shoot's state.
class CameraPages extends StatefulWidget {
  const new({super.key});

  @override
  State<CameraPages> createState() => _CameraPagesState();
}

class _CameraPagesState extends State<CameraPages> {
  late final AppModels _app = AppScope.of(context);
  late final ShootModel _shoot = ShootModel(
    connection: _app.connection,
    settings: _app.settings,
  );
  late final LooksModel _looks = LooksModel.camera(
    connection: _app.connection,
    store: _app.looks,
  );
  final Set<CameraTab> _built = {};

  /// The tab last shown; kept while the pages close
  /// ([ConnectionController.tab] is then null).
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
    _looks.visible = tab == CameraTab.looks;
  }

  @override
  void dispose() {
    _app.connection.removeListener(_onConnection);
    _shoot.dispose();
    _looks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _shoot,
    builder: (context, _) {
      // Live view is laid out like a camera app: the bar steps aside.
      final bar =
          !(_tab == CameraTab.shoot && _shoot.mode == ShootMode.liveView);
      return DockLayout(
        dock: bar
            ? CameraTabBar(
                tabs: _app.connection.tabs,
                tab: _tab,
                onSelect: _app.connection.selectTab,
              )
            : null,
        child: IndexedStack(
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
                        CameraTab.looks => LooksScreen(model: _looks),
                      },
              ),
          ],
        ),
      );
    },
  );
}
