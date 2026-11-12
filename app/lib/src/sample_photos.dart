import 'package:flutter/foundation.dart';
import 'package:gr_camera/gr_camera.dart';

/// One of GR Photo's own photos: a picture of the welcome screen and a photo
/// the look editor can preview a look on.
@immutable
final class SamplePhoto {
  const new(this.asset, this.base);

  /// The bundled JPEG: 2064 pixels on its long side (a third of a GR IV
  /// frame), stored upright in sRGB, with none of the camera's metadata.
  final String asset;

  /// The base image the camera developed the photo with, as the maker
  /// note of the camera's file names it
  /// (research/image-control-processing.md §10.1). A photo whose file does
  /// not say is not a sample: its look could not be undone.
  final LookBase base;

  /// The look the photo was developed with: [base] with every adjustment
  /// at 0 \[inferred\], as the file does not say what they were in a form
  /// GR Photo reads.
  Look get look => Look.onBase(base);
}

/// GR Photo's own photos, taken with a GR IV and a GR IV HDF, in the order
/// the welcome screen shows them and the look editor offers them. The
/// first is taller than wide.
const List<SamplePhoto> samplePhotos = [
  SamplePhoto('assets/samples/sample01.jpg', LookBase.positiveFilm),
  SamplePhoto('assets/samples/sample02.jpg', LookBase.positiveFilm),
  SamplePhoto('assets/samples/sample03.jpg', LookBase.positiveFilm),
  SamplePhoto('assets/samples/sample04.jpg', LookBase.negativeFilm),
  SamplePhoto('assets/samples/sample05.jpg', LookBase.positiveFilm),
  SamplePhoto('assets/samples/sample06.jpg', LookBase.positiveFilm),
];
