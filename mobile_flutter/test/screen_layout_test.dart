import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations.dart';
import 'package:mtl_trader_mobile/models/models.dart';
import 'package:mtl_trader_mobile/screens/dashboard_screen.dart';
import 'package:mtl_trader_mobile/screens/journal_screen.dart';
import 'package:mtl_trader_mobile/screens/trade_form_screen.dart';
import 'package:mtl_trader_mobile/services/journal_api.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

/// Empty but well-typed data, so every panel lays itself out: an overflow lives
/// in the layout, and no request needs to leave the test to reach it.
///
/// The screens are handed this instead of a real `JournalApi` because building
/// one creates a Supabase client, whose periodic token refresh the test binding
/// reports as a pending timer.
class _FakeApi implements JournalApi {
  @override
  Future<DashboardData> dashboard() async => DashboardData(
        summary: TradeSummary.fromMap(const <String, dynamic>{}),
        equity: const [],
        deposits: 0,
        timeStats: TimeStats.empty,
        journalFeed: const [],
        recentTrades: const [],
      );

  @override
  Future<TradePageResult> tradePage({
    int limit = 25,
    int offset = 0,
    String? search,
    String filter = 'all',
    String? session,
  }) async =>
      TradePageResult.empty;

  @override
  Future<Map<String, ({int trades, int wins, double pnl})>>
      sessionStats() async => const {};

  @override
  Future<List<String>> strategyLabels({int limit = 20}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _harness(Widget home, {double scale = 2}) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildFlatTheme(AppPalette.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: home,
    );

/// Deliberately not `pumpAndSettle`: the brand mark pulses and the skeleton
/// shimmers forever, so the tree never settles. Three frames is what a first
/// layout — and therefore an overflow — needs.
Future<void> _firstPaint(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => initializeDateFormatting());

  setUp(() {
    // 320pt wide is the narrowest phone the store still serves; 2x text is the
    // largest system size, so together they are the worst case.
    // The height is tall on purpose: it lets the whole scroll view build in one
    // frame instead of only the first screenful.
  });

  testWidgets('the dashboard fits a 320pt phone at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        DashboardScreen(
          api: _FakeApi(),
          onOpenEdge: () {},
          onEdit: (_) {},
        ),
      ),
    );
    await _firstPaint(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the journal fits a 320pt phone at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(JournalScreen(api: _FakeApi(), onEdit: (_) {})),
    );
    await _firstPaint(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the trade form fits a 320pt phone at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(TradeFormScreen(api: _FakeApi())));
    await _firstPaint(tester);

    expect(tester.takeException(), isNull);
  });
}
