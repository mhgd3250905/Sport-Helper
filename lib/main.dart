import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/services.dart';
import 'core/storage/local_state_storage.dart';
import 'data/app_store.dart';
import 'ui/chat/chat_home_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/glass.dart';
import 'ui/theme/tokens.dart';
import 'voice/just_audio_output.dart';

/// The bundled font's licence on the 开源软件许可 page.
void registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/licenses/NotoSansSC-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Noto Sans SC'], text);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicense();
  // Pre-warm the glass shaders before the first frame (no white flash).
  await LiquidGlassWidgets.initialize();
  final (lib, catalog, voices) = await AppServices.loadContent();
  final store = AppStore(SharedPreferencesLocalStateStorage());
  await store.load();
  final services = AppServices(
    library: lib,
    catalog: catalog,
    store: store,
    voiceLibrary: voices,
    voiceOutput: JustAudioVoiceOutput(),
  );
  runApp(
    LiquidGlassWidgets.wrap(
      // Material theme mode drives the glass brightness.
      brightnessResolver: Theme.maybeBrightnessOf,
      // Benchmarks the device's raster budget and settles premium / standard
      // / minimal; the settled tier is kept so the next launch starts there.
      adaptiveQuality: true,
      adaptiveConfig: GlassAdaptiveScopeConfig(
        initialQuality: SfGlass.parse(store.glassQuality),
        onQualityChanged: (_, to) => store.setGlassQuality(to.name),
      ),
      child: SmartFitApp(services: services),
    ),
  );
}

class SmartFitApp extends StatefulWidget {
  const SmartFitApp({super.key, required this.services, this.fontFamily});
  final AppServices services;

  /// Kept for the screenshot harness; the app bundles Noto Sans SC.
  final String? fontFamily;
  @override
  State<SmartFitApp> createState() => _SmartFitAppState();
}

class _SmartFitAppState extends State<SmartFitApp> {
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
        // Glass widgets render text outside a Scaffold (toasts, overlays):
        // a transparent Material gives them Material text and ink.
        builder: (context, child) => Material(
          type: MaterialType.transparency,
          child: SfPaletteScope(child: child!),
        ),
        // The chat opens with the safety talk on first launch.
        home: const ChatHomePage(),
      ),
    ),
  );
}
