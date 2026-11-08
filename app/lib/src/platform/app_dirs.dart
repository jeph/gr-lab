import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent data in application support (backed up, never purged by the
/// OS) and disposable data in the app cache directory. Both are created when
/// missing; iOS does not create application support until asked.
Future<({Directory data, Directory cache})> appDirectories() async {
  final data = await getApplicationSupportDirectory();
  final cache = await getApplicationCacheDirectory();
  await data.create(recursive: true);
  await cache.create(recursive: true);
  return (data: data, cache: cache);
}
