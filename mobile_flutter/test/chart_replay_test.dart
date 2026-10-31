import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_replay.dart';

void main() {
  test('starts with roughly a third of the series left to step through', () {
    final cursor = ReplayCursor.start(count: 288);

    expect(cursor.index, 192);
    expect(cursor.visible, 193);
    expect(cursor.atStart, isFalse);
    expect(cursor.atEnd, isFalse);
  });

  test('steps forward to the last candle and stops there', () {
    var cursor = ReplayCursor(count: 5, index: 0);

    for (var i = 0; i < 10; i++) {
      cursor = cursor.next();
    }

    expect(cursor.index, 4);
    expect(cursor.visible, 5);
    expect(cursor.atEnd, isTrue);
    expect(cursor.next().index, 4, reason: 'the end holds, it never overflows');
  });

  test('steps back to the first candle and stops there', () {
    var cursor = ReplayCursor(count: 5, index: 2);

    for (var i = 0; i < 10; i++) {
      cursor = cursor.previous();
    }

    expect(cursor.index, 0);
    expect(cursor.visible, 1);
    expect(cursor.atStart, isTrue);
    expect(cursor.previous().index, 0);
  });

  test('handles a series with almost nothing in it', () {
    final single = ReplayCursor.start(count: 1);
    expect(single.visible, 1);
    expect(single.atEnd, isTrue);

    final empty = ReplayCursor.start(count: 0);
    expect(empty.visible, 0);
    expect(empty.atEnd, isTrue);
    expect(empty.atStart, isTrue);
  });

  test('never shows a candle that is not loaded', () {
    final cursor = ReplayCursor(count: 3, index: 0);
    expect(cursor.visible, 1);
    expect(cursor.next().next().next().visible, 3);
  });
}
