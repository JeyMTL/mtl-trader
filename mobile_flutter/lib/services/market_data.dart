import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
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
    this.volume = 0,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;

  /// Tick volume for the bar; 0 for feeds that do not report it.
  final double volume;

  bool get isUp => close >= open;
}

/// Longest request OANDA will answer. A window that needs more bars has to use
/// a larger candle size.
const int maxCandlesPerRequest = 5000;

/// Candle sizes the candle route understands. The trader picks one; the server
/// maps it onto the vendor's granularity code.
enum ChartInterval {
  // Seconds. OANDA quotes 5, 10, 15 and 30 directly; 45 is three 15-second
  // bars bucketed on the server, because the vendor has no 45-second size.
  fiveSeconds('5s', '5-sec candles', Duration(seconds: 5)),
  tenSeconds('10s', '10-sec candles', Duration(seconds: 10)),
  fifteenSeconds('15s', '15-sec candles', Duration(seconds: 15)),
  thirtySeconds('30s', '30-sec candles', Duration(seconds: 30)),
  fortyFiveSeconds('45s', '45-sec candles', Duration(seconds: 45)),
  oneMinute('1m', '1-min candles', Duration(minutes: 1)),
  fiveMinutes('5m', '5-min candles', Duration(minutes: 5)),
  fifteenMinutes('15m', '15-min candles', Duration(minutes: 15)),
  thirtyMinutes('30m', '30-min candles', Duration(minutes: 30)),
  oneHour('1h', '1-hour candles', Duration(hours: 1)),
  fourHours('4h', '4-hour candles', Duration(hours: 4)),
  oneDay('1d', 'daily candles', Duration(days: 1));

  const ChartInterval(this.key, this.detail, this.size);

  /// Query value sent as `?interval=`, e.g. `15m`.
  final String key;

  /// Candle size in words, e.g. `15-min candles`.
  final String detail;

  /// Length of one candle.
  final Duration size;
}

/// Bars a window needs at this size, or null when it is past the vendor cap.
int? candleCountFor(Duration span, ChartInterval interval) {
  if (span <= Duration.zero) return 0;
  final bars = (span.inMilliseconds / interval.size.inMilliseconds).ceil();
  return bars > maxCandlesPerRequest ? null : bars;
}

/// A sensible starting size for a window this long.
ChartInterval defaultIntervalFor(Duration span) {
  if (span <= const Duration(hours: 3)) return ChartInterval.oneMinute;
  if (span <= const Duration(days: 2)) return ChartInterval.fiveMinutes;
  if (span <= const Duration(days: 7)) return ChartInterval.fifteenMinutes;
  if (span <= const Duration(days: 30)) return ChartInterval.oneHour;
  if (span <= const Duration(days: 90)) return ChartInterval.fourHours;
  return ChartInterval.oneDay;
}

/// Reads mid-price candles used to pin entry, stop, target and exit levels.
///
/// The app never calls a market data provider directly: candles come from this
/// deployment's `/api/market/candles` route, which holds the OANDA token. That
/// keeps the credential out of the binary; the server refuses symbols OANDA
/// cannot quote rather than substituting another feed.
class MarketDataService {
  MarketDataService({HttpClient? client, String? Function()? accessToken})
      : _client = client,
        _accessToken = accessToken ?? _sessionToken;

  /// Process-wide cache so reopening the chart paints instantly instead of
  /// going blank while another request runs.
  static final Map<String, _CachedCandles> _cache = {};
  static const int _maxEntries = 30;

  /// Device archive of every candle this phone has been shown, one entry per
  /// symbol and candle size.
  ///
  /// It is a union, not a tail: opening Thursday leaves Thursday in it, jumping
  /// back to Monday adds Monday, and the next fetch merges instead of replacing.
  /// That is what makes a past day reachable when the feed is down. Only the
  /// newest [historyLimit] bars are kept per entry, so a size whose history grows
  /// fastest (seconds, one minute) forgets its oldest days first — a bound, not a
  /// bug, because a prefs blob cannot hold a decade of ticks.
  static const String historyPrefix = 'chart.history.v1.';
  static const String historyIndexKey = 'chart.history.v1.index';
  static const int historyLimit = 12000;

  /// How many symbol+size archives are kept before the least recently written
  /// one is dropped. Twelve sizes for twenty instruments is already far more
  /// than one trader uses, and the bound keeps the store from growing forever.
  static const int historyMaxEntries = 20;

  /// The archive currently in memory, newest last. A few entries only: reading
  /// one is what the chart does, and twelve thousand bars per entry is real
  /// memory.
  static final Map<String, OfflineCandles> _archiveCache = {};
  static const int _archiveCacheEntries = 6;

  /// When each archive last reached the disk. A live chart polls every few
  /// seconds and the newest bar moves each time; rewriting half a megabyte of
  /// JSON on every poll would be a battery bug, not a feature.
  static final Map<String, int> _archiveWrittenAt = {};
  static const int archiveWriteGapMs = 15000;

  final String? Function() _accessToken;

  HttpClient? _client;

  /// Candles already fetched for this instrument, resolution and window, even
  /// when stale. A null window means the live tail.
  List<Candle>? cached(
    Instrument instrument,
    ChartInterval interval, {
    DateTime? from,
    DateTime? to,
  }) =>
      _cache[_cacheKey(
        instrument,
        interval,
        fromMs: from?.toUtc().millisecondsSinceEpoch,
        toMs: to?.toUtc().millisecondsSinceEpoch,
      )]
          ?.candles;

  DateTime? cachedAt(
    Instrument instrument,
    ChartInterval interval, {
    DateTime? from,
    DateTime? to,
  }) =>
      _cache[_cacheKey(
        instrument,
        interval,
        fromMs: from?.toUtc().millisecondsSinceEpoch,
        toMs: to?.toUtc().millisecondsSinceEpoch,
      )]
          ?.at;

  static String _cacheKey(
    Instrument instrument,
    ChartInterval interval, {
    int? fromMs,
    int? toMs,
  }) {
    // Historical windows are cached separately from the live tail: both hold
    // the same instrument and size but never the same candles.
    final suffix = fromMs == null || toMs == null ? '' : '|$fromMs-$toMs';
    return '${instrument.symbol}|${interval.key}$suffix';
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

  /// Candles for [interval]. With [from] and [to] the server serves that
  /// historical window instead of the newest candles, which is what the
  /// time-frame picker, replay's jump-to-date and load-earlier use.
  Future<List<Candle>> candles(
    Instrument instrument,
    ChartInterval interval, {
    bool force = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final fromMs = from?.toUtc().millisecondsSinceEpoch;
    final toMs = to?.toUtc().millisecondsSinceEpoch;
    final hasWindow = fromMs != null && toMs != null;

    final key = _cacheKey(instrument, interval, fromMs: fromMs, toMs: toMs);
    final entry = _cache[key];
    // A past window never changes, so it is kept far longer than the live tail.
    // The live tail is cached for half a bar: a flat 45 seconds would freeze a
    // 5-second chart nine bars behind the market.
    final ttl = hasWindow
        ? const Duration(minutes: 30)
        : Duration(
            milliseconds: (interval.size.inMilliseconds / 2)
                .round()
                .clamp(2000, 45000),
          );
    if (!force && entry != null && DateTime.now().difference(entry.at) < ttl) {
      return entry.candles;
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/market/candles').replace(
      queryParameters: {
        'symbol': instrument.symbol,
        'interval': interval.key,
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
    final at = DateTime.now();
    _cache[key] = _CachedCandles(candles, at);
    if (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    // Every series the trader sees is merged into the device archive, windows
    // included: the day they opened Thursday and the day they jumped back to
    // Monday both belong on this phone afterwards.
    unawaited(
      _archive(instrument, interval, candles, at, immediate: hasWindow),
    );
    return candles;
  }

  static String _historyKey(Instrument instrument, ChartInterval interval) =>
      '$historyPrefix${instrument.symbol}|${interval.key}';

  Future<void> _archive(
    Instrument instrument,
    ChartInterval interval,
    List<Candle> candles,
    DateTime at, {
    bool immediate = false,
  }) async {
    try {
      final key = _historyKey(instrument, interval);
      // Merge in memory; read the file only when this entry is not loaded.
      final base = _archiveCache[key] ?? await _readArchive(key);
      final merged = mergeCandles(base?.candles ?? const [], candles);
      _rememberArchive(key, OfflineCandles(merged, at));

      final now = DateTime.now().millisecondsSinceEpoch;
      final writtenAt = _archiveWrittenAt[key] ?? 0;
      if (!immediate && now - writtenAt < archiveWriteGapMs) return;
      _archiveWrittenAt[key] = now;
      final file = await _archiveFile(key);
      await file.writeAsString(encodeOfflineCandles(merged, at), flush: false);
      await _pruneArchives(key);
    } catch (_) {
      // A device copy is a convenience; losing it must never fail a fetch.
    }
  }

  /// One JSON file per symbol and size, in the app's support directory.
  ///
  /// Files rather than SharedPreferences on purpose: prefs are parsed whole at
  /// startup, and a dozen sizes of a dozen thousand bars would become a
  /// multi-megabyte XML blob in front of the first frame.
  static Future<File> _archiveFile(String key) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/candles');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9|._-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  static Future<OfflineCandles?> _readArchive(String key) async {
    try {
      final file = await _archiveFile(key);
      if (!await file.exists()) return null;
      return decodeOfflineCandles(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Keeps the archive in memory between writes, bounded so twenty instruments
  /// cannot sit in RAM at once.
  static void _rememberArchive(String key, OfflineCandles archive) {
    _archiveCache.remove(key);
    _archiveCache[key] = archive;
    while (_archiveCache.length > _archiveCacheEntries) {
      _archiveCache.remove(_archiveCache.keys.first);
    }
  }

  /// Marks [key] as the most recently written archive and drops the least
  /// recently used files once the store is over [historyMaxEntries].
  ///
  /// The index is the order of use, so opening a chart keeps its archive and
  /// opening a new one evicts the oldest — a bounded store without a database.
  Future<void> _pruneArchives(String key) async {
    final order = <String>[];
    try {
      final base = await getApplicationSupportDirectory();
      final index = File('${base.path}/candles/_index.json');
      if (await index.exists()) {
        final decoded = jsonDecode(await index.readAsString());
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is String && entry != key) order.add(entry);
          }
        }
      }
      order.add(key);
      while (order.length > historyMaxEntries) {
        final dropped = order.removeAt(0);
        final file = await _archiveFile(dropped);
        if (await file.exists()) await file.delete();
      }
      await index.writeAsString(jsonEncode(order), flush: false);
    } catch (_) {
      // Pruning is housekeeping: never let it cost a chart its candles.
    }
  }

  /// The candles this device has seen for [interval], or null when it has never
  /// held any. With [from] and [to], only the stored bars inside that window.
  ///
  /// Read when the feed itself failed, so the chart can stand on what was true
  /// rather than on nothing.
  Future<OfflineCandles?> offline(
    Instrument instrument,
    ChartInterval interval, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final key = _historyKey(instrument, interval);
      final stored = _archiveCache[key] ?? await _readArchive(key);
      if (stored == null) return null;
      if (from == null || to == null) return stored;
      final start = from.toUtc().millisecondsSinceEpoch;
      final end = to.toUtc().millisecondsSinceEpoch;
      final slice = [
        for (final candle in stored.candles)
          if (candle.time.millisecondsSinceEpoch >= start &&
              candle.time.millisecondsSinceEpoch <= end)
            candle,
      ];
      if (slice.isEmpty) return null;
      return OfflineCandles(slice, stored.at);
    } catch (_) {
      return null;
    }
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
    final volume = row['v'];
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
        volume: volume is num ? volume.toDouble() : 0,
      ),
    );
  }

  candles.sort((a, b) => a.time.compareTo(b.time));
  return candles;
}

/// The last series this device saw for one symbol and candle size, with the
/// moment it arrived.
///
/// It exists for one situation: the chart feed is down and there is nothing on
/// screen. Showing the market as it last really was, stamped, beats an empty
/// canvas — but it is never presented as live, and never used to price an order.
class OfflineCandles {
  const OfflineCandles(this.candles, this.at);

  final List<Candle> candles;
  final DateTime at;
}

/// Every candle from both lists once, oldest first, capped to the newest
/// [MarketDataService.historyLimit].
///
/// A later read of the same bar wins, because the feed revises the newest candle
/// as it prints and the stored copy before it is the older opinion of the same
/// minute. Merging by time is what lets windows join the archive instead of
/// fighting over one slot.
List<Candle> mergeCandles(List<Candle> existing, List<Candle> fresh) {
  final byTime = <int, Candle>{};
  for (final candle in existing) {
    byTime[candle.time.millisecondsSinceEpoch] = candle;
  }
  for (final candle in fresh) {
    byTime[candle.time.millisecondsSinceEpoch] = candle;
  }
  final merged = byTime.values.toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  const limit = MarketDataService.historyLimit;
  if (merged.length <= limit) return merged;
  return merged.sublist(merged.length - limit);
}

/// Writes the newest candles as a compact device copy.
///
/// Only the tail is kept: the chart opens on the newest bars, so an old chart
/// scrolled far back is not what this is for, and a prefs blob has to stay small.
String encodeOfflineCandles(List<Candle> candles, DateTime at) {
  const limit = MarketDataService.historyLimit;
  final tail = candles.length <= limit
      ? candles
      : candles.sublist(candles.length - limit);
  return jsonEncode({
    'at': at.toUtc().millisecondsSinceEpoch,
    'c': [
      for (final candle in tail)
        [
          candle.time.millisecondsSinceEpoch,
          candle.open,
          candle.high,
          candle.low,
          candle.close,
          candle.volume,
        ],
    ],
  });
}

/// Reads a device copy back. Null for a missing, empty or unreadable blob, and
/// for one whose every row was unusable.
OfflineCandles? decodeOfflineCandles(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final stamp = decoded['at'];
    final rows = decoded['c'];
    if (stamp is! num || rows is! List) return null;
    final candles = <Candle>[];
    for (final row in rows) {
      if (row is! List || row.length < 5) continue;
      final t = row[0];
      final o = row[1];
      final h = row[2];
      final l = row[3];
      final c = row[4];
      final v = row.length > 5 ? row[5] : 0;
      if (t is! num || o is! num || h is! num || l is! num || c is! num) {
        continue;
      }
      candles.add(
        Candle(
          time: DateTime.fromMillisecondsSinceEpoch(t.toInt(), isUtc: true),
          open: o.toDouble(),
          high: h.toDouble(),
          low: l.toDouble(),
          close: c.toDouble(),
          volume: v is num ? v.toDouble() : 0,
        ),
      );
    }
    if (candles.isEmpty) return null;
    return OfflineCandles(
      candles,
      DateTime.fromMillisecondsSinceEpoch(stamp.toInt()),
    );
  } catch (_) {
    return null;
  }
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
