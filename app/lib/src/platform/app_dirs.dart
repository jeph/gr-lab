import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent data in application support (never purged by the OS, never
/// backed up: `android:allowBackup`, `AppDelegate.excludeAppDataFromBackup`)
/// and disposable data in the app cache directory. Both are created when
/// missing; iOS does not create application support until asked.
Future<({Directory data, Directory cache})> appDirectories() async {
  final data = await getApplicationSupportDirectory();
  final cache = await getApplicationCacheDirectory();
  await data.create(recursive: true);
  await cache.create(recursive: true);
  return (data: data, cache: cache);
}
