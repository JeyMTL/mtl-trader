import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The instruments a trader pinned to the top of the picker.
///
/// Per device, like the chart presets: which symbols someone watches is a
/// habit, not account data, and it stays useful signed out.
class SymbolFavorites {
  static const String storageKey = 'mtl_symbol_favorites';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((value) => '$value').toList();
    } catch (_) {
      return const [];
    }
  }

  /// Adds the symbol, or removes it when it is already pinned.
  static Future<List<String>> toggle(String symbol) async {
    final current = await load();
    final next = current.contains(symbol)
        ? (current.where((item) => item != symbol).toList())
        : [...current, symbol];
    await _save(next);
    return next;
  }

  static Future<void> _save(List<String> symbols) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(symbols));
  }
}
