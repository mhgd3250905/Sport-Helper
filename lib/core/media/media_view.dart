// Copied from 3D-Body@a83a0f4 (branch feat/hiplab-flavor) `app/lib/platform/drill_media/media_view.dart`.
// HipLab ships Android/iOS only, so the web implementation is not copied.
export 'media_view_stub.dart' if (dart.library.io) 'media_view_native.dart';
