import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mtl_trader_mobile/core/chart_drawings.dart';
import 'package:mtl_trader_mobile/services/chart_drawings_sync.dart';

/// The reconciliation is matched by signature rather than id, so the two things
/// that can silently break it are covered here: a signature that changes when an
/// object is merely saved and reloaded, and a row shape that does not survive the
/// trip between the phone's model and the table.
void main() {
  test('a rectangle keeps one signature across a save and reload', () {
    const drawing = ChartDrawing.points(
      kind: DrawingKind.rectangle,
      points: [
        ChartPoint(ms: 1762900000000, price: 1.25100),
        ChartPoint(ms: 1762900600000, price: 1.24700),
      ],
    );

    final reloaded = decodeDrawings(encodeDrawings([drawing])).single;

    expect(drawingSignature(reloaded), drawingSignature(drawing));
  });

  test('moving an object changes its signature', () {
    const drawing = ChartDrawing.ray(price: 1.25);
    final moved = ChartDrawing.ray(price: 1.2505);

    expect(drawingSignature(moved), isNot(drawingSignature(drawing)));
  });

  test('a horizontal level travels as a price and comes back unchanged', () {
    const drawing = ChartDrawing.ray(price: 1.08432);

    final points = ChartDrawingsSync.drawingToPoints(drawing);
    final back = ChartDrawingsSync.drawingFromRow({
      'id': 'abc',
      'kind': 'ray',
      'points': points,
      'text': null,
    });

    expect(back, isNotNull);
    expect(back!.kind, DrawingKind.ray);
    expect(back.price, closeTo(1.08432, 1e-9));
    expect(drawingSignature(back), drawingSignature(drawing));
  });

  test('a project without the style column is named, not guessed at', () {
    // The shapes PostgREST and Postgres actually produce for a missing column.
    expect(
      ChartDrawingsSync.isMissingStyleColumn(
        PostgrestException(
          message: 'column chart_drawings.style does not exist',
          code: '42703',
        ),
      ),
      isTrue,
    );
    expect(
      ChartDrawingsSync.isMissingStyleColumn(
        "Could not find the 'style' column of 'chart_drawings' in the schema cache",
      ),
      isTrue,
    );
    // Anything else is a real failure and must not be swallowed as one.
    expect(
      ChartDrawingsSync.isMissingStyleColumn('JWT expired'),
      isFalse,
    );
    expect(
      ChartDrawingsSync.isMissingStyleColumn(
        PostgrestException(message: 'relation does not exist', code: '42P01'),
      ),
      isFalse,
    );
  });

  test('a trend line travels as its two anchors', () {
    final drawing = ChartDrawing.trend(
      startMs: 1762900000000,
      startPrice: 1.25000,
      endMs: 1762903600000,
      endPrice: 1.25600,
    );

    final points = ChartDrawingsSync.drawingToPoints(drawing);
    expect(points.length, 2);
    expect(points.first['t'], 1762900000000);

    final back = ChartDrawingsSync.drawingFromRow({
      'id': 'abc',
      'kind': 'trend',
      'points': points,
      'text': null,
    });

    expect(back!.kind, DrawingKind.trend);
    expect(back.endPrice, closeTo(1.25600, 1e-9));
    expect(drawingSignature(back), drawingSignature(drawing));
  });

  test('a text label keeps its words when it comes back from the table', () {
    const drawing = ChartDrawing.points(
      kind: DrawingKind.text,
      text: 'NFP',
      points: [ChartPoint(ms: 1762900000000, price: 1.25)],
    );

    final back = ChartDrawingsSync.drawingFromRow({
      'id': 'abc',
      'kind': 'text',
      'points': ChartDrawingsSync.drawingToPoints(drawing),
      'text': 'NFP',
    });

    expect(back!.text, 'NFP');
    expect(drawingSignature(back), drawingSignature(drawing));
  });

  test('a row id is kept when the object is read back', () {
    final back = ChartDrawingsSync.drawingFromRow({
      'id': 'row-1',
      'kind': 'ray',
      'points': const [
        {'t': 0, 'p': 1.25100},
      ],
      'text': null,
    });

    expect(back!.id, 'row-1');
    expect(back.toJson()['id'], 'row-1');
  });

  test('an id survives a save and reload, so a move can update its row', () {
    const drawing = ChartDrawing.points(
      id: 'row-7',
      kind: DrawingKind.rectangle,
      points: [
        ChartPoint(ms: 1762900000000, price: 1.25100),
        ChartPoint(ms: 1762900600000, price: 1.24700),
      ],
    );

    final reloaded = decodeDrawings(encodeDrawings([drawing])).single;
    final moved = reloaded.translated(
      shiftTime: (ms) => ms + 60000,
      priceDelta: 0.0005,
    );

    expect(reloaded.id, 'row-7');
    expect(moved.id, 'row-7',
        reason: 'the drag must update that row, not create one');
    expect(drawingSignature(moved), isNot(drawingSignature(reloaded)));
  });

  test('the signature describes the content, not the row', () {
    const drawing = ChartDrawing.ray(price: 1.25100);
    const same = ChartDrawing.ray(price: 1.25100, id: 'row-1');

    expect(drawingSignature(same), drawingSignature(drawing));
  });

  test('the phone and the web desk agree on one symbol spelling', () {
    expect(ChartDrawingsSync.symbolForCloud('EURUSD'), 'EUR_USD');
    expect(ChartDrawingsSync.symbolForCloud(' eurusd '), 'EUR_USD');
    expect(ChartDrawingsSync.symbolForCloud('XAUUSD'), 'XAU_USD');
    expect(ChartDrawingsSync.symbolForCloud('EUR_USD'), 'EUR_USD');
    // Indices keep the short names both halves of the product already use.
    expect(ChartDrawingsSync.symbolForCloud('US30'), 'US30');
    expect(ChartDrawingsSync.symbolForCloud('NAS100'), 'NAS100');
  });

  test('the later edit wins even when it syncs second', () {
    // The phone edited at 10:00, the web desk moved the same level at 11:00 and
    // the phone only came online at midnight.
    expect(
      localEditWins(
        localMs: 1000,
        localSignature: 'b',
        remoteMs: 2000,
        remoteSignature: 'a',
      ),
      isFalse,
    );
    expect(
      localEditWins(
        localMs: 2000,
        localSignature: 'a',
        remoteMs: 1000,
        remoteSignature: 'b',
      ),
      isTrue,
    );
  });

  test(
      'two versions with the same timestamp pick the same winner on both sides',
      () {
    final first = localEditWins(
      localMs: 5,
      localSignature: 'ray|1.2500000',
      remoteMs: 5,
      remoteSignature: 'ray|1.2400000',
    );
    final second = localEditWins(
      localMs: 5,
      localSignature: 'ray|1.2400000',
      remoteMs: 5,
      remoteSignature: 'ray|1.2500000',
    );

    // Whichever side asks, both agree the same version stands — otherwise the
    // row would be overwritten on every sync, in both directions.
    expect(first, isNot(second));
  });

  test('an edit time survives a save and a move', () {
    const drawing = ChartDrawing.points(
      id: 'row-1',
      editedAtMs: 1762900000000,
      kind: DrawingKind.rectangle,
      points: [
        ChartPoint(ms: 1762900000000, price: 1.25100),
        ChartPoint(ms: 1762900600000, price: 1.24700),
      ],
    );

    final reloaded = decodeDrawings(encodeDrawings([drawing])).single;
    final moved = reloaded.translated(
      shiftTime: (ms) => ms + 60000,
      priceDelta: 0.0005,
    );
    final stamped = moved.withEditedAt(1762900900000);

    expect(reloaded.editedAtMs, 1762900000000);
    expect(moved.editedAtMs, 1762900000000);
    expect(stamped.editedAtMs, 1762900900000);
    expect(stamped.id, 'row-1');
  });

  test('a row carries the edit time the phone compares against', () {
    final back = ChartDrawingsSync.drawingFromRow({
      'id': 'row-1',
      'kind': 'ray',
      'points': const [
        {'t': 0, 'p': 1.25100},
      ],
      'text': null,
      'edited_at': '2026-11-20T10:15:00.000Z',
    });

    expect(
      back!.editedAtMs,
      DateTime.utc(2026, 11, 20, 10, 15).millisecondsSinceEpoch,
    );
  });

  test('a position tool stays on the device', () {
    final drawing = ChartDrawing.position(
      side: PositionSide.long,
      startMs: 1762900000000,
      entry: 1.25000,
      stop: 1.24800,
      target: 1.25400,
    );

    expect(ChartDrawingsSync.drawingToPoints(drawing), isEmpty);
    expect(
      ChartDrawingsSync.drawingFromRow({
        'id': 'abc',
        'kind': 'position',
        'points': const [],
        'text': null,
      }),
      isNull,
    );
  });
}
