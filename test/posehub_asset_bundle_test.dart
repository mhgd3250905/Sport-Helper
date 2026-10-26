import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/posehub_pack_installation.dart';
import 'package:ugk_coach/ugk_coach.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

class _Delegate extends CachingAssetBundle {
  final reads = <String>[];
  final data = ByteData.sublistView(Uint8List.fromList([7, 8, 9]));

  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    if (key.endsWith('.zip')) throw StateError('Dart must not load the ZIP');
    return data;
  }
}

List<int> _bytes(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

String _key(String id, String role) =>
    '${PoseHubAssetBundle.prefix}${Uri.encodeComponent(id)}/$role';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PoseHubAppTestCatalog catalog;
  late Directory root;
  late _Delegate delegate;

  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() async {
    root = await Directory.systemTemp.createTemp('smartfit-posehub-bundle-');
    delegate = _Delegate();
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'cover and thumbnail resolve exact SDK paths from one local installation',
    () async {
      final action = catalog.allActions.first;
      final cover = File.fromUri(action.cover.resolve(root.uri));
      final thumbnail = File.fromUri(action.thumbnail.resolve(root.uri));
      await cover.parent.create(recursive: true);
      await cover.writeAsBytes([1, 2, 3, 4]);
      await thumbnail.writeAsBytes([5, 6]);
      final ready = Completer<Uri>();
      var installs = 0;
      final installation = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () {
          installs++;
          return ready.future;
        },
      );
      addTearDown(installation.dispose);
      final bundle = PoseHubAssetBundle(
        catalog: catalog,
        installation: installation,
        delegate: delegate,
      );
      final coverRead = bundle.load(_key(action.id, 'cover'));
      final thumbnailRead = bundle.load(_key(action.id, 'thumbnail'));
      expect(installs, 1);
      ready.complete(root.uri);
      expect(_bytes(await coverRead), [1, 2, 3, 4]);
      expect(_bytes(await thumbnailRead), [5, 6]);
      expect(_bytes(await bundle.load(_key(action.id, 'cover'))), [1, 2, 3, 4]);
      expect(installs, 1);
      // Only the two selected small files exist. The bundle must not request the
      // archive, SDK assets or any retired media from its Dart asset delegate.
      expect(delegate.reads, isEmpty);
      expect(
        await root.list(recursive: true).where((e) => e is File).length,
        2,
      );
    },
  );

  test(
    'unknown IDs, roles and malformed keys fail before installation',
    () async {
      var installs = 0;
      final installation = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () async {
          installs++;
          return root.uri;
        },
      );
      addTearDown(installation.dispose);
      final bundle = PoseHubAssetBundle(
        catalog: catalog,
        installation: installation,
        delegate: delegate,
      );
      for (final key in [
        _key('missing-action', 'cover'),
        _key(catalog.allActions.first.id, 'video'),
        '${_key(catalog.allActions.first.id, 'cover')}/extra',
      ]) {
        await expectLater(bundle.load(key), throwsFormatException, reason: key);
      }
      await expectLater(
        bundle.load('${PoseHubAssetBundle.prefix}%ZZ/cover'),
        throwsArgumentError,
      );
      expect(installs, 0);
      expect(delegate.reads, isEmpty);
    },
  );

  test(
    'ordinary assets delegate unchanged without installing a pack',
    () async {
      var installs = 0;
      final installation = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () async {
          installs++;
          return root.uri;
        },
      );
      addTearDown(installation.dispose);
      final bundle = PoseHubAssetBundle(
        catalog: catalog,
        installation: installation,
        delegate: delegate,
      );
      expect(await bundle.load('assets/ordinary.png'), same(delegate.data));
      expect(delegate.reads, ['assets/ordinary.png']);
      expect(installs, 0);
    },
  );

  test(
    'installation failure propagates without trying an alternate media source',
    () async {
      final failure = StateError('local installation failed');
      final installation = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () async => throw failure,
      );
      addTearDown(installation.dispose);
      final bundle = PoseHubAssetBundle(
        catalog: catalog,
        installation: installation,
        delegate: delegate,
      );
      await expectLater(
        bundle.load(_key(catalog.allActions.first.id, 'cover')),
        throwsA(same(failure)),
      );
      expect(delegate.reads, isEmpty);
    },
  );
}
