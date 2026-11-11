import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/backtest.dart';
import 'api_transport.dart';

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
    this.ruleSpec,
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

  /// The declarative rules a custom backtest was compiled into. Present only
  /// for a custom run; the engine refuses it without `strategyId: 'custom'`.
  final Map<String, dynamic>? ruleSpec;

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
      if (ruleSpec != null) 'ruleSpec': ruleSpec,
    };
  }
}

/// A description compiled into executable rules, plus the same rules in plain
/// English so the trader can check them before a run.
class CompiledBacktest {
  const CompiledBacktest({
    required this.spec,
    required this.rules,
    required this.disclaimer,
    this.model,
  });

  final Map<String, dynamic> spec;
  final List<String> rules;
  final String disclaimer;
  final String? model;

  String get name => spec['name']?.toString().trim().isNotEmpty == true
      ? spec['name'].toString().trim()
      : 'Custom strategy';

  String get timeframe => spec['timeframe']?.toString() ?? 'M15';
}

/// Backtest runs, saved runs and their deletion — the phone side of
/// `/api/backtest`.
///
/// The engine stays on the server, so this client only carries bar data up and
/// renders the report that comes back. Reads and deletes are not plan-gated
/// there either: a downgraded account keeps its own results.
class BacktestApi {
  BacktestApi({HttpClient? client, String? Function()? accessToken})
      : _transport = ApiTransport(
          client: client,
          accessToken: accessToken ?? _sessionToken,
        );

  final ApiTransport _transport;

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

  /// Turns a voice note into text for the description.
  ///
  /// The clip is sent as a data URL and nothing is stored: the transcript is the
  /// only thing that survives, and the trader edits it before compiling.
  Future<String> transcribe(String audioDataUrl) async {
    final body = await _send(
      'POST',
      '/api/backtest/transcribe',
      body: <String, dynamic>{'audio': audioDataUrl},
      timeout: const Duration(seconds: 75),
    );
    final transcript = body['transcript'];
    if (transcript is! String || transcript.trim().isEmpty) {
      throw BacktestApiException(
        'That recording came back empty. Try again, or type the explanation.',
      );
    }
    return transcript.trim();
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

  /// Turns a plain-language setup into a declarative rule spec.
  ///
  /// The model call happens on the server and is gated like a run, so this is
  /// the same Workbench the web sells. Only text is sent from the phone: the
  /// description, the chosen timeframes, an optional stop rule and the trader's
  /// own definition of an acceptable setup.
  Future<CompiledBacktest> compile({
    required String description,
    required String timeframe,
    String? higherTimeframe,
    String? stopLoss,
    String? symbol,
    String? criteria,
    List<String> images = const [],
  }) async {
    final body = await _send(
      'POST',
      '/api/backtest/compile',
      body: <String, dynamic>{
        'description': description,
        'timeframe': timeframe,
        if (higherTimeframe != null && higherTimeframe.isNotEmpty)
          'higherTimeframe': higherTimeframe,
        if (stopLoss != null && stopLoss.trim().isNotEmpty)
          'stopLoss': stopLoss.trim(),
        if (symbol != null && symbol.trim().isNotEmpty) 'symbol': symbol.trim(),
        if (criteria != null && criteria.trim().isNotEmpty)
          'criteria': criteria.trim(),
        if (images.isNotEmpty) 'images': images,
      },
      timeout: const Duration(seconds: 75),
    );

    final spec = body['spec'];
    if (spec is! Map<String, dynamic>) {
      throw BacktestApiException('The compiler returned no rules. Try again.');
    }
    return CompiledBacktest(
      spec: spec,
      rules: _list(body['rules']).map((line) => line.toString()).toList(),
      disclaimer: body['disclaimer']?.toString() ?? '',
      model: body['meta'] is Map
          ? (body['meta'] as Map)['model']?.toString()
          : null,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await _transport.send(
        method,
        path,
        body: body,
        timeout: timeout,
      );
      return response.body;
    } on ApiTransportException catch (error) {
      // A run has its own timeout advice; everything else keeps the server's
      // message, or the transport's plain-language network error.
      final message = error.code == 'timeout'
          ? 'The run took too long. Try a shorter date range or a larger timeframe.'
          : error.message;
      throw BacktestApiException(
        message,
        upgradeRequired: error.code == 'upgrade_required',
      );
    }
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];
