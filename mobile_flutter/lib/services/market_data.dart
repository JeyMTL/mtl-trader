import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/instruments.dart';

/// Raised when the delayed chart feed cannot be read. The message is shown to
/// the trader as-is, so keep it short and actionable.
class MarketDataException implements Exception {
  MarketDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;

  bool get isUp => close >= open;
}

enum ChartRange {
  oneDay('5m', '1d', '1D'),
  fiveDays('15m', '5d', '5D'),
  oneMonth('1h', '1mo', '1M');

  const ChartRange(this.interval, this.range, this.label);

  final String interval;
  final String range;
  final String label;
}

/// Reads delayed OHLC candles used to pin entry, stop, target and exit levels.
///
/// This uses the public chart feed (no API key, no cost) and is only meant to
/// help a trader locate their levels. It is not a live execution feed.
class MarketDataService {
  MarketDataService({HttpClient? client}) : _client = client;

  /// Process-wide cache so reopening the chart paints instantly instead of
  /// going blank while another request runs.
  static final Map<String, _CachedCandles> _cache = {};
  static const int _maxEntries = 30;

  HttpClient? _client;

  /// Candles already fetched for this instrument and range, even when stale.
  List<Candle>? cached(Instrument instrument, ChartRange range) =>
      _cache[_cacheKey(instrument, range)]?.candles;

  DateTime? cachedAt(Instrument instrument, ChartRange range) =>
      _cache[_cacheKey(instrument, range)]?.at;

  static String _cacheKey(Instrument instrument, ChartRange range) =>
      '${instrument.yahoo}|${range.interval}|${range.range}';

  HttpClient get _http {
    final existing = _client;
    if (existing != null) return existing;
    final created = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _client = created;
    return created;
  }

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  Future<List<Candle>> candles(
    Instrument instrument,
    ChartRange range, {
    bool force = false,
  }) async {
    final key = _cacheKey(instrument, range);
    final entry = _cache[key];
    // Live spot feeds move faster than delayed exchange feeds, so they expire
    // sooner. Cached candles are returned without touching the network.
    final ttl = instrument.isLive
        ? const Duration(seconds: 45)
        : const Duration(minutes: 10);
    if (!force && entry != null && DateTime.now().difference(entry.at) < ttl) {
      return entry.candles;
    }

    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/'
      '${Uri.encodeComponent(instrument.yahoo)}'
      '?interval=${range.interval}&range=${range.range}&includePrePost=false',
    );

    final String body;
    try {
      body = await _fetch(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw MarketDataException(
        'The chart feed timed out. Check your connection and try again.',
      );
    } on MarketDataException {
      rethrow;
    } catch (_) {
      throw MarketDataException(
        'Could not reach the chart feed. Check your connection.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw MarketDataException('The chart feed returned an unreadable reply.');
    }

    final candles = parseChartPayload(decoded);
    if (candles.isEmpty) {
      throw MarketDataException('No candles came back for this instrument.');
    }
    _cache[key] = _CachedCandles(candles, DateTime.now());
    if (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return candles;
  }

  Future<String> _fetch(Uri uri) async {
    final request = await _http.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (compatible; MTLTrader/1.0)',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode == 429) {
      await response.drain<void>();
      throw MarketDataException(
        'The chart feed is busy right now. Try again in a minute.',
      );
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw MarketDataException(
        'The chart feed answered ${response.statusCode}. Try another range.',
      );
    }
    return response.transform(utf8.decoder).join();
  }
}

/// Parses the chart feed payload into candles sorted oldest → newest.
/// Null quotes (market closures) are dropped.
List<Candle> parseChartPayload(dynamic payload) {
  if (payload is! Map) {
    throw MarketDataException('Unexpected chart data.');
  }
  final chart = payload['chart'];
  if (chart is! Map) {
    throw MarketDataException('Unexpected chart data.');
  }

  final error = chart['error'];
  if (error is Map && error['description'] != null) {
    throw MarketDataException(error['description'].toString());
  }

  final results = chart['result'];
  if (results is! List || results.isEmpty) {
    throw MarketDataException('No chart data for that symbol.');
  }
  final result = results.first;
  if (result is! Map) {
    throw MarketDataException('No chart data for that symbol.');
  }

  final timestamps = result['timestamp'];
  if (timestamps is! List || timestamps.isEmpty) {
    throw MarketDataException('No chart data for that symbol.');
  }

  final indicators = result['indicators'];
  final quotes = indicators is Map ? indicators['quote'] : null;
  final quote = quotes is List && quotes.isNotEmpty ? quotes.first : null;
  if (quote is! Map) {
    throw MarketDataException('No chart data for that symbol.');
  }

  final opens = quote['open'];
  final highs = quote['high'];
  final lows = quote['low'];
  final closes = quote['close'];

  final candles = <Candle>[];
  for (var i = 0; i < timestamps.length; i++) {
    final stamp = timestamps[i];
    final open = _numAt(opens, i);
    final high = _numAt(highs, i);
    final low = _numAt(lows, i);
    final close = _numAt(closes, i);
    if (stamp is! num || open == null || high == null || low == null) {
      continue;
    }
    if (close == null) continue;
    candles.add(
      Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          (stamp * 1000).round(),
          isUtc: true,
        ),
        open: open,
        high: high,
        low: low,
        close: close,
      ),
    );
  }

  candles.sort((a, b) => a.time.compareTo(b.time));
  return candles;
}

class _CachedCandles {
  _CachedCandles(this.candles, this.at);

  final List<Candle> candles;
  final DateTime at;
}

double? _numAt(dynamic values, int index) {
  if (values is! List || index >= values.length) return null;
  final value = values[index];
  if (value is num) return value.toDouble();
  return null;
}
