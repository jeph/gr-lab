import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gr_protocol/gr_protocol.dart';

import '../app_scope.dart';
import '../data/cameras.dart';
import '../pairing/pairing_flow.dart';
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
/// mock `b-camera`, with the `b-connect` / `b-connect-fail` states):
/// connection progress or failure, battery and storage while connected,
/// and renaming, pairing another camera or forgetting this one.
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
                ConnectionStatus.connecting => _connecting(
                  context,
                  camera,
                  connection,
                ),
                ConnectionStatus.failed => _failed(context, camera, connection),
                ConnectionStatus.connected => _connected(
                  context,
                  camera,
                  connection,
                ),
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

  // ------------------------------------------------------------ connecting

  List<Widget> _connecting(
    BuildContext context,
    SavedCamera camera,
    ConnectionController connection,
  ) {
    final visible = connection.visibleSteps;
    // The wake happens before the link that stays up, as the user sees it.
    final ordered = [
      if (visible.contains(ConnectStep.waking)) ConnectStep.waking,
      ...visible.where((s) => s != ConnectStep.waking),
    ];
    final current = connection.step;
    final at = current == null ? -1 : ordered.indexOf(current);
    GrStepState state(int i) => i < at
        ? GrStepState.done
        : i == at
        ? GrStepState.now
        : GrStepState.todo;
    return [
      _Header(
        title: 'Connecting to ${camera.name}',
        subtitle: _identityLine(camera, null),
      ),
      Padding(
        key: const Key('camera-sheet-connecting'),
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
        child: GrStepList(
          steps: [
            for (var i = 0; i < ordered.length; i++)
              _step(ordered[i], state(i)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: OutlinedButton(
          key: const Key('camera-sheet-cancel'),
          onPressed: () => unawaited(connection.disconnect()),
          child: const Text('Cancel'),
        ),
      ),
    ];
  }

  static GrStep _step(ConnectStep step, GrStepState state) => switch (step) {
    ConnectStep.bluetooth => GrStep(
      state == GrStepState.done
          ? 'Connected over Bluetooth'
          : 'Connecting over Bluetooth',
      state,
    ),
    ConnectStep.waking => GrStep(
      'Waking the camera',
      state,
      detail: state == GrStepState.now
          ? 'It was off. The first link drops while it starts up; the app '
                'reconnects'
          : null,
    ),
    ConnectStep.wifiOn => GrStep("Turning on the camera's Wi-Fi", state),
    ConnectStep.joining => GrStep(
      "Joining the camera's Wi-Fi",
      state,
      detail: state == GrStepState.now ? 'This can take a while' : null,
    ),
  };

  // ---------------------------------------------------------------- failed

  List<Widget> _failed(
    BuildContext context,
    SavedCamera camera,
    ConnectionController connection,
  ) {
    final c = GrColors.of(context);
    final failure = connection.failure;
    final kind = failure?.kind ?? ConnectFailureKind.unreachable;
    final name = camera.name;
    final (title, body) = switch (kind) {
      ConnectFailureKind.bluetoothOff => (
        'Bluetooth is off',
        'Turn on Bluetooth on this phone, then try again.',
      ),
      ConnectFailureKind.bluetoothDenied => (
        "GR Lab can't use Bluetooth",
        'Allow Bluetooth (on Android: Nearby devices) for GR Lab in the '
            "phone's settings, then try again.",
      ),
      ConnectFailureKind.unreachable => (
        "Can't reach $name",
        "The camera didn't answer over Bluetooth.",
      ),
      ConnectFailureKind.needsPairing => (
        'Pair $name again',
        "The camera no longer accepts this phone's pairing, so trying again "
            "won't help. To pair again:",
      ),
      ConnectFailureKind.wifi => (
        "Couldn't join $name's Wi-Fi",
        "Bluetooth works, but the phone couldn't join or keep the camera's "
            'Wi-Fi.',
      ),
    };
    final tryAgain = kind == ConnectFailureKind.needsPairing
        ? OutlinedButton(
            key: const Key('camera-sheet-retry'),
            onPressed: () => unawaited(connection.connect()),
            child: const Text('Try again'),
          )
        : FilledButton(
            key: const Key('camera-sheet-retry'),
            onPressed: () => unawaited(connection.connect()),
            child: const Text('Try again'),
          );
    return [
      Padding(
        key: Key('camera-sheet-failed-${kind.name}'),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
                color: c.t1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(fontSize: 14, height: 1.45, color: c.t2),
            ),
          ],
        ),
      ),
      ...switch (kind) {
        ConnectFailureKind.unreachable => [
          const SectionLabel('Check'),
          const GroupBox(
            children: [
              GroupRow(
                icon: Icons.battery_std_rounded,
                title: "The camera is close and its battery isn't empty",
              ),
              GroupRow(
                icon: Icons.bluetooth_rounded,
                title: 'Action Mode is On',
                subtitle:
                    'MENU → E6 Wireless Connection → Wireless Communication',
              ),
            ],
          ),
          const SizedBox(height: 12),
          GroupBox(
            children: [
              GroupRow(
                icon: Icons.info_outline_rounded,
                title: 'Camera forgot this phone?',
                subtitle:
                    "If its Paired Devices list doesn't show this phone, "
                    'pair again',
                trailing: TrailingFit(
                  child: TextButton(
                    key: const Key('camera-sheet-pair-again'),
                    onPressed: () => _pairAnother(context),
                    child: const Text('Pair again'),
                  ),
                ),
              ),
            ],
          ),
        ],
        ConnectFailureKind.needsPairing => [
          const SizedBox(height: 18),
          const GroupBox(
            children: [
              GroupRow(
                leading: NumberTile(1),
                title: "Delete this phone from the camera's Paired Devices",
              ),
              GroupRow(
                leading: NumberTile(2),
                title: "Delete the camera from this phone's Bluetooth settings",
              ),
              GroupRow(
                leading: NumberTile(3),
                title: 'Open Execute Pairing on the camera and pair',
              ),
            ],
          ),
        ],
        ConnectFailureKind.wifi => [
          const SectionLabel('Check'),
          const GroupBox(
            children: [
              GroupRow(
                icon: Icons.wifi_rounded,
                title: 'The phone stays close to the camera',
              ),
              GroupRow(
                icon: Icons.check_circle_outline_rounded,
                title:
                    "If the phone asks to join the camera's network, "
                    'allow it',
              ),
            ],
          ),
        ],
        ConnectFailureKind.bluetoothOff ||
        ConnectFailureKind.bluetoothDenied => const <Widget>[],
      },
      if (failure != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
          child: Text(
            failure.message,
            style: GrFonts.monoStyle(context, size: 11, color: c.t3),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kind == ConnectFailureKind.needsPairing) ...[
              FilledButton(
                key: const Key('camera-sheet-pair-again'),
                onPressed: () => _pairAnother(context),
                child: const Text('Pair again'),
              ),
              const SizedBox(height: 10),
            ],
            tryAgain,
          ],
        ),
      ),
    ];
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
        subtitle: _identityLine(camera, props),
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
                      Icon(
                        Icons.wifi_rounded,
                        size: 18,
                        color: connection.reconnecting ? c.accent : c.ok,
                      ),
                    ],
                  ),
                ),
                caption: connection.reconnecting ? 'Reconnecting…' : 'Wi-Fi',
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: OutlinedButton(
          key: const Key('camera-sheet-disconnect'),
          onPressed: () => unawaited(connection.disconnect()),
          child: const Text('Disconnect'),
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

  List<Widget> _offline(BuildContext context, SavedCamera camera) {
    final connection = AppScope.of(context).connection;
    return [
      _Header(
        title: camera.name,
        subtitle: _identityLine(camera, null),
        large: true,
      ),
      Padding(
        key: const Key('camera-sheet-offline'),
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
        child: Text(
          'Not connected.',
          style: TextStyle(fontSize: 14, color: GrColors.of(context).t2),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: FilledButton(
          key: const Key('camera-sheet-connect'),
          onPressed: () => unawaited(connection.connect()),
          child: const Text('Connect'),
        ),
      ),
    ];
  }

  /// `GR IV · No. 1234567 · fw 1.20`, leaving out the model when the name
  /// already says it.
  static String _identityLine(SavedCamera camera, GrProps? props) {
    final model =
        stripRicohPrefix(props?.model) ??
        stripRicohPrefix(camera.paired.modelName);
    final firmware = props?.firmwareVersion ?? camera.paired.firmwareRevision;
    return [
      if (model != null && model.isNotEmpty && model != camera.name) model,
      'No. ${camera.serial}',
      if (firmware != null) 'fw $firmware',
    ].join(' · ');
  }
}

/// Closes the sheet and starts pairing over the Library.
void _pairAnother(BuildContext context) {
  final navigator = Navigator.of(context);
  navigator.pop();
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const PairingFlow()),
    ),
  );
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

/// Name, power-on choice, pairing another camera and forgetting this one.
class _CameraRows extends StatelessWidget {
  const _CameraRows({required this.camera});

  final SavedCamera camera;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
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
        GroupRow(
          key: const Key('camera-sheet-pair-another'),
          icon: Icons.add_rounded,
          title: 'Pair another camera',
          chevron: true,
          onTap: () => _pairAnother(context),
        ),
        InkWell(
          key: const Key('camera-sheet-forget'),
          onTap: () => _forget(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.danger.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: c.danger,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Forget camera',
                      style: TextStyle(fontSize: 15, color: c.danger),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _forget(BuildContext context) async {
    final models = AppScope.of(context);
    final navigator = Navigator.of(context);
    final c = GrColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${camera.name}?'),
        content: const Text(
          'GR Lab stops connecting to this camera. To use it again, delete '
          "this phone from the camera's Paired Devices and pair again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('camera-forget-confirm'),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    navigator.pop();
    await models.connection.disconnect();
    await models.cameras.remove(camera.serial);
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
