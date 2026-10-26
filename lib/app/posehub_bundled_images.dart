import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

/// Optional verified image bytes from the APK. Video always stays outside this
/// index; a miss lets the media repository use its ordinary file downloader.
class PoseHubBundledImages {
  PoseHubBundledImages._(this._bundle, this._files);

  static const indexAsset = 'assets/posehub/images-index.json';
  static const assetPrefix = 'assets/posehub/images/';
  static const _format = 'smartfit-posehub-bundled-images@1';
  static final _sha = RegExp(r'^[0-9a-f]{64}$');
  final AssetBundle _bundle;
  final Map<String, _BundledImage> _files;

  /// The caller supplies the exact current catalog SHA256. A mismatched or
  /// malformed index is rejected before any image is read.
  static Future<PoseHubBundledImages> load({
    required String catalogRevision,
    AssetBundle? bundle,
  }) async {
    final assets = bundle ?? rootBundle;
    final decoded = jsonDecode(await assets.loadString(indexAsset));
    if (decoded is! Map ||
        decoded['format'] != _format ||
        !_sha.hasMatch(catalogRevision) ||
        decoded['catalogSha256'] != catalogRevision ||
        decoded['files'] is! Map) {
      throw const FormatException('Bundled image index/catalog mismatch');
    }
    final files = <String, _BundledImage>{};
    final unique = <String, int>{};
    var referencedBytes = 0;
    for (final entry in (decoded['files'] as Map).entries) {
      final path = entry.key;
      final value = entry.value;
      if (path is! String || !_safeImagePath(path) || value is! Map) {
        throw const FormatException('Unsafe bundled image source path');
      }
      final asset = value['asset'];
      final bytes = value['bytes'];
      final sha = value['sha256'];
      if (sha is! String ||
          !_sha.hasMatch(sha) ||
          !_safeAsset(asset, sha) ||
          bytes is! int ||
          bytes <= 0) {
        throw const FormatException('Invalid bundled image descriptor');
      }
      if (unique.containsKey(asset) && unique[asset] != bytes) {
        throw const FormatException('Conflicting bundled image sizes');
      }
      files[path] = _BundledImage(asset as String, bytes, sha);
      unique[asset] = bytes;
      referencedBytes += bytes;
    }
    final uniqueBytes = unique.values.fold(0, (sum, bytes) => sum + bytes);
    if (decoded['uniqueFiles'] != unique.length ||
        decoded['uniqueBytes'] != uniqueBytes ||
        decoded['referencedBytes'] != referencedBytes ||
        uniqueBytes > 20000000) {
      throw const FormatException('Bundled image index size/budget mismatch');
    }
    return PoseHubBundledImages._(assets, Map.unmodifiable(files));
  }

  /// Only an exact path, size and SHA256 match can read an APK image. The asset
  /// itself is verified too; absent/corrupt optional payloads become cache misses.
  Future<Uint8List?> loadFile(coach.PoseHubPackFile file) async {
    final match = _files[file.path];
    if (match == null ||
        match.bytes != file.bytes ||
        match.sha256 != file.sha256) {
      return null;
    }
    ByteData data;
    try {
      data = await _bundle.load(match.asset);
    } on FlutterError {
      return null;
    }
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != match.bytes || coach.sha256Hex(bytes) != match.sha256) {
      return null;
    }
    return bytes;
  }
}

bool _safeImagePath(String path) =>
    path.endsWith('.webp') &&
    !RegExp(r'[\\:%?#\x00-\x1f]').hasMatch(path) &&
    !path.split('/').any((part) => part.isEmpty || part == '.' || part == '..');

bool _safeAsset(Object? asset, String sha) =>
    asset is String &&
    asset.startsWith(PoseHubBundledImages.assetPrefix) &&
    asset.split('/').last == '$sha.webp' &&
    _safeImagePath(asset);

class _BundledImage {
  const _BundledImage(this.asset, this.bytes, this.sha256);
  final String asset;
  final int bytes;
  final String sha256;
}
