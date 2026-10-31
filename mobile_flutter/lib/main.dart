import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/chart_theme.dart';
import 'core/config.dart';
import 'screens/auth_gate.dart';
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

  // The saved chart style, read once so the first chart already looks right.
  await ChartStyle.restore();
  await ThemeController.restore();

  runApp(const MtlTraderApp());
}

class MtlTraderApp extends StatelessWidget {
  const MtlTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final mode = ThemeController.instance.mode;
        return MaterialApp(
          title: 'MTL Trader',
          debugShowCheckedModeBanner: false,
          theme: buildFlatTheme(AppColors.palette),
          // The palette is read through `AppColors` getters rather than an
          // InheritedWidget, so a switch has to rebuild the tree. The key makes
          // Flutter discard the subtree instead of keeping const widgets that
          // still hold the old colours.
          home: KeyedSubtree(
            key: ValueKey<String>('theme-${mode.name}'),
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
      theme: buildFlatTheme(AppPalette.dark),
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
