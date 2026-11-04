import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/screens/subscription_screen.dart';
import 'package:mtl_trader_mobile/services/journal_api.dart';
import 'package:mtl_trader_mobile/ui/theme.dart';

/// Stands in for the network: the screen reads `profile()` before the first tap
/// and nothing else, so no request ever leaves this test.
///
/// It implements the interface rather than extending `JournalApi`, because the
/// real one builds a Supabase client, and that client starts a periodic token
/// refresh which the test binding then reports as a pending timer.
class _FakeApi implements JournalApi {
  _FakeApi(this.profileRow);

  final Map<String, dynamic> profileRow;

  @override
  Future<Map<String, dynamic>> profile() async => profileRow;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _basicMonthly() => {
      'subscription_tier': 'basic',
      'subscription_status': 'active',
      'max_trades': 50,
      'current_period_end':
          DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      'trial_ends_at': null,
    };

/// The worst case the store actually serves: a 320pt-wide phone at the largest
/// system text size. Overflow only ever shows up at a real width with real type,
/// which is why this pumps the screen rather than the individual widgets. The
/// height is generous so the lazily-built list actually reaches the plan cards.
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

Future<void> _reveal(WidgetTester tester, String text) =>
    tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );

void main() {
  testWidgets('the plans screen fits the narrowest phone at 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(SubscriptionScreen(api: _FakeApi(_basicMonthly()))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // The yearly cadence carries the widest label and the widest price.
    await _reveal(tester, 'Monthly');
    await tester.tap(find.text('Annual · 2 months free'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('/yr'), findsWidgets);

    // And the cards themselves, scrolled into view at this width.
    await _reveal(tester, 'Basic');
    await _reveal(tester, 'Pro');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a monthly subscriber gets the yearly switch, not a dead button',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(SubscriptionScreen(api: _FakeApi(_basicMonthly())), scale: 1),
    );
    await tester.pumpAndSettle();

    // Buying the month they already own is the mistake: the button is off.
    final repeat = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Current plan'),
    );
    expect(repeat.onPressed, isNull);

    await tester.tap(find.text('Annual · 2 months free'));
    await tester.pumpAndSettle();

    // Switching cadence stays open, and is what the server allows.
    final upgrade = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Switch to annual'),
    );
    expect(upgrade.onPressed, isNotNull);
  });
}
