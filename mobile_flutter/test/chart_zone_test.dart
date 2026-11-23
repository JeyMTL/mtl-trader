import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_theme.dart';
import 'package:mtl_trader_mobile/core/chart_zone.dart';

void main() {
  test('Johannesburg reads two hours ahead of UTC', () {
    final zone = ChartZone.byId('Africa/Johannesburg');

    expect(zone.id, 'Africa/Johannesburg');
    expect(zone.wall(DateTime.utc(2026, 7, 15, 7)).hour, 9);
    expect(zone.offsetLabel(DateTime.utc(2026, 7, 15, 7)), 'UTC+2');
  });

  test('New York follows daylight saving', () {
    final zone = ChartZone.byId('America/New_York');

    expect(zone.wall(DateTime.utc(2026, 1, 15, 12)).hour, 7);
    expect(zone.wall(DateTime.utc(2026, 7, 15, 12)).hour, 8);
    expect(zone.offsetLabel(DateTime.utc(2026, 1, 15, 12)), 'UTC-5');
    expect(zone.offsetLabel(DateTime.utc(2026, 7, 15, 12)), 'UTC-4');
  });

  // The account tab offers Europe/Stockholm, which the trimmed `latest`
  // dataset does not carry; when it was missing the clock silently showed the
  // device time instead of the chosen zone.
  test('every zone the account tab offers resolves', () {
    for (final id in [
      'Europe/Stockholm',
      'Europe/London',
      'Africa/Nairobi',
      'America/New_York',
    ]) {
      expect(ChartZone.byId(id).id, id, reason: id);
    }
  });

  test('an unknown zone falls back to the device clock', () {
    expect(ChartZone.byId('Mars/Olympus').isDevice, isTrue);
    expect(ChartZone.byId(null).isDevice, isTrue);
  });

  test('search finds a city and the full zone name', () {
    expect(ChartZone.search('johannesburg').first.id, 'Africa/Johannesburg');
    expect(
      ChartZone.search('africa/johannesburg').first.id,
      'Africa/Johannesburg',
    );
    expect(ChartZone.search('new york'), isNotEmpty);
  });

  test('the chosen clock survives a saved layout', () {
    final style = ChartStyle.ink.copyWith(zoneId: 'Asia/Tokyo');
    final decoded = ChartStyle.decode(ChartStyle.encode(style));

    expect(decoded.zoneId, 'Asia/Tokyo');
    expect(decoded.zone.label, 'Tokyo');
  });

  test('a layout saved before time zones keeps the device clock', () {
    final decoded = ChartStyle.fromJson(const {'preset': 'ink'});

    expect(decoded.zone.isDevice, isTrue);
  });
}
