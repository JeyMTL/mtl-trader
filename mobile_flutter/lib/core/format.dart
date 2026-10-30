import 'package:intl/intl.dart';

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

final DateFormat _time = DateFormat('HH:mm');
final DateFormat _day = DateFormat('d MMM');
final DateFormat _longDay = DateFormat('EEE, d MMM yyyy');

String money(num value) => _money.format(value);

String signedMoney(num value) =>
    '${value >= 0 ? '+' : ''}${_money.format(value)}';

String compactMoney(num value) => _compact.format(value);

String percent(num value) => '${value.toStringAsFixed(1)}%';

String timeOf(DateTime? value) => value == null ? '—' : _time.format(value);

String dayOf(DateTime? value) => value == null ? '—' : _day.format(value);

String longDay(DateTime date) => _longDay.format(date);

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
