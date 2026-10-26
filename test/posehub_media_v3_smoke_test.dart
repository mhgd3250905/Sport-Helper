import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

/// Uses the real anonymous HTTPS client inside this opt-in network test. TLS
/// validation is unchanged; neither certificates, cookies nor credentials are set.
class _PublicTransport extends HttpOverrides {
  final requests = <Map<String, Object?>>[];
  bool offline = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ObservedClient(super.createHttpClient(context), this);
}

class _ObservedClient implements HttpClient {
  _ObservedClient(this.inner, this.transport);
  final HttpClient inner;
  final _PublicTransport transport;

  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Duration? get connectionTimeout => inner.connectionTimeout;
  @override
  set autoUncompress(bool value) => inner.autoUncompress = value;
  @override
  bool get autoUncompress => inner.autoUncompress;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final record = <String, Object?>{'method': 'GET', 'url': url.toString()};
    transport.requests.add(record);
    if (transport.offline) {
      record['blockedOffline'] = true;
      throw StateError('Offline smoke must reuse verified cache files');
    }
    final elapsed = Stopwatch()..start();
    try {
      return _ObservedRequest(await inner.getUrl(url), record, elapsed);
    } catch (error) {
      record['errorType'] = error.runtimeType.toString();
      record['headersElapsedMilliseconds'] = elapsed.elapsedMilliseconds;
      rethrow;
    }
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedRequest implements HttpClientRequest {
  _ObservedRequest(this.inner, this.record, this.elapsed);
  final HttpClientRequest inner;
  final Map<String, Object?> record;
  final Stopwatch elapsed;

  @override
  HttpHeaders get headers => inner.headers;
  @override
  bool get followRedirects => inner.followRedirects;
  @override
  set followRedirects(bool value) => inner.followRedirects = value;

  @override
  Future<HttpClientResponse> close() async {
    final anonymous =
        inner.cookies.isEmpty &&
        headers.value(HttpHeaders.authorizationHeader) == null &&
        headers.value(HttpHeaders.cookieHeader) == null &&
        headers.value(HttpHeaders.proxyAuthorizationHeader) == null;
    record['anonymous'] = anonymous;
    if (!anonymous) {
      inner.abort(
        StateError('This smoke allows anonymous public requests only'),
      );
      throw StateError('Unexpected authentication on public media request');
    }
    try {
      final response = await inner.close();
      elapsed.stop();
      record.addAll({
        'statusCode': response.statusCode,
        'contentLength': response.contentLength,
        'contentType': response.headers.contentType?.mimeType,
        'cacheControl': response.headers.value(HttpHeaders.cacheControlHeader),
        'headersElapsedMilliseconds': elapsed.elapsedMilliseconds,
      });
      return response;
    } catch (error) {
      record['errorType'] = error.runtimeType.toString();
      record['headersElapsedMilliseconds'] = elapsed.elapsedMilliseconds;
      rethrow;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled =
      Platform.environment['SMARTFIT_POSEHUB_V3_HTTPS_SMOKE'] == '1';
  test(
    'official R2 median action verifies three files, repeat and offline reopen',
    () async {
      final transport = _PublicTransport();
      await HttpOverrides.runWithHttpOverrides(() async {
        final catalog = await PoseHubActionLibrary.load();
        final ordered = catalog.allActions.toList()
          ..sort((a, b) {
            final bySize = a.video.bytes.compareTo(b.video.bytes);
            return bySize == 0 ? a.id.compareTo(b.id) : bySize;
          });
        final action = ordered[ordered.length ~/ 2];
        final temporary = await Directory.systemTemp.createTemp(
          'smartfit-v3-r2-smoke-',
        );
        final bases = [Uri.parse('https://media.uuugk.win/pack/r1-v3/')];
        final report = File(
          Platform.environment['SMARTFIT_POSEHUB_V3_SMOKE_REPORT'] ??
              '../deliveries/posehub-on-demand-v3-20261026/v3-r2-download-smoke.json',
        );
        final receipt = <String, Object?>{
          'format': 'smartfit-posehub-v3-r2-download-smoke@1',
          'status': 'running',
          'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'catalogSha256': PoseHubActionLibrary.catalogSha256,
          'packVersion': 'r1-v3',
          'allActions': catalog.allActions.length,
          'aiActions': catalog.toAiCatalog().length,
          'pendingActions': catalog.pendingActions.length,
          'selection': 'median video bytes; ID breaks ties',
          'selectedIndex': ordered.length ~/ 2,
          'selectedActionId': action.id,
          'videoBytes': action.video.bytes,
          'videoSha256': action.video.sha256,
          'transport': 'anonymous official R2 HTTPS; default TLS validation',
          'bundledFileLoaderUsed': false,
          'syntheticMedia': false,
          'devicePlaybackVerified': false,
          'apkBuilt': false,
          'zipRead': false,
        };
        PoseHubMediaRepository? first, reopened;
        final elapsed = Stopwatch()..start();
        try {
          first = await PoseHubMediaRepository.forTesting(
            catalog: catalog,
            catalogRevision: PoseHubActionLibrary.catalogSha256,
            mediaBaseUrls: bases,
            packVersion: 'r1-v3',
            rootDirectory: temporary.path,
            timeout: const Duration(seconds: 30),
          );
          final root = await first.ensureAction(action.id);
          receipt['initialPrepareMilliseconds'] = elapsed.elapsedMilliseconds;
          final verified = <Map<String, Object?>>[];
          for (final file in action.files.values) {
            final cached = File.fromUri(file.resolve(root));
            final bytes = await cached.length();
            final digest = (await sha256.bind(cached.openRead()).first)
                .toString();
            expect(bytes, file.bytes, reason: file.path);
            expect(digest, file.sha256, reason: file.path);
            verified.add({'path': file.path, 'bytes': bytes, 'sha256': digest});
          }
          expect(transport.requests, hasLength(3));
          expect(transport.requests.map((r) => r['url']).toSet(), {
            for (final file in action.files.values)
              bases.single.resolve(file.path).toString(),
          });
          for (final response in transport.requests) {
            expect(response['statusCode'], HttpStatus.ok);
            expect(response['anonymous'], isTrue);
            expect(response['cacheControl'], contains('immutable'));
            expect(response['cacheControl'], contains('max-age=31536000'));
            expect(
              response['contentType'],
              (response['url']! as String).endsWith('.mp4')
                  ? 'video/mp4'
                  : 'image/webp',
            );
          }
          final initialRequests = transport.requests.length;
          final expectedBytes = action.files.values.fold(
            0,
            (n, f) => n + f.bytes,
          );
          expect(
            transport.requests.fold(
              0,
              (n, r) => n + (r['contentLength']! as int),
            ),
            expectedBytes,
          );
          receipt.addAll({
            'verifiedCacheFiles': verified,
            'initialHttpRequests': initialRequests,
            'verifiedNetworkPayloadBytes': expectedBytes,
          });

          elapsed.reset();
          expect(await first.ensureAction(action.id), root);
          receipt['repeatCachePrepareMilliseconds'] =
              elapsed.elapsedMilliseconds;
          receipt['repeatAdditionalHttpRequests'] =
              transport.requests.length - initialRequests;
          expect(transport.requests.length, initialRequests);

          first.dispose();
          transport.offline = true;
          elapsed.reset();
          reopened = await PoseHubMediaRepository.forTesting(
            catalog: catalog,
            catalogRevision: PoseHubActionLibrary.catalogSha256,
            mediaBaseUrls: bases,
            packVersion: 'r1-v3',
            rootDirectory: temporary.path,
            timeout: const Duration(seconds: 2),
          );
          expect(await reopened.ensureAction(action.id), root);
          expect(transport.requests.length, initialRequests);
          expect(
            await Directory.fromUri(
              root,
            ).list(recursive: true).where((entity) => entity is File).length,
            3,
          );
          receipt.addAll({
            'offlineReopenPrepareMilliseconds': elapsed.elapsedMilliseconds,
            'offlineAdditionalHttpRequests':
                transport.requests.length - initialRequests,
            'offlineNetworkExplicitlyBlocked': true,
            'status': 'passed',
          });
        } catch (error) {
          receipt['status'] = 'failed';
          receipt['errorType'] = error.runtimeType.toString();
          receipt['failureElapsedMilliseconds'] = elapsed.elapsedMilliseconds;
          rethrow;
        } finally {
          first?.dispose();
          reopened?.dispose();
          receipt['requests'] = transport.requests;
          receipt['failedHttpAttempts'] = transport.requests
              .where(
                (r) =>
                    r.containsKey('errorType') ||
                    r['statusCode'] != HttpStatus.ok,
              )
              .length;
          final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
          final actual = Directory(await temporary.resolveSymbolicLinks());
          expect(await actual.parent.resolveSymbolicLinks(), tempRoot);
          expect(
            actual.uri.pathSegments.where((s) => s.isNotEmpty).last,
            startsWith('smartfit-v3-r2-smoke-'),
          );
          await actual.delete(recursive: true);
          receipt['temporaryCacheCleaned'] = !await temporary.exists();
          await report.parent.create(recursive: true);
          await report.writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
            flush: true,
          );
        }
        // ignore: avoid_print
        print(
          'R2 v3 ${action.id}: 3 verified HTTPS files; repeated/offline 0 requests; ${report.absolute.path}',
        );
      }, transport);
    },
    skip: enabled
        ? false
        : 'Set SMARTFIT_POSEHUB_V3_HTTPS_SMOKE=1 for public HTTPS verification.',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
