import 'pnl.dart' show normalizeSymbol;

/// The instruments the journal ships with, so a trader never has to type a
/// ticker by hand. `symbol` is what is stored on the trade; `yahoo` is the
/// ticker used by the delayed chart feed that pins the levels.
enum InstrumentKind {
  forex('Forex'),
  metal('Metals'),
  indices('Indices'),
  crypto('Crypto'),
  energy('Energy');

  const InstrumentKind(this.label);
  final String label;
}

class Instrument {
  const Instrument(
    this.symbol,
    this.name,
    this.yahoo,
    this.kind,
    this.decimals,
  );

  /// Journal symbol, e.g. `NAS100`.
  final String symbol;

  /// Human label, e.g. `Nasdaq 100`.
  final String name;

  /// Ticker for the chart feed.
  final String yahoo;

  final InstrumentKind kind;

  /// Decimals used when a chart tap fills a price field.
  final int decimals;

  bool get isIndex => kind == InstrumentKind.indices;

  /// Spot forex and crypto come from free, live feeds. Exchange-traded
  /// instruments (indices and futures) need a paid licence for real time, so
  /// the free feed is delayed for them.
  bool get isLive =>
      kind == InstrumentKind.forex || kind == InstrumentKind.crypto;

  bool get isDelayed => !isLive;
}

const List<Instrument> instrumentCatalog = [
  // Forex majors
  Instrument('EURUSD', 'Euro / US Dollar', 'EURUSD=X', InstrumentKind.forex, 5),
  Instrument('GBPUSD', 'British Pound / US Dollar', 'GBPUSD=X',
      InstrumentKind.forex, 5),
  Instrument('USDJPY', 'US Dollar / Japanese Yen', 'USDJPY=X',
      InstrumentKind.forex, 3),
  Instrument(
      'USDCHF', 'US Dollar / Swiss Franc', 'USDCHF=X', InstrumentKind.forex, 5),
  Instrument('USDCAD', 'US Dollar / Canadian Dollar', 'USDCAD=X',
      InstrumentKind.forex, 5),
  Instrument('AUDUSD', 'Australian Dollar / US Dollar', 'AUDUSD=X',
      InstrumentKind.forex, 5),
  Instrument('NZDUSD', 'New Zealand Dollar / US Dollar', 'NZDUSD=X',
      InstrumentKind.forex, 5),
  // Forex crosses
  Instrument(
      'EURGBP', 'Euro / British Pound', 'EURGBP=X', InstrumentKind.forex, 5),
  Instrument(
      'EURJPY', 'Euro / Japanese Yen', 'EURJPY=X', InstrumentKind.forex, 3),
  Instrument(
      'EURCHF', 'Euro / Swiss Franc', 'EURCHF=X', InstrumentKind.forex, 5),
  Instrument('EURAUD', 'Euro / Australian Dollar', 'EURAUD=X',
      InstrumentKind.forex, 5),
  Instrument(
      'EURCAD', 'Euro / Canadian Dollar', 'EURCAD=X', InstrumentKind.forex, 5),
  Instrument('EURNZD', 'Euro / New Zealand Dollar', 'EURNZD=X',
      InstrumentKind.forex, 5),
  Instrument('GBPJPY', 'British Pound / Japanese Yen', 'GBPJPY=X',
      InstrumentKind.forex, 3),
  Instrument('GBPCHF', 'British Pound / Swiss Franc', 'GBPCHF=X',
      InstrumentKind.forex, 5),
  Instrument('GBPAUD', 'British Pound / Australian Dollar', 'GBPAUD=X',
      InstrumentKind.forex, 5),
  Instrument('GBPCAD', 'British Pound / Canadian Dollar', 'GBPCAD=X',
      InstrumentKind.forex, 5),
  Instrument('GBPNZD', 'British Pound / New Zealand Dollar', 'GBPNZD=X',
      InstrumentKind.forex, 5),
  Instrument('AUDJPY', 'Australian Dollar / Japanese Yen', 'AUDJPY=X',
      InstrumentKind.forex, 3),
  Instrument('AUDCAD', 'Australian Dollar / Canadian Dollar', 'AUDCAD=X',
      InstrumentKind.forex, 5),
  Instrument('AUDCHF', 'Australian Dollar / Swiss Franc', 'AUDCHF=X',
      InstrumentKind.forex, 5),
  Instrument('AUDNZD', 'Australian Dollar / New Zealand Dollar', 'AUDNZD=X',
      InstrumentKind.forex, 5),
  Instrument('CADJPY', 'Canadian Dollar / Japanese Yen', 'CADJPY=X',
      InstrumentKind.forex, 3),
  Instrument('CADCHF', 'Canadian Dollar / Swiss Franc', 'CADCHF=X',
      InstrumentKind.forex, 5),
  Instrument('CHFJPY', 'Swiss Franc / Japanese Yen', 'CHFJPY=X',
      InstrumentKind.forex, 3),
  Instrument('NZDJPY', 'New Zealand Dollar / Japanese Yen', 'NZDJPY=X',
      InstrumentKind.forex, 3),
  Instrument('NZDCAD', 'New Zealand Dollar / Canadian Dollar', 'NZDCAD=X',
      InstrumentKind.forex, 5),
  Instrument('NZDCHF', 'New Zealand Dollar / Swiss Franc', 'NZDCHF=X',
      InstrumentKind.forex, 5),
  // Forex exotics
  Instrument('USDMXN', 'US Dollar / Mexican Peso', 'USDMXN=X',
      InstrumentKind.forex, 4),
  Instrument('USDZAR', 'US Dollar / South African Rand', 'USDZAR=X',
      InstrumentKind.forex, 4),
  Instrument('USDTRY', 'US Dollar / Turkish Lira', 'USDTRY=X',
      InstrumentKind.forex, 4),
  Instrument('USDSEK', 'US Dollar / Swedish Krona', 'USDSEK=X',
      InstrumentKind.forex, 4),
  Instrument('USDNOK', 'US Dollar / Norwegian Krone', 'USDNOK=X',
      InstrumentKind.forex, 4),
  Instrument('USDSGD', 'US Dollar / Singapore Dollar', 'USDSGD=X',
      InstrumentKind.forex, 4),
  Instrument('USDHKD', 'US Dollar / Hong Kong Dollar', 'USDHKD=X',
      InstrumentKind.forex, 4),
  Instrument('USDCNH', 'US Dollar / Offshore Yuan', 'USDCNH=X',
      InstrumentKind.forex, 4),
  // Metals
  Instrument('XAUUSD', 'Gold / US Dollar', 'GC=F', InstrumentKind.metal, 2),
  Instrument('XAGUSD', 'Silver / US Dollar', 'SI=F', InstrumentKind.metal, 3),
  Instrument('XPTUSD', 'Platinum / US Dollar', 'PL=F', InstrumentKind.metal, 2),
  Instrument(
      'XPDUSD', 'Palladium / US Dollar', 'PA=F', InstrumentKind.metal, 2),
  // Indices
  Instrument('NAS100', 'Nasdaq 100', '^NDX', InstrumentKind.indices, 1),
  Instrument('US30', 'Dow Jones 30', '^DJI', InstrumentKind.indices, 1),
  Instrument('SPX500', 'S&P 500', '^GSPC', InstrumentKind.indices, 1),
  Instrument('US2000', 'Russell 2000', '^RUT', InstrumentKind.indices, 1),
  Instrument('GER40', 'DAX 40', '^GDAXI', InstrumentKind.indices, 1),
  Instrument('UK100', 'FTSE 100', '^FTSE', InstrumentKind.indices, 1),
  Instrument('FRA40', 'CAC 40', '^FCHI', InstrumentKind.indices, 1),
  Instrument('EU50', 'Euro Stoxx 50', '^STOXX50E', InstrumentKind.indices, 1),
  Instrument('JP225', 'Nikkei 225', '^N225', InstrumentKind.indices, 1),
  Instrument('AUS200', 'ASX 200', '^AXJO', InstrumentKind.indices, 1),
  Instrument('HK50', 'Hang Seng', '^HSI', InstrumentKind.indices, 1),
  // Crypto
  Instrument(
      'BTCUSD', 'Bitcoin / US Dollar', 'BTC-USD', InstrumentKind.crypto, 1),
  Instrument(
      'ETHUSD', 'Ethereum / US Dollar', 'ETH-USD', InstrumentKind.crypto, 2),
  Instrument(
      'SOLUSD', 'Solana / US Dollar', 'SOL-USD', InstrumentKind.crypto, 2),
  Instrument('XRPUSD', 'XRP / US Dollar', 'XRP-USD', InstrumentKind.crypto, 4),
  Instrument('BNBUSD', 'BNB / US Dollar', 'BNB-USD', InstrumentKind.crypto, 2),
  Instrument(
      'DOGEUSD', 'Dogecoin / US Dollar', 'DOGE-USD', InstrumentKind.crypto, 5),
  Instrument(
      'ADAUSD', 'Cardano / US Dollar', 'ADA-USD', InstrumentKind.crypto, 4),
  Instrument(
      'LTCUSD', 'Litecoin / US Dollar', 'LTC-USD', InstrumentKind.crypto, 2),
  // Energy
  Instrument('USOIL', 'WTI Crude', 'CL=F', InstrumentKind.energy, 2),
  Instrument('UKOIL', 'Brent Crude', 'BZ=F', InstrumentKind.energy, 2),
  Instrument('NATGAS', 'Natural Gas', 'NG=F', InstrumentKind.energy, 3),
];

/// Looks a written symbol up in the shipped catalog.
Instrument? findInstrument(String value) {
  final key = normalizeSymbol(value);
  if (key.isEmpty) return null;
  for (final item in instrumentCatalog) {
    if (item.symbol == key) return item;
  }
  return null;
}

/// Catalog match, else a forex fallback for a hand-typed six-letter pair such
/// as `EURUSD`. Returns null when no chart can be drawn for the symbol.
Instrument? inferInstrument(String value) {
  final exact = findInstrument(value);
  if (exact != null) return exact;
  final key = normalizeSymbol(value);
  if (key.length == 6 && RegExp(r'^[A-Z]{6}$').hasMatch(key)) {
    return Instrument(
      key,
      key,
      '$key=X',
      InstrumentKind.forex,
      key.endsWith('JPY') ? 3 : 5,
    );
  }
  return null;
}

/// A price with the instrument's decimals, ready for a form field.
String chartPrice(double value, Instrument instrument) =>
    value.toStringAsFixed(instrument.decimals);
