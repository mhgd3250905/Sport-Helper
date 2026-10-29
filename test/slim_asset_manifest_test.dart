import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'compiled AssetManifest retains static media and excludes every MP4',
    () async {
      final assets = (await AssetManifest.loadFromAssetBundle(
        rootBundle,
      )).listAssets();
      expect(
        assets.where((path) => path.toLowerCase().endsWith('.mp4')),
        isEmpty,
      );
      expect(
        assets.where((path) => path.startsWith('assets/brand/source/')),
        isEmpty,
      );
      expect(assets.where((path) => path.startsWith('design/')), isEmpty);
      for (final path in [
        'assets/training_media/v0.3.0-app/app-manifest.json',
        'assets/training_media/v0.3.0-app/assets-index.json',
        'assets/training_media/v0.3.0-app/packages/builtin.json',
        'assets/training_media/v0.3.0-app/packages/realistic-dark.json',
        'assets/training_media/v0.3.0-app/packages/realistic-light.json',
        'assets/training_media/v0.3.0-app/theme-lossy/dark/first-frames/h-squat.webp',
        'assets/training_media/v0.3.0-app/theme-lossy/light/first-frames/h-squat.webp',
        'assets/voice_lc32/v1/manifest.json',
      ]) {
        expect(assets, contains(path));
        expect((await rootBundle.load(path)).lengthInBytes, greaterThan(0));
      }
    },
  );
}
