import 'dart:convert';

import 'package:flutter/services.dart';

/// The immutable pack identity and ordered public mirrors for catalog paths.
class PoseHubMediaDelivery {
  PoseHubMediaDelivery._(this.packVersion, this.mediaBaseUrls);

  factory PoseHubMediaDelivery.unavailable() =>
      PoseHubMediaDelivery._('r1-v3', const []);

  static const asset = 'assets/posehub/media-delivery.json';
  final String packVersion;
  final List<Uri> mediaBaseUrls;

  static Future<PoseHubMediaDelivery> load({
    required String catalogRevision,
    String mediaBaseUrls = '',
    AssetBundle? bundle,
  }) async {
    final data = jsonDecode(await (bundle ?? rootBundle).loadString(asset));
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(catalogRevision) ||
        data is! Map ||
        data['format'] != 'smartfit-posehub-file-delivery@2' ||
        data['catalogSha256'] != catalogRevision ||
        data['packVersion'] != 'r1-v3') {
      throw const FormatException('Invalid PoseHub file delivery identity');
    }
    if (data['ready'] != true) {
      return PoseHubMediaDelivery.unavailable();
    }
    final urls = mediaBaseUrls.isEmpty
        ? data['mediaBaseUrls']
        : jsonDecode(mediaBaseUrls);
    if (urls is! List || urls.isEmpty) {
      throw const FormatException('Expected an ordered media mirror list');
    }
    final bases = <Uri>[];
    for (final raw in urls) {
      final base = raw is String ? Uri.tryParse(raw) : null;
      if (base == null ||
          (raw is String && RegExp(r'/\.{1,2}/').hasMatch(raw)) ||
          base.scheme != 'https' ||
          base.host.isEmpty ||
          base.userInfo.isNotEmpty ||
          base.hasQuery ||
          base.hasFragment ||
          !base.path.endsWith('/') ||
          base.normalizePath() != base ||
          bases.contains(base)) {
        throw const FormatException('Invalid public media mirror directory');
      }
      bases.add(base);
    }
    return PoseHubMediaDelivery._('r1-v3', List.unmodifiable(bases));
  }
}
