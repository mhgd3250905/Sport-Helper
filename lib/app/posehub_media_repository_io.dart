import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'posehub_media_repository_types.dart';

Future<PoseHubMediaFileStore> createPoseHubMediaStore({
  required String revision,
  required String packVersion,
  required String? rootDirectory,
  required List<coach.PoseHubPackFile> files,
  required List<coach.PoseHubPackFile> videos,
  required List<Uri> mediaBaseUrls,
  required bool allowInsecureLocalhost,
  required Duration timeout,
  required int maxRedirects,
}) async {
  for (final mediaBaseUrl in mediaBaseUrls) {
    _checkUrl(mediaBaseUrl, allowInsecureLocalhost);
    if (!mediaBaseUrl.path.endsWith('/')) {
      throw const FormatException('Media base URL must be a directory.');
    }
  }
  for (final file in files) {
    _checkedPath(file.path);
    if (file.bytes > 128 * 1024 * 1024) {
      throw const FormatException('Media file exceeds its size limit.');
    }
  }
  final support = Directory(
    rootDirectory ?? (await getApplicationSupportDirectory()).path,
  );
  await support.create(recursive: true);
  final supportPath = await support.resolveSymbolicLinks();
  final parent = Directory('$supportPath/posehub-media');
  if (await FileSystemEntity.type(parent.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException('Media cache parent is a link.');
  }
  await parent.create();
  final version = Directory('${parent.path}/$packVersion');
  if (await FileSystemEntity.type(version.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException('Media cache version is a link.');
  }
  await version.create();
  final root = Directory('${version.path}/$revision');
  if (await FileSystemEntity.type(root.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const FormatException('Media cache revision is a link.');
  }
  await root.create();
  final canonical = Directory(await root.resolveSymbolicLinks());
  if (!_within(canonical.path, supportPath)) {
    throw const FormatException('Media cache escaped application support.');
  }
  return _FileStore(
    canonical,
    files,
    videos,
    allowInsecureLocalhost,
    timeout,
    maxRedirects,
  );
}

void _checkedPath(String path) {
  if (!path.startsWith('media/') ||
      path.length > 1024 ||
      RegExp(r'[\\:%?#\x00-\x20\x7f]').hasMatch(path) ||
      path
          .split('/')
          .any(
            (part) =>
                part.isEmpty ||
                part == '.' ||
                part == '..' ||
                part.endsWith('.'),
          )) {
    throw const FormatException('Invalid media file path.');
  }
}

bool _within(String path, String root) {
  if (Platform.isWindows) {
    path = path.toLowerCase();
    root = root.toLowerCase();
  }
  return path.startsWith('$root${Platform.pathSeparator}');
}

void _checkUrl(Uri uri, bool local, {bool redirect = false}) {
  final localHttp =
      local &&
      uri.scheme == 'http' &&
      const ['127.0.0.1', 'localhost', '::1'].contains(uri.host);
  if ((uri.scheme != 'https' && !localHttp) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (!redirect && uri.hasQuery) ||
      uri.hasFragment) {
    throw const PoseHubMediaException('invalid_url', 'Media URL is invalid.');
  }
}

class _FileStore implements PoseHubMediaFileStore {
  _FileStore(
    this.root,
    this.files,
    this.videos,
    this.allowLocal,
    this.timeout,
    this.maxRedirects,
  );

  final Directory root;
  final List<coach.PoseHubPackFile> files;
  final List<coach.PoseHubPackFile> videos;
  final bool allowLocal;
  final Duration timeout;
  final int maxRedirects;
  final _clients = <HttpClient, String>{};
  final _random = Random.secure();
  bool _disposed = false;

  @override
  Uri get mediaBaseUri => root.uri;

  void _check() {
    if (_disposed) {
      throw const PoseHubMediaException(
        'disposed',
        'Media preparation stopped.',
      );
    }
  }

  Future<File> _target(String relative, {bool createParents = false}) async {
    _check();
    final parts = relative.split('/');
    var path = root.path;
    for (var i = 0; i < parts.length; i++) {
      path = '$path${Platform.pathSeparator}${parts[i]}';
      var type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const PoseHubMediaException(
          'unsafe_cache',
          'Media cache path is invalid.',
        );
      }
      if (i < parts.length - 1) {
        if (type == FileSystemEntityType.notFound && createParents) {
          await Directory(path).create(recursive: true);
          type = await FileSystemEntity.type(path, followLinks: false);
        }
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw const PoseHubMediaException(
            'unsafe_cache',
            'Media cache path is invalid.',
          );
        }
      }
      if (type != FileSystemEntityType.notFound) {
        final resolved = await File(path).resolveSymbolicLinks();
        if (!_within(resolved, root.path)) {
          throw const PoseHubMediaException(
            'unsafe_cache',
            'Media cache path is invalid.',
          );
        }
      }
    }
    return File(path);
  }

  Future<bool> _verified(File file, coach.PoseHubPackFile expected) async {
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != expected.bytes) {
        return false;
      }
      return (await sha256.bind(file.openRead()).first).toString() ==
          expected.sha256;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<Uri?> cached(coach.PoseHubPackFile file) async {
    final target = await _target(file.path);
    return await _verified(target, file) ? target.uri : null;
  }

  @override
  Future<Uri?> reusable(coach.PoseHubPackFile file) async {
    final aliases = files.where(
      (f) => f.sha256 == file.sha256 && f.bytes == file.bytes,
    );
    for (final alias in aliases) {
      final target = await _target(alias.path);
      if (await _verified(target, file)) return target.uri;
    }
    return null;
  }

  @override
  Future<Uri> bundled(
    coach.PoseHubPackFile file,
    Uint8List bytes,
    void Function(int) onProgress,
    void Function() onVerifying,
  ) async {
    if (bytes.length != file.bytes) {
      throw const PoseHubMediaException('size', 'Bundled media size mismatch.');
    }
    final target = await _target(file.path, createParents: true);
    return _publish(file, target, Stream.value(bytes), onProgress, onVerifying);
  }

  @override
  Future<Uri> download(
    coach.PoseHubPackFile file,
    Uri url,
    void Function(int) onProgress,
    void Function() onVerifying,
  ) async {
    _checkUrl(url, allowLocal);
    _check();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    _clients[client] = file.path;
    try {
      var current = url;
      for (var redirects = 0; ; redirects++) {
        _check();
        _checkUrl(current, allowLocal, redirect: redirects > 0);
        final request = await client.getUrl(current).timeout(timeout);
        request.followRedirects = false;
        // A fresh request receives only public headers, including across hosts.
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/octet-stream',
        );
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final response = await request.close().timeout(timeout);
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (redirects >= maxRedirects || location == null) {
            throw const PoseHubMediaException(
              'redirect',
              'Media redirect limit reached.',
            );
          }
          final next = current.resolve(location);
          _checkUrl(next, allowLocal, redirect: true);
          var discarded = 0;
          await for (final chunk in response.timeout(timeout)) {
            discarded += chunk.length;
            if (discarded > 64 * 1024) {
              throw const PoseHubMediaException(
                'redirect',
                'Media redirect response is invalid.',
              );
            }
          }
          current = next;
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          throw const PoseHubMediaException(
            'http',
            'Media server did not return a file.',
          );
        }
        if (response.contentLength >= 0 &&
            response.contentLength != file.bytes) {
          throw const PoseHubMediaException(
            'size',
            'Media response size mismatch.',
          );
        }
        final target = await _target(file.path, createParents: true);
        return await _publish(
          file,
          target,
          response.timeout(timeout),
          onProgress,
          onVerifying,
        );
      }
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  Future<Uri> _publish(
    coach.PoseHubPackFile file,
    File target,
    Stream<List<int>> input,
    void Function(int) onProgress,
    void Function() onVerifying,
  ) async {
    _check();
    final temp = File(
      '${target.path}.${pid}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}.part',
    );
    RandomAccessFile? output;
    final result = _DigestResult();
    final hash = sha256.startChunkedConversion(result);
    var received = 0;
    try {
      await temp.create(exclusive: true);
      output = await temp.open(mode: FileMode.write);
      await for (final chunk in input) {
        _check();
        received += chunk.length;
        if (received > file.bytes) {
          throw const PoseHubMediaException(
            'size',
            'Media exceeds its declared size.',
          );
        }
        hash.add(chunk);
        await output.writeFrom(chunk);
        onProgress(received);
      }
      hash.close();
      onVerifying();
      if (received != file.bytes) {
        throw const PoseHubMediaException(
          'size',
          'Media download is incomplete.',
        );
      }
      if (result.value?.toString() != file.sha256) {
        throw const PoseHubMediaException('sha256', 'Media checksum mismatch.');
      }
      await output.flush();
      await output.close();
      output = null;
      _check();
      // Preserve a winner from another request. Replacement only occurs after
      // all incoming bytes are validated, within our versioned media namespace.
      if (await _verified(target, file)) return target.uri;
      await temp.rename(target.path);
      return target.uri;
    } finally {
      try {
        await output?.close();
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
  }

  @override
  Future<Uri> materialize(coach.PoseHubPackFile file, Uri source) async {
    final target = await _target(file.path, createParents: true);
    if (await _verified(target, file)) return target.uri;
    return _publish(
      file,
      target,
      File.fromUri(source).openRead(),
      (_) {},
      () {},
    );
  }

  @override
  void cancelVideoDownloads() {
    final videoPaths = videos.map((file) => file.path).toSet();
    for (final entry in _clients.entries.toList()) {
      if (videoPaths.contains(entry.value)) entry.key.close(force: true);
    }
  }

  @override
  Future<int> videoCacheBytes() async {
    _check();
    var bytes = 0;
    for (final video in videos) {
      final target = await _target(video.path);
      try {
        final stat = await target.stat();
        if (stat.type == FileSystemEntityType.file) bytes += stat.size;
      } on FileSystemException {
        // A download/clear may change an entry during this usage snapshot.
      }
    }
    return bytes;
  }

  @override
  Future<void> clearVideoCache() async {
    _check();
    for (final video in videos) {
      final target = await _target(video.path);
      if (await target.exists()) await target.delete();
      if (!await target.parent.exists()) continue;
      final filename = target.uri.pathSegments.last;
      final ownedPart = RegExp(
        '^${RegExp.escape(filename)}\\.\\d+_\\d+_\\d+\\.part\$',
      );
      await for (final entry in target.parent.list(followLinks: false)) {
        if (entry is File && ownedPart.hasMatch(entry.uri.pathSegments.last)) {
          await entry.delete();
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final client in _clients.keys.toList()) {
      client.close(force: true);
    }
  }
}

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
