// Copied from 3D-Body@a83a0f4 (branch feat/hiplab-flavor) `app/lib/platform/scene/scene_asset_server.dart`.
// FlareLab's 3D-scene URI options (scene_variant.dart) are removed; the rest is unchanged.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'scene_asset_router.dart';

/// A same-origin module/GLB server reachable only on this device's loopback.
class SceneAssetServer {
  SceneAssetServer._(this._server, this._router) {
    _subscription = _server.listen((request) => unawaited(_serve(request)));
  }

  final HttpServer _server;
  final SceneAssetRouter _router;
  late final StreamSubscription<HttpRequest> _subscription;
  bool _closed = false;

  Uri get origin => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
  );

  Uri get sceneUri => origin.resolve('/index.html');

  static Future<SceneAssetServer> start({SceneAssetRouter? router}) async {
    if (router == null) {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      router = SceneAssetRouter(
        assets: manifest.listAssets(),
        load: (key) async {
          final data = await rootBundle.load(key);
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        },
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return SceneAssetServer._(server, router);
  }

  bool permitsNavigation(Uri target) =>
      target.scheme == origin.scheme &&
      target.host == origin.host &&
      target.port == origin.port &&
      target.userInfo.isEmpty;

  Future<void> _serve(HttpRequest request) async {
    try {
      if (_closed) return;
      final target = request.requestedUri;
      if (!permitsNavigation(target)) {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        final result = await _router.route(
          request.uri.toString(),
          method: request.method,
          range: request.headers[HttpHeaders.rangeHeader]?.join(','),
        );
        if (_closed) return;
        final response = request.response;
        response.statusCode = result.statusCode;
        response.headers.set(HttpHeaders.contentTypeHeader, result.contentType);
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        response.headers.set('X-Content-Type-Options', 'nosniff');
        result.headers.forEach(response.headers.set);
        response.contentLength = result.contentLength;
        if (request.method != 'HEAD') response.add(result.body);
      }
      await request.response.close();
    } catch (_) {
      // A WebView may disappear while an asset is loading or close its socket.
      // Force-closing the server during dispose handles those pending requests.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _server.close(force: true);
  }
}
