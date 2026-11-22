import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/level_touch.dart';
import 'package:mtl_trader_mobile/services/alerts.dart';

void main() {
  group('level touches', () {
    const entry = WatchedLevel(label: 'entry', price: 1.2050);
    const target = WatchedLevel(label: 'target', price: 1.2100);
    const stop = WatchedLevel(label: 'stop', price: 1.2000);

    test('a close that steps over a level reports it once', () {
      final hits = touchedLevels(
        from: 1.2040,
        to: 1.2060,
        levels: const [entry, target, stop],
      );

      expect(hits, const [entry]);
    });

    test('falling through a level counts, in the other direction', () {
      final hits = touchedLevels(
        from: 1.2055,
        to: 1.2045,
        levels: const [entry],
      );

      expect(hits, const [entry]);
    });

    test('landing exactly on a level is a touch', () {
      expect(
        touchedLevels(from: 1.2040, to: 1.2050, levels: const [entry]),
        const [entry],
      );
    });

    test('a level price was already standing on is not reported again', () {
      expect(
        touchedLevels(from: 1.2050, to: 1.2070, levels: const [entry]),
        isEmpty,
      );
    });

    test('an unchanged close reports nothing', () {
      expect(
        touchedLevels(from: 1.2050, to: 1.2050, levels: const [entry]),
        isEmpty,
      );
    });

    test('the first load, with no previous close, reports nothing', () {
      expect(
        touchedLevels(from: null, to: 1.2060, levels: const [entry]),
        isEmpty,
      );
    });

    test('a gap over several levels reports each of them', () {
      final hits = touchedLevels(
        from: 1.1995,
        to: 1.2105,
        levels: const [stop, entry, target],
      );

      expect(hits, const [stop, entry, target]);
    });

    test('levels outside the move are silent', () {
      expect(
        touchedLevels(from: 1.2010, to: 1.2020, levels: const [entry, target]),
        isEmpty,
      );
    });
  });

  group('alert events', () {
    test('survive a round trip through the history file', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1795000000000);
      final event = AlertEvent(
        kind: AlertKind.dailyStop,
        title: 'Daily stop reached',
        body: 'Loss 250.00 of the 250.00 limit.',
        reason: 'The day reached its loss limit.',
        at: at,
        delivered: false,
        muted: true,
      );

      final restored = AlertEvent.fromJson(event.toJson());

      expect(restored, isNotNull);
      expect(restored!.kind, AlertKind.dailyStop);
      expect(restored.title, event.title);
      expect(restored.reason, event.reason);
      expect(restored.at.toUtc(), at.toUtc());
      expect(restored.delivered, isFalse);
      expect(restored.muted, isTrue);
    });

    test('a delivered event keeps the shorthand out of the file', () {
      final json = AlertEvent(
        kind: AlertKind.levelTouch,
        title: 'EURUSD entry 1.2050 touched',
        body: 'Price crossed your level.',
        reason: 'A level you drew was crossed.',
        at: DateTime.fromMillisecondsSinceEpoch(1795000000000),
      ).toJson();

      expect(json.containsKey('d'), isFalse);
      expect(json.containsKey('m'), isFalse);
      expect(AlertEvent.fromJson(json)!.delivered, isTrue);
      expect(AlertEvent.fromJson(json)!.muted, isFalse);
    });

    test('a junk row is dropped rather than thrown', () {
      expect(AlertEvent.fromJson(null), isNull);
      expect(AlertEvent.fromJson('nonsense'), isNull);
      expect(AlertEvent.fromJson(const {'k': 'dailyStop'}), isNull);
    });
  });

  test('a reminder time renders as a wall clock', () {
    expect(const TimeOfDayValue(18, 5).label, '18:05');
    expect(const TimeOfDayValue(7, 0).label, '07:00');
  });
}
