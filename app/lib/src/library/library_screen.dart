import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grlab/l10n/l10n.dart';
import 'package:grlab/src/app_scope.dart';
import 'package:grlab/src/camera/camera_top_bar.dart';
import 'package:grlab/src/connection/connect_failure_view.dart';
import 'package:grlab/src/connection/connect_steps.dart';
import 'package:grlab/src/connection/connection_controller.dart';
import 'package:grlab/src/downloads/download_bar.dart';
import 'package:grlab/src/downloads/download_engine.dart';
import 'package:grlab/src/library/format.dart';
import 'package:grlab/src/library/library_model.dart';
import 'package:grlab/src/library/library_scope.dart';
import 'package:grlab/src/library/shot.dart';
import 'package:grlab/src/library/shot_cell.dart';
import 'package:grlab/src/library/viewer.dart';
import 'package:grlab/src/theme/tokens.dart';
import 'package:grlab/src/widgets/group.dart';

/// The camera's photos (mocks `b-library-ios` / `b-library-android`): camera
/// pill and settings, filter chips, a grid by day, selection with a
/// download bar, and the download mini bar.
class LibraryScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => LibraryScope(
    library: AppScope.of(context).library,
    child: const _LibraryView(),
  );
}

class _LibraryView extends StatefulWidget {
  const new();

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
      // The engine is the app's: the photo library may have refused it
      // while the camera pages were closed.
      _onEngine();
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

  Future<void> _download(String serial, List<Shot> shots, FileKind kind) async {
    _endSelecting();
    await _library.engine.enqueue(serial, shots, kinds: {kind});
  }

  void _open(List<Shot> shots, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryScope(
          library: _library,
          child: ShotViewer(shots: shots, initialIndex: index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _library.model,
      _library.engine,
      _app.connection,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final model = _library.model;
    final engine = _library.engine;
    final serial = model.serial;
    final all = model.shots;
    bool downloaded(Shot s) =>
        serial != null && engine.isShotDownloaded(serial, s);
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
    // Without the camera's Wi-Fi the failure replaces the (cached) photos;
    // its Try again joins again.
    final failure = _app.connection.failure;
    final wifiFailure = !model.connected && failure?.step == ConnectStep.wifi
        ? failure
        : null;
    final camera = _app.connection.camera;

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
                  const SliverSafeArea(
                    bottom: false,
                    sliver: SliverToBoxAdapter(child: _Header()),
                  ),
                  if (wifiFailure != null && camera != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: ConnectFailureView(
                          camera: camera,
                          failure: wifiFailure,
                          connection: _app.connection,
                        ),
                      ),
                    )
                  else ...[
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
                      ..._grid(context, serial, shots),
                  ],
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
                      onDownload: (kind) =>
                          _download(serial, selectedShots, kind),
                      onClose: _endSelecting,
                    )
                  : const DownloadBar(),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _grid(BuildContext context, String serial, List<Shot> shots) {
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
              title: formatDay(context, section.day!, now),
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
              mark: _markFor(engine, serial, shot),
              duration: model.info(shot.primary)?.duration,
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

  CellMark _markFor(DownloadEngine engine, String serial, Shot shot) {
    if (_selecting) {
      return _selected.contains(shot.key)
          ? CellMark.selected
          : CellMark.unselected;
    }
    // A shot downloaded before and queued again shows that it is coming.
    if (shot.files.any((f) => engine.isFileQueued(serial, f))) {
      return CellMark.queued;
    }
    if (engine.isShotDownloaded(serial, shot)) return CellMark.downloaded;
    return CellMark.none;
  }
}

/// Explains how to allow photo-library access after the OS refused it.
Future<void> showPermissionGuidance(BuildContext context) {
  final ios = Theme.of(context).platform == TargetPlatform.iOS;
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.libraryPhotoAccessTitle),
      content: Text(
        ios ? l10n.libraryPhotoAccessIos : l10n.libraryPhotoAccessAndroid,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.libraryOk),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CameraTopBar(showSettings: false),
        PageTitle(context.l10n.libraryTitle, actions: const [SettingsButton()]),
      ],
    );
  }
}

/// Updating, or failed-update note under the title. The Library only shows
/// while the camera's Wi-Fi is up; a failed update whose camera no longer
/// answers returns to the Cameras screen instead (see `ConnectionLink`).
class _StatusLine extends StatelessWidget {
  const new({required this.model});

  final LibraryModel model;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
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
          Text(
            model.refreshing ? l10n.libraryUpdating : l10n.libraryConnecting,
            style: style,
          ),
        ],
      );
    } else if (model.error != null) {
      content = Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: c.danger),
          const SizedBox(width: 6),
          Flexible(child: Text(l10n.libraryUpdateFailed, style: style)),
          TextButton(
            onPressed: () => unawaited(model.refresh()),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.libraryRetry),
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
  const new({
    required this.filter,
    required this.counts,
    required this.onSelect,
  });

  final LibraryFilter filter;
  final Map<LibraryFilter, int> counts;
  final ValueChanged<LibraryFilter> onSelect;

  static String _label(AppLocalizations l10n, LibraryFilter f) => switch (f) {
    LibraryFilter.all => l10n.libraryFilterAll,
    LibraryFilter.jpeg => l10n.libraryFilterJpeg,
    LibraryFilter.raw => l10n.libraryFilterRaw,
    LibraryFilter.video => l10n.libraryFilterVideo,
    LibraryFilter.notDownloaded => l10n.libraryFilterNotDownloaded,
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
            label: _label(context.l10n, f),
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
  const new({required this.title, required this.shots});

  final String title;
  final List<Shot> shots;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final storages = {for (final s in shots) storageLabel(context, s.storage)}
      ..remove(null);
    final meta = [
      formatCount(context, shots.length),
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
  const new({
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
    final l10n = context.l10n;
    final IconData icon;
    final String title;
    final String body;
    Widget? action;
    if (model.shots != null) {
      icon = Icons.photo_library_outlined;
      if (filter == LibraryFilter.all) {
        title = l10n.libraryEmptyTitle;
        body = l10n.libraryEmptyBody;
      } else {
        title = l10n.libraryFilterEmptyTitle;
        body = filter == LibraryFilter.notDownloaded
            ? l10n.libraryFilterEmptyNotDownloaded
            : l10n.libraryFilterEmptyBody;
      }
    } else if (model.connected && model.error != null) {
      icon = Icons.error_outline_rounded;
      title = l10n.libraryListFailedTitle;
      body = l10n.libraryListFailedBody;
      action = FilledButton(
        onPressed: () => unawaited(model.refresh()),
        child: Text(l10n.libraryTryAgain),
      );
    } else if (!model.connected) {
      return Padding(
        key: const Key('library-joining'),
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (connection.camera?.name) {
                final name? => l10n.libraryJoining(name),
                null => l10n.libraryJoiningUnnamed,
              },
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            ConnectSteps(connection: connection),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.libraryReading, style: TextStyle(color: c.t2)),
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

/// 'N selected' with a download action per kind of file (mock `.selbar`):
/// JPEG and RAW, plus Video when movies are selected. A RAW+JPEG pair
/// counts for both. Each action shows what it would fetch: the files of its
/// kind that are not already queued, including files downloaded before
/// (they may have been deleted from the phone).
class _SelectionBar extends StatelessWidget {
  const new({
    required this.serial,
    required this.shots,
    required this.onDownload,
    required this.onClose,
  });

  final String serial;
  final List<Shot> shots;
  final ValueChanged<FileKind> onDownload;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final kinds = [
      FileKind.jpeg,
      FileKind.raw,
      if (shots.any((s) => s.isVideo)) FileKind.movie,
    ];
    return Material(
      color: c.invBg,
      borderRadius: BorderRadius.circular(20),
      shadowColor: c.shadow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onClose,
                  tooltip: l10n.libraryCancelSelection,
                  icon: Icon(Icons.close_rounded, color: c.invFg),
                ),
                Expanded(
                  child: Text(
                    l10n.librarySelectedCount(shots.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.invFg,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  for (final (i, kind) in kinds.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _KindAction(
                        serial: serial,
                        shots: shots,
                        kind: kind,
                        onDownload: () => onDownload(kind),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Downloads the selection's files of one kind: 'JPEG', '3 files · 24 MB'.
class _KindAction extends StatelessWidget {
  const new({
    required this.serial,
    required this.shots,
    required this.kind,
    required this.onDownload,
  });

  final String serial;
  final List<Shot> shots;
  final FileKind kind;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    final library = LibraryScope.of(context);
    final files = [
      for (final s in shots) ...library.engine.filesToDownload(serial, s, kind),
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
    final String detail;
    if (files.isNotEmpty) {
      detail = [
        l10n.libraryFileCount(files.length),
        if (sizeKnown) formatBytes(context, bytes),
      ].join(' · ');
    } else if (shots.any((s) => s.filesOf(kind).isNotEmpty)) {
      detail = l10n.libraryKindQueued;
    } else {
      detail = l10n.libraryKindNoneSelected;
    }
    return FilledButton(
      key: ValueKey('selection-download:${kind.name}'),
      onPressed: files.isEmpty ? null : onDownload,
      style: FilledButton.styleFrom(
        backgroundColor: c.invFg,
        foregroundColor: c.invBg,
        disabledBackgroundColor: c.invFg.withValues(alpha: .08),
        disabledForegroundColor: c.invFg2,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GrRadii.md),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_rounded, size: 16),
              const SizedBox(width: 4),
              Text(
                switch (kind) {
                  FileKind.jpeg => l10n.libraryFormatJpeg,
                  FileKind.raw => l10n.libraryFormatRaw,
                  FileKind.movie => l10n.libraryFormatVideo,
                },
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Text(
            detail,
            key: ValueKey('selection-detail:${kind.name}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // The button's foreground, dimmed with it when disabled.
            style: const TextStyle(
              fontFamily: GrFonts.mono,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
