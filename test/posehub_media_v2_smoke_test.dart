import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

/// Overrides the widget-test HTTP mock only inside this opt-in local transport.
/// No certificate override, external network, device or archive is involved.
class _LoopbackTransport extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sourcePath = Platform.environment['SMARTFIT_POSEHUB_V2_SOURCE'];
  test(
    'actual v2 median video downloads once and survives a closed-server restart',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final source = Directory(
        await Directory(sourcePath!).resolveSymbolicLinks(),
      );
      final catalog = await PoseHubActionLibrary.load();
      final sourceCatalogSha =
          (await sha256
                  .bind(
                    File.fromUri(source.uri.resolve('catalog.json')).openRead(),
                  )
                  .first)
              .toString();
      expect(sourceCatalogSha, PoseHubActionLibrary.catalogSha256);
      final ordered = catalog.allActions.toList()
        ..sort((a, b) {
          final byBytes = a.video.bytes.compareTo(b.video.bytes);
          return byBytes == 0 ? a.id.compareTo(b.id) : byBytes;
        });
      final action = ordered[ordered.length ~/ 2];
      final video = action.video;
      final sourceVideo = File.fromUri(video.resolve(source.uri));
      expect(await sourceVideo.length(), video.bytes);

      final temporary = await Directory.systemTemp.createTemp(
        'smartfit-v2-smoke-',
      );
      HttpServer? server;
      PoseHubMediaRepository? first, reopened;
      Map<String, Object?>? receipt;
      var requests = 0;
      var networkBytes = 0;
      final loadedImages = <String>[];
      final verifiedFiles = <Map<String, Object?>>[];
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final base = Uri.parse('http://127.0.0.1:${server.port}/');
        server.listen((request) async {
          requests++;
          if (request.method != 'GET' || request.uri.path != '/${video.path}') {
            request.response.statusCode = 404;
            await request.response.close();
            return;
          }
          request.response.contentLength = video.bytes;
          await for (final chunk in sourceVideo.openRead()) {
            networkBytes += chunk.length;
            request.response.add(chunk);
            await request.response.flush();
          }
          await request.response.close();
        });
        first = await PoseHubMediaRepository.forTesting(
          catalog: catalog,
          catalogRevision: PoseHubActionLibrary.catalogSha256,
          mediaBaseUrl: base,
          rootDirectory: temporary.path,
          allowInsecureLocalhost: true,
          bundledFileLoader: (file) async {
            final expected = [action.cover, action.thumbnail].where(
              (image) => image.path == file.path && image.sha256 == file.sha256,
            );
            expect(
              expected.length,
              1,
              reason: 'Only this real action supplies bundled images.',
            );
            loadedImages.add(file.path);
            return Uint8List.fromList(
              await File.fromUri(file.resolve(source.uri)).readAsBytes(),
            );
          },
        );
        final root = await first.ensureAction(action.id);
        expect(root, first.mediaBaseUri);
        for (final file in action.files.values) {
          final cached = File.fromUri(file.resolve(root));
          final bytes = await cached.length();
          final digest = (await sha256.bind(cached.openRead()).first)
              .toString();
          expect(bytes, file.bytes);
          expect(digest, file.sha256);
          verifiedFiles.add({
            'path': file.path,
            'bytes': bytes,
            'sha256': digest,
          });
        }
        expect(requests, 1);
        expect(networkBytes, video.bytes);
        expect(loadedImages.toSet(), {
          action.cover.path,
          action.thumbnail.path,
        });
        final initialRequests = requests;
        final initialNetworkBytes = networkBytes;
        expect(await first.ensureAction(action.id), root);
        expect(requests, initialRequests);
        expect(networkBytes, initialNetworkBytes);

        first.dispose();
        await server.close(force: true);
        server = null;
        // Preserve the now-unreachable base: any unexpected cache miss fails.
        reopened = await PoseHubMediaRepository.forTesting(
          catalog: catalog,
          catalogRevision: PoseHubActionLibrary.catalogSha256,
          mediaBaseUrl: base,
          rootDirectory: temporary.path,
          allowInsecureLocalhost: true,
          timeout: const Duration(seconds: 2),
        );
        expect(await reopened.ensureAction(action.id), root);
        expect(requests, 1);
        expect(networkBytes, video.bytes);
        final localFiles = await Directory.fromUri(root)
            .list(recursive: true, followLinks: false)
            .where((entity) => entity is File)
            .toList();
        expect(localFiles.length, 3);
        receipt = {
          'format': 'smartfit-posehub-v2-download-smoke@1',
          'status': 'passed',
          'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'sourceDirectory': source.path,
          'catalogSha256': sourceCatalogSha,
          'allActions': catalog.allActions.length,
          'aiCatalogActions': catalog.toAiCatalog().length,
          'pendingActions': catalog.pendingActions.length,
          'selection':
              'video bytes sorted ascending, middle index; ID breaks ties',
          'selectedIndex': ordered.length ~/ 2,
          'selectedActionId': action.id,
          'videoBytes': video.bytes,
          'videoSha256': video.sha256,
          'verifiedCacheFiles': verifiedFiles,
          'bundledImagesLoaded': loadedImages,
          'initialHttpRequests': initialRequests,
          'initialNetworkBytes': initialNetworkBytes,
          'repeatAdditionalHttpRequests': requests - initialRequests,
          'reopenedAfterServerClosed': true,
          'offlineAdditionalHttpRequests': requests - initialRequests,
          'offlineAdditionalNetworkBytes': networkBytes - initialNetworkBytes,
          'transport': 'real loopback HTTP serving original v2 video bytes',
          'syntheticMedia': false,
          'githubDownloadVerified': false,
          'devicePlaybackVerified': false,
          'apkBuilt': false,
          'sourceModified': false,
          'zipRead': false,
        };
      } finally {
        first?.dispose();
        reopened?.dispose();
        await server?.close(force: true);
        final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
        final actual = Directory(await temporary.resolveSymbolicLinks());
        expect(await actual.parent.resolveSymbolicLinks(), tempRoot);
        expect(
          actual.uri.pathSegments
              .where((p) => p.isNotEmpty)
              .last
              .startsWith('smartfit-v2-smoke-'),
          isTrue,
        );
        await actual.delete(recursive: true);
      }
      expect(await temporary.exists(), isFalse);
      receipt['temporaryCacheCleaned'] = true;
      final report = File(
        Platform.environment['SMARTFIT_POSEHUB_V2_SMOKE_REPORT'] ??
            '../deliveries/posehub-on-demand-20261026/v2-download-smoke.json',
      );
      await report.parent.create(recursive: true);
      await report.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
        flush: true,
      );
      // ignore: avoid_print
      print(
        'Actual v2: ${action.id}; $networkBytes video bytes; $requests HTTP request; report ${report.absolute.path}',
      );
    }, _LoopbackTransport()),
    skip: sourcePath == null
        ? 'Set SMARTFIT_POSEHUB_V2_SOURCE to the verified installed-v2 directory.'
        : false,
  );
}
