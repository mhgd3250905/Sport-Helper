import 'package:flutter/services.dart';
import 'package:ugk_coach/ugk_coach.dart';

import 'posehub_asset_reader_stub.dart'
    if (dart.library.io) 'posehub_asset_reader_io.dart';
import 'posehub_media_repository.dart';

/// Resolves existing App/SDK asset-image slots from the verified file cache.
/// This contains no copied media or alternate catalogue.
class PoseHubAssetBundle extends CachingAssetBundle {
  PoseHubAssetBundle({
    required this.catalog,
    required this.installation,
    AssetBundle? delegate,
  }) : delegate = delegate ?? rootBundle;

  static const prefix = 'posehub-r1/';
  final PoseHubAppTestCatalog catalog;
  final PoseHubMediaRepository installation;
  final AssetBundle delegate;

  static bool handles(String key) => key.startsWith(prefix);

  @override
  Future<ByteData> load(String key) async {
    if (!handles(key)) return delegate.load(key);
    final parts = key.substring(prefix.length).split('/');
    if (parts.length != 2 || !const {'cover', 'thumbnail'}.contains(parts[1])) {
      throw const FormatException('Unknown local pack image role');
    }
    final action = catalog.tryGet(Uri.decodeComponent(parts[0]));
    if (action == null) throw const FormatException('Unknown pack action');
    final file = parts[1] == 'cover' ? action.cover : action.thumbnail;
    final localFile = await installation.ensureFile(file);
    final bytes = await readPoseHubAsset(localFile);
    return ByteData.sublistView(bytes);
  }
}
