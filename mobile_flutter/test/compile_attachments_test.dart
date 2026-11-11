import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/compile_attachments.dart';

Uint8List bytes(int length) => Uint8List(length);

void main() {
  test('encodes an accepted screenshot as a data URL', () {
    final url = chartDataUrl('image/png', bytes(8));
    expect(url, startsWith('data:image/png;base64,'));
  });

  test('normalises image/jpg and rejects a format the model cannot read', () {
    expect(chartDataUrl('image/jpg', bytes(4)), startsWith('data:image/jpeg'));
    expect(chartDataUrl('image/heic', bytes(4)), isNull);
    expect(chartDataUrl('image/gif', bytes(4)), isNull);
  });

  test('refuses a fifth chart, an oversized one, or one past the shared budget', () {
    expect(
      chartRejection(
        count: maxCompileCharts,
        usedBytes: 100,
        candidateBytes: 100,
        mimeType: 'image/png',
      ),
      contains('Up to'),
    );
    expect(
      chartRejection(
        count: 1,
        usedBytes: 0,
        candidateBytes: maxCompileChartBytes + 1,
        mimeType: 'image/png',
      ),
      contains('4 MB'),
    );
    expect(
      chartRejection(
        count: 1,
        usedBytes: compileChartBudgetBytes - 10,
        candidateBytes: 100,
        mimeType: 'image/png',
      ),
      contains('too large'),
    );
  });

  test('a normal screenshot inside every limit is accepted', () {
    expect(
      chartRejection(
        count: 3,
        usedBytes: 500000,
        candidateBytes: 800000,
        mimeType: 'image/jpeg',
      ),
      isNull,
    );
  });

  test('audio is wrapped with its own mime type', () {
    expect(
      audioDataUrl('audio/mp4', bytes(4)),
      startsWith('data:audio/mp4;base64,'),
    );
  });
}
