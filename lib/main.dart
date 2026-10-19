import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/services.dart';
import 'core/storage/local_state_storage.dart';
import 'data/app_store.dart';
import 'ui/home_page.dart';
import 'ui/safety_page.dart';
import 'ui/theme.dart';
import 'voice/just_audio_output.dart';
import 'voice/voice_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (lib, catalog) = await AppServices.loadContent();
  final store = AppStore(SharedPreferencesLocalStateStorage());
  await store.load();
  final services = AppServices(
    library: lib,
    catalog: catalog,
    store: store,
    voiceLibrary: await VoiceLibrary.load(),
    voiceOutput: JustAudioVoiceOutput(),
  );
  runApp(SmartFitApp(services: services));
}

class SmartFitApp extends StatefulWidget {
  const SmartFitApp({super.key, required this.services, this.fontFamily});
  final AppServices services;

  /// Only set by the screenshot harness (tests have no system CJK font).
  final String? fontFamily;
  @override
  State<SmartFitApp> createState() => _SmartFitAppState();
}

class _SmartFitAppState extends State<SmartFitApp> {
  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.services,
    child: MaterialApp(
      title: '智能健身助手',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(fontFamily: widget.fontFamily),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: widget.services.store.safetyAccepted
          ? const HomePage()
          : Builder(
              builder: (context) => SafetyPage(onDone: () => setState(() {})),
            ),
    ),
  );
}
