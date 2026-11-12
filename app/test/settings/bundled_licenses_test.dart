import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grlab/src/settings/bundled_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the photo credits name every photo and video the app ships', () async {
    final credits = await bundledLicenses().firstWhere(
      (entry) => entry.packages.contains('Unsplash'),
    );
    final text = credits.paragraphs.map((p) => p.text).join('\n');

    // A scene's thumbnail, view and full size are one photo: `land01`.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final scenes = manifest
        .listAssets()
        .where((asset) => asset.endsWith('.jpg') || asset.endsWith('.mov'))
        .map(
          (asset) => asset.replaceFirst(
            RegExp(r'(_(full|view|thumb))?\.(jpg|mov)$'),
            '',
          ),
        )
        .toSet();

    expect(scenes, containsAll(['assets/welcome', 'assets/demo/clip']));
    for (final scene in scenes) {
      expect(text, contains(scene), reason: '$scene has no credit');
    }
  });
}
