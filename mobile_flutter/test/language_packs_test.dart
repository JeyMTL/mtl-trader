import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/language_packs.dart';
import 'package:mtl_trader_mobile/core/locale.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations.dart';
import 'package:mtl_trader_mobile/l10n/gen/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A published pack server: `/locales/manifest.json` plus one file per pack.
class _Server {
  final Map<String, String> bodies = <String, String>{};

  Future<String> get(Uri uri) async {
    final body = bodies[uri.path];
    if (body == null) throw StateError('not published: ${uri.path}');
    return body;
  }

  void manifest(List<Map<String, Object>> packs) {
    bodies['/locales/manifest.json'] = jsonEncode(<String, Object>{
      'packs': packs,
    });
  }

  void pack(String code, Map<String, String> messages, {int version = 1}) {
    bodies['/locales/$code.json'] = jsonEncode(<String, Object>{
      'code': code,
      'version': version,
      'messages': messages,
    });
  }
}

void main() {
  late _Server server;
  late LanguagePacks packs;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = _Server();
    packs = LanguagePacks(fetch: server.get);
    LanguagePacks.instance = packs;
  });

  tearDown(() {
    LanguagePacks.instance = LanguagePacks();
  });

  test('the manifest advertises packs without downloading them', () async {
    server.manifest(<Map<String, Object>>[
      <String, Object>{'code': 'fr', 'version': 7, 'bytes': 5120, 'keys': 147},
    ]);

    await packs.refreshManifest();

    final info = packs.infoFor('fr');
    expect(info, isNotNull);
    expect(info!.bytes, 5120);
    expect(info.version, 7);
    expect(info.keys, 147);
    expect(packs.isInstalled('fr'), isFalse);
  });

  test('the manifest ignores languages the catalogue does not offer', () async {
    server.manifest(<Map<String, Object>>[
      <String, Object>{'code': 'fr', 'version': 1, 'bytes': 10, 'keys': 1},
      <String, Object>{'code': 'xx', 'version': 1, 'bytes': 10, 'keys': 1},
    ]);

    await packs.refreshManifest();

    expect(packs.available.keys, <String>['fr']);
  });

  test('downloading stores the messages and bumps the generation', () async {
    server.pack('fr', <String, String>{'navDesk': 'Bureau'});

    final before = packs.generation;
    expect(await packs.install('fr'), isTrue);

    expect(packs.isInstalled('fr'), isTrue);
    expect(packs.messagesFor('fr')!['navDesk'], 'Bureau');
    expect(packs.generation, greaterThan(before));
  });

  test('a downloaded pack survives a restart', () async {
    server.pack('fr', <String, String>{'navDesk': 'Bureau'});
    await packs.install('fr');

    final restarted = LanguagePacks(fetch: server.get);
    await restarted.restore();

    expect(restarted.isInstalled('fr'), isTrue);
    expect(restarted.messagesFor('fr')!['navDesk'], 'Bureau');
  });

  test('removing a pack deletes it from the phone too', () async {
    server.pack('fr', <String, String>{'navDesk': 'Bureau'});
    await packs.install('fr');

    await packs.remove('fr');

    expect(packs.isInstalled('fr'), isFalse);
    final restarted = LanguagePacks(fetch: server.get);
    await restarted.restore();
    expect(restarted.isInstalled('fr'), isFalse);
  });

  test('a failed download leaves the phone untouched', () async {
    // Advertised but not published.
    server.manifest(<Map<String, Object>>[
      <String, Object>{'code': 'de', 'version': 1, 'bytes': 10, 'keys': 1},
    ]);
    await packs.refreshManifest();

    expect(await packs.install('de'), isFalse);
    expect(packs.isInstalled('de'), isFalse);
    expect(packs.errorFor('de'), isNotNull);
    expect(packs.isInstalling('de'), isFalse);
  });

  test('a pack localises its keys and falls back to English for the rest',
      () async {
    server.pack('fr', <String, String>{
      'navDesk': 'Bureau',
      'netSummary': '{pnl} net · {closed} clos',
    });
    await packs.install('fr');

    final AppLocalizations fr =
        await packs.delegates.first.load(const Locale('fr')) as AppLocalizations;

    expect(fr.navDesk, 'Bureau');
    // Translated method with placeholders.
    expect(fr.netSummary(r'+$10.00', 4, 3, 1), r'+$10.00 net · 4 clos');
    // Untranslated key, getter and method, fall back per message.
    expect(fr.accountBalance, 'Account balance');
    expect(fr.a11yProfit(r'$120.00'), contains('Profit'));
  });

  test('a language without a pack resolves, in English', () async {
    final AppLocalizations de =
        await packs.delegates.first.load(const Locale('de')) as AppLocalizations;

    expect(de, isA<AppLocalizationsEn>());
    expect(de.navDesk, 'Desk');
  });

  test('every catalogue language is accepted by the delegate', () {
    final delegate = packs.delegates.first;
    for (final entry in LocaleController.languages) {
      expect(
        delegate.isSupported(Locale(entry.code)),
        isTrue,
        reason: entry.code,
      );
    }
  });
}
