import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app/services.dart';
import 'app/app_test_pack.dart';
import 'app/app_test_catalog.dart';
import 'app/app_test_content.dart';
import 'app/build_info.dart';
import 'app/device_identity.dart';
import 'app/training_media_config.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show TrainingMediaRepository, TrainingMediaScope;
import 'core/storage/local_state_storage.dart';
import 'data/app_store.dart';
import 'diagnostics/runtime_log.dart';
import 'diagnostics/frame_recorder.dart';
import 'diagnostics/performance_report.dart';
import 'diagnostics/performance_routes.dart';
import 'diagnostics/performance_vm.dart';
import 'diagnostics/performance_conditions.dart';
import 'diagnostics/performance_lab.dart';
import 'ui/chat/chat_home_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/glass.dart';
import 'ui/theme/adaptive_glass.dart';
import 'ui/theme/tokens.dart';
import 'voice/just_audio_output.dart';

/// The bundled font's licence on the 开源软件许可 page.
void registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'assets/licenses/NotoSansSC-OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(const ['Noto Sans SC'], text);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureSystemUi();
  final storage = SharedPreferencesLocalStateStorage();
  final log = RuntimeLog.instance = RuntimeLog(
    enabled: RuntimeLog.buildEnabled,
    storage: storage,
  );
  await log.initialize();
  log.record(
    'app.start',
    fields: {
      'version': AppBuildInfo.version,
      'flavor': TrainingMediaConfig.isInternal ? 'internal' : 'production',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    },
  );
  if (log.enabled) {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      log.record(
        'app.flutter_error',
        fields: {'errorType': RuntimeLog.errorType(details.exception)},
      );
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      log.record(
        'app.unhandled_error',
        fields: {'errorType': RuntimeLog.errorType(error)},
      );
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }
  registerFontLicense();
  // Pre-warm the glass shaders before the first frame (no white flash).
  await LiquidGlassWidgets.initialize();
  log.record('app.shaders_ready');
  final media = await TrainingMediaRepository.create(
    manifestAsset: TrainingMediaConfig.manifestAsset,
    baseUrls: TrainingMediaConfig.baseUrls,
    allowPending: TrainingMediaConfig.includePending,
  );
  await media.availableActionIds();
  await media.canDownload();
  log.record(
    'app.media_ready',
    fields: {'count': media.visibleActions.length, 'offline': media.isOffline},
  );
  final testPack = await AppTestPack.load(rootBundle.loadString);
  final (lib, catalog, voices, coachCatalog) = await AppServices.loadContent(
    media: media,
    testPack: testPack,
  );
  AppTestContent? testContent;
  if (AppTestPackConfig.fullCatalog && testPack != null) {
    final index =
        jsonDecode(await rootBundle.loadString(AppTestPackConfig.indexAsset))
            as Map<String, dynamic>;
    final testCatalog = await AppTestCatalog.load(
      deliveryCatalogJson: await rootBundle.loadString(
        index['catalogAsset'] as String,
      ),
      bundledMedia: testPack.actions,
      readSemanticCatalog: (relativePath) async {
        final entry = (index['semanticSources'] as Map?)?[relativePath];
        if (entry is! String || !entry.startsWith('assets/app_test_pack/')) {
          return null;
        }
        final bytes = await rootBundle.load(entry);
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      },
    );
    testContent = AppTestContent.build(
      catalog: testCatalog,
      legacyLibrary: lib,
    );
  }
  final activeLibrary = testContent?.library ?? lib;
  final activeCoachCatalog = testContent?.coachCatalog ?? coachCatalog;
  final coachProfile = coach.CoachProfile.fromJson(
    jsonDecode(await rootBundle.loadString('assets/coach/smartfit.json')),
  );
  log.record(
    'app.catalog_ready',
    fields: {
      'count': activeLibrary.length,
      'catalogCount': activeCoachCatalog.length,
      if (testContent != null)
        'browseCount': testContent.catalog.entries.length,
    },
  );
  final store = AppStore(storage);
  await store.load();
  log.record('app.state_initialized');
  media.wifiOnly = store.mediaWifiOnly;
  String? deviceId;
  try {
    deviceId = await DeviceIdentity(storage).loadOrCreate();
  } on Object catch (error) {
    log.record(
      'app.identity_unavailable',
      fields: RuntimeLog.errorFields(error),
    );
    // No persisted identifier means no proxy call; offline training still works.
  }
  final services = AppServices(
    library: activeLibrary,
    catalog: catalog,
    store: store,
    voiceLibrary: voices,
    voiceOutput: JustAudioVoiceOutput(),
    coachCatalog: activeCoachCatalog,
    testCatalog: testContent?.catalog,
    coachProfile: coachProfile,
    deviceId: deviceId,
    media: media,
  );
  log.record('app.ready');
  if (FrameRecorder.buildEnabled) {
    FrameRecorder.instance.start();
    installPerformanceServiceExtension();
    unawaited(PerformanceReportService.instance.initialize());
  }
  runApp(
    LiquidGlassWidgets.wrap(
      // Material theme mode drives the glass brightness.
      brightnessResolver: Theme.maybeBrightnessOf,
      // One App-owned monitor uses the exact display budget in every build.
      // The package's integer 16 ms default must not run alongside it.
      adaptiveQuality: false,
      child: SfAdaptiveGlass(
        initialQuality: SfGlass.initialQuality(store.glassQuality),
        onQualityChanged: (_, to) => store.setGlassQuality(to.name),
        freezeListenable: FrameRecorder.buildEnabled
            ? PerformanceLab.instance
            : null,
        freezeAdaptation: FrameRecorder.buildEnabled
            ? () => PerformanceLab.instance.freezeAdaptation
            : null,
        child: TrainingMediaScope(
          repository: media,
          child: SmartFitApp(services: services),
        ),
      ),
    ),
  );
}

/// Keep Android page backgrounds behind the system bars; each page's existing
/// SafeArea still protects its controls and the palette supplies icon contrast.
Future<void> configureSystemUi() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class SmartFitApp extends StatefulWidget {
  const SmartFitApp({super.key, required this.services, this.fontFamily});
  final AppServices services;

  /// Kept for the screenshot harness; the app bundles Noto Sans SC.
  final String? fontFamily;
  @override
  State<SmartFitApp> createState() => _SmartFitAppState();
}

class _SmartFitAppState extends State<SmartFitApp> with WidgetsBindingObserver {
  // Keeping this instance stable preserves Navigator's route history when the
  // app's existing store listener rebuilds MaterialApp.
  late final _performanceRoutes = FrameRecorder.buildEnabled
      ? PerformanceRouteObserver()
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    RuntimeLog.instance.record('app.lifecycle', fields: {'state': state.name});
    unawaited(RuntimeLog.instance.flush());
  }

  @override
  void dispose() {
    if (FrameRecorder.buildEnabled) FrameRecorder.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    RuntimeLog.instance.record('app.dispose');
    unawaited(RuntimeLog.instance.flush());
    unawaited(widget.services.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: ListenableBuilder(
      listenable: widget.services.store,
      builder: (context, _) => MaterialApp(
        title: '智能健身助手',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(SfPalette.light),
        darkTheme: buildTheme(SfPalette.dark),
        themeMode: switch (widget.services.store.appearance) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        },
        themeAnimationDuration: Duration.zero,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorObservers: [?_performanceRoutes],
        // Glass widgets render text outside a Scaffold (toasts, overlays):
        // a transparent Material gives them Material text and ink.
        builder: (context, child) {
          if (FrameRecorder.buildEnabled) {
            final store = widget.services.store;
            FrameRecorder.instance.setMetadata({
              'appearance': store.appearance,
              'theme': Theme.of(context).brightness.name,
              'contentActionCount': widget.services.library.length,
              'chatMessageCount': widget.services.chat.messages.length,
            });
          }
          return Material(
            type: MaterialType.transparency,
            child: SfPaletteScope(
              child: FrameRecorder.buildEnabled
                  ? PerformanceConditions(
                      store: widget.services.store,
                      child: child!,
                    )
                  : child!,
            ),
          );
        },
        // The chat opens with the safety talk on first launch.
        home: const ChatHomePage(),
      ),
    ),
  );
}
