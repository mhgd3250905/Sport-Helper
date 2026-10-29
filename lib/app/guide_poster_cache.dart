import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An exceptional missing-cover fallback. This never creates a video player.
/// Normal guide images come straight from the verified bundled first frames.
class GuidePosterCache {
  GuidePosterCache({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('smartfit/guide_poster');

  static final shared = GuidePosterCache();
  final MethodChannel _channel;
  final _pending = <String, Future<String?>>{};

  Future<String?> frameZero({
    required Uri source,
    required String revision,
    bool packedAlpha = false,
  }) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !const {'file', 'asset'}.contains(source.scheme) ||
        revision.isEmpty) {
      return Future.value();
    }
    final key = sha256
        .convert(
          utf8.encode('guide-frame-v1|$source|$revision|$packedAlpha|720'),
        )
        .toString();
    return _pending.putIfAbsent(key, () async {
      try {
        final path = await _channel
            .invokeMethod<String>('frameZero', {
              'source': source.toString(),
              'cacheKey': key,
              'width': 720,
              'timeUs': 0,
              'packedAlpha': packedAlpha,
            })
            .timeout(const Duration(seconds: 15));
        if (path == null || path.isEmpty) return null;
        return path;
      } on Object {
        // A missing poster must not block text, scrolling or an explicit play.
        return null;
      } finally {
        // Android's cache can be cleared independently of the running App.
        // Coalesce only work in flight; the native owner rechecks its disk hit.
        _pending.remove(key);
      }
    });
  }
}
