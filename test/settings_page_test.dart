import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/training_media_config.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/action_issue_store.dart';
import 'package:smartfit/chat/safety_script.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/settings_widgets.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/settings_tokens.dart';
import 'package:smartfit/ui/training_media_settings.dart';

import 'posehub_ui_support.dart';
import 'settings_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'cold settings restores a persisted disabled recording preference',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 6500);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final storage = PoseHubUiStorage();
      storage.values[LocalActionIssueStore.recordingKey] = 'false';
      final store = AppStore(storage, actionIssueEnabled: true);
      final services = settingsServices(store: store);
      addTearDown(services.dispose);
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.light,
          services: services,
          home: const AboutPage(),
        ),
      );
      if (TrainingMediaConfig.isInternal) {
        final first = tester.widget<SfSettingsSwitch>(
          find.byKey(const ValueKey('action-issues-recording')),
        );
        expect(first.value, isFalse);
        expect(first.onChanged, isNull);
      }
      await tester.pumpAndSettle();
      expect(store.actionIssueStore.enabled, isFalse);
      if (TrainingMediaConfig.isInternal) {
        final loaded = tester.widget<SfSettingsSwitch>(
          find.byKey(const ValueKey('action-issues-recording')),
        );
        expect(loaded.value, isFalse);
        expect(loaded.onChanged, isNotNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'settings D2/D3 hierarchy and functional settings ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cache = SettingsCacheRepository();
        final services = settingsServices(cache: cache);
        addTearDown(services.dispose);
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            services: services,
            home: const AboutPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-title-large')),
          findsOneWidget,
        );
        expect(find.text('背景星尘缓慢漂移'), findsOneWidget);
        expect(find.textContaining('离线动作素材'), findsNothing);
        expect(find.textContaining('训练说明待补'), findsNothing);
        expect(find.text('86.0 MB'), findsOneWidget);
        final expected = SfSettingsTokens(palette);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          expected.background,
        );
        await tester.tap(find.byKey(const ValueKey('appearance-light')));
        await tester.pumpAndSettle();
        expect(services.store.appearance, 'light');
        await tester.tap(find.byKey(const ValueKey('starfield-switch')));
        await tester.pumpAndSettle();
        expect(services.store.starfield, isFalse);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('settings-privacy')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-title-small')),
          findsOneWidget,
        );
        final icon = tester.widget<Image>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName.endsWith(
                  'smartfit-icon-v4-crop.png',
                ),
          ),
        );
        expect(icon.width, 56);
        expect(icon.height, 56);
        expect(
          find.text(
            '版本 0.1.0 (36)${TrainingMediaConfig.isInternal ? ' · 内测' : ''}',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('settings-privacy')));
        await tester.pumpAndSettle();
        final privacy = tester
            .widget<SelectableText>(find.byType(SelectableText))
            .data!;
        expect(privacy, contains('https://api.uuugk.win/v1'));
        expect(privacy, contains('每个设备每 10 分钟最多 30 次请求'));
        expect(
          tester
              .widget<SelectableText>(find.byType(SelectableText))
              .style!
              .height,
          1.7,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        cache.dispose();
      },
    );
  }

  testWidgets(
    'cache clear requires confirmation and failure remains retryable',
    (tester) async {
      final cache = SettingsCacheRepository();
      final services = settingsServices(cache: cache);
      addTearDown(services.dispose);
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.light,
          services: services,
          home: const TrainingMediaSettings(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('86.0 MB'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media-clear-cache')));
      await tester.pumpAndSettle();
      expect(cache.clears, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cache.clears, 0);
      cache.failClear = true;
      await tester.tap(find.byKey(const ValueKey('media-clear-cache')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('media-clear-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('缓存暂时无法清理，请稍后重试'), findsOneWidget);
      expect(cache.bytes, 86000000);
      cache.failClear = false;
      await tester.tap(find.byKey(const ValueKey('media-clear-cache')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('media-clear-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('0.0 MB'), findsOneWidget);
      expect(cache.clears, 2);
      expect(services.store.aiMemoryEnabled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      cache.dispose();
    },
  );

  testWidgets('legal and attribution text moved intact into secondary pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final services = settingsServices();
    addTearDown(services.dispose);
    await tester.pumpWidget(
      poseHubUiApp(
        palette: SfPalette.light,
        services: services,
        home: const AboutPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(disclaimerText), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-disclaimer')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      disclaimerText,
    );
    expect(find.byKey(const ValueKey('safety-recheck')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-material-licenses')));
    await tester.pumpAndSettle();
    final license = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(license, contains('Snow Rig © Blender Foundation'));
    expect(license, contains('Human Base Meshes（CC0）'));
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks([
        'settings-fixture',
      ], 'License fixture text retained.');
    });
    await tester.tap(find.byKey(const ValueKey('settings-open-source')));
    await tester.pumpAndSettle();
    final open = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(open, contains('settings-fixture'));
    expect(open, contains('License fixture text retained.'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'internal tools are gated by flavor even if capabilities are enabled',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 6500);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final services = settingsServices();
      addTearDown(services.dispose);
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: const AboutPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-internal-tools')),
        TrainingMediaConfig.isInternal ? findsOneWidget : findsNothing,
      );
      if (TrainingMediaConfig.isInternal) {
        final toggle = find.byKey(const ValueKey('action-issues-recording'));
        expect(tester.widget<SfSettingsSwitch>(toggle).value, isTrue);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(services.store.actionIssueStore.enabled, isFalse);
        expect(tester.widget<SfSettingsSwitch>(toggle).value, isFalse);
        await tester.tap(find.byKey(const ValueKey('action-issues-open')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('action-issues-export')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
