import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mtl_trader_mobile/l10n/app_localizations_pack.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations_en.dart';

/// Counted messages reach the screen through two paths: the compiled English
/// getter and a downloaded pack. Both have to read "1 trade" as one trade, and
/// a pack that was translated before the plural existed must keep working.
void main() {
  test('the compiled English plurals read one and many', () {
    final en = AppLocalizationsEn();
    expect(en.monthTrades(1), '1 trade');
    expect(en.monthTrades(2), '2 trades');
    expect(en.greenDays(1), '1 green day');
    expect(en.winnersCount(1), '1 winner');
    expect(en.a11yHeatmapDay('Mon', r'$12.00', 1), endsWith('1 trade'));
    expect(en.a11yHeatmapDay('Mon', r'$12.00', 4), endsWith('4 trades'));
  });

  test('a pack carrying the plural shape renders one and many', () {
    final pack = AppLocalizationsPack(const Locale('fr'), {
      'monthTrades': '{count, plural, =1{1 trade} other{{count} trades}}',
      'periodStats':
          '{trades, plural, =1{1 trade} other{{trades} trades}} · {winRate} win',
    });

    expect(pack.monthTrades(1), '1 trade');
    expect(pack.monthTrades(5), '5 trades');
    // A plural embedded in a longer message is resolved in place.
    expect(pack.periodStats(1, '64%'), '1 trade · 64% win');
    expect(pack.periodStats(9, '50%'), '9 trades · 50% win');
  });

  test('a pack that still holds a plain template only substitutes', () {
    final pack = AppLocalizationsPack(const Locale('fr'), {
      'monthTrades': '{count} transactions',
    });

    expect(pack.monthTrades(1), '1 transactions');
    expect(pack.monthTrades(3), '3 transactions');
  });

  test('a message the pack does not carry falls back to English plurals', () {
    final pack = AppLocalizationsPack(const Locale('fr'), const {});

    expect(pack.monthTrades(1), '1 trade');
    expect(pack.monthTrades(2), '2 trades');
  });
}
