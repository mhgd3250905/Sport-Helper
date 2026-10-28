import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartfit/app/build_info.dart';

PackageInfo _package({String version = '0.1.0', String build = '2039'}) =>
    PackageInfo(
      appName: 'SmartFit',
      packageName: 'com.ugk.smartfit.internal',
      version: version,
      buildNumber: build,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reads installed package metadata including Android ABI build offset',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'SmartFit',
        packageName: 'com.ugk.smartfit.internal',
        version: '0.1.0',
        buildNumber: '2039',
        buildSignature: '',
      );
      await AppBuildInfo.initialize();
      expect(AppBuildInfo.versionName, '0.1.0');
      expect(AppBuildInfo.buildNumber, '2039');
      expect(AppBuildInfo.version, '0.1.0+2039');
    },
  );

  test(
    'a new installed package changes the identity without a code constant',
    () async {
      await AppBuildInfo.initialize(
        load: () async => _package(version: '2.4.1', build: '9042'),
      );
      expect(AppBuildInfo.versionName, '2.4.1');
      expect(AppBuildInfo.buildNumber, '9042');
      expect(AppBuildInfo.version, '2.4.1+9042');
    },
  );

  test(
    'metadata failure reports unknown and a later read can recover',
    () async {
      await AppBuildInfo.initialize(load: () async => _package());
      await AppBuildInfo.initialize(
        load: () async => throw StateError('metadata unavailable'),
      );
      expect(AppBuildInfo.versionName, 'unknown');
      expect(AppBuildInfo.buildNumber, 'unknown');
      expect(AppBuildInfo.version, 'unknown');
      await AppBuildInfo.initialize(load: () async => _package(build: '2040'));
      expect(AppBuildInfo.version, '0.1.0+2040');
    },
  );

  test(
    'empty platform fields never fall back to an old hardcoded build',
    () async {
      await AppBuildInfo.initialize(
        load: () async => _package(version: '', build: ''),
      );
      expect(AppBuildInfo.versionName, 'unknown');
      expect(AppBuildInfo.buildNumber, 'unknown');
      expect(AppBuildInfo.version, 'unknown');
    },
  );
}
