import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtl_trader_mobile/core/chart_layouts.dart';
import 'package:mtl_trader_mobile/core/chart_theme.dart';

ChartLayout layout(
  String id,
  String name, {
  bool starred = false,
  int minutesAgo = 0,
  String symbol = 'EURUSD',
  String interval = '1m',
}) {
  return ChartLayout(
    id: id,
    name: name,
    symbol: symbol,
    intervalKey: interval,
    style: ChartStyle.slate,
    savedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
    starred: starred,
  );
}

void main() {

  test('a layout survives a round trip through storage', () async {
    SharedPreferences.setMockInitialValues({});
    final original = layout('a', 'JeyMTL', starred: true, interval: '15m');

    await ChartLayoutStore.save([original]);
    final loaded = await ChartLayoutStore.load();

    expect(loaded, hasLength(1));
    expect(loaded.first.name, 'JeyMTL');
    expect(loaded.first.symbol, 'EURUSD');
    expect(loaded.first.intervalKey, '15m');
    expect(loaded.first.starred, isTrue);
    // The palette comes back whole: a layout that lost its colours would be a
    // name and nothing else.
    expect(loaded.first.style.id, ChartStyle.slate.id);
    expect(loaded.first.style.bull, ChartStyle.slate.bull);
  });

  test('starred layouts list first, then the newest', () async {
    SharedPreferences.setMockInitialValues({});
    await ChartLayoutStore.save([
      layout('old', 'Old', minutesAgo: 60),
      layout('new', 'New'),
      layout('star', 'Star', starred: true, minutesAgo: 120),
    ]);

    final loaded = await ChartLayoutStore.load();
    expect(loaded.map((item) => item.id).toList(), ['star', 'new', 'old']);
  });

  test('a corrupt library reads as empty rather than crashing the chart', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{ChartLayoutStore.storageKey: 'not json at all'},
    );
    expect(await ChartLayoutStore.load(), isEmpty);
  });

  test('an unreadable entry is dropped and its neighbours are kept', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{
        ChartLayoutStore.storageKey:
            '[{"id":"a","name":"Kept","symbol":"XAUUSD","interval":"5m",'
                '"style":{"preset":"ink"},"savedAt":1763000000000},'
                '{"nope":true}]',
      },
    );
    final loaded = await ChartLayoutStore.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.name, 'Kept');
  });

  test('the subtitle reads like the spec: symbol, interval and a stamp', () {
    final entry = ChartLayout(
      id: 'a',
      name: 'JeyMTL',
      symbol: 'EURUSD',
      intervalKey: '1m',
      style: ChartStyle.slate,
      savedAt: DateTime(2026, 11, 20, 14, 46),
    );
    expect(entry.subtitle, 'EURUSD, 1m (20 Nov 2026, 14:46)');
  });
}
