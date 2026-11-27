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

/// What a trade risks at its stop, stands to make at its target, and the ratio
/// between the two — the figures a trader reads before pressing save.
///
/// Only a level on the losing side counts as risk and only a winning one as
/// reward. A stop above the entry of a buy is a typo the form refuses to save,
/// and a preview that called it a loss would be describing a trade the market
/// cannot print. Commission and swap are left out on purpose: the preview is
/// about the levels, and the costs are typed after them.
///
/// The two flags say whether a level was entered on the side that cannot be
/// hit first. Both figures are zero in that case, which is indistinguishable
/// from "no levels yet", and the strip owes the trader which one it is: "add a
/// level" in front of a stop that was simply typed two digits out is the sort
/// of hint that makes a form feel like it is not listening.
({
  double risk,
  double reward,
  double? r,
  bool stopWrongSide,
  bool takeWrongSide,
}) riskRewardPreview({
  required String type,
  required String symbol,
  required double entry,
  required double? stop,
  required double? take,
  required double lots,
}) {
  double at(double price) => calculatePnl(
        type: type,
        symbol: symbol,
        entry: entry,
        exit: price,
        lots: lots,
      );
  final loss = stop == null ? 0.0 : -at(stop);
  final gain = take == null ? 0.0 : at(take);
  final risk = loss > 0 ? loss : 0.0;
  final reward = gain > 0 ? gain : 0.0;
  return (
    risk: risk,
    reward: reward,
    r: risk > 0 && reward > 0 ? reward / risk : null,
    // Reaching zero this way means the level is at or past the entry, which is
    // the wrong side — a level exactly on the entry is worth saying too.
    stopWrongSide: stop != null && loss <= 0,
    takeWrongSide: take != null && gain <= 0,
  );
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
