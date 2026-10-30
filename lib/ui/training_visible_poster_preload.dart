import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'training_poster_image.dart';

/// Observes the SDK's actual visible still-image requests without changing
/// its grid, assets or image renderer. The route uses the surrounding bundle,
/// so its screen-width decode is warmed with that exact same cache key.
class TrainingVisiblePosterPreload extends StatefulWidget {
  const TrainingVisiblePosterPreload({super.key, required this.child});

  final Widget child;

  @override
  State<TrainingVisiblePosterPreload> createState() =>
      _TrainingVisiblePosterPreloadState();
}

class _TrainingVisiblePosterPreloadState
    extends State<TrainingVisiblePosterPreload> {
  AssetBundle? _parent;
  AssetBundle? _observed;
  int? _width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = DefaultAssetBundle.of(context);
    final width = TrainingPosterImages.decodeWidth(context);
    if (identical(_parent, parent) && _width == width) return;
    _parent = parent;
    _width = width;
    _observed = _VisibleStandingAssetBundle(parent, (asset) {
      if (!mounted) return;
      // This State's context is outside the observing bundle. Prewarming can
      // never recursively observe itself or populate a route-incompatible key.
      unawaited(TrainingPosterImages.precacheAsset(context, asset));
    });
  }

  @override
  Widget build(BuildContext context) =>
      DefaultAssetBundle(bundle: _observed!, child: widget.child);
}

class _VisibleStandingAssetBundle extends CachingAssetBundle {
  _VisibleStandingAssetBundle(this.parent, this.onLoaded);

  final AssetBundle parent;
  final ValueChanged<String> onLoaded;
  final _seen = <String>{};

  @override
  Future<ByteData> load(String key) async {
    final bytes = await parent.load(key);
    if (key.startsWith(
          'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/',
        ) &&
        key.endsWith('.webp') &&
        _seen.add(key)) {
      onLoaded(key);
    }
    return bytes;
  }
}
