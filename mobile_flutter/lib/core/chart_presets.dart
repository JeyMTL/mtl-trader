import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chart_theme.dart';

/// A named set of chart settings the trader can reapply.
///
/// Templates sit between the built-in palettes and a full layout: a preset is
/// only the canvas's own settings — colours, grid, crosshair, watermark,
/// studies — with no market or candle size attached, so "MTL" can be stamped
/// onto whichever chart is open.
@immutable
class ChartPreset {
  const ChartPreset({
    required this.name,
    required this.style,
    this.editedAtMs,
  });

  final String name;
  final ChartStyle style;

  /// When the look was last changed, epoch milliseconds.
  ///
  /// The same claim `chart_drawings.edited_at` carries, and for the same
  /// reason: a phone that was offline all afternoon must not overwrite a
  /// template saved on the web desk after it. Null on presets written before
  /// templates were shared.
  final int? editedAtMs;

  ChartPreset copyWith({String? name, ChartStyle? style, int? editedAtMs}) =>
      ChartPreset(
        name: name ?? this.name,
        style: style ?? this.style,
        editedAtMs: editedAtMs ?? this.editedAtMs,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'style': style.toJson(),
        if (editedAtMs != null) 'editedAt': editedAtMs,
      };

  static ChartPreset? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final edited = value['editedAt'];
    return ChartPreset(
      name: name.trim(),
      style: value['style'] is Map
          ? ChartStyle.fromJson(Map<Object?, Object?>.from(value['style'] as Map))
          : ChartStyle.ink,
      editedAtMs: edited is num ? edited.toInt() : null,
    );
  }
}

/// The trader's own templates, kept on the device beside the layouts.
class ChartPresetStore {
  static const String storageKey = 'chart.presets.v1';

  /// Enough for a handful of house looks; a list longer than this is a list
  /// nobody reads.
  static const int maxPresets = 20;

  static Future<List<ChartPreset>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return <ChartPreset>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ChartPreset>[];
      return <ChartPreset>[
        for (final entry in decoded)
          if (ChartPreset.fromJson(entry) case final preset?) preset,
      ];
    } catch (_) {
      return <ChartPreset>[];
    }
  }

  static Future<void> save(List<ChartPreset> presets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(<Object?>[
          for (final preset in presets.take(maxPresets)) preset.toJson(),
        ]),
      );
    } catch (_) {
      // The session keeps the in-memory copy either way.
    }
  }
}
