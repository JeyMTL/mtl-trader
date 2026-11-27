import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/features.dart';
import 'package:mtl_trader_mobile/core/market_widget.dart';

void main() {
  group('the market view holds the chart\'s place', () {
    test('the chart is off and the widget is on', () {
      expect(kMarketChartsEnabled, isFalse);
      expect(kMarketWidgetEnabled, isTrue);
    });
  });

  group('tradingViewSymbol', () {
    test('maps every instrument the view offers', () {
      for (final code in kMarketInstruments) {
        expect(
          tradingViewSymbol(code),
          matches(RegExp(r'^[A-Z]+:[A-Z0-9]+$')),
          reason: code,
        );
      }
    });

    test('pairs go to the FX feed, the rest to their own venue', () {
      expect(tradingViewSymbol('EURUSD'), 'FX:EURUSD');
      expect(tradingViewSymbol('GBPJPY'), 'FX:GBPJPY');
      expect(tradingViewSymbol('XAUUSD'), 'OANDA:XAUUSD');
      expect(tradingViewSymbol('BTCUSD'), 'COINBASE:BTCUSD');
      expect(tradingViewSymbol('NAS100'), 'CAPITALCOM:US100');
      expect(tradingViewSymbol('US30'), 'CAPITALCOM:US30');
      // Capital.com lists the Nikkei as J225; CAPITALCOM:JP225 is a 404.
      expect(tradingViewSymbol('JP225'), 'CAPITALCOM:J225');
    });

    test('reads the spellings brokers actually store', () {
      expect(tradingViewSymbol('EUR_USD'), 'FX:EURUSD');
      expect(tradingViewSymbol('eur/usd'), 'FX:EURUSD');
      expect(tradingViewSymbol(' eur usd '), 'FX:EURUSD');
      // Account-type tails.
      expect(tradingViewSymbol('EURUSDM'), 'FX:EURUSD');
      expect(tradingViewSymbol('XAUUSDM'), 'OANDA:XAUUSD');
      expect(tradingViewSymbol('EURUSDRAW'), 'FX:EURUSD');
      expect(tradingViewSymbol('NAS100.cash'), 'CAPITALCOM:US100');
      // A venue somebody else picked is not trusted over the mapping.
      expect(tradingViewSymbol('CAPITALCOM:XAUUSD'), 'OANDA:XAUUSD');
    });

    test('answers null rather than charting the wrong instrument', () {
      expect(tradingViewSymbol('XPTUSD'), isNull);
      expect(tradingViewSymbol('AAPL'), isNull);
      expect(tradingViewSymbol(''), isNull);
      expect(tradingViewSymbol('   '), isNull);
    });
  });

  group('market view intervals', () {
    test('offers no seconds, because TradingView does not render them free', () {
      expect(
        kMarketIntervals.where((interval) => interval.key.endsWith('s')),
        isEmpty,
      );
    });

    test('sends TradingView its own codes, in UTC', () {
      final uri = marketViewUri(
        symbol: 'FX:EURUSD',
        interval: kMarketIntervals.firstWhere((i) => i.key == '4h'),
      );

      expect(uri.host, 's.tradingview.com');
      expect(uri.path, '/widgetembed/');
      expect(uri.queryParameters['symbol'], 'FX:EURUSD');
      expect(uri.queryParameters['interval'], '240');
      expect(uri.queryParameters['timezone'], 'Etc/UTC');
      expect(uri.queryParameters['theme'], 'dark');
      // Attribution stays: the widget is free on that condition.
      expect(uri.queryParameters.containsKey('hidelogo'), isFalse);
      expect(uri.queryParameters['saveimage'], '0');
    });

    test('hides the toolbars that do not fit a phone', () {
      final uri = marketViewUri(
        symbol: 'FX:EURUSD',
        interval: kMarketIntervals.first,
      );
      // Their toolbar clipped its right-hand icons at 420 pt and repeated the
      // interval chips the screen already draws.
      expect(uri.queryParameters['hide_top_toolbar'], '1');
      expect(uri.queryParameters['hidesidetoolbar'], '1');
    });

    test('the daily size is D and the light theme changes the toolbar', () {
      final daily = marketViewUri(
        symbol: 'CAPITALCOM:US30',
        interval: kMarketIntervals.last,
      );
      expect(daily.queryParameters['interval'], 'D');

      final light = marketViewUri(
        symbol: 'FX:EURUSD',
        interval: kMarketIntervals.first,
        light: true,
      );
      expect(light.queryParameters['theme'], 'light');
      expect(light.queryParameters['toolbarbg'], 'f1f3f6');
    });
  });

  group('opening instrument', () {
    test('opens on the trader\'s own symbol when it maps', () {
      expect(marketInstrumentFor('XAUUSDM'), 'XAUUSD');
      expect(marketInstrumentFor('NAS100.cash'), 'NAS100');
      expect(marketInstrumentFor('EUR_USD'), 'EURUSD');
    });

    test('falls back to the first instrument rather than showing nothing', () {
      expect(marketInstrumentFor('XPTUSD'), kMarketInstruments.first);
      expect(marketInstrumentFor(null), kMarketInstruments.first);
    });

    test('labels pairs with a slash and leaves indices alone', () {
      expect(marketInstrumentLabel('EURUSD'), 'EUR/USD');
      expect(marketInstrumentLabel('NAS100'), 'NAS100');
    });
  });

  group('searching for an instrument', () {
    test('an empty query is the whole chip row', () {
      expect(marketInstrumentMatches(''), kMarketInstruments);
      expect(marketInstrumentMatches('   '), kMarketInstruments);
    });

    test('matches a fragment of the code however it is typed', () {
      expect(marketInstrumentMatches('eur'), contains('EURUSD'));
      expect(marketInstrumentMatches('EUR/USD'), contains('EURUSD'));
      expect(marketInstrumentMatches('nas'), <String>['NAS100']);
      expect(marketInstrumentMatches('us'), contains('US30'));
    });

    test('offers a cross the chips do not carry, but the mapping resolves', () {
      expect(marketInstrumentMatches('gbp jpy').first, 'GBPJPY');
      expect(marketInstrumentMatches('gbpjpy'), <String>['GBPJPY']);
      // An alias for an index the chips list under another name.
      expect(marketInstrumentMatches('jp225'), <String>['JP225']);
    });

    test('does not invent an instrument the mapping cannot chart', () {
      expect(marketInstrumentMatches('xptusd'), isEmpty);
      expect(marketInstrumentMatches('aapl'), isEmpty);
    });
  });
}
