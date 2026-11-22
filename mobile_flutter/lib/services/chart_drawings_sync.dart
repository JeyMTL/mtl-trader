import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/chart_drawings.dart';

/// Two-way reconciliation between the phone's objects and the shared
/// `chart_drawings` table the web desk writes.
///
/// Objects carry the id of their row, so a move is an **update**: the same row
/// keeps its id, its `updated_at` and its place in every other device's view.
/// Signature matching is still there, but only as the hand-over for objects that
/// have no id yet — everything drawn before ids existed, and everything this
/// phone has not shared before. Once an object has an id, ids decide.
///
/// The `seen` set — remote ids this device has already reconciled — is what
/// makes a deletion stick: a row this phone pulled before and no longer holds is
/// one the trader deleted, so the table follows. Without it, the next sync would
/// pull the object straight back.
///
/// Position tools stay local. They are three prices and a box, not anchors, and
/// the web desk has no position tool to draw them back into.
class ChartDrawingsSync {
  ChartDrawingsSync({SupabaseClient? client}) : _client = client;

  SupabaseClient? _client;

  /// Null when the app has no Supabase session yet (or is running in a widget
  /// test), so every caller has to treat syncing as optional.
  SupabaseClient? get _db {
    final existing = _client;
    if (existing != null) return existing;
    try {
      return _client = Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// The symbol the table is keyed by.
  ///
  /// The phone's instrument list says `EURUSD` and `XAUUSD`; the web desk says
  /// `EUR_USD` and `XAU_USD`, which is also the vendor's own spelling. Without
  /// one canonical form the same pair would have two sets of levels that never
  /// meet. Indices keep their short names (`US30`, `NAS100`) because that is
  /// what both sides already call them.
  static String symbolForCloud(String symbol) {
    final trimmed = symbol.trim().toUpperCase();
    if (trimmed.isEmpty || trimmed.contains('_')) return trimmed;
    for (final quote in _quoteCurrencies) {
      if (trimmed.length > quote.length && trimmed.endsWith(quote)) {
        return '${trimmed.substring(0, trimmed.length - quote.length)}_$quote';
      }
    }
    return trimmed;
  }

  static const List<String> _quoteCurrencies = [
    'USD',
    'EUR',
    'JPY',
    'GBP',
    'AUD',
    'CHF',
    'CAD',
    'NZD',
  ];

  /// True when a Supabase client exists, i.e. there is somewhere to sync to.
  /// A widget test or an unconfigured build answers false, and the chart then
  /// stays purely local rather than scheduling work it cannot do.
  bool get available => _db != null;

  static const String seenPrefix = 'chart.drawings.cloud.v1.';

  /// More ids than any sane chart holds; the cap only stops the pref value from
  /// growing without bound on a symbol that is edited for years.
  static const int maxSeen = 2000;

  Future<ChartDrawingsSyncOutcome> sync(
    String symbol,
    List<ChartDrawing> local,
  ) async {
    final db = _db;
    if (db == null) {
      return ChartDrawingsSyncOutcome(drawings: local, changed: false);
    }
    if (db.auth.currentSession == null) {
      return ChartDrawingsSyncOutcome(
        drawings: local,
        changed: false,
        error: 'Signed out, so the shared copy was not refreshed.',
      );
    }

    final cloudSymbol = symbolForCloud(symbol);
    final List<Map<String, dynamic>> rows;
    try {
      final data = await db
          .from('chart_drawings')
          .select('id, kind, points, text, style, edited_at')
          .eq('symbol', cloudSymbol);
      rows = [
        for (final row in data as List)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    } catch (error) {
      // The table may not exist yet on this project; the chart keeps working
      // from the device copy and the caller can show why.
      return ChartDrawingsSyncOutcome(
        drawings: local,
        changed: false,
        error: _friendly(error),
      );
    }

    final seen = await _seen(symbol);

    // Index the table once: by id, and by content for the hand-over case.
    final remoteById = <String, ChartDrawing>{};
    final remoteSignatureById = <String, String>{};
    final idBySignature = <String, String>{};
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null) continue;
      final drawing = drawingFromRow(row);
      if (drawing == null) continue;
      final signature = drawingSignature(drawing);
      remoteById[id] = drawing;
      remoteSignatureById[id] = signature;
      idBySignature.putIfAbsent(signature, () => id);
    }

    var uploadFailed = false;
    final resolved = <ChartDrawing>[];
    final usedIds = <String>{};
    final toUpdate = <String, ChartDrawing>{};

    for (final drawing in local) {
      final id = drawing.id;

      // Same object, same row: the later edit wins, whichever device syncs
      // second. When the two disagree, one of them has to give up its version.
      if (id != null && remoteById.containsKey(id)) {
        usedIds.add(id);
        final remote = remoteById[id]!;
        final localSignature = drawingSignature(drawing);
        if (localSignature == remoteSignatureById[id]) {
          resolved.add(drawing);
          continue;
        }
        final winner = localEditWins(
          localMs: drawing.editedAtMs ?? 0,
          localSignature: localSignature,
          remoteMs: remote.editedAtMs ?? 0,
          remoteSignature: remoteSignatureById[id] ?? '',
        );
        if (winner) {
          final stamped = drawing.editedAtMs == null
              ? drawing.withEditedAt(DateTime.now().millisecondsSinceEpoch)
              : drawing;
          toUpdate[id] = stamped;
          resolved.add(stamped);
        } else {
          // A newer version from the other device replaces this one locally.
          // Without this, an offline phone would push its stale geometry over
          // the edit made after it.
          resolved.add(remote);
        }
        continue;
      }

      // No id, or an id the table does not have: match on content and adopt the
      // row rather than inserting a twin.
      final signature = drawingSignature(drawing);
      final matchedId = idBySignature[signature];
      if (matchedId != null && !usedIds.contains(matchedId)) {
        usedIds.add(matchedId);
        resolved.add(drawing.withId(matchedId));
        continue;
      }

      // It had a row and the row is gone: another device removed it, so this
      // copy follows instead of being re-uploaded as a new object.
      if (id != null) continue;

      resolved.add(drawing);
    }

    // A move keeps its row: one update, same id, same updated_at chain.
    for (final entry in toUpdate.entries) {
      final drawing = entry.value;
      try {
        await db.from('chart_drawings').update({
          'kind': drawing.kind.name,
          'points': drawingToPoints(drawing),
          'text': drawing.text,
          // The look travels with the geometry: a zone made red and half-solid
          // on the phone must be the same zone on the web desk.
          'style': drawing.look.toJson(),
          // The edit time, not the arrival time: this is what the other device
          // compares against when it comes back.
          'edited_at': _isoTime(
            drawing.editedAtMs ?? DateTime.now().millisecondsSinceEpoch,
          ),
        }).eq('id', entry.key);
      } catch (_) {
        uploadFailed = true;
      }
    }

    // Objects that have never been shared are the only ones inserted, and the id
    // the database returns is written onto the object so the next edit updates.
    for (var index = 0; index < resolved.length; index += 1) {
      final drawing = resolved[index];
      if (drawing.id != null || !_isShareable(drawing)) continue;
      try {
        final inserted = await db
            .from('chart_drawings')
            .insert({
              'symbol': cloudSymbol,
              'kind': drawing.kind.name,
              'points': drawingToPoints(drawing),
              'text': drawing.text,
              'style': drawing.look.toJson(),
              'edited_at': _isoTime(
                drawing.editedAtMs ?? DateTime.now().millisecondsSinceEpoch,
              ),
            })
            .select('id')
            .single();
        final id = (inserted as Map)['id']?.toString();
        if (id == null) continue;
        resolved[index] = drawing.withId(id);
        seen.add(id);
        usedIds.add(id);
      } catch (_) {
        uploadFailed = true;
      }
    }

    // Rows this device never used.
    for (final entry in remoteById.entries) {
      final id = entry.key;
      if (usedIds.contains(id)) {
        seen.add(id);
        continue;
      }
      if (!seen.contains(id)) {
        // Pinned on another device since the last sync: it joins this chart.
        final drawing = entry.value;
        seen.add(id);
        if (_isShareable(drawing)) {
          resolved.add(drawing);
          usedIds.add(id);
        }
        continue;
      }
      // Reconciled before and no longer on this chart: the trader deleted it.
      try {
        await db.from('chart_drawings').delete().eq('id', id);
        seen.remove(id);
      } catch (_) {
        uploadFailed = true;
      }
    }

    await _rememberSeen(symbol, seen);

    return ChartDrawingsSyncOutcome(
      drawings: resolved,
      changed: !_sameOrder(local, resolved),
      error: uploadFailed
          ? 'Some levels could not be saved to your account. They are safe on '
              'this device.'
          : null,
    );
  }

  /// Deletes every shared object for `symbol`.
  ///
  /// "Clear all" has to mean all: the phone's copy and the account's, including
  /// levels pinned on another device. Without this the next sync would pull back
  /// every row this phone had not yet seen, and the chart would look like it
  /// ignored the command.
  Future<String?> clear(String symbol) async {
    final db = _db;
    if (db == null) return null;
    final cloudSymbol = symbolForCloud(symbol);
    try {
      await db.from('chart_drawings').delete().eq('symbol', cloudSymbol);
      await _rememberSeen(symbol, <String>{});
      return null;
    } catch (error) {
      return _friendly(error);
    }
  }

  /// The cloud shape of one object: an anchor list, whatever the kind.
  static List<Map<String, num>> drawingToPoints(ChartDrawing drawing) {
    switch (drawing.kind) {
      case DrawingKind.ray:
        // A horizontal level has no time of its own; the web reads its price.
        return [
          {'t': 0, 'p': drawing.price ?? 0},
        ];
      case DrawingKind.trend:
        return [
          {'t': drawing.startMs, 'p': drawing.startPrice},
          {'t': drawing.endMs, 'p': drawing.endPrice},
        ];
      case DrawingKind.position:
        return const [];
      default:
        return [
          for (final point in drawing.points) {'t': point.ms, 'p': point.price},
        ];
    }
  }

  static ChartDrawing? drawingFromRow(Map<String, dynamic> row) {
    final kindName = row['kind']?.toString();
    DrawingKind? kind;
    for (final candidate in DrawingKind.values) {
      if (candidate.name == kindName) kind = candidate;
    }
    if (kind == null) return null;
    final rawId = row['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : null;
    final editedAtMs = _parseEditTime(row['edited_at']);

    final points = <ChartPoint>[];
    final raw = row['points'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final t = entry['t'];
        final p = entry['p'];
        if (t is! num || p is! num) continue;
        points.add(ChartPoint(ms: t.toInt(), price: p.toDouble()));
      }
    }

    if (kind == DrawingKind.ray) {
      if (points.isEmpty) return null;
      return ChartDrawing.ray(
        id: id,
        editedAtMs: editedAtMs,
        look: DrawingLook.fromJson(row['style']),
        price: points.first.price,
      );
    }
    if (kind == DrawingKind.trend) {
      if (points.length < 2) return null;
      return ChartDrawing.trend(
        id: id,
        editedAtMs: editedAtMs,
        look: DrawingLook.fromJson(row['style']),
        startMs: points[0].ms,
        startPrice: points[0].price,
        endMs: points[1].ms,
        endPrice: points[1].price,
      );
    }
    // Positions are not shared: the web desk has no tool to draw them back into
    // and a half-read box would be worse than none.
    if (kind == DrawingKind.position) return null;
    if (points.isEmpty) return null;

    final label = row['text'];
    return ChartDrawing.points(
      id: id,
      editedAtMs: editedAtMs,
      look: DrawingLook.fromJson(row['style']),
      kind: kind,
      points: points,
      text: label is String && label.isNotEmpty ? label : null,
    );
  }

  static bool _isShareable(ChartDrawing drawing) =>
      drawing.kind != DrawingKind.position;

  static String _isoTime(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  static int? _parseEditTime(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return DateTime.tryParse(raw)?.millisecondsSinceEpoch;
    return null;
  }

  static bool _sameOrder(List<ChartDrawing> a, List<ChartDrawing> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (a[index].id != b[index].id) return false;
      if (drawingSignature(a[index]) != drawingSignature(b[index])) {
        return false;
      }
    }
    return true;
  }

  static Future<Set<String>> _seen(String symbol) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$seenPrefix$symbol');
      if (raw == null || raw.isEmpty) return <String>{};
      return raw.split(',').where((id) => id.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> _rememberSeen(String symbol, Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kept = ids.length > maxSeen
          ? ids.toList().sublist(ids.length - maxSeen)
          : ids.toList();
      await prefs.setString('$seenPrefix$symbol', kept.join(','));
    } catch (_) {
      // Losing the memory costs a duplicate or a resurrected object, never data.
    }
  }

  static String _friendly(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('does not exist') ||
        message.contains('42p01') ||
        message.contains('schema cache')) {
      return 'Chart levels are not shared yet — apply '
          'supabase/migrations/20261124_chart_analysis.sql.';
    }
    return 'Could not reach the shared chart. The levels on this device are '
        'unaffected.';
  }
}

/// What one reconciliation did: the list to show, whether it differs from the
/// one handed in, and why nothing could be shared when that happened.
class ChartDrawingsSyncOutcome {
  const ChartDrawingsSyncOutcome({
    required this.drawings,
    required this.changed,
    this.error,
  });

  final List<ChartDrawing> drawings;
  final bool changed;
  final String? error;
}

/// Which version of one shared object stands.
///
/// The **later edit** wins, even when it reaches the table second — a phone that
/// was offline all afternoon must not overwrite a level moved after it. Two
/// versions with the same timestamp (same millisecond, or neither side stamped)
/// fall back to the content signature, so both devices pick the same winner and
/// the row stops flapping instead of trading back and forth on every sync.
bool localEditWins({
  required int localMs,
  required String localSignature,
  required int remoteMs,
  required String remoteSignature,
}) {
  if (localMs != remoteMs) return localMs > remoteMs;
  return localSignature.compareTo(remoteSignature) > 0;
}

/// A stable identity for the **content** of one object, used only to recognise a
/// row that has no id on this device — an object drawn before ids existed, or one
/// this phone has never shared.
///
/// Prices are rounded to seven decimals because a drag produces a long double
/// that a round trip through JSON may land a hair either side of; without the
/// rounding the same level would look like two. The row id is deliberately not
/// part of it: the signature describes the drawing, not where it is stored.
String drawingSignature(ChartDrawing drawing) {
  final buffer = StringBuffer(drawing.kind.name);
  switch (drawing.kind) {
    case DrawingKind.ray:
      buffer.write('|${_money(drawing.price ?? 0)}');
      break;
    case DrawingKind.trend:
      buffer.write(
        '|${drawing.startMs}|${_money(drawing.startPrice)}'
        '|${drawing.endMs}|${_money(drawing.endPrice)}',
      );
      break;
    case DrawingKind.position:
      buffer.write(
        '|${drawing.side?.name}|${drawing.startMs}|${drawing.endMs}'
        '|${_money(drawing.entry ?? 0)}|${_money(drawing.stop ?? 0)}'
        '|${_money(drawing.target ?? 0)}',
      );
      break;
    default:
      for (final point in drawing.points) {
        buffer.write('|${point.ms}|${_money(point.price)}');
      }
      if (drawing.text != null) buffer.write('|t:${drawing.text}');
      break;
  }
  // Style belongs in the signature: without it a restyle would look identical
  // to the row it came from, and the cloud copy would keep the old colour
  // forever while the phone showed the new one.
  buffer.write('|s:${lookSignature(drawing.look)}');
  return buffer.toString();
}

/// The look as one comparable string, for signatures and tests.
String lookSignature(DrawingLook look) => <Object?>[
      look.tint?.toARGB32() ?? '',
      look.weight ?? '',
      look.dashed ? 'd' : '',
      look.locked ? 'lk' : '',
      look.hidden ? 'hd' : '',
      look.fill ?? '',
      look.alert ? 'al' : '',
      look.fired ? 'fd' : '',
    ].join(',');

String _money(double value) => value.toStringAsFixed(7);
