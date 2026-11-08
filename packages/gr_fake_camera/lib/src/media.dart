import 'dart:convert';
import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';

import 'config.dart';

/// A decodable 24×16 grey baseline JPEG without EXIF: a frame in the
/// camera's stored (landscape, 3:2) layout.
final Uint8List _tinyJpeg = base64.decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9'
  'PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/wAALCAAQABgBAREA/8QAFAAB'
  'AAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AAA//2Q==',
);

/// [jpeg] with an EXIF segment right after its SOI marker whose IFD0 holds
/// only Orientation = [orientation], laid out as a GR IV HDF writes it
/// (APP1 first, little-endian TIFF, IFD0 at offset 8).
Uint8List withExifOrientation(Uint8List jpeg, int orientation) {
  if (jpeg.length < 2 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    throw ArgumentError.value(jpeg, 'jpeg', 'not a JPEG');
  }
  final payload = [
    ...'Exif'.codeUnits, 0, 0, //
    0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // TIFF header (II)
    0x01, 0x00, // one IFD0 entry:
    0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, // 0x0112 SHORT ×1
    orientation & 0xFF, orientation >> 8 & 0xFF, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // no IFD1
  ];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF, 0xD8, //
    0xFF, 0xE1, length >> 8, length & 0xFF, ...payload,
    ...jpeg.sublist(2),
  ]);
}

/// Media for tests, oriented as a GR stores it (see [FakePhoto.orientation]):
/// every preview size is a tiny landscape JPEG without EXIF; full files
/// have their real format's magic bytes and a deterministic, per-file body
/// around [jpegBytes] / [rawBytes] / [movieBytes] long. Full JPEGs decode
/// (the padding follows the EOI marker) and carry the photo's orientation
/// as an EXIF tag unless it is 1 or null; DNG and MOV bodies do not decode.
FakeMediaSource syntheticMedia({
  int jpegBytes = 300 * 1024,
  int rawBytes = 600 * 1024,
  int movieBytes = 1024 * 1024,
}) => (photo, size) async {
  if (size != GrImageSize.full) return Uint8List.fromList(_tinyJpeg);
  final seed = photo.toString().codeUnits.fold(
    17,
    (h, c) => (h * 31 + c) & 0x7fffffff,
  );
  final jitter = seed & 0x7fff;
  final List<int> head = switch (photo.extension) {
    'DNG' => const [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00],
    'MOV' => const [0, 0, 0, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74, 0x20],
    _ => switch (photo.orientation) {
      null || 1 => _tinyJpeg,
      final o => withExifOrientation(_tinyJpeg, o),
    },
  };
  final length =
      switch (photo.extension) {
        'DNG' => rawBytes,
        'MOV' => movieBytes,
        _ => jpegBytes,
      } +
      jitter;
  final bytes = Uint8List(length < head.length ? head.length : length)
    ..setAll(0, head);
  var x = seed & 0x7fffffff;
  for (var i = head.length; i < bytes.length; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    bytes[i] = x >> 16;
  }
  return bytes;
};
