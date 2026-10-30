import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/ui/training_visible_poster_preload.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

class _RecordingAssets extends CachingAssetBundle {
  final loads = <String>[];
  final screenDecodeStarted = Completer<void>();
  final marker = ByteData.sublistView(Uint8List.fromList([1, 2, 3]));

  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    if (key == 'passthrough.bin') return marker;
    if (key.contains('/standing/') &&
        loads.where((asset) => asset == key).length == 2 &&
        !screenDecodeStarted.isCompleted) {
      screenDecodeStarted.complete();
    }
    return rootBundle.load(key);
  }
}

Future<ImageInfo> _decodedImage(ImageProvider provider, BuildContext context) {
  final stream = provider.resolve(createLocalImageConfiguration(context));
  final completer = Completer<ImageInfo>();
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      completer.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

void main() {
  late coach.PoseHubAppTestCatalog catalog;
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());

  testWidgets(
    'bundle observes actual SDK still loads and warms the outer width key',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bundle = _RecordingAssets();
      final action = catalog.semanticCompleteActions.first;
      final asset =
          'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${action.id}.webp';
      late BuildContext outer;
      late BuildContext inner;
      late AssetBundle observed;
      var showImage = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultAssetBundle(
            bundle: bundle,
            child: Builder(
              builder: (context) {
                outer = context;
                return TrainingVisiblePosterPreload(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      inner = context;
                      observed = DefaultAssetBundle.of(context);
                      return showImage
                          ? PoseHubStandingImage(action: action)
                          : const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(bundle.loads.where((key) => key.contains('/standing/')), isEmpty);
      final bytes = await observed.load('passthrough.bin');
      expect(
        identical(bytes, bundle.marker),
        isTrue,
        reason: 'The SDK receives the unchanged delegated bytes',
      );
      expect(bundle.loads, ['passthrough.bin']);
      final provider = TrainingPosterImages.provider(asset, 390) as ResizeImage;
      final outerKey = await provider.obtainKey(
        createLocalImageConfiguration(outer),
      );
      expect(
        PaintingBinding.instance.imageCache.containsKey(outerKey),
        isFalse,
      );
      update(() => showImage = true);
      await tester.pump();
      // Drain the actual bundled WebP decode while retaining the finite fake
      // animation clock. No replacement bytes, image-cache mutation or SDK UI.
      final imageInfo = await tester.runAsync(() async {
        // Wait for the observer to initiate the outer decode itself. Resolving
        // the same key afterward only waits for those already-requested pixels.
        await bundle.screenDecodeStarted.future.timeout(
          const Duration(seconds: 5),
        );
        final imageInfo = await _decodedImage(provider, outer);
        final native = await _decodedImage(AssetImage(asset), inner);
        native.dispose();
        return imageInfo;
      });
      await tester.pump();
      expect(
        bundle.loads.where((key) => key == asset).length,
        2,
        reason: 'Visible native SDK key plus one surrounding screen-width key',
      );
      expect(PaintingBinding.instance.imageCache.containsKey(outerKey), isTrue);
      expect(outerKey, isA<ResizeImageKey>());
      expect(provider.width, 390);
      final observedKey = await provider.obtainKey(
        createLocalImageConfiguration(inner),
      );
      expect(observedKey, isNot(outerKey));
      expect(
        PaintingBinding.instance.imageCache.containsKey(observedKey),
        isFalse,
        reason: 'Only the outer route bundle gets the resized decode',
      );
      expect(find.byType(PoseHubStandingImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(imageInfo!.image.width, 390);
      imageInfo.dispose();
      await tester.runAsync(() async {
        final buffer = await observed.loadBuffer(asset);
        buffer.dispose();
      });
      await tester.pump();
      expect(
        bundle.loads.where((key) => key == asset).length,
        3,
        reason: 'Repeated real loadBuffer does not start another warm decode',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('non-standing assets never trigger a training decode', (
    tester,
  ) async {
    final bundle = _RecordingAssets();
    late AssetBundle observed;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: bundle,
          child: TrainingVisiblePosterPreload(
            child: Builder(
              builder: (context) {
                observed = DefaultAssetBundle.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    final buffer = await tester.runAsync(
      () => observed.loadBuffer('passthrough.bin'),
    );
    buffer!.dispose();
    await tester.pump();
    expect(bundle.loads, ['passthrough.bin']);
    expect(tester.takeException(), isNull);
  });
}
