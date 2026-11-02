import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../models/ai_review.dart';
import '../models/models.dart';
import '../models/prop_rules.dart';

/// A decoded, already error-checked response from the web API.
class _ApiResult {
  const _ApiResult(this.body);

  final Map<String, dynamic> body;
}

/// Every read and write the Flutter app performs, in one place.
class JournalApi {
  JournalApi({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const String mediaBucket = 'journal-media';

  SupabaseClient get raw => _db;
  String? get userId => _db.auth.currentUser?.id;
  User? get currentUser => _db.auth.currentUser;

  Future<DashboardData> dashboard() async {
    final results = await Future.wait<dynamic>([
      summary(),
      equity(),
      depositsTotal(),
      timeStats(),
      journalFeed(limit: 4),
      recentTrades(limit: 5),
    ]);

    return DashboardData(
      summary: results[0] as TradeSummary,
      equity: results[1] as List<EquityPoint>,
      deposits: results[2] as double,
      timeStats: results[3] as TimeStats,
      journalFeed: results[4] as List<JournalEntry>,
      recentTrades: results[5] as List<TradeRow>,
    );
  }

  Future<TradeSummary> summary() async {
    final data = await _db.rpc('trade_summary');
    return TradeSummary.fromMap(asMap(data));
  }

  Future<List<EquityPoint>> equity() async {
    final data = await _db.rpc('equity_curve');
    return asList(data).map((row) => EquityPoint.fromMap(asMap(row))).toList();
  }

  Future<double> depositsTotal() async {
    final data = await _db.rpc('deposits_total');
    return asDouble(data);
  }

  /// Trades, wins and P&L for each UTC window, from `session_stats`
  /// (migration 20261105) — one request instead of one per session, and the
  /// same buckets the journal filter uses.
  Future<Map<String, ({int trades, int wins, double pnl})>>
      sessionStats() async {
    final data = await _db.rpc('session_stats');
    final result = <String, ({int trades, int wins, double pnl})>{};
    for (final row in asList(data)) {
      final map = asMap(row);
      final key = asString(map['session']);
      if (key == null || key.isEmpty) continue;
      result[key] = (
        trades: asInt(map['trades']),
        wins: asInt(map['wins']),
        pnl: asDouble(map['pnl']),
      );
    }
    return result;
  }

  Future<TimeStats> timeStats() async {
    final data = await _db.rpc('time_stats');
    final map = asMap(data);
    if (map.isEmpty) return TimeStats.empty;
    return TimeStats.fromMap(map);
  }

  Future<List<DailyPnlPoint>> dailyPnl(DateTime from, DateTime to) async {
    final data = await _db.rpc(
      'daily_pnl',
      params: {'p_from': isoDate(from), 'p_to': isoDate(to)},
    );
    return asList(data)
        .map((row) => DailyPnlPoint.fromMap(asMap(row)))
        .toList();
  }

  Future<DateTime?> latestTradeDay() async {
    final data = await _db.rpc('latest_trade_day');
    if (data == null) return null;
    return asDate(data.toString());
  }

  Future<List<TradeRow>> dayTrades(DateTime day) async {
    final data = await _db.rpc('day_trades', params: {'p_day': isoDate(day)});
    return asList(data)
        .map((row) => TradeRow.fromMap(asMap(row)))
        .where((row) => row.id.isNotEmpty)
        .toList();
  }

  Future<List<SymbolStat>> symbolStats({int limit = 10}) async {
    final data = await _db.rpc('symbol_stats', params: {'p_limit': limit});
    return asList(data).map((row) => SymbolStat.fromMap(asMap(row))).toList();
  }

  Future<List<TagStat>> tagStats({int limit = 12}) async {
    final data = await _db.rpc('tag_stats', params: {'p_limit': limit});
    return asList(data).map((row) => TagStat.fromMap(asMap(row))).toList();
  }

  Future<List<StrategyStat>> strategyStats({int limit = 20}) async {
    final data = await _db.rpc('strategy_stats', params: {'p_limit': limit});
    return asList(data).map((row) => StrategyStat.fromMap(asMap(row))).toList();
  }

  /// Distinct strategy labels already used, for the form's suggestion chips.
  /// Missing migration or an empty journal both yield an empty list.
  Future<List<String>> strategyLabels({int limit = 20}) async {
    final data = await _db.rpc('strategy_labels', params: {'p_limit': limit});
    return asList(data)
        .map((row) => asMap(row)['label']?.toString() ?? '')
        .where((label) => label.trim().isNotEmpty)
        .toList();
  }

  /// Prop-firm rules plus the standing computed from the trades. The server
  /// decides whether a rule is breached; this only transports it.
  Future<Map<String, dynamic>> propRules() async {
    final result = await _api('GET', '/api/prop-rules');
    return result.body;
  }

  Future<Map<String, dynamic>> savePropRules(PropRules rules) async {
    final result = await _api('PUT', '/api/prop-rules', rules.toBody());
    return result.body;
  }

  /// Remaining AI reviews this month. A 402 is not thrown: the card renders the
  /// allowance as "not included" rather than an error.
  Future<Map<String, dynamic>> aiReviewQuota() async {
    final result = await _api('GET', '/api/ai/review/quota');
    return result.body;
  }

  /// Generates the journal review. The route loads the note-bearing trades
  /// itself, so only the summary has to be sent from the device.
  Future<AiReviewResult> aiReview({
    required int totalTrades,
    required double totalPnl,
    required double winRate,
  }) async {
    final result = await _api('POST', '/api/ai/review', <String, dynamic>{
      'totalTrades': totalTrades,
      'totalPnl': totalPnl,
      'winRate': winRate,
    });
    return AiReviewResult.fromBody(result.body);
  }

  Future<List<JournalEntry>> journalFeed({int limit = 6}) async {
    final data = await _db.rpc('journal_feed', params: {'p_limit': limit});
    return asList(data).map((row) => JournalEntry.fromMap(asMap(row))).toList();
  }

  Future<List<TradeRow>> recentTrades({int limit = 5}) async {
    // Reading `userId!` here threw a null-check error straight out of the
    // dashboard load when the session had expired; say what happened instead.
    final id = userId;
    if (id == null) {
      throw Exception('Your session expired. Sign in again.');
    }
    final data = await _db
        .from('trades')
        .select(
          'id, symbol, type, pnl, entry_price, exit_price, lot_size, commission, swap, open_time, close_time, strategy, notes, tags, created_at',
        )
        .eq('user_id', id)
        .order('created_at', ascending: false)
        .limit(limit);
    return asList(data).map((row) => TradeRow.fromMap(asMap(row))).toList();
  }

  Future<TradePageResult> tradePage({
    int limit = 25,
    int offset = 0,
    String? search,
    String filter = 'all',
    String? session,
  }) async {
    final term = (search ?? '').trim();
    dynamic data;
    try {
      data = await _db.rpc(
        'trade_page',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_search': term.isEmpty ? null : term,
          'p_filter': filter,
          'p_session': session,
        },
      );
    } catch (error) {
      // A database that has not had the session migration applied rejects the
      // extra argument outright. Say so, rather than showing an unfiltered list
      // as if the session chip had worked.
      if (session != null && _rejectedSessionArgument(error)) {
        throw Exception(
          'The session filter needs a database update. Apply '
          'supabase/migrations/20261104_trade_page_session_filter.sql, then '
          'try again.',
        );
      }
      rethrow;
    }
    return TradePageResult.fromMap(asMap(data));
  }

  /// True when PostgREST could not find this function signature at all, which
  /// is what a missing migration looks like from the client.
  static bool _rejectedSessionArgument(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('pgrst202') ||
        message.contains('could not find the function') ||
        message.contains('schema cache');
  }

  Future<Map<String, dynamic>> loadTrade(String id) async {
    final data = await _db.from('trades').select().eq('id', id).single();
    return asMap(data);
  }

  Future<List<MediaAttachment>> attachments(String tradeId) async {
    final data = await _db
        .from('trade_attachments')
        .select()
        .eq('trade_id', tradeId)
        .order('created_at', ascending: true);
    return asList(data)
        .map((row) => MediaAttachment.fromMap(asMap(row)))
        .toList();
  }

  Future<String> createTrade(Map<String, dynamic> payload) async {
    final row = await _db.from('trades').insert(payload).select('id').single();
    return asMap(row)['id'].toString();
  }

  Future<void> updateTrade(String id, Map<String, dynamic> payload) async {
    await _db.from('trades').update(payload).eq('id', id);
  }

  Future<void> deleteTrade(String id) async {
    final media = await attachments(id);
    final paths =
        media.map((row) => row.storagePath).whereType<String>().toList();
    if (paths.isNotEmpty) {
      await _db.storage.from(mediaBucket).remove(paths);
    }
    await _db.from('trades').delete().eq('id', id);
  }

  Future<void> clearTrades(String userId) async {
    final rows = await _db.from('trades').select('id').eq('user_id', userId);
    final ids = asList(rows).map((row) => asMap(row)['id'].toString()).toList();
    if (ids.isNotEmpty) {
      final media = await _db
          .from('trade_attachments')
          .select('storage_path')
          .inFilter('trade_id', ids);
      final paths = asList(media)
          .map((row) => asString(asMap(row)['storage_path']))
          .whereType<String>()
          .toList();
      if (paths.isNotEmpty) {
        await _db.storage.from(mediaBucket).remove(paths);
      }
    }
    await _db.from('trades').delete().eq('user_id', userId);
  }

  Future<PendingAttachment> uploadAttachment({
    required String userId,
    String? tradeId,
    required Uint8List bytes,
    required String kind,
    required String fileName,
    required String mimeType,
    double? durationSeconds,
    Uint8List? previewBytes,
  }) async {
    final ext = _extensionFor(fileName, mimeType, kind);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}.$ext';
    final path = '$userId/${tradeId ?? 'draft'}/$name';

    await _db.storage.from(mediaBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );

    return PendingAttachment(
      kind: kind,
      storagePath: path,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      durationSeconds: durationSeconds,
      previewBytes: previewBytes,
    );
  }

  Future<void> persistAttachments({
    required String userId,
    required String tradeId,
    required List<PendingAttachment> pending,
  }) async {
    if (pending.isEmpty) return;
    await _db.from('trade_attachments').insert(
          pending
              .map(
                (item) => {
                  'user_id': userId,
                  'trade_id': tradeId,
                  'kind': item.kind,
                  'storage_path': item.storagePath,
                  'file_name': item.fileName,
                  'mime_type': item.mimeType,
                  'size_bytes': item.sizeBytes,
                  'duration_seconds': item.durationSeconds,
                },
              )
              .toList(),
        );
  }

  Future<void> removeAttachment(MediaAttachment attachment) async {
    if (attachment.storagePath != null) {
      await _db.storage.from(mediaBucket).remove([attachment.storagePath!]);
    }
    await _db.from('trade_attachments').delete().eq('id', attachment.id);
  }

  Future<void> removePending(PendingAttachment pending) async {
    await _db.storage.from(mediaBucket).remove([pending.storagePath]);
  }

  Future<String?> signedUrl(String path) async {
    try {
      return await _db.storage.from(mediaBucket).createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> profile() async {
    final id = userId;
    if (id == null) return const {};
    const full = 'email, full_name, subscription_tier, subscription_status, '
        'trial_ends_at, current_period_end, max_trades, timezone';
    try {
      final data =
          await _db.from('users').select(full).eq('id', id).maybeSingle();
      return data == null ? const {} : asMap(data);
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (!message.contains('42703') && !message.contains('does not exist')) {
        rethrow;
      }
      // A project that has not applied the billing-period migration still has
      // to render its plan, so retry with the columns every schema carries.
      final data = await _db
          .from('users')
          .select(
            'email, full_name, subscription_tier, subscription_status, '
            'max_trades, timezone',
          )
          .eq('id', id)
          .maybeSingle();
      return data == null ? const {} : asMap(data);
    }
  }

  Future<void> updateTimezone(String timezone) async {
    final id = userId;
    if (id == null) throw Exception('Not signed in.');
    await _db.from('users').update({'timezone': timezone}).eq('id', id);
  }

  Future<void> signOut() => _db.auth.signOut();

  /// Current hosted MT5 connection, or `{connected: false}` when there is none.
  Future<Map<String, dynamic>> brokerConnection() async {
    final result = await _api('GET', '/api/broker/connection');
    return result.body;
  }

  /// Connects an MT5 account with its investor (read-only) password. The server
  /// seals the password; nothing about it is kept on the device.
  Future<Map<String, dynamic>> connectBroker({
    required String broker,
    required String server,
    required String login,
    required String investorPassword,
  }) async {
    final result = await _api('POST', '/api/broker/connection', {
      'broker': broker,
      'server': server,
      'login': login,
      'investorPassword': investorPassword,
    });
    return result.body;
  }

  /// Removes the connection and wipes the stored credential server-side.
  Future<Map<String, dynamic>> disconnectBroker() async {
    final result = await _api('DELETE', '/api/broker/connection');
    return result.body;
  }

  /// The MT5 broker directory behind the connect form's searchable picker. The
  /// whole list comes back in one call and is filtered on the device, so typing
  /// in the picker never waits on a request.
  Future<List<Mt5Broker>> brokers() async {
    final result = await _api('GET', '/api/brokers');
    return asList(result.body['brokers'])
        .map((row) => Mt5Broker.fromMap(asMap(row)))
        .where((broker) => broker.name.isNotEmpty)
        .toList();
  }

  /// Authenticated JSON call to the web API. Throws the server's message so the
  /// UI can show something actionable instead of a status code.
  Future<_ApiResult> _api(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final session = _db.auth.currentSession;
    if (session == null) {
      throw Exception('Your session expired. Sign in again.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.accessToken}',
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(
            const Duration(seconds: 25),
          );
      final text = await response.transform(utf8.decoder).join();

      dynamic decoded;
      try {
        decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      } catch (_) {
        decoded = <String, dynamic>{};
      }
      final map =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode >= 400) {
        final message = map['error'];
        throw Exception(
          message is String && message.isNotEmpty
              ? message
              : 'Request failed (${response.statusCode}). Try again.',
        );
      }
      return _ApiResult(map);
    } finally {
      client.close(force: true);
    }
  }

  /// Starts a card subscription and returns the hosted checkout URL. The app
  /// opens it in the browser; the webhook applies the payment, so closing the
  /// app mid-flow loses nothing.
  ///
  /// It talks to this app's own checkout endpoint rather than to Paddle
  /// directly, so the price ids, webhook and merchant-of-record setup stay a
  /// server concern and the app never carries payment credentials.
  Future<String> startCardSubscription(
    String planId, {
    String interval = 'month',
  }) async {
    final session = _db.auth.currentSession;
    final id = userId;
    if (session == null || id == null) {
      throw Exception('Your session expired. Sign in again.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse('${AppConfig.apiBaseUrl}/api/checkout/card'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.accessToken}',
      );
      // The cadence travels with the payment so the webhook knows whether to
      // grant 30 days or a full year. Without it every purchase is monthly.
      request.write(
        jsonEncode({'planId': planId, 'userId': id, 'interval': interval}),
      );

      final response = await request.close().timeout(
            const Duration(seconds: 25),
          );
      final body = await response.transform(utf8.decoder).join();

      dynamic decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        decoded = null;
      }

      if (response.statusCode != 200) {
        final message = decoded is Map && decoded['error'] is String
            ? decoded['error'] as String
            : 'Could not start the card checkout.';
        throw Exception(message);
      }

      final url = decoded is Map ? decoded['url'] : null;
      if (url is! String || url.isEmpty) {
        throw Exception('The payment page did not open. Please try again.');
      }
      return url;
    } finally {
      client.close(force: true);
    }
  }

  /// `2026-10-28` — the format Postgres accepts for a `date` argument.
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _extensionFor(String fileName, String mimeType, String kind) {
    final dot = fileName.lastIndexOf('.');
    if (dot >= 0 && dot < fileName.length - 1) {
      final ext = fileName.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) return ext;
    }
    if (mimeType.contains('png')) return 'png';
    if (mimeType.contains('webp')) return 'webp';
    if (mimeType.contains('heic')) return 'heic';
    if (mimeType.contains('mpeg')) return 'mp3';
    if (mimeType.contains('wav')) return 'wav';
    if (mimeType.contains('mp4') || mimeType.contains('m4a')) return 'm4a';
    if (mimeType.contains('ogg')) return 'ogg';
    return kind == 'image' ? 'jpg' : 'webm';
  }
}
