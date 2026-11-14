import 'dart:convert';

import 'package:flutter/services.dart';

/// Ordered public mirrors for the catalogue pack currently in use.
///
/// The pack version comes from the loaded catalogue (bundled baseline or the
/// SDK's verified hot-update cache), never from this asset. Every mirror is a
/// template with one `{pack}` placeholder, e.g.
/// `https://media.uuugk.win/pack/{pack}/`, so a new pack needs no App release.
class PoseHubMediaDelivery {
  PoseHubMediaDelivery._(this.packVersion, this.mediaBaseUrls);

  factory PoseHubMediaDelivery.unavailable(String packVersion) =>
      PoseHubMediaDelivery._(packVersion, const []);

  static const asset = 'assets/posehub/media-delivery.json';
  static const format = 'smartfit-posehub-file-delivery@3';
  static const packPlaceholder = '{pack}';
  static final _pack = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  final String packVersion;
  final List<Uri> mediaBaseUrls;

  static Future<PoseHubMediaDelivery> load({
    required String packVersion,
    String mediaBaseUrls = '',
    AssetBundle? bundle,
  }) async {
    final data = jsonDecode(await (bundle ?? rootBundle).loadString(asset));
    if (packVersion.length > 64 ||
        !_pack.hasMatch(packVersion) ||
        data is! Map ||
        data['format'] != format) {
      throw const FormatException('Invalid PoseHub file delivery identity');
    }
    if (data['ready'] != true) {
      return PoseHubMediaDelivery.unavailable(packVersion);
    }
    final urls = mediaBaseUrls.isEmpty
        ? data['mediaBaseUrls']
        : jsonDecode(mediaBaseUrls);
    if (urls is! List || urls.isEmpty) {
      throw const FormatException('Expected an ordered media mirror list');
    }
    final bases = <Uri>[];
    for (final template in urls) {
      if (template is! String ||
          packPlaceholder.allMatches(template).length != 1) {
        throw const FormatException('Mirror must contain one {pack}');
      }
      final raw = template.replaceFirst(packPlaceholder, packVersion);
      final base = Uri.tryParse(raw);
      if (base == null ||
          RegExp(r'/\.{1,2}/').hasMatch(raw) ||
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
    return PoseHubMediaDelivery._(packVersion, List.unmodifiable(bases));
  }
}
