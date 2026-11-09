import 'package:flutter/foundation.dart';
import 'package:gr_camera/src/camera_features.dart';
import 'package:gr_camera/src/environment.dart';
import 'package:gr_camera/src/looks/look.dart';
import 'package:gr_protocol/gr_protocol.dart';

/// The longest slot name, in characters: GR WORLD's name editor stops at
/// 32 (code 0x960724), and Ricoh's GR WORLD page says "up to 32
/// single-byte characters" (research/protocol/image-control.md §2).
const lookNameMaxLength = 32;

/// The characters GR WORLD lets a slot name have (pool 0x32898): ASCII
/// letters, digits, spaces and common symbols. Whether the camera shows
/// other characters is \[unknown\].
final lookNameCharacters = RegExp(
  r'''[a-zA-Z0-9@#%:.,/+\\"'`~^*=()<>\[\]!?&_\s-]''',
);

/// [CameraLooks.load] refused a look the connected camera does not offer
/// ([Look.offeredBy]): its base image is not one the camera's model has,
/// or is one GR Lab does not know. Nothing was written.
final class LookNotOffered implements Exception {
  /// A look on [base] refused by a camera of [model].
  const new({required this.base, required this.model});

  /// The look's base image; null when GR Lab does not know it.
  final LookBase? base;

  /// The connected camera's model; null when GR Lab does not know it.
  final GrModel? model;

  @override
  String toString() =>
      'LookNotOffered(base: ${base?.name}, model: ${model?.name})';
}

/// One Image Control Custom slot (C1–C3) as the camera reported it.
@immutable
final class LookSlot {
  /// Slot [number] (1–3) holding [data], decoded as [look], under [name].
  const new({
    required this.number,
    required this.name,
    required this.data,
    required this.look,
  });

  /// 1 for C1, 2 for C2, 3 for C3.
  final int number;

  /// The name the camera keeps for the slot \[inferred\]: UTF-8 with any
  /// NUL padding removed, as GR WORLD reads it (CamSvcChars.md §2).
  final String name;

  /// The slot's Image Control blob as read.
  final Uint8List data;

  /// [data] read as a look; null when it is not one.
  final Look? look;
}

/// The camera's Image Control Custom slots C1–C3 over Bluetooth, for one
/// session: reading what each holds and loading a look into one. Only
/// models with `CameraFeature.lookSlots` serve them (the slots are
/// `GrBleCatalog.imageControlSlots`). GR WORLD loads a look by writing the
/// data, then the name, then reading every slot back
/// (`/imageControlWrite`, CamSvcChars.md §7 item 4); this does the same for
/// the one slot it writes.
final class CameraLooks extends ChangeNotifier {
  new _(this._session, this._camera, this._body);

  final GrSession _session;
  final GrCameraEnvironment _camera;

  /// The camera's model and firmware, as `CameraSession.body` has them.
  final CameraBody Function() _body;
  List<LookSlot>? _slots;
  bool _closed = false;

  /// What C1–C3 hold, in slot order; null until [readSlots] has read them
  /// on this session.
  List<LookSlot>? get slots => _slots;

  /// The Bluetooth link is up.
  bool get linked => _session.ble != null;

  /// Turns the camera on, or puts a camera that is on into shooting, as
  /// `CameraRemote.wake` does: the slots are served by the camera's main
  /// firmware, not by the Bluetooth-only state of a camera that is off
  /// \[inferred\] (firmware-bonding.md §6). Throws [GrSessionException].
  Future<void> wake() => _session.wake(BleOperationMode.capture);

  /// Reads the name and data of C1–C3 into [slots]. Throws when a read
  /// fails; does nothing without a link.
  Future<void> readSlots() async {
    final ble = _session.ble;
    if (ble == null) return;
    _camera.event('looks.read');
    final slots = [for (var n = 1; n <= 3; n++) await _read(ble, n)];
    if (_closed) return;
    _slots = slots;
    _camera.event('looks.slots', {
      for (final s in slots)
        'c${s.number}': {
          'name': s.name,
          'hex': BleBytes.toHex(s.data),
          'decoded': s.look != null,
        },
    });
    notifyListeners();
  }

  /// Loads [look] into slot [number] (1–3) under [name]: the data first,
  /// then the name, as GR WORLD writes them, then reads the slot back into
  /// [slots] and returns it. The camera may keep the look in a form of its
  /// own, so the slot read back can differ from [look]; the trace records
  /// whether it does. Throws [LookNotOffered], before writing anything,
  /// when the camera's model does not offer [look]'s base image; throws
  /// when a write or the read fails, or without a link ([BleException]
  /// `notConnected`).
  Future<LookSlot> load(
    int number, {
    required String name,
    required Look look,
  }) async {
    RangeError.checkValueInInterval(number, 1, 3, 'number');
    final ble = _session.ble;
    if (ble == null) {
      throw const BleException(BleErrorCode.notConnected, 'no link');
    }
    final bytes = look.toBytes();
    final camera = _body();
    if (!look.offeredBy(camera)) {
      _camera.event('looks.refused', {
        'slot': number,
        'name': name,
        'hex': BleBytes.toHex(bytes),
        'model': camera.model?.name,
        'firmware': camera.firmware,
        'reason': look.base == null
            ? 'base ${look.unknownBaseNumber} unknown'
            : '${look.base!.name} not offered by this camera',
      });
      throw LookNotOffered(base: look.base, model: camera.model);
    }
    _camera.event('looks.load', {
      'slot': number,
      'name': name,
      'hex': BleBytes.toHex(bytes),
    });
    await ble.writeImageControlData(number, look.blob);
    await ble.writeImageControlName(number, name);
    final slot = await _read(ble, number);
    _camera.event('looks.loaded', {
      'slot': number,
      'sameData': listEquals(slot.data, bytes),
      'sameName': slot.name == name,
    });
    final slots = _slots;
    if (!_closed && slots != null) {
      _slots = [
        for (final s in slots)
          if (s.number == number) slot else s,
      ];
      notifyListeners();
    }
    return slot;
  }

  static Future<LookSlot> _read(GrBleClient ble, int number) async {
    final read = await ble.readImageControl(number);
    final data = read.data.raw;
    return LookSlot(
      number: number,
      name: (read.name.value ?? '').replaceAll('\u0000', ''),
      data: Uint8List.fromList(data),
      look: switch (read.data.value) {
        final blob? => lookOf(blob),
        null => null,
      },
    );
  }

  void _close() => _closed = true;
}

/// Creates the looks of [session], judging what the camera offers by
/// [body]. Used by `CameraSession` only.
CameraLooks createCameraLooks(
  GrSession session,
  GrCameraEnvironment camera, {
  required CameraBody Function() body,
}) => CameraLooks._(session, camera, body);

/// What `CameraSession` does to its looks. Not exported.
extension CameraLooksInternals on CameraLooks {
  /// The session ended: stops notifying.
  void close() => _close();
}
