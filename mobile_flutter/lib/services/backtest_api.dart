import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/backtest.dart';
import '../core/config.dart';

/// Raised when a backtest request is refused. [message] is written for the
/// trader and shown verbatim; [upgradeRequired] marks the server's 402, which
/// the workbench renders as a plan prompt rather than an error.
class BacktestApiException implements Exception {
  BacktestApiException(this.message, {this.upgradeRequired = false});

  final String message;
  final bool upgradeRequired;

  @override
  String toString() => message;
}

/// What a run sends, matching the body the web workbench posts.
class BacktestRequest {
  const BacktestRequest({
    required this.csv,
    required this.symbol,
    required this.timeframe,
    required this.strategyId,
    required this.params,
    required this.name,
    required this.initialBalance,
    required this.riskPercent,
    required this.contractSize,
    required this.maxLeverage,
    required this.spread,
    required this.slippage,
    required this.commission,
    required this.splitRatio,
    required this.timezoneOffsetMinutes,
  });

  final String csv;
  final String symbol;
  final String timeframe;
  final String strategyId;

  /// Missing or unreadable values are left out, so the server substitutes the
  /// declared default — the same thing the web form's `null` does.
  final Map<String, double?> params;
  final String name;
  final double? initialBalance;
  final double? riskPercent;
  final double? contractSize;
  final double? maxLeverage;
  final double? spread;
  final double? slippage;
  final double? commission;
  final double? splitRatio;
  final double? timezoneOffsetMinutes;

  Map<String, dynamic> toBody() {
    return <String, dynamic>{
      'csv': csv,
      'symbol': symbol,
      'timeframe': timeframe,
      'strategyId': strategyId,
      'name': name,
      'params': {
        for (final entry in params.entries)
          if (entry.value != null) entry.key: entry.value,
      },
      'initialBalance': initialBalance,
      'riskPercent': riskPercent,
      'contractSize': contractSize,
      'maxLeverage': maxLeverage,
      'spread': spread,
      'slippage': slippage,
      'commission': commission,
      'splitRatio': splitRatio,
      'timezoneOffsetMinutes': timezoneOffsetMinutes,
    };
  }
}

/// Backtest runs, saved runs and their deletion — the phone side of
/// `/api/backtest`.
///
/// The engine stays on the server, so this client only carries bar data up and
/// renders the report that comes back. Reads and deletes are not plan-gated
/// there either: a downgraded account keeps its own results.
class BacktestApi {
  BacktestApi({HttpClient? client, String? Function()? accessToken})
      : _client = client,
        _accessToken = accessToken ?? _sessionToken;

  final HttpClient? _client;
  final String? Function() _accessToken;

  static String? _sessionToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Simulates a CSV and archives the run.
  Future<BacktestRunResult> run(BacktestRequest request) async {
    final body = await _send(
      'POST',
      '/api/backtest',
      body: request.toBody(),
      // The route's own ceiling is 60 s; anything faster than that is a failed
      // run, not a slow one.
      timeout: const Duration(seconds: 90),
    );
    final report = body['report'];
    if (report is! Map<String, dynamic>) {
      throw BacktestApiException('The run returned no report. Try again.');
    }
    return BacktestRunResult(
      report: BacktestReport.fromJson(report),
      saved: body['saved'] == true,
      id: body['id']?.toString(),
    );
  }

  /// The caller's 20 most recent runs.
  Future<List<SavedBacktestRun>> savedRuns() async {
    final body = await _send('GET', '/api/backtest');
    return _list(body['runs'])
        .map((row) => SavedBacktestRun.fromMap(_map(row)))
        .where((run) => run.id.isNotEmpty)
        .toList();
  }

  /// One stored run, including its trades and equity curve.
  Future<BacktestReport> savedRun(String id) async {
    final body = await _send(
      'GET',
      '/api/backtest?id=${Uri.encodeQueryComponent(id)}',
    );
    final run = body['run'];
    if (run is! Map<String, dynamic>) {
      throw BacktestApiException('Could not load that run.');
    }
    return BacktestReport.fromSaved(run);
  }

  Future<void> delete(String id) async {
    await _send('DELETE', '/api/backtest?id=${Uri.encodeQueryComponent(id)}');
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw BacktestApiException('Your session expired. Sign in again.');
    }

    final client = _client ??
        (HttpClient()..connectionTimeout = const Duration(seconds: 10));
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();

      dynamic decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
      final map =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode >= 400) {
        final message = map['error'];
        throw BacktestApiException(
          message is String && message.trim().isNotEmpty
              ? message
              : 'Request failed (${response.statusCode}). Try again.',
          upgradeRequired: map['code'] == 'upgrade_required',
        );
      }
      return map;
    } on BacktestApiException {
      rethrow;
    } on TimeoutException {
      throw BacktestApiException(
        'The run took too long. Try a shorter date range or a larger timeframe.',
      );
    } catch (_) {
      throw BacktestApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    } finally {
      if (_client == null) client.close(force: true);
    }
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];
