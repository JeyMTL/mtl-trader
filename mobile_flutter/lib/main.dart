import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/chart_theme.dart';
import 'core/config.dart';
import 'core/language_packs.dart';
import 'core/locale.dart';
import 'screens/auth_gate.dart';
import 'services/telemetry.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _ConfigMissingApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // Month names come from intl's own locale data, which is empty until it is
  // loaded. Doing it here means no date format can run before the data exists,
  // whatever order the widget tree resolves languages in.
  await initializeDateFormatting();

  // The saved chart style and language, read once so the first frame is
  // already in the right palette and language.
  await ChartStyle.restore();
  await ThemeController.restore();
  await LocaleController.restore();
  // Packs already on the phone, read before the first frame so a downloaded
  // language is not briefly English. A saved language whose pack is missing
  // fetches itself below, so upgrading does not lose the choice.
  await LanguagePacks.instance.restore();
  unawaited(LanguagePacks.instance.ensureActivePack(
    LocaleController.instance.code,
  ));

  // Crash reporting, installed before the first frame so a failure while the
  // widget tree boots is still counted. `presentError` comes second so the red
  // screen in debug builds is unchanged.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Telemetry.crash(details.exception, details.stack, source: 'flutter');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Telemetry.crash(error, stack, source: 'platform');
    return true;
  };

  Telemetry.start();

  runApp(const MtlTraderApp());
}

class MtlTraderApp extends StatelessWidget {
  const MtlTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        ThemeController.instance,
        LocaleController.instance,
        LanguagePacks.instance,
      ]),
      builder: (context, _) {
        final appearance = ThemeController.instance.theme;
        final language = LocaleController.instance.code ?? 'system';
        return MaterialApp(
          title: 'MTL Trader',
          debugShowCheckedModeBanner: false,
          theme: buildFlatTheme(AppColors.palette),
          // Null locale means "follow the device", resolved against the
          // generated list, which falls back to English for anything else.
          locale: LocaleController.instance.locale,
          // The catalogue is what the picker offers; the delegate resolves each
          // entry from the bundled strings, a downloaded pack, or English.
          supportedLocales: LocaleController.supported,
          localizationsDelegates: LanguagePacks.instance.delegates,
          // The palette is read through `AppColors` getters rather than an
          // InheritedWidget, so a switch has to rebuild the tree. The key makes
          // Flutter discard the subtree instead of keeping const widgets that
          // still hold the old colours or the old strings.
          home: KeyedSubtree(
            key: ValueKey<String>(
              'theme-${appearance.name}-$language-'
              '${LanguagePacks.instance.generation}',
            ),
            child: const AuthGate(),
          ),
        );
      },
    );
  }
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildFlatTheme(AppColors.palette),
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'MTL Trader',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Supabase credentials are missing from this build.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Text(
                'Run the app with:',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'flutter run \\\n'
                '  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \\\n'
                '  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                style: TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 11.5,
                  height: 1.6,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Use the same URL and anon key as the web app (.env.local). The mobile app reads the same journal and storage bucket.',
                style: TextStyle(
                  color: AppColors.faint,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
