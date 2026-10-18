// Copied from 3D-Body@a83a0f4 (branch feat/hiplab-flavor) `app/lib/platform/scene/scene_asset_router.dart`.
// Unchanged. HipLab bundles no assets/scene/, so only /drill_media/* (and
// /fonts/*) resolve; everything else is a 404 from the manifest whitelist.
import 'dart:typed_data';

typedef SceneAssetLoader = Future<Uint8List> Function(String assetKey);

class SceneAssetResponse {
  const SceneAssetResponse({
    required this.statusCode,
    required this.contentType,
    required this.body,
    this.headers = const {},
    required this.contentLength,
  });

  final int statusCode;
  final String contentType;
  final Uint8List body;
  final Map<String, String> headers;
  final int contentLength;
}

/// Resolves only assets explicitly present in the Flutter bundle manifest.
/// No request path is ever joined to a filesystem directory.
class SceneAssetRouter {
  SceneAssetRouter({required Iterable<String> assets, required this.load})
    : _assets = {
        for (final key in assets)
          if (_mimeForAsset(key) != null)
            if (key.startsWith(assetPrefix))
              key.substring(assetPrefix.length): key
            else if (key.startsWith(mediaAssetPrefix))
              'drill_media/${key.substring(mediaAssetPrefix.length)}': key
            else if (key.startsWith('assets/fonts/'))
              'fonts/${key.substring('assets/fonts/'.length)}': key,
      };

  static const assetPrefix = 'assets/scene/';
  static const mediaAssetPrefix = 'assets/drill_media/';
  final Map<String, String> _assets;
  final SceneAssetLoader load;

  Future<SceneAssetResponse> route(
    String requestTarget, {
    String method = 'GET',
    String? range,
  }) async {
    if (method != 'GET' && method != 'HEAD') return _error(405);
    final name = _assetName(requestTarget);
    if (name == null) return _error(400);
    final key = _assets[name];
    if (key == null) return _error(404);
    try {
      final bytes = await load(key);
      final isMedia = key.startsWith(mediaAssetPrefix);
      final headers = <String, String>{if (isMedia) 'Accept-Ranges': 'bytes'};
      if (isMedia && method == 'GET' && range != null) {
        final selected = _range(range, bytes.length);
        if (selected == null) {
          return SceneAssetResponse(
            statusCode: 416,
            contentType: _mimeForAsset(key)!,
            body: Uint8List(0),
            contentLength: 0,
            headers: {...headers, 'Content-Range': 'bytes */${bytes.length}'},
          );
        }
        final (start, end) = selected;
        return SceneAssetResponse(
          statusCode: 206,
          contentType: _mimeForAsset(key)!,
          body: Uint8List.sublistView(bytes, start, end + 1),
          contentLength: end - start + 1,
          headers: {
            ...headers,
            'Content-Range': 'bytes $start-$end/${bytes.length}',
          },
        );
      }
      return SceneAssetResponse(
        statusCode: 200,
        contentType: _mimeForAsset(key)!,
        body: method == 'HEAD' ? Uint8List(0) : bytes,
        contentLength: bytes.length,
        headers: headers,
      );
    } catch (_) {
      return _error(404);
    }
  }

  // A bounded, open-ended or suffix byte range. Multiple ranges are not
  // supported: never return multipart bytes under a video MIME type.
  static (int, int)? _range(String value, int length) {
    if (length == 0) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value.trim());
    if (match == null) return null;
    final first = match.group(1)!;
    final last = match.group(2)!;
    if (first.isEmpty) {
      final suffix = int.tryParse(last);
      if (suffix == null || suffix <= 0) return null;
      return (suffix >= length ? 0 : length - suffix, length - 1);
    }
    final start = int.tryParse(first);
    final end = last.isEmpty ? length - 1 : int.tryParse(last);
    if (start == null || end == null || start >= length || end < start) {
      return null;
    }
    return (start, end >= length ? length - 1 : end);
  }

  static String? _mimeForAsset(String key) {
    if (key.startsWith(assetPrefix)) {
      return _mimeFor(key.substring(assetPrefix.length));
    }
    if (key.startsWith('assets/fonts/') && key.endsWith('.ttf')) {
      return 'font/ttf';
    }
    if (!key.startsWith(mediaAssetPrefix)) return null;
    return switch (key.split('.').last.toLowerCase()) {
      'mp4' => 'video/mp4',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => _mimeFor(key.substring(mediaAssetPrefix.length)),
    };
  }

  static String? _assetName(String target) {
    // Validate the raw path before Uri parsing can normalize dot segments.
    final raw = target.split('?').first;
    if (!raw.startsWith('/') || raw.startsWith('//') || raw.contains('#')) {
      return null;
    }
    String path;
    try {
      path = Uri.decodeComponent(raw);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (path.contains('%') ||
        path.contains('\\') ||
        path.contains(':') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
      return null;
    }
    if (path == '/') return 'index.html';
    final segments = path.substring(1).split('/');
    if (segments.any((part) => part.isEmpty || part.startsWith('.'))) {
      return null;
    }
    return segments.join('/');
  }

  static String? _mimeFor(String name) =>
      switch (name.split('.').last.toLowerCase()) {
        'html' => 'text/html; charset=utf-8',
        'js' || 'mjs' => 'text/javascript; charset=utf-8',
        'css' => 'text/css; charset=utf-8',
        'json' => 'application/json; charset=utf-8',
        'glb' => 'model/gltf-binary',
        'gz' => 'application/gzip',
        'bin' => 'application/octet-stream',
        'wasm' => 'application/wasm',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'svg' => 'image/svg+xml',
        'ttf' => 'font/ttf',
        _ => null,
      };

  static SceneAssetResponse _error(int status) => SceneAssetResponse(
    statusCode: status,
    contentType: 'text/plain; charset=utf-8',
    body: Uint8List(0),
    contentLength: 0,
  );
}
