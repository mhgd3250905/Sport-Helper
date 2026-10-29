import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/guide_poster_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartfit/guide_poster_test');
  final calls = <MethodCall>[];
  late GuidePosterCache cache;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    cache = GuidePosterCache(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return '/private/cache/guide-first-frames-v1/frame.webp';
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('construction does not extract or allocate a video player', () {
    expect(calls, isEmpty);
  });

  test(
    'missing cover requests exactly frame zero as a 720px WebP cache',
    () async {
      final path = await cache.frameZero(
        source: Uri.file('/private/files/verified/action.mp4'),
        revision: 'verified-video-sha',
        packedAlpha: true,
      );
      expect(path, endsWith('.webp'));
      final call = calls.single;
      expect(call.method, 'frameZero');
      final args = call.arguments as Map;
      expect(args['width'], 720);
      expect(args['timeUs'], 0);
      expect(args['packedAlpha'], isTrue);
      expect(args['source'], 'file:///private/files/verified/action.mp4');
      expect(args['cacheKey'], matches(RegExp(r'^[a-f0-9]{64}$')));
    },
  );

  test(
    'concurrent misses share extraction and later reads recheck disk cache',
    () async {
      final response = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call);
            return response.future;
          });
      final source = Uri.file('/private/files/action.mp4');
      final first = cache.frameZero(source: source, revision: 'v1');
      final second = cache.frameZero(source: source, revision: 'v1');
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      response.complete('/private/cache/frame.webp');
      expect(await first, await second);
      expect(
        await cache.frameZero(source: source, revision: 'v1'),
        '/private/cache/frame.webp',
      );
      expect(calls, hasLength(2));
    },
  );

  test(
    'revised video and packed formats cannot reuse an old frame cache',
    () async {
      final source = Uri.file('/private/files/action.mp4');
      await cache.frameZero(source: source, revision: 'v1');
      await cache.frameZero(source: source, revision: 'v2');
      await cache.frameZero(source: source, revision: 'v2', packedAlpha: true);
      expect(
        calls.map((c) => (c.arguments as Map)['cacheKey']).toSet(),
        hasLength(3),
      );
    },
  );

  test(
    'platform failure remains retryable without blocking guide content',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (calls.length == 1) {
              throw PlatformException(code: 'decode_failed');
            }
            return '/private/cache/retried.webp';
          });
      final source = Uri.file('/private/files/action.mp4');
      expect(await cache.frameZero(source: source, revision: 'v1'), isNull);
      expect(
        await cache.frameZero(source: source, revision: 'v1'),
        endsWith('.webp'),
      );
      expect(calls, hasLength(2));
    },
  );

  test(
    'remote URLs are not decoded and assets retain their own identity',
    () async {
      expect(
        await cache.frameZero(
          source: Uri.https('example.com', '/video.mp4'),
          revision: 'v1',
        ),
        isNull,
      );
      expect(calls, isEmpty);
      await cache.frameZero(
        source: Uri.parse('asset:///assets/packs/demo.mp4'),
        revision: 'v1',
      );
      expect(
        (calls.single.arguments as Map)['source'],
        'asset:///assets/packs/demo.mp4',
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await cache.frameZero(
          source: Uri.file('/private/movie.mp4'),
          revision: 'v1',
        ),
        isNull,
      );
      expect(calls, hasLength(1));
    },
  );
}
