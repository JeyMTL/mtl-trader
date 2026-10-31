import 'package:intl/intl.dart';

// Money is deliberately fixed to en_US/USD. The account is denominated in
// dollars, so "$1,240.50" stays correct in every translation, keeps the mono
// columns aligned, and does not change the width of a chart axis label when the
// language switches. Dates do localise: month names are the part a reader
// actually expects to see in their own language.
final NumberFormat _money = NumberFormat.currency(
  locale: 'en_US',
  symbol: r'$',
  decimalDigits: 2,
);

final NumberFormat _compact = NumberFormat.compactCurrency(
  locale: 'en_US',
  symbol: r'$',
  decimalDigits: 0,
);

/// Date formatters are cached per language rather than built once, so a
/// language switch re-renders "12 Mar" as "12 mars" without rebuilding them on
/// every row of a long list.
final Map<String, DateFormat> _dates = <String, DateFormat>{};

DateFormat _date(String pattern) {
  final key = '${Intl.getCurrentLocale()}|$pattern';
  return _dates.putIfAbsent(key, () => DateFormat(pattern));
}

String money(num value) => _money.format(value);

String signedMoney(num value) =>
    '${value >= 0 ? '+' : ''}${_money.format(value)}';

String compactMoney(num value) => _compact.format(value);

String percent(num value) => '${value.toStringAsFixed(1)}%';

String timeOf(DateTime? value) =>
    value == null ? '—' : _date('HH:mm').format(value);

String dayOf(DateTime? value) =>
    value == null ? '—' : _date('d MMM').format(value);

String longDay(DateTime date) => _date('EEE, d MMM yyyy').format(date);

/// Minutes → `2h 15m`.
String durationText(num? minutes) {
  if (minutes == null || minutes.isNaN) return '—';
  final total = minutes.round().abs();
  if (total < 60) return '${total}m';
  final hours = total ~/ 60;
  final rest = total % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

/// Seconds → `1:23`, for recorder timers and voice-note labels.
/// Unknown durations stay `—` instead of pretending the file is empty.
String clockText(num? seconds) {
  if (seconds == null || seconds.isNaN) return '—';
  final total = seconds.round().abs();
  final minutes = total ~/ 60;
  return '$minutes:${(total % 60).toString().padLeft(2, '0')}';
}

/// `83` → `1:23`.
String elapsedSince(DateTime started) =>
    clockText(DateTime.now().difference(started).inSeconds);

String fileSize(num bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// `2026-10-28` → `28 Oct`.
String isoDayLabel(String iso) {
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : dayOf(parsed);
}
