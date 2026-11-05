import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:mtl_trader_mobile/core/format.dart';
import 'package:mtl_trader_mobile/core/language_packs.dart';
import 'package:mtl_trader_mobile/core/locale.dart';
import 'package:mtl_trader_mobile/l10n/app_localizations_pack.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations.dart';

/// The French strings as published, read from the ARB the pack is built from.
/// Reading the source rather than the JSON keeps this independent of whether
/// `node scripts/make-locales.mjs` has run in this checkout.
Map<String, String> publishedPack(String code) {
  final decoded = jsonDecode(
    File('lib/l10n/packs/app_$code.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return <String, String>{
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value as String,
  };
}

void main() {
  // The app loads intl's date data in `main`; a unit test has to do it too.
  setUpAll(() => initializeDateFormatting());

  test('English is the only language compiled into the app', () {
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
      <String>['en'],
    );
  });

  test('every catalogue language is offered by the app delegates', () {
    final delegate = LanguagePacks.instance.delegates.first;
    for (final entry in LocaleController.languages) {
      expect(
        delegate.isSupported(Locale(entry.code)),
        isTrue,
        reason: '${entry.code} is not accepted by the delegate',
      );
    }
  });

  test('every published pack covers every message', () {
    final english =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
    final keys = english.keys.where((key) => !key.startsWith('@')).toSet();

    final packs = Directory('lib/l10n/packs')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.arb'))
        .toList();
    expect(packs, isNotEmpty);

    for (final file in packs) {
      final messages =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final missing = keys.difference(messages.keys.toSet());
      expect(
        missing,
        isEmpty,
        reason: '${file.path} is missing ${missing.length} messages',
      );
    }
  });

  test('the published French pack translates the interface', () {
    final fr = AppLocalizationsPack(const Locale('fr'), publishedPack('fr'));

    expect(fr.navDesk, 'Bureau');
    expect(fr.language, 'Langue');
    expect(fr.accountBalance, 'Solde du compte');
    expect(fr.a11yProfit(r'$120.00'), contains('Gain'));
    expect(fr.a11yLoss(r'$40.00'), contains('Perte'));
  });

  test('a message the pack leaves out falls back to English', () {
    final fr = AppLocalizationsPack(const Locale('fr'), <String, String>{});

    expect(fr.navDesk, 'Desk');
    expect(fr.language, 'Language');
    expect(fr.a11yProfit(r'$1.00'), contains('Profit of'));
  });

  test('placeholders survive translation', () {
    final fr = AppLocalizationsPack(const Locale('fr'), publishedPack('fr'));

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
