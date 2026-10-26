import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ugk_coach/ugk_coach.dart';

/// Maps exact catalog files to names from an immutable Release asset inventory.
/// A missing/pending manifest cannot silently invent remote download URLs.
class PoseHubMediaDelivery {
  PoseHubMediaDelivery._(this.mediaBaseUrl, this._files);

  factory PoseHubMediaDelivery.unavailable() =>
      PoseHubMediaDelivery._(null, const {});

  static const asset = 'assets/posehub/media-delivery.json';
  final Uri? mediaBaseUrl;
  final Map<String, Map<String, Object?>> _files;

  static Future<PoseHubMediaDelivery> load({
    required String catalogRevision,
    String mediaBaseUrl = '',
    AssetBundle? bundle,
  }) async {
    final data = jsonDecode(await (bundle ?? rootBundle).loadString(asset));
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(catalogRevision) ||
        data is! Map ||
        data['format'] != 'smartfit-posehub-file-delivery@1' ||
        data['catalogSha256'] != catalogRevision ||
        data['files'] is! Map) {
      throw const FormatException('Invalid PoseHub file delivery identity');
    }
    if (data['ready'] != true) {
      return PoseHubMediaDelivery.unavailable();
    }
    final rawBase = mediaBaseUrl.isEmpty ? data['mediaBaseUrl'] : mediaBaseUrl;
    final base = rawBase is String ? Uri.tryParse(rawBase) : null;
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !base.path.endsWith('/')) {
      throw const FormatException('Invalid public media base URL');
    }
    final files = <String, Map<String, Object?>>{};
    for (final entry in (data['files'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid file delivery record');
      }
      final file = Map<String, Object?>.from(entry.value as Map);
      final name = file['assetName'];
      if (name is! String ||
          name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains('\\') ||
          name.runes.any((c) => c < 32 || c == 127) ||
          file['bytes'] is! int ||
          (file['bytes']! as int) <= 0 ||
          file['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(file['sha256']! as String)) {
        throw const FormatException('Invalid immutable file delivery record');
      }
      files[entry.key as String] = Map.unmodifiable(file);
    }
    return PoseHubMediaDelivery._(base, Map.unmodifiable(files));
  }

  Uri? urlFor(PoseHubPackFile file) {
    final entry = _files[file.path];
    final base = mediaBaseUrl;
    if (base == null ||
        entry == null ||
        entry['bytes'] != file.bytes ||
        entry['sha256'] != file.sha256) {
      return null;
    }
    return base.resolve(Uri.encodeComponent(entry['assetName']! as String));
  }
}
