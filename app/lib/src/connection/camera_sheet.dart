import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../app_scope.dart';
import '../data/cameras.dart';
import '../pairing/pairing_widgets.dart';
import '../theme/tokens.dart';
import '../widgets/group.dart';
import 'connection_controller.dart';

/// Opens the camera sheet over the current screen.
Future<void> showCameraSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CameraSheet(),
    );

/// Everything about the current camera, from the camera pill (subset of
/// mock `b-camera`): battery, storage and link while connected, and the
/// camera's name and power-on choice. Disconnecting Wi-Fi returns to the
/// Cameras screen; Bluetooth stays.
class CameraSheet extends StatelessWidget {
  const CameraSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        models.cameras,
        models.connection,
        models.settings,
      ]),
      builder: (context, _) {
        final camera = models.cameras.current;
        if (camera == null) return const SizedBox(height: 120);
        final connection = models.connection;
        return SingleChildScrollView(
          key: const Key('camera-sheet'),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...switch (connection.status) {
                ConnectionStatus.connected => _connected(
                  context,
                  camera,
                  connection,
                ),
                // Only while the sheet closes: losing or leaving Wi-Fi
                // returns to the Cameras screen.
                ConnectionStatus.connecting ||
                ConnectionStatus.bluetooth ||
                ConnectionStatus.failed ||
                ConnectionStatus.offline => _offline(context, camera),
              },
              const SectionLabel('Camera'),
              _CameraRows(camera: camera),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- connected

  List<Widget> _connected(
    BuildContext context,
    SavedCamera camera,
    ConnectionController connection,
  ) {
    final c = GrColors.of(context);
    final props = connection.props;
    final battery = props?.battery;
    final storages = _storages(props);
    return [
      _Header(
        title: camera.name,
        subtitle: camera.identityLine(props: props),
        large: true,
      ),
      Padding(
        key: const Key('camera-sheet-connected'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Tile(
                label: 'Battery',
                value: _Fit(
                  child: Text(
                    battery == null ? '—' : '$battery%',
                    key: const Key('camera-sheet-battery'),
                    style: GrFonts.monoStyle(context, size: 20, color: c.t1),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                label: 'Storage',
                value: Column(
                  key: const Key('camera-sheet-storage'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (storages.isEmpty)
                      Text(
                        '—',
                        style: GrFonts.monoStyle(
                          context,
                          size: 20,
                          color: c.t1,
                        ),
                      ),
                    for (final s in storages)
                      _Fit(
                        key: Key('camera-sheet-storage-${s.id}'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              s.label,
                              style: TextStyle(fontSize: 11.5, color: c.t2),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s.remain == null ? '—' : _grouped(s.remain!),
                              style: GrFonts.monoStyle(
                                context,
                                // Two cards share the tile's height.
                                size: storages.length > 1 ? 15 : 20,
                                color: c.t1,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                caption: storages.isEmpty ? null : 'shots left',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                label: 'Link',
                value: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth_rounded, size: 18, color: c.ok),
                      const SizedBox(width: 6),
                      Icon(Icons.wifi_rounded, size: 18, color: c.ok),
                    ],
                  ),
                ),
                caption: 'Wi-Fi',
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: OutlinedButton(
          key: const Key('camera-sheet-disconnect'),
          onPressed: () => unawaited(connection.closeLibrary()),
          child: const Text('Disconnect Wi-Fi'),
        ),
      ),
    ];
  }

  /// Every storage that can take photos, SD card first because that is
  /// where photos normally go.
  static List<({String id, String label, int? remain})> _storages(
    GrProps? props,
  ) {
    final storages = [
      for (final s in props?.storages ?? const <GrStorageInfo>[])
        if (s.equipped != false)
          (
            id: s.name ?? '?',
            label: switch (s.name) {
              'sd1' => 'SD',
              'in' => 'Internal',
              final name? => name,
              null => 'Storage',
            },
            remain: s.remain,
          ),
    ];
    int rank(String id) => switch (id) {
      'sd1' => 0,
      'in' => 2,
      _ => 1,
    };
    return storages..sort((a, b) => rank(a.id).compareTo(rank(b.id)));
  }

  // --------------------------------------------------------------- offline

  List<Widget> _offline(BuildContext context, SavedCamera camera) => [
    _Header(title: camera.name, subtitle: camera.identityLine(), large: true),
    Padding(
      key: const Key('camera-sheet-offline'),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Text(
        'Not connected.',
        style: TextStyle(fontSize: 14, color: GrColors.of(context).t2),
      ),
    ),
  ];
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    this.large = false,
  });

  final String title;
  final String subtitle;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final size = large ? 64.0 : 56.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c.s3,
              borderRadius: BorderRadius.circular(large ? 18 : 16),
            ),
            child: Icon(Icons.photo_camera_outlined, size: 28, color: c.t1),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: large ? 20 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                    color: c.t1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: GrFonts.monoStyle(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the three status tiles (battery, storage, link).
class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.caption});

  final String label;
  final Widget value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(GrRadii.lg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
              color: c.t2,
            ),
          ),
          const SizedBox(height: 6),
          value,
          if (caption case final caption?)
            Text(caption, style: TextStyle(fontSize: 10.5, color: c.t3)),
        ],
      ),
    );
  }
}

/// Shrinks one line of tile content to the tile's width instead of
/// wrapping or overflowing it at large text sizes.
class _Fit extends StatelessWidget {
  const _Fit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );
}

/// Name and power-on choice.
class _CameraRows extends StatelessWidget {
  const _CameraRows({required this.camera});

  final SavedCamera camera;

  @override
  Widget build(BuildContext context) {
    final models = AppScope.of(context);
    return GroupBox(
      children: [
        GroupRow(
          key: const Key('camera-sheet-rename'),
          icon: Icons.edit_outlined,
          title: 'Name',
          trailing: TrailingFit.value(context, camera.name),
          chevron: true,
          onTap: () => showRenameCameraDialog(context, camera),
        ),
        GroupRow(
          icon: Icons.power_settings_new_rounded,
          title: 'Turn on when connecting',
          trailing: Switch(
            key: const Key('camera-sheet-power-on'),
            value: models.settings.powerOnWhenConnecting,
            onChanged: (v) => models.settings.powerOnWhenConnecting = v,
          ),
        ),
      ],
    );
  }
}

/// Asks for a new display name for [camera] and saves it.
Future<void> showRenameCameraDialog(
  BuildContext context,
  SavedCamera camera,
) async {
  final cameras = AppScope.of(context).cameras;
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: camera.name),
  );
  if (name == null) return;
  await cameras.rename(camera.serial, name);
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final name = _text.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Camera name'),
    content: TextField(
      key: const Key('camera-rename-field'),
      controller: _text,
      autofocus: true,
      maxLength: 32,
      textCapitalization: TextCapitalization.words,
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ListenableBuilder(
        listenable: _text,
        builder: (context, _) => TextButton(
          key: const Key('camera-rename-save'),
          onPressed: _text.text.trim().isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ),
    ],
  );
}

/// `1234` → `1,234`.
String _grouped(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
