import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:mtl_trader_mobile/core/format.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations.dart';

void main() {
  // The app loads intl's date data in `main`; a unit test has to do it too.
  setUpAll(() => initializeDateFormatting());

  test('every supported language resolves its strings', () {
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
      containsAll(<String>['en', 'fr']),
    );

    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      expect(l10n.navDesk, isNotEmpty,
          reason: 'navDesk for ${locale.languageCode}');
      expect(l10n.accountBalance, isNotEmpty);
      expect(l10n.navAccount, isNotEmpty);
    }
  });

  test('profit and loss are announced with a direction, not just a number', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.a11yProfit(r'$120.00'), contains('Profit'));
    expect(en.a11yLoss(r'$40.00'), contains('Loss'));
    expect(en.a11yBreakEven(r'$0.00'), contains('Break even'));

    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(fr.a11yProfit(r'$120.00'), contains('Gain'));
    expect(fr.a11yLoss(r'$40.00'), contains('Perte'));
  });

  test('placeholders survive translation', () {
    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(fr.netSummary(r'+$10.00', 4, 3, 1), contains(r'+$10.00'));
    expect(fr.periodStats(5, '60.0%'), contains('5'));
    expect(fr.periodStats(5, '60.0%'), contains('60.0%'));
  });

  test('dates follow the active language, money stays USD', () {
    final date = DateTime(2026, 3, 12);

    Intl.defaultLocale = 'en';
    expect(dayOf(date), '12 Mar');
    expect(longDay(date), 'Thu, 12 Mar 2026');

    Intl.defaultLocale = 'fr';
    expect(dayOf(date), '12 mars');

    // The account is denominated in dollars, so the amount does not change
    // shape with the language.
    expect(money(1234.5), r'$1,234.50');
    expect(signedMoney(-12), r'-$12.00');

    Intl.defaultLocale = 'en';
  });
}
