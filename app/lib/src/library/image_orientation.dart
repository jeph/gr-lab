import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// What a JPEG's header says about its layout: the stored (encoded) pixel
/// size and the EXIF Orientation tag, if there is one.
@immutable
final class JpegLayout {
  const JpegLayout({
    required this.width,
    required this.height,
    this.exifOrientation,
  });

  /// Size of the encoded pixels, before any EXIF rotation.
  final int width;
  final int height;

  /// The IFD0 Orientation tag as written, which may be out of range.
  final int? exifOrientation;

  /// The image decoder turns the pixels itself: Flutter's built-in JPEG
  /// decoder applies Orientation 2–8 (engine `image_generator.cc`,
  /// `BuiltinSkiaCodecImageGenerator`) and treats other values as 1.
  bool get decoderOrients => _isTurning(exifOrientation);
}

/// Reads the JPEG header in [bytes] up to the frame header (SOFn). Null
/// when [bytes] is not a JPEG or its header is cut short or malformed.
JpegLayout? readJpegLayout(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  int? orientation;
  var i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] != 0xFF) return null;
    final marker = bytes[i + 1];
    if (marker == 0xFF) {
      i++; // Fill byte.
      continue;
    }
    // Start of scan or end of image before any frame header.
    if (marker == 0xDA || marker == 0xD9) return null;
    final length = bytes[i + 2] << 8 | bytes[i + 3];
    final start = i + 4;
    final end = i + 2 + length;
    if (length < 2 || end > bytes.length) return null;
    if (_isFrameHeader(marker)) {
      if (end - start < 5) return null;
      return JpegLayout(
        height: bytes[start + 1] << 8 | bytes[start + 2],
        width: bytes[start + 3] << 8 | bytes[start + 4],
        exifOrientation: orientation,
      );
    }
    if (marker == 0xE1) orientation ??= _exifOrientation(bytes, start, end);
    i = end;
  }
  return null;
}

/// SOF0–SOF15, which are C0–CF without DHT (C4), JPG (C8) and DAC (CC).
bool _isFrameHeader(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;

/// The Orientation tag (0x0112) in the IFD0 of an `Exif\0\0` APP1 payload
/// spanning `bytes[start, end)`.
int? _exifOrientation(Uint8List bytes, int start, int end) {
  const exif = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
  if (end - start < exif.length + 8) return null;
  for (var k = 0; k < exif.length; k++) {
    if (bytes[start + k] != exif[k]) return null;
  }
  final tiff = ByteData.sublistView(bytes, start + exif.length, end);
  final endian = switch ((tiff.getUint8(0), tiff.getUint8(1))) {
    (0x49, 0x49) => Endian.little,
    (0x4D, 0x4D) => Endian.big,
    _ => null,
  };
  if (endian == null || tiff.getUint16(2, endian) != 42) return null;
  final ifd = tiff.getUint32(4, endian);
  if (ifd + 2 > tiff.lengthInBytes) return null;
  final count = tiff.getUint16(ifd, endian);
  for (var e = 0; e < count; e++) {
    final entry = ifd + 2 + e * 12;
    if (entry + 12 > tiff.lengthInBytes) return null;
    if (tiff.getUint16(entry, endian) != 0x0112) continue;
    // SHORT, one value, held in the first two bytes of the value field.
    if (tiff.getUint16(entry + 2, endian) != 3) return null;
    return tiff.getUint16(entry + 8, endian);
  }
  return null;
}

bool _isTurning(int? orientation) =>
    orientation != null && orientation >= 2 && orientation <= 8;

/// Orientations 5–8 show the image with width and height swapped.
bool orientationSwapsAxes(int orientation) =>
    orientation >= 5 && orientation <= 8;

/// The EXIF orientation (1–8) to apply with [ExifOrientation] so that an
/// image with header [layout] shows upright, given the camera's `/info`
/// [orientation] for the shot.
///
/// A GR stores every frame in sensor (landscape) layout and says how it
/// was held in `/info` and in the full JPEG's Orientation tag; the
/// thumbnail and preview embedded in a GR IV HDF file are unrotated JPEGs
/// without EXIF. So:
/// - bytes whose own tag the decoder applies need nothing more, or they
///   would turn twice;
/// - an image that is already taller than wide was turned by whoever made
///   it, so a quarter turn would lay it on its side again;
/// - an explicit tag 1 says the pixels are already upright, and is
///   trusted, except for a landscape frame of a shot held on its side
///   (5–8): that frame visibly is not upright, so the tag is a default;
/// - otherwise the image gets [orientation]; a missing or unknown value
///   (outside 1–8) shows the image as stored.
int orientationToApply(JpegLayout? layout, int? orientation) {
  if (!_isTurning(orientation)) return 1;
  final o = orientation!;
  if (layout != null) {
    if (layout.decoderOrients) return 1;
    final swaps = orientationSwapsAxes(o);
    if (swaps && layout.height > layout.width) return 1;
    if (layout.exifOrientation == 1 &&
        !(swaps && layout.width > layout.height)) {
      return 1;
    }
  }
  return o;
}

/// How much an image with header [layout], turned by [orientation] (from
/// [orientationToApply]), is enlarged when shown with [fit] in a box of
/// [box] physical pixels: above 1 when it has fewer pixels than the box
/// shows. 1 when either is unknown.
double enlargement(JpegLayout? layout, int orientation, Size box, BoxFit fit) {
  if (layout == null || layout.width == 0 || layout.height == 0) return 1;
  if (!box.width.isFinite || !box.height.isFinite || box.isEmpty) return 1;
  final (w, h) = _decoded(layout);
  final (sw, sh) = orientationSwapsAxes(orientation) ? (h, w) : (w, h);
  final sx = box.width / sw, sy = box.height / sh;
  return fit == BoxFit.cover ? math.max(sx, sy) : math.min(sx, sy);
}

/// `cacheWidth` for the image [enlargement] describes: the decoded width
/// that still backs every shown pixel. Null when the image has no more
/// pixels than that, so it decodes as it is.
int? decodeWidth(JpegLayout? layout, int orientation, Size box, BoxFit fit) {
  final scale = enlargement(layout, orientation, box, fit);
  if (layout == null || scale >= 1) return null;
  final (w, _) = _decoded(layout);
  return (w * scale).ceil().clamp(1, w);
}

/// Size of the decoded image: stored, or turned when the decoder applies
/// the image's own tag ([JpegLayout.decoderOrients]); `cacheWidth` counts
/// these pixels.
(int, int) _decoded(JpegLayout layout) =>
    layout.decoderOrients && orientationSwapsAxes(layout.exifOrientation!)
    ? (layout.height, layout.width)
    : (layout.width, layout.height);

/// Shows [child], an image in stored layout, the way EXIF [orientation]
/// (1–8) says: mirrored left to right first where the value says so, then
/// turned clockwise. Turns swap the layout axes as [RotatedBox] does, so
/// the box takes the upright aspect. Other values leave [child] as it is.
class ExifOrientation extends StatelessWidget {
  const ExifOrientation({
    super.key,
    required this.orientation,
    required this.child,
  });

  final int orientation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (mirror, quarterTurns) = switch (orientation) {
      2 => (true, 0),
      3 => (false, 2),
      4 => (true, 2),
      5 => (true, 3),
      6 => (false, 1),
      7 => (true, 1),
      8 => (false, 3),
      _ => (false, 0),
    };
    // Same shape for every value, so a change keeps the child's state.
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Transform.flip(flipX: mirror, child: child),
    );
  }
}
