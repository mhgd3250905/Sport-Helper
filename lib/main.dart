import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app/services.dart';
import 'app/device_identity.dart';
import 'core/storage/local_state_storage.dart';
import 'data/app_store.dart';
import 'ui/chat/chat_home_page.dart';
import 'ui/theme/app_theme.dart';
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
  registerFontLicense();
  final (lib, catalog, voices, coachCatalog) = await AppServices.loadContent();
  final coachProfile = coach.CoachProfile.fromJson(
    jsonDecode(await rootBundle.loadString('assets/coach/smartfit.json')),
  );
  final storage = SharedPreferencesLocalStateStorage();
  final store = AppStore(storage);
  await store.load();
  String? deviceId;
  try {
    deviceId = await DeviceIdentity(storage).loadOrCreate();
  } on Object {
    // No persisted identifier means no proxy call; offline training still works.
  }
  final services = AppServices(
    library: lib,
    catalog: catalog,
    store: store,
    voiceLibrary: voices,
    voiceOutput: JustAudioVoiceOutput(),
    coachCatalog: coachCatalog,
    coachProfile: coachProfile,
    deviceId: deviceId,
  );
  runApp(SmartFitApp(services: services));
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
  void dispose() {
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
        builder: (context, child) => SfPaletteScope(child: child!),
        // The chat opens with the safety talk on first launch.
        home: const ChatHomePage(),
      ),
    ),
  );
}
