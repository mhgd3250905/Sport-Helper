import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/media/scene_asset_router.dart';

void main() {
  final router = SceneAssetRouter(
    assets: const [
      'assets/media_player/player.html',
      'assets/media_player/player.js',
      'assets/packs/h-squat/demo.mp4',
      'assets/packs/h-squat/cover.jpg',
      'assets/packs/h-squat/pack.json',
      'assets/packs/_common/voice/zh/n.1.m4a',
      'assets/packs/index.json',
    ],
    load: (key) async => Uint8List.fromList(List.filled(100, 7)),
  );

  test('the player page and each pack\'s clip and cover are served', () async {
    expect((await router.route('/player/player.html')).statusCode, 200);
    expect((await router.route('/player/player.js')).contentType, startsWith('text/javascript'));
    final clip = await router.route('/packs/h-squat/demo.mp4');
    expect(clip.statusCode, 200);
    expect(clip.contentType, 'video/mp4');
    expect((await router.route('/packs/h-squat/cover.jpg')).contentType, 'image/jpeg');
    final part = await router.route('/packs/h-squat/demo.mp4', range: 'bytes=10-19');
    expect(part.statusCode, 206);
    expect(part.contentLength, 10);
  });

  test('pack metadata, audio and anything outside the whitelist stay private', () async {
    for (final path in [
      '/packs/h-squat/pack.json',
      '/packs/_common/voice/zh/n.1.m4a',
      '/packs/index.json',
      '/drill_media/player.html',
      '/packs/../player/player.html',
    ]) {
      expect((await router.route(path)).statusCode, anyOf(400, 404), reason: path);
    }
  });
}
