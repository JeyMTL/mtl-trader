import 'package:shared_preferences/shared_preferences.dart';

/// The tools a trader keeps at the top of the drawing sheet.
///
/// Four is the most that fits a thumb-width strip without scrolling, and the
/// sheet is meant to be used without scrolling. The defaults are the four a
/// discretionary trader reaches for on almost every idea: a trend line, a
/// horizontal level, a fib and a long position.
class ToolFavourites {
  ToolFavourites._();

  static const String storageKey = 'chart.tools.pinned.v1';

  /// The strip before anyone has pinned anything.
  static const List<String> defaults = <String>['trend', 'ray', 'fib', 'long'];

  static const int max = 4;

  /// Pinned ids, in the order they are shown.
  ///
  /// A stored list is trusted only for ids that still exist and only up to
  /// [max]: a renamed tool, or a list written by an older build, would
  /// otherwise leave a hole in the strip.
  static Future<List<String>> load(Set<String> known) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return defaults;
      final stored = <String>[
        for (final id in raw.split(','))
          if (id.trim().isNotEmpty) id.trim(),
      ].where(known.contains).toList();
      return stored.isEmpty ? defaults : stored.take(max).toList();
    } catch (_) {
      // A missing or unreadable preference keeps the defaults; the sheet is
      // still usable, which is what matters when a drawing is being placed.
      return defaults;
    }
  }

  static Future<void> save(List<String> pinned) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, pinned.take(max).join(','));
    } catch (_) {
      // The in-memory list stays correct for this session.
    }
  }

  /// The list after pinning or unpinning [id].
  ///
  /// A fifth pin pushes the oldest one out rather than refusing the tap: the
  /// trader asked for this tool, and the strip is capped by geometry, not by
  /// preference.
  static List<String> toggle(List<String> pinned, String id) {
    final next = <String>[...pinned];
    if (next.remove(id)) return next;
    next.add(id);
    while (next.length > max) {
      next.removeAt(0);
    }
    return next;
  }
}
