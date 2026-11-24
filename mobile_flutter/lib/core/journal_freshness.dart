/// Deciding whether a journal row is news.
///
/// `created_at` is when the database received the row. A first sync backfills
/// months of history in one burst, so the row inserted last can be a trade from
/// hours ago — which is how a trader in a BTC position gets told "EURUSDM
/// journaled". The trade's own close time answers the question the banner is
/// really asking.
library;

/// When the trade happened, in UTC: the close, or the open if it is missing.
DateTime? journaledTradeTime(Map<String, dynamic> row) {
  for (final key in const ['close_time', 'open_time']) {
    final value = row[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
  }
  return null;
}

/// Whether [row] is a trade that just happened, worth a banner and a toast.
///
/// Anything older than [window] came from a backfill, and a row with no usable
/// timestamp cannot be shown to be fresh. A time slightly in the future is
/// treated as fresh: the broker's clock is not this phone's clock.
bool isJustJournaled(
  Map<String, dynamic> row, {
  DateTime? now,
  Duration window = const Duration(minutes: 10),
}) {
  final at = journaledTradeTime(row);
  if (at == null) return false;
  final reference = (now ?? DateTime.now()).toUtc();
  return reference.difference(at) < window;
}
