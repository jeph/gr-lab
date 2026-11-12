import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/library/image_orientation.dart';
import 'package:grlab/src/sample_photos.dart';

/// The application segments (APP0–APP15) and comments ahead of the picture
/// data of [jpeg], as marker and length: where EXIF, XMP, a colour profile
/// and a maker note would be.
List<(int, int)> _segmentsOf(Uint8List jpeg) {
  final found = <(int, int)>[];
  var at = 2;
  while (at + 4 <= jpeg.length && jpeg[at] == 0xFF && jpeg[at + 1] != 0xDA) {
    final marker = jpeg[at + 1];
    final length = jpeg[at + 2] << 8 | jpeg[at + 3];
    if (marker >= 0xE0 && marker <= 0xEF || marker == 0xFE) {
      found.add((marker, length));
    }
    at += 2 + length;
  }
  return found;
}

void main() {
  test("the sample photos carry none of their camera's metadata, and are "
      'stored upright', () {
    final listed = {for (final photo in samplePhotos) photo.asset};
    expect(listed, hasLength(samplePhotos.length));
    // Every file of the folder is bundled, listed here or not.
    final bundled = Directory('assets/samples').listSync().whereType<File>();
    expect({for (final file in bundled) file.path}, listed);

    for (final asset in listed) {
      final bytes = File(asset).readAsBytesSync();
      // A JFIF header and nothing else: no EXIF, so no serial number,
      // location, date or maker note.
      expect(_segmentsOf(bytes), [(0xE0, 16)], reason: asset);
      expect(readJpegLayout(bytes)!.exifOrientation, isNull, reason: asset);
    }
  });
}
