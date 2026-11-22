import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chart_theme.dart';

/// A saved chart layout: how the canvas looked, on which market, at which
/// candle size.
///
/// A layout is not a copy of the journal. Drawings already live per symbol and
/// sync to the account, so a layout that carried them would be a third copy to
/// keep honest. What it does carry is everything else the trader builds up —
/// palette, studies, indicators, grid, watermark, events, time zone — plus the
/// symbol and interval they were looking at, which is what makes a layout a
/// *place* rather than a theme.
@immutable
class ChartLayout {
  const ChartLayout({
    required this.id,
    required this.name,
    required this.symbol,
    required this.intervalKey,
    required this.style,
    required this.savedAt,
    this.starred = false,
    this.owner = '',
  });

  final String id;
  final String name;

  /// The market it was saved on. Opening a layout on a different market keeps
  /// that market — a layout is a way of looking, not a switch of instrument.
  final String symbol;

  /// [ChartInterval.key] at save time, e.g. `15m`.
  final String intervalKey;

  final ChartStyle style;
  final DateTime savedAt;

  /// Starred layouts sort first, the way a pinned chart does in every desk.
  final bool starred;

  /// Optional label shown in the list, e.g. the account it was built for.
  final String owner;

  /// "EURUSD, 1m (20 Nov 2026, 14:46)" — the subtitle the spec asks for.
  String get subtitle {
    final date = savedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${date.day} ${_months[date.month - 1]} ${date.year}, '
        '${two(date.hour)}:${two(date.minute)}';
    return '$symbol, $intervalKey ($stamp)';
  }

  ChartLayout copyWith({
    String? name,
    bool? starred,
    ChartStyle? style,
    String? intervalKey,
    DateTime? savedAt,
    String? symbol,
  }) {
    return ChartLayout(
      id: id,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      intervalKey: intervalKey ?? this.intervalKey,
      style: style ?? this.style,
      savedAt: savedAt ?? this.savedAt,
      starred: starred ?? this.starred,
      owner: owner,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'symbol': symbol,
        'interval': intervalKey,
        'style': style.toJson(),
        'savedAt': savedAt.toUtc().millisecondsSinceEpoch,
        'starred': starred,
        if (owner.isNotEmpty) 'owner': owner,
      };

  static ChartLayout? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || name is! String || name.isEmpty) return null;
    final symbol = value['symbol'];
    final interval = value['interval'];
    final savedAt = value['savedAt'];
    return ChartLayout(
      id: id,
      name: name,
      symbol: symbol is String && symbol.isNotEmpty ? symbol : '—',
      intervalKey: interval is String && interval.isNotEmpty ? interval : '1m',
      // An unreadable palette falls back to the app's own ink rather than
      // dropping the whole layout: the name is the part the trader typed.
      style: value['style'] is Map
          ? ChartStyle.fromJson(Map<Object?, Object?>.from(value['style'] as Map))
          : ChartStyle.ink,
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        savedAt is num ? savedAt.toInt() : 0,
        isUtc: true,
      ),
      starred: value['starred'] == true,
      owner: value['owner'] is String ? value['owner']! as String : '',
    );
  }

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// The saved-layout library, kept on the device.
///
/// Small, local and ordered: a list of layouts is not journal data, and putting
/// it behind a network round trip would mean the chart opens before its own
/// settings are known. SharedPreferences is enough for a handful of entries and
/// it is what the rest of the chart's preferences already use.
class ChartLayoutStore {
  static const String storageKey = 'chart.layouts.v1';
  static const String activeKey = 'chart.layouts.active.v1';

  /// A trader with more layouts than this cannot find them in a search box
  /// either; the cap only stops the preference from growing without bound.
  static const int maxLayouts = 40;

  static Future<List<ChartLayout>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return <ChartLayout>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ChartLayout>[];
      final layouts = <ChartLayout>[];
      for (final entry in decoded) {
        final layout = ChartLayout.fromJson(entry);
        if (layout != null) layouts.add(layout);
      }
      return _sorted(layouts);
    } catch (_) {
      // A corrupt list must not stop the chart opening; an empty library is a
      // worse surprise than a crash only for a moment.
      return <ChartLayout>[];
    }
  }

  static Future<void> save(List<ChartLayout> layouts) async {
    final trimmed = _sorted(layouts).take(maxLayouts).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(<Object?>[for (final layout in trimmed) layout.toJson()]),
      );
    } catch (_) {
      // Nothing to do: the in-memory list stays correct for this session.
    }
  }

  static Future<String?> activeId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(activeKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActive(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(activeKey);
      } else {
        await prefs.setString(activeKey, id);
      }
    } catch (_) {
      // The highlight is a convenience; losing it costs a glance.
    }
  }

  /// Starred first, then newest — the order the manager lists them in.
  static List<ChartLayout> _sorted(List<ChartLayout> layouts) {
    final next = [...layouts];
    next.sort((a, b) {
      if (a.starred != b.starred) return a.starred ? -1 : 1;
      return b.savedAt.compareTo(a.savedAt);
    });
    return next;
  }
}
