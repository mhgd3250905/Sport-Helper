import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_pack_installation.dart';

void main() {
  final installed = Uri.parse('file:///data/user/0/test/files/posehub/v2/');

  test('default callers use one shared installation service', () {
    expect(PoseHubPackInstallation(), same(PoseHubPackInstallation()));
  });

  test('configuration requires both internal flavor and explicit opt in', () {
    expect(
      PoseHubPackConfig.enabled,
      const String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
          const bool.fromEnvironment('SMARTFIT_POSEHUB_PACK'),
    );
  });

  test('concurrent callers share work and completed URI is cached', () async {
    final completion = Completer<Uri>();
    var calls = 0;
    final service = PoseHubPackInstallation.forTesting(
      enabled: true,
      install: () {
        calls++;
        return completion.future;
      },
    );
    addTearDown(service.dispose);
    final snapshots = <bool>[];
    service.addListener(() => snapshots.add(service.busy));
    final first = service.ensureInstalled();
    expect(service.ensureInstalled(), same(first));
    expect(calls, 1);
    expect(service.busy, isTrue);
    expect(service.mediaBaseUri, isNull);
    completion.complete(installed);
    expect(await first, installed);
    expect(await service.ensureInstalled(), installed);
    expect(service.mediaBaseUri, installed);
    expect(service.error, isNull);
    expect(calls, 1);
    expect(snapshots, [true, false]);
  });

  test(
    'a failed shared attempt clears busy and supports a fresh retry',
    () async {
      var calls = 0;
      final failure = StateError('not enough space');
      final service = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () async {
          if (++calls == 1) throw failure;
          return installed;
        },
      );
      addTearDown(service.dispose);
      final attempt = service.ensureInstalled();
      expect(service.ensureInstalled(), same(attempt));
      await expectLater(attempt, throwsA(same(failure)));
      expect(service.busy, isFalse);
      expect(service.mediaBaseUri, isNull);
      expect(service.error, same(failure));
      expect(await service.ensureInstalled(), installed);
      expect(service.error, isNull);
      expect(calls, 2);
    },
  );

  test('disabled configuration never invokes a platform installer', () async {
    var calls = 0;
    final service = PoseHubPackInstallation.forTesting(
      enabled: false,
      install: () async {
        calls++;
        return installed;
      },
    );
    addTearDown(service.dispose);
    await expectLater(service.ensureInstalled(), throwsStateError);
    expect(calls, 0);
    expect(service.busy, isFalse);
  });

  for (final invalid in [
    'https://example.invalid/media/',
    'content://provider/media/',
    'file://remote-server/media/',
    'file:///',
    'file:///data/pack',
    'file:///data/pack/?',
    'file:///data/pack/?query=1',
    'file:///data/pack/#fragment',
  ]) {
    test('rejects an invalid media base: $invalid', () async {
      final service = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () async => Uri.parse(invalid),
      );
      addTearDown(service.dispose);
      await expectLater(service.ensureInstalled(), throwsFormatException);
      expect(service.mediaBaseUri, isNull);
      expect(service.busy, isFalse);
    });
  }
}
