import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/instruments.dart';

/// Raised when the candle feed cannot be read. The message is shown to the
/// trader as-is, so keep it short and actionable.
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

/// Reads mid-price candles used to pin entry, stop, target and exit levels.
///
/// The app never calls a market data provider directly: candles come from this
/// deployment's `/api/market/candles` route, which holds the market-data key.
/// That keeps the credential out of the binary and lets the server fall back to
/// the delayed public feed for instruments OANDA does not quote.
class MarketDataService {
  MarketDataService({HttpClient? client, String? Function()? accessToken})
      : _client = client,
        _accessToken = accessToken ?? _sessionToken;

  /// Process-wide cache so reopening the chart paints instantly instead of
  /// going blank while another request runs.
  static final Map<String, _CachedCandles> _cache = {};
  static const int _maxEntries = 30;

  final String? Function() _accessToken;

  HttpClient? _client;

  /// Candles already fetched for this instrument and range, even when stale.
  List<Candle>? cached(Instrument instrument, ChartRange range) =>
      _cache[_cacheKey(instrument, range)]?.candles;

  DateTime? cachedAt(Instrument instrument, ChartRange range) =>
      _cache[_cacheKey(instrument, range)]?.at;

  static String _cacheKey(
    Instrument instrument,
    ChartRange range, {
    int? fromMs,
    int? toMs,
  }) {
    // Historical windows are cached separately from the live tail: both hold
    // the same instrument and range but never the same candles.
    final suffix = fromMs == null || toMs == null ? '' : '|$fromMs-$toMs';
    return '${instrument.symbol}|${range.range}$suffix';
  }

  /// The signed-in session's token, or null when there is none (widget tests
  /// and the parser never start Supabase).
  static String? _sessionToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

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

  /// Candles for [range]. With [from] and [to] the server serves that historical
  /// window instead of the newest candles, which is what replay's jump-to-date
  /// and load-earlier use.
  Future<List<Candle>> candles(
    Instrument instrument,
    ChartRange range, {
    bool force = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final fromMs = from?.toUtc().millisecondsSinceEpoch;
    final toMs = to?.toUtc().millisecondsSinceEpoch;
    final hasWindow = fromMs != null && toMs != null;

    final key = _cacheKey(instrument, range, fromMs: fromMs, toMs: toMs);
    final entry = _cache[key];
    // A past window never changes, so it is kept far longer than the live tail.
    // Live spot feeds move faster than delayed exchange feeds.
    final ttl = hasWindow
        ? const Duration(minutes: 30)
        : instrument.isLive
            ? const Duration(seconds: 45)
            : const Duration(minutes: 10);
    if (!force && entry != null && DateTime.now().difference(entry.at) < ttl) {
      return entry.candles;
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/market/candles').replace(
      queryParameters: {
        'symbol': instrument.symbol,
        'range': range.range,
        'ticker': instrument.yahoo,
        if (hasWindow) 'from': '$fromMs',
        if (hasWindow) 'to': '$toMs',
      },
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

    final candles = parseCandlePayload(decoded);
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
    final token = _accessToken();
    if (token != null && token.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      );
    }
    final response = await request.close();

    if (response.statusCode == 401 || response.statusCode == 403) {
      await response.drain<void>();
      throw MarketDataException('Your session expired. Sign in again.');
    }
    if (response.statusCode == 429) {
      await response.drain<void>();
      throw MarketDataException(
        'The chart feed is busy right now. Try again in a minute.',
      );
    }
    if (response.statusCode != 200) {
      final body = await response.transform(utf8.decoder).join();
      throw MarketDataException(
        _errorMessage(body) ??
            'The chart feed answered ${response.statusCode}. Try another range.',
      );
    }
    return response.transform(utf8.decoder).join();
  }
}

/// Parses the normalised candle payload served by `/api/market/candles`.
/// Rows with a missing or non-numeric field are dropped, oldest first.
List<Candle> parseCandlePayload(dynamic payload) {
  if (payload is! Map) {
    throw MarketDataException('Unexpected chart data.');
  }

  final error = payload['error'];
  if (error is String && error.trim().isNotEmpty) {
    throw MarketDataException(error);
  }

  final rows = payload['candles'];
  if (rows is! List) {
    throw MarketDataException('Unexpected chart data.');
  }

  final candles = <Candle>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final stamp = row['t'];
    final open = row['o'];
    final high = row['h'];
    final low = row['l'];
    final close = row['c'];
    if (stamp is! num ||
        open is! num ||
        high is! num ||
        low is! num ||
        close is! num) {
      continue;
    }
    candles.add(
      Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          stamp.round(),
          isUtc: true,
        ),
        open: open.toDouble(),
        high: high.toDouble(),
        low: low.toDouble(),
        close: close.toDouble(),
      ),
    );
  }

  candles.sort((a, b) => a.time.compareTo(b.time));
  return candles;
}

/// The `error` string a refused request carried, if any.
String? _errorMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error'] is String) {
      final message = (decoded['error'] as String).trim();
      return message.isEmpty ? null : message;
    }
  } catch (_) {
    return null;
  }
  return null;
}

class _CachedCandles {
  _CachedCandles(this.candles, this.at);

  final List<Candle> candles;
  final DateTime at;
}
