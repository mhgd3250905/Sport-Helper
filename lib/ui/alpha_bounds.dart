import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Import-time analysis of immutable alpha covers/thumbnails. Never video
/// frame-zero posters: those retain the video's original camera framing.
class SfAlphaBounds {
  const SfAlphaBounds._(this.entries);
  final Map<String, Rect> entries;
  static const root = 'assets/app_test_pack/app-test-pack-r1';
  static final _loads = Expando<Future<SfAlphaBounds>>();
  static final _ready = Expando<SfAlphaBounds>();

  static Future<SfAlphaBounds> load(AssetBundle bundle) {
    final ready = _ready[bundle];
    if (ready != null) return SynchronousFuture(ready);
    return _loads[bundle] ??= _load(bundle).then((value) {
      _ready[bundle] = value;
      return value;
    });
  }

  static Future<SfAlphaBounds> _load(AssetBundle bundle) async {
    try {
      return parse(
        jsonDecode(await bundle.loadString('$root/alpha-bounds.json')),
        jsonDecode(await bundle.loadString('$root/index.json')),
      );
    } catch (_) {
      return const SfAlphaBounds._({});
    }
  }

  /// Compare each source SHA and geometry with the current verified import.
  /// A stale/malformed entry only disables cropping for that asset.
  static SfAlphaBounds parse(Object? metadata, Object? index) {
    if (metadata is! Map ||
        index is! Map ||
        metadata['format'] != 'smartfit-alpha-bounds@1' ||
        index['format'] != 'smartfit-app-test-pack-index@1' ||
        index['internalOnly'] != true) {
      return const SfAlphaBounds._({});
    }
    final incoming = metadata['assets'];
    final actions = index['actions'];
    if (incoming is! Map || actions is! Map) {
      return const SfAlphaBounds._({});
    }
    final result = <String, Rect>{};
    for (final action in actions.values.whereType<Map>()) {
      for (final role in ['alphaCover', 'alphaThumbnail']) {
        final source = action[role];
        if (source is! Map || source['asset'] is! String) continue;
        final asset = source['asset'] as String;
        final entry = incoming[asset];
        if (entry is! Map ||
            entry['sourceSha256'] != source['sha256'] ||
            entry['width'] != source['width'] ||
            entry['height'] != source['height']) {
          continue;
        }
        final width = source['width'];
        final height = source['height'];
        final bounds = entry['bounds'];
        if (width is! num ||
            height is! num ||
            width <= 0 ||
            height <= 0 ||
            bounds is! List ||
            bounds.length != 4 ||
            !bounds.every((value) => value is num && value.isFinite)) {
          continue;
        }
        final values = bounds.cast<num>();
        final rect = Rect.fromLTRB(
          values[0].toDouble(),
          values[1].toDouble(),
          values[2].toDouble(),
          values[3].toDouble(),
        );
        if (rect.isEmpty ||
            rect.left < 0 ||
            rect.top < 0 ||
            rect.right > width ||
            rect.bottom > height) {
          continue;
        }
        result[asset] = Rect.fromLTRB(
          rect.left / width,
          rect.top / height,
          rect.right / width,
          rect.bottom / height,
        );
      }
    }
    return SfAlphaBounds._(Map.unmodifiable(result));
  }
}
