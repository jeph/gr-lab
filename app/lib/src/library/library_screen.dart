import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../connection/camera_pill.dart';
import '../connection/connection_controller.dart';
import '../data/settings.dart';
import '../downloads/download_bar.dart';
import '../downloads/download_engine.dart';
import '../settings/settings_screen.dart';
import '../theme/tokens.dart';
import '../widgets/group.dart';
import 'format.dart';
import 'library_model.dart';
import 'library_scope.dart';
import 'shot.dart';
import 'shot_cell.dart';
import 'viewer.dart';

/// The camera's photos (mocks `b-library-ios` / `b-library-android`): camera
/// pill and settings, filter chips, a grid by day, selection with a
/// download bar, and the download mini bar.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final AppModels _app = AppScope.of(context);
  LibraryContext? _library;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_library == null) {
      _library = LibraryContext.create(_app);
      _app.cameras.addListener(_onCameras);
      _onCameras();
    }
  }

  void _onCameras() {
    unawaited(_library!.model.setCamera(_app.cameras.current?.serial));
  }

  @override
  void dispose() {
    _app.cameras.removeListener(_onCameras);
    _library?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LibraryScope(library: _library!, child: const _LibraryView());
}

class _LibraryView extends StatefulWidget {
  const _LibraryView();

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  late final AppModels _app = AppScope.of(context);
  late final LibraryContext _library = LibraryScope.of(context);
  LibraryFilter _filter = LibraryFilter.all;
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _permissionDialogOpen = false;
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listening) {
      _listening = true;
      _library.engine.addListener(_onEngine);
    }
  }

  @override
  void dispose() {
    _library.engine.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() {
    final problem = _library.engine.permissionProblem;
    if (problem == null || _permissionDialogOpen) return;
    _permissionDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showPermissionGuidance(context);
      _library.engine.dismissPermissionProblem();
      _permissionDialogOpen = false;
    });
  }

  void _startSelecting(Shot shot) => setState(() {
    _selecting = true;
    _selected.add(shot.key);
  });

  void _toggle(Shot shot) => setState(() {
    if (!_selected.remove(shot.key)) _selected.add(shot.key);
    if (_selected.isEmpty) _selecting = false;
  });

  void _endSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  Future<void> _download(String serial, List<Shot> shots) async {
    _endSelecting();
    await _library.engine.enqueue(serial, shots, _app.settings.rawJpeg);
  }

  void _open(List<Shot> shots, int index) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LibraryScope(
            library: _library,
            child: ShotViewer(shots: shots, initialIndex: index),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _library.model,
      _library.engine,
      _app.settings,
      _app.connection,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final model = _library.model;
    final engine = _library.engine;
    final serial = model.serial;
    final choice = _app.settings.rawJpeg;
    final all = model.shots;
    bool downloaded(Shot s) =>
        serial != null && engine.isShotDownloaded(serial, s, choice);
    final filtered = all == null
        ? null
        : FilteredShots.of(all, _filter, downloaded);
    final shots = filtered?.shots;
    final selectedShots = [
      if (_selecting && all != null)
        for (final s in all)
          if (_selected.contains(s.key)) s,
    ];
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _endSelecting();
      },
      child: Scaffold(
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: model.refresh,
              notificationPredicate: (n) => model.connected && n.depth == 0,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverSafeArea(
                    bottom: false,
                    sliver: SliverToBoxAdapter(
                      child: _Header(
                        onSettings: () => unawaited(
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _StatusLine(model: model)),
                  if (filtered != null && all!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _Chips(
                        filter: _filter,
                        counts: filtered.counts,
                        onSelect: (f) => setState(() => _filter = f),
                      ),
                    ),
                  if (shots == null || shots.isEmpty || serial == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        model: model,
                        connection: _app.connection,
                        filter: _filter,
                      ),
                    )
                  else
                    ..._grid(context, serial, shots, choice),
                  SliverToBoxAdapter(child: SizedBox(height: 96 + bottomInset)),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12 + bottomInset,
              child: _selecting && serial != null
                  ? _SelectionBar(
                      serial: serial,
                      shots: selectedShots,
                      choice: choice,
                      onDownload: () => _download(serial, selectedShots),
                      onClose: _endSelecting,
                    )
                  : const DownloadBar(),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _grid(
    BuildContext context,
    String serial,
    List<Shot> shots,
    RawJpegChoice choice,
  ) {
    final model = _library.model;
    final engine = _library.engine;
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 5 : 3;
    final now = DateTime.now();
    final sections = daySections(shots, (s) => model.info(s.primary)?.taken);
    var offset = 0;
    final slivers = <Widget>[];
    for (final section in sections) {
      final start = offset;
      offset += section.shots.length;
      if (section.day != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: _DayLabel(
              title: formatDay(section.day!, now),
              shots: section.shots,
            ),
          ),
        );
      } else if (sections.length > 1 || start > 0) {
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
      }
      slivers.add(
        SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            final shot = section.shots[i];
            return ShotCell(
              key: ValueKey(shot.key),
              serial: serial,
              shot: shot,
              mark: _markFor(engine, serial, shot, choice),
              duration: model.info(shot.primary)?.duration,
              onVisible: () => unawaited(model.ensureInfo(shot.primary)),
              onTap: () => _selecting ? _toggle(shot) : _open(shots, start + i),
              onLongPress: () =>
                  _selecting ? _toggle(shot) : _startSelecting(shot),
            );
          }, childCount: section.shots.length),
        ),
      );
    }
    return slivers;
  }

  CellMark _markFor(
    DownloadEngine engine,
    String serial,
    Shot shot,
    RawJpegChoice choice,
  ) {
    if (_selecting) {
      return _selected.contains(shot.key)
          ? CellMark.selected
          : CellMark.unselected;
    }
    if (engine.isShotDownloaded(serial, shot, choice)) {
      return CellMark.downloaded;
    }
    if (shot.files.any((f) => engine.isFileQueued(serial, f))) {
      return CellMark.queued;
    }
    return CellMark.none;
  }
}

/// Explains how to allow photo-library access after the OS refused it.
Future<void> showPermissionGuidance(BuildContext context) {
  final ios = Theme.of(context).platform == TargetPlatform.iOS;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Allow access to Photos'),
      content: Text(
        ios
            ? 'GR Lab needs permission to add photos. Open Settings › GR Lab › '
                  'Photos, allow access, then retry the downloads.'
            : 'GR Lab needs permission to save photos and videos. Open '
                  'Settings › Apps › GR Lab › Permissions, allow Photos and '
                  'videos, then retry the downloads.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Row(
            children: [
              const Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: CameraPill(),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Settings',
                child: Material(
                  color: c.s2,
                  shape: CircleBorder(side: BorderSide(color: c.line)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onSettings,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.settings_outlined,
                        size: 18,
                        color: c.t1,
                        semanticLabel: 'Settings',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(
            'Library',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
        ),
      ],
    );
  }
}

/// Connecting, updating or failed-update note under the title. The
/// Library only shows while a camera is connected or reconnecting.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.model});

  final LibraryModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    if (model.shots == null) return const SizedBox.shrink();
    final style = TextStyle(fontSize: 13, color: c.t2);
    final Widget content;
    if (model.refreshing || !model.connected) {
      content = Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: c.t2),
          ),
          const SizedBox(width: 8),
          Text(model.refreshing ? 'Updating…' : 'Connecting…', style: style),
        ],
      );
    } else if (model.error != null) {
      content = Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: c.danger),
          const SizedBox(width: 6),
          Flexible(child: Text("Couldn't update the list", style: style)),
          TextButton(
            onPressed: () => unawaited(model.refresh()),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: SizedBox(height: 32, child: content),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({
    required this.filter,
    required this.counts,
    required this.onSelect,
  });

  final LibraryFilter filter;
  final Map<LibraryFilter, int> counts;
  final ValueChanged<LibraryFilter> onSelect;

  static String _label(LibraryFilter f) => switch (f) {
    LibraryFilter.all => 'All',
    LibraryFilter.jpeg => 'JPEG',
    LibraryFilter.raw => 'RAW',
    LibraryFilter.video => 'Video',
    LibraryFilter.notDownloaded => 'Not downloaded',
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Row(
      children: [
        for (final f in LibraryFilter.values) ...[
          if (f != LibraryFilter.all) const SizedBox(width: 8),
          GrChip(
            key: ValueKey('chip:${f.name}'),
            label: _label(f),
            count: counts[f],
            selected: f == filter,
            onTap: () => onSelect(f),
          ),
        ],
      ],
    ),
  );
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.title, required this.shots});

  final String title;
  final List<Shot> shots;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final storages = {for (final s in shots) storageLabel(s.storage)}
      ..remove(null);
    final meta = [
      '${shots.length}',
      if (storages.isNotEmpty) storages.join(' + '),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            meta,
            style: GrFonts.monoStyle(
              context,
              color: c.t3,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.model,
    required this.connection,
    required this.filter,
  });

  final LibraryModel model;
  final ConnectionController connection;
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final name = connection.camera?.name ?? 'your camera';
    final IconData icon;
    final String title;
    final String body;
    Widget? action;
    if (model.shots != null) {
      icon = Icons.photo_library_outlined;
      if (filter == LibraryFilter.all) {
        title = 'No photos';
        body = 'The camera has no photos or videos.';
      } else {
        title = 'Nothing here';
        body = filter == LibraryFilter.notDownloaded
            ? 'Every photo is on your phone.'
            : 'No photos match this filter.';
      }
    } else if (model.connected && model.error != null) {
      icon = Icons.error_outline_rounded;
      title = "Couldn't read the photos";
      body = 'The camera did not send its photo list.';
      action = FilledButton(
        onPressed: () => unawaited(model.refresh()),
        child: const Text('Try again'),
      );
    } else {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              model.connected
                  ? "Reading the camera's photos…"
                  : 'Connecting to $name…',
              style: TextStyle(color: c.t2),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: c.t3),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.t2),
          ),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }
}

/// 'N selected · F files · size' with Download (mock `.selbar`). Counts
/// what would actually be fetched: the setting's halves of each pair, minus
/// files already on the phone or queued.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.serial,
    required this.shots,
    required this.choice,
    required this.onDownload,
    required this.onClose,
  });

  final String serial;
  final List<Shot> shots;
  final RawJpegChoice choice;
  final VoidCallback onDownload;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final library = LibraryScope.of(context);
    final files = [
      for (final s in shots)
        ...library.engine.filesToDownload(serial, s, choice),
    ];
    var bytes = 0;
    var sizeKnown = true;
    for (final f in files) {
      final size = library.model.info(f)?.size;
      if (size == null) {
        sizeKnown = false;
        unawaited(library.model.ensureInfo(f));
      } else {
        bytes += size;
      }
    }
    final detail = files.isEmpty
        ? 'Already on your phone'
        : [
            '${files.length} ${files.length == 1 ? 'file' : 'files'}',
            if (sizeKnown) formatBytes(bytes),
          ].join(' · ');
    return Material(
      color: c.invBg,
      elevation: 0,
      borderRadius: BorderRadius.circular(20),
      shadowColor: c.shadow,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              tooltip: 'Cancel selection',
              icon: Icon(Icons.close_rounded, color: c.invFg),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${shots.length} selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.invFg,
                    ),
                  ),
                  Text(
                    detail,
                    key: const ValueKey('selection-detail'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GrFonts.monoStyle(
                      context,
                      size: 11.5,
                      color: c.invFg2,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                key: const ValueKey('selection-download'),
                onPressed: files.isEmpty ? null : onDownload,
                style: FilledButton.styleFrom(
                  backgroundColor: c.invFg,
                  foregroundColor: c.invBg,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
