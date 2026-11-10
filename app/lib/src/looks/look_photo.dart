import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The quality the copy of a photo kept with a look is encoded at: a file
/// of a few hundred kilobytes whose compression does not show under a look
/// \[design\].
const int _quality = 90;

/// [jpeg] as the picture to keep with a look saved from it: no more than
/// [longSide] pixels on its long side, since a camera's full file is many
/// times what a look's preview is worked out on. [jpeg] itself when it is
/// no larger than that; null when it does not decode.
///
/// A smaller copy holds the pixels as Flutter's decoder lays [jpeg] out,
/// turned by its EXIF Orientation tag if it has one, and no tags of its
/// own: what shows [jpeg] upright shows the copy upright.
Future<Uint8List?> lookPhotoOf(Uint8List jpeg, {required int longSide}) async {
  ui.Image? picture;
  try {
    var smaller = false;
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(jpeg),
      getTargetSize: (width, height) {
        final scale = longSide / math.max(width, height);
        if (scale >= 1) return const ui.TargetImageSize();
        smaller = true;
        return ui.TargetImageSize(
          width: math.max(1, (width * scale).round()),
          height: math.max(1, (height * scale).round()),
        );
      },
    );
    try {
      if (!smaller) return jpeg;
      picture = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    final pixels = await picture.toByteData();
    if (pixels == null) return null;
    return await compute(_encoded, (
      pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
      picture.width,
      picture.height,
    ));
  } on Exception {
    // Not an image the decoder reads.
    return null;
  } finally {
    picture?.dispose();
  }
}

/// A JPEG of a picture given as its RGBA pixels, its width and its height.
/// Flutter has no JPEG encoder of its own.
Uint8List _encoded((Uint8List, int, int) job) {
  final (rgba, width, height) = job;
  return img.encodeJpg(
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
    ),
    quality: _quality,
  );
}
