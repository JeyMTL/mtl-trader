import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/screens/prop_firm_screen.dart';
import 'package:mtl_trader_mobile/services/journal_api.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

/// The body `/api/prop-rules` returns once the consistency migration is applied:
/// the column exists, and `prop_status()` reports the best day against it.
///
/// The numbers match a real breach taken from the database, so the test covers
/// the case that matters — a day carrying 225% of the gain against a 30% rule.
Map<String, dynamic> _configured() => {
      'configured': true,
      'missing': false,
      'rules': {
        'account_size': 10000,
        'max_daily_loss_pct': 5,
        'max_drawdown_pct': 10,
        'trailing_drawdown': true,
        'profit_target_pct': 10,
        'min_trading_days': 5,
        'consistency_pct': 30,
        'started_on': '2026-11-01',
      },
      'status': {
        'configured': true,
        'account_size': 10000,
        'equity': 63.75,
        'peak_equity': 10174.23,
        'daily_pnl': 0,
        'daily_loss_limit': 500,
        'daily_headroom': 500,
        'drawdown': 10110.48,
        'drawdown_limit': 1017.42,
        'drawdown_headroom': 0,
        'profit_target': 1000,
        'profit_progress': -9936.25,
        'best_day_pnl': 7102,
        'consistency': 225.79,
        'consistency_pct': 30,
        'trading_days': 4,
        'min_trading_days': 5,
        'trailing_drawdown': true,
        'max_daily_loss_pct': 5,
        'max_drawdown_pct': 10,
        'profit_target_pct': 10,
        'status': 'breach_drawdown',
      },
    };

/// Implements the interface rather than extending `JournalApi`: the real one
/// builds a Supabase client whose token refresh the test binding reports as a
/// pending timer.
class _FakeApi implements JournalApi {
  _FakeApi(this.body);

  final Map<String, dynamic> body;

  @override
  Future<Map<String, dynamic>> propRules() async => body;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _harness(Widget home, {double scale = 2}) => MaterialApp(
      theme: buildFlatTheme(AppPalette.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: home,
    );

void main() {
  testWidgets('the consistency meter shows on the prop firm screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(PropFirmScreen(api: _FakeApi(_configured()))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Four meters: daily loss, drawdown, profit target, consistency.
    expect(find.text('Consistency'), findsOneWidget);
    expect(find.text('225.8% / 30.0%'), findsOneWidget);
    expect(
      find.text('Best day \$7,102.00 · maximum 30.0% of total profit'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
  });

  testWidgets('without the column the meter is omitted, not shown empty',
      (tester) async {
    final body = _configured();
    (body['rules'] as Map<String, dynamic>).remove('consistency_pct');
    (body['status'] as Map<String, dynamic>)['consistency_pct'] = 0;

    await tester.pumpWidget(
      _harness(PropFirmScreen(api: _FakeApi(body)), scale: 1),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Consistency'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
  });
}
