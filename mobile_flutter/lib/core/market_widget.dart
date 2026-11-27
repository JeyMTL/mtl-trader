/// The TradingView market view, for the phone.
///
/// A straight mirror of `src/lib/market-widget.ts`, and deliberately a mirror
/// rather than a fetched config: the two clients show the same instruments on
/// the same TradingView symbols, and a table that only lives on a server is a
/// table that drifts. The tests read both files' intent, not their bytes.
///
/// The prices are TradingView's, inside TradingView's own WebView. Nothing here
/// is redistribution, and nothing here needs a data licence.
library;

/// Candle sizes TradingView renders for free. Seconds are not offered.
class MarketInterval {
  const MarketInterval(this.key, this.label, this.tv);

  /// The key the rest of the app uses.
  final String key;

  /// What the chip says.
  final String label;

  /// TradingView's own interval code.
  final String tv;
}

const List<MarketInterval> kMarketIntervals = <MarketInterval>[
  MarketInterval('1m', '1m', '1'),
  MarketInterval('5m', '5m', '5'),
  MarketInterval('15m', '15m', '15'),
  MarketInterval('1h', '1h', '60'),
  MarketInterval('4h', '4h', '240'),
  MarketInterval('1d', '1d', 'D'),
];

/// Instruments the market view offers, spelled the way a terminal does.
const List<String> kMarketInstruments = <String>[
  'EURUSD',
  'GBPUSD',
  'USDJPY',
  'AUDUSD',
  'USDCAD',
  'USDCHF',
  'XAUUSD',
  'XAGUSD',
  'BTCUSD',
  'ETHUSD',
  'US30',
  'NAS100',
  'SPX500',
  'GER40',
];

/// Symbols whose TradingView home is not the default FX feed.
///
/// Every value here was checked against its TradingView symbol page; the Nikkei
/// in particular is `CAPITALCOM:J225`, because `CAPITALCOM:JP225` is a 404.
const Map<String, String> _pinned = <String, String>{
  'XAUUSD': 'OANDA:XAUUSD',
  'XAGUSD': 'OANDA:XAGUSD',
  'BTCUSD': 'COINBASE:BTCUSD',
  'ETHUSD': 'COINBASE:ETHUSD',
  'US30': 'CAPITALCOM:US30',
  'NAS100': 'CAPITALCOM:US100',
  'US100': 'CAPITALCOM:US100',
  'USTEC': 'CAPITALCOM:US100',
  'SPX500': 'CAPITALCOM:US500',
  'US500': 'CAPITALCOM:US500',
  'GER40': 'CAPITALCOM:DE40',
  'DE40': 'CAPITALCOM:DE40',
  'UK100': 'CAPITALCOM:UK100',
  'JP225': 'CAPITALCOM:J225',
};

const Set<String> _currencies = <String>{
  'USD', 'EUR', 'JPY', 'GBP', 'AUD', 'CHF', 'CAD', 'NZD',
  'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF', 'TRY', 'ZAR',
  'MXN', 'SGD', 'HKD', 'CNH',
};

/// Account-type tails brokers stick on a symbol: XAUUSDM, EURUSDRAW, NAS100CASH.
/// Longest first, so `MICRO` is never mistaken for a bare `M`.
const List<String> _suffixes = <String>[
  'MICRO', 'MINI', 'CASH', 'SPOT', 'RAW', 'ECN', 'PRO', 'M',
];

/// `EUR_USD`, `eur/usd` and `EURUSD` all mean the same pair.
String _compact(String raw) {
  // A symbol already carrying an exchange (`OANDA:EURUSD`) keeps only its code:
  // the mapping decides the venue, not whatever the caller guessed.
  final colon = raw.indexOf(':');
  final bare = colon >= 0 ? raw.substring(colon + 1) : raw;
  return bare.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

String? _lookup(String code) {
  final pinned = _pinned[code];
  if (pinned != null) return pinned;
  return _isPair(code) ? 'FX:$code' : null;
}

bool _isPair(String code) {
  if (code.length != 6) return false;
  return _currencies.contains(code.substring(0, 3)) &&
      _currencies.contains(code.substring(3));
}

/// A broker symbol to the symbol TradingView knows, or null when it cannot be
/// mapped confidently.
///
/// Returning null is the point: a market view that silently charts EUR/USD
/// because the customer asked for `XPTUSD` is worse than one that says it does
/// not carry that instrument.
String? tradingViewSymbol(String raw) {
  final code = _compact(raw);
  if (code.isEmpty) return null;

  final direct = _lookup(code);
  if (direct != null) return direct;

  for (final suffix in _suffixes) {
    if (code.length > suffix.length && code.endsWith(suffix)) {
      final trimmed = _lookup(code.substring(0, code.length - suffix.length));
      if (trimmed != null) return trimmed;
    }
  }

  return null;
}

/// The URL the WebView loads.
///
/// Branding stays on: the widget is free on the condition that its attribution
/// remains visible, and `hideideas` only hides the *ideas* strip.
Uri marketViewUri({
  required String symbol,
  required MarketInterval interval,
  bool light = false,
}) {
  return Uri.https('s.tradingview.com', '/widgetembed/', <String, String>{
    'symbol': symbol,
    'interval': interval.tv,
    'theme': light ? 'light' : 'dark',
    'style': '1',
    'timezone': 'Etc/UTC',
    'locale': 'en',
    // A phone cannot fit TradingView's own toolbar: at 420 pt its right-hand
    // icons are cut off, and its interval buttons duplicate the chips above.
    // The native pickers are the controls here, so both toolbars stay hidden.
    'hide_top_toolbar': '1',
    'hidesidetoolbar': '1',
    'symboledit': '1',
    'saveimage': '0',
    'withdateranges': '1',
    'hideideas': '1',
    'toolbarbg': light ? 'f1f3f6' : '131722',
  });
}

/// The instrument the view opens on: the trader's own symbol when it maps,
/// otherwise the first one that works.
String marketInstrumentFor(String? raw) {
  if (raw != null) {
    final wanted = tradingViewSymbol(raw);
    if (wanted != null) {
      for (final code in kMarketInstruments) {
        if (tradingViewSymbol(code) == wanted) return code;
      }
    }
  }
  return kMarketInstruments.first;
}

/// `EURUSD` reads as `EUR/USD`; indices keep their name.
///
/// Six letters is not enough to be a pair — `NAS100` is six characters too, and
/// splitting it in the middle reads as a currency it is not.
String marketInstrumentLabel(String code) =>
    _isPair(code) ? '${code.substring(0, 3)}/${code.substring(3)}' : code;
