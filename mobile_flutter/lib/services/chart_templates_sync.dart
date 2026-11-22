import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/chart_presets.dart';
import '../core/chart_theme.dart';

/// The account copy of the trader's chart presets.
///
/// Templates are a named canvas look — colours, grid, crosshair, studies — with
/// no market attached, so "MTL" can be stamped onto whatever chart is open. The
/// phone has kept them in SharedPreferences; the web desk in the browser. This
/// is the copy that makes a look saved on one desk appear on the other.
///
/// The phone's `ChartStyle.toJson()` is the shared vocabulary: it is the older
/// and longer settings list, and the web desk writes it back untouched for the
/// keys it cannot paint. Both sides identify a template by `slug`, the trimmed
/// lowercase name, so "MTL" and "mtl" are one look.
///
/// A template is a preference, not trade data: every call here is best-effort
/// and reports a sentence instead of throwing. Nothing in this file can lose the
/// device's own list, and a failed sync leaves the chart exactly as it was.
class ChartTemplatesSync {
  ChartTemplatesSync({SupabaseClient? client}) : _client = client;

  SupabaseClient? _client;

  static const String table = 'chart_templates';

  /// Same cap the phone's store and the web desk use.
  static const int maxTemplates = ChartPresetStore.maxPresets;

  /// The settings sheet waits on this read, so it must not wait long: a slow or
  /// missing network shows the device's own templates rather than a spinner.
  static const Duration deadline = Duration(seconds: 4);

  SupabaseClient? get _db {
    final existing = _client;
    if (existing != null) return existing;
    try {
      return _client = Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// True when there is a project to sync to and someone signed in.
  bool get available {
    final db = _db;
    return db != null && db.auth.currentSession != null;
  }

  /// The case-insensitive identity of a template, matching the server's `slug`.
  static String slugFor(String name) => name.trim().toLowerCase();

  Future<ChartTemplatesSyncOutcome> sync(List<ChartPreset> local) async {
    final db = _db;
    if (db == null || db.auth.currentSession == null) {
      return ChartTemplatesSyncOutcome(
        presets: local,
        changed: false,
        error: 'Signed out, so templates stayed on this device.',
      );
    }

    List<Map<String, dynamic>> rows;
    try {
      final data = await db
          .from(table)
          .select('name, style, edited_at')
          .timeout(deadline);
      rows = <Map<String, dynamic>>[
        for (final row in data as List)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    } catch (error) {
      return ChartTemplatesSyncOutcome(
        presets: local,
        changed: false,
        error: _friendly(error),
      );
    }

    final remoteBySlug = <String, ChartPreset>{};
    for (final row in rows) {
      final preset = presetFromRow(row);
      if (preset == null) continue;
      remoteBySlug[slugFor(preset.name)] = preset;
    }

    // Union by slug, later edit winning. The list is rebuilt rather than edited
    // in place so a pull can never leave a half-merged list on screen.
    final merged = mergePresets(local, remoteBySlug);

    // Anything the account has never seen, or has an older copy of, goes up.
    var uploadFailed = false;
    for (final preset in merged) {
      final remote = remoteBySlug[slugFor(preset.name)];
      if (remote != null) {
        final localMs = preset.editedAtMs ?? 0;
        final remoteMs = remote.editedAtMs ?? 0;
        if (remoteMs > localMs) continue;
        if (remoteMs == localMs && _sameStyle(preset.style, remote.style)) continue;
      }
      final failure = await _push(db, preset);
      if (failure != null) uploadFailed = true;
    }

    final capped = merged.take(maxTemplates).toList();

    return ChartTemplatesSyncOutcome(
      presets: capped,
      changed: !_sameOrder(local, capped),
      error: uploadFailed
          ? 'Some templates could not be saved to your account. They are safe '
              'on this device.'
          : null,
    );
  }

  /// Writes one template to the account, replacing the row with the same slug.
  Future<String?> push(ChartPreset preset) async {
    final db = _db;
    if (db == null || db.auth.currentSession == null) return null;
    return _push(db, preset);
  }

  /// Deletes one template from the account.
  ///
  /// Only a delete the trader asked for reaches this: the merge never removes a
  /// remote row for being missing locally, so a fresh install cannot wipe the
  /// templates saved on another desk.
  Future<String?> remove(ChartPreset preset) async {
    final db = _db;
    if (db == null || db.auth.currentSession == null) return null;
    try {
      await db.from(table).delete().eq('slug', slugFor(preset.name));
      return null;
    } catch (error) {
      return _friendly(error);
    }
  }

  Future<String?> _push(SupabaseClient db, ChartPreset preset) async {
    try {
      await db.from(table).upsert(
        <String, Object?>{
          'slug': slugFor(preset.name),
          'name': preset.name,
          'style': preset.style.toJson(),
          'edited_at': _isoTime(
            preset.editedAtMs ?? DateTime.now().millisecondsSinceEpoch,
          ),
        },
        onConflict: 'user_id,slug',
      );
      return null;
    } catch (error) {
      return _friendly(error);
    }
  }

  /// Union of the device's list and the account's, by slug.
  ///
  /// The later edit wins; a tie keeps the device's copy, which is the same rule
  /// the web desk applies, so neither side can see a different winner and the
  /// row stops flapping. Sorted newest first, the way a list of saves is read.
  static List<ChartPreset> mergePresets(
    List<ChartPreset> local,
    Map<String, ChartPreset> remoteBySlug,
  ) {
    final localBySlug = <String, ChartPreset>{
      for (final preset in local) slugFor(preset.name): preset,
    };
    final merged = <ChartPreset>[];
    for (final slug in <String>{...remoteBySlug.keys, ...localBySlug.keys}) {
      final remote = remoteBySlug[slug];
      final own = localBySlug[slug];
      if (remote == null) {
        merged.add(own!);
      } else if (own == null) {
        merged.add(remote);
      } else {
        merged.add((own.editedAtMs ?? 0) >= (remote.editedAtMs ?? 0) ? own : remote);
      }
    }
    merged.sort((a, b) => (b.editedAtMs ?? 0).compareTo(a.editedAtMs ?? 0));
    return merged;
  }

  static ChartPreset? presetFromRow(Map<String, dynamic> row) {
    final name = row['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final style = row['style'];
    return ChartPreset(
      name: name.trim(),
      style: style is Map
          ? ChartStyle.fromJson(Map<Object?, Object?>.from(style))
          : ChartStyle.ink,
      editedAtMs: _parseEditTime(row['edited_at']),
    );
  }

  static String _isoTime(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  static int? _parseEditTime(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return DateTime.tryParse(raw)?.millisecondsSinceEpoch;
    return null;
  }

  /// Whether two looks are identical, compared through the shared JSON: the
  /// phone can hold a style the web desk cannot paint, and only a real change
  /// should push a row.
  static bool _sameStyle(ChartStyle a, ChartStyle b) =>
      ChartStyle.encode(a) == ChartStyle.encode(b);

  static bool _sameOrder(List<ChartPreset> a, List<ChartPreset> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (a[index].name != b[index].name) return false;
      if ((a[index].editedAtMs ?? 0) != (b[index].editedAtMs ?? 0)) return false;
    }
    return true;
  }

  static String _friendly(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('42p01') ||
        message.contains('does not exist') ||
        message.contains('schema cache')) {
      return 'Chart templates are not shared yet — apply '
          'supabase/migrations/20261127_chart_templates.sql.';
    }
    return 'Could not reach the account. The templates on this device are '
        'unaffected.';
  }
}

/// What one reconciliation did: the list to show, whether it differs from the
/// one handed in, and why nothing could be shared when that happened.
class ChartTemplatesSyncOutcome {
  const ChartTemplatesSyncOutcome({
    required this.presets,
    required this.changed,
    this.error,
  });

  final List<ChartPreset> presets;
  final bool changed;
  final String? error;
}
