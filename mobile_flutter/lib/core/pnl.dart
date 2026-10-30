String normalizeSymbol(String symbol) =>
    symbol.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Contract size per symbol, matching the web journal.
double pointValue(String symbol) {
  final s = normalizeSymbol(symbol);
  if (s.isEmpty) return 100000;
  if (s.endsWith('JPY')) return 1000;
  if (s.startsWith('XAU') || s.startsWith('GOLD')) return 100;
  if (s.startsWith('XAG') || s.startsWith('SILVER')) return 5000;
  if (s.startsWith('BTC') ||
      s.startsWith('ETH') ||
      s.startsWith('DOGE') ||
      s.startsWith('SOL') ||
      s.startsWith('ADA') ||
      s.startsWith('XRP') ||
      s.startsWith('DOT') ||
      s.startsWith('AVAX') ||
      s.startsWith('LINK')) {
    return 1;
  }
  if (s.startsWith('US30') ||
      s.startsWith('DJ30') ||
      s.startsWith('NAS100') ||
      s.startsWith('NASDAQ') ||
      s.startsWith('SPX500') ||
      s.startsWith('SP500') ||
      s.startsWith('US500') ||
      s.startsWith('US100') ||
      s.startsWith('US2000') ||
      s.startsWith('USTEC') ||
      s.startsWith('DAX') ||
      s.startsWith('FTSE') ||
      s.startsWith('UK100') ||
      s.startsWith('JP225') ||
      s.startsWith('NIKKEI')) {
    return 1;
  }
  if (s.startsWith('USOIL') ||
      s.startsWith('WTI') ||
      s.startsWith('BRN') ||
      s.startsWith('BRENT') ||
      s.startsWith('NATGAS') ||
      s.startsWith('NGAS')) {
    return 1000;
  }
  return 100000;
}

/// P&L = price movement × lots × contract size + commission + swap.
/// Commission and swap are signed (negative means a cost), as MT5 reports them.
double calculatePnl({
  required String type,
  required String symbol,
  required double entry,
  required double exit,
  required double lots,
  double commission = 0,
  double swap = 0,
}) {
  final move = type.toUpperCase() == 'SELL' ? entry - exit : exit - entry;
  return move * lots * pointValue(symbol) + commission + swap;
}

double pipSize(String symbol) {
  final s = normalizeSymbol(symbol);
  if (s.isEmpty) return 0.0001;
  if (s.endsWith('JPY')) return 0.01;
  if (s.startsWith('XAU') ||
      s.startsWith('GOLD') ||
      s.startsWith('XAG') ||
      s.startsWith('SILVER')) {
    return 0.1;
  }
  if (pointValue(s) == 1) return 1;
  if (pointValue(s) == 1000 && !s.endsWith('JPY')) return 0.01;
  return 0.0001;
}
