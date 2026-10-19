// Copied from 3D-Body@a83a0f4 (branch feat/hiplab-flavor) `app/lib/data/drill_media.dart`.
// HipLab keeps only the value class; FlareLab's drill-media-manifest parser/loader
// is dropped (loop lengths come from assets/hip/hip-content.json).

/// One prerecorded drill clip served to the WebView player
/// (SmartFit: a drill pack's `assets/packs/<id>/demo.mp4` + `cover.jpg`).
class DrillMedia {
  const DrillMedia({
    required this.id,
    required this.videoAsset,
    required this.posterAsset,
    required this.duration,
    this.posterTime = 0,
  });
  final String id;
  final String videoAsset;
  final String posterAsset;
  final double duration;
  final double posterTime;
}
