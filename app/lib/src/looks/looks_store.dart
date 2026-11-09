import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

import 'package:grlab/src/data/json_file.dart';

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
  });

  factory fromJson(Map<String, Object?> json) => SavedLook(
    id: json['id']! as String,
    name: json['name']! as String,
    data: base64Decode(json['data']! as String),
    created: DateTime.parse(json['created']! as String),
    source: json['source'] as String?,
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

  /// [data] decoded; null when it is not a blob the camera layer can read.
  BleImageControlBlob? get look => imageControlFromBytes(data);

  SavedLook copyWith({String? name, Uint8List? data}) => SavedLook(
    id: id,
    name: name ?? this.name,
    data: data ?? this.data,
    created: created,
    source: source,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'data': base64Encode(data),
    'created': created.toIso8601String(),
    'source': ?source,
  };
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
  Future<void> _pending = Future.value();

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
  /// saved from. Completes once the look is on disk; when it cannot be
  /// written, the look is taken out again and the [FileSystemException] is
  /// rethrown, so saving again does not leave a duplicate.
  Future<SavedLook> add({
    required String name,
    required Uint8List data,
    String? source,
    Uint8List? photo,
  }) async {
    final now = DateTime.now();
    final look = SavedLook(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      name: name,
      data: data,
      created: now,
      source: source,
    );
    final photoFile = File('${_photos.path}/${look.id}.jpg');
    try {
      if (photo != null) {
        await _photos.create(recursive: true);
        await photoFile.writeAsBytes(photo);
      }
      _looks.insert(0, look);
      await _save();
    } on FileSystemException {
      if (_looks.remove(look)) notifyListeners();
      if (photoFile.existsSync()) await photoFile.delete();
      rethrow;
    }
    return look;
  }

  /// Replaces the look with [look]'s id. Completes once it is on disk; when
  /// it cannot be written, the earlier version comes back and the
  /// [FileSystemException] is rethrown.
  Future<void> update(SavedLook look) async {
    final i = _looks.indexWhere((l) => l.id == look.id);
    if (i < 0) return;
    final before = _looks[i];
    _looks[i] = look;
    try {
      await _save();
    } on FileSystemException {
      final now = _looks.indexWhere((l) => l.id == look.id);
      if (now >= 0) _looks[now] = before;
      notifyListeners();
      rethrow;
    }
  }

  /// Removes [look]. Completes once the removal is on disk; when it cannot
  /// be written, the look comes back and the [FileSystemException] is
  /// rethrown. Its photo is deleted only after a successful write.
  Future<void> delete(SavedLook look) async {
    final i = _looks.indexWhere((l) => l.id == look.id);
    if (i < 0) return;
    final removed = _looks.removeAt(i);
    try {
      await _save();
    } on FileSystemException {
      _looks.insert(math.min(i, _looks.length), removed);
      notifyListeners();
      rethrow;
    }
    final photo = File('${_photos.path}/${look.id}.jpg');
    if (photo.existsSync()) await photo.delete();
  }

  /// Writes every look after the writes already queued. The returned future
  /// fails when this write does; the queue itself carries on, so one failed
  /// write does not stop later ones.
  Future<void> _save() {
    notifyListeners();
    final snapshot = {
      'looks': [for (final l in _looks) l.toJson()],
    };
    final write = _pending.then((_) => _file.write(snapshot));
    _pending = write.catchError((Object _) {});
    return write;
  }

  /// Completes when every write so far has finished, whether or not it
  /// succeeded.
  Future<void> flush() => _pending;
}
