import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mtl_trader_mobile/core/instruments.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations.dart';
import 'package:mtl_trader_mobile/screens/chart_picker_screen.dart';
import 'package:mtl_trader_mobile/ui/chart/sync_badge.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

/// The chart's account-copy badge at the narrowest phone width with doubled text.
///
/// The badge shares the app bar with four other actions, which is exactly where
/// a fifth element can push the bar past the screen. Each state is pinned through
/// `debugSyncState`: `saved` and `syncing` cannot be reached from a test
/// otherwise, because both need a live sync.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpChart(WidgetTester tester, ChartSyncState state) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildFlatTheme(AppPalette.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: ChartPickerScreen(
          instrument: const Instrument(
            'EURUSD',
            'Euro / US Dollar',
            'EURUSD=X',
            InstrumentKind.forex,
            5,
          ),
          direction: 'BUY',
          debugSyncState: state,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Nothing is clipped and nothing overflows: the badge has to be fully inside
  /// the 320 pt bar, not merely present in the tree.
  void expectOnScreen(WidgetTester tester, Finder finder) {
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
  }

  testWidgets('idle shows no badge and still fits', (tester) async {
    await pumpChart(tester, ChartSyncState.idle);

    expect(find.byType(ChartSyncBadge), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('syncing shows the spinner and still fits', (tester) async {
    await pumpChart(tester, ChartSyncState.syncing);

    expect(find.byType(ChartSyncBadge), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expectOnScreen(tester, find.byType(ChartSyncBadge));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('saved shows the tick and still fits', (tester) async {
    await pumpChart(tester, ChartSyncState.saved);

    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expectOnScreen(tester, find.byIcon(Icons.cloud_done_outlined));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('failed shows the cloud and explains itself when tapped', (
    tester,
  ) async {
    await pumpChart(tester, ChartSyncState.failed);

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expectOnScreen(tester, find.byIcon(Icons.cloud_off_outlined));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.cloud_off_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('could not reach your account'),
      findsOneWidget,
      reason: 'the failed badge must say why, not just colour itself red',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
