import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One statement that was imported from this device.
///
/// The shape matches the web desk's `mtl_imports` entries (id, filename,
/// tradeCount, timestamp) so both platforms describe an import the same way.
class ImportRecord {
  const ImportRecord({
    required this.id,
    required this.filename,
    required this.tradeCount,
    required this.timestamp,
  });

  /// The batch id written to `trades.import_id`.
  final String id;
  final String filename;
  final int tradeCount;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'tradeCount': tradeCount,
        'timestamp': timestamp.toIso8601String(),
      };

  static ImportRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final at = DateTime.tryParse(raw['timestamp']?.toString() ?? '');
    if (id is! String || id.isEmpty || at == null) return null;
    final count = raw['tradeCount'];
    return ImportRecord(
      id: id,
      filename: raw['filename']?.toString() ?? 'Unknown',
      tradeCount: count is int ? count : int.tryParse('$count') ?? 0,
      timestamp: at,
    );
  }
}

/// Import history, newest first, kept on the device the way the web desk keeps
/// it in the browser. It is a convenience list, not a source of truth: the rows
/// themselves live in `trades` and are grouped by `import_id`.
class ImportHistoryStore {
  /// The web desk's localStorage key.
  static const String storageKey = 'mtl_imports';

  static Future<List<ImportRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(ImportRecord.fromJson)
          .whereType<ImportRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ImportRecord>> add(ImportRecord record) async {
    final records = await load();
    final next = [
      record,
      ...records.where((item) => item.id != record.id),
    ];
    await _save(next);
    return next;
  }

  static Future<List<ImportRecord>> remove(String id) async {
    final records = await load();
    final next = records.where((item) => item.id != id).toList();
    await _save(next);
    return next;
  }

  /// Clearing the journal also forgets every import, like the web desk.
  static Future<List<ImportRecord>> clear() async {
    await _save(const []);
    return const [];
  }

  static Future<void> _save(List<ImportRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }
}
