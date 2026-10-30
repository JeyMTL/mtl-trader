import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/instruments.dart';
import 'package:mtl_trader_mobile/services/market_data.dart';

void main() {
  group('instrument catalog', () {
    test('ships every asset class', () {
      for (final kind in InstrumentKind.values) {
        expect(
          instrumentCatalog.any((item) => item.kind == kind),
          isTrue,
          reason: '${kind.label} should have instruments',
        );
      }
    });

    test('finds a symbol regardless of case and separators', () {
      expect(findInstrument('eur/usd')?.symbol, 'EURUSD');
      expect(findInstrument(' nas100 ')?.symbol, 'NAS100');
      expect(findInstrument('GOLD'), isNull);
    });

    test('splits live spot feeds from delayed exchange feeds', () {
      expect(findInstrument('EURUSD')?.isLive, isTrue);
      expect(findInstrument('GBPJPY')?.isLive, isTrue);
      expect(findInstrument('BTCUSD')?.isLive, isTrue);
      expect(findInstrument('NAS100')?.isLive, isFalse);
      expect(findInstrument('NAS100')?.isDelayed, isTrue);
      expect(findInstrument('EURUSD')?.isDelayed, isFalse);
      expect(findInstrument('XAUUSD')?.isDelayed, isTrue);
      expect(findInstrument('USOIL')?.isDelayed, isTrue);
    });

    test('infers a chart for a hand-typed forex pair', () {
      final inferred = inferInstrument('gbpusd');
      expect(inferred?.yahoo, 'GBPUSD=X');
      expect(inferred?.decimals, 5);
      expect(inferInstrument('GBPJPY')?.decimals, 3);
      expect(inferInstrument('NOTREAL'), isNull);
    });

    test('formats prices with the instrument decimals', () {
      expect(chartPrice(1.084234, findInstrument('EURUSD')!), '1.08423');
      expect(chartPrice(28419.62, findInstrument('NAS100')!), '28419.6');
    });
  });

  group('chart payload', () {
    test('parses candles oldest first and drops empty quotes', () {
      final candles = parseChartPayload({
        'chart': {
          'result': [
            {
              'timestamp': [1793369400, 1793369100, 1793369700],
              'indicators': {
                'quote': [
                  {
                    'open': [1.10, 1.20, null],
                    'high': [1.15, 1.25, null],
                    'low': [1.05, 1.15, null],
                    'close': [1.12, 1.18, null],
                  },
                ],
              },
            },
          ],
          'error': null,
        },
      });

      expect(candles, hasLength(2));
      expect(candles.first.time.isBefore(candles.last.time), isTrue);
      expect(candles.first.time.isUtc, isTrue);
      expect(candles.first.open, 1.20);
      expect(candles.last.close, 1.12);
    });

    test('surfaces the feed error description', () {
      expect(
        () => parseChartPayload({
          'chart': {
            'result': null,
            'error': {'description': 'No data found, symbol may be delisted'},
          },
        }),
        throwsA(
          isA<MarketDataException>().having(
            (error) => error.message,
            'message',
            contains('No data found'),
          ),
        ),
      );
    });

    test('rejects an empty result set', () {
      expect(
        () => parseChartPayload({
          'chart': {'result': [], 'error': null},
        }),
        throwsA(isA<MarketDataException>()),
      );
    });
  });
}
