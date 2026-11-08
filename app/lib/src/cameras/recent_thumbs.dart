import 'dart:io';
import 'dart:typed_data';

import '../library/camera_images.dart';
import '../library/image_orientation.dart';
import '../library/library_model.dart';
import '../library/shot.dart';

/// A thumbnail kept from a camera's last visit, with the EXIF orientation
/// that shows it upright.
typedef RecentThumb = ({Uint8List bytes, int orientation});

/// Up to [count] images of [serial]'s newest shots that the Library grid
/// has on disk ([Shot.gridSize]), newest first. Shots whose image was
/// never loaded are skipped; nothing is fetched.
Future<List<RecentThumb>> loadRecentThumbs(
  Directory cacheDir,
  String serial, {
  int count = 4,
}) async {
  final listing = await readCachedListing(cacheDir, serial);
  if (listing == null) return const [];
  final thumbs = <RecentThumb>[];
  for (final shot in groupShots(listing.files)) {
    if (thumbs.length == count) break;
    final file = shot.primary;
    final Uint8List bytes;
    try {
      bytes = await CameraImages.diskFile(
        cacheDir,
        serial,
        file,
        shot.gridSize,
      ).readAsBytes();
    } on FileSystemException {
      continue;
    }
    thumbs.add((
      bytes: bytes,
      orientation: orientationToApply(
        readJpegLayout(bytes),
        listing.info[file.key]?.orientation,
      ),
    ));
  }
  return thumbs;
}
