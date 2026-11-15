import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The clock the chart's time axis speaks.
///
/// Candles arrive as UTC epochs and sessions are quoted in UTC, but a trader
/// reading a New York chart expects New York hours on the axis, and a chart
/// opened in Johannesburg expects South African hours. This wrapper keeps the
/// conversion in one place so the axis, the crosshair tag and the day
/// separators can never disagree about which midnight they mean.
///
/// The empty [id] means "whatever the phone is set to", which is Dart's local
/// time and therefore already DST-correct. Named zones come from the bundled
/// tz database, so New York moves between EST and EDT on its own.
class ChartZone {
  const ChartZone(this.id, this.label);

  /// Follow the device's own clock.
  static const ChartZone device = ChartZone('', 'Device');

  static const ChartZone utc = ChartZone('UTC', 'UTC');

  /// The zones a trader is most likely to want, in the order they are offered.
  static const List<ChartZone> quick = <ChartZone>[
    device,
    utc,
    ChartZone('Africa/Johannesburg', 'Johannesburg'),
    ChartZone('Africa/Lagos', 'Lagos'),
    ChartZone('Africa/Nairobi', 'Nairobi'),
    ChartZone('Europe/London', 'London'),
    ChartZone('Europe/Berlin', 'Berlin'),
    ChartZone('Europe/Istanbul', 'Istanbul'),
    ChartZone('America/New_York', 'New York'),
    ChartZone('America/Chicago', 'Chicago'),
    ChartZone('America/Sao_Paulo', 'São Paulo'),
    ChartZone('Asia/Dubai', 'Dubai'),
    ChartZone('Asia/Kolkata', 'Mumbai'),
    ChartZone('Asia/Shanghai', 'Shanghai'),
    ChartZone('Asia/Tokyo', 'Tokyo'),
    ChartZone('Australia/Sydney', 'Sydney'),
    ChartZone('Pacific/Auckland', 'Auckland'),
  ];

  /// IANA name, or empty for the device clock.
  final String id;

  /// Short name for the picker and the chart's status line.
  final String label;

  bool get isDevice => id.isEmpty;

  /// The UTC clock: candles are already expressed in it.
  bool get isUtc => id == 'UTC';

  static bool _ready = false;

  /// Loads the tz database once. Cheap to call from a getter: after the first
  /// call it is a boolean test.
  static void ensureReady() {
    if (_ready) return;
    tzdata.initializeTimeZones();
    _ready = true;
  }

  /// The stored value as a zone, falling back to the device clock for anything
  /// unknown (a removed zone, a hand-edited layout).
  static ChartZone byId(String? id) {
    if (id == null || id.isEmpty) return device;
    if (id == utc.id) return utc;
    final match = quick.where((zone) => zone.id == id);
    if (match.isNotEmpty) return match.first;
    ensureReady();
    if (tz.timeZoneDatabase.locations.containsKey(id)) {
      return ChartZone(id, _pretty(id));
    }
    return device;
  }

  /// Wall-clock time in this zone for a UTC instant.
  ///
  /// The returned value carries the zone's calendar fields, so `DateFormat`
  /// prints the trader's hours without any further conversion. For the device
  /// zone that is simply [DateTime.toLocal].
  DateTime wall(DateTime instant) {
    final utcTime = instant.toUtc();
    if (isUtc) return utcTime;
    if (isDevice) return utcTime.toLocal();
    ensureReady();
    return tz.TZDateTime.from(utcTime, tz.getLocation(id));
  }

  /// `UTC+2` / `UTC-4` for the instant, which is what the chart corner shows.
  /// DST is read from the zone at that instant, not from today's offset.
  String offsetLabel([DateTime? instant]) {
    final wallTime = wall(instant ?? DateTime.now().toUtc());
    final minutes = wallTime.timeZoneOffset.inMinutes;
    if (minutes == 0) return 'UTC';
    final sign = minutes < 0 ? '-' : '+';
    final abs = minutes.abs();
    final hours = abs ~/ 60;
    final rest = abs % 60;
    return 'UTC$sign$hours${rest == 0 ? '' : ':${rest.toString().padLeft(2, '0')}'}';
  }

  /// Name plus offset, for chips and the picker.
  String describe([DateTime? instant]) {
    final clock = isDevice ? 'Device (${DateTime.now().timeZoneName})' : label;
    return '$clock · ${offsetLabel(instant)}';
  }

  /// Every zone the bundled database knows, sorted, with the quick list first.
  static List<ChartZone> all() {
    ensureReady();
    final ids = tz.timeZoneDatabase.locations.keys.toList()..sort();
    final seen = <String>{'', utc.id, for (final zone in quick) zone.id};
    return [
      ...quick,
      for (final id in ids)
        if (id != utc.id && !seen.contains(id))
          ChartZone(id, _pretty(id)),
    ];
  }

  /// Case-insensitive match on the city or the full IANA name.
  static List<ChartZone> search(String query) {
    final allZones = all();
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return allZones;
    return [
      for (final zone in allZones)
        if (zone.label.toLowerCase().contains(needle) ||
            zone.id.toLowerCase().contains(needle))
          zone,
    ];
  }

  /// `Australia/Sydney` → `Sydney`, `America/Argentina/Buenos_Aires` →
  /// `Buenos Aires`.
  static String _pretty(String id) {
    final tail = id.split('/').last.replaceAll('_', ' ');
    return tail.isEmpty ? id : tail;
  }

  @override
  bool operator ==(Object other) => other is ChartZone && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => describe();
}
