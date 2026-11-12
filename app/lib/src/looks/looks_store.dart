import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grphoto/src/data/json_file.dart';

/// A look in the user's library: an Image Control (base image and
/// parameters) under a name the user chose, with the photo it came from.
@immutable
final class SavedLook {
  const new({
    required this.id,
    required this.name,
    required this.data,
    required this.created,
    this.source,
    this.photoData,
    this.photoOrientation,
  });

  factory fromJson(Map<String, Object?> json) => SavedLook(
    id: json['id']! as String,
    name: json['name']! as String,
    data: base64Decode(json['data']! as String),
    created: DateTime.parse(json['created']! as String),
    source: json['source'] as String?,
    photoData: switch (json['photoData']) {
      final String data => base64Decode(data),
      _ => null,
    },
    photoOrientation: (json['photoOrientation'] as num?)?.toInt(),
  );

  final String id;
  final String name;

  /// The Image Control blob, as the camera's slots and `/imgctrl` carry it.
  final Uint8List data;
  final DateTime created;

  /// Where the look came from, as the list shows it ("From …"): the file
  /// name of the camera photo it was saved from, or the slot (`C1`) it was
  /// read from; null for a look made in the app.
  final String? source;

  /// The Image Control blob the look's photo was developed with, which
  /// stays as it was when the look is edited; null for a look without a
  /// photo, and for one saved before GR Photo kept this.
  final Uint8List? photoData;

  /// The EXIF orientation (1–8) that shows the look's photo upright: a
  /// camera stores its previews in the sensor's layout however it was
  /// held (`orientationToApply`). Null shows the photo as stored: a look
  /// without a photo, or one saved before GR Photo kept this.
  final int? photoOrientation;

  /// [data] read as a look; null when it is not one.
  Look? get look => Look.fromBytes(data);

  /// The look the photo was developed with ([photoData]), for showing the
  /// photo under other looks; null when it is not known.
  Look? get photoLook => switch (photoData) {
    final data? => Look.fromBytes(data),
    null => null,
  };

  /// What the look does to a picture, for telling whether two looks are
  /// the same ([LookSettings]); null when [data] is not a look.
  LookSettings? get settings => look?.settings;

  SavedLook copyWith({String? name, Uint8List? data}) => SavedLook(
    id: id,
    name: name ?? this.name,
    data: data ?? this.data,
    created: created,
    source: source,
    photoData: photoData,
    photoOrientation: photoOrientation,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'data': base64Encode(data),
    'created': created.toIso8601String(),
    'source': ?source,
    'photoData': ?switch (photoData) {
      final data? => base64Encode(data),
      null => null,
    },
    'photoOrientation': ?photoOrientation,
  };
}

/// What a look shares with the saved look that keeps it from being saved.
enum LookConflictKind {
  /// The name and the settings: the look is already saved.
  nameAndSettings,

  /// The settings, under another name.
  settings,

  /// The name, with other settings.
  name,
}

/// A look was not saved because the library already has [other], which
/// shares its name, its settings ([SavedLook.settings]) or both: no two
/// saved looks may share either.
final class LookConflict implements Exception {
  const new(this.kind, this.other);

  final LookConflictKind kind;

  /// The saved look in the way.
  final SavedLook other;

  @override
  String toString() => 'LookConflict(${kind.name}, ${other.name})';
}

/// The user's looks, persisted as `looks.json` in the app data directory,
/// with each look's photo as `looks/<id>.jpg` beside it. Newest first.
final class LooksStore extends ChangeNotifier {
  new _(this._file, this._photos);

  static Future<LooksStore> load(Directory dataDir) async {
    final store = LooksStore._(
      JsonFile(File('${dataDir.path}/looks.json')),
      Directory('${dataDir.path}/looks'),
    );
    final json = await store._file.read();
    final list = json?['looks'];
    if (list is List<Object?>) {
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        try {
          store._looks.add(SavedLook.fromJson(item));
        } on Object {
          // A look this version cannot read is left out rather than
          // failing the whole library.
        }
      }
    }
    return store;
  }

  final JsonFile _file;
  final Directory _photos;
  final List<SavedLook> _looks = [];
  Future<void> _queue = Future.value();

  List<SavedLook> get looks => List.unmodifiable(_looks);

  SavedLook? byId(String id) {
    for (final l in _looks) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// The photo kept for [look], if it has one.
  File? photoOf(SavedLook look) {
    final file = File('${_photos.path}/${look.id}.jpg');
    return file.existsSync() ? file : null;
  }

  /// Adds a look named [name] holding [data], from [source] (see
  /// [SavedLook.source]), with [photo] (a JPEG) of the camera photo it was
  /// saved from, which [data] is therefore the look of
  /// ([SavedLook.photoData]) and which [photoOrientation] shows upright
  /// ([SavedLook.photoOrientation]). Throws [LookConflict], storing
  /// nothing, when a saved look has its name or its settings. Completes
  /// once the look is on disk; when it cannot be written, the look is
  /// taken out again and the [FileSystemException] is rethrown, so saving
  /// again stores it once.
  Future<SavedLook> add({
    required String name,
    required Uint8List data,
    String? source,
    Uint8List? photo,
    int? photoOrientation,
  }) => _serial(() async {
    final now = DateTime.now();
    final look = SavedLook(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      name: name,
      data: data,
      created: now,
      source: source,
      photoData: photo == null ? null : data,
      photoOrientation: photo == null ? null : photoOrientation,
    );
    final conflict = _conflictOf(look);
    if (conflict != null) throw conflict;
    final photoFile = File('${_photos.path}/${look.id}.jpg');
    try {
      if (photo != null) {
        await _photos.create(recursive: true);
        await photoFile.writeAsBytes(photo);
      }
      _looks.insert(0, look);
      await _write();
    } on FileSystemException {
      if (_looks.remove(look)) notifyListeners();
      if (photoFile.existsSync()) await photoFile.delete();
      rethrow;
    }
    return look;
  });

  /// Replaces the look with [look]'s id. Throws [LookConflict], changing
  /// nothing, when another saved look has its name or its settings.
  /// Completes once it is on disk; when it cannot be written, the earlier
  /// version comes back and the [FileSystemException] is rethrown.
  Future<void> update(SavedLook look) => _serial(() async {
    final i = _looks.indexWhere((l) => l.id == look.id);
    if (i < 0) return;
    final conflict = _conflictOf(look);
    if (conflict != null) throw conflict;
    final before = _looks[i];
    _looks[i] = look;
    try {
      await _write();
    } on FileSystemException {
      _looks[i] = before;
      notifyListeners();
      rethrow;
    }
  });

  /// The saved look, other than [look] itself, that keeps [look] from being
  /// saved. One with both its name and its settings comes first: the look
  /// already exists. Then one with its settings, which no other name gets
  /// around, then one with its name.
  LookConflict? _conflictOf(SavedLook look) {
    final settings = look.settings;
    SavedLook? sameSettings;
    SavedLook? sameName;
    for (final other in _looks) {
      if (other.id == look.id) continue;
      final hasName = other.name == look.name;
      final hasSettings = settings != null && other.settings == settings;
      if (hasName && hasSettings) {
        return LookConflict(LookConflictKind.nameAndSettings, other);
      }
      if (hasSettings) sameSettings ??= other;
      if (hasName) sameName ??= other;
    }
    if (sameSettings != null) {
      return LookConflict(LookConflictKind.settings, sameSettings);
    }
    if (sameName != null) return LookConflict(LookConflictKind.name, sameName);
    return null;
  }

  /// Removes [look]. Completes once the removal is on disk; when it cannot
  /// be written, the look comes back and the [FileSystemException] is
  /// rethrown. Its photo is deleted only after a successful write.
  Future<void> delete(SavedLook look) => _serial(() async {
    final i = _looks.indexWhere((l) => l.id == look.id);
    if (i < 0) return;
    final removed = _looks.removeAt(i);
    try {
      await _write();
    } on FileSystemException {
      _looks.insert(i, removed);
      notifyListeners();
      rethrow;
    }
    final photo = File('${_photos.path}/${look.id}.jpg');
    if (photo.existsSync()) await photo.delete();
  });

  /// Runs [change] once every earlier change has finished, so a change, its
  /// write and its undo never interleave with another's: an undo then
  /// always restores what is on disk. The returned future fails when
  /// [change] does; the queue carries on.
  Future<T> _serial<T>(Future<T> Function() change) {
    final done = _queue.then((_) => change());
    _queue = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<void> _write() {
    notifyListeners();
    return _file.write({
      'looks': [for (final l in _looks) l.toJson()],
    });
  }

  /// Completes when every change so far has finished, whether or not it
  /// reached disk.
  Future<void> flush() => _queue;
}
