import 'dart:convert';
import 'dart:typed_data';

import 'package:gr_protocol/gr_protocol.dart';

import 'config.dart';

/// A decodable 16×16 grey baseline JPEG.
final Uint8List _tinyJpeg = base64.decode(
  '/9j/4AAQSkZJRgABAgAAAQABAAD/2wBDAAgoKC8oLzc3Nzc3N0E8QUNDQ0FBQUFDQ0NISEhV'
  'VVVISEhDQ0hIUFBVVVxfXFdXVVdfX2RkZHh4c3OMjJGsrM//xABLAAEBAAAAAAAAAAAAAAAA'
  'AAAAAgEBAAAAAAAAAAAAAAAAAAAAAxABAAAAAAAAAAAAAAAAAAAAABEBAAAAAAAAAAAAAAAA'
  'AAAAAP/AABEIABAAEAMBIgACEQADEQD/2gAMAwEAAhEDEQA/AJAIN//Z',
);

/// Media for tests: every preview size is a tiny valid JPEG; full files
/// have their real format's magic bytes and a deterministic, per-file body
/// around [jpegBytes] / [rawBytes] / [movieBytes] long. Full JPEGs decode
/// (the padding follows the EOI marker); DNG and MOV bodies do not.
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
    _ => _tinyJpeg,
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
