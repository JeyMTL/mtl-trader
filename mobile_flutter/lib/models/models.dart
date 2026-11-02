import 'dart:typed_data';

import '../core/format.dart';

double asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ?? 0;
}

double? asNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

bool asBool(dynamic value) => value == true || value == 'true';

String? asString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

DateTime? asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toLocal();
}

List<String> asStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<dynamic> asList(dynamic value) => value is List ? value : const [];

class TradeSummary {
  const TradeSummary({
    required this.totalTrades,
    required this.wins,
    required this.losses,
    required this.monthTrades,
    required this.monthWins,
    required this.monthPnl,
    required this.monthWinningDays,
    required this.totalPnl,
    required this.grossProfit,
    required this.grossLoss,
    required this.bestTrade,
    required this.worstTrade,
    required this.hasTradeToday,
  });

  final int totalTrades;
  final int wins;
  final int losses;
  final int monthTrades;
  final int monthWins;
  final double monthPnl;
  final int monthWinningDays;
  final double totalPnl;
  final double grossProfit;
  final double grossLoss;
  final double bestTrade;
  final double worstTrade;
  final bool hasTradeToday;

  double get winRate => totalTrades > 0 ? (wins / totalTrades) * 100 : 0;
  double get monthWinRate =>
      monthTrades > 0 ? (monthWins / monthTrades) * 100 : 0;
  double get profitFactor => grossLoss > 0 ? grossProfit / grossLoss : 0;
  double get averageTrade => totalTrades > 0 ? totalPnl / totalTrades : 0;

  factory TradeSummary.fromMap(Map<String, dynamic> map) => TradeSummary(
        totalTrades: asInt(map['total_trades']),
        wins: asInt(map['wins']),
        losses: asInt(map['losses']),
        monthTrades: asInt(map['month_trades']),
        monthWins: asInt(map['month_wins']),
        monthPnl: asDouble(map['month_pnl']),
        monthWinningDays: asInt(map['month_winning_days']),
        totalPnl: asDouble(map['total_pnl']),
        grossProfit: asDouble(map['gross_profit']),
        grossLoss: asDouble(map['gross_loss']),
        bestTrade: asDouble(map['best_trade']),
        worstTrade: asDouble(map['worst_trade']),
        hasTradeToday: asBool(map['has_trade_today']),
      );

  static const empty = TradeSummary(
    totalTrades: 0,
    wins: 0,
    losses: 0,
    monthTrades: 0,
    monthWins: 0,
    monthPnl: 0,
    monthWinningDays: 0,
    totalPnl: 0,
    grossProfit: 0,
    grossLoss: 0,
    bestTrade: 0,
    worstTrade: 0,
    hasTradeToday: false,
  );
}

class EquityPoint {
  const EquityPoint({
    required this.day,
    required this.pnl,
    required this.cumulative,
    required this.trades,
  });

  final String day;
  final double pnl;
  final double cumulative;
  final int trades;

  factory EquityPoint.fromMap(Map<String, dynamic> map) => EquityPoint(
        day: map['day']?.toString() ?? '',
        pnl: asDouble(map['pnl']),
        cumulative: asDouble(map['cumulative']),
        trades: asInt(map['trades']),
      );
}

class HourStat {
  const HourStat({
    required this.hour,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.pnl,
  });

  final int hour;
  final int trades;
  final int wins;
  final int losses;
  final double pnl;

  double get winRate => trades > 0 ? (wins / trades) * 100 : 0;

  factory HourStat.fromMap(Map<String, dynamic> map) => HourStat(
        hour: asInt(map['hour']),
        trades: asInt(map['trades']),
        wins: asInt(map['wins']),
        losses: asInt(map['losses']),
        pnl: asDouble(map['pnl']),
      );
}

class SessionStat {
  const SessionStat({
    required this.session,
    required this.firstHour,
    required this.lastHour,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.pnl,
  });

  final String session;
  final int firstHour;
  final int lastHour;
  final int trades;
  final int wins;
  final int losses;
  final double pnl;

  double get winRate => trades > 0 ? (wins / trades) * 100 : 0;

  factory SessionStat.fromMap(Map<String, dynamic> map) => SessionStat(
        session: map['session']?.toString() ?? 'Session',
        firstHour: asInt(map['first_hour']),
        lastHour: asInt(map['last_hour']),
        trades: asInt(map['trades']),
        wins: asInt(map['wins']),
        losses: asInt(map['losses']),
        pnl: asDouble(map['pnl']),
      );
}

class TimeStats {
  const TimeStats({
    required this.timezone,
    required this.hours,
    required this.sessions,
    required this.holdTrades,
    required this.medianMinutes,
    required this.averageMinutes,
  });

  final String timezone;
  final List<HourStat> hours;
  final List<SessionStat> sessions;
  final int holdTrades;
  final double? medianMinutes;
  final double? averageMinutes;

  factory TimeStats.fromMap(Map<String, dynamic> map) {
    final hold = asMap(map['hold']);
    return TimeStats(
      timezone: map['timezone']?.toString() ?? 'UTC',
      hours: asList(map['hours'])
          .map((row) => HourStat.fromMap(asMap(row)))
          .toList(),
      sessions: asList(map['sessions'])
          .map((row) => SessionStat.fromMap(asMap(row)))
          .toList(),
      holdTrades: asInt(hold['trades']),
      medianMinutes: asNullableDouble(hold['median_minutes']),
      averageMinutes: asNullableDouble(hold['average_minutes']),
    );
  }

  static const empty = TimeStats(
    timezone: 'UTC',
    hours: [],
    sessions: [],
    holdTrades: 0,
    medianMinutes: null,
    averageMinutes: null,
  );
}

class MediaAttachment {
  const MediaAttachment({
    required this.id,
    required this.kind,
    this.storagePath,
    this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.durationSeconds,
  });

  final String id;
  final String kind;
  final String? storagePath;
  final String? fileName;
  final String? mimeType;
  final int? sizeBytes;
  final double? durationSeconds;

  bool get isImage => kind == 'image';
  bool get isAudio => kind == 'audio';

  factory MediaAttachment.fromMap(Map<String, dynamic> map) => MediaAttachment(
        id: map['id']?.toString() ?? '',
        kind: map['kind']?.toString() ?? 'image',
        storagePath: asString(map['storage_path']),
        fileName: asString(map['file_name']),
        mimeType: asString(map['mime_type']),
        sizeBytes: asNullableInt(map['size_bytes']),
        durationSeconds: asNullableDouble(map['duration_seconds']),
      );
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.symbol,
    required this.type,
    required this.pnl,
    required this.strategy,
    required this.notes,
    required this.tags,
    required this.openTime,
    required this.closeTime,
    required this.createdAt,
    required this.imageCount,
    required this.audioCount,
    required this.attachments,
  });

  final String id;
  final String symbol;
  final String type;
  final double pnl;
  final String? strategy;
  final String? notes;
  final List<String> tags;
  final DateTime? openTime;
  final DateTime? closeTime;
  final DateTime createdAt;
  final int imageCount;
  final int audioCount;
  final List<MediaAttachment> attachments;

  factory JournalEntry.fromMap(Map<String, dynamic> map) => JournalEntry(
        id: map['id']?.toString() ?? '',
        symbol: map['symbol']?.toString() ?? '—',
        type: map['type']?.toString() ?? 'BUY',
        pnl: asDouble(map['pnl']),
        strategy: asString(map['strategy']),
        notes: asString(map['notes']),
        tags: asStringList(map['tags']),
        openTime: asDate(map['open_time']),
        closeTime: asDate(map['close_time']),
        createdAt: asDate(map['created_at']) ?? DateTime.now(),
        imageCount: asInt(map['image_count']),
        audioCount: asInt(map['audio_count']),
        attachments: asList(map['attachments'])
            .map((row) => MediaAttachment.fromMap(asMap(row)))
            .toList(),
      );
}

class TradeRow {
  const TradeRow({
    required this.id,
    required this.symbol,
    required this.type,
    required this.entryPrice,
    required this.exitPrice,
    required this.lotSize,
    required this.pnl,
    required this.commission,
    required this.swap,
    required this.openTime,
    required this.closeTime,
    required this.strategy,
    required this.notes,
    required this.tags,
    required this.createdAt,
    required this.imageCount,
    required this.audioCount,
  });

  final String id;
  final String symbol;
  final String type;
  final double entryPrice;
  final double exitPrice;
  final double lotSize;
  final double pnl;
  final double commission;
  final double swap;
  final DateTime? openTime;
  final DateTime? closeTime;
  final String? strategy;
  final String? notes;
  final List<String> tags;
  final DateTime createdAt;
  final int imageCount;
  final int audioCount;

  DateTime get tradedAt => closeTime ?? openTime ?? createdAt;

  String? get timeWindow {
    if (openTime == null && closeTime == null) return null;
    final minutes = openTime != null && closeTime != null
        ? closeTime!.difference(openTime!).inMinutes
        : null;
    return '${timeOf(openTime)} → ${timeOf(closeTime)}'
        '${minutes != null && minutes >= 0 ? ' · ${durationText(minutes)}' : ''}';
  }

  factory TradeRow.fromMap(Map<String, dynamic> map) => TradeRow(
        id: map['id']?.toString() ?? '',
        symbol: map['symbol']?.toString() ?? '—',
        type: map['type']?.toString() ?? 'BUY',
        entryPrice: asDouble(map['entry_price']),
        exitPrice: asDouble(map['exit_price']),
        lotSize: asDouble(map['lot_size']),
        pnl: asDouble(map['pnl']),
        commission: asDouble(map['commission']),
        swap: asDouble(map['swap']),
        openTime: asDate(map['open_time']),
        closeTime: asDate(map['close_time']),
        strategy: asString(map['strategy']),
        notes: asString(map['notes']),
        tags: asStringList(map['tags']),
        createdAt: asDate(map['created_at']) ?? DateTime.now(),
        imageCount: asInt(map['image_count']),
        audioCount: asInt(map['audio_count']),
      );
}

class TradePageResult {
  const TradePageResult({
    required this.total,
    required this.totalPnl,
    required this.trades,
  });

  final int total;
  final double totalPnl;
  final List<TradeRow> trades;

  factory TradePageResult.fromMap(Map<String, dynamic> map) => TradePageResult(
        total: asInt(map['total']),
        totalPnl: asDouble(map['total_pnl']),
        trades: asList(map['trades'])
            .map((row) => TradeRow.fromMap(asMap(row)))
            .toList(),
      );

  static const empty = TradePageResult(total: 0, totalPnl: 0, trades: []);
}

/// A file that is already in storage but may not be linked to a trade yet.
class PendingAttachment {
  const PendingAttachment({
    required this.kind,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.durationSeconds,
    this.previewBytes,
  });

  final String kind;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final double? durationSeconds;
  final Uint8List? previewBytes;

  bool get isImage => kind == 'image';
}

class DashboardData {
  const DashboardData({
    required this.summary,
    required this.equity,
    required this.deposits,
    required this.timeStats,
    required this.journalFeed,
    required this.recentTrades,
  });

  final TradeSummary summary;
  final List<EquityPoint> equity;
  final double deposits;
  final TimeStats timeStats;
  final List<JournalEntry> journalFeed;
  final List<TradeRow> recentTrades;

  double get balance => deposits + summary.totalPnl;
}

/// One day of realised P&L from `daily_pnl(p_from, p_to)`.
class DailyPnlPoint {
  const DailyPnlPoint({
    required this.day,
    required this.pnl,
    required this.trades,
  });

  /// `2026-10-28`, exactly as Postgres renders a `date`.
  final String day;
  final double pnl;
  final int trades;

  factory DailyPnlPoint.fromMap(Map<String, dynamic> map) => DailyPnlPoint(
        day: map['day']?.toString() ?? '',
        pnl: asDouble(map['pnl']),
        trades: asInt(map['trades']),
      );
}

class SymbolStat {
  const SymbolStat({
    required this.symbol,
    required this.trades,
    required this.wins,
    required this.pnl,
  });

  final String symbol;
  final int trades;
  final int wins;
  final double pnl;

  int get losses => (trades - wins).clamp(0, trades);
  double get winRate => trades > 0 ? (wins / trades) * 100 : 0;

  factory SymbolStat.fromMap(Map<String, dynamic> map) => SymbolStat(
        symbol: map['symbol']?.toString() ?? '—',
        trades: asInt(map['trades']),
        wins: asInt(map['wins']),
        pnl: asDouble(map['pnl']),
      );
}

/// One label from the `strategy_stats` RPC. Blank labels arrive as "Untagged".
class StrategyStat {
  const StrategyStat({
    required this.strategy,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.pnl,
    required this.winRate,
  });

  final String strategy;
  final int trades;
  final int wins;
  final int losses;
  final double pnl;
  final double winRate;

  double get expectancy => trades > 0 ? pnl / trades : 0;

  factory StrategyStat.fromMap(Map<String, dynamic> map) => StrategyStat(
        strategy: map['strategy']?.toString() ?? 'Untagged',
        trades: asInt(map['trades']),
        wins: asInt(map['wins']),
        losses: asInt(map['losses']),
        pnl: asDouble(map['pnl']),
        winRate: asDouble(map['win_rate']),
      );
}

class TagStat {
  const TagStat({
    required this.tag,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.pnl,
    required this.winRate,
  });

  final String tag;
  final int trades;
  final int wins;
  final int losses;
  final double pnl;
  final double winRate;

  factory TagStat.fromMap(Map<String, dynamic> map) => TagStat(
        tag: map['tag']?.toString() ?? '—',
        trades: asInt(map['trades']),
        wins: asInt(map['wins']),
        losses: asInt(map['losses']),
        pnl: asDouble(map['pnl']),
        winRate: asDouble(map['win_rate']),
      );
}

/// One broker from the MT5 directory behind `/api/brokers`.
///
/// `servers` holds the server names worth suggesting for it. It is deliberately
/// partial — brokers add and retire servers constantly — so the server field
/// stays free text and this list is only a shortcut.
class Mt5Broker {
  const Mt5Broker({required this.name, this.servers = const []});

  final String name;
  final List<String> servers;

  factory Mt5Broker.fromMap(Map<String, dynamic> map) => Mt5Broker(
        name: asString(map['name']) ?? '',
        servers: asList(map['servers'])
            .map((server) => server.toString())
            .where((server) => server.isNotEmpty)
            .toList(),
      );
}
